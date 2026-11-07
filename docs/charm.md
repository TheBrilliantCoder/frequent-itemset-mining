To implement the **CHARM** algorithm (using tidsets), the core architecture decomposes into **five essential functions/modules**:

1. **`CHARM` (Main Driver & Optimized Initialization)**
2. **`Order-Elements` (Ordering Function)**
3. **`CHARM-Extend` (Equivalence Class Search & Recursive Descent)**
4. **`CHARM-Property` (Candidate Intersection & Property Testing)**
5. **`Fast-Subsumption-Check` (Hash-based Subsumption Checking)**

---

### 1. `CHARM(D, minsup)` — Main Driver & Optimized Initialization
* **Purpose**: Coordinates the overall lifecycle, reads data vertically, performs 2-itemset precomputation, constructs the root equivalence class, and kicks off exploration.
* **Implementation Details**:
  1. **Vertical Database Scan**:
     * Scan database \\(D\\) to construct tidsets \\(t(x)\\) for each single item \\(x \in I\\).
     * Compute each item's support \\(\sigma(x) = |t(x)|\\) and discard any infrequent items (\\(\sigma(x) < minsup\\)).
  2. **Frequent 2-Itemsets (\\(F_2\\)) Pre-computation**:
     * To prevent evaluating all \\(\frac{n(n-1)}{2}\\) item pairs (many of which are infrequent), perform an on-the-fly vertical-to-horizontal conversion over chunks of transactions.
     * Count pair frequencies in an upper-triangular 2D array and record the set of all frequent pairs \\(F_2\\).
  3. **Root Class Construction**:
     * Form the root prefix equivalence class \\([P] = \{X_i \times t(X_i) : X_i \in I \wedge \sigma(X_i) \ge minsup\}\\).
     * Sort \\([P]\\) using the ordering function.
  4. **Invoke Exploration**:
     * Initialize closed set collection \\(\mathcal{C} = \emptyset\\) (stored as a hash table).
     * Call `CHARM-Extend([P], C)` and return \\(\mathcal{C}\\).

---

### 2. `Order-Elements([P])` — Ordering Function
* **Purpose**: Sorts items/IT-pairs in an equivalence class according to a total order \\(f\\) to maximize early pruning.
* **Implementation Details**:
  * **Heuristic (Increasing Support / Weight)**:
    * While elements can be sorted lexicographically, CHARM sorts elements in **increasing order of weight** (or support):
      \\[w(X) = \sum_{XY \in F_2} \sigma(XY)\\]
  * **Why It Is Implemented This Way**:
    * Sorting by increasing support ensures smaller tidsets come first, which maximizes the likelihood of **Property 1 (\\(t(X_i) = t(X_j)\\))** and **Property 2 (\\(t(X_i) \subset t(X_j)\\))** occurring.
    * Properties 1 and 2 replace \\(X_i\\) with \\(X_i \cup X_j\\) without inserting any new nodes into the child class \\([P_i]\\), effectively pruning and skipping search tree levels. (In contrast, decreasing support promotes Properties 3 and 4, which bloats the tree).

---

