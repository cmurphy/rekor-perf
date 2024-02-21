#!/bin/bash

sleep 2

count=$(curl -s http://localhost:9090/api/v1/query?query=rekor_index_storage_latency_summary_count | jq -r .data.result[0].value[1])
avg=$(curl -s http://localhost:9090/api/v1/query?query=rekor_index_storage_latency_summary_sum/rekor_index_storage_latency_summary_count | jq -r .data.result[0].value[1])

echo "Insert latency: ${avg} (average over ${count} inserts)"
