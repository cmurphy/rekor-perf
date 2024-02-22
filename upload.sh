#!/bin/bash -e

N=$1

# Create N artifacts with different contents
dir=$(mktemp -d)
for i in $(seq 1 $N) ; do
    echo hello${i} > ${dir}/blob${i}
done
# Create an extra that won't ever be signed
echo hellohello > ${dir}/blobnone

# Get public keys
for i in $(seq 1 $N) ; do
    user=test${i}@example.com
    gpg --export --armor $user > ${dir}/${user}.key
done
gpg --export --armor notreal@example.com > ${dir}/notreal@example.com.key

echo "Signing $N artifacts with 1 key" 1>&2
user=test1@example.com
for i in $(seq 1 $N) ; do
    sig=${dir}/$(uuidgen).asc
    (
    gpg --armor -u $user --output $sig --detach-sig ${dir}/blob${i} 1>&2
    rekor-cli upload --rekor_server http://localhost:3000 --signature $sig --public-key ${dir}/${user}.key --artifact ${dir}/blob${i} 1>&2
    ) &
done

wait

echo "Signing 1 artifact with $N keys" 1>&2
echo $RANDOM > ${dir}/blob1
for i in $(seq 1 $N) ; do
    sig=${dir}/$(uuidgen).asc
    user=test${i}@example.com
    (
        gpg --armor -u $user --output $sig --detach-sig ${dir}/blob1 1>&2
        rekor-cli upload --rekor_server http://localhost:3000 --signature $sig --public-key ${dir}/${user}.key --artifact ${dir}/blob1 1>&2
    ) &
done

wait

echo $dir
