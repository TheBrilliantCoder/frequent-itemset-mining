# CHARM Implementation Contract v2.0 (Julia Edition)

**Status:** Proposed — Freeze trước khi chia nhánh triển khai.  
**Mục tiêu:** Tái lập thuật toán CHARM khai phá **frequent closed itemsets (FCI)** từ cơ sở dữ liệu giao dịch bằng **Julia**, tận dụng cấu trúc `BitSet` tối ưu hiệu năng bộ nhớ và vi xử lý, cam kết kết quả tất định, kiểm thử chéo toàn diện.  
**Scope v2:** Vertical **tidset** triển khai qua `BitSet`; `minsup` là **số giao dịch tuyệt đối**; item là `String`; TID nội bộ là `Int` (quy ước **1-based index** chuẩn Julia).

---

## 1. Quy ước Chung (Bắt buộc)

1. **Transaction & TID:**
   - Mỗi transaction là một tập item: item lặp trong cùng một transaction chỉ tính một lần.
   - Giữ transaction trùng lặp ở các dòng khác nhau (tính là các transaction độc lập với TID riêng biệt).
   - TID nội bộ là chỉ số dòng hợp lệ theo chuẩn Julia (**1-based indexing**, từ $1$ đến $N$).
2. **Định dạng dữ liệu vào:**
   - **TXT:** Mỗi dòng không rỗng là một transaction; các item cách nhau bằng khoảng trắng (whitespace). Dòng rỗng tự động bỏ qua.
   - **CSV:** Bắt buộc có header `tid,items`. Mỗi dòng là một transaction; cột `items` chứa danh sách item cách nhau bằng whitespace; `tid` bên ngoài chỉ là nhãn định danh, không dùng làm chỉ số tính toán.
   - Item rỗng hoặc chứa khoảng trắng không hợp lệ; chuỗi item phân biệt hoa/thường (`"Apple" != "apple"`).
3. **Định nghĩa toán học & Cắt tỉa:**
   - $\text{support}(X) = |t(X)|$ với $t(X)$ là `BitSet` các TID chứa $X$.
   - `minsup` là `Int` thuộc khoảng $[1, N]$. Nếu dữ liệu rỗng hoặc $N = 0$, pipeline trả về `[]`.
   - Chỉ khai phá **itemset khác rỗng** ($\text{items} \neq \emptyset$).
   - Một itemset $X$ được gọi là **phổ biến (frequent)** nếu $\text{support}(X) \ge \text{minsup}$.
   - Một itemset $X$ được gọi là **đóng (closed)** nếu **không tồn tại** itemset cha thực sự $Y \supset X$ sao cho $\text{support}(Y) = \text{support}(X)$.
4. **Bất biến và Tính xác định (Immutability & Determinism):**
   - Kiểu `ITPair` và `ClosedItemset` là struct bất biến về ngữ nghĩa.
   - Không phụ thuộc vào thứ tự duyệt ngẫu nhiên của `Dict` hay `Set`. Toàn bộ danh sách nút và kết quả đầu ra phải được chuẩn hóa theo thứ tự từ điển rõ ràng.

---

## 2. Cấu trúc Package và Phân công Trách nhiệm

```text
CharmMining/
├── Project.toml
├── src/
│   ├── CharmMining.jl       # Module root: gom và export API
│   ├── models.jl            # Model chung: structs & invariants (Freeze trước)
│   ├── data.jl              # Lead: Người 1 | Phối hợp: Người 2
│   ├── ordering.jl          # Lead: Người 2 | Phối hợp: Người 1
│   ├── properties.jl        # Lead: Người 2 | Phối hợp: Người 3
│   ├── repository.jl        # Lead: Người 3 | Phối hợp: Người 2
│   ├── engine.jl            # Lead: Người 2 | Phối hợp: Người 3
│   └── pipeline.jl          # Lead: Người 1 | Phối hợp: Người 3
└── test/
    ├── runtests.jl          # Test orchestrator
    ├── test_data.jl         # Người 1
    ├── test_ordering.jl     # Người 2
    ├── test_properties.jl   # Người 2 & 3
    ├── test_repository.jl   # Người 3
    ├── test_engine.jl       # Người 2 & 3
    └── test_oracle.jl       # Cả 3 người (Fuzzing 100 datasets)
```

---

