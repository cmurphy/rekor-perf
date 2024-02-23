#!/bin/bash

count=null

# may need to wait for the data to be scraped
tries=0
until [ "${count}" != "null" ] ; do
    sleep 1
    count=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_count{success="true"}' | jq -r .data.result[0].value[1])
    echo $count
    let 'tries+=1'
    if [ $tries -eq 6 ] ; then
        echo "count query failed, here is the raw result:"
        set -x
        curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_count{success="true"}'
        set +x
        echo
        exit 1
    fi
done

avg=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_sum{success="true"}/rekor_index_storage_latency_summary_count{success="true"}' | jq -r .data.result[0].value[1])

if [ "${avg}" == "null" ] ; then
    echo "avg query failed, here is the raw result:"
    set -x
    curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_sum{success="true"}/rekor_index_storage_latency_summary_count{success="true"}'
    set +x
    echo
    exit 1
fi

echo "Insert latency: ${avg} (average over ${count} inserts)"
