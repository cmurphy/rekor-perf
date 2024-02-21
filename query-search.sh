#!/bin/bash

sleep 2

count=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_api_latency_summary_count{path="/api/v1/index/retrieve"}' | jq -r .data.result[0].value[1])
avg=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_api_latency_summary_sum{path="/api/v1/index/retrieve"}/rekor_api_latency_summary_count{path="/api/v1/index/retrieve"}' | jq -r .data.result[0].value[1])

echo "Search latency: ${avg} (average over ${count} searches)"
