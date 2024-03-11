#!/bin/bash -e

cleanup() {
    code=$?
    if [ $code -ne 0 ] ; then
        echo "An error occurred. Waiting 30 seconds to start cleanup, press ^C to cancel cleanup."
        sleep 30
    fi
    $@
    exit $code
}

INSERT_RUNS=${INSERT_RUNS:-1000}
SEARCH_ENTRIES=${SEARCH_ENTRIES:-100000}
INDEX_BACKEND=${INDEX_BACKEND:-redis}
REGION=${REGION:-us-west1}

setup_bastion() {
    echo "Configuring the bastion..."
    sudo apt install kubernetes-client google-cloud-sdk-gke-gcloud-auth-plugin git redis-tools gnuplot prometheus -y
    which hyperfine >/dev/null || ( wget -O /tmp/hyperfine_1.16.1_amd64.deb https://github.com/sharkdp/hyperfine/releases/download/v1.16.1/hyperfine_1.16.1_amd64.deb && sudo dpkg -i /tmp/hyperfine_1.16.1_amd64.deb )
    which helm >/dev/null || ( wget -O helm-v3.14.2-linux-amd64.tar.gz https://get.helm.sh/helm-v3.14.2-linux-amd64.tar.gz && tar -xzf helm-v3.14.2-linux-amd64.tar.gz -C /tmp/helm && sudo mv /tmp/helm/helm /usr/local/bin/ )
    which rekor-cli >/dev/null || ( wget -O /tmp/rekor-cli-linux-amd64 https://github.com/sigstore/rekor/releases/download/v1.3.5/rekor-cli-linux-amd64 && sudo install -m 0755 /tmp/rekor-cli-linux-amd64 /usr/local/bin/rekor-cli )
    gcloud auth print-access-token >/dev/null 2>&1 || gcloud auth login
    gcloud container clusters get-credentials rekor --region $REGION
}

setup_rekor() {
    echo "Setting up rekor..."
    helm repo add sigstore https://sigstore.github.io/helm-charts
    helm repo update

    sha=$(git ls-remote https://github.com/sigstore/rekor HEAD | awk '{print substr($1, 1, 7)}')
    cat >values.yaml <<EOF
server:
  ingress:
    enabled: false
  image:
    repository: projectsigstore/rekor/ci/rekor/rekor-server
    version: '$sha'
EOF

    if [ "$INDEX_BACKEND" == "redis" ] ; then
        export REDIS_IP=$(gcloud redis instances describe rekor-index --region $REGION --format='get(host)')
        cat >index-values.yaml <<EOF
redis:
  enabled: false
  hostname: $REDIS_IP
server:
  extraArgs:
    - --search_index.storage_provider=redis
EOF
        helm upgrade rekor sigstore/rekor -n rekor-system --values values.yaml --values index-values.yaml
    else
        export MYSQL_IP=$(gcloud sql instances describe rekor-perf-tf --format='get(ipAddresses[0].ipAddress)')
        cat >index-values.yaml <<EOF
server:
  extraArgs:
    - --search_index.storage_provider=mysql
    - --search_index.mysql.dsn=trillian:\$(MYSQL_PASSWORD)@tcp(${MYSQL_IP}:3306)/trillian
EOF
        helm upgrade -i rekor sigstore/rekor -n rekor-system --values values.yaml --values mysql-args-values.yaml
        echo -n $MYSQL_PASS | kubectl -n rekor-system create secret generic mysql-credentials --save-config --dry-run=client --output=yaml --from-file=mysql-password=/dev/stdin | kubectl apply -f -
        cat > patch.yaml <<EOF
spec:
  template:
    spec:
      containers:
      - name: rekor-server
        env:
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-credentials
              key: mysql-password
EOF
        kubectl -n rekor-system patch deployment rekor-server --patch-file=patch.yaml
    fi
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: rekor-server-nodeport
  namespace: rekor-system
spec:
  selector:
    app.kubernetes.io/component: server
    app.kubernetes.io/instance: rekor
    app.kubernetes.io/name: rekor
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 3000
    nodePort: 30080
  - name: metrics
    port: 2112
    protocol: TCP
    targetPort: 2112
    nodePort: 32112
  type: NodePort
EOF

    node_address=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    export REKOR_URL=http://${node_address}:30080
    export REKOR_METRICS=${node_address}:32112
}

setup_prometheus() {
    echo "Setting up prometheus..."
    sudo systemctl disable --now prometheus
    mkdir -p prometheus >/dev/null
    rm -rf prometheus/metrics2
    cat >prometheus/prometheus.yml <<EOF
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 1s
    static_configs:
      - targets:
          - '$REKOR_METRICS'
EOF
    setsid prometheus --storage.tsdb.path=./prometheus/metrics2 --config.file=prometheus/prometheus.yml >prometheus/prom.log 2>&1 &
    export PROM_PID=$!
}

create_key() {
    name=$1
    gpg --batch --gen-key 2>/dev/null <<EOF
Key-Type: 1
Key-Length: 256
Name-Real: $name
Name-Email: $name@example.com
Expire-Date: 1
%no-protection
EOF
    gpg --export --armor ${name}@example.com > ${DIR}/${name}@example.com.key
}

delete_key() {
    email=$1
    gpg --list-secret-keys --with-colons --fingerprint | grep -B2 ${email} | sed -n 's/^fpr:::::::::\([[:alnum:]]\+\):/\1/p' | xargs gpg --batch --yes --delete-secret-keys
    gpg --list-keys --with-colons --fingerprint | grep -B1 ${email} | sed -n 's/^fpr:::::::::\([[:alnum:]]\+\):/\1/p' | xargs gpg --batch --yes --delete-keys
}

# Upload $INSERT_RUNS rekords of $INSERT_RUNS artifacts signed by 1 key, and $INSERT_RUNS rekords of 1 artifact signed by $INSERT_RUNS keys
insert() {
    echo "Inserting entries..."
    local N=$INSERT_RUNS
    # Create N artifacts with different contents
    export DIR=$(mktemp -d)
    for i in $(seq 1 $N) ; do
        echo hello${i} > ${DIR}/blob${i}
    done
    # Create an extra that won't ever be signed
    echo hellohello > ${DIR}/blobnone
    # Create one signing key
    create_key user1
    # Create a key that won't be used
    create_key notreal

    echo "Signing $N artifacts with 1 key"
    user=user1@example.com
    for i in $(seq 1 $N) ; do
        sig=${DIR}/$(uuidgen).asc
        (
        gpg --armor -u $user --output $sig --detach-sig ${DIR}/blob${i}
        rekor-cli upload --rekor_server $REKOR_URL --signature $sig --public-key ${DIR}/${user}.key --artifact ${DIR}/blob${i}
        ) &
    done
    wait

    echo "Signing 1 artifact with $N keys"
    echo $RANDOM > ${DIR}/blob1
    for i in $(seq 2 $N) ; do
        # Create temporary signing keys, except for user2 which will be needed later
        if [ $i -eq 2 ] ; then
            name=user2
        else
            name=tmp${i}
        fi
        create_key $name
        sig=${DIR}/$(uuidgen).asc
        user=${name}@example.com
        (
            gpg --armor -u $user --output $sig --detach-sig ${DIR}/blob1
            rekor-cli upload --rekor_server $REKOR_URL --signature $sig --public-key ${DIR}/${user}.key --artifact ${DIR}/blob1
        ) &
        if [ $i -ne 2 ] ; then
            delete_key tmp${i}@example.com
        fi
    done
    wait
}

query_inserts() {
    echo "Getting metrics for inserts..."
    count=null

    # may need to wait for the data to be scraped
    tries=0
    until [ "${count}" != "null" ] ; do
        sleep 1
        count=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_count{success="true"}' | jq -r .data.result[0].value[1])
        let 'tries+=1'
        if [ $tries -eq 6 ] ; then
            echo "count query failed, here is the raw result:"
            set -x
            curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_count{success="true"}'
            set +x
            echo
            exit 1
        fi
    done

    avg=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_sum{success="true"}/rekor_index_storage_latency_summary_count{success="true"}' | jq -r .data.result[0].value[1])

    if [ "${avg}" == "null" ] ; then
        echo "avg query failed, here is the raw result:"
        set -x
        curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_index_storage_latency_summary_sum{success="true"}/rekor_index_storage_latency_summary_count{success="true"}'
        set +x
        echo
        exit 1
    fi

    echo "Insert latency: ${avg} (average over ${count} inserts)"
    results=${INDEX_BACKEND}.dat
    if [ "$INDEX_BACKEND" == "redis" ] ; then
        x=1
    else
        x=0
    fi
    # output to gnuplot data set
    echo "$x \"${INDEX_BACKEND} inserts (${count})\" $avg" > $results
}

upload() {
    echo "Uploading entries..."
    N=$SEARCH_ENTRIES

    if [ ! -f indices.csv ] ; then
        echo "Generating $N * 2 entries. This may take a while..."
        # N artifacts, 1 user
        for i in $(seq 1 $N) ; do
            uuid=$(dbus-uuidgen)
            echo user1@example.com,$uuid >> indices.csv
            sha=$(echo $i | sha256sum | cut -d ' ' -f 1)
            echo $sha,$uuid >> indices.csv
        done

        # 1 artifact, N users
        sha=$(echo 1 | sha256sum | cut -d ' ' -f 1)
        for i in $(seq 2 $N) ; do
            uuid=$(dbus-uuidgen)
            echo user${i}@example.com,$uuid >> indices.csv
            echo $sha,$uuid >> indices.csv
        done
    fi

    if [ "${INDEX_BACKEND}" == "redis" ] ; then
        while read LINE ; do
            key=$(echo $LINE | cut -d',' -f1)
            val=$(echo $LINE | cut -d',' -f2)
            printf "*3\r\n\$5\r\nLPUSH\r\n\$${#key}\r\n${key}\r\n\$${#val}\r\n${val}\r\n"
        done < indices.csv | redis-cli -h $REDIS_IP --pipe
    else
        mysql -h $MYSQL_IP -P 3306 -utrillian -p${MYSQL_PASS}  -D trillian -e "CREATE TABLE IF NOT EXISTS EntryIndex (
                PK BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                EntryKey varchar(512) NOT NULL,
                EntryUUID char(80) NOT NULL,
                PRIMARY KEY(PK),
                UNIQUE(EntryKey, EntryUUID)
        );
        LOAD DATA LOCAL INFILE './indices.csv'
        INTO TABLE EntryIndex
        FIELDS TERMINATED BY ','
        LINES TERMINATED BY '\n' (EntryKey, EntryUUID);"
    fi
}

search() {
    echo "Running search requests..."
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
}

query_search() {
    echo "Getting metrics for searches..."
    count=null
    # may need to wait for the data to be scraped
    tries=0
    until [ "${count}" != "null" ] ; do
        sleep 1
        count=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_api_latency_summary_count{path="/api/v1/index/retrieve"}' | jq -r .data.result[0].value[1])
        let 'tries+=1'
        if [ $tries -eq 6 ] ; then
            echo "count query failed, here is the raw result:"
            set -x
            curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_api_latency_summary_count{path="/api/v1/index/retrieve"}'
            set +x
            echo
        fi
    done

    avg=$(curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_api_latency_summary_sum{path="/api/v1/index/retrieve"}/rekor_api_latency_summary_count{path="/api/v1/index/retrieve"}' | jq -r .data.result[0].value[1])
    if [ "${avg}" == "null" ] ; then
        echo "avg query failed, here is the raw result:"
        set -x
        curl -s http://localhost:9090/api/v1/query --data-urlencode 'query=rekor_api_latency_summary_sum{path="/api/v1/index/retrieve"}/rekor_api_latency_summary_count{path="/api/v1/index/retrieve"}'
        set +x
        echo
    fi

    echo "Search latency: ${avg} (average over ${count} searches)"
    results=${INDEX_BACKEND}.dat
    if [ "$INDEX_BACKEND" == "redis" ] ; then
        x=3
    else
        x=2
    fi
    # output to gnuplot data set
    echo "$x \"${INDEX_BACKEND} searches (${count})\" $avg" >> $results
}

reset() {
    echo "Resetting data..."
    if [ "${INDEX_BACKEND}" == "redis" ] ; then
        redis-cli -h $REDIS_IP flushall
    else
        mysql -h $MYSQL_IP -P 3306 -utrillian -p${MYSQL_PASS}  -D trillian -e 'DELETE FROM EntryIndex;'
    fi
    kubectl -n rekor-system rollout restart deployment rekor-server
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    if [ "${INDEX_BACKEND}" != "redis" -a "${INDEX_BACKEND}" != "mysql" ] ; then
        echo '$INDEX_BACKEND must be either redis or mysql.'
        exit 1
    fi

    if [ "${INDEX_BACKEND}" == "mysql" -a "${MYSQL_PASS}" == "" ] ; then
        echo '$MYSQL_PASS must be set when $INDEX_BACKEND is mysql.'
        echo 'The trillian mysql user password can be found from your terraform host using `terraform output -json | jq -r .mysql_pass.value`.'
        exit 1
    fi

    echo "Gathering insertion and retrieval metrics for index backend [${INDEX_BACKEND}]."

    setup_bastion

    setup_rekor

    setup_prometheus
    cleanup_prom() {
        echo "Cleaning up prometheus..."
        kill $PROM_PID
    }
    trap 'cleanup cleanup_prom' EXIT

    insert
    cleanup_all() {
        cleanup_prom
        rm -rf $DIR
        echo "Cleaning up keys..."
        delete_key example.com
    }
    trap 'cleanup cleanup_all' EXIT

    query_inserts

    upload

    search

    query_search

    reset
fi
