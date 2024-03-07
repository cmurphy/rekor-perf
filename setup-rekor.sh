#!/bin/bash -e

if [ -z "${MYSQL_PASS}" ] ; then
    echo 'Set $MYSQL_PASS for the trillian mysql user. This value can be found from your terraform host using `terraform output -json | jq -r .mysql_pass.value`.'
    exit 1
fi

helm repo add sigstore https://sigstore.github.io/helm-charts
helm repo update

sha=$(git ls-remote https://github.com/sigstore/rekor HEAD | awk '{print substr($1, 1, 7)}')
redis_ip=$(gcloud redis instances describe rekor-index --region us-west1 --format='get(host)')
mysql_ip=$(gcloud sql instances describe rekor-perf-tf --format='get(ipAddresses[0].ipAddress)')
cat >values.yaml <<EOF
redis:
  enabled: false
  hostname: $redis_ip
server:
  ingress:
    enabled: false
  image:
    repository: projectsigstore/rekor/ci/rekor/rekor-server
    version: $sha
EOF

helm upgrade -i rekor sigstore/rekor -n rekor-system --create-namespace --values values.yaml
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

cat >redis-args-values.yaml <<EOF
server:
  extraArgs:
    - --search_index.storage_provider=redis
EOF
cat >mysql-args-values.yaml <<EOF
server:
  extraArgs:
    - --search_index.storage_provider=mysql
    - --search_index.mysql.dsn=trillian:\$(MYSQL_PASSWORD)@tcp(${mysql_ip}:3306)/trillian
EOF

if [ "${INDEX_BACKEND}" == "redis" ] ; then
    helm upgrade rekor sigstore/rekor -n rekor-system --values values.yaml --values redis-args-values.yaml
else
    helm upgrade rekor sigstore/rekor -n rekor-system --values values.yaml --values mysql-args-values.yaml
    kubectl -n rekor-system patch deployment rekor-server --patch-file=patch.yaml
fi
kubectl -n rekor-system rollout status deployment rekor-server


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

echo -n > settings.vars
node_address=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo export REKOR_URL=http://${node_address}:30080 >> settings.vars
echo export REKOR_METRICS=${node_address}:32112 >> settings.vars