## 3. Public API & Type Contract

### 3.1 `src/models.jl` — Dùng chung (Cả nhóm chốt trước)

```julia
module Models

export Item, Tid, Itemset, Tidset, VerticalDB, ITPair, ClosedItemset, support

const Item = String
const Tid = Int
const Itemset = Set{Item}
const Tidset = BitSet
const VerticalDB = Dict{Item, Tidset}

"""
    ITPair(items, tids)
Đại diện cặp (Itemset, Tidset). Bất biến ngữ nghĩa.
"""
struct ITPair
    items::Itemset
    tids::Tidset

    function ITPair(items::Itemset, tids::Tidset)
        @assert !isempty(items) "Itemset không được rỗng"
        new(items, tids)
    end
end

support(node::ITPair)::Int = length(node.tids)

"""
    ClosedItemset(items, support)
Tập phổ biến đóng xuất ra pipeline. `items` luôn được sort tăng dần theo thứ tự từ điển.
"""
struct ClosedItemset
    items::Vector{Item}
    support::Int

    function ClosedItemset(items::Vector{Item}, supp::Int)
        @assert issorted(items) "items phải được sắp xếp từ điển"
        new(items, supp)
    end
end

end # module Models
```

### 3.2 `src/data.jl` — Người 1 (Người 2 phối hợp)

```julia
module Data

using ..Models

export load_transactions, to_vertical, frequent_singletons

"""
Đọc file TXT/CSV trả về danh sách transaction.
TID tự động gán từ 1 đến N theo số dòng hợp lệ.
"""
function load_transactions(path::AbstractString; fmt::Symbol = :txt)::Vector{Vector{Item}} end

"""
Chuyển đổi danh sách transaction sang VerticalDB dạng Dict{Item, BitSet}.
"""
function to_vertical(transactions::Vector{Vector{Item}})::VerticalDB end

"""
Lọc các item có |tids| >= minsup và bọc vào ITPair.
Bắt buộc gọi trực tiếp `ordering_key` từ Người 2 để trả về danh sách được sắp xếp chuẩn.
"""
function frequent_singletons(db::VerticalDB, minsup::Int, sort_fn::Function)::Vector{ITPair} end

end # module Data
```

### 3.3 `src/ordering.jl` — Người 2 (Người 1 phối hợp)

```julia
module Ordering

using ..Models

export ordering_key, order_itemsets

"""
Khóa sắp xếp: support tăng dần; nếu hòa thì so sánh vector item đã sort theo từ điển.
"""
function ordering_key(node::ITPair)::Tuple{Int, Vector{Item}}
    return (support(node), sort!(collect(node.items)))
end

"""
Sắp xếp mảng ITPair theo quy tắc tất định, không làm biến đổi mảng đầu vào.
"""
function order_itemsets(nodes::Vector{ITPair})::Vector{ITPair}
    return sort(nodes, by = ordering_key)
end

end # module Ordering
```

### 3.4 `src/properties.jl` — Người 2 (Người 3 phối hợp)

```julia
module Properties

using ..Models

export CharmRelation, EQUAL, LEFT_SUBSET, RIGHT_SUBSET, INCOMPARABLE,
       classify_relation, combine_nodes

@enum CharmRelation begin
    EQUAL          # t(X) == t(Y)
    LEFT_SUBSET    # t(X) ⊊ t(Y)
    RIGHT_SUBSET   # t(X) ⊋ t(Y)
    INCOMPARABLE   # Không bao hàm nhau
end

"""
Phân loại quan hệ giữa hai Tidset (BitSet).
"""
function classify_relation(tx::BitSet, ty::BitSet)::CharmRelation
    if tx == ty
        return EQUAL
    elseif issubset(tx, ty)
        return LEFT_SUBSET
    elseif issubset(ty, tx)
        return RIGHT_SUBSET
    else
        return INCOMPARABLE
    end
end

"""
Sinh nút kết hợp: items = X.items ∪ Y.items; tids = X.tids ∩ Y.tids.
"""
function combine_nodes(x::ITPair, y::ITPair)::ITPair
    return ITPair(union(x.items, y.items), intersect(x.tids, y.tids))
end

end # module Properties
```

### 3.5 `src/repository.jl` — Người 3 (Người 2 phối hợp)

