proot := source_dir()
qemu_ssh_port := "2222"
user := `whoami`
rep := '1'
ssd_id := '84:00.0'

mod motiv "motivation/motiv.just"
mod vmcache "vmcache_exprs/vmcache.just"

set shell := ["bash", "-euo", "pipefail", "-c"]

duckdb_dir := proot / "duckdb_cache_experements/duckdb"
duckdb_build_dir := proot / "duckdb_cache_experements/build"
cache_fs_dir := proot / "duckdb_cache_experements/duck-read-cache-fs"
minio_data_dir := proot / "duckdb_cache_experements/.minio"
bench_state_dir := proot / "duckdb_cache_experements/.bench_state"
minio_port := "9000"
minio_access_key := "minioadmin"
minio_secret_key := "minioadmin"

help:
    just --list

poweroff-vm:
    just ssh "poweroff" || true

ssh COMMAND="":
    @ ssh \
    -i {{proot}}/nix/keyfile \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentityAgent=/dev/null \
    -o LogLevel=ERROR \
    -F /dev/null \
    -T \
    -p {{qemu_ssh_port}} \
    root@localhost -- "{{COMMAND}}"

linux_vm_numa size_mem="204800":
    #!/usr/bin/env bash
    let "half_mem = {{size_mem}} / 2"
    sudo taskset -c 0-127 qemu-system-x86_64 \
        -cpu host \
        -smp 128,sockets=2,cores=64,threads=1 \
        -enable-kvm \
        -m {{size_mem}} \
        -machine q35,accel=kvm,kernel-irqchip=split \
        -device intel-iommu,intremap=on,device-iotlb=on,caching-mode=on \
        -object memory-backend-ram,id=ram0,size=${half_mem}M,host-nodes=0,policy=bind \
        -object memory-backend-ram,id=ram1,size=${half_mem}M,host-nodes=1,policy=bind \
        -numa node,nodeid=0,cpus=0,cpus=2,cpus=4,cpus=6,cpus=8,cpus=10,cpus=12,cpus=14,cpus=16,cpus=18,cpus=20,cpus=22,cpus=24,cpus=26,cpus=28,cpus=30,cpus=32,cpus=34,cpus=36,cpus=38,cpus=40,cpus=42,cpus=44,cpus=46,cpus=48,cpus=50,cpus=52,cpus=54,cpus=56,cpus=58,cpus=60,cpus=62,cpus=64,cpus=66,cpus=68,cpus=70,cpus=72,cpus=74,cpus=76,cpus=78,cpus=80,cpus=82,cpus=84,cpus=86,cpus=88,cpus=90,cpus=92,cpus=94,cpus=96,cpus=98,cpus=100,cpus=102,cpus=104,cpus=106,cpus=108,cpus=110,cpus=112,cpus=114,cpus=116,cpus=118,cpus=120,cpus=122,cpus=124,cpus=126,memdev=ram0 \
        -numa node,nodeid=1,cpus=1,cpus=3,cpus=5,cpus=7,cpus=9,cpus=11,cpus=13,cpus=15,cpus=17,cpus=19,cpus=21,cpus=23,cpus=25,cpus=27,cpus=29,cpus=31,cpus=33,cpus=35,cpus=37,cpus=39,cpus=41,cpus=43,cpus=45,cpus=47,cpus=49,cpus=51,cpus=53,cpus=55,cpus=57,cpus=59,cpus=61,cpus=63,cpus=65,cpus=67,cpus=69,cpus=71,cpus=73,cpus=75,cpus=77,cpus=79,cpus=81,cpus=83,cpus=85,cpus=87,cpus=89,cpus=91,cpus=93,cpus=95,cpus=97,cpus=99,cpus=101,cpus=103,cpus=105,cpus=107,cpus=109,cpus=111,cpus=113,cpus=115,cpus=117,cpus=119,cpus=121,cpus=123,cpus=125,cpus=127,memdev=ram1 \
        -numa dist,src=0,dst=1,val=21 \
        -numa dist,src=1,dst=0,val=21 \
        -device virtio-serial \
        -fsdev local,id=home,path={{proot}},security_model=none \
        -device virtio-9p-pci,fsdev=home,mount_tag=home,disable-modern=on,disable-legacy=off \
        -fsdev local,id=scratch,path=/scratch/{{user}},security_model=none \
        -device virtio-9p-pci,fsdev=scratch,mount_tag=scratch,disable-modern=on,disable-legacy=off \
        -fsdev local,id=nixstore,path=/nix/store,security_model=none \
        -device virtio-9p-pci,fsdev=nixstore,mount_tag=nixstore,disable-modern=on,disable-legacy=off \
        -drive file={{proot}}/VMs/linux-image.qcow2 \
        -net nic,netdev=user.0,model=virtio \
        -netdev user,id=user.0,hostfwd=tcp:127.0.0.1:{{qemu_ssh_port}}-:22 \
        -nographic

