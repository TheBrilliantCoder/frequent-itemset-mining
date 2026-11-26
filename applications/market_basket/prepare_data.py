"""
Data preparation pipeline for Chapter 3 - Application 1: Market Basket Analysis.
Dataset: UCI Online Retail (https://archive.ics.uci.edu/dataset/352/online+retail)

Steps:
1. Extract (or download if missing) Online Retail.xlsx
2. Clean anomalies:
   - Missing InvoiceNo, StockCode, or Description
   - Canceled invoices (InvoiceNo starting with 'C')
   - Non-positive Quantity or UnitPrice
   - Non-merchandise service/adjustment StockCodes (POST, DOT, M, BANK CHARGES, etc.)
3. Canonicalize product descriptions per StockCode and assign deterministic integer item IDs.
4. Group items by InvoiceNo into transactions and export:
   - SPMF .txt transaction file
   - item_mapping.csv (item_id -> stock_code, description, tx_count)
   - dataset_summary.json (cleaning statistics & basket distribution)
"""

from __future__ import annotations

import json
import os
import re
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path

import pandas as pd

UCI_URL = "https://archive.ics.uci.edu/static/public/352/online+retail.zip"

NON_PRODUCT_CODES = {
    "POST", "DOT", "M", "BANK CHARGES", "PADS", "C2", "CRUK",
    "D", "AMAZONFEE", "B", "S", "ADJUST", "ADJUST2", "DCGS0003",
    "DCGS0004", "DCGS0069", "DCGS0070", "DCGS0076", "GIFT_0001_10",
    "GIFT_0001_20", "GIFT_0001_30", "GIFT_0001_40", "GIFT_0001_50",
}

NON_PRODUCT_DESC_KEYWORDS = (
    "POSTAGE", "MANUAL", "DISCOUNT", "BANK CHARGES", "SAMPLES",
    "CARRIAGE", "ADJUST", "DOTCOM", "AMAZON FEE", "CRUK COMMISSION",
)


def ensure_excel_file(data_dir: Path) -> Path:
    data_dir.mkdir(parents=True, exist_ok=True)
    xlsx_candidates = list(data_dir.glob("*.xlsx"))
    if xlsx_candidates:
        return xlsx_candidates[0]

    zip_path = data_dir / "online_retail.zip"
    if not zip_path.exists():
        print(f"Downloading UCI Online Retail dataset to {zip_path}...")
        urllib.request.urlretrieve(UCI_URL, zip_path)

    print(f"Extracting {zip_path}...")
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(data_dir)

    xlsx_candidates = list(data_dir.glob("*.xlsx"))
    if not xlsx_candidates:
        raise FileNotFoundError(f"No .xlsx file found after extracting {zip_path}")
    return xlsx_candidates[0]


