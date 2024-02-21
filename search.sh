#!/bin/bash -u

DIR=$1
if [ "${DIR}" == "" ] ; then
    echo "must set provide the artifact directory"
    exit 1
fi

echo $DIR

sumblob1=$(sha256sum ${DIR}/blob1 | cut -d ' ' -f1)
sumblob2=$(sha256sum ${DIR}/blob2 | cut -d ' ' -f1)
sumblobnone=$(sha256sum ${DIR}/blobnone | cut -d ' ' -f1)
echo $sumblob1
# Search for entries using public key test1@example.com (should be many), test2@example.com (should be few), notreal@example.com (should be none)
hyperfine --style basic --warmup 10 --ignore-failure --parameter-list public_key ${DIR}/test1@example.com.key,${DIR}/test2@example.com.key,${DIR}/notreal@example.com.key "rekor-cli search --rekor_server http://localhost:3000 --public-key {public_key}"
# Search for entries using the sha256 sum of blob1 (should be many), blob2 (should be few), blobnone (should be none)
hyperfine --style basic --warmup 10 --ignore-failure --parameter-list sha ${sumblob1},${sumblob2},${sumblobnone} "rekor-cli search --rekor_server http://localhost:3000 --sha sha256:{sha}"
# Search for entries using public key test1@example.com/test2@example.com/notreal@example.com OR/AND sha256 sum of blob1/blob2/blobnone
hyperfine --style basic --warmup 10 --ignore-failure --parameter-list public_key ${DIR}/test1@example.com.key,${DIR}/test2@example.com.key,${DIR}/notreal@example.com.key \
    --parameter-list sha ${sumblob1},${sumblob2},${sumblobnone} \
    --parameter-list operator or,and \
    "rekor-cli search --rekor_server http://localhost:3000 --public-key {public_key} --sha sha256:{sha} --operator {operator}"