linux_vm nb_cpu="1" size_mem="16384":
    #!/usr/bin/env bash
    let "taskset_cores = {{nb_cpu}}-1"
    sudo taskset -c 0-$taskset_cores qemu-system-x86_64 \
        -cpu host \
        -smp {{nb_cpu}} \
        -enable-kvm \
        -m {{size_mem}} \
        -machine q35,accel=kvm,kernel-irqchip=split \
        -device intel-iommu,intremap=on,device-iotlb=on,caching-mode=on \
        -device virtio-serial \
        -fsdev local,id=home,path={{proot}},security_model=none \
        -device virtio-9p-pci,fsdev=home,mount_tag=home,disable-modern=on,disable-legacy=off \
        -fsdev local,id=scratch,path=/scratch/{{user}},security_model=none \
        -device virtio-9p-pci,fsdev=scratch,mount_tag=scratch,disable-modern=on,disable-legacy=off \
        -fsdev local,id=nixstore,path=/nix/store,security_model=none \
        -device virtio-9p-pci,fsdev=nixstore,mount_tag=nixstore,disable-modern=on,disable-legacy=off \
        -drive file={{proot}}/VMs/linux-image.qcow2 \
        -net nic,netdev=user.0,model=virtio \
        -netdev user,id=user.0,hostfwd=tcp:127.0.0.1:{{qemu_ssh_port}}-:22 \
        -nographic #\
        #-device vfio-pci,host={{ssd_id}}

# --- duckdb cache experiments ---

duckdb-build:
    #!/usr/bin/env bash
    set -e
    mkdir -p {{duckdb_build_dir}}
    cmake -G Ninja -S {{duckdb_dir}} -B {{duckdb_build_dir}} \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DBUILD_EXTENSIONS="httpfs;tpch"
    cmake --build {{duckdb_build_dir}} --parallel

cache-fs-build:
    #!/usr/bin/env bash
    set -e
    cd {{cache_fs_dir}}
    CMAKE_BUILD_PARALLEL_LEVEL=$(nproc) make reldebug DUCKDB_SRCDIR={{duckdb_dir}}

duckdb-shell: duckdb-build
    {{duckdb_build_dir}}/duckdb

minio-start bucket="duckdb-test":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p {{minio_data_dir}}
    MINIO_ROOT_USER={{minio_access_key}} MINIO_ROOT_PASSWORD={{minio_secret_key}} \
        nohup minio server {{minio_data_dir}} --address :{{minio_port}} \
        > {{minio_data_dir}}/minio.log 2>&1 &
    echo $! > {{minio_data_dir}}/minio.pid
    echo "MinIO started (S3 on port {{minio_port}})"
    mc alias set local http://localhost:{{minio_port}} {{minio_access_key}} {{minio_secret_key}}
    until mc ls local/ >/dev/null 2>&1; do sleep 0.5; done
    mc mb --ignore-existing local/{{bucket}}
    echo "Bucket '{{bucket}}' ready at http://localhost:{{minio_port}}"

minio-stop:
    #!/usr/bin/env bash
    pkill -x minio || true
    rm -f {{minio_data_dir}}/minio.pid

