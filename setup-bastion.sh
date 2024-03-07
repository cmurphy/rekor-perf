#!/bin/bash

sudo apt install kubernetes-client google-cloud-sdk-gke-gcloud-auth-plugin git redis-tools -y
which hyperfine >/dev/null || ( wget -O /tmp/hyperfine_1.16.1_amd64.deb https://github.com/sharkdp/hyperfine/releases/download/v1.16.1/hyperfine_1.16.1_amd64.deb && sudo dpkg -i /tmp/hyperfine_1.16.1_amd64.deb )
which helm >/dev/null || ( wget -O helm-v3.14.2-linux-amd64.tar.gz https://get.helm.sh/helm-v3.14.2-linux-amd64.tar.gz && tar -xzf helm-v3.14.2-linux-amd64.tar.gz -C /tmp/helm && sudo mv /tmp/helm/helm /usr/local/bin/ )
which rekor-cli >/dev/null || ( wget -O /tmp/rekor-cli-linux-amd64 https://github.com/sigstore/rekor/releases/download/v1.3.5/rekor-cli-linux-amd64 && sudo install -m 0755 /tmp/rekor-cli-linux-amd64 /usr/local/bin/rekor-cli )

gcloud auth print-access-token >/dev/null 2>&1 || gcloud auth login
gcloud container clusters get-credentials rekor --region us-west1
