import statistics
from collections import Counter
from pathlib import Path

# ==============================================================================
# CẤU HÌNH ĐƯỜNG DẪN & THAM SỐ (CONSTANTS)
# ==============================================================================
REPO_ROOT = Path(__file__).resolve().parents[2]
RAW_DATASET_PATH = REPO_ROOT / "data" / "application" / "human.txt"
PREPROCESSED_DATASET_PATH = REPO_ROOT / "data" / "application" / "human_preprocessed.txt"

MIN_SEQ_LEN = 50
MAX_SEQ_LEN = 10000
K_MER_SIZE = 6
VALID_BASES = {"A", "T", "C", "G"}

CLASS_NAMES = {
    "0": "G protein-coupled receptors (GPCRs)",
    "1": "Tyrosine kinase",
    "2": "Tyrosine phosphatase",
    "3": "Synthetase",
    "4": "Synthase",
    "5": "Ion channel",
    "6": "Transcription factor",
}


# ==============================================================================
# 1. HÀM TIỀN XỬ LÝ DỮ LIỆU
# ==============================================================================
def preprocess_dna_dataset(
    raw_path: Path,
    min_len: int = MIN_SEQ_LEN,
    max_len: int = MAX_SEQ_LEN,
    k: int = K_MER_SIZE,
) -> tuple[list[tuple[str, str]], dict[str, int]]:
    """
    Thực hiện 4 bước tiền xử lý:
    1. Chuẩn hóa chữ hoa và loại bỏ khoảng trắng.
    2. Lọc bỏ các trình tự quá ngắn (< min_len) hoặc quá dài (> max_len).
    3. Kiểm tra tính hợp lệ của chuỗi nucleotide (phải sinh được ít nhất 1 k-mer chuẩn A/T/C/G).
    4. Khử trùng lặp trình tự gốc (Sequence Deduplication) để tránh thổi phồng support.
    """
    stats_log = {
        "raw_total": 0,
        "dropped_invalid_format": 0,
        "dropped_length_outlier": 0,
        "dropped_no_valid_kmer": 0,
        "dropped_duplicate_seq": 0,
        "clean_total": 0,
    }

    seen_sequences = set()
    clean_records = []

    with raw_path.open("r", encoding="utf-8") as f:
        next(f, None)  # Bỏ qua dòng tiêu đề (sequence \t class)
        for line in f:
            line = line.strip()
            if not line:
                continue
            stats_log["raw_total"] += 1

            parts = line.split("\t")
            if len(parts) < 2:
                stats_log["dropped_invalid_format"] += 1
                continue

            seq = parts[0].strip().upper()
            cls = parts[1].strip()

            # Lọc ngoại lai chiều dài
            if not (min_len <= len(seq) <= max_len):
                stats_log["dropped_length_outlier"] += 1
                continue

            # Kiểm tra có tồn tại ít nhất 1 k-mer hợp lệ hay không
            has_valid_kmer = any(
                set(seq[i : i + k]).issubset(VALID_BASES)
                for i in range(len(seq) - k + 1)
            )
            if not has_valid_kmer:
                stats_log["dropped_no_valid_kmer"] += 1
                continue

            # Khử trùng lặp trình tự hoàn toàn giống nhau
            if seq in seen_sequences:
                stats_log["dropped_duplicate_seq"] += 1
                continue

            seen_sequences.add(seq)
            clean_records.append((seq, cls))

    stats_log["clean_total"] = len(clean_records)
    return clean_records, stats_log


