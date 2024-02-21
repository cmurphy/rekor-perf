#!/bin/bash -e

cleanup() {
    code=$?
    if [ $code -ne 0 ] ; then
        echo "An error occurred, check perf.log"
    fi
    ./teardown-rekor.sh >> perf.log 2>&1
    ./cleanup-keys.sh >> perf.log 2>&1
    exit $code
}
trap cleanup EXIT

echo > perf.log

./setup-rekor.sh >> perf.log 2>&1
./create-keys.sh >> perf.log 2>&1
PROM_PID=$(./setup-prometheus.sh)
cleanup_prom() {
    code=$?
    if [ $code -ne 0 ] ; then
        echo "An error occurred, check perf.log"
    fi
    ./teardown-rekor.sh >> perf.log 2>&1
    ./cleanup-keys.sh >> perf.log 2>&1
    ./teardown-prometheus.sh $PROM_PID >> perf.log 2>&1
    exit $code
}
trap cleanup_prom EXIT
DIR=$(./upload.sh 2>> perf.log)
./query-inserts.sh
./search.sh $DIR >> perf.log 2>&1
./query-search.sh
