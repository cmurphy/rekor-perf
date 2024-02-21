#!/bin/bash

sleep 2

count=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_count{success="true"}' | jq -r .data.result[0].value[1])
avg=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_sum{success="true"}/rekor_index_storage_latency_summary_count{success="true"}' | jq -r .data.result[0].value[1])

if [ "${count}" == "null" ] ; then
    echo "count query failed, here is the raw result:"
    set -x
    curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_api_latency_summary_count{path="/api/v1/index/retrieve"}'
    set +x
    echo
fi

if [ "${avg}" == "null" ] ; then
    echo "avg query failed, here is the raw result:"
    set -x
    curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_api_latency_summary_sum{path="/api/v1/index/retrieve"}/rekor_api_latency_summary_count{path="/api/v1/index/retrieve"}'
    set +x
    echo
fi

echo "Insert latency: ${avg} (average over ${count} inserts)"
