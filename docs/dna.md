# BÁO CÁO TỔNG HỢP: KHAI PHÁ MẪU TRÌNH TỰ ĐẶC TRƯNG TRÊN VÙNG KHỞI ĐỘNG PHIÊN MÃ (PROMOTER) BẰNG THUẬT TOÁN CHARM


> Pipeline: `applications/dna/cluster.py` (phân cụm tọa độ) → `applications/dna/run_dna.jl` (CHARM) → `applications/dna/report.py` (lọc tương phản). Dữ liệu: `data/applications/dna/promoters.data`; kết quả sinh ra trong `results/app2/`.

## 1. Giới thiệu bài toán

Trong hệ gene của sinh vật, **Promoter (vùng khởi động)** là các đoạn trình tự ngắn nằm ngay phía trước một gene, đóng vai trò như "công tắc điều khiển" giúp bộ máy tế bào nhận diện vị trí bắt đầu đọc và sao chép thông tin di truyền. Ngược lại, **Non-promoter** là các đoạn trình tự thông thường không mang chức năng khởi động này.

Bài toán đặt ra là **khai phá tri thức có giám sát từ dữ liệu chuỗi**: tự động phát hiện các đoạn mã ngắn (motif) và quy luật tổ hợp đặc trưng xuất hiện lặp lại trong nhóm Promoter (`class=+`) nhưng vắng mặt hoặc cực hiếm trong nhóm Non-promoter (`class=-`), hoàn toàn dựa trên phân tích thống kê và khai phá dữ liệu mà không áp đặt trước các giả định lý thuyết.


## 2. Tập dữ liệu nghiên cứu

Nghiên cứu sử dụng bộ dữ liệu chuẩn **Promoter Gene Sequences** của vi khuẩn *Escherichia coli*:

* **Quy mô & Cân bằng lớp:** Gồm **106 trình tự** độc lập, chia đều thành **53 mẫu Promoter (`class=+`)** và **53 mẫu Non-promoter (`class=-`)**.
* **Cấu trúc mỗi bản ghi:** Bao gồm nhãn phân lớp (`+`/`-`), tên định danh mẫu và chuỗi ký tự DNA dài cố định **57 nucleotide** (sử dụng bảng chữ cái 4 ký tự `a, c, g, t`).
* **Hệ tọa độ chuẩn hóa:** Toàn bộ 106 chuỗi đã được căn thẳng hàng theo điểm bắt đầu phiên mã (quy ước là vị trí `+1`, không có vị trí `0`), trải dài từ vị trí **`p-50`** (50 ký tự phía trước điểm khởi đầu) đến **`p7`** (7 ký tự phía sau điểm khởi đầu).

---

## 3. Quy trình khai phá tri thức & Lý do lựa chọn phương pháp

Quy trình được thiết kế thành 4 bước tuần tự nhằm chuyển hóa dữ liệu chuỗi thô thành các quy luật có ý nghĩa thống kê và sinh học:

### Bước 1: Hồ sơ hóa thống kê & Phân cụm tọa độ tự động

* **Cách thực hiện:** Xem mỗi vị trí từ `p-50` đến `p7` là một cột thuộc tính rời rạc. Tại từng cột, tính **Độ bảo tồn thông tin** ($IC = 2 - H$, dựa trên Shannon Entropy) của nhóm `class=+` và chạy **kiểm định $\chi^2$** để đo mức độ khác biệt phân bố ký tự `(a, c, g, t)` giữa hai lớp `+` và `-`. Các tọa độ có ý nghĩa thống kê ($p\text{-value} < 0,05$) nằm gần nhau được gom nhóm và nới rộng biên thêm $\pm 3$ vị trí.
* **Lý do lựa chọn:** Thay vì khoanh vùng thủ công dựa trên kiến thức sẵn có, kiểm định thống kê giúp dữ liệu tự chỉ ra các "điểm nóng" mang thông tin phân loại. Kết quả tự động chia 57 vị trí thành **3 cụm vùng trọng tâm**:
* **`C1` (`3:23`, tương ứng `p-48` đến `p-28`):** Vùng điều hòa ngược dòng.
* **`C2` (`27:34`, tương ứng `p-24` đến `p-17`):** Vùng đệm trung tâm.
* **`C3` (`35:52`, tương ứng `p-16` đến `p1`):** Vùng sát điểm khởi đầu phiên mã.



### Bước 2: Mã hóa giao dịch bằng cửa sổ trượt $k$-mer theo cụm

