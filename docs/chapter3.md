# CHAPTER 3: REAL-WORLD APPLICATIONS

## PREREQUISITE

- Select **2 applications** (1 chosen direction for each of the 2 problem themes):
  - **Application 1**: Market Basket Analysis / E-commerce Transaction Mining (Theme: Transactional Data).
  - **Application 2**: Biological Sequence Pattern Mining using DNA/Protein Data (Theme: Complex Data Transformation).
- Ensure all frequent patterns are discovered strictly using the **group's implemented algorithm from Chapter 1** (no external FIM libraries like `mlxtend` or SPMF pre-runs for final reporting).
- Prepare data conversion pipelines to serialize raw tabular/sequence data into the standardized SPMF `.txt` format and map numerical IDs back to domain-meaningful labels.
- We will use public datasets from Kaggle or Hugging Face for this chapter.


## TASKS TO DO

### Application 1: Market Basket Analysis (E-commerce Data)

1. **Dataset Selection & Preparation**:
   - [ ] Acquire a real-world transaction dataset (e.g., *Online Retail* or *Instacart*).
   - [ ] Clean anomalies (remove canceled orders, negative quantities, missing user/item IDs).
   - [ ] Group items by `InvoiceNo` or `OrderID` into transactions.
   - [ ] Convert transactions into SPMF `.txt` format and maintain an `item_id -> product_name` mapping dictionary.

2. **Mining & Rule Generation**:
   - [ ] Run the group's algorithm across suitable `minsup` thresholds to produce meaningful frequent itemsets.
   - [ ] Compute key association metrics for the discovered itemsets:
     - **Support**
     - **Confidence**
     - **Lift**
   - [ ] Filter out trivial or uninformative itemsets.

3. **Business Interpretation & Actionable Insights**:
   - [ ] Identify top cross-selling itemsets and complementary products.
   - [ ] Propose realistic retail recommendations based on findings (e.g., product bundling, shelf/web layout redesign, promotional discounting).

---

### Application 2: Biological Sequence Analysis (Genomic / Protein Data)

1. **Dataset Selection & Encoding Strategy**:
   - [ ] Acquire a benchmark sequence dataset (e.g., *UCI Molecular Biology Promoter Gene Sequences* or *Protein Secondary Structure*).
   - [ ] Choose and implement a transaction encoding strategy:
     - **Positional Encoding**: Pair position index with nucleotide/residue (`pos_i=base`).
     - **$k$-mer Window Encoding**: Decompose sequences into overlapping substrings of length $k$.
   - [ ] Convert encoded sequences into SPMF `.txt` format and preserve an `item_id -> feature_label` dictionary.

2. **Pattern Mining**:
   - [ ] Run the group's algorithm on the biological transaction file with an appropriate `minsup`.
   - [ ] Decode output integer itemsets back to biological features (positions, motifs, or amino acid groupings).
   - [ ] Measure pattern frequency across sequence classes/families if comparative labels exist.

3. **Biological Meaning & Interpretation**:
   - [ ] Highlight conserved consensus motifs (e.g., regulatory promoter sites, TATA-box equivalents) or frequent residue groupings.
   - [ ] Discuss the physical/biological significance of the detected patterns (e.g., binding site conservation, hydrophobic clustering in structural cores).
   - [ ] Analyze the limitations of treating ordered sequence data as unordered transactional sets.
