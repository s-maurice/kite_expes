import os
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from common import *

def plot_tlb():
    df = pd.read_csv(os.path.join(result_dir, "vmcache_tlb.csv"))
    
    # Calculate time spent per thread
    df['tlb_ms_per_thread'] = df['tlb_ms'] / df['threads']
    df['tlb_pct'] = (df['tlb_ms_per_thread'] / 1000.0) * 100.0
    
    fig, ax = plt.subplots(figsize=(figwidth_half, fig_height))
    
    sns.barplot(data=df, x='threads', y='tlb_pct', hue='workload', 
                palette=get_palette(df, 'workload'), ax=ax)
    
    ax.set_ylabel("TLB Invalidation Time per Second (%)", fontsize=FONTSIZE-1)
    ax.set_xlabel("Number of Threads", fontsize=FONTSIZE-1)
    ax.set_title(lower_better_str, color="blue", fontsize=FONTSIZE-2)
    ax.legend(ncols=2, fontsize=FONTSIZE-2, bbox_to_anchor=(0.05, 0.95), loc='upper left', borderaxespad=0.)
    ax.set_xticklabels(ax.get_xticklabels(), fontsize=FONTSIZE-2)
    ax.set_yticklabels(ax.get_yticklabels(), fontsize=FONTSIZE-2)
    ax.grid(True, axis='y', linestyle='--', alpha=0.7, zorder=0)
    
    plt.tight_layout()
    plt.savefig(os.path.join(result_dir, "tlb_overhead.pdf"), bbox_inches="tight")
    plt.close()

def plot_mvcc():
    df = pd.read_csv(os.path.join(result_dir, "mvcc_degradation_results.csv"))

    fig, ax = plt.subplots(figsize=(figwidth_half, fig_height))

    sns.lineplot(data=df, x='seconds_elapsed', y='scan_latency_ms', ax=ax)
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Scan latency (ms)")
    ax.set_title(lower_better_str, color="blue", fontsize=FONTSIZE-2)
    ax.set_xticklabels(ax.get_xticklabels(), fontsize=FONTSIZE-2)
    ax.set_yticklabels(ax.get_yticklabels(), fontsize=FONTSIZE-2)
    ax.grid(True, axis='y', linestyle='--', alpha=0.7, zorder=0)
    plt.tight_layout()
    plt.savefig(os.path.join(result_dir, "mvcc_degradation.pdf"), bbox_inches="tight")
    plt.close()
    

def plot_in_mem():
    df = pd.read_csv(os.path.join(result_dir, "vmcache_in_mem.csv"))
    
    # Filter for 96 threads
    df96 = df[df['threads'] == 96].copy()
    df96['workload'] = df96['workload'].replace({'uniform': 'Random Reads', 'zipfian': 'YCSB-C'})
    
    fig, ax = plt.subplots(figsize=(figwidth_half, fig_height))
    
    sns.barplot(data=df96, x='workload', y='lookups', hue='version', 
                hue_order=['guards', 'noguards'], ax=ax)
    
    ax.set_yscale('log')
    ax.set_ylabel("Lookups / sec", fontsize=FONTSIZE-1)
    ax.set_xlabel("Workload (96 Threads)", fontsize=FONTSIZE-1)
    ax.set_title(higher_better_str, color="blue", fontsize=FONTSIZE-2)
    ax.set_xticklabels(ax.get_xticklabels(), fontsize=FONTSIZE-2)
    ax.set_yticklabels(ax.get_yticklabels(), fontsize=FONTSIZE-2)
    ax.grid(True, axis='y', linestyle='--', alpha=0.7, zorder=0)
    
    workloads = [t.get_text() for t in ax.get_xticklabels()]
    n_w = len(workloads)
    patches = ax.patches
    
    c1 = palette[0]
    c2 = palette[1]
    
    if len(patches) >= 2 * n_w:
        for i in range(n_w):
            base_color = c1 if i == 0 else c2
            guard_patch = patches[i]
            noguard_patch = patches[i + n_w]
            
            guard_patch.set_facecolor(base_color)
            noguard_patch.set_facecolor(darken(base_color))
            noguard_patch.set_hatch('//')
            noguard_patch.set_edgecolor('black')
            
            x0 = guard_patch.get_x() + guard_patch.get_width() / 2
            y0 = guard_patch.get_height()
            
            x1 = noguard_patch.get_x() + noguard_patch.get_width() / 2
            y1 = noguard_patch.get_height()
            
            if y0 > 0 and y1 > 0:
                speedup = y1 / y0
                
                # Move arrow to x0
                ax.hlines(y1, x0, x1, colors='black', linewidth=1)
                ax.annotate('', xy=(x0, y1), xytext=(x0, y0),
                            arrowprops=dict(arrowstyle='<->', shrinkA=0, shrinkB=0, color='black', linewidth=1))
                ax.text(x0 - 0.05, (y0 * y1)**0.5, f"{speedup:.1f}x", 
                        va='center', ha='right', fontsize=FONTSIZE-2)
                        
    import matplotlib.patches as mpatches
    handles = [
        mpatches.Patch(facecolor='gray', label='With guards'),
        mpatches.Patch(facecolor=darken('gray'), hatch='//', edgecolor='black', label='Without guards')
    ]
    ax.legend(handles=handles, title="", ncols=2, fontsize=FONTSIZE-2, handletextpad=0.25, columnspacing=0.4, bbox_to_anchor=(0.48, 0.95), loc='upper left', borderaxespad=0.)
    ax.set_ylim(1e7, 1e10)
    
    plt.tight_layout()
    plt.savefig(os.path.join(result_dir, "in_mem_perf.pdf"), bbox_inches="tight")
    plt.close()

if __name__ == "__main__":
    plot_tlb()
    plot_in_mem()
    plot_mvcc()
