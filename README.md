# PROJECT INFORMATION

## SETUP GUIDELINE

...julia setup, download dependencies...

---

## PROJECT STRUCTURE
Cấu trúc thư mục của dự án `CharmMining` được tổ chức như sau:

```text
CharmMining/
├── Project.toml
├── src/
│   ├── CharmMining.jl
│   ├── models.jl
│   ├── data.jl
│   ├── ordering.jl
│   ├── properties.jl
│   ├── repository.jl
│   ├── engine.jl
│   └── pipeline.jl
└── test/
    ├── runtests.jl
    ├── test_data.jl
    ├── test_ordering.jl
    ├── test_properties.jl
    ├── test_repository.jl
    ├── test_engine.jl
    └── test_oracle.jl
```

## HOW TO RUN

### 1. Project Setup (Optional)
This implementation relies purely on Julia's standard library (`Base`), so no external packages are required. However, if a `Project.toml` is present in the root directory, you can initialize the project environment with:

```bash
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

### 2. Prepare the Dataset
Create an input text file (e.g., `input.txt`) in the project root directory. Each line represents a single transaction with space-separated items (lines starting with `#`, `%`, or `@` are ignored):

```text
1 2 5
2 4
2 3
1 2 4
1 3
2 3
1 3
1 2 3 5
1 2 3
```

### 3. Configure `run.jl`
Use the `run.jl` file in the project root directory to run the mining pipeline and export the results:

```julia
include("src/CharmMining.jl")
using .CharmMining

# Mine closed itemsets with minsup = 2 and export to output.txt in SPMF format
mine_file("input.txt"; minsup = 2, output_path = "output.txt")
```

### 4. Execute the Code
Run the script from your terminal at the project root:

```bash
julia --project=. run.jl
```

### 5. View the Output
After execution completes, open `output.txt` in the project root directory to view the mined closed itemsets in SPMF format (`items #SUP: support`):

```text
2 #SUP: 7
1 #SUP: 6
3 #SUP: 6
1 2 #SUP: 4
1 3 #SUP: 4
2 3 #SUP: 4
1 2 3 #SUP: 2
1 2 5 #SUP: 2
2 4 #SUP: 2
```

### EXAMPLES

...some ways to run this project...

---

## DEMO WITH NOTEBOOKS

...link notebook to demo practical application...


