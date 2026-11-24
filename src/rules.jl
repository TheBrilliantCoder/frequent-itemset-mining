module Rules

using ..Models

export AssociationRule, ClosureSupportIndex, build_support_index, support_of,
       generate_rules, top_rules_by_lift

"""
    AssociationRule

Luật kết hợp `antecedent => consequent` được sinh trực tiếp từ tập phổ biến đóng
(Closed Frequent Itemsets) của thuật toán CHARM, kèm các độ đo chuẩn:
`support`, `confidence`, `lift`, `leverage`, và `conviction`.
"""
struct AssociationRule
    antecedent::Vector{Item}
    consequent::Vector{Item}
    support_count::Int
    support::Float64
    confidence::Float64
    lift::Float64
    leverage::Float64
    conviction::Float64
end

"""
    ClosureSupportIndex

Chỉ mục tra cứu chính xác support của mọi tập con phổ biến `X` từ tập các
Closed Frequent Itemsets `C` theo tính chất bao đóng Galois:
`supp(X) = supp(c(X)) = max { supp(C) | C in Closed, X ⊆ C }`.
"""
struct ClosureSupportIndex
    closed::Vector{ClosedItemset}
    exact::Dict{Vector{Item}, Int}
    item_to_closed::Dict{Item, Vector{Int}}
end

"""
Kiểm tra `a ⊆ b` trong O(|a| + |b|) khi cả hai vector đã sắp xếp tăng dần.
"""
function _sorted_issubset_str(a::Vector{Item}, b::Vector{Item})::Bool
    na = length(a)
    nb = length(b)
    na > nb && return false
    ia = 1
    ib = 1
    @inbounds while ia <= na && ib <= nb
        va = a[ia]
        vb = b[ib]
        if va == vb
            ia += 1
            ib += 1
        elseif va > vb
            ib += 1
        else
            return false
        end
    end
    return ia > na
end

"""
    build_support_index(closed_itemsets) -> ClosureSupportIndex

Xây dựng chỉ mục tra cứu support chính xác từ danh sách Closed Frequent Itemsets.
Các tập đóng được sắp xếp giảm dần theo support để phép tra cứu bao đóng dừng sớm
ngay tại tập đóng đầu tiên chứa `X`.
"""
function build_support_index(closed_itemsets::Vector{ClosedItemset})::ClosureSupportIndex
    sorted_closed = sort(
        closed_itemsets;
        by = c -> (-c.support, length(c.items), c.items)
    )
    exact = Dict{Vector{Item}, Int}()
    sizehint!(exact, length(sorted_closed) * 2)
    item_to_closed = Dict{Item, Vector{Int}}()

    for (idx, c) in enumerate(sorted_closed)
        exact[c.items] = c.support
        for item in c.items
            push!(get!(Vector{Int}, item_to_closed, item), idx)
        end
    end

    return ClosureSupportIndex(sorted_closed, exact, item_to_closed)
end

"""
    support_of(index::ClosureSupportIndex, items::Vector{Item}) -> Int

Trả về support chính xác của tập phổ biến `items` (đã sắp xếp tăng dần).
Nếu `items` không tự đóng, tra cứu bao đóng `c(items)` qua danh sách đảo ngược
đã sắp giảm dần theo support và lưu cache vào `index.exact`.
"""
function support_of(index::ClosureSupportIndex, items::Vector{Item})::Int
    isempty(items) && throw(ArgumentError("items must be non-empty"))
    cached = get(index.exact, items, 0)
    cached > 0 && return cached

    # Chọn item có danh sách chỉ mục ngắn nhất để quét tối thiểu
    best_list = get(index.item_to_closed, items[1], Int[])
    best_len = length(best_list)
    for k in 2:length(items)
        lst = get(index.item_to_closed, items[k], Int[])
        if length(lst) < best_len
            best_list = lst
            best_len = length(lst)
        end
    end

    for idx in best_list
        c = index.closed[idx]
        if length(c.items) >= length(items) && _sorted_issubset_str(items, c.items)
            index.exact[items] = c.support
            return c.support
        end
    end

    throw(KeyError("Itemset $(items) is not covered by any closed frequent itemset"))
end