### 3. `CHARM-Extend([P], C)` — Equivalence Class Search & Recursive Descent
* **Purpose**: Navigates the Itemset–Tidset tree (IT-tree) in a depth-first manner, systematically extending each IT-pair with downstream members of the class.
* **Implementation Details**:
  1. For each IT-pair \\(X_i \times t(X_i)\\) currently in \\([P]\\):
     * Allocate an empty child equivalence class \\([P_i] = \emptyset\\).
     * Initialize an accumulator variable \\(\mathbf{X} = X_i\\) to hold any closure extensions found along this branch.
  2. For each downstream partner \\(X_j \times t(X_j) \in [P]\\) with \\(X_j \ge_f X_i\\):
     * *(Optimization check)*: If at root level, only proceed if \\(X_i \cup X_j \in F_2\\).
     * Form the candidate union \\(\mathbf{X}' = X_i \cup X_j\\) and candidate tidset \\(\mathbf{Y} = t(X_i) \cap t(X_j)\\).
     * Call `CHARM-Property([P], [Pi], Xi, Xj, X, X', Y, minsup)`.
  3. **Recursive Step**:
     * If \\([P_i] \neq \emptyset\\), recursively invoke `CHARM-Extend([Pi], C)`.
     * Free memory for child class \\([P_i]\\) upon return (`delete [Pi]`).
  4. **Subsumption & Insertion**:
     * Call `Fast-Subsumption-Check(X, t(X), C)`.
     * If \\(\mathbf{X}\\) is not subsumed, insert \\(\mathbf{X}\\) into \\(\mathcal{C}\\).

---

### 4. `CHARM-Property([P], [Pi], ...)` — Candidate Intersection & Property Testing
* **Purpose**: Evaluates candidate support and applies the 4 fundamental IT-pair properties to prune redundant branches or accumulate itemset closures.
* **Implementation Details**:
  * **Support Check**: Evaluate \\(\sigma(\mathbf{X}') = |\mathbf{Y}|\\). If \\(|\mathbf{Y}| < minsup\\), return immediately (infrequent candidate).
  * If frequent, compare the tidsets \\(t(X_i)\\) and \\(t(X_j)\\):
    * **Property 1 (\\(t(X_i) == t(X_j)\\))**:
      * Both itemsets share identical closures (\\(c(X_i) = c(X_j) = c(X_i \cup X_j)\\)).
      * Remove \\(X_j\\) from \\([P]\\).
      * Replace all occurrences of \\(X_i\\) with \\(\mathbf{X} = \mathbf{X} \cup X_j\\) across \\([P]\\) and in existing child nodes of \\([P_i]\\).
      * *No node added to \\([P_i]\\)*.
    * **Property 2 (\\(t(X_i) \subset t(X_j)\\))**:
      * \\(c(X_i) = c(X_i \cup X_j) \neq c(X_j)\\).
      * Replace all occurrences of \\(X_i\\) with \\(\mathbf{X} = \mathbf{X} \cup X_j\\) in \\([P]\\) and \\([P_i]\\).
      * Retain \\(X_j\\) in \\([P]\\) (it generates a different closure).
      * *No node added to \\([P_i]\\)*.
    * **Property 3 (\\(t(X_i) \supset t(X_j)\\))**:
      * \\(c(X_j) = c(X_i \cup X_j) \neq c(X_i)\\).
      * Remove \\(X_j\\) from \\([P]\\).
      * Add \\(\mathbf{X}' \times \mathbf{Y}\\) to the child class \\([P_i]\\) in sorted order according to \\(f\\).
    * **Property 4 (\\(t(X_i) \neq t(X_j)\\))**:
      * \\(c(X_i) \neq c(X_j) \neq c(X_i \cup X_j)\\).
      * Neither itemset is removed; insert \\(\mathbf{X}' \times \mathbf{Y}\\) into \\([P_i]\\) sorted by \\(f\\).

---

### 5. `Fast-Subsumption-Check(X, t(X), C)` — Hash-Based Subsumption Checking
* **Purpose**: Verifies whether an itemset \\(\mathbf{X}\\) is already subsumed by an existing closed itemset in \\(\mathcal{C}\\) without an exhaustive \\(O(|\mathcal{C}|^2)\\) comparison.
* **Implementation Details**:
  1. **Hash Key Computation**:
     * Closed patterns in \\(\mathcal{C}\\) are maintained in a hash multimap indexed by the **sum of their transaction IDs**:
       \\[h(\mathbf{X}) = \sum_{T \in t(\mathbf{X})} T\\]
     * *(Note: \\(h(\mathbf{X})\\) is the arithmetic sum of IDs, not the set cardinality \\(\sigma(\mathbf{X})\\))*.
  2. **Lookup & Matching**:
     * Retrieve all closed entries \\(C \in \mathcal{C}\\) matching hash key \\(h(\mathbf{X})\\).
     * For each matched entry \\(C\\):
       * **Filter 1 (Support equality)**: Verify if \\(\sigma(\mathbf{X}) == \sigma(C)\\). If supports differ, skip.
       * **Filter 2 (Subset verification)**: If supports match, test if \\(\mathbf{X} \subset C\\).
       * If both conditions are satisfied, \\(\mathbf{X}\\) is non-closed (subsumed by \\(C\\)) \\(\rightarrow\\) return `True` (discard \\(\mathbf{X}\\)).
  3. **Store**:
     * If no entry subsumes \\(\mathbf{X}\\), insert \\((\mathbf{X}, \sigma(\mathbf{X}))\\) into the hash multimap under key \\(h(\mathbf{X})\\) \\(\rightarrow\\) return `False`.