```julia
module Repository

using ..Models

export ClosedItemsetRepository, consider!, results

"""
Repository lưu trữ Closed Itemsets sử dụng 2 cấp bucket:
Cấp 1: Support (Int)
Cấp 2: Checksum hash của Tidset (UInt64) -> Vector{ITPair}
"""
mutable struct ClosedItemsetRepository
    buckets::Dict{Int, Dict{UInt64, Vector{ITPair}}}
    ClosedItemsetRepository() = new(Dict{Int, Dict{UInt64, Vector{ITPair}}}())
end

function tid_checksum(tids::BitSet)::UInt64
    acc = UInt64(0)
    for tid in tids
        acc = acc ⊻ hash(tid)
    end
    return acc
end

"""
Kiểm tra xem candidate có bị subsumed không:
- Trả về false nếu đã tồn tại superset có cùng support.
- Nếu không bị subsumed, chèn candidate và xóa các subset cũ có cùng support, trả về true.
"""
function consider!(repo::ClosedItemsetRepository, candidate::ITPair)::Bool end

"""
Trả về danh sách ClosedItemset theo thứ tự chuẩn (-support, items từ điển).
"""
function results(repo::ClosedItemsetRepository)::Vector{ClosedItemset} end

end # module Repository
```

### 3.6 `src/engine.jl` — Người 2 (Người 3 phối hợp)

```julia
module Engine

using ..Models
using ..Ordering
using ..Properties
using ..Repository

export run_charm

"""
Điều phối thuật toán CHARM: tạo repository, mở rộng nhánh tìm kiếm qua CHARM-Extend.
"""
function run_charm(db::VerticalDB, minsup::Int; repo::Union{ClosedItemsetRepository, Nothing} = nothing)::Vector{ClosedItemset} end

end # module Engine
```

### 3.7 `src/pipeline.jl` — Người 1 (Người 3 phối hợp)

```julia
module Pipeline

using ..Models
using ..Data
using ..Ordering
using ..Engine
using ..Repository

export mine_file

"""
Pipeline khép kín: Đọc file -> To Vertical -> run_charm -> Xuất JSON/CSV.
"""
function mine_file(
    input_path::AbstractString;
    minsup::Int,
    input_format::Symbol = :txt,
    output_path::Union{AbstractString, Nothing} = nothing,
    output_format::Symbol = :json
)::Vector{ClosedItemset} end

end # module Pipeline
```

---

## 4. Mã giả Chi tiết Thuật toán (Pseudocode)

### Thuật toán 1: `RUN_CHARM(D, minsup)`

```text
Input:  D (VerticalDB: Item -> BitSet), minsup (Int >= 1)
Output: Res (Danh sách ClosedItemset đã sắp xếp)

1:  If D is empty or minsup <= 0 then:
2:      Return []
3:  End If
4:
5:  Nodes ← []
6:  For each (item, tids) in D do:
7:      If |tids| >= minsup then:
8:          Nodes.append(ITPair({item}, tids))
9:      End If
10: End For
11:
12: // Sắp xếp tăng dần theo support, giải hòa bằng thứ tự từ điển của item
13: Nodes ← ORDER_ITEMSETS(Nodes)
14:
15: Repo ← ClosedItemsetRepository()
16: CHARM_EXTEND(Nodes, Repo, minsup)
17:
18: Return Repo.RESULTS()
```

### Thuật toán 2: `CHARM_EXTEND(Nodes, Repo, minsup)`