"""
    generate_rules(closed_itemsets, n_transactions;
                   minconf=0.5, minlift=1.0,
                   max_antecedent_len=0, max_consequent_len=0,
                   max_itemset_len=10) -> Vector{AssociationRule}

Sinh luật kết hợp `A => B` từ tập phổ biến đóng `closed_itemsets` (với `A ∪ B = C`,
`A ≠ ∅`, `B ≠ ∅`), tính chính xác Support, Confidence, Lift, Leverage và Conviction
nhờ `ClosureSupportIndex`.
"""
function generate_rules(
    closed_itemsets::Vector{ClosedItemset},
    n_transactions::Int;
    minconf::Float64 = 0.5,
    minlift::Float64 = 1.0,
    max_antecedent_len::Int = 0,
    max_consequent_len::Int = 0,
    max_itemset_len::Int = 10
)::Vector{AssociationRule}
    n_transactions >= 1 || throw(ArgumentError("n_transactions must be >= 1"))
    0.0 <= minconf <= 1.0 || throw(ArgumentError("minconf must be in [0, 1]"))
    minlift >= 0.0 || throw(ArgumentError("minlift must be >= 0"))

    index = build_support_index(closed_itemsets)
    rules = AssociationRule[]
    inv_n = 1.0 / Float64(n_transactions)

    for c in closed_itemsets
        k = length(c.items)
        (k < 2 || k > max_itemset_len) && continue

        supp_ab_count = c.support
        supp_ab = supp_ab_count * inv_n
        full_mask = (1 << k) - 1

        for mask in 1:(full_mask - 1)
            a_len = count_ones(mask)
            b_len = k - a_len
            (max_antecedent_len > 0 && a_len > max_antecedent_len) && continue
            (max_consequent_len > 0 && b_len > max_consequent_len) && continue

            antecedent = Vector{Item}(undef, a_len)
            consequent = Vector{Item}(undef, b_len)
            ia = 1
            ib = 1
            @inbounds for bit in 0:(k - 1)
                if (mask & (1 << bit)) != 0
                    antecedent[ia] = c.items[bit + 1]
                    ia += 1
                else
                    consequent[ib] = c.items[bit + 1]
                    ib += 1
                end
            end

            supp_a_count = support_of(index, antecedent)
            conf = Float64(supp_ab_count) / Float64(supp_a_count)
            conf < minconf && continue

            supp_b_count = support_of(index, consequent)
            supp_a = supp_a_count * inv_n
            supp_b = supp_b_count * inv_n
            # Compute Lift symmetrically via integer products to prevent IEEE-754 1-ULP
            # asymmetry between (A => B) and (B => A) during tie-breaking by confidence.
            lift = Float64(supp_ab_count * n_transactions) / Float64(supp_a_count * supp_b_count)
            lift < minlift && continue

            leverage = supp_ab - supp_a * supp_b
            conviction = conf >= 1.0 ? Inf : (1.0 - supp_b) / (1.0 - conf)

            push!(rules, AssociationRule(
                antecedent, consequent,
                supp_ab_count, supp_ab, conf, lift, leverage, conviction
            ))
        end
    end

    sort!(rules; by = r -> (-r.lift, -r.confidence, -r.support_count, r.antecedent, r.consequent))
    return rules
end

"""
    top_rules_by_lift(rules, k=10; deduplicate_symmetric=false) -> Vector{AssociationRule}

Trích xuất top-`k` luật có chỉ số Lift cao nhất (sắp xếp giảm dần theo Lift, sau đó
Confidence và Support). Nếu `deduplicate_symmetric=true`, với các cặp luật đối xứng
cùng tập sản phẩm `{A ∪ B}`, chỉ giữ lại hướng có Confidence cao hơn.
"""
function top_rules_by_lift(
    rules::Vector{AssociationRule},
    k::Int = 10;
    deduplicate_symmetric::Bool = false
)::Vector{AssociationRule}
    k >= 0 || throw(ArgumentError("k must be non-negative"))
    sorted_rules = sort(
        rules;
        by = r -> (-r.lift, -r.confidence, -r.support_count, r.antecedent, r.consequent)
    )
    !deduplicate_symmetric && return sorted_rules[1:min(k, length(sorted_rules))]

    selected = AssociationRule[]
    seen_pairs = Set{Tuple{Vector{Item}, Vector{Item}}}()
    for r in sorted_rules
        pair_key = r.antecedent <= r.consequent ? (r.antecedent, r.consequent) : (r.consequent, r.antecedent)
        pair_key in seen_pairs && continue
        push!(seen_pairs, pair_key)
        push!(selected, r)
        length(selected) == k && break
    end
    return selected
end

end # module Rules
