# CHAPTER 2: EXPERIMENTAL EVALUATION & BENCHMARKING

## PREREQUISITE

- Select at least **4 benchmark datasets** from Chapter 1.
- Prepare baseline outputs and execution metrics from the official **SPMF library** (Java executable) on the same machine.
- Set up automated benchmarking scripts to track:
  - Execution time (wall-clock time)
  - Peak memory usage (RAM)
  - Output itemset validation counts


## TASKS TO DO

1. **Correctness Verification**:
   - [ ] Run both the group's implementation and SPMF on all 4 datasets across multiple `minsup` values.
   - [ ] Compare total frequent itemsets found and exact support values per itemset.
   - [ ] Report matching rate against SPMF version.
   - [ ] Document and analyze root causes if any discrepancies occur.

2. **Execution Time vs. Minimum Support (`minsup`)**:
   - [ ] Test each dataset across **5 to 7 decreasing `minsup` points** (from high to low minsup).
   - [ ] Record runtime for both the group's implementation and SPMF.
   - [ ] Plot runtime comparison curves (Group vs. SPMF) on the same graph per dataset.
   - [ ] Explain runtime trends based on algorithm time complexity and dataset density.

3. **Number of Frequent Itemsets vs. Minimum Support**:
   - [ ] Record output itemset counts across the tested `minsup` thresholds.
   - [ ] Plot the output size explosion curve as `minsup` decreases.
   - [ ] Explain relationships between output size and minsup on **dense datasets** and **sparse datasets**.

4. **Memory Consumption Evaluation**:
   - [ ] Measure peak RAM usage (MB) for each dataset at a median/average `minsup` threshold.
   - [ ] Compare peak memory between:
     - Basic implementation (Chapter 1)
     - Optimized implementation (Chapter 1)
     - SPMF reference baseline
   - [ ] Detail the concrete memory impact of the chosen optimization technique.

5. **Scalability Analysis**:
   - [ ] Choose a large dataset to partition into sub-databases of sizes: **10%, 25%, 50%, 75%, and 100%** of transactions.
   - [ ] Run the algorithm at a fixed `minsup` across all subsets.
   - [ ] Plot runtime vs. database size (transaction count).
   - [ ] Analyze whether scaling shows linear, polynomial, or exponential growth.

6. **Transaction Length Analysis (Optional / If Applicable)**:
   - [ ] Assess if the chosen algorithm is sensitive to average transaction width.
   - [ ] Generate synthetic transactional sets with increasing transaction lengths.
   - [ ] Plot performance impact and explain theoretical reasons.

7. **Analysis & Discussion**:
   - [ ] Identify strengths and performance bottlenecks of the group's implementation relative to SPMF.
   - [ ] Propose at least **2 concrete future optimization directions** grounded in theoretical analysis.


Note: save metrics, don't need plot

Truc: Execution time and Number of Itemset
Loc: Memory and scalable
Khai: 1 Optimize and propose 2 optimization

