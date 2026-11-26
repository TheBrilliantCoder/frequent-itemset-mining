import csv
from collections import Counter
from pathlib import Path

# ==============================================================================
# CẤU HÌNH ĐƯỜNG DẪN (CONSTANTS)
# ==============================================================================
REPO_ROOT = Path(__file__).resolve().parents[2]
DATASET_PATH = REPO_ROOT / "data" / "applications" / "dna" / "human_preprocessed.txt"
RESULTS_DIR = REPO_ROOT / "results" / "app2"
CHARM_OUTPUT_PATH = RESULTS_DIR / "global_closed_itemsets_k6.txt"
ANALYSIS_DIR = RESULTS_DIR / "bio_analysis"

CLASS_NAMES = {
    "CLASS_0": "G protein-coupled receptors (GPCRs)",
    "CLASS_1": "Tyrosine kinase",
    "CLASS_2": "Tyrosine phosphatase",
    "CLASS_3": "Synthetase",
    "CLASS_4": "Synthase",
    "CLASS_5": "Ion channel",
    "CLASS_6": "Transcription factor",
}

CODON_TABLE = {
    "TTT": "F", "TTC": "F", "TTA": "L", "TTG": "L",
    "TCT": "S", "TCC": "S", "TCA": "S", "TCG": "S",
    "TAT": "Y", "TAC": "Y", "TAA": "*", "TAG": "*",
    "TGT": "C", "TGC": "C", "TGA": "*", "TGG": "W",
    "CTT": "L", "CTC": "L", "CTA": "L", "CTG": "L",
    "CCT": "P", "CCC": "P", "CCA": "P", "CCG": "P",
    "CAT": "H", "CAC": "H", "CAA": "Q", "CAG": "Q",
    "CGT": "R", "CGC": "R", "CGA": "R", "CGG": "R",
    "ATT": "I", "ATC": "I", "ATA": "I", "ATG": "M",
    "ACT": "T", "ACC": "T", "ACA": "T", "ACG": "T",
    "AAT": "N", "AAC": "N", "AAA": "K", "AAG": "K",
    "AGT": "S", "AGC": "S", "AGA": "R", "AGG": "R",
    "GTT": "V", "GTC": "V", "GTA": "V", "GTG": "V",
    "GCT": "A", "GCC": "A", "GCA": "A", "GCG": "A",
    "GAT": "D", "GAC": "D", "GAA": "E", "GAG": "E",
    "GGT": "G", "GGC": "G", "GGA": "G", "GGG": "G",
}

HYDROPHOBIC_AA = {"A", "V", "I", "L", "M", "F", "Y", "W"}


# ==============================================================================
# CÁC HÀM PHÂN TÍCH SINH HỌC & THỐNG KÊ
# ==============================================================================
def load_dataset(dataset_path: Path):
    """Đọc human_preprocessed.txt và tính phân bố gốc của 7 họ protein."""
    records = []
    class_counts = Counter()

    with dataset_path.open("r", encoding="utf-8") as f:
        header = next(f, None)
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) < 2:
                continue
            seq = parts[0].strip().upper()
            cls = f"CLASS_{parts[1].strip()}"
            records.append((seq, cls))
            class_counts[cls] += 1

    total = len(records)
    class_probs = {cls: count / total for cls, count in class_counts.items()}
    return records, class_counts, class_probs


def parse_charm_output(charm_path: Path):
    """Đọc file kết quả CHARM toàn cục (chuẩn SPMF)."""
    closed_sets = []
    with charm_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or "#SUP:" not in line:
                continue
            items_part, sup_part = line.split("#SUP:")
            items = frozenset(items_part.strip().split())
            sup = int(sup_part.strip())
            closed_sets.append((items, sup))
    return closed_sets


def get_motif_support(motif_set: frozenset, closed_sets: list) -> int:
    """
    Tính chính xác support(M) từ tập các Closed Itemsets:
    Theo tính chất bao đóng, sup(M) = max{ sup(C) | C là closed itemset và M ⊆ C }.
    """
    matching_sups = [sup for items, sup in closed_sets if motif_set.issubset(items)]
    return max(matching_sups) if matching_sups else 0


