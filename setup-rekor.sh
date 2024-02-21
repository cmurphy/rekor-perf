#!/bin/bash

if [ -d rekor ] ; then
    pushd rekor
    git pull
    popd
else
    git clone https://github.com/sigstore/rekor
fi
pushd rekor
docker-compose up -d
for i in `seq 1 6` ; do
    if docker-compose ps | grep rekor_rekor-server_1 | grep healthy ; then
        break
    fi
    echo "waiting for rekor to come up..."
    sleep 10
    if [ $i -eq 6 ] ; then
        echo "rekor did not come up."
        exit 1
    fi
done
