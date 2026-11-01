Phân tích luồng chính cần làm
Chia việc
Viết report

---
1. Implement cách sắp xếp thứ tự itemset (ordering func)
2. Subsumed check, kiểm tra X có phải tập con và có support = support cha : cơ chế: hash table
3. Implement, unit test cho Charm-property
4. Chuyển đổi từ tập data: tid - itemset -> verticle: item - tidset.
5. Pipeline xử lý input output

---

# TO-DO
| Thành viên                | Công việc chính                                                                                               | Đầu ra                                                               | Human | Deadline    |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ----- | ----------- |
| Người 1 – Data & Pipeline | Chuyển đổi dữ liệu từ horizontal sang vertical; xử lý input/output; Implement subsumed check bằng hash table; | Data loader, vertical database, pipeline CLI. Hash-based subsumption | Trúc  | 5/11-9/11   |
| Người 2 – CHARM Core      | Implement ordering function và 4 CHARM properties; xây dựng thuật toán duyệt đệ quy                           | CHARM engine hoàn chỉnh                                              | Lộc   | 5/11-9/11   |
| Người 3 – Testing         | unit test toàn bộ function <br>kiểm thử tự động toàn hệ thống                                                 | test suite, báo cáo kiểm thử                                         | Khải  | 10/11-12/11 |
