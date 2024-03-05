#!/bin/bash -e

if ! which prometheus >/dev/null ; then
    sudo apt install prometheus -y
    sudo systemctl disable --now prometheus
fi

mkdir -p prometheus >/dev/null
pushd prometheus >/dev/null
rm -rf metrics2
cat >prometheus.yml <<EOF
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 1s
    static_configs:
      - targets:
          - '$REKOR_METRICS'
EOF
setsid prometheus --storage.tsdb.path=./metrics2 --config.file=prometheus.yml >prom.log 2>&1 &
PROM_PID=$!
echo $PROM_PID
