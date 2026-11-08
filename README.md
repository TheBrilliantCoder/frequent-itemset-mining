# CharmMining: Khai thác tập phổ biến đóng với thuật toán CHARM

Dự án cài đặt từ đầu (scratch implementation) thuật toán **CHARM** (Closed Association Rule Mining) bằng ngôn ngữ **Julia**, phục vụ bài toán khai thác tập phổ biến đóng (Frequent Closed Itemset Mining - FIM). Hệ thống sử dụng cấu trúc cơ sở dữ liệu dạng dọc (Vertical Database) kết hợp `BitSet` để biểu diễn tidset, sắp xếp thứ tự duyệt bằng trọng số tần số 2-itemsets, và cơ chế kiểm tra bao hàm (subsumption checking) qua bảng băm TID checksum.

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
│   ├── models.jl             # Định nghĩa cấu trúc dữ liệu: ITPair, ClosedItemset, Tidset (BitSet)
│   ├── data.jl               # Xử lý I/O dữ liệu chuẩn SPMF, chuyển đổi VerticalDB
│   ├── ordering.jl           # Sắp xếp nút theo trọng số CHARM weight (F2)
│   ├── properties.jl         # Định nghĩa và phân loại 4 tính chất CHARM-Property
│   ├── repository.jl         # ClosedItemsetRepository & Hash-based Subsumption Checking
│   ├── engine.jl             # Thuật toán duyệt đệ quy IT-Tree (charm, charm_extend)
│   └── pipeline.jl           # Pipeline cấp cao mine_file tích hợp đọc - lọc - khai thác - ghi
├── data/
│   ├── toy/                  # CSDL nhỏ kiểm thử nhanh (contextPasquier99.txt)
│   └── benchmark/            # CSDL benchmark chuẩn FIMI (chess, mushroom, retail, T10I4D100K, accidents)
└── test/
    ├── runtests.jl           # Master test runner
    ├── test_data.jl          # Unit test: Đọc file, xử lý comment, chuyển đổi VerticalDB
    ├── test_ordering.jl      # Unit test: Tính CHARM weight và sắp xếp tăng dần
    ├── test_properties.jl    # Unit test: Kiểm thử độc lập 4 tính chất CHARM
    ├── test_repository.jl    # Unit test: TID checksum băm và thuật toán consider!
    ├── test_engine.jl        # Integration test: Khai thác trên CSDL Pasquier 1999
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
Mở file `run.jl` tại thư mục gốc để cấu hình đường dẫn file và ngưỡng hỗ trợ:

```julia
include("src/CharmMining.jl")
using .CharmMining

input_file = "data/toy/contextPasquier99.txt"
output_file = "output.txt"
min_support = 2  # Ngưỡng minsup dạng số lượng giao dịch (Int)

println("Starting CHARM algorithm...")
results = mine_file(input_file; minsup = min_support, output_path = output_file)
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

---

## 4. Kiểm thử tự động & Đối chuẩn SPMF (Testing & Verification)

Dự án sở hữu bộ test suite tự động gồm **115 bài kiểm thử**, bao phủ từ các hàm chức năng đơn lẻ cho đến kiểm thử chéo với SPMF.

### Chuẩn bị SPMF CLI (cho kiểm thử đối chứng)
Tải file thực thi `spmf.jar` vào thư mục `tools/`:

- **Linux / macOS / WSL:**
  ```bash
  mkdir -p tools
  curl -o tools/spmf.jar https://www.philippe-fournier-viger.com/spmf/spmf.jar
  ```
- **Windows (Command Prompt):**
  ```cmd
  mkdir tools
  curl -o tools\spmf.jar https://www.philippe-fournier-viger.com/spmf/spmf.jar
  ```

*(Lưu ý: Nếu không có file `tools/spmf.jar`, bài test `test_oracle.jl` sẽ đưa ra cảnh báo và tự động bỏ qua mà không làm gián đoạn các unit test nội bộ khác).*

### Chuẩn bị dữ liệu Benchmark (để chạy đầy đủ 115 test cases)

Do các bộ dữ liệu benchmark có dung lượng lớn và nằm trong `.gitignore`, bạn có thể chuẩn bị dữ liệu theo các bước sau:

1. **Tải dữ liệu về máy:**
   - **Lựa chọn A (Khuyên dùng - Gói nén của nhóm):** Tải file `benchmark_datasets.zip` đã được chuẩn hóa sẵn tại drive của nhóm
   - **Lựa chọn B (Tải trực tiếp từ web gốc):** Truy cập bằng trình duyệt vào [FIMI Repository](http://fimi.uantwerpen.be/data/) hoặc [SPMF Datasets](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php) để tải trực tiếp 5 file dữ liệu (`chess`, `mushroom`, `retail`, `T10I4D100K`, `accidents`).

2. **Thêm dữ liệu vào thư mục dự án:**
   - Giải nén (nếu dùng Lựa chọn A) hoặc sao chép các file vừa tải vào thư mục `data/benchmark/`.
   - Đảm bảo tên file trong thư mục khớp đúng định dạng:
     - `data/benchmark/chess.txt`
     - `data/benchmark/mushroom.txt`
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
| `test_oracle.jl` | Tự động chạy song song Julia CHARM và `Charm_bitset` của SPMF trên toàn bộ 5 CSDL benchmark, xác thực tỷ lệ khớp 100%. |

### Kết quả nghiệm thu thực tế với SPMF Oracle
Toàn bộ **115/115 bài test** đều vượt qua (Pass 100%) với thời gian thực thi xấp xỉ 15 giây:

| Tập dữ liệu | Đặc tính | Số giao dịch (\|D\|) | Ngưỡng minsup | Số tập đóng tìm được | Tỷ lệ khớp với SPMF |
|---|---|---|---|---|---|
| **contextPasquier99** | Mẫu nhỏ (Toy) | 9 | 22% (2 txs) | 9 | **100% (9/9)** |
| **mushroom.txt** | Dense | 8.124 | 30% | 425 | **100% (425/425)** |
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

## 6. Demo Notebooks & Ứng dụng thực tế
