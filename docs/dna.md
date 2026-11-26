# Phân tích các pattern DNA bằng thuật toán CHARM

## 1. Phạm vi và cách đọc kết quả

Báo cáo này diễn giải các pattern được tìm thấy trong `results/app2/` (sinh bởi pipeline `applications/dna/`). Phân tích gồm kết quả CHARM toàn cục và kết quả chạy riêng cho bảy nhãn `CLASS_0`–`CLASS_6`. Trong CSV toàn cục, mỗi hàng mô tả một tập k-mer đóng cùng support và một số đặc trưng trình tự được tính từ motif đã ghép.

Support là số chuỗi trong tập phân tích có chứa pattern; `support_pct` là tỷ lệ trên toàn bộ tập đó. Đây là mức phổ biến, không tự nó cho biết pattern đặc hiệu cho một lớp hay có vai trò sinh học. Các file per-class hiện có motif và `#SUP`; chúng không có mẫu số lớp, confidence, lift hoặc kiểm định thống kê. Vì vậy, các pattern theo lớp dưới đây được xem là ứng viên để khảo sát, chưa phải biomarker đã xác nhận.

## 2. Biểu diễn trình tự và CHARM

Mỗi chuỗi được biểu diễn bằng tập các k-mer thu được từ cửa sổ trượt. CSV toàn cục dùng các k-mer dài 6 ký tự; các file `per_class_charm` chứa các motif dài 8 ký tự. Khi các k-mer chồng lấp, chúng có thể được ghép thành `assembled_contigs`. CHARM tìm các tập phổ biến đóng: các tập item có cùng tập chuỗi hỗ trợ được biểu diễn gọn mà vẫn giữ support.

Độ dài motif và ngưỡng support quyết định loại pattern nào có cơ hội xuất hiện. Cách chọn k=6 hoặc k=8 là lựa chọn phân tích, không có nghĩa motif tương ứng với codon hay đơn vị chức năng sinh học. Codon gồm ba nucleotide, nhưng một k-mer dài 6 hoặc 8 có thể bắt đầu ở bất kỳ vị trí nào và không nhất thiết nằm trong vùng mã hóa.

## 3. Các pattern phổ biến toàn cục

Ba dòng nổi bật trong `universal_motifs_bio_analysis.csv` cho thấy các motif lặp giàu A/G hoặc C/T/G phổ biến trong tập dữ liệu:

| Motif ghép | K-mer thành phần | Support | GC | CpG đếm được | Dịch mã ba khung trong CSV |
|---|---|---:|---:|---:|---|
| `AAGAAGAA` | `AAGAAG`, `AGAAGA`, `GAAGAA` | 1.366 (37,89%) | 25,0% | 0 | `KK`, `RR`, `EE` |
| `CTGCTGCT` | `CTGCTG`, `GCTGCT`, `TGCTGC` | 1.303 (36,14%) | 62,5% | 0 | `LL`, `CC`, `AA` |
| `CCTGGAGG` | `CCTGGA`, `CTGGAG`, `TGGAGG` | 1.228 (34,06%) | 75,0% | 0 | `PG`, `LE`, `WR` |

### 3.1. Motif `AAGAAGAA`

Đây là pattern có support lớn nhất trong ba ví dụ trên. Thành phần giàu A/G nhưng không có cặp CpG. Trong khung đọc thứ nhất, `AAG AAG` mã hóa lysine (K), còn các khung khác cho kết quả khác; điều đó minh họa rằng cách diễn giải thành amino acid phụ thuộc điểm bắt đầu đọc. Do chưa biết motif có nằm trong exon, intron, vùng điều hòa hay vùng khác, kết quả dịch mã tính toán không chứng minh motif tạo ra peptide KK hoặc có chức năng điều hòa cắt nối.

Một khả năng cần khảo sát là sự phong phú của các motif lặp phản ánh thành phần nucleotide, cấu trúc lặp hoặc thiên lệch của tập dữ liệu. Muốn gắn motif này với splicing cần đối chiếu tọa độ genome, chú giải exon/intron và các vị trí nối exon đã biết.

### 3.2. Motif `CTGCTGCT`

Motif này giàu GC (62,5%) và có thể đọc thành leucine ở khung thứ nhất (`CTG CTG`). Điều đó gợi ý một giả thuyết có thể kiểm tra: nếu các bản sao tập trung trong vùng mã hóa và đúng khung, chúng có thể tương ứng với đoạn giàu leucine. Tuy nhiên, kết quả CSV không cho biết vị trí hay khung mã hóa thực tế; hai khung còn lại cho amino acid khác. Vì vậy, chưa thể suy ra protein chứa đoạn leucine lặp, tốc độ dịch mã hoặc vai trò cấu trúc protein từ motif này riêng lẻ.

### 3.3. Motif `CCTGGAGG`

Motif có GC 75,0% nhưng `cpg_dinucleotides` bằng 0: trong chính chuỗi motif này không có hai ký tự `C` rồi `G` liền nhau. Đây là mô tả thành phần trình tự, chưa phải bằng chứng về cơ chế né tránh CpG hay áp lực đột biến. Đặc biệt, cùng contig `CCTGGAGG` còn xuất hiện ở một hàng CSV khác với support 1.329 (36,87%). Cần kiểm tra cách sinh các hàng trong pipeline trước khi chọn một support duy nhất để báo cáo.

