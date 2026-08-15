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
#   - curl, jq
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
TOKEN_URL="https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token"
BLOB_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${BLOB_NAME}"

echo "TENANT_SA_EMAIL: ${TENANT_SA_EMAIL}"
echo "STORAGE_ACCOUNT: ${STORAGE_ACCOUNT}"
echo "CONTAINER: ${CONTAINER}"
echo "BLOB: ${BLOB_NAME}"

# Identity token whose aud claim matches the Entra federated credential audience.
GCP_TOKEN="$(gcloud auth print-identity-token \
  --impersonate-service-account="${TENANT_SA_EMAIL}" \
  --audiences="${AUDIENCE}")"

exchange_azure_token() {
  local response access_token
  response="$(curl -sS -X POST "${TOKEN_URL}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "scope=https://storage.azure.com/.default" \
    --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    --data-urlencode "client_assertion=${GCP_TOKEN}" \
    --data-urlencode "grant_type=client_credentials")"

  access_token="$(printf '%s' "${response}" | jq -r '.access_token // empty')"
  if [[ -z "${access_token}" || "${access_token}" == "null" ]]; then
    echo "Failed to exchange Google ID token for an Entra access token:" >&2
    printf '%s' "${response}" | jq -c 'del(.access_token)' >&2 || printf '%s\n' "${response}" >&2
    return 1
  fi
  printf '%s' "${access_token}"
}

retry() {
  local attempt=1
  local max_attempts=12
  local delay=10
  local output
  while (( attempt <= max_attempts )); do
    if output="$("$@" 2>&1)"; then
      printf '%s' "${output}"
      return 0
    fi
    echo "Attempt ${attempt}/${max_attempts} failed: ${output}" >&2
    sleep "${delay}"
    delay=$(( delay < 40 ? delay * 2 : 40 ))
    attempt=$(( attempt + 1 ))
  done
  echo "Giving up after ${max_attempts} attempts." >&2
  return 1
}

echo "Exchanging Google ID token for Entra access token..."
AZURE_TOKEN="$(retry exchange_azure_token)"

# RBAC on a newly created assignment can take a minute or two to become effective.
put_blob() {
  curl -sS -f -X PUT "${BLOB_URL}" \
    -H "Authorization: Bearer ${AZURE_TOKEN}" \
    -H "x-ms-version: 2023-11-03" \
    -H "x-ms-blob-type: BlockBlob" \
    -H "Content-Type: text/plain" \
    --data "${BLOB_BODY}"
}

get_blob() {
  curl -sS -f -X GET "${BLOB_URL}" \
    -H "Authorization: Bearer ${AZURE_TOKEN}" \
    -H "x-ms-version: 2023-11-03"
}

echo "Writing blob as federated GCP identity..."
retry put_blob

echo "Reading blob as federated GCP identity..."
DOWNLOADED="$(retry get_blob)"

if [[ "${DOWNLOADED}" != "${BLOB_BODY}" ]]; then
  echo "Blob content mismatch." >&2
  echo "expected: ${BLOB_BODY}" >&2
  echo "actual:   ${DOWNLOADED}" >&2
  exit 1
fi

echo "Read/write round-trip succeeded."