* **Cách thực hiện:** Thay vì mã hóa từng ký tự đơn lẻ tại một tọa độ cố định (ví dụ `p-10=a`), thuật toán cắt các đoạn con liên tiếp độ dài **`k = 5`** ($5$-mer) trượt bên trong từng cụm vừa tìm được, gắn tiền tố tên cụm (ví dụ `C1_attttt`, `C3_tataa`) và kết hợp cùng nhãn lớp (`class=+` hoặc `class=-`) để tạo thành một giao dịch (transaction).
* **Lý do lựa chọn:**
* *Khắc phục sự dịch chuyển vị trí:* Trong tự nhiên, cùng một tín hiệu nhận diện có thể xê dịch 1–2 vị trí giữa các chuỗi khác nhau. Nếu dùng tọa độ điểm cố định, sự xê dịch này sẽ làm đứt gãy mẫu; việc dùng $k$-mer trong vùng cụm giúp bắt trọn đoạn mã bất kể sự dịch chuyển nhỏ.
* *Tối ưu kích thước `k = 5`:* Cụm ngắn nhất là `C2` có độ dài 8 ký tự, nên `k = 5` vừa đủ sinh nhiều cửa sổ trượt trong mọi cụm, vừa nắm bắt được lõi bảo tồn 5–6 ký tự của các vùng điều hòa.



### Bước 3: Khai phá tập phổ biến đóng có giám sát bằng CHARM

* **Cách thực hiện:** Chuyển đổi tập giao dịch sang biểu diễn bit dọc và chạy thuật toán **CHARM** với ngưỡng hỗ trợ tối thiểu **`minsup = 5`** (tương đương ~9,4% số mẫu của mỗi lớp).
* **Lý do lựa chọn:**
* *Loại bỏ dư thừa tổ hợp:* Khi trượt cửa sổ $k$-mer trên chuỗi, các đoạn gối đầu lên nhau luôn cùng xuất hiện trong một tập bản ghi. Khai phá tập phổ biến thông thường sẽ sinh ra hàng loạt tập con trùng lặp, trong khi **CHARM** chỉ giữ lại các **tập phổ biến đóng (Closed Itemsets)**—tự động gom các $k$-mer có cùng tập bản ghi hỗ trợ thành một tổ hợp hoàn chỉnh duy nhất mà không làm mất thông tin tần suất.
* *Cân bằng độ nhạy tại `minsup = 5`:* Đủ thấp để không bỏ sót các biến thể trình tự có đột biến điểm, nhưng đủ cao để loại bỏ các 5-mer trùng hợp ngẫu nhiên.



### Bước 4: Lọc tương phản, ghép chuỗi đồng thuận & đo khoảng cách không gian

* **Cách thực hiện:** Đối chiếu các tập đóng tìm được lên toàn bộ 106 chuỗi gốc để tính các thước đo phân biệt (**Confidence**, **Lift**, **Growth Rate**, kiểm định **$\chi^2$**). Sau đó, áp dụng thuật toán ghép nối gối đầu (*greedy overlap assembly*) để ráp các 5-mer trong cùng cụm thành chuỗi dài hoàn chỉnh, đồng thời đo khoảng cách tọa độ trung bình (`mean_span_bp`) giữa các cụm khác nhau.
* **Lý do lựa chọn:** Tần suất xuất hiện cao chưa chắc đã là đặc trưng riêng của Promoter. Bộ lọc thống kê (`Confidence >= 0,85`, `Growth Rate >= 3,0`, $p < 0,05$) giúp cô lập các mẫu thực sự phân biệt được hai lớp, còn bước ghép chuỗi và đo khoảng cách giúp khôi phục cấu trúc hoàn chỉnh dễ đọc thay vì các mảnh rời rạc.

---

## 4. Kết quả thực nghiệm

### 4.1. Thống kê tổng quan quá trình khai phá

* **Tổng số tập phổ biến đóng thu được từ CHARM:** **154 mẫu**, trong đó có **52 mẫu gắn nhãn `class=+**` và **27 mẫu gắn nhãn `class=-**` (các mẫu còn lại là mẫu nền chung không gắn nhãn lớp).
* **Sau bước lọc tương phản thống kê:** Đánh giá 128 tổ hợp motif duy nhất, thu được **40 mẫu đạt chuẩn phân biệt cao** (`Confidence >= 0,85`, `Growth Rate >= 3,0`, $p < 0,05$).

### 4.2. Bảng các mẫu đặc trưng tiêu biểu nhất cho Promoter (`class=+`)

