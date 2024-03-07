#!/bin/bash

if [ -z "${MYSQL_PASS}" ] ; then
    echo 'Set $MYSQL_PASS for the trillian mysql user. This value can be found from your terraform host using `terraform output -json | jq -r .mysql_pass.value`.'
    exit 1
fi

mysql_ip=$(gcloud sql instances describe rekor-perf-tf --format='get(ipAddresses[0].ipAddress)')
redis_ip=$(gcloud redis instances describe rekor-index --region us-west1 --format='get(host)')

mysql -h $mysql_ip -P 3306 -utrillian -p${MYSQL_PASS}  -D trillian -e 'DELETE FROM EntryIndex;'
redis-cli -h $redis_ip flushall

kubectl -n rekor-system rollout restart deployment rekor-server
