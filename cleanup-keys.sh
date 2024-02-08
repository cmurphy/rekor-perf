#!/bin/bash

gpg --list-secret-keys --with-colons --fingerprint | grep -B2 example.com | sed -n 's/^fpr:::::::::\([[:alnum:]]\+\):/\1/p' | xargs gpg --batch --yes --delete-secret-keys
gpg --list-keys --with-colons --fingerprint | grep -B1 example.com | sed -n 's/^fpr:::::::::\([[:alnum:]]\+\):/\1/p' | xargs gpg --batch --yes --delete-keys
