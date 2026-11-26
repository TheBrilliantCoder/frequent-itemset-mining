# CharmMining: Khai thác tập phổ biến đóng với thuật toán CHARM

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/TheBrilliantCoder/frequent-itemset-mining/blob/main/notebooks/demo.ipynb)

**Demo notebook (Chương 1 → 3, chạy trên Google Colab):** [notebooks/demo.ipynb](https://colab.research.google.com/github/TheBrilliantCoder/frequent-itemset-mining/blob/main/notebooks/demo.ipynb)

Dự án cài đặt từ đầu (scratch implementation) thuật toán **CHARM** (Closed Association Rule Mining) bằng ngôn ngữ **Julia**, phục vụ bài toán khai thác tập phổ biến đóng (Frequent Closed Itemset Mining - FIM). Hệ thống cung cấp hai phiên bản cài đặt đối xứng để đối chiếu hiệu năng:
- **Bản cơ bản (Baseline):** Sử dụng cơ sở dữ liệu dạng dọc (Vertical Database) kết hợp `BitSet` để biểu diễn tidset, sắp xếp thứ tự duyệt bằng trọng số tần số 2-itemsets, và kiểm tra bao hàm (subsumption checking) qua bảng băm tổng TID.
- **Bản tối ưu (Optimized):** Tối ưu hóa cấp độ thấp với mảng bit liền kề `BitVector` kết hợp tập lệnh вектор hóa `@inbounds @simd`, mã hóa `Itemset` thành mảng số nguyên có thứ tự `Vector{Int32}`, cắt tỉa hai pha không cấp phát bộ nhớ (Zero-Allocation Pruning) và hàm băm 64-bit XOR checksum.

Toàn bộ thuật toán được kiểm thử tự động và đối chuẩn khớp 100% với thư viện chuẩn **SPMF (Java)**.

---

## 1. Yêu cầu hệ thống & Cài đặt môi trường

### Yêu cầu tiên quyết
- **Julia**: Phiên bản 1.9 trở lên (đã kiểm thử tương thích tốt trên Julia 1.10 và 1.11+).
- **Java Runtime Environment (JRE)**: Phiên bản 8 trở lên (chỉ bắt buộc khi chạy module kiểm thử đối chuẩn tự động với SPMF Oracle).

### Khởi tạo môi trường
Dự án được tối ưu hóa dựa trên thư viện chuẩn (`Base`) của Julia, không phụ thuộc vào các thư viện FIM bên ngoài. Khởi tạo môi trường dự án bằng lệnh:

```bash
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

---

## 2. Cấu trúc dự án

```text
CharmMining/
├── Project.toml              # Cấu hình dự án Julia
├── .gitignore                # Chặn các file dữ liệu lớn và file sinh tự động
├── run.jl                    # Script thực thi nhanh
├── tools/
│   └── spmf.jar              # Thư viện SPMF phục vụ kiểm thử đối chứng Oracle
├── src/
│   ├── CharmMining.jl        # Module chính (entrypoint tổng hợp các submodule)
│   ├── models.jl             # Định nghĩa cấu trúc dữ liệu cơ bản: ITPair, ClosedItemset, Tidset (BitSet)
│   ├── data.jl               # Xử lý I/O dữ liệu chuẩn SPMF, chuyển đổi VerticalDB
│   ├── ordering.jl           # Sắp xếp nút theo trọng số CHARM weight (F2)
│   ├── properties.jl         # Định nghĩa và phân loại 4 tính chất CHARM-Property
│   ├── repository.jl         # ClosedItemsetRepository & Hash-based Subsumption Checking
│   ├── engine.jl             # Thuật toán duyệt đệ quy IT-Tree (charm, charm_extend)
│   ├── pipeline.jl           # Pipeline cấp cao mine_file tích hợp đọc - lọc - khai thác - ghi
│   ├── rules.jl              # Sinh luật kết hợp chính xác từ tập phổ biến đóng (ClosureSupportIndex)
│   └── optimized/            # Module tối ưu hóa (BitVector + Int32 + @simd)
│       ├── Optimized.jl      # Submodule gom và export các thành phần tối ưu
│       ├── models.jl         # FastBitTidset (BitVector), FastITNode (Vector{Int32}), BitVerticalDB
│       ├── ordering.jl       # Tính trọng số F2 bằng @simd count_ones & sắp xếp tại chỗ
│       ├── properties.jl     # Giao BitVector hai pha (Zero-Allocation) & tái sử dụng vùng nhớ
│       ├── repository.jl     # Bảng băm 2 tầng với 64-bit XOR checksum & sorted_issubset
│       └── engine.jl         # Vòng lặp đệ quy charm_extend_bit & pipeline mine_file_bit
├── comparison/               # Thực nghiệm Chương 2: Basic vs. Optimized vs. SPMF
│   ├── compare_time.jl       # Thời gian chạy & số tập đóng theo minsup (5 benchmark)
│   ├── compare_memory.jl     # Bộ nhớ đỉnh (VmHWM) theo từng cài đặt
│   ├── compare_scalability.jl # Khả năng mở rộng 10% -> 100% giao dịch
│   ├── plot_*.jl             # Vẽ biểu đồ SVG từ các file CSV kết quả
│   └── *_result.csv, *_summary.csv # Kết quả đo đã lưu
├── applications/             # Ứng dụng thực tế (Chương 3)
│   ├── market_basket/        # Ứng dụng 1: Market Basket Analysis trên UCI Online Retail
│   │   ├── prepare_data.py   # Tải, làm sạch dữ liệu & chuyển đổi sang SPMF .txt + item_mapping.csv
│   │   ├── run_mba.jl        # Khai thác bằng Optimized CHARM & sinh luật kết hợp (Top-10 Lift)
│   │   ├── posthoc_analysis.py # Kiểm chứng hậu kiểm (Herb Marker 1..6, mùa vụ & in-season Lift, CustomerID)
│   │   └── plot_mba.py       # Vẽ 4 biểu đồ phân tích độ phân giải cao
│   └── dna/                  # Ứng dụng 2: Khai thác motif k-mer trên trình tự DNA người (7 họ protein)
│       ├── eda.py            # Tiền xử lý (lọc độ dài, khử trùng lặp) & thống kê mô tả
│       ├── run_dna.jl        # Mã hóa k-mer -> SPMF và khai thác CHARM toàn cục (k=6) & theo lớp (k=8)
│       └── analysis.py       # Ghép contig, GC/CpG, dịch mã 3 khung, xuất CSV phân tích sinh học
├── requirements.txt          # Thư viện Python cho Chương 3 (pandas, openpyxl, matplotlib)
├── scripts/
│   └── download_data.py      # Tải benchmark, spmf.jar, UCI Online Retail (kiểm tra SHA-256)
├── notebooks/
│   ├── demo.ipynb            # Demo toàn bộ dự án Chương 1 → 3 (Google Colab)
│   └── app1_market_basket.ipynb # Notebook riêng cho Ứng dụng 1
├── docs/
│   ├── app1_market_basket.md # Báo cáo & diễn giải kinh doanh cho Ứng dụng 1
│   ├── dna.md                # Báo cáo phân tích pattern DNA cho Ứng dụng 2
│   └── figures/app1/         # Biểu đồ xuất bản cho báo cáo Ứng dụng 1
├── data/
│   ├── toy/                  # CSDL nhỏ kiểm thử nhanh (contextPasquier99.txt)
│   ├── benchmark/            # CSDL benchmark chuẩn FIMI (chess, mushrooms, retail, T10I4D100K, accidents)
│   └── applications/         # Dữ liệu Chương 3 (online_retail/ tự tải; dna/human.txt có sẵn)
├── results/                  # Kết quả sinh tự động (bị .gitignore): app1/, app2/
└── test/
    ├── runtests.jl           # Master test runner
    ├── test_data.jl          # Unit test: Đọc file, xử lý comment, chuyển đổi VerticalDB
    ├── test_ordering.jl      # Unit test: Tính CHARM weight và sắp xếp tăng dần
    ├── test_properties.jl    # Unit test: Kiểm thử độc lập 4 tính chất CHARM
    ├── test_repository.jl    # Unit test: TID checksum băm và thuật toán consider!
    ├── test_engine.jl        # Integration test: Khai thác trên CSDL Pasquier 1999
    ├── test_optimized.jl     # Unit & Integration test: Kiểm thử toàn diện bản tối ưu & đối chiếu Baseline
    ├── test_rules.jl         # Unit test: Tra cứu bao đóng & sinh luật kết hợp (Support, Confidence, Lift)
    └── test_oracle.jl        # Oracle test: Đối chuẩn tự động 100% với SPMF trên 5 benchmark
```

---

## 3. Hướng dẫn sử dụng

### Định dạng dữ liệu đầu vào
File văn bản (`.txt`) theo quy cách SPMF: mỗi dòng biểu diễn một giao dịch (transaction), các item cách nhau bằng dấu cách. Các dòng chú thích bắt đầu bằng `#`, `%`, hoặc `@` sẽ tự động được bỏ qua.

Ví dụ (`data/toy/contextPasquier99.txt`):
```text
1 2 5
2 4
2 3
1 2 4
1 3
2 3
1 3
1 2 3 5
1 2 3
```

### Chạy thuật toán qua script `run.jl`
Mở file `run.jl` tại thư mục gốc để cấu hình đường dẫn file và ngưỡng hỗ trợ (có thể chọn `mine_file` cho bản cơ bản hoặc `mine_file_bit` cho bản tối ưu):

```julia
include("src/CharmMining.jl")
using .CharmMining

input_file = "data/toy/contextPasquier99.txt"
output_file = "results/output.txt"
min_support = 2  # Ngưỡng minsup dạng số lượng giao dịch (Int)

println("Starting CHARM algorithm (Optimized)...")
results = mine_file_bit(input_file; minsup = min_support, output_path = output_file)
println("Found $(length(results)) closed itemsets.")
```

Thực thi từ terminal:
```bash
julia --project=. run.jl
```

### Định dạng kết quả đầu ra
Kết quả được ghi nhận vào file đầu ra theo đúng chuẩn SPMF (`<item_1> <item_2> ... #SUP: <count>`):
```text
2 #SUP: 7
1 #SUP: 6
3 #SUP: 6
1 2 #SUP: 4
1 3 #SUP: 4
2 3 #SUP: 4
1 2 3 #SUP: 2
1 2 5 #SUP: 2
2 4 #SUP: 2
```

### Đo lường và lưu kết quả thực nghiệm (Chương 2 — `comparison/`)
Các script đối chiếu hiệu năng giữa **bản cơ bản (`mine_file`)**, **bản tối ưu (`mine_file_bit`)** và **SPMF `Charm_bitset`** trên toàn bộ 5 CSDL benchmark. Mỗi lần chạy là một tiến trình riêng. Cần `java` và `tools/spmf.jar` (xem mục 4).

```bash
julia --project=. comparison/compare_time.jl         # -> comparison/time_result.csv
julia --project=. comparison/compare_memory.jl       # -> comparison/memory_result.csv, memory_summary.csv
julia --project=. comparison/compare_scalability.jl  # -> comparison/scalability_*.csv
julia --project=. comparison/plot_time.jl            # -> comparison/plots/*.svg
julia --project=. comparison/plot_memory.jl
julia --project=. comparison/plot_scalability.jl
```

- `time_result.csv`: thời gian chạy và số tập đóng của 3 cài đặt qua các ngưỡng `minsup` giảm dần.
- `memory_result.csv` / `memory_summary.csv`: bộ nhớ đỉnh (RSS) và bộ nhớ ròng sau khi trừ chi phí khởi động Julia/JVM.
- `scalability_*.csv`: thời gian & bộ nhớ khi tăng kích thước CSDL từ `10%` lên `100%` (mặc định `T10I4D100K`, đổi bằng biến `SCALABILITY_DATASET`).

---

## 4. Kiểm thử tự động & Đối chuẩn SPMF (Testing & Verification)

Dự án sở hữu bộ test suite tự động gồm **238 bài kiểm thử**, bao phủ từ các hàm chức năng đơn lẻ của cả hai phiên bản (Baseline và Optimized), module sinh luật kết hợp (`src/rules.jl`) cho đến kiểm thử chéo với SPMF.

### Chuẩn bị SPMF CLI (cho kiểm thử đối chứng)

Tải [Java Development Kit](https://adoptium.net/temurin/releases) mới nhất để chạy được thư viện SPMF. 
Sau đó thiết lập môi trường để máy nhận diện lệnh java. Sau đó kiểm tra:

```java
java --version
```

Output nên là:

```text
openjdk 25.0.5 2026-10-20 LTS
OpenJDK Runtime Environment Temurin-25.0.5+8 (build 25.0.5+8-LTS)
OpenJDK 64-Bit Server VM Temurin-25.0.5+8 (build 25.0.5+8-LTS, mixed mode, sharing)
```

Tải file thực thi `spmf.jar` vào thư mục `tools/`:

- **Linux / macOS / WSL:**
  ```bash
  mkdir -p tools
  curl -o tools/spmf.jar [https://www.philippe-fournier-viger.com/spmf/spmf.jar](https://www.philippe-fournier-viger.com/spmf/spmf.jar)
  ```
- **Windows (Command Prompt):**
  ```cmd
  mkdir tools
  curl -o tools\spmf.jar [https://www.philippe-fournier-viger.com/spmf/spmf.jar](https://www.philippe-fournier-viger.com/spmf/spmf.jar)
  ```

*(Lưu ý: Nếu không có file `tools/spmf.jar`, bài test `test_oracle.jl` sẽ đưa ra cảnh báo và tự động bỏ qua mà không làm gián đoạn các unit test nội bộ khác).*

### Chuẩn bị dữ liệu Benchmark (để chạy đầy đủ 238 test cases)

Do các bộ dữ liệu benchmark có dung lượng lớn và nằm trong `.gitignore`, bạn có thể chuẩn bị dữ liệu theo các bước sau:

1. **Tải dữ liệu về máy:**
   - **Lựa chọn A (Khuyên dùng):** Chạy script tải tự động từ kho Hugging Face của nhóm (5 benchmark, `tools/spmf.jar`, UCI Online Retail; kiểm tra SHA-256 từng file):
     ```bash
     python3 scripts/download_data.py
     ```
   - **Lựa chọn B (Tải trực tiếp từ web gốc):** Truy cập bằng trình duyệt vào [FIMI Repository](http://fimi.uantwerpen.be/data/) hoặc [SPMF Datasets](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php) để tải trực tiếp 5 file dữ liệu (`chess`, `mushrooms`, `retail`, `T10I4D100K`, `accidents`).

2. **Thêm dữ liệu vào thư mục dự án:**
   - Với Lựa chọn B, sao chép các file vừa tải vào thư mục `data/benchmark/`.
   - Đảm bảo tên file trong thư mục khớp đúng định dạng:
     - `data/benchmark/chess.txt`
     - `data/benchmark/mushrooms.txt`
     - `data/benchmark/retail.txt`
     - `data/benchmark/T10I4D100K.txt`
     - `data/benchmark/accidents.txt`

### Thực thi bộ kiểm thử
Chạy test runner từ thư mục gốc của dự án:

```bash
julia --project=. test/runtests.jl
```

### Chi tiết các module kiểm thử
| File kiểm thử | Nội dung kiểm thử |
|---|---|
| `test_data.jl` | Kiểm tra lọc dòng chú thích (`#`, `%`, `@`), chuẩn hóa item trùng lặp, chuyển đổi sang `VerticalDB`, và định dạng xuất file SPMF. |
| `test_ordering.jl` | Kiểm tra tính bảng trọng số `build_weight_map`, hàm `charm_weight` và sắp xếp thứ tự nút tăng dần theo trọng số. |
| `test_properties.jl` | Kiểm thử cô lập 4 nhánh quan hệ CHARM-Property (`EQUAL`, `LEFT_SUBSET`, `RIGHT_SUBSET`, `INCOMPARABLE`) cùng cơ chế cắt tỉa nhánh không đủ `minsup`. |
| `test_repository.jl` | Kiểm tra hàm băm tổng TID ($\sum \text{tid}$), kiểm tra khả năng xử lý va chạm băm và thuật toán `consider!` loại bỏ tập con cùng support. |
| `test_engine.jl` | Kiểm thử tích hợp thuật toán CHARM trên bộ dữ liệu mẫu Pasquier 1999, xác thực tính đóng (không xuất hiện các tập con thừa). |
| `test_optimized.jl` | Kiểm thử từng thành phần của bản tối ưu (`BitVerticalDB`, `sorted_union`, `charm_property_bit`, 64-bit XOR checksum) và đối chiếu khớp 100% với bản Baseline. |
| `test_rules.jl` | Kiểm thử chỉ mục tra cứu bao đóng `ClosureSupportIndex`, tính toán chính xác Support / Confidence / Lift / Leverage / Conviction và khử cặp đối xứng `top_rules_by_lift`. |
| `test_oracle.jl` | Tự động chạy song song cả hai bản Julia CHARM (`mine_file`, `mine_file_bit`) và `Charm_bitset` của SPMF trên toàn bộ 5 CSDL benchmark, xác thực tỷ lệ khớp 100%. |

### Kết quả nghiệm thu thực tế với SPMF Oracle
Toàn bộ **238/238 bài test** đều vượt qua (Pass 100%) trên cả phiên bản Baseline, Optimized và module Association Rules:

| Tập dữ liệu | Đặc tính | Số giao dịch (\|D\|) | Ngưỡng minsup | Số tập đóng tìm được | Tỷ lệ khớp với SPMF |
|---|---|---|---|---|---|
| **contextPasquier99** | Mẫu nhỏ (Toy) | 9 | 22% (2 txs) | 9 | **100% (9/9)** |
| **mushrooms.txt** | Dense | 8.124 | 30% | 425 | **100% (425/425)** |
| **chess.txt** | Very Dense | 3.196 | 70% | 23.892 | **100% (23.892/23.892)** |
| **retail.txt** | Very Sparse | 88.162 | 2% | 55 | **100% (55/55)** |
| **T10I4D100K.txt** | Sparse tổng hợp | 100.000 | 2% | 155 | **100% (155/155)** |
| **accidents.txt** | Large & Dense | 340.183 | 80% | 149 | **100% (149/149)** |

---

## 5. Dữ liệu thực nghiệm (Datasets)

Các tập dữ liệu benchmark được lưu trữ cục bộ trong `data/benchmark/` phục vụ đo đạc hiệu năng và phân tích:
- Nguồn tham chiếu gốc: [FIMI Repository](http://fimi.uantwerpen.be/data/) và [SPMF Datasets](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php).
- Để tối ưu dung lượng Git repository, các bộ dữ liệu lớn đã được cấu hình trong `.gitignore` và được tự động tải về qua script hoặc truy xuất từ kho lưu trữ mở khi chạy trên Google Colab.

---

## 6. Demo Notebooks & Ứng dụng thực tế (Chương 3)

### Ứng dụng 1: Phân tích Giỏ hàng (Market Basket Analysis — UCI Online Retail)
Ứng dụng sử dụng trực tiếp bản **Optimized CHARM (`mine_file_bit`)** cùng module sinh luật kết hợp dựa trên bao đóng Galois (`src/rules.jl`) trên tập dữ liệu bán lẻ thực tế **UCI Online Retail** (19.773 hóa đơn sạch, 3.787 sản phẩm).

- **Pipeline chuẩn bị dữ liệu & khai thác:**
  ```bash
  python applications/market_basket/prepare_data.py
  julia --project=. applications/market_basket/run_mba.jl
  python applications/market_basket/plot_mba.py
  ```
- **Notebook chạy trên Google Colab / Local:** `notebooks/app1_market_basket.ipynb`
- **Báo cáo phân tích & diễn giải kinh doanh:** `docs/app1_market_basket.md`
- **Kết quả & biểu đồ:** `results/app1/` (bảng độ nhạy `minsup_sensitivity.csv`, 962 luật tại `minsup = 1.0%`, `minconf = 50%`, Top-10 luật theo Lift và 4 biểu đồ phân tích trong `results/app1/figures/`).

### Ứng dụng 2: Khai thác motif trên trình tự DNA (Human DNA — 7 họ protein)
Mỗi trình tự DNA được mã hóa thành tập các **k-mer** (cửa sổ trượt) và khai thác bằng **Optimized CHARM** (`to_vertical_bit` + `run_charm_bit`): toàn cục với `k = 6`, `minsup = 30%` (nhãn lớp `CLASS_i` được thêm vào giao dịch), và riêng từng họ protein với `k = 8`, `minsup = 15%`.

- **Pipeline:**
  ```bash
  python applications/dna/eda.py        # -> data/applications/dna/human_preprocessed.txt
  julia --project=. applications/dna/run_dna.jl
  python applications/dna/analysis.py
  ```
- **Kết quả:** `results/app2/` (`global_closed_itemsets_k6.txt`, `per_class_charm/`, `bio_analysis/*.csv`).
- **Báo cáo phân tích:** `docs/dna.md`
