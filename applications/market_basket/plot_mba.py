"""
Generate publication-quality visualizations for Chapter 3 - Application 1: Market Basket Analysis.
Reads outputs produced by `prepare_data.py` and `run_mba.jl` from `results/app1/` and saves
high-DPI figures to `results/app1/figures/`.
"""

from __future__ import annotations

import json
import textwrap
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def shorten(label: str, width: int = 38) -> str:
    label = label.strip()
    if len(label) <= width:
        return label
    return label[: width - 3].rstrip() + "..."


def setup_style() -> None:
    plt.rcParams.update({
        "figure.dpi": 150,
        "savefig.dpi": 300,
        "font.size": 10,
        "axes.titlesize": 12,
        "axes.titleweight": "bold",
        "axes.labelsize": 10,
        "axes.grid": True,
        "grid.alpha": 0.3,
        "axes.spines.top": False,
        "axes.spines.right": False,
    })


def plot_top_products(mapping_path: Path, fig_dir: Path) -> None:
    df = pd.read_csv(mapping_path).sort_values("tx_count", ascending=False).head(15)
    df = df.iloc[::-1]

    fig, ax = plt.subplots(figsize=(10, 6))
    bars = ax.barh(
        [shorten(d, 42) for d in df["description"]],
        df["support_pct"],
        color="#2563EB",
        alpha=0.88,
    )
    ax.set_xlabel("Support (% of Transactions)")
    ax.set_title("Top-15 Most Frequent Products in UCI Online Retail")

    for bar, cnt, pct in zip(bars, df["tx_count"], df["support_pct"]):
        ax.text(
            bar.get_width() + 0.15,
            bar.get_y() + bar.get_height() / 2,
            f"{pct:.2f}% ({cnt:,})",
            va="center",
            fontsize=8.5,
        )

    ax.set_xlim(0, df["support_pct"].max() * 1.22)
    plt.tight_layout()
    out = fig_dir / "fig1_top15_products.png"
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {out}")


def plot_minsup_sensitivity(sens_path: Path, fig_dir: Path) -> None:
    df = pd.read_csv(sens_path).sort_values("minsup_pct", ascending=False)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.6))

    # Left: Closed itemsets & Rules
    ax1.plot(df["minsup_pct"], df["num_closed_itemsets"], marker="o", lw=2, color="#1D4ED8", label="Closed Frequent Itemsets")
    ax1.plot(df["minsup_pct"], df["num_rules_conf50"], marker="s", lw=2, color="#DC2626", label="Association Rules (conf >= 50%)")
    ax1.invert_xaxis()
    ax1.set_xlabel("Minimum Support Threshold (%)")
    ax1.set_ylabel("Count")
    ax1.set_title("Output Size vs. Minsup Threshold")
    ax1.legend()

    # Right: Runtime (ms)
    ax2.plot(df["minsup_pct"], df["runtime_ms"], marker="^", lw=2, color="#059669")
    ax2.invert_xaxis()
    ax2.set_xlabel("Minimum Support Threshold (%)")
    ax2.set_ylabel("Execution Time (ms)")
    ax2.set_title("Optimized CHARM Runtime vs. Minsup")

    for x, y in zip(df["minsup_pct"], df["runtime_ms"]):
        ax2.annotate(f"{y:.1f}ms", (x, y), textcoords="offset points", xytext=(0, 7), ha="center", fontsize=8)
    ax2.set_ylim(0, df["runtime_ms"].max() * 1.15)

    plt.tight_layout()
    out = fig_dir / "fig2_minsup_sensitivity.png"
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {out}")


def plot_rules_scatter(all_rules_path: Path, top10_path: Path, fig_dir: Path) -> None:
    df = pd.read_csv(all_rules_path)
    top10 = pd.read_csv(top10_path)

    fig, ax = plt.subplots(figsize=(9, 5.5))
    sc = ax.scatter(
        df["support_pct"],
        df["confidence_pct"],
        c=df["lift"],
        s=30 + df["lift"] * 2.5,
        cmap="viridis",
        alpha=0.75,
        edgecolors="white",
        linewidths=0.4,
    )
    cbar = plt.colorbar(sc, ax=ax)
    cbar.set_label("Lift")

    # Highlight top-10 deduplicated rules
    ax.scatter(
        top10["support_pct"],
        top10["confidence_pct"],
        facecolors="none",
        edgecolors="#DC2626",
        s=110,
        linewidths=1.5,
        label="Top-10 Rules by Lift",
    )

    ax.set_xlabel("Support (%)")
    ax.set_ylabel("Confidence (%)")
    ax.set_title("Association Rules Distribution: Support vs. Confidence (colored by Lift)")
    ax.legend(loc="lower right")
    plt.tight_layout()
    out = fig_dir / "fig3_rules_scatter.png"
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {out}")


def plot_top10_lift(top10_path: Path, fig_dir: Path) -> None:
    df = pd.read_csv(top10_path).iloc[::-1]

    labels = []
    for _, row in df.iterrows():
        ant = shorten(str(row["antecedent_names"]), 48)
        con = shorten(str(row["consequent_names"]), 48)
        labels.append(f"{ant}\n  -> {con}")

    fig, ax = plt.subplots(figsize=(12, 7.2))
    bars = ax.barh(range(len(df)), df["lift"], color="#7C3AED", alpha=0.88)
    ax.set_yticks(range(len(df)))
    ax.set_yticklabels(labels, fontsize=8.5)
    ax.set_xlabel("Lift")
    ax.set_title("Top-10 Association Rules Ranked by Lift (Online Retail, minsup=1.0%, minconf=50%)")

    for bar, lift, conf, supp in zip(bars, df["lift"], df["confidence_pct"], df["support_pct"]):
        ax.text(
            bar.get_width() + 0.5,
            bar.get_y() + bar.get_height() / 2,
            f"Lift={lift:.2f} | Conf={conf:.1f}% | Supp={supp:.2f}%",
            va="center",
            fontsize=8.2,
            fontweight="bold",
            color="#1F2937",
        )

    ax.set_xlim(0, df["lift"].max() * 1.38)
    plt.tight_layout()
    out = fig_dir / "fig4_top10_lift.png"
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {out}")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    data_dir = repo_root / "data" / "applications" / "online_retail"
    results_dir = repo_root / "results" / "app1"
    fig_dir = results_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)

    setup_style()
    plot_top_products(data_dir / "item_mapping.csv", fig_dir)
    plot_minsup_sensitivity(results_dir / "minsup_sensitivity.csv", fig_dir)
    plot_rules_scatter(results_dir / "all_rules.csv", results_dir / "top10_rules_lift_dedup.csv", fig_dir)
    plot_top10_lift(results_dir / "top10_rules_lift_dedup.csv", fig_dir)

    # Sync figures into docs/figures/app1 so Markdown preview & GitHub render them cleanly
    docs_fig_dir = repo_root / "docs" / "figures" / "app1"
    docs_fig_dir.mkdir(parents=True, exist_ok=True)
    for png in fig_dir.glob("*.png"):
        (docs_fig_dir / png.name).write_bytes(png.read_bytes())


if __name__ == "__main__":
    main()