| Phạm vi mẫu | Chuỗi đồng thuận sau ghép nối | Tần suất (`+` / `-`) | Confidence | Lift | Growth Rate | $p$-value | Tỷ lệ `A+T` | Khoảng cách trung bình |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Nội cụm `C3` | `C3:aatgcgc` | 9 / 0 | 1,00 | 2,00x | $\infty$ | 0,0017 | 40,0% | — |
| Nội cụm `C3` | `C3:ataatgc` | 8 / 0 | 1,00 | 2,00x | $\infty$ | 0,0033 | 80,0% | — |
| Nội cụm `C3` | `C3:tataatgc` | 7 / 0 | 1,00 | 2,00x | $\infty$ | 0,0062 | 85,0% | — |
| Nội cụm `C3` | `C3:tataatgcgc` | 6 / 0 | 1,00 | 2,00x | $\infty$ | 0,0117 | 66,7% | — |
| Nội cụm `C3` | `C3:cctataatgcgcc` (13 bp) | 5 / 0 | 1,00 | 2,00x | $\infty$ | 0,0220 | 60,0% | — |
| Xuyên cụm `C1+C3` | `C1:attttt` + `C3:aatgc` | 5 / 0 | 1,00 | 2,00x | $\infty$ | 0,0220 | 80,0% | **34,4 bp** |

---

## 5. Giải thích ý nghĩa các kết quả đạt được

1. **Sự chênh lệch số lượng mẫu giữa hai lớp (`52` vs. `27`):**
Dù số lượng chuỗi đầu vào của hai lớp bằng nhau (53 và 53), số tập phổ biến đóng của lớp Promoter lại cao gần gấp đôi. Điều này phản ánh **tính cấu trúc chặt chẽ**: các vùng khởi động phiên mã bắt buộc phải duy trì những khuôn mẫu chung để bộ máy tế bào nhận diện được, trong khi các vùng Non-promoter phân bố tự do và ngẫu nhiên hơn nên ít tạo thành cụm lặp lại.
2. **Tái khám phá chính xác vùng tín hiệu cốt lõi tại cụm `C3` (`tataat` và `gcgcc`):**
* Toàn bộ các mẫu đứng đầu bảng đều đạt **`Confidence = 1,00`** và **`Growth Rate = ∞`** (xuất hiện 5–9 lần ở Promoter nhưng **0 lần** ở Non-promoter), mang lại độ nâng tối đa **`Lift = 2,00x`**.
* Thuật toán ghép nối đã tự động khôi phục chuỗi **`tataat`** (nằm trong `C3:tataatgc` với tỷ lệ `A+T = 85%` và chuỗi dài `C3:cctataatgcgcc`). Trong sinh học, `TATAAT` chính là **hộp `-10` (Pribnow box)** kinh điển—vùng giàu cặp `A=T` có liên kết yếu giúp enzyme dễ dàng tách đôi hai mạch DNA để bắt đầu đọc gene. Ngay liền kề phía sau là cụm giàu `G/C` (`gcgcc`) đóng vai trò ổn định phức hệ khởi động tại điểm `+1`.


3. **Phát hiện quy luật liên kết tầm xa giữa hai cụm (`C1:attttt + C3:aatgc`):**
* Mẫu xuyên cụm này chứng minh sự phối hợp giữa hai vùng tách biệt: dải ký tự giàu `A/T` liên tiếp (`attttt`) ở đầu cụm `C1` (vùng yếu tố tăng cường ngược dòng giúp tăng ái lực bám của enzyme) và cụm `aatgc` ở vùng `-10`.
* Khoảng cách đo được giữa hai cụm là **`34,4 bp`**—khớp với cấu trúc hình học thực tế của phân tử DNA khi hai vị trí này cùng tiếp xúc với các tiểu đơn vị của bộ máy phiên mã.


4. **Ảnh hưởng của tính suy biến trình tự lên các biến thể khác:**
Một vùng nhận diện quan trọng khác ở cụm `C1` (quanh vị trí `-35`, chuỗi chuẩn `TTGACA`) thường xuất hiện dưới nhiều biến thể đột biến điểm (`ttgact`, `ttgacg`, `ctgaca`...). Do dùng khớp chuỗi chính xác từng 5-mer, các biến thể này bị chia nhỏ tần suất xuống mức 2–4 lần (nằm ngay dưới ngưỡng `minsup = 5`), cho thấy tiềm năng mở rộng pipeline bằng cách gom cụm các chuỗi tương đồng gần (khoảng cách Hamming $\le 1$) để tăng độ phủ nhận diện.