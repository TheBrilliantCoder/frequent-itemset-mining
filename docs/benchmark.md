# Benchmark: Basic vs. Optimized vs. SPMF

Tài liệu này mô tả tổng quan benchmark trong thư mục `comparison/`. Cách chạy xem trong `README.md`, mục "Chạy benchmark".

## Mục tiêu

So sánh ba cài đặt thuật toán CHARM (khai thác tập phổ biến đóng) trên cùng dữ liệu, cùng ngưỡng minsup:

| Tên | Cài đặt | Hàm |
|---|---|---|
| `basic` | Julia, tidset là `BitSet` | `mine_file` |
| `optimized` | Julia, `BitVector` + `@simd`, itemset là `Vector{Int32}` | `mine_file_bit` |
| `spmf` | Java, `Charm_bitset` trong SPMF | `tools/spmf.jar` |

Ba chỉ số được đo: **thời gian chạy**, **bộ nhớ đỉnh**, và **khả năng mở rộng** khi CSDL lớn dần. Số tập đóng tìm được cũng được ghi lại; ba bản phải cho cùng một con số (nếu lệch, script in cảnh báo).

## Cách đo

- **Mỗi lần chạy là một tiến trình riêng**: bản Julia chạy qua `comparison/worker.jl`, SPMF chạy qua `java -jar`. Nhờ vậy cả ba được đo bằng cùng một cách, không bị ảnh hưởng bởi JIT hay bộ gom rác của tiến trình khác.
- **Thời gian**: đồng hồ treo tường của cả tiến trình, gồm đọc dữ liệu, khai thác và ghi kết quả.
- **Bộ nhớ**: giá trị đỉnh RSS (`VmHWM` trong `/proc/<pid>/status`), nên chỉ chạy được trên Linux. Tiến trình bị dừng nếu vượt `MEMORY_LIMIT_MB` (mặc định 6000 MB) và dòng đó có `status = mem_exceeded`.
- **Chi phí khởi động**: Julia và JVM đều tốn thời gian và RAM cố định khi khởi động. Script chạy mỗi bản một lần trên `data/toy/contextPasquier99.txt` để lấy mức nền, rồi báo cả giá trị thô và giá trị đã trừ nền (`net_seconds`, `net_mb`). Biểu đồ dùng giá trị đã trừ nền.
- **minsup**: dùng cùng một tỷ lệ phần trăm. SPMF nhận phần trăm; hai bản Julia nhận số giao dịch tuyệt đối, tính bằng `ceil(số giao dịch × tỷ lệ)`.

## Ba phép đo

| Phép đo | Script đo | Script vẽ | Nội dung |
|---|---|---|---|
| Thời gian | `compare_time.jl` | `plot_time.jl` | Cả 5 dataset, nhiều mức minsup từ cao xuống thấp |
| Bộ nhớ | `compare_memory.jl` | `plot_memory.jl` | Mỗi dataset một mức minsup giữa dải, lặp 3 lần, lấy trung vị |
| Mở rộng | `compare_scalability.jl` | `plot_scalability.jl` | Một dataset, lấy mẫu lồng nhau 10/25/50/75/100% giao dịch, cùng tỷ lệ minsup; khớp mô hình tuyến tính, lũy thừa, mũ |

### Dataset và dải minsup (đo thời gian)

| Dataset | Loại | Các mức minsup |
|---|---|---|
| `chess`, `accidents` | very dense | 90%, 80%, 70%, 60%, 50%, 40% |
| `mushrooms` | dense | 80%, 60%, 50%, 20%, 10%, 5% |
| `retail`, `T10I4D100K` | sparse | 10%, 8%, 6%, 4%, 2%, 1%, 0.5% |

Dữ liệu dày cần minsup cao để số tập đóng không quá lớn; dữ liệu thưa cần minsup thấp để còn tìm được mẫu có ý nghĩa.

## Cấu trúc mã

```text
comparison/
├── common.jl              # hằng số, tìm dataset, chạy tiến trình con, đo RSS đỉnh
├── worker.jl              # tiến trình con cho basic / optimized
├── compare_*.jl           # ba phép đo, ghi CSV vào metrics/
├── plot_*.jl              # đọc CSV, vẽ SVG vào plots/ (không cần thư viện ngoài)
├── run_all.jl             # chạy tất cả
├── metrics/               # kết quả CSV
└── plots/                 # biểu đồ SVG
```

## Các file kết quả

**`metrics/` (CSV)**

- `time_result.csv`: `dataset, dataset_type, minsup_ratio, minsup_count, implementation, seconds, net_seconds, peak_mb, itemsets, status`. Mỗi (dataset, minsup, implementation) một dòng. Nếu `status` khác `ok` thì các cột số để trống.
- `memory_result.csv`: từng lần đo RAM. `memory_summary.csv`: trung vị và mức giảm RAM so với `basic`.
- `scalability_result.csv`, `scalability_summary.csv`: thời gian và RAM theo kích thước CSDL. `scalability_analysis.csv`: số mũ lũy thừa, R² của ba mô hình và kết luận về độ tăng trưởng.

**`plots/` (SVG)**: mỗi dataset có `<dataset>_runtime.svg` (ba đường: basic, optimized, SPMF) và `<dataset>_itemsets.svg`; ngoài ra có `memory_peak.svg`, `memory_net.svg`, `scalability_runtime.svg`, `scalability_loglog.svg`, `scalability_memory.svg`.

## Lưu ý khi đọc kết quả

- Với dữ liệu nhỏ, thời gian sau khi trừ nền rất ngắn nên sai số tương đối lớn. Tăng `TIME_RUNS` để lấy trung vị.
- Bản Julia và SPMF dùng bộ gom rác khác nhau (Julia GC và JVM); chênh lệch RAM một phần đến từ đây chứ không chỉ từ thuật toán. Đặt `SPMF_JAVA_OPTS=-Xmx...` nếu muốn cố định heap của JVM.
