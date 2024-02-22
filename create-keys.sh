#!/bin/bash
#

N=$1

# Create N different public keys
for i in $(seq 1 $N) ; do
    gpg --batch --gen-key 2>/dev/null <<EOF
Key-Type: 1
Key-Length: 1024
Name-Real: test${i}
Name-Email: test${i}@example.com
Expire-Date: 1
%no-protection
EOF
done

# Create one more key that won't ever be used for signing
gpg --batch --gen-key 2>/dev/null <<EOF
Key-Type: 1
Key-Length: 1024
Name-Real: notreal
Name-Email: notreal@example.com
Expire-Date: 1
%no-protection
EOF
