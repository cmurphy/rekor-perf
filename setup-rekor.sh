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
popd
