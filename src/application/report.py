import csv
import math
from collections import defaultdict
from pathlib import Path

# ==============================================================================
# CẤU HÌNH ĐƯỜNG DẪN & THAM SỐ 
# ==============================================================================
REPO_ROOT = Path(__file__).resolve().parents[2]
DATASET_PATH = REPO_ROOT / "data" / "application" / "promoters.data"
CHARM_OUTPUT_PATH = REPO_ROOT / "output" / "promoters_charm_output.txt"
OUT_DIR = REPO_ROOT / "output" / "promoter_analysis"

# Chỉ số 1-based từ Julia quy đổi sang slice 0-based của Python [start-1 : end]
CLUSTER_SLICES = {
    "C1": (2, 23),   # Julia 3:23  (p-48 .. p-28)
    "C2": (26, 34),  # Julia 27:34 (p-24 .. p-17)
    "C3": (34, 52),  # Julia 35:52 (p-16 .. p1)
}
VALID_BASES = {"a", "c", "g", "t"}

# Ngưỡng lọc thống kê cho Contrast Pattern Mining
MIN_CONFIDENCE = 0.85
MIN_GROWTH_RATE = 3.0
MAX_P_VALUE = 0.05


# ==============================================================================
# 1. ĐỌC DỮ LIỆU GỐC & OUTPUT TỪ CHARM
# ==============================================================================
def load_promoters(dataset_path: Path) -> list[dict]:
    records = []
    with dataset_path.open("r", encoding="utf-8") as f:
        for line in f:
            fields = [x.strip() for x in line.strip().split(",")]
            if len(fields) < 3:
                continue
            cls = fields[0]
            seq = "".join(ch for ch in "".join(fields[2:]).lower() if not ch.isspace())
            if cls in ("+", "-") and len(seq) == 57 and set(seq).issubset(VALID_BASES):
                records.append({"class": cls, "name": fields[1], "seq": seq})
    return records


def parse_charm_output(charm_path: Path) -> list[tuple[list[str], int]]:
    patterns = []
    with charm_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or "#SUP:" not in line:
                continue
            items_part, sup_part = line.split("#SUP:")
            items = sorted(items_part.strip().split())
            patterns.append((items, int(sup_part.strip())))
    return patterns


# ==============================================================================
# 2. CÁC HÀM THỐNG KÊ CÓ GIÁM SÁT, GHÉP CHUỖI & ĐO KHOẢNG CÁCH
# ==============================================================================
def chi2_2x2(sup_pos: int, n_pos: int, sup_neg: int, n_neg: int) -> tuple[float, float]:
    """Kiểm định Chi-square (df = 1) cho bảng chéo 2x2 giữa sự xuất hiện của tổ hợp và nhãn lớp."""
    total = n_pos + n_neg
    row1 = sup_pos + sup_neg
    row2 = total - row1
    if row1 == 0 or row2 == 0:
        return 0.0, 1.0

    # Công thức giải tích chính xác cho bảng 2x2
    num = total * ((sup_pos * (n_neg - sup_neg) - sup_neg * (n_pos - sup_pos)) ** 2)
    den = row1 * row2 * n_pos * n_neg
    chi2 = num / den if den > 0 else 0.0
    p_val = math.erfc(math.sqrt(chi2 / 2.0))
    return round(chi2, 4), p_val


def assemble_cluster_contigs(motif_items: list[str]) -> tuple[str, list[str]]:
    """
    Gom nhóm các k-mer theo từng cụm (C1, C2, C3) và ghép nối (greedy overlap)
    các đoạn gối đầu nhau để khôi phục chuỗi đồng thuận hoàn chỉnh.
    """
    by_cluster = defaultdict(list)
    for it in motif_items:
        c_name, kmer = it.split("_", 1)
        by_cluster[c_name].append(kmer)

    assembled_parts = []
    for c_name in sorted(by_cluster.keys()):
        contigs = sorted(set(by_cluster[c_name]))
        merged = True
        while merged and len(contigs) > 1:
            merged = False
            best_ov, best_pair, best_str = 0, None, ""
            for i in range(len(contigs)):
                for j in range(len(contigs)):
                    if i == j:
                        continue
                    a, b = contigs[i], contigs[j]
                    if b in a:
                        best_pair, best_str, best_ov = (i, j), a, len(b)
                        break
                    for ov in range(min(len(a), len(b)) - 1, 0, -1):
                        if a.endswith(b[:ov]) and ov > best_ov:
                            best_ov, best_pair, best_str = ov, (i, j), a + b[ov:]
                            break
                if best_pair and contigs[best_pair[1]] in contigs[best_pair[0]]:
                    break
            if best_pair is not None:
                i, j = best_pair
                contigs = sorted(set(
                    [contigs[idx] for idx in range(len(contigs)) if idx not in (i, j)] + [best_str]
                ))
                merged = True

        for c in contigs:
            assembled_parts.append(f"{c_name}:{c}")

    return " + ".join(assembled_parts), sorted(by_cluster.keys())


def evaluate_itemset_on_data(motif_items: list[str], records: list[dict]) -> tuple[int, int, float]:
    """
    Quét tổ hợp motif trên toàn bộ dữ liệu để đếm sup(+), sup(-) và đo khoảng cách
    tọa độ trung bình (mean_span_bp) trên các chuỗi thuộc lớp Promoter (+).
    """
    pos_spans = []
    neg_hits = 0

    for rec in records:
        seq = rec["seq"]
        positions = []
        matched = True

        for it in motif_items:
            c_name, kmer = it.split("_", 1)
            start, end = CLUSTER_SLICES[c_name]
            idx = seq.find(kmer, start, end)
            if idx == -1:
                matched = False
                break
            positions.append(idx)

        if matched:
            if rec["class"] == "+":
                span = (max(positions) - min(positions)) if len(positions) > 1 else 0
                pos_spans.append(span)
            else:
                neg_hits += 1

    sup_pos = len(pos_spans)
    mean_span = round(sum(pos_spans) / sup_pos, 1) if sup_pos > 0 else 0.0
    return sup_pos, neg_hits, mean_span


