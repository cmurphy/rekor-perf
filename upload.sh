#!/bin/bash -e

# Create 10 artifacts with different contents
dir=$(mktemp -d)
for i in $(seq 1 10) ; do
    echo hello${i} > ${dir}/blob${i}
done
# Create an extra that won't ever be signed
echo hellohello > ${dir}/blobnone

# Get public keys
for i in $(seq 1 10) ; do
    user=test${i}@example.com
    gpg --export --armor $user > ${dir}/${user}.key
done
gpg --export --armor notreal@example.com > ${dir}/notreal@example.com.key

echo "Signing 10 artifacts with 1 key" 1>&2
user=test1@example.com
for i in $(seq 1 10) ; do
    sig=${dir}/$(uuidgen).asc
    gpg --armor -u $user --output $sig --detach-sig ${dir}/blob${i} 1>&2
    rekor-cli upload --rekor_server http://localhost:3000 --signature $sig --public-key ${dir}/${user}.key --artifact ${dir}/blob${i} 1>&2
done

echo "Signing 1 artifact with 10 keys" 1>&2
for i in $(seq 1 10) ; do
    sig=${dir}/$(uuidgen).asc
    user=test${i}@example.com
    gpg --armor -u $user --output $sig --detach-sig ${dir}/blob1 1>&2
    rekor-cli upload --rekor_server http://localhost:3000 --signature $sig --public-key ${dir}/${user}.key --artifact ${dir}/blob1 1>&2
done

#echo "Signing 1 artifact 10 times with same key"
#user=test1@example.com
#for i in $(seq 1 10) ; do
#    sig=${dir}/$(uuidgen).asc
#    gpg --armor -u $user --output $sig --detach-sig ${dir}/blob1
#    # signing includes the timestamp, so need to wait to produce a different signature
#    sleep 1
#    rekor-cli upload --rekor_server http://localhost:3000 --signature $sig --public-key ${dir}/${user}.key --artifact ${dir}/blob1
#done

echo $dir
