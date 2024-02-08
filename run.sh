#!/bin/bash

./setup-rekor.sh
./create-keys.sh
./upload.sh
./search.sh
./cleanup-keys.sh
./teardown-rekor.sh