# ==============================================================================
# 3. CHẠY PIPELINE PHÂN TÍCH & XUẤT BÁO CÁO
# ==============================================================================
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    records = load_promoters(DATASET_PATH)
    raw_patterns = parse_charm_output(CHARM_OUTPUT_PATH)

    n_pos = sum(1 for r in records if r["class"] == "+")
    n_neg = sum(1 for r in records if r["class"] == "-")
    p_pos_baseline = n_pos / (n_pos + n_neg)

    all_rows = []
    seen_motifs = set()

    for items, _ in raw_patterns:
        motif_items = tuple(sorted(it for it in items if not it.startswith("class=")))
        if not motif_items or motif_items in seen_motifs:
            continue
        seen_motifs.add(motif_items)

        sup_pos, sup_neg, mean_span = evaluate_itemset_on_data(list(motif_items), records)
        total_sup = sup_pos + sup_neg
        if total_sup == 0:
            continue

        confidence = sup_pos / total_sup
        lift = confidence / p_pos_baseline
        growth_rate = round(sup_pos / sup_neg, 2) if sup_neg > 0 else float("inf")
        chi2_stat, p_val = chi2_2x2(sup_pos, n_pos, sup_neg, n_neg)

        consensus_str, clusters_involved = assemble_cluster_contigs(list(motif_items))
        is_cross_cluster = len(clusters_involved) > 1
        dna_concat = "".join(it.split("_", 1)[1] for it in motif_items)
        at_pct = round(100.0 * (dna_concat.count("a") + dna_concat.count("t")) / len(dna_concat), 1)

        is_discriminative = (
            confidence >= MIN_CONFIDENCE
            and growth_rate >= MIN_GROWTH_RATE
            and p_val < MAX_P_VALUE
        )

        all_rows.append({
            "consensus_motifs": consensus_str,
            "raw_items": " ".join(motif_items),
            "num_items": len(motif_items),
            "clusters_involved": "+".join(clusters_involved),
            "pattern_scope": "Cross_Cluster" if is_cross_cluster else "Intra_Cluster",
            "sup_pos": sup_pos,
            "sup_neg": sup_neg,
            "confidence_pos": round(confidence, 4),
            "lift_pos": round(lift, 3),
            "growth_rate": "Inf" if math.isinf(growth_rate) else growth_rate,
            "chi2_stat": chi2_stat,
            "p_value": round(p_val, 6),
            "mean_span_bp": mean_span,
            "at_content_pct": at_pct,
            "discriminative_pass": "YES" if is_discriminative else "NO",
        })

    # Sắp xếp ưu tiên các mẫu đạt chuẩn thống kê, Lift cao và tổ hợp nhiều item
    all_rows.sort(
        key=lambda r: (
            r["discriminative_pass"] == "YES",
            r["lift_pos"],
            r["num_items"],
            r["sup_pos"],
        ),
        reverse=True,
    )

    disc_rows = [r for r in all_rows if r["discriminative_pass"] == "YES"]

    all_csv = OUT_DIR / "all_closed_motifs.csv"
    disc_csv = OUT_DIR / "discriminative_promoters.csv"

    for path, rows in [(all_csv, all_rows), (disc_csv, disc_rows)]:
        if rows:
            with path.open("w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
                writer.writeheader()
                writer.writerows(rows)

    print("=== TỔNG HỢP TRI THỨC TỪ TẬP ĐÓNG TƯƠNG PHẢN ===")
    print(f"Tổng số tổ hợp motif duy nhất đánh giá : {len(all_rows)}")
    print(f"Số mẫu đạt chuẩn phân biệt (Conf>={MIN_CONFIDENCE}, GR>={MIN_GROWTH_RATE}, p<{MAX_P_VALUE}): {len(disc_rows)}\n")

    print("--- 1. TOP CHUỖI ĐỒNG THUẬN (CONSENSUS ASSEMBLY) ĐẶC TRƯNG CHO PROMOTER (+) ---")
    for r in disc_rows[:12]:
        print(
            f"[{r['pattern_scope']:13s}] Sup(+/-)={r['sup_pos']:2d}/{r['sup_neg']:2d} | "
            f"Conf={r['confidence_pos']:.2f} | Lift={r['lift_pos']:.2f}x | GR={str(r['growth_rate']):<4s} | "
            f"p={r['p_value']:.4f} | AT={r['at_content_pct']:4.1f}% | {r['consensus_motifs']}"
        )

    cross_rows = [r for r in disc_rows if r["pattern_scope"] == "Cross_Cluster"]
    print(f"\n--- 2. QUY LUẬT RÀNG BUỘC KHOẢNG CÁCH XUYÊN CỤM ({len(cross_rows)} MẪU) ---")
    if cross_rows:
        for r in cross_rows[:10]:
            print(
                f"[{r['clusters_involved']:8s}] Sup(+/-)={r['sup_pos']:2d}/{r['sup_neg']:2d} | "
                f"Mean Span = {r['mean_span_bp']:4.1f} bp | Motifs: {r['consensus_motifs']}"
            )
    else:
        print("  (Không có tổ hợp xuyên cụm vượt ngưỡng minsup=5 do biến thể điểm; "
              "xem thêm các mẫu xuyên cụm ở file all_closed_motifs.csv)")

    print(f"\nĐã xuất toàn bộ kết quả tại:\n  - {disc_csv}\n  - {all_csv}")


if __name__ == "__main__":
    main()