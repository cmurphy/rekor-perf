#!/bin/bash -e

cleanup() {
    code=$?
    if [ $code -ne 0 ] ; then
        echo "An error occurred, check perf.log"
        echo "Waiting 30 seconds to start cleanup, press ^C to cancel cleanup."
        sleep 30
    fi
    $@
    exit $code
}

echo > perf.log

RUNS=${1:-1000}

echo "Setting up rekor..."
./setup-rekor.sh >> perf.log 2>&1
cleanup_rekor() {
    echo "Cleaning up rekor..."
    ./teardown-rekor.sh >> perf.log 2>&1
}
trap 'cleanup cleanup_rekor' EXIT

index_backend=$(grep -o 'search_index.storage_provider=[a-z]\+' rekor/docker-compose.yml | cut -d '=' -f 2)
echo "Gathering insertion and retrieval metrics for index backend [${index_backend}]."
echo "Check perf.log for detailed output."

echo "Setting up prometheus..."
PROM_PID=$(./setup-prometheus.sh)
cleanup_prom() {
    cleanup_rekor
    echo "Cleaning up prometheus..."
    ./teardown-prometheus.sh $PROM_PID >> perf.log 2>&1
}
trap 'cleanup cleanup_prom' EXIT

echo "Uploading entries..."
DIR=$(./upload.sh $RUNS 2>> perf.log)
cleanup_all() {
    cleanup_prom
    rm -rf $DIR
    echo "Cleaning up keys..."
    ./cleanup-keys.sh >> perf.log 2>&1
}
trap 'cleanup cleanup_all' EXIT

echo "Getting metrics for inserts..."
./query-inserts.sh

echo "Running search requests..."
./search.sh $DIR >> perf.log 2>&1

echo "Getting metrics for searches..."
./query-search.sh
