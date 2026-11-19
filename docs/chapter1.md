# CHAPTER 1: IMPLEMENTATION

## PREREQUISITE

- Choose a FIM algorithm from [here](https://www.philippe-fournier-viger.com/spmf/index.php?link=algorithms.php).
- Find the original paper about chosen algorithm. [original paper here](https://www.researchgate.net/publication/220907052_CHARM_An_efficient_algorithm_for_Closed_Itemset_Mining)
- Find 5 different datasets from [here](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php#d2).

Note:

   *If later teacher want us to host data in Hugging Face or Kaggle,
   we zip these datasets and upload zip file on Kaggle.
   We also need a script to help teacher retrieve and unzip dataset before running notebook*

## TASKS TO DO

1. Implement algorithm **correctly**:
   - [x] Output all FI and corresponding supports
   - [x] Output matches results against SPMF version given the same input

2. **Reproduce** the output:
   - [x] Automation test
   - [x] Run in at least 5 different datasets/databases
   - [x] Report identical rate against the SPMF version

3. Optimize **memory and speed**:
   - [ ] Apply at least 1 optimization technique to algorithm
   - [ ] Evaluate and report any improvements compared against the basic version - the one we manually implement

4. **Input & output** processing:
   - [x] Input as `.txt` file with the structure based on SPMF:
     - Each line represents one transaction (or itemset).
     - Items are represented by positive integers (or sometimes strings), separated by a single space.
     - Items inside a line are usually sorted in ascending order.
   - [x] Output should be formatted like this:

     ```text
     1 2 #SUP: 2
     1 #SUP: 3
     2 4 #SUP: 2
     ```

   - [ ] Must allow command arguments, something like this:

     ```bash
     python main.py --input input.txt --output output.txt --minsup 2
      ```

## Optimization Technique: Contiguous `BitVector` Representation with 64-bit XOR Closed Hashing

To accelerate execution speed and reduce memory footprint without relying on `diffset` structures, the optimized implementation (`src/optimized/`) introduces a cohesive data-structure overhaul: replacing dynamic sets with **contiguous 64-bit register-aligned bit arrays (`BitVector`)** paired with a **collision-resistant 64-bit XOR closed hash table**.

### 1. Core Architectural Mechanisms

- **Contiguous Bit-Array `Tidset` (`FastBitTidset`):** Instead of using Julia's dynamic offset `BitSet`, each `Tidset` is represented as a fixed-length one-dimensional `BitVector` of size $N$ (total transactions), stored contiguously in memory as an array of 64-bit machine words (`Vector{UInt64}`). Set intersections $T(X) \cap T(Y)$ are executed via bitwise `AND` operations annotated with `@inbounds @simd` and hardware population count instructions (`count_ones`), reducing intersection complexity from $O(|T(X)| + |T(Y)|)$ to $O(N / 64)$. The support count (`supp`) is cached upon initialization for $O(1)$ retrieval.
- **64-bit Multiplicative XOR Closed Hash Table (`calc_bit_checksum`):** To prevent hash collisions caused by the baseline's transaction-ID sum checksum ($\sum \text{tid}$) on large datasets, the secondary hash key in `FastRepository` is computed directly over the 64-bit chunks $w_i$ of the `BitVector` using Knuth's multiplicative constants and bitwise `XOR` mixing:
  $$H(T(X)) = \bigoplus_{i=1}^{\lceil N/64 \rceil} \left( w_i \times \text{0x9e3779b97f4a7c15} + i \times \text{0x517cc1b727220a95} \right)$$
  This leverages the contiguous bit-word layout to distribute hash keys uniformly and eliminate false bucket collisions during subsumption checking.

### 2. Accompanying Implementation Refinements

To fully unlock the throughput of `BitVector` operations and eliminate auxiliary bottlenecks present in the baseline implementation, three low-level refinements are integrated:

- **Two-Phase Zero-Allocation Pruning & Reference Reuse (`charm_property_bit`):** Unlike the baseline `charm_property`, which eagerly allocates an intersection `Tidset` prior to checking the `minsup` threshold, `charm_property_bit` first accumulates `count_ones(ca[k] & cb[k])` in CPU registers. If the resulting support is below `minsup`, the branch is pruned immediately with **zero heap allocations**. When frequent, the candidate node directly reuses the existing `FastBitTidset` reference for Property 1 (`EQUAL`), Property 2 (`LEFT_SUBSET`), and Property 3 (`RIGHT_SUBSET`), allocating a new `BitVector` strictly for Property 4 (`INCOMPARABLE`). Similarly, `compute_f2_weights` computes frequent 2-itemset ($F_2$) weights in registers without instantiating intermediate `ITPair` objects.
- **Lexicographically Ordered `Int32` Itemsets (`FastITNode`):** String items (`Set{String}`) in the baseline incur recurring string-hashing and sorting overhead during union and subset checks. During vertical database construction (`to_vertical_bit`), unique items are sorted lexicographically once and mapped to dense `Int32` identifiers ($1 \dots M$). Maintaining each `Itemset` as a sorted `Vector{Int32}` enables linear $O(|A| + |B|)$ two-pointer `sorted_union` and `sorted_issubset` operations without hashing.
- **In-Place Subsumption Pruning (`consider_bit!`):** Before checking subset inclusion in `FastRepository`, candidates are filtered in $O(1)$ by itemset length. When a newly inserted closed itemset strictly subsumes existing entries in the same hash bucket, those entries are removed in-place via an $O(1)$ swap-and-pop operation rather than allocating a new array via `filter!`.