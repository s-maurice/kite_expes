import pandas as pd
from common import *


def plot_thread_sweep():
    df = pd.read_csv(os.path.join(result_dir, "vmcache_thread_sweep.csv"))

    fig, (ax1, ax2) = plt.subplots(
        2, 1, figsize=(figwidth_full, fig_height * 2 + 0.5), sharex=True
    )

    for ax in (ax1, ax2):
        ax.axvline(x=64, color="gray", linestyle="--", linewidth=0.8, alpha=0.7)

    ax1.plot(df["threads"], df["tx_per_sec"] / 1e3,
             color=palette[0], marker="o", markersize=4, linewidth=1.2)
    ax1.set_ylabel("Throughput (k tx/s)", fontsize=FONTSIZE)
    ax1.set_title(higher_better_str, color="blue", fontsize=FONTSIZE - 2)
    ax1.yaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax1.grid(True, axis="y", linestyle="--", alpha=0.7, zorder=0)
    ax1.text(64, ax1.get_ylim()[1], " NUMA\n boundary", fontsize=FONTSIZE - 2,
             color="gray", va="top")

    ax2.plot(df["threads"], df["tlb_per_sec"] / 1e3,
             color=palette[1], marker="o", markersize=4, linewidth=1.2)
    ax2.set_ylabel("TLB shootdowns (k/s)", fontsize=FONTSIZE)
    ax2.set_xlabel("Threads", fontsize=FONTSIZE)
    ax2.set_title(lower_better_str, color="blue", fontsize=FONTSIZE - 2)
    ax2.set_xticks(df["threads"])
    ax2.set_xticklabels(df["threads"], fontsize=FONTSIZE - 2, rotation=45)
    ax2.yaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax2.grid(True, axis="y", linestyle="--", alpha=0.7, zorder=0)

    sns.despine(fig=fig)
    plt.tight_layout()

    out = os.path.join(result_dir, "vmcache_thread_sweep.pdf")
    plt.savefig(out, bbox_inches="tight")
    print(f"Saved {out}")
    plt.close()


if __name__ == "__main__":
    plot_thread_sweep()