```text
Input:  Nodes (Vector of ITPair), Repo (ClosedItemsetRepository), minsup (Int)

1:  n ← length(Nodes)
2:  For i ← 1 to n do:
3:      X ← Nodes[i]
4:      If X is null then continue    // Đã bị loại bỏ bởi Property 1
5:      
6:      NewNodes ← []
7:      j ← i + 1
8:      While j <= n do:
9:          Y ← Nodes[j]
10:         If Y is null then:
11:             j ← j + 1
12:             continue
13:         End If
14:         
15:         t_inter ← X.tids ∩ Y.tids    // Phép AND bitwise giữa hai BitSet
16:         supp_inter ← |t_inter|
17:         
18:         If supp_inter >= minsup then:
19:             rel ← CLASSIFY_RELATION(X.tids, Y.tids)
20:             
21:             // --- Case 1: Property 1 (t(X) == t(Y)) ---
22:             If rel == EQUAL then:
23:                 X.items ← X.items ∪ Y.items
24:                 Nodes[j] ← null       // Loại bỏ Y khỏi nhánh hiện tại
25:                 For each Node in NewNodes do:
26:                     Node.items ← Node.items ∪ Y.items
27:                 End For
28:                 
29:             // --- Case 2: Property 2 (t(X) ⊂ t(Y)) ---
30:             Else If rel == LEFT_SUBSET then:
31:                 X.items ← X.items ∪ Y.items
32:                 For each Node in NewNodes do:
33:                     Node.items ← Node.items ∪ Y.items
34:                 End For
35:                 // Y vẫn giữ nguyên
36:                 
37:             // --- Case 3: Property 3 (t(X) ⊃ t(Y)) ---
38:             Else If rel == RIGHT_SUBSET then:
39:                 NewNodes.append(ITPair(X.items ∪ Y.items, t_inter))
40:                 // X và Y vẫn giữ nguyên
41:                 
42:             // --- Case 4: Property 4 (Incomparable) ---
43:             Else:
44:                 NewNodes.append(ITPair(X.items ∪ Y.items, t_inter))
45:             End If
46:         End If
47:         
48:         j ← j + 1
49:     End While
50:     
51:     If !isempty(NewNodes) then:
52:         NewNodes ← ORDER_ITEMSETS(NewNodes)
53:         CHARM_EXTEND(NewNodes, Repo, minsup)
54:     End If
55:     
56:     // Đưa X vào Repository để kiểm tra bao hàm (subsumption)
57:     Repo.CONSIDER(X)
58: End For
```

### Thuật toán 3: `CONSIDER(candidate, Repo)`

```text
Input:  candidate (ITPair: items, tids), Repo
Output: Boolean (true nếu candidate được ghi nhận, false nếu bị subsumed)

1:  supp ← |candidate.tids|
2:  chk ← TID_CHECKSUM(candidate.tids)
3:  
4:  TargetBucket ← Repo.buckets[supp][chk]
5:  
6:  // Bước 1: Kiểm tra xem candidate có bị bao hàm bởi tập nào đã có không
7:  For each existing in TargetBucket do:
8:      If candidate.items ⊆ existing.items then:
9:          Return false    // Bị subsumed: không đóng, loại bỏ
10:     End If
11: End For
12: 
13: // Bước 2: Kiểm tra xem candidate có thay thế tập con cũ nào không
14: ToRemove ← []
15: For each existing in TargetBucket do:
16:     If existing.items ⊂ candidate.items then:
17:         ToRemove.append(existing)
18:     End If
19: End For
20: Remove all ToRemove from TargetBucket
21: 
22: // Bước 3: Thêm candidate vào bucket
23: TargetBucket.append(candidate)
24: Return true
```

---

## 5. Ma trận Nhiệm vụ Liên kết Chéo (Interdependent Workflow)

```
        [Người 1: Pipeline & Data]
               ▲          ▲
   (BitSet DB) │          │ (Results Contract)
               ▼          ▼
    [Người 2: Engine] ◄────► [Người 3: Repository]
            (consider! callback)
```

| Người | Module Trách Nhiệm Chính | Module Đồng Hành & Phụ Thuộc | Cơ Chế Bàn Giao & Kiểm Tra Chéo (Handshake) |
|---|---|---|---|
| **Người 1** | `src/data.jl`<br>`src/pipeline.jl`<br>`test/test_data.jl` | Phụ thuộc: `src/models.jl`, `src/ordering.jl`<br>Đồng hành: `test/test_oracle.jl` | **Interface 1 ↔ 2:** `frequent_singletons` phải dùng trực tiếp `ordering_key` của Người 2 để sắp xếp singletons.<br>**Interface 1 ↔ 3:** Pipeline tiếp nhận `results(repo)` để xuất JSON/CSV theo định dạng chuẩn hóa. |
| **Người 2** | `src/ordering.jl`<br>`src/properties.jl`<br>`src/engine.jl` | Phụ thuộc: `src/models.jl`, `src/repository.jl`<br>Đồng hành: `test/test_properties.jl` | **Interface 2 ↔ 3:** `engine.jl` gọi `consider!` của Người 3 sau mỗi bước duyệt. Người 2 và Người 3 cùng pair-programming viết unit test cho 4 tính chất (Properties 1–4). |
| **Người 3** | `src/repository.jl`<br>`test/test_properties.jl`<br>`test/test_repository.jl`<br>`test/test_oracle.jl` | Phụ thuộc: `src/models.jl`, `src/properties.jl`<br>Đồng hành: `src/engine.jl` | **Interface 3 ↔ 2:** Đảm bảo `consider!` không bị miss khi xảy ra va chạm hash checksum của `BitSet`. Người 3 viết Test Oracle độc lập để fuzzing kết quả của Người 2. |

