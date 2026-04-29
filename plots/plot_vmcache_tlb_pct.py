import pandas as pd
from common import *

DEFAULT_BATCH = 64
RUNFOR_SEC = 5


def plot_vmcache_tlb_pct():
    df = pd.read_csv(os.path.join(result_dir, "vmcache_tlb_pct.csv"))

    batch_sizes = sorted(df["batch"].unique())
    thread_counts = sorted(df["threads"].unique())

    batch_palette = sns.color_palette("tab10", len(batch_sizes))
    # single hue gradient: light→dark as thread count rises
    thread_palette = sns.color_palette("Blues", len(thread_counts) + 3)[3:]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(figwidth_full, fig_height + 0.4))

    # --- subplot 1: emphasis on batch size, x=threads ---
    for i, batch in enumerate(batch_sizes):
        sub = df[df["batch"] == batch].sort_values("threads")
        lw = 1.8 if batch == DEFAULT_BATCH else 1.0
        ls = "-" if batch == DEFAULT_BATCH else "--"
        label = f"batch={batch}" + (" (default)" if batch == DEFAULT_BATCH else "")
        ax1.plot(sub["threads"], sub["tlb_pct"],
                 color=batch_palette[i], marker=marker_def[i % len(marker_def)],
                 markersize=3, linewidth=lw, linestyle=ls, label=label)

    ax1.set_xlabel("Threads", fontsize=FONTSIZE)
    ax1.set_ylabel("TLB Flush (% of wall time / thread)", fontsize=FONTSIZE)
    ax1.set_xticks(thread_counts)
    ax1.set_xticklabels(thread_counts, fontsize=FONTSIZE - 2, rotation=45)
    ax1.yaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax1.grid(True, axis="y", linestyle="--", alpha=0.5, zorder=0)
    ax1.legend(fontsize=FONTSIZE - 2, title="Batch size", title_fontsize=FONTSIZE - 2)
    ax1.set_title("Effect of batch size on TLB flush overhead", fontsize=FONTSIZE)

    # --- subplot 2: emphasis on thread count, x=batch_size ---
    for i, threads in enumerate(thread_counts):
        sub = df[df["threads"] == threads].sort_values("batch")
        ax2.plot(sub["batch"], sub["tlb_pct"],
                 color=thread_palette[i],
                 marker=marker_def[i % len(marker_def)],
                 markersize=3, linewidth=1.0, label=f"{threads}t")

    ax2.axvline(x=DEFAULT_BATCH, color="gray", linestyle="--", linewidth=0.9, alpha=0.8)
    ax2.text(DEFAULT_BATCH + 1, ax2.get_ylim()[1] * 0.98, "default",
             fontsize=FONTSIZE - 2, color="gray", va="top")

    ax2.set_xlabel("Batch size", fontsize=FONTSIZE)
    ax2.set_ylabel("TLB Flush (% of wall time / thread)", fontsize=FONTSIZE)
    ax2.set_xticks(batch_sizes)
    ax2.set_xticklabels(batch_sizes, fontsize=FONTSIZE - 2)
    ax2.yaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax2.grid(True, axis="y", linestyle="--", alpha=0.5, zorder=0)
    ax2.legend(fontsize=FONTSIZE - 2, title="Threads", title_fontsize=FONTSIZE - 2,
               ncol=2)
    ax2.set_title("Effect of thread count on TLB flush overhead", fontsize=FONTSIZE)

    sns.despine(fig=fig)
    plt.tight_layout()

    out = os.path.join(result_dir, "vmcache_tlb_pct.pdf")
    plt.savefig(out, bbox_inches="tight")
    print(f"Saved {out}")
    plt.close()

    # --- plot 3: throughput (tx/s) vs threads, one line per batch size ---
    df_t = pd.read_csv(os.path.join(result_dir, "vmcache_tlb_pct_thpt.csv"))
    df_t["tx_per_sec"] = df_t["tx"] / RUNFOR_SEC

    fig3, ax3 = plt.subplots(1, 1, figsize=(figwidth_half + 0.5, fig_height + 0.4))

    for i, batch in enumerate(sorted(df_t["batch"].unique())):
        sub = df_t[df_t["batch"] == batch].sort_values("threads")
        lw = 1.8 if batch == DEFAULT_BATCH else 1.0
        ls = "-" if batch == DEFAULT_BATCH else "--"
        label = f"batch={batch}" + (" (default)" if batch == DEFAULT_BATCH else "")
        ax3.plot(sub["threads"], sub["tx_per_sec"] / 1e3,
                 color=batch_palette[i], marker=marker_def[i % len(marker_def)],
                 markersize=3, linewidth=lw, linestyle=ls, label=label)

    ax3.set_xlabel("Threads", fontsize=FONTSIZE)
    ax3.set_ylabel("Throughput (k tx/s)", fontsize=FONTSIZE)
    ax3.set_xticks(sorted(df_t["threads"].unique()))
    ax3.set_xticklabels(sorted(df_t["threads"].unique()), fontsize=FONTSIZE - 2, rotation=45)
    ax3.yaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax3.grid(True, axis="y", linestyle="--", alpha=0.5, zorder=0)
    ax3.legend(fontsize=FONTSIZE - 2, title="Batch size", title_fontsize=FONTSIZE - 2)
    ax3.set_title("TPC-C throughput vs thread count", fontsize=FONTSIZE)

    sns.despine(fig=fig3)
    plt.tight_layout()

    out3 = os.path.join(result_dir, "vmcache_tlb_pct_thpt.pdf")
    plt.savefig(out3, bbox_inches="tight")
    print(f"Saved {out3}")
    plt.close()


if __name__ == "__main__":
    plot_vmcache_tlb_pct()
