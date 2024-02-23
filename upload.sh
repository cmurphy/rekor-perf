#!/bin/bash -e

createkey() {
    name=$1
    gpg --batch --gen-key 2>/dev/null <<EOF
Key-Type: 1
Key-Length: 1024
Name-Real: $name
Name-Email: $name@example.com
Expire-Date: 1
%no-protection
EOF
    gpg --export --armor ${name}@example.com > ${dir}/${name}@example.com.key
}

deletekey() {
    name=$1
    gpg --list-secret-keys --with-colons --fingerprint | grep -B2 ${name}@example.com | sed -n 's/^fpr:::::::::\([[:alnum:]]\+\):/\1/p' | xargs gpg --batch --yes --delete-secret-keys
    gpg --list-keys --with-colons --fingerprint | grep -B1 ${name}@example.com | sed -n 's/^fpr:::::::::\([[:alnum:]]\+\):/\1/p' | xargs gpg --batch --yes --delete-keys
}

N=$1

# Create N artifacts with different contents
dir=$(mktemp -d)
for i in $(seq 1 $N) ; do
    echo hello${i} > ${dir}/blob${i}
done
# Create an extra that won't ever be signed
echo hellohello > ${dir}/blobnone

# Create one signing key
createkey user1
# Create a key that won't be used
createkey notreal

echo "Signing $N artifacts with 1 key" 1>&2
user=user1@example.com
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
for i in $(seq 2 $N) ; do
    # Create temporary signing keys, except for user2 which will be needed later
    if [ $i -eq 2 ] ; then
        name=user2
    else
        name=tmp${i}
    fi
    createkey $name
    sig=${dir}/$(uuidgen).asc
    user=${name}@example.com
    (
        gpg --armor -u $user --output $sig --detach-sig ${dir}/blob1 1>&2
        rekor-cli upload --rekor_server http://localhost:3000 --signature $sig --public-key ${dir}/${user}.key --artifact ${dir}/blob1 1>&2
    ) &
    if [ $i -ne 2 ] ; then
        deletekey tmp${i}
    fi
done

wait

echo $dir
