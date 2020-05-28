#!/usr/bin/env bash

# Get Absolute Path of the base repo
export REPO_ROOT=$(git rev-parse --show-toplevel)

need() {
    if ! [ -x "$(command -v $1)" ]; then
      echo "Error: Unable to find binary $1"
      exit 1
    fi
}

# Verify we have dependencies
need "kubeseal"
need "kubectl"
need "sed"
need "envsubst"
need "yq"

# Work-arounds for MacOS
if [ "$(uname)" == "Darwin" ]; then
  # brew install gnu-sed
  need "gsed"
  # use sed as alias to gsed
  export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
  # Source secrets.env
  set -a
  . "${REPO_ROOT}/secrets/.secrets.env"
  set +a
else
  . "${REPO_ROOT}/secrets/.secrets.env"
fi

# Path to Public Cert
PUB_CERT="${REPO_ROOT}/secrets/pub-cert.pem"

# Path to generated secrets file
GENERATED_SECRETS="${REPO_ROOT}/deployments/zz_generated_secrets.yaml"

{
  echo "#"
  echo "# Manifests generated by secrets.sh -- DO NOT EDIT."
  echo "#"
  echo "---"
} > "${GENERATED_SECRETS}"

#
# Helm Secrets
#

# Generate Helm Secrets
for file in "${REPO_ROOT}"/secrets/helm-templates/*.txt
do
  # Get the path and basename of the txt file
  # e.g. "deployments/default/pihole/pihole"
  secret_path="$(dirname "$file")/$(basename -s .txt "$file")"
  
  # Get the filename without extension
  # e.g. "pihole"
  secret_name=$(basename "${secret_path}")
  
  # Find namespace by looking for the chart file in the deployments folder
  namespace="$(find ${REPO_ROOT}/deployments -type f -name "${secret_name}.yaml" | awk -F/ '{print $(NF-1)}')"
  echo "  Generating helm secret '${secret_name}' in namespace '${namespace}'..."

  # Create secret
  envsubst < "$file" \
    | \
  kubectl -n "${namespace}" create secret generic "${secret_name}-helm-values" \
    --from-file=/dev/stdin --dry-run=client -o json \
    | \
  kubeseal --format=yaml --cert="${PUB_CERT}" \
    >> "${GENERATED_SECRETS}"

  echo "---" >> "${GENERATED_SECRETS}"
done

# Replace stdin with values.yaml
sed -i 's/stdin\:/values.yaml\:/g' "${GENERATED_SECRETS}"

#
# Generic Secrets
#

{
  echo "#"
  echo "# Generic Secrets generated by secrets.sh -- DO NOT EDIT."
  echo "#"
} >> "${GENERATED_SECRETS}"

# NginX Basic Auth - default namespace
kubectl create secret generic nginx-basic-auth \
  --from-literal=auth="${NGINX_BASIC_AUTH}" \
  --namespace default --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# NginX Basic Auth - kube-system namespace
kubectl create secret generic nginx-basic-auth \
  --from-literal=auth="${NGINX_BASIC_AUTH}" \
  --namespace kube-system --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# NginX Basic Auth - monitoring namespace
kubectl create secret generic nginx-basic-auth \
  --from-literal=auth="${NGINX_BASIC_AUTH}" \
  --namespace monitoring --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# Cloudflare API Key - cert-manager namespace
kubectl create secret generic cloudflare-api-key \
  --from-literal=api-key="${CF_API_KEY}" \
  --namespace cert-manager --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# qBittorrent Prune - default namespace
kubectl create secret generic qbittorrent-prune \
  --from-literal=username="${QB_USERNAME}" \
  --from-literal=password="${QB_PASSWORD}" \
  --namespace default --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# sonarr episode prune - default namespace
kubectl create secret generic sonarr-episode-prune \
  --from-literal=api-key="${SONARR_APIKEY}" \
  --namespace default --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# sonarr exporter
kubectl create secret generic sonarr-exporter \
  --from-literal=api-key="${SONARR_APIKEY}" \
  --namespace monitoring --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# radarr exporter
kubectl create secret generic radarr-exporter \
  --from-literal=api-key="${RADARR_APIKEY}" \
  --namespace monitoring --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# uptimerobot heartbeat
kubectl create secret generic uptimerobot-heartbeat \
  --from-literal=url="${UPTIMEROBOT_HEARTBEAT_URL}" \
  --namespace monitoring --dry-run=client -o json \
  | \
kubeseal --format=yaml --cert="${PUB_CERT}" \
  >> "${GENERATED_SECRETS}"
echo "---" >> "${GENERATED_SECRETS}"

# Remove empty new-lines
sed -i '/^[[:space:]]*$/d' "${GENERATED_SECRETS}"

# Validate Yaml
if ! yq validate "${GENERATED_SECRETS}" > /dev/null 2>&1; then
    echo "Errors in YAML"
    exit 1
else
    echo "** YAML looks good, ready to commit"
fi

#
# Kubernetes Manifests w/ Secrets
#

# for file in "${REPO_ROOT}"/secrets/manifest-templates/*.txt
# do
#   # Get the path and basename of the txt file
#   secret_path="$(dirname "$file")/$(basename -s .txt "$file")"
#   # Get the filename without extension
#   secret_name=$(basename "${secret_path}")
#   echo "  Applying manifest ${secret_name} to cluster..."
#   # Apply this manifest to our cluster
#   if output=$(envsubst < "$file"); then
#     printf '%s' "$output" | kubectl apply -f -
#   fi
# done