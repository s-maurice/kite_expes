src := source_dir()
result_dir := src+"/../results/"
nb_cpus := "1 8 16 32 64 96 128"


run_vmcache_motiv_tlb size_mem="204800" ram0_size_gb="128" datasize="512" runfor="30":
    #!/usr/bin/env bash
    set -x
    set -e

    mkdir -p {{result_dir}}
    echo "workload,threads,tlb_inv,tlb_ms" > {{result_dir}}/vmcache_tlb.csv

    for thread in {{nb_cpus}}
    do
        nohup just linux_vm $thread {{size_mem}} </dev/null >/dev/null 2>&1 &
        VM_PID=$!

        until just ssh "echo VM_READY" | grep -q 'VM_READY'; do
            sleep 2
        done

        let "ram0_size_kb = {{ram0_size_gb}} * 1024 * 1024"
        just ssh "modprobe brd rd_nr=1 rd_size=$ram0_size_kb"

        let "phys_gb = {{ram0_size_gb}} / 8"
        just ssh "BLOCK=/dev/ram0 VIRTGB={{ram0_size_gb}} PHYSGB=$phys_gb THREADS=$thread EXMAP=1 DATASIZE={{datasize}} RUNFOR={{runfor}} bpftrace -e 'BEGIN { @run_start = nsecs; } kprobe:flush_tlb_multi, kprobe:native_flush_tlb_local { @start[tid] = nsecs; } kretprobe:flush_tlb_multi, kretprobe:native_flush_tlb_local /@start[tid]/ { \\\$rs = @run_start; \\\$sec = (nsecs - \\\$rs) / 1000000000; @tlb_time_ns_per_sec[\\\$sec] += (nsecs - @start[tid]); @tlb_inv_per_sec[\\\$sec] += 1; delete(@start[tid]); }' -c 'time vmcache'" > /tmp/bpf_raw.out 2>&1 || true
        
        awk -v threads=$thread -v workload="tpcc" -F'[][]' '{ split($3, a, ": "); if ($1 == "@tlb_inv_per_sec") { t=$2+0; inv[t]=a[2]; if(t>max_t) max_t=t; } if ($1 == "@tlb_time_ns_per_sec") ms[$2+0]=a[2]; } END { sum_ms=0; sum_inv=0; cnt=0; for(t=max_t-10; t<=max_t-1; t++) { if(t in ms) { sum_ms+=ms[t]; sum_inv+=inv[t]; cnt++; } } if(cnt>0) print workload "," threads "," sum_inv/cnt "," sum_ms/(cnt*1000000.0); else print workload "," threads ",0,0"; }' /tmp/bpf_raw.out >> {{result_dir}}/vmcache_tlb.csv

        just ssh "BLOCK=/dev/ram0 VIRTGB={{ram0_size_gb}} PHYSGB=$phys_gb THREADS=$thread EXMAP=1 DATASIZE=6e8 RUNFOR={{runfor}} RNDREAD=1 bpftrace -e 'BEGIN { @run_start = nsecs; } kprobe:flush_tlb_multi, kprobe:native_flush_tlb_local { @start[tid] = nsecs; } kretprobe:flush_tlb_multi, kretprobe:native_flush_tlb_local /@start[tid]/ { \\\$rs = @run_start; \\\$sec = (nsecs - \\\$rs) / 1000000000; @tlb_time_ns_per_sec[\\\$sec] += (nsecs - @start[tid]); @tlb_inv_per_sec[\\\$sec] += 1; delete(@start[tid]); }' -c 'time vmcache'" > /tmp/bpf_raw.out 2>&1 || true
        awk -v threads=$thread -v workload="rndread" -F'[][]' '{ split($3, a, ": "); if ($1 == "@tlb_inv_per_sec") { t=$2+0; inv[t]=a[2]; if(t>max_t) max_t=t; } if ($1 == "@tlb_time_ns_per_sec") ms[$2+0]=a[2]; } END { sum_ms=0; sum_inv=0; cnt=0; for(t=max_t-10; t<=max_t-1; t++) { if(t in ms) { sum_ms+=ms[t]; sum_inv+=inv[t]; cnt++; } } if(cnt>0) print workload "," threads "," sum_inv/cnt "," sum_ms/(cnt*1000000.0); else print workload "," threads ",0,0"; }' /tmp/bpf_raw.out >> {{result_dir}}/vmcache_tlb.csv

        just ssh "poweroff" || true
        wait $VM_PID 2>/dev/null || true
    done

