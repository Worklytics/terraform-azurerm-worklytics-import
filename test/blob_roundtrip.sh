#!/usr/bin/env bash
# Prove the Worklytics GCP identity can read and write blobs in the import container
# via Google → Entra workload identity federation.
#
# Usage:
#   ./test/blob_roundtrip.sh \
#     <tenant_sa_email> \
#     <storage_account_name> \
#     <container_name> \
#     <azure_tenant_id> \
#     <entra_application_client_id>
#
# Prerequisites:
#   - gcloud authenticated as an identity that can impersonate tenant_sa_email
#   - az
set -euo pipefail

TENANT_SA_EMAIL="${1:?tenant SA email required}"
STORAGE_ACCOUNT="${2:?storage account name required}"
CONTAINER="${3:?container name required}"
AZURE_TENANT_ID="${4:?azure tenant id required}"
CLIENT_ID="${5:?entra application client id required}"

CI_RUN="${CI_RUN:-$(date +%Y%m%dT%H%M%S)}"
BLOB_NAME="ci/${CI_RUN}/test.txt"
BLOB_BODY="worklytics-import-ci ${CI_RUN}"
AUDIENCE="api://AzureADTokenExchange"

echo "TENANT_SA_EMAIL: ${TENANT_SA_EMAIL}"
echo "STORAGE_ACCOUNT: ${STORAGE_ACCOUNT}"
echo "CONTAINER: ${CONTAINER}"
echo "BLOB: ${BLOB_NAME}"

# Isolated Azure CLI profile so this login does not replace the workflow's
# azure/login session (later steps still need az as the CI service principal).
AZURE_CONFIG_DIR="$(mktemp -d)"
export AZURE_CONFIG_DIR
trap 'rm -rf "${AZURE_CONFIG_DIR}"' EXIT

# Identity token whose aud claim matches the Entra federated credential audience.
GCP_TOKEN="$(gcloud auth print-identity-token \
  --impersonate-service-account="${TENANT_SA_EMAIL}" \
  --audiences="${AUDIENCE}")"

retry() {
  local attempt=1
  local max_attempts=12
  local delay=10
  while (( attempt <= max_attempts )); do
    if "$@"; then
      return 0
    fi
    echo "Attempt ${attempt}/${max_attempts} failed." >&2
    sleep "${delay}"
    delay=$(( delay < 40 ? delay * 2 : 40 ))
    attempt=$(( attempt + 1 ))
  done
  echo "Giving up after ${max_attempts} attempts." >&2
  return 1
}

az_federated_login() {
  az login --service-principal \
    -u "${CLIENT_ID}" \
    --tenant "${AZURE_TENANT_ID}" \
    --federated-token "${GCP_TOKEN}" \
    --allow-no-subscriptions \
    --output none
}

put_blob() {
  local tmp
  tmp="$(mktemp)"
  printf '%s' "${BLOB_BODY}" > "${tmp}"
  az storage blob upload \
    --account-name "${STORAGE_ACCOUNT}" \
    --container-name "${CONTAINER}" \
    --name "${BLOB_NAME}" \
    --file "${tmp}" \
    --auth-mode login \
    --overwrite \
    --output none
  rm -f "${tmp}"
}

get_blob() {
  az storage blob download \
    --account-name "${STORAGE_ACCOUNT}" \
    --container-name "${CONTAINER}" \
    --name "${BLOB_NAME}" \
    --file "${DOWNLOAD_FILE}" \
    --auth-mode login \
    --no-progress \
    --output none
}

echo "Logging in to Azure as the federated Worklytics identity..."
retry az_federated_login

# RBAC on a newly created assignment can take a minute or two to become effective.
echo "Writing blob as federated GCP identity..."
retry put_blob

echo "Reading blob as federated GCP identity..."
DOWNLOAD_FILE="$(mktemp)"
retry get_blob
DOWNLOADED="$(cat "${DOWNLOAD_FILE}")"
rm -f "${DOWNLOAD_FILE}"

if [[ "${DOWNLOADED}" != "${BLOB_BODY}" ]]; then
  echo "Blob content mismatch." >&2
  echo "expected: ${BLOB_BODY}" >&2
  echo "actual:   ${DOWNLOADED}" >&2
  exit 1
fi

echo "Read/write round-trip succeeded."
