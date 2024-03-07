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

echo -n > perf.log

INSERT_RUNS=${INSERT_RUNS:-1000}
SEARCH_ENTRIES=${SEARCH_ENTRIES:-100000}
INDEX_BACKEND=${INDEX_BACKEND:-redis}

echo "Gathering insertion and retrieval metrics for index backend [${INDEX_BACKEND}]."
echo "Check perf.log for detailed output."

echo "Configuring the bastion..."
./setup-bastion.sh

echo "Setting up rekor..."
./setup-rekor.sh

source settings.vars

echo "Setting up prometheus..."
PROM_PID=$(./setup-prometheus.sh)
cleanup_prom() {
    echo "Cleaning up prometheus..."
    ./teardown-prometheus.sh $PROM_PID >> perf.log 2>&1
}
trap 'cleanup cleanup_prom' EXIT

echo "Inserting entries..."
DIR=$(./insert.sh $INSERT_RUNS 2>> perf.log)
cleanup_all() {
    cleanup_prom
    rm -rf $DIR
    echo "Cleaning up keys..."
    ./cleanup-keys.sh >> perf.log 2>&1
}
trap 'cleanup cleanup_all' EXIT

echo "Getting metrics for inserts..."
./query-inserts.sh

echo "Uploading entries..."
./upload.sh $SEARCH_ENTRIES

echo "Running search requests..."
./search.sh $DIR >> perf.log 2>&1

echo "Getting metrics for searches..."
./query-search.sh

echo "Resetting data..."
./reset.sh
