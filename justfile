proot := source_dir()
qemu_ssh_port := "2222"
user := `whoami`
rep := '1'
ssd_id := '84:00.0'

mod motiv "motivation/motiv.just"

set shell := ["bash", "-euo", "pipefail", "-c"]

duckdb_dir := proot / "duckdb_cache_experements/duckdb"
duckdb_build_dir := proot / "duckdb_cache_experements/build"
cache_fs_dir := proot / "duckdb_cache_experements/duck-read-cache-fs"
seaweed_data_dir := proot / "duckdb_cache_experements/.seaweedfs"
bench_state_dir := proot / "duckdb_cache_experements/.bench_state"
seaweed_s3_port := "8333"
seaweed_master_port := "9333"
seaweed_volume_port := "8080"

help:
    just --list

ssh COMMAND="":
    @ ssh \
    -i {{proot}}/nix/keyfile \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentityAgent=/dev/null \
    -o LogLevel=ERROR \
    -F /dev/null \
    -p {{qemu_ssh_port}} \
    root@localhost -- "{{COMMAND}}"

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

seaweed-start:
    #!/usr/bin/env bash
    mkdir -p {{seaweed_data_dir}}
    nohup weed server \
        -dir={{seaweed_data_dir}} \
        -master.port={{seaweed_master_port}} \
        -volume.port={{seaweed_volume_port}} \
        -filer \
        -s3 \
        -s3.port={{seaweed_s3_port}} &
    echo "SeaweedFS started (S3 on port {{seaweed_s3_port}})"
    echo "Endpoint: http://localhost:{{seaweed_s3_port}}"

seaweed-stop:
	#!/usr/bin/env bash
	if [ -f {{seaweed_data_dir}}/seaweed.pid ]; then
		kill $(cat {{seaweed_data_dir}}/seaweed.pid) || true
		rm -f {{seaweed_data_dir}}/seaweed.pid
	else
		pkill -f "weed server" || true
	fi

# Generate TPC-H and upload to SeaweedFS S3 (seaweed-start must be running)
duckdb-tpch-load sf="50" bucket="duckdb-test": duckdb-build
    #!/usr/bin/env bash
    {{duckdb_build_dir}}/duckdb <<SQL
        LOAD httpfs;
        SET s3_endpoint='localhost:{{seaweed_s3_port}}';
        SET s3_use_ssl=false;
        SET s3_url_style='path';
        SET s3_access_key_id='any';
        SET s3_secret_access_key='any';
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
        SET s3_endpoint='localhost:{{seaweed_s3_port}}'; \
        SET s3_use_ssl=false; \
        SET s3_url_style='path'; \
        SET s3_access_key_id='any'; \
        SET s3_secret_access_key='any'; \
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

        sql="LOAD '{{cache_fs_ext}}';
        ${cache_config}
        SET enable_progress_bar=false;
        SET cache_httpfs_profile_type='temp';

        SET s3_endpoint='localhost:{{seaweed_s3_port}}';
        SET s3_use_ssl=false;
        SET s3_url_style='path';
        SET s3_access_key_id='any';
        SET s3_secret_access_key='any';

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
duckdb-s3-init bucket="duckdb-test": duckdb-build
    {{duckdb_build_dir}}/duckdb -c "\
        LOAD httpfs; \
        SET s3_endpoint='localhost:{{seaweed_s3_port}}'; \
        SET s3_use_ssl=false; \
        SET s3_url_style='path'; \
        SET s3_access_key_id='any'; \
        SET s3_secret_access_key='any'; \
        COPY (SELECT 1 AS init) TO 's3://{{bucket}}/init.parquet';"

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
