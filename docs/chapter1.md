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