---

## 6. Bộ Test Tích hợp & Expected Output Chuẩn

### Test Case 1: Dữ liệu Cơ bản

**Input TXT:**
```text
A B C
A C
B C
A B
```

**Biểu diễn VerticalDB:**
- `A` $\rightarrow \{1, 2, 4\}$
- `B` $\rightarrow \{1, 3, 4\}$
- `C` $\rightarrow \{1, 2, 3\}$

Với `minsup = 2`, kết quả chuẩn hóa từ điển qua JSON:
```json
[
  {"items": ["A"], "support": 3},
  {"items": ["B"], "support": 3},
  {"items": ["C"], "support": 3},
  {"items": ["A", "B"], "support": 2},
  {"items": ["A", "C"], "support": 2},
  {"items": ["B", "C"], "support": 2}
]
```

### Test Case 2: Kiểm tra Tính Đóng (Subsumption Case)

**Input TXT:**
```text
A B
A B
A
```

Với `minsup = 2`:
- `A` xuất hiện 3 lần $\rightarrow \text{support} = 3$ (Closed vì không có tập cha nào có support = 3).
- `B` xuất hiện 2 lần $\rightarrow \text{support} = 2$. Nhưng $AB$ xuất hiện 2 lần $\rightarrow \text{support} = 2$.
- Vì $B \subset AB$ và $\text{support}(B) = \text{support}(AB) = 2$, tập $B$ **không đóng** và phải bị `consider!` loại bỏ.
- **Output:** Chỉ có `[{"items": ["A"], "support": 3}, {"items": ["A", "B"], "support": 2}]`.

### Test Case 3: Oracle Verification (Fuzzing 100 Bộ Dữ liệu)

- Tạo ngẫu nhiên 100 cơ sở dữ liệu nhỏ (tối đa 8 item, 20 transactions).
- Thuật toán Brute-force Oracle độc lập: Duyệt toàn bộ $2^k - 1$ tập item, đếm support trên mảng transaction thô, lọc tập thỏa mãn $\ge \text{minsup}$, sau đó loại bỏ các tập con có tập cha cùng support.
- Khẳng định: $\text{Set}(\text{CHARM Output}) \equiv \text{Set}(\text{Oracle Output})$.

---

## 7. Quy trình Tích hợp và Definition of Done (DoD)

1. **Chuẩn mã nguồn:**
   - Hoàn toàn viết bằng **Julia 1.10+**.
   - Type annotations tường minh cho toàn bộ public functions.
   - Không phân bổ thừa bộ nhớ (sử dụng in-place `intersect!` hoặc tái sử dụng bộ đệm `BitSet` khi có thể).
2. **Tiêu chuẩn hoàn thành (DoD):**
   - Mọi test suite (`test_data.jl`, `test_ordering.jl`, `test_properties.jl`, `test_repository.jl`, `test_oracle.jl`) đều đạt 100% green (`Pkg.test()`).
   - CLI hoạt động trơn tru:
     ```bash
     julia --project -e 'using CharmMining; mine_file("data.txt", minsup=2, output_path="out.json")'
     ```
   - Không có tập closed itemset bị trùng lặp trong file kết quả xuất ra.
3. **Thứ tự Merge Branch:**
   1. `main` khởi tạo `models.jl` + test fixtures ban đầu.
   2. Branch `feat/data` (Người 1) và `feat/ordering-props` (Người 2) tích hợp song song.
   3. Branch `feat/repository` (Người 3) merge sau khi pass unit test va chạm bucket.
   4. Branch `feat/engine` (Người 2 + 3) kết nối duyệt nhánh và kho lưu trữ.
   5. Branch `feat/pipeline` (Người 1 + 3) hoàn thiện CLI, benchmark và Oracle test suite.