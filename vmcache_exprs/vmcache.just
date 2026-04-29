src := source_dir()
result_dir := src+"/../results/"

run_vmcache size_mem="204800" ram0_size_gb="128" datasize="512" runfor="30":
    #!/usr/bin/env bash
    set -x
    set -e

    mkdir -p {{result_dir}}
    make -C {{src}}/vmcache

    thread=$(nproc)

    nohup just linux_vm $thread {{size_mem}} </dev/null >/dev/null 2>&1 &
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
