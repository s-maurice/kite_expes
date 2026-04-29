import pandas as pd
from common import *


def fmt_block_size(b):
    if b >= 1048576:
        return f"{b // 1048576} MB"
    return f"{b // 1024} KB"


def plot_sweep():
    df = pd.read_csv(os.path.join(result_dir, "duckdb_sweep.csv"))

    block_sizes = sorted(df["block_size"].unique())
    labels = {b: fmt_block_size(b) for b in block_sizes}
    colors = palette[: len(block_sizes)]
    markers = marker_def[: len(block_sizes)]

    # Wall time: all cache_types share t_start/t_end, so deduplicate
    time_df = (
        df.groupby(["block_size", "cache_pct"], as_index=False)
        .first()
        .assign(wall_time=lambda x: x["t_end"] - x["t_start"])
    )

    # Hit rate: data rows only; cache_pct=0 is noop (both counts are 0)
    hit_df = (
        df[(df["cache_type"] == "data") & (df["cache_pct"] > 0)].copy()
    )
    hit_df["hit_rate"] = (
        hit_df["cache_hit_count"]
        / (hit_df["cache_hit_count"] + hit_df["cache_miss_count"])
        * 100
    )

    fig, (ax1, ax2) = plt.subplots(
        2, 1, figsize=(figwidth_full, fig_height * 2 + 0.5), sharex=True
    )

    for i, bs in enumerate(block_sizes):
        t = time_df[time_df["block_size"] == bs].sort_values("cache_pct")
        ax1.plot(
            t["cache_pct"],
            t["wall_time"],
            label=labels[bs],
            color=colors[i],
            marker=markers[i],
            markersize=4,
            linewidth=1.2,
        )

        h = hit_df[hit_df["block_size"] == bs].sort_values("cache_pct")
        ax2.plot(
            h["cache_pct"],
            h["hit_rate"],
            label=labels[bs],
            color=colors[i],
            marker=markers[i],
            markersize=4,
            linewidth=1.2,
        )

    ax1.set_ylabel("Wall time (s)", fontsize=FONTSIZE)
    ax1.set_title(lower_better_str, color="blue", fontsize=FONTSIZE - 2)
    ax1.yaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax1.legend(
        title="Block size",
        fontsize=FONTSIZE - 1,
        title_fontsize=FONTSIZE - 1,
        ncols=2,
    )
    ax1.grid(True, axis="y", linestyle="--", alpha=0.7, zorder=0)

    ax2.set_xlabel("Cache size (% of dataset)", fontsize=FONTSIZE)
    ax2.set_ylabel("Data hit rate (%)", fontsize=FONTSIZE)
    ax2.set_title(higher_better_str, color="blue", fontsize=FONTSIZE - 2)
    ax2.set_xticks([0, 20, 40, 60, 80, 100])
    ax2.set_ylim(0, 105)
    ax2.yaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax2.legend(
        title="Block size",
        fontsize=FONTSIZE - 1,
        title_fontsize=FONTSIZE - 1,
        ncols=2,
    )
    ax2.grid(True, axis="y", linestyle="--", alpha=0.7, zorder=0)

    sns.despine(fig=fig)
    plt.tight_layout()

    out = os.path.join(result_dir, "duckdb_sweep.pdf")
    plt.savefig(out, bbox_inches="tight")
    print(f"Saved {out}")
    plt.close()


if __name__ == "__main__":
    plot_sweep()
