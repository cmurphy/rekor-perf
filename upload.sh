#!/bin/bash

N=$1

if [ ! -f indices.csv ] ; then
    echo "Generating $N * 2 entries. This may take a while..."
    # N artifacts, 1 user
    for i in $(seq 1 $N) ; do
        uuid=$(dbus-uuidgen)
        echo user1@example.com,$uuid >> indices.csv
        sha=$(echo $i | sha256sum | cut -d ' ' -f 1)
        echo $sha,$uuid >> indices.csv
    done

    # 1 artifact, N users
    sha=$(echo 1 | sha256sum | cut -d ' ' -f 1)
    for i in $(seq 2 $N) ; do
        uuid=$(dbus-uuidgen)
        echo user${i}@example.com,$uuid >> indices.csv
        echo $sha,$uuid >> indices.csv
    done
fi

if [ "${INDEX_BACKEND}" == "redis" ] ; then
    redis_ip=$(gcloud redis instances describe rekor-index --region us-west1 --format='get(host)')
    while read LINE ; do
        key=$(echo $LINE | cut -d',' -f1)
        val=$(echo $LINE | cut -d',' -f2)
        printf "*3\r\n\$5\r\nLPUSH\r\n\$${#key}\r\n${key}\r\n\$${#val}\r\n${val}\r\n"
    done < indices.csv | redis-cli -h $redis_ip --pipe
else
    if [ -z "${MYSQL_PASS}" ] ; then
        echo 'Set $MYSQL_PASS for the trillian mysql user. This value can be found from your terraform host using `terraform output -json | jq -r .mysql_pass.value`.'
        exit 1
    fi

    mysql_ip=$(gcloud sql instances describe rekor-perf-tf --format='get(ipAddresses[0].ipAddress)')

    mysql -h $mysql_ip -P 3306 -utrillian -p${MYSQL_PASS}  -D trillian < indices.sql
fi