# Generate TPC-H and upload to MinIO S3 (minio-start must be running)
duckdb-tpch-load sf="50" bucket="duckdb-test": duckdb-build
    #!/usr/bin/env bash
    {{duckdb_build_dir}}/duckdb <<SQL
        LOAD httpfs;
        SET s3_endpoint='localhost:{{minio_port}}';
        SET s3_use_ssl=false;
        SET s3_url_style='path';
        SET s3_access_key_id='{{minio_access_key}}';
        SET s3_secret_access_key='{{minio_secret_key}}';
        LOAD tpch;
        CALL dbgen(sf={{sf}});
        COPY lineitem   TO 's3://{{bucket}}/tpch/lineitem.parquet';
        COPY orders     TO 's3://{{bucket}}/tpch/orders.parquet';
        COPY customer   TO 's3://{{bucket}}/tpch/customer.parquet';
        COPY part       TO 's3://{{bucket}}/tpch/part.parquet';
        COPY partsupp   TO 's3://{{bucket}}/tpch/partsupp.parquet';
        COPY supplier   TO 's3://{{bucket}}/tpch/supplier.parquet';
        COPY nation     TO 's3://{{bucket}}/tpch/nation.parquet';
        COPY region     TO 's3://{{bucket}}/tpch/region.parquet';
    SQL

cache_fs_ext := cache_fs_dir / "build/reldebug/extension/cache_httpfs/cache_httpfs.duckdb_extension"


# Print total compressed size of TPC-H parquet files in the bucket.
# Saves bytes to bench_state_dir for use by duckdb-sweep.
duckdb-bucket-size bucket="duckdb-test": duckdb-build
    #!/usr/bin/env bash
    set -e
    mkdir -p {{bench_state_dir}}
    {{duckdb_build_dir}}/duckdb -noheader -list -c "\
        LOAD httpfs; \
        SET s3_endpoint='localhost:{{minio_port}}'; \
        SET s3_use_ssl=false; \
        SET s3_url_style='path'; \
        SET s3_access_key_id='{{minio_access_key}}'; \
        SET s3_secret_access_key='{{minio_secret_key}}'; \
        SELECT sum(total_compressed_size) FROM parquet_metadata('s3://{{bucket}}/tpch/*.parquet');" \
        > {{bench_state_dir}}/bucket_size_bytes
    bytes=$(cat {{bench_state_dir}}/bucket_size_bytes)
    echo "Bucket size: ${bytes} bytes"