# ==============================================================================
# 2. HÀM THỐNG KÊ MÔ TẢ TRƯỚC KHI CHẠY (PRE-MINING EDA)
# ==============================================================================
def extract_descriptive_stats(
    records: list[tuple[str, str]],
    filter_log: dict[str, int],
    k: int = K_MER_SIZE,
) -> None:
    """Tính và in toàn bộ chỉ số thống kê mô tả của tập dữ liệu và ma trận giao dịch."""
    total_seqs = len(records)
    lengths = [len(seq) for seq, _ in records]
    class_counts = Counter(cls for _, cls in records)

    # Mô phỏng trích xuất transaction k-mer để đo độ dày ma trận
    vocab_kmers = set()
    tx_lengths = []
    for seq, _ in records:
        kmers = {
            seq[i : i + k]
            for i in range(len(seq) - k + 1)
            if set(seq[i : i + k]).issubset(VALID_BASES)
        }
        vocab_kmers.update(kmers)
        tx_lengths.append(len(kmers))

    num_distinct_items = len(vocab_kmers) + len(class_counts)
    avg_tx_len = statistics.mean(tx_lengths)
    matrix_density = (avg_tx_len / num_distinct_items) * 100

    print("=" * 70)
    print("BÁO CÁO TIỀN XỬ LÝ & THỐNG KÊ MÔ TẢ TRƯỚC KHI CHẠY CHARM")
    print("=" * 70)

    print("\n[1] TỔNG HỢP QUÁ TRÌNH LÀM SẠCH DỮ LIỆU")
    print(f"  - Tổng số bản ghi thô ban đầu     : {filter_log['raw_total']:,}")
    print(f"  - Loại do sai định dạng dòng      : -{filter_log['dropped_invalid_format']:,}")
    print(f"  - Loại do ngoại lai độ dài        : -{filter_log['dropped_length_outlier']:,} (ngoài khoảng [{MIN_SEQ_LEN}, {MAX_SEQ_LEN}] bp)")
    print(f"  - Loại do thiếu {k}-mer hợp lệ      : -{filter_log['dropped_no_valid_kmer']:,}")
    print(f"  - Loại do trùng lặp trình tự gốc  : -{filter_log['dropped_duplicate_seq']:,}")
    print(f"  => Số trình tự sạch giữ lại (|D|) : {total_seqs:,}")

    print("\n[2] PHÂN BỐ CHIỀU DÀI TRÌNH TỰ NUCLEOTIDE (bp)")
    print(f"  - Ngắn nhất (Min)    : {min(lengths):,} bp")
    print(f"  - Trung vị (Median)  : {statistics.median(lengths):,.1f} bp")
    print(f"  - Trung bình (Mean)  : {statistics.mean(lengths):,.1f} bp (SD = {statistics.stdev(lengths):,.1f})")
    print(f"  - Dài nhất (Max)     : {max(lengths):,} bp")

    print("\n[3] PHÂN BỐ 7 HỌ PROTEIN (CLASS DISTRIBUTION)")
    for cls in sorted(class_counts.keys()):
        cnt = class_counts[cls]
        pct = (cnt / total_seqs) * 100
        name = CLASS_NAMES.get(cls, "Unknown")
        print(f"  - CLASS_{cls} ({name:35s}): {cnt:4d} chuỗi ({pct:5.2f}%)")

    print(f"\n[4] ĐẶC TRƯNG MA TRẬN GIAO DỊCH (VỚI k = {k})")
    print(f"  - Số lượng giao dịch (|D|)            : {total_seqs:,}")
    print(f"  - Số lượng {k}-mer phân biệt          : {len(vocab_kmers):,} / {4**k:,} tổ hợp lý thuyết")
    print(f"  - Tổng kích thước tập item (|I|)      : {num_distinct_items:,} (gồm cả {len(class_counts)} nhãn lớp)")
    print(f"  - Độ dài giao dịch trung bình (T̄)     : {avg_tx_len:,.1f} items/gene (Median = {statistics.median(tx_lengths):,.1f})")
    print(f"  - Mật độ ma trận (Density = T̄ / |I|)  : {matrix_density:.2f}%")
    print("=" * 70)


# ==============================================================================
# 3. HÀM XUẤT FILE ĐÃ TIỀN XỬ LÝ
# ==============================================================================
def save_preprocessed_dataset(records: list[tuple[str, str]], output_path: Path) -> None:
    """Lưu dữ liệu sạch ra file TSV giữ nguyên cấu trúc sequence \t class."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        f.write("sequence\tclass\n")
        for seq, cls in records:
            f.write(f"{seq}\t{cls}\n")
    print(f"\nĐã lưu tập dữ liệu sạch tại: {output_path}")


def main():
    clean_records, filter_log = preprocess_dna_dataset(RAW_DATASET_PATH)
    extract_descriptive_stats(clean_records, filter_log, k=K_MER_SIZE)
    save_preprocessed_dataset(clean_records, PREPROCESSED_DATASET_PATH)


if __name__ == "__main__":
    main()