Các khung dịch mã cho `PG`, `LE` và `WR`. `CCT GGA` mã hóa proline-glycine trong khung thứ nhất, nhưng không thể kết luận motif tạo ra cặp amino acid này nếu chưa xác nhận vùng mã hóa, strand và khung đọc. Các vai trò như tạo khớp nối protein hay điều khiển gấp cuộn không được đo trong output.

## 4. Cách diễn giải các chỉ số sinh học

- **GC content:** tỷ lệ G và C trong motif đã ghép. Đây là đặc tính cục bộ của motif, không đại diện cho GC của toàn gene hay genome. Mức 50% chỉ là mốc so sánh đơn giản, không phải giá trị nền thích hợp cho mọi vùng DNA.
- **CpG count:** số cặp `CG` liền kề bên trong motif. Giá trị 0 chỉ mô tả motif ngắn này; không đo methyl hóa, tần suất CpG trong vùng lân cận hoặc lịch sử đột biến.
- **`aa_3frames`:** kết quả dịch giả định cả ba khung trên chuỗi motif. Nếu chưa biết strand, vị trí bắt đầu, vùng mã hóa và tính liên tục của ORF, đây không phải dự đoán protein.
- **`hydrophobic_aa_pct`:** tỷ lệ amino acid kỵ nước theo phép dịch giả định của pipeline. Giá trị này phụ thuộc khung đọc và thành phần motif; không đủ để suy ra motif tạo lõi protein hay neo màng.
- **`mean_span_bp`:** khoảng cách trung bình được pipeline tính giữa các k-mer hỗ trợ một pattern. Một khoảng cách tuyến tính lớn không chứng minh các đoạn tiếp xúc trong cấu trúc 3D; điều đó cần dữ liệu cấu trúc hoặc thí nghiệm tương tác.
- **Support:** tần suất pattern trong tập chuỗi. Để đánh giá đặc hiệu lớp cần so sánh support giữa lớp mục tiêu và nền, biết rõ kích thước mỗi lớp, rồi tính lift/kiểm định và hiệu chỉnh nhiều phép thử.

## 5. Pattern trong các lớp

Các file per-class cho thấy một số chuỗi motif lặp xuất hiện nổi bật. Ví dụ, `CLASS_6` có `AAGAAGAA` (`#SUP: 267`), `AGAAGAAG` (257) và `GAAGAAGA` (241); `CLASS_3` có `TGGAGCAG` (94), `GCTGAAGA` (89) và `GGAGAAGA` (88); `CLASS_2` có cụm `CACTGCAG` (115), `TGCAGTGC` (115), `ACTGCAGT` (111) và `CTGCAGTG` (111). Các motif này là các kết quả quan sát được trong từng lần chạy.

Không nên diễn giải những motif trên như dấu ấn riêng của lớp chỉ dựa vào support trong file tương ứng. Một motif có thể phổ biến trong lớp lớn nhưng cũng phổ biến tương tự ở các lớp khác. Ngoài ra, số motif được ghi ra khác đáng kể giữa file lớp: `CLASS_3` và `CLASS_4` có 5 motif mỗi file, còn `CLASS_2` và `CLASS_5` có hàng nghìn dòng. Điều này có thể phản ánh khác biệt về kích thước lớp, ngưỡng hoặc cấu hình chạy; cần kiểm tra metadata và mẫu số trước khi so sánh trực tiếp.

## 6. Thảo luận và giới hạn sinh học

Các kết quả gợi ý rằng tập trình tự chứa nhiều motif ngắn giàu A/G và các motif giàu C/T/G, trong đó có các vùng lặp chồng lấp. Những pattern như vậy có thể là tín hiệu đáng quan tâm về thành phần nucleotide, lặp trình tự hoặc thiên lệch của dữ liệu. Với `CTGCTGCT`, có thể đặt giả thuyết về leucine lặp nếu motif nằm trong vùng mã hóa đúng khung; với `CCTGGAGG`, có thể khảo sát sự kết hợp GC cao và vắng CpG. Đây là các hướng phân tích tiếp theo, không phải kết luận chức năng từ CHARM.

Hiện output không chứa tọa độ genome, strand, chú giải gene, trạng thái exon/intron, biểu hiện, methyl hóa, hay phép đo cấu trúc protein. Do đó, chưa thể kết luận các motif là tín hiệu splicing, codon được ưu tiên, dấu ấn của thụ thể màng/yếu tố phiên mã, cơ chế né CpG, hoặc biomarker. Để kiểm định các giả thuyết này, cần ánh xạ motif về genome tham chiếu, đối chiếu chú giải chức năng và so sánh mức làm giàu giữa lớp với nền có kiểm soát độ dài chuỗi, thành phần nucleotide và tính lặp. Các giả thuyết quan trọng nên được xác nhận trên tập dữ liệu độc lập hoặc bằng thí nghiệm phù hợp.