# Sweep cache size (0-100% of bucket) x block size.
# Run duckdb-bucket-size first. Results written to results/tpch_sweep_<timestamp>.csv
# cache_block_sizes is a space-separated list of block sizes in bytes.
duckdb-sweep bucket="duckdb-test" cache_block_sizes="65536 262144 524288 1048576": duckdb-build cache-fs-build
    #!/usr/bin/env bash
    set -euxo pipefail
    ulimit -n 65536

    bucket_bytes=$(<{{bench_state_dir}}/bucket_size_bytes)
    results_dir="{{proot}}/results"
    mkdir -p "$results_dir"

    out="$results_dir/tpch_sweep_$(date +%Y%m%d_%H%M%S).csv"

    echo "block_size,cache_pct,cache_blocks,cache_bytes,t_start,t_end,cache_type,cache_hit_count,cache_miss_count,cache_miss_by_in_use,bytes_to_read,bytes_to_cache,bytes_from_hits,bytes_from_misses" > "$out"

    echo "Sweeping cache 0-100% of bucket (${bucket_bytes}B) x block sizes [{{cache_block_sizes}}]"
    echo "→ $out"

    for block_size in {{cache_block_sizes}}; do
      for cache_pct in 0 20 40 60 80 100; do

        cache_bytes=$(( bucket_bytes * cache_pct / 100 ))
        cache_blocks=$(( (cache_bytes + block_size - 1) / block_size ))

        printf "  block=%sB cache=%s%% (%s blocks) ... " "$block_size" "$cache_pct" "$cache_blocks"

        if (( cache_pct == 0 )); then
          cache_config="SET cache_httpfs_type='noop';"
        else
          cache_config="
            SET cache_httpfs_type='in_mem';
            SET cache_httpfs_cache_block_size=${block_size};
            SET cache_httpfs_max_in_mem_cache_block_count=${cache_blocks};
            "
        fi

        tmp_access=$(mktemp)

        t_start=$(date +%s.%N)

        threads=$(( $(nproc) / 3 ))

        sql="LOAD '{{cache_fs_ext}}';
        ${cache_config}
        SET threads=${threads};
        SET enable_progress_bar=false;
        SET http_retries=5;
        SET http_retry_wait_ms=200;
        SET cache_httpfs_profile_type='temp';

        SET s3_endpoint='localhost:{{minio_port}}';
        SET s3_use_ssl=false;
        SET s3_url_style='path';
        SET s3_access_key_id='{{minio_access_key}}';
        SET s3_secret_access_key='{{minio_secret_key}}';

        CREATE VIEW lineitem AS SELECT * FROM read_parquet('s3://{{bucket}}/tpch/lineitem.parquet');
        CREATE VIEW orders   AS SELECT * FROM read_parquet('s3://{{bucket}}/tpch/orders.parquet');
        CREATE VIEW customer AS SELECT * FROM read_parquet('s3://{{bucket}}/tpch/customer.parquet');
        CREATE VIEW part     AS SELECT * FROM read_parquet('s3://{{bucket}}/tpch/part.parquet');
        CREATE VIEW partsupp AS SELECT * FROM read_parquet('s3://{{bucket}}/tpch/partsupp.parquet');
        CREATE VIEW supplier AS SELECT * FROM read_parquet('s3://{{bucket}}/tpch/supplier.parquet');
        CREATE VIEW nation   AS SELECT * FROM read_parquet('s3://{{bucket}}/tpch/nation.parquet');
        CREATE VIEW region   AS SELECT * FROM read_parquet('s3://{{bucket}}/tpch/region.parquet');

        LOAD tpch;

        PRAGMA tpch(1);  PRAGMA tpch(2);  PRAGMA tpch(3);  PRAGMA tpch(4);
        PRAGMA tpch(5);  PRAGMA tpch(6);  PRAGMA tpch(7);  PRAGMA tpch(8);
        PRAGMA tpch(9);  PRAGMA tpch(10); PRAGMA tpch(11); PRAGMA tpch(12);
        PRAGMA tpch(13); PRAGMA tpch(14); PRAGMA tpch(15); PRAGMA tpch(16);
        PRAGMA tpch(17); PRAGMA tpch(18); PRAGMA tpch(19); PRAGMA tpch(20);
        PRAGMA tpch(21); PRAGMA tpch(22);

        COPY (
          SELECT * FROM cache_httpfs_cache_access_info_query()
        ) TO '${tmp_access}' (FORMAT CSV, HEADER false);"
        printf '%s\n' "$sql" | {{duckdb_build_dir}}/duckdb -unsigned -batch

        t_end=$(date +%s.%N)

        echo "done"

        # Robust file read (no pipe, no subshell)
        while IFS= read -r line; do
          printf "%s,%s,%s,%s,%s,%s,%s\n" \
            "$block_size" "$cache_pct" "$cache_blocks" "$cache_bytes" \
            "$t_start" "$t_end" "$line" >> "$out"
        done < "$tmp_access"

        rm -f "$tmp_access"

      done
    done

    echo "Done → $out"

# Write a small parquet file via DuckDB httpfs — creates the bucket if absent
# duckdb-s3-init bucket="duckdb-test": duckdb-build
#     {{duckdb_build_dir}}/duckdb -c "\
#         LOAD httpfs; \
#         SET s3_endpoint='localhost:{{minio_port}}'; \
#         SET s3_use_ssl=false; \
#         SET s3_url_style='path'; \
#         SET s3_access_key_id='any'; \
#         SET s3_secret_access_key='any'; \
#         COPY (SELECT 1 AS init) TO 's3://{{bucket}}/init.parquet';"

# --- vm ---

linux-image-init:
    #!/usr/bin/env bash
    set -x
    set -e
    echo "Initializing disk for the VM"
    mkdir -p {{proot}}/VMs

    # build images fast
    overwrite() {
        install -D -m644 {{proot}}/VMs/ro/nixos.qcow2 {{proot}}/VMs/$1.qcow2
        qemu-img resize {{proot}}/VMs/$1.qcow2 +8g
    }

    nix build .#linux-image --out-link {{proot}}/VMs/ro
    overwrite linux-image
