src := source_dir()
result_dir := src+"/../results/"

run_vmcache_tlb_pct size_mem="204800" ram0_size_gb="128" datasize="400" runfor="3":
    #!/usr/bin/env bash
    set -x
    set -e

    mkdir -p {{result_dir}}
    make -C {{src}}/vmcache vmcache_tlb_pct

    just linux_vm 192 {{size_mem}} &
    VM_PID=$!

    until just ssh "echo VM_READY" 2>/dev/null | grep -q 'VM_READY'; do
        sleep 2
    done

    let "ram0_size_kb = {{ram0_size_gb}} * 1024 * 1024"
    just ssh "modprobe brd rd_nr=1 rd_size=$ram0_size_kb"

    let "phys_gb = {{ram0_size_gb}} / 8"

    echo "threads,batch,tlb_pct" > {{result_dir}}/vmcache_tlb_pct.csv
    > {{result_dir}}/vmcache_tlb_pct_thpt.raw

    for batch in 1 32 64 96; do
        for nthreads in 1 16 32 64 128 192; do
            just ssh "BLOCK=/dev/ram0 VIRTGB=512 PHYSGB=$phys_gb GENTHREADS=192 EXMAP=1 DATASIZE={{datasize}} RUNFOR={{runfor}} BATCH=$batch THREADS=$nthreads \
                bpftrace /root/vmcache_exprs/vmcache/tlb_pct.bt \
                -c /root/vmcache_exprs/vmcache/vmcache_tlb_pct \
                2>/tmp/vmcache_tlb_err.txt" \
                | awk -v t=$nthreads -v b=$batch '/^DATA/{printf "%s,%s,%.4f\n", t, b, $4/(t*$5)*100}' \
                >> {{result_dir}}/vmcache_tlb_pct.csv

            just ssh "grep '^batch=' /tmp/vmcache_tlb_err.txt" \
                >> {{result_dir}}/vmcache_tlb_pct_thpt.raw
        done
    done

    just ssh "poweroff" || true
    wait $VM_PID 2>/dev/null || true

run_vmcache_thread_sweep size_mem="204800" ram0_size_gb="128" datasize="512" runfor="5":
    #!/usr/bin/env bash
    set -x
    set -e

    mkdir -p {{result_dir}}
    make -C {{src}}/vmcache vmcache_thread_sweep

    just linux_vm_numa {{size_mem}} &
    VM_PID=$!

    until just ssh "echo VM_READY" 2>/dev/null | grep -q 'VM_READY'; do
        sleep 2
    done

    let "ram0_size_kb = {{ram0_size_gb}} * 1024 * 1024"
    just ssh "modprobe brd rd_nr=1 rd_size=$ram0_size_kb"

    let "phys_gb = {{ram0_size_gb}} / 8"

    just ssh "BLOCK=/dev/ram0 VIRTGB={{ram0_size_gb}} PHYSGB=$phys_gb GENTHREADS=128 EXMAP=1 DATASIZE={{datasize}} RUNFOR={{runfor}} \
        /root/vmcache_exprs/vmcache/vmcache_thread_sweep" \
        > {{result_dir}}/vmcache_thread_sweep.csv

    just ssh "poweroff" || true
    wait $VM_PID 2>/dev/null || true

parse_vmcache_tlb_pct_thpt:
    awk '/^batch=/{split($1,b,"="); split($2,t,"="); split($3,x,"="); print b[2]","t[2]","x[2]}' \
        {{result_dir}}/vmcache_tlb_pct_thpt.raw \
        | awk 'BEGIN{print "batch,threads,tx"} {print}' \
        > {{result_dir}}/vmcache_tlb_pct_thpt.csv

run_vmcache size_mem="204800" ram0_size_gb="128" datasize="512" runfor="30":
    #!/usr/bin/env bash
    set -x
    set -e

    mkdir -p {{result_dir}}
    make -C {{src}}/vmcache

    thread=$(nproc)

    just linux_vm $thread {{size_mem}} &
    VM_PID=$!

    until just ssh "echo VM_READY" | grep -q 'VM_READY'; do
        sleep 2
    done

    let "ram0_size_kb = {{ram0_size_gb}} * 1024 * 1024"
    just ssh "modprobe brd rd_nr=1 rd_size=$ram0_size_kb"

    let "phys_gb = {{ram0_size_gb}} / 8"
    just ssh "BLOCK=/dev/ram0 VIRTGB={{ram0_size_gb}} PHYSGB=$phys_gb THREADS=$thread EXMAP=1 DATASIZE={{datasize}} RUNFOR={{runfor}} time /root/vmcache_exprs/vmcache/vmcache" | tee {{result_dir}}/vmcache_tpcc.out

    just ssh "BLOCK=/dev/ram0 VIRTGB={{ram0_size_gb}} PHYSGB=$phys_gb THREADS=$thread EXMAP=1 DATASIZE=6e8 RUNFOR={{runfor}} RNDREAD=1 time /root/vmcache_exprs/vmcache/vmcache" | tee {{result_dir}}/vmcache_rndread.out

    just ssh "poweroff" || true
    wait $VM_PID 2>/dev/null || true