run_vmcache_motiv_in_mem size_mem="80" datasize="5e8" runfor="10":
    #!/usr/bin/env bash
    set -x
    set -e

    mkdir -p {{result_dir}}
    csv_file="{{result_dir}}/vmcache_in_mem.csv"
    echo "workload,threads,version,lookups" > $csv_file
    make -C {{src}}/in_mem_vmcache

    for thread in {{nb_cpus}}
    do
        taskset_cores=$((thread - 1))
        for guards in 0 1
        do
            for zipfian in 0 1
            do
                if [ "$guards" -eq 1 ]; then version="guards"; else version="noguards"; fi
                if [ "$zipfian" -eq 1 ]; then workload="zipfian"; else workload="uniform"; fi

                mean_lookups=$(USE_GUARDS=$guards THREADS=$thread MEMGB={{size_mem}} DATASIZE={{datasize}} RUNFOR={{runfor}} ZIPFIAN=$zipfian taskset -c 0-$taskset_cores ./in_mem_vmcache/vmcache | grep '^[0-9]' | tail -n 5 | awk -F',' '{sum+=$2; count++} END {if(count>0) printf "%.0f\n", sum/count; else printf "0\n"}')
                echo "$workload,$thread,$version,$mean_lookups" >> $csv_file
            done
        done
    done

run_pgsql_motiv:
    #!/usr/bin/env bash
    set -e

    DB_NAME="mvcc_kite_test"
    ROWS_SCALE=10
    WRITE_CLIENTS=16
    WRITE_THREADS=4
    DURATION=180q
    OUTPUT_CSV="{{result_dir}}/mvcc_degradation_results.csv"

    # Temp dir for postgres data + socket
    PG_DATA=$(mktemp -d /tmp/pgdata.XXXXXX)
    PG_SOCKET_DIR="/tmp"

    # Initialize and start postgres with a local socket
    pg_ctl initdb -D "$PG_DATA" -o "--encoding=UTF8" > /dev/null
    pg_ctl start -D "$PG_DATA" -o "-k $PG_SOCKET_DIR -h ''" -l "$PG_DATA/pg.log"

    # Wait for server to be ready
    until pg_isready -h "$PG_SOCKET_DIR" -d postgres > /dev/null 2>&1; do sleep 1; done

    PSQL="psql -h $PG_SOCKET_DIR -d"
    PGBENCH_CONN="-h $PG_SOCKET_DIR"

    dropdb $PGBENCH_CONN --if-exists $DB_NAME || true
    createdb $PGBENCH_CONN $DB_NAME
    pgbench $PGBENCH_CONN -i -s $ROWS_SCALE $DB_NAME > /dev/null 2>&1

    cat << EOF > /tmp/update_workload.sql
        \set aid random(1, 100000)
        UPDATE pgbench_accounts SET abalance = abalance + 1 WHERE aid = :aid;
    EOF

    $PSQL $DB_NAME -c "
        BEGIN ISOLATION LEVEL REPEATABLE READ; 
        SELECT count(*) FROM pgbench_accounts; 
        SELECT pg_sleep($DURATION + 10); 
        COMMIT;" > /dev/null 2>&1 &
    SABOTEUR_PID=$!

    sleep 2

    pgbench $PGBENCH_CONN -c $WRITE_CLIENTS -j $WRITE_THREADS -T $DURATION -f /tmp/update_workload.sql -n $DB_NAME > /dev/null 2>&1 &
    PGBENCH_PID=$!

    mkdir -p {{result_dir}}
    echo "seconds_elapsed,scan_latency_ms" > $OUTPUT_CSV

    START_TIME=$SECONDS
    ELAPSED=0

    while [ $ELAPSED -lt $DURATION ]; do
        LATENCY=$($PSQL $DB_NAME -t -A -c "\timing on" -c "SELECT SUM(abalance) FROM pgbench_accounts;" | grep "Time" | awk '{print $2}')

        echo "$ELAPSED,$LATENCY" >> $OUTPUT_CSV
        echo "  -> Elapsed: ${ELAPSED}s | Full Table Scan Latency: ${LATENCY} ms"

        sleep 2
        ELAPSED=$(( SECONDS - START_TIME ))
    done

    kill $SABOTEUR_PID 2>/dev/null || true
    wait $PGBENCH_PID 2>/dev/null || true
    rm /tmp/update_workload.sql

    # Shutdown postgres and cleanup
    pg_ctl stop -D "$PG_DATA" -m fast
    rm -rf "$PG_DATA"