def assemble_contigs(kmers: list[str]) -> list[str]:
    """
    Ghép nối (greedy overlap assembly) các k-mer gối đầu nhau thành chuỗi dài hơn.
    Ví dụ: ['ATGGTGCT', 'TGGTGCTG'] -> ['ATGGTGCTG']
    """
    if not kmers:
        return []
    contigs = sorted(set(kmers))
    merged = True
    while merged and len(contigs) > 1:
        merged = False
        best_ov = 0
        best_pair = None
        best_str = ""

        for i in range(len(contigs)):
            for j in range(len(contigs)):
                if i == j:
                    continue
                a, b = contigs[i], contigs[j]
                if b in a:
                    best_pair = (i, j)
                    best_str = a
                    best_ov = len(b)
                    break
                max_possible = min(len(a), len(b)) - 1
                for ov in range(max_possible, 0, -1):
                    if a.endswith(b[:ov]) and ov > best_ov:
                        best_ov = ov
                        best_pair = (i, j)
                        best_str = a + b[ov:]
                        break
            if best_pair and contigs[best_pair[1]] in contigs[best_pair[0]]:
                break

        if best_pair is not None:
            i, j = best_pair
            new_contigs = [
                contigs[idx] for idx in range(len(contigs)) if idx not in (i, j)
            ]
            new_contigs.append(best_str)
            contigs = sorted(set(new_contigs))
            merged = True

    return contigs


def compute_mean_span_bp(kmers: list[str], records: list[tuple[str, str]], target_cls: str = None) -> float:
    """
    Tính khoảng cách trung bình (bp) từ k-mer đầu đến k-mer cuối trên các chuỗi
    thực tế chứa đồng thời toàn bộ tập k-mer.
    """
    if len(kmers) < 2:
        return 0.0

    spans = []
    for seq, cls in records:
        if target_cls and cls != target_cls:
            continue
        positions = [seq.find(k) for k in kmers]
        if all(p != -1 for p in positions):
            spans.append(max(positions) - min(positions))

    return round(sum(spans) / len(spans), 1) if spans else 0.0


def analyze_biochemistry(contigs: list[str]):
    """Tính tỷ lệ GC%, số lượng cặp CpG, dịch mã 3 khung đọc và tỷ lệ axit amin kỵ nước."""
    combined_dna = "".join(contigs)
    total_len = len(combined_dna)
    if total_len == 0:
        return 0.0, 0, "", 0.0

    gc_count = combined_dna.count("G") + combined_dna.count("C")
    gc_pct = round(100.0 * gc_count / total_len, 2)
    cpg_count = sum(c.count("CG") for c in contigs)

    # Dịch mã 3 khung đọc trên contig dài nhất
    longest_contig = max(contigs, key=len)
    frames = []
    for frame in range(3):
        aa_seq = []
        for i in range(frame, len(longest_contig) - 2, 3):
            codon = longest_contig[i : i + 3]
            aa_seq.append(CODON_TABLE.get(codon, "X"))
        frames.append(f"F{frame+1}:{''.join(aa_seq)}")

    # Tính tỷ lệ axit amin kỵ nước trên khung đọc không chứa stop codon '*' (hoặc khung 1)
    valid_aa = [
        f.split(":")[1] for f in frames if "*" not in f.split(":")[1] and len(f.split(":")[1]) > 0
    ]
    ref_aa = valid_aa[0] if valid_aa else frames[0].split(":")[1]
    hydro_pct = (
        round(100.0 * sum(1 for aa in ref_aa if aa in HYDROPHOBIC_AA) / len(ref_aa), 1)
        if ref_aa
        else 0.0
    )

    return gc_pct, cpg_count, " | ".join(frames), hydro_pct


# ==============================================================================
# PIPELINE CHÍNH
# ==============================================================================
def main():
    ANALYSIS_DIR.mkdir(parents=True, exist_ok=True)

    print("1. Đang tải dữ liệu đã tiền xử lý human_preprocessed.txt...")
    records, class_counts, class_probs = load_dataset(DATASET_PATH)
    total_seqs = len(records)

    print("\n=== PHÂN BỐ NỀN (BASELINE) CỦA 7 HỌ PROTEIN TRONG DATASET ===")
    for cls in sorted(class_counts.keys()):
        print(
            f"  {cls} ({CLASS_NAMES.get(cls, 'Unknown'):35s}): "
            f"{class_counts[cls]:4d} chuỗi ({class_probs[cls]*100:5.2f}%)"
        )

    print(f"\n2. Đang phân tích kết quả từ {CHARM_OUTPUT_PATH.name}...")
    closed_sets = parse_charm_output(CHARM_OUTPUT_PATH)

    class_specific_rows = []
    universal_rows = []

    for items, sup in closed_sets:
        classes = sorted(it for it in items if it.startswith("CLASS_"))
        kmers = sorted(it for it in items if not it.startswith("CLASS_"))
        if not kmers:
            continue

        motif_set = frozenset(kmers)
        contigs = assemble_contigs(kmers)
        gc_pct, cpg_count, aa_frames, hydro_pct = analyze_biochemistry(contigs)
        is_overlapping = len(contigs) < len(kmers)

        if classes:
            # Pattern gắn với họ protein cụ thể
            motif_sup = get_motif_support(motif_set, closed_sets)
            if motif_sup == 0:
                motif_sup = sup

            for cls in classes:
                confidence = sup / motif_sup
                lift = confidence / class_probs[cls]
                mean_span = compute_mean_span_bp(kmers, records, target_cls=cls)

                class_specific_rows.append({
                    "class_id": cls,
                    "protein_family": CLASS_NAMES.get(cls, cls),
                    "num_kmers": len(kmers),
                    "num_contigs": len(contigs),
                    "pattern_type": "Overlapping_Contig" if is_overlapping else "Co_occurring_Distal",
                    "assembled_contigs": "; ".join(contigs),
                    "raw_kmers": " ".join(kmers),
                    "support_count": sup,
                    "support_pct": round(100.0 * sup / total_seqs, 2),
                    "confidence": round(confidence, 4),
                    "lift": round(lift, 3),
                    "mean_span_bp": mean_span,
                    "gc_content_pct": gc_pct,
                    "cpg_dinucleotides": cpg_count,
                    "hydrophobic_aa_pct": hydro_pct,
                    "aa_3frames": aa_frames,
                })
        else:
            # Pattern phổ quát không gắn nhãn lớp
            mean_span = compute_mean_span_bp(kmers, records, target_cls=None)
            universal_rows.append({
                "num_kmers": len(kmers),
                "num_contigs": len(contigs),
                "pattern_type": "Overlapping_Contig" if is_overlapping else "Co_occurring_Distal",
                "assembled_contigs": "; ".join(contigs),
                "raw_kmers": " ".join(kmers),
                "support_count": sup,
                "support_pct": round(100.0 * sup / total_seqs, 2),
                "mean_span_bp": mean_span,
                "gc_content_pct": gc_pct,
                "cpg_dinucleotides": cpg_count,
                "hydrophobic_aa_pct": hydro_pct,
                "aa_3frames": aa_frames,
            })

    # Sắp xếp kết quả: ưu tiên Lift & số lượng k-mer cho nhóm đặc hiệu lớp
    class_specific_rows.sort(
        key=lambda r: (r["lift"], r["num_kmers"], r["support_count"]), reverse=True
    )
    universal_rows.sort(
        key=lambda r: (r["num_kmers"], r["support_count"]), reverse=True
    )

    # Xuất ra 2 file CSV
    cls_csv = ANALYSIS_DIR / "class_specific_bio_analysis.csv"
    if class_specific_rows:
        with cls_csv.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(class_specific_rows[0].keys()))
            writer.writeheader()
            writer.writerows(class_specific_rows)

    uni_csv = ANALYSIS_DIR / "universal_motifs_bio_analysis.csv"
    if universal_rows:
        with uni_csv.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(universal_rows[0].keys()))
            writer.writeheader()
            writer.writerows(universal_rows)

    print(f"\n3. Đã xuất báo cáo chi tiết tại thư mục: {ANALYSIS_DIR}")
    print(f"   - Pattern đặc hiệu họ gene : {len(class_specific_rows)} mẫu -> {cls_csv.name}")
    print(f"   - Pattern phổ quát toàn cục: {len(universal_rows)} mẫu -> {uni_csv.name}")

    # In tóm tắt ra terminal
    if class_specific_rows:
        print("\n=== TOP 10 PATTERN ĐẶC HIỆU HỌ PROTEIN (XẾP THEO LIFT) ===")
        for r in class_specific_rows[:10]:
            print(
                f"[{r['class_id']} - {r['protein_family'][:22]:22s}] "
                f"Sup={r['support_count']:3d} | Conf={r['confidence']:.2f} | Lift={r['lift']:5.2f}x | "
                f"GC={r['gc_content_pct']:5.1f}% | HydroAA={r['hydrophobic_aa_pct']:4.1f}% | "
                f"Contig: {r['assembled_contigs']}"
            )

    if universal_rows:
        print("\n=== TOP 10 PATTERN PHỔ QUÁT TOÀN HỆ GENE ===")
        for r in universal_rows[:10]:
            print(
                f"[Size={r['num_kmers']:2d} | {r['pattern_type']:19s}] "
                f"Sup={r['support_count']:4d} ({r['support_pct']:5.2f}%) | "
                f"GC={r['gc_content_pct']:5.1f}% | CpG={r['cpg_dinucleotides']:2d} | "
                f"Contig: {r['assembled_contigs']}"
            )


if __name__ == "__main__":
    main()