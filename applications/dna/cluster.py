import csv
import math
from collections import Counter
from pathlib import Path

# ==============================================================================
# CẤU HÌNH ĐƯỜNG DẪN & THAM SỐ THỐNG KÊ
# ==============================================================================
REPO_ROOT = Path(__file__).resolve().parents[2]
DATASET_PATH = REPO_ROOT / "data" / "applications" / "dna" / "promoters.data"
OUT_DIR = REPO_ROOT / "results" / "app2" / "promoter_analysis"

SEQ_LEN = 57
VALID_BASES = ("a", "c", "g", "t")
ALPHA = 0.05          # Ngưỡng ý nghĩa thống kê p-value
CLUSTER_GAP = 4       # Khoảng cách tối đa (bp) để gộp các điểm nóng thành 1 cụm
WINDOW_PADDING = 3    # Nới rộng biên mỗi cụm ±3 bp để bù trừ sai số xê dịch


# ==============================================================================
# 1. ĐỌC DỮ LIỆU & TÍNH CHỈ SỐ THỐNG KÊ TỪNG TỌA ĐỘ
# ==============================================================================
def load_sequences(dataset_path: Path) -> tuple[list[str], list[str]]:
    pos_seqs, neg_seqs = [], []
    with dataset_path.open("r", encoding="utf-8") as f:
        for line in f:
            fields = [x.strip() for x in line.strip().split(",")]
            if len(fields) < 3:
                continue
            cls = fields[0]
            seq = "".join(ch for ch in "".join(fields[2:]).lower() if not ch.isspace())
            if len(seq) == SEQ_LEN and set(seq).issubset(VALID_BASES):
                if cls == "+":
                    pos_seqs.append(seq)
                elif cls == "-":
                    neg_seqs.append(seq)
    return pos_seqs, neg_seqs


def shannon_ic(counts: Counter, total: int) -> float:
    """Tính Information Content IC(j) = 2 - H(j) (đơn vị: bits, tối đa = 2.0)."""
    if total == 0:
        return 0.0
    entropy = 0.0
    for b in VALID_BASES:
        p = counts[b] / total
        if p > 0:
            entropy -= p * math.log2(p)
    return round(2.0 - entropy, 4)


def chi2_test_df3(pos_counts: Counter, n_pos: int, neg_counts: Counter, n_neg: int) -> tuple[float, float]:
    """
    Kiểm định Chi-square (df = 3) so sánh phân bố 4 base (a, c, g, t) giữa 2 lớp.
    Với df = 3, hàm phân phối tích lũy có dạng giải tích chính xác:
    P(X >= x) = erfc(sqrt(x/2)) + sqrt(2*x / pi) * exp(-x/2).
    """
    total = n_pos + n_neg
    chi2 = 0.0
    for b in VALID_BASES:
        col_total = pos_counts[b] + neg_counts[b]
        if col_total == 0:
            continue
        exp_pos = n_pos * col_total / total
        exp_neg = n_neg * col_total / total
        chi2 += ((pos_counts[b] - exp_pos) ** 2) / exp_pos
        chi2 += ((neg_counts[b] - exp_neg) ** 2) / exp_neg

    p_val = math.erfc(math.sqrt(chi2 / 2.0)) + math.sqrt(2.0 * chi2 / math.pi) * math.exp(-chi2 / 2.0)
    return round(chi2, 4), p_val


# ==============================================================================
# 2. GOM CỤM ĐIỂM NÓNG TỰ ĐỘNG (DATA-DRIVEN CLUSTERING)
# ==============================================================================
def discover_hotspot_clusters(hot_indices_1based: list[int]) -> list[tuple[str, int, int]]:
    """
    Gom các chỉ số tọa độ có p < 0.05 nằm gần nhau thành cụm và nới rộng biên ±WINDOW_PADDING.
    Trả về danh sách (tên_cụm, start_1based, end_1based) để dùng trực tiếp trong Julia.
    """
    if not hot_indices_1based:
        return []

    raw_clusters = [[hot_indices_1based[0]]]
    for idx in hot_indices_1based[1:]:
        if idx - raw_clusters[-1][-1] <= CLUSTER_GAP:
            raw_clusters[-1].append(idx)
        else:
            raw_clusters.append([idx])

    padded_clusters = []
    for c_id, group in enumerate(raw_clusters, 1):
        start_idx = max(1, group[0] - WINDOW_PADDING)
        end_idx = min(SEQ_LEN, group[-1] + WINDOW_PADDING)
        padded_clusters.append((f"C{c_id}", start_idx, end_idx))
    return padded_clusters


# ==============================================================================
# 3. CHẠY PIPELINE & XUẤT KẾT QUẢ
# ==============================================================================
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    pos_seqs, neg_seqs = load_sequences(DATASET_PATH)
    n_pos, n_neg = len(pos_seqs), len(neg_seqs)

    print("=== HỒ SƠ HÓA THỐNG KÊ TỌA ĐỘ (DATA-DRIVEN PROFILING) ===")
    print(f"Dữ liệu hợp lệ: {n_pos + n_neg} chuỗi (class=+ : {n_pos} | class=- : {n_neg} | độ dài = {SEQ_LEN} bp)\n")

    profile_rows = []
    hot_indices = []

    for idx0 in range(SEQ_LEN):
        idx1 = idx0 + 1          # Chỉ số 1-based cho Julia (1..57)
        bio_pos = idx0 - 50      # Tọa độ sinh học (p-50..p7, lưu ý: offset 50 là p0 theo quy ước file)
        pos_label = f"p{bio_pos}"

        pos_cnt = Counter(s[idx0] for s in pos_seqs)
        neg_cnt = Counter(s[idx0] for s in neg_seqs)

        ic_pos = shannon_ic(pos_cnt, n_pos)
        ic_neg = shannon_ic(neg_cnt, n_neg)
        chi2_stat, p_val = chi2_test_df3(pos_cnt, n_pos, neg_cnt, n_neg)

        dom_base_pos, dom_cnt_pos = pos_cnt.most_common(1)[0]
        dom_pct_pos = round(100.0 * dom_cnt_pos / n_pos, 1)
        is_sig = p_val < ALPHA
        if is_sig:
            hot_indices.append(idx1)

        profile_rows.append({
            "julia_idx": idx1,
            "bio_pos": pos_label,
            "ic_pos_bits": ic_pos,
            "ic_neg_bits": ic_neg,
            "dom_base_pos": f"{dom_base_pos} ({dom_pct_pos}%)",
            "chi2_stat": chi2_stat,
            "p_value": round(p_val, 6),
            "significant": "YES" if is_sig else "NO",
        })

    # Lưu toàn bộ 57 tọa độ ra CSV
    csv_path = OUT_DIR / "coordinate_profiling.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(profile_rows[0].keys()))
        writer.writeheader()
        writer.writerows(profile_rows)

    # In các điểm nóng thống kê ra terminal
    print(f"--- CÁC TỌA ĐỘ 'ĐIỂM NÓNG' CÓ Ý NGHĨA THỐNG KÊ (p-value < {ALPHA}) ---")
    print(f"{'JuliaIdx':<8} | {'BioPos':<7} | {'IC(+) bits':<10} | {'Base trội (+)':<13} | {'Chi2':<8} | {'p-value'}")
    print("-" * 68)
    for r in profile_rows:
        if r["significant"] == "YES":
            print(
                f"{r['julia_idx']:<8d} | {r['bio_pos']:<7s} | {r['ic_pos_bits']:<10.4f} | "
                f"{r['dom_base_pos']:<13s} | {r['chi2_stat']:<8.4f} | {r['p_value']:.6f}"
            )

    # Tự động phân cụm vùng dữ liệu
    clusters = discover_hotspot_clusters(hot_indices)
    print("\n--- KẾT QUẢ TỰ ĐỘNG PHÂN VÙNG CỤM (ĐÃ NỚI BIÊN ±3 BP) ---")
    for name, s_idx, e_idx in clusters:
        print(f"  {name}: Julia index {s_idx}:{e_idx}  (tương ứng p{s_idx - 51} đến p{e_idx - 51})")

    julia_const_str = ", ".join(f'("{name}", {s}:{e})' for name, s, e in clusters)
    print("\n>>> Copy dòng hằng số dưới đây sang applications/dna/run_dna.jl:")
    print(f"const CLUSTER_RANGES = [{julia_const_str}]")
    print(f"\nĐã lưu bảng thống kê đầy đủ 57 vị trí tại: {csv_path}")


if __name__ == "__main__":
    main()