def clean_description(text: str) -> str:
    return re.sub(r"\s+", " ", str(text).strip()).upper()


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    data_dir = repo_root / "data" / "applications" / "online_retail"
    results_dir = repo_root / "results" / "app1"
    results_dir.mkdir(parents=True, exist_ok=True)

    xlsx_path = ensure_excel_file(data_dir)
    print(f"Loading {xlsx_path} ...")
    df = pd.read_excel(xlsx_path, dtype={"InvoiceNo": str, "StockCode": str})

    raw_rows = len(df)
    raw_invoices = df["InvoiceNo"].nunique(dropna=True)
    raw_products = df["StockCode"].nunique(dropna=True)

    # 1. Drop missing key fields
    mask_missing = df["InvoiceNo"].isna() | df["StockCode"].isna() | df["Description"].isna()
    dropped_missing = int(mask_missing.sum())
    df = df.loc[~mask_missing].copy()

    df["InvoiceNo"] = df["InvoiceNo"].str.strip().str.upper()
    df["StockCode"] = df["StockCode"].str.strip().str.upper()
    df["Description"] = df["Description"].map(clean_description)

    # 2. Remove canceled orders (InvoiceNo starting with 'C')
    mask_canceled = df["InvoiceNo"].str.startswith("C")
    dropped_canceled = int(mask_canceled.sum())
    df = df.loc[~mask_canceled].copy()

    # 3. Remove non-positive quantity or unit price
    mask_invalid_qty_price = (df["Quantity"] <= 0) | (df["UnitPrice"] <= 0)
    dropped_qty_price = int(mask_invalid_qty_price.sum())
    df = df.loc[~mask_invalid_qty_price].copy()

    # 4. Remove non-merchandise service/fee codes
    mask_non_prod = (
        df["StockCode"].isin(NON_PRODUCT_CODES)
        | df["StockCode"].str.startswith("GIFT_")
        | df["Description"].apply(lambda d: any(kw in d for kw in NON_PRODUCT_DESC_KEYWORDS))
    )
    dropped_non_product = int(mask_non_prod.sum())
    df = df.loc[~mask_non_prod].copy()

    clean_rows = len(df)

    # 5. Canonical description per StockCode (most frequent description; tie-break lexicographically)
    desc_counts = (
        df.groupby(["StockCode", "Description"])
        .size()
        .reset_index(name="cnt")
        .sort_values(["StockCode", "cnt", "Description"], ascending=[True, False, True])
    )
    canonical_desc = (
        desc_counts.drop_duplicates(subset=["StockCode"], keep="first")
        .set_index("StockCode")["Description"]
        .to_dict()
    )

    # 6. Build deterministic integer item_id mapping (1..M) sorted by StockCode
    unique_codes = sorted(df["StockCode"].unique())
    code_to_id = {code: idx + 1 for idx, code in enumerate(unique_codes)}
    df["item_id"] = df["StockCode"].map(code_to_id)

    # 7. Group by InvoiceNo into unique sorted item_id transactions (deterministic InvoiceNo order)
    grouped = (
        df.groupby("InvoiceNo", sort=True)["item_id"]
        .apply(lambda s: sorted(set(s.tolist())))
    )
    transactions = grouped.tolist()
    n_transactions = len(transactions)
    n_items = len(unique_codes)

    basket_sizes = [len(tx) for tx in transactions]
    avg_basket = sum(basket_sizes) / n_transactions
    sorted_sizes = sorted(basket_sizes)
    median_basket = sorted_sizes[n_transactions // 2]
    max_basket = max(basket_sizes)
    multi_item_txs = sum(1 for sz in basket_sizes if sz >= 2)
    density = sum(basket_sizes) / (n_transactions * n_items)

    # Count item transaction frequency
    item_tx_counts = Counter()
    for tx in transactions:
        for item_id in tx:
            item_tx_counts[item_id] += 1

    # 8. Write SPMF .txt transaction file
    tx_path = data_dir / "transactions.txt"
    with open(tx_path, "w", encoding="utf-8") as f:
        for tx in transactions:
            f.write(" ".join(str(i) for i in tx) + "\n")

    # 9. Write item_mapping.csv
    mapping_rows = [
        {
            "item_id": code_to_id[code],
            "stock_code": code,
            "description": canonical_desc[code],
            "tx_count": item_tx_counts[code_to_id[code]],
            "support_pct": round(100.0 * item_tx_counts[code_to_id[code]] / n_transactions, 4),
        }
        for code in unique_codes
    ]
    mapping_df = pd.DataFrame(mapping_rows)
    mapping_path = data_dir / "item_mapping.csv"
    mapping_df.to_csv(mapping_path, index=False, encoding="utf-8")

    # Country breakdown (top 5)
    country_invoices = (
        df.groupby("Country")["InvoiceNo"].nunique().sort_values(ascending=False).head(5).to_dict()
    )

    summary = {
        "dataset": "UCI Online Retail (2010-12 to 2011-12)",
        "source_url": UCI_URL,
        "raw_rows": raw_rows,
        "raw_invoices": int(raw_invoices),
        "raw_stock_codes": int(raw_products),
        "dropped_missing_fields": dropped_missing,
        "dropped_canceled_invoices": dropped_canceled,
        "dropped_non_positive_qty_or_price": dropped_qty_price,
        "dropped_non_product_items": dropped_non_product,
        "clean_rows": clean_rows,
        "n_transactions": n_transactions,
        "n_multi_item_transactions": multi_item_txs,
        "n_unique_items": n_items,
        "avg_basket_size": round(avg_basket, 2),
        "median_basket_size": int(median_basket),
        "max_basket_size": int(max_basket),
        "matrix_density": round(density, 6),
        "top_countries_by_invoices": {str(k): int(v) for k, v in country_invoices.items()},
        "top_10_items": (
            mapping_df.sort_values("tx_count", ascending=False)
            .head(10)[["item_id", "stock_code", "description", "tx_count", "support_pct"]]
            .to_dict(orient="records")
        ),
    }

    summary_path = results_dir / "dataset_summary.json"
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)

    print("\n=== Online Retail Data Preparation Complete ===")
    print(f"Raw rows            : {raw_rows:,}")
    print(f"Clean rows          : {clean_rows:,}")
    print(f"Transactions (|D|)  : {n_transactions:,} (multi-item: {multi_item_txs:,})")
    print(f"Unique items (|I|)  : {n_items:,}")
    print(f"Avg / Median / Max  : {avg_basket:.2f} / {median_basket} / {max_basket}")
    print(f"Matrix density      : {density * 100:.3f}%")
    print(f"SPMF transactions   : {tx_path}")
    print(f"Item mapping        : {mapping_path}")
    print(f"Summary JSON        : {summary_path}")


if __name__ == "__main__":
    main()
