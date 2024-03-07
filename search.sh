#!/bin/bash -u

DIR=$1
if [ "${DIR}" == "" ] ; then
    echo "must set provide the artifact directory"
    exit 1
fi

if ! which hyperfine >/dev/null ; then
    echo "hyperfine is not installed yet"
    exit 1
fi

sumblob1=$(sha256sum ${DIR}/blob1 | cut -d ' ' -f1)
sumblob2=$(sha256sum ${DIR}/blob2 | cut -d ' ' -f1)
sumblobnone=$(sha256sum ${DIR}/blobnone | cut -d ' ' -f1)
# Search for entries using public key user1@example.com (should be many), user2@example.com (should be few), notreal@example.com (should be none)
hyperfine --style basic --warmup 10 --ignore-failure --parameter-list email user1@example.com,user2@example.com,notreal@example.com "rekor-cli search --rekor_server $REKOR_URL --email {email}"
# Search for entries using the sha256 sum of blob1 (should be many), blob2 (should be few), blobnone (should be none)
hyperfine --style basic --warmup 10 --ignore-failure --parameter-list sha ${sumblob1},${sumblob2},${sumblobnone} "rekor-cli search --rekor_server $REKOR_URL --sha sha256:{sha}"
# Search for entries using public key user1@example.com/user2@example.com/notreal@example.com OR/AND sha256 sum of blob1/blob2/blobnone
hyperfine --style basic --warmup 10 --ignore-failure --parameter-list email user1@example.com,user2@example.com,notreal@example.com \
    --parameter-list sha ${sumblob1},${sumblob2},${sumblobnone} \
    --parameter-list operator or,and \
    "rekor-cli search --rekor_server $REKOR_URL --email {email} --sha sha256:{sha} --operator {operator}"
