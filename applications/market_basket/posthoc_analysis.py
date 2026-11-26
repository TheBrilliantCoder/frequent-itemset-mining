"""
Reproducible post-hoc verification for Chapter 3 - Application 1 (Market Basket Analysis).

Computes and exports `results/app1/posthoc_verification.json` covering:
1. Herb Marker collection (all 6 SKUs including CHIVES): exact basket-count distribution
   for sizes 1..6 and support of 4-, 5-, and 6-item subsets.
2. Seasonality baseline & in-season Lift for Wooden Christmas decorations:
   - Overall invoice share in Oct-Dec 2011 vs Dec 2010 vs rest of year
   - Share of Wooden Tree / Stocking / Sleigh invoices in Oct-Dec 2011 vs all Oct-Dec
   - Exact support of 3-item set {TREE, STOCKING, SLEIGH}
   - In-season Confidence & Lift (computed strictly within Oct-Dec 2011 invoices)
3. Customer-level diversity (`CustomerID` unique counts vs `InvoiceNo` counts) for key rules.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

import pandas as pd

from prepare_data import NON_PRODUCT_CODES, NON_PRODUCT_DESC_KEYWORDS, clean_description


def load_cleaned_df(xlsx_path: Path) -> pd.DataFrame:
    df = pd.read_excel(
        xlsx_path,
        usecols=["InvoiceNo", "StockCode", "Description", "Quantity", "UnitPrice", "InvoiceDate", "CustomerID"],
        dtype={"InvoiceNo": str, "StockCode": str},
    )
    df = df.dropna(subset=["InvoiceNo", "StockCode", "Description"]).copy()
    df["InvoiceNo"] = df["InvoiceNo"].str.strip().str.upper()
    df["StockCode"] = df["StockCode"].str.strip().str.upper()
    df["Description"] = df["Description"].map(clean_description)

    df = df[~df["InvoiceNo"].str.startswith("C")]
    df = df[(df["Quantity"] > 0) & (df["UnitPrice"] > 0)]
    mask_non_prod = (
        df["StockCode"].isin(NON_PRODUCT_CODES)
        | df["StockCode"].str.startswith("GIFT_")
        | df["Description"].apply(lambda d: any(kw in d for kw in NON_PRODUCT_DESC_KEYWORDS))
    )
    df = df[~mask_non_prod].copy()

    # Canonical description per StockCode (same rule as prepare_data.py)
    desc_counts = (
        df.groupby(["StockCode", "Description"])
        .size()
        .reset_index(name="cnt")
        .sort_values(["StockCode", "cnt", "Description"], ascending=[True, False, True])
    )
    canonical = (
        desc_counts.drop_duplicates(subset=["StockCode"], keep="first")
        .set_index("StockCode")["Description"]
        .to_dict()
    )
    df["CanonicalDesc"] = df["StockCode"].map(canonical)
    df["InvoiceDate"] = pd.to_datetime(df["InvoiceDate"])
    df["YearMonth"] = df["InvoiceDate"].dt.to_period("M").astype(str)
    return df


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    xlsx_path = repo_root / "data" / "applications" / "online_retail" / "Online Retail.xlsx"
    results_dir = repo_root / "results" / "app1"
    results_dir.mkdir(parents=True, exist_ok=True)

    df = load_cleaned_df(xlsx_path)

    # Invoice-level metadata
    inv_meta = (
        df.sort_values("InvoiceDate")
        .drop_duplicates("InvoiceNo", keep="first")
        .set_index("InvoiceNo")[["InvoiceDate", "YearMonth", "CustomerID"]]
    )
    n_total_inv = len(inv_meta)
    summary_path = results_dir / "dataset_summary.json"
    if summary_path.exists():
        expected_n = json.loads(summary_path.read_text(encoding="utf-8"))["n_transactions"]
        assert n_total_inv == expected_n, f"Invoice count mismatch: {n_total_inv} != {expected_n}"
    inv_products = df.groupby("InvoiceNo")["CanonicalDesc"].apply(set).to_dict()

    # 1. Herb Marker collection (all 6 SKUs)
    herb_6 = [
        "HERB MARKER THYME",
        "HERB MARKER ROSEMARY",
        "HERB MARKER PARSLEY",
        "HERB MARKER MINT",
        "HERB MARKER BASIL",
        "HERB MARKER CHIVES",
    ]
    herb_5_no_chives = herb_6[:5]

    herb_size_dist = Counter()
    herb_any_inv = 0
    for prods in inv_products.values():
        cnt = sum(1 for h in herb_6 if h in prods)
        if cnt > 0:
            herb_any_inv += 1
            herb_size_dist[cnt] += 1

    herb_4_core = ["HERB MARKER THYME", "HERB MARKER ROSEMARY", "HERB MARKER PARSLEY", "HERB MARKER BASIL"]
    supp_4_core = sum(1 for p in inv_products.values() if all(h in p for h in herb_4_core))
    supp_5_no_chives = sum(1 for p in inv_products.values() if all(h in p for h in herb_5_no_chives))
    supp_all_6 = sum(1 for p in inv_products.values() if all(h in p for h in herb_6))

    herb_per_item = {
        h: {
            "invoices": sum(1 for p in inv_products.values() if h in p),
            "support_pct": round(100.0 * sum(1 for p in inv_products.values() if h in p) / n_total_inv, 4),
        }
        for h in herb_6
    }

    # 2. Seasonality baseline & in-season Lift (Oct-Dec 2011 vs Dec 2010 vs full dataset)
    oct_dec_2011_months = {"2011-10", "2011-11", "2011-12"}
    all_oct_dec_months = {"2010-12", "2011-10", "2011-11", "2011-12"}

    inv_oct_dec_2011 = set(inv_meta.index[inv_meta["YearMonth"].isin(oct_dec_2011_months)])
    inv_dec_2010 = set(inv_meta.index[inv_meta["YearMonth"] == "2010-12"])
    inv_all_oct_dec = set(inv_meta.index[inv_meta["YearMonth"].isin(all_oct_dec_months)])

    baseline_oct_dec_2011_pct = round(100.0 * len(inv_oct_dec_2011) / n_total_inv, 2)
    baseline_dec_2010_pct = round(100.0 * len(inv_dec_2010) / n_total_inv, 2)
    baseline_all_oct_dec_pct = round(100.0 * len(inv_all_oct_dec) / n_total_inv, 2)

    wooden_items = {
        "tree": "SET OF 3 WOODEN TREE DECORATIONS",
        "stocking": "SET OF 3 WOODEN STOCKING DECORATION",
        "sleigh": "SET OF 3 WOODEN SLEIGH DECORATIONS",
    }
    wooden_invs = {
        k: {inv for inv, p in inv_products.items() if name in p}
        for k, name in wooden_items.items()
    }

    wooden_seasonality = {}
    for k, invs in wooden_invs.items():
        n_all = len(invs)
        n_od11 = len(invs & inv_oct_dec_2011)
        n_d10 = len(invs & inv_dec_2010)
        n_all_od = len(invs & inv_all_oct_dec)
        first_date = inv_meta.loc[list(invs), "InvoiceDate"].min()
        inv_since_launch = set(inv_meta.index[inv_meta["InvoiceDate"] >= first_date])
        post_launch_od11_pct = round(100.0 * len(inv_since_launch & inv_oct_dec_2011) / max(1, len(inv_since_launch)), 2)
        wooden_seasonality[k] = {
            "description": wooden_items[k],
            "first_invoice_date": first_date.strftime("%Y-%m-%d"),
            "post_launch_baseline_oct_dec_2011_pct": post_launch_od11_pct,
            "total_invoices": n_all,
            "oct_dec_2011_invoices": n_od11,
            "oct_dec_2011_pct": round(100.0 * n_od11 / max(1, n_all), 2),
            "dec_2010_invoices": n_d10,
            "all_oct_dec_invoices": n_all_od,
            "all_oct_dec_pct": round(100.0 * n_all_od / max(1, n_all), 2),
        }

    # Exact 3-item support {TREE, STOCKING, SLEIGH} & conditional confidence
    wooden_3_all = wooden_invs["tree"] & wooden_invs["stocking"] & wooden_invs["sleigh"]
    wooden_tree_stocking = wooden_invs["tree"] & wooden_invs["stocking"]

    # In-season Lift (computed strictly inside Oct-Dec 2011 invoices)
    n_season = len(inv_oct_dec_2011)
    in_season_rules = {}
    for a_key, b_key in [("tree", "stocking"), ("sleigh", "stocking")]:
        a_s = wooden_invs[a_key] & inv_oct_dec_2011
        b_s = wooden_invs[b_key] & inv_oct_dec_2011
        ab_s = a_s & b_s
        conf_s = len(ab_s) / max(1, len(a_s))
        lift_s = (len(ab_s) * n_season) / max(1, len(a_s) * len(b_s))
        in_season_rules[f"{a_key}_to_{b_key}"] = {
            "in_season_invoices_n": n_season,
            "support_count": len(ab_s),
            "support_pct": round(100.0 * len(ab_s) / n_season, 2),
            "confidence_pct": round(100.0 * conf_s, 2),
            "lift_in_season": round(lift_s, 2),
        }

    # 3. Customer diversity for representative rules
    cust_checks = {}
    for label, items in [
        ("herb_thyme_rosemary_parsley", ["HERB MARKER THYME", "HERB MARKER ROSEMARY", "HERB MARKER PARSLEY"]),
        ("wooden_tree_stocking", ["SET OF 3 WOODEN TREE DECORATIONS", "SET OF 3 WOODEN STOCKING DECORATION"]),
        ("dolly_girl_spaceboy_cutlery", ["CHILDRENS CUTLERY DOLLY GIRL", "CHILDRENS CUTLERY SPACEBOY"]),
        ("regency_sugar_milk", ["REGENCY SUGAR BOWL GREEN", "REGENCY MILK JUG PINK"]),
    ]:
        matched = [inv for inv, p in inv_products.items() if all(it in p for it in items)]
        cust_ids = inv_meta.loc[matched, "CustomerID"].dropna()
        cust_checks[label] = {
            "invoices": len(matched),
            "invoices_with_customer_id": int(len(cust_ids)),
            "unique_customers": int(cust_ids.nunique()),
        }

    report = {
        "n_total_invoices": n_total_inv,
        "herb_marker_analysis": {
            "per_item": herb_per_item,
            "baskets_with_at_least_1_herb": herb_any_inv,
            "size_distribution_among_herb_baskets": {str(k): int(herb_size_dist[k]) for k in range(1, 7)},
            "support_4_core_thyme_rosemary_parsley_basil": {
                "invoices": supp_4_core,
                "support_pct": round(100.0 * supp_4_core / n_total_inv, 4),
            },
            "support_5_without_chives": {
                "invoices": supp_5_no_chives,
                "support_pct": round(100.0 * supp_5_no_chives / n_total_inv, 4),
            },
            "support_all_6_including_chives": {
                "invoices": supp_all_6,
                "support_pct": round(100.0 * supp_all_6 / n_total_inv, 4),
            },
        },
        "seasonality_analysis": {
            "baseline_all_invoices": {
                "oct_dec_2011_invoices": len(inv_oct_dec_2011),
                "oct_dec_2011_pct": baseline_oct_dec_2011_pct,
                "dec_2010_invoices": len(inv_dec_2010),
                "dec_2010_pct": baseline_dec_2010_pct,
                "all_oct_dec_invoices": len(inv_all_oct_dec),
                "all_oct_dec_pct": baseline_all_oct_dec_pct,
            },
            "wooden_decorations": wooden_seasonality,
            "wooden_3_item_tree_stocking_sleigh": {
                "invoices": len(wooden_3_all),
                "support_pct": round(100.0 * len(wooden_3_all) / n_total_inv, 4),
                "conf_given_tree_and_stocking_pct": round(100.0 * len(wooden_3_all) / max(1, len(wooden_tree_stocking)), 2),
            },
            "in_season_oct_dec_2011_rules": in_season_rules,
        },
        "customer_diversity": cust_checks,
    }

    out_path = results_dir / "posthoc_verification.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"Saved post-hoc verification to {out_path}")
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
