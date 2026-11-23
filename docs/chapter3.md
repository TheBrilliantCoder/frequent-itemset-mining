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

> **Status:** Completed. See implementation in [`applications/market_basket/`](../applications/market_basket/), rule generator in [`src/rules.jl`](../src/rules.jl), Colab notebook in [`notebooks/app1_market_basket.ipynb`](../notebooks/app1_market_basket.ipynb), and full report analysis in [`docs/app1_market_basket.md`](app1_market_basket.md).

1. **Dataset Selection & Preparation**:
   - [x] Acquire a real-world transaction dataset (*UCI Online Retail*, 541,909 raw rows).
   - [x] Clean anomalies (remove canceled orders `C*`, negative/zero quantities & prices, missing IDs/descriptions, and non-product service codes like `POST`/`DOT`/`M`).
   - [x] Group items by `InvoiceNo` into 19,773 transactions across 3,787 unique products.
   - [x] Convert transactions into SPMF `.txt` format and maintain an `item_id -> product_name` mapping dictionary (`item_mapping.csv`).

2. **Mining & Rule Generation**:
   - [x] Run the group's Optimized CHARM (`CharmMining.mine_file_bit`) across 7 `minsup` thresholds (`5.0%` down to `0.8%`), mining 2,026 closed itemsets in ~71 ms at `minsup = 1.0%`.
   - [x] Compute exact association metrics via Galois closure support lookup (`ClosureSupportIndex` in `src/rules.jl`):
     - **Support**
     - **Confidence**
     - **Lift** (plus Leverage & Conviction)
   - [x] Filter out trivial/non-product items and deduplicate symmetric pairs for Top-10 Lift ranking.

3. **Business Interpretation & Actionable Insights**:
   - [x] Identify top cross-selling itemsets and complementary products (Herb Marker collection, Regency Tea sets, Wooden Christmas decorations, Poppy's Playhouse, Dolly Girl/Spaceboy cutlery, Garage/Shed key fobs).
   - [x] Propose realistic retail recommendations (product bundling, one-click complete-the-set, cart-level cross-selling, seasonal promos, B2B assorted packs).

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
