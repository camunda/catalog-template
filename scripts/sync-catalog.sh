#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Sync every catalog asset in this repository to the Camunda Hub Catalog.
#
# Discovers each asset directory (a README.md plus the .json element template it
# references in its frontmatter), builds a single multipart/form-data request,
# and submits the full desired state to the Hub Catalog ingestion endpoint.
#
# Because the submission is the complete desired state, any asset that exists in
# the Catalog but is absent from this submission is unpublished.
#
# Required environment variables:
#   CAMUNDA_HUB_CLIENT_ID         OAuth client ID
#   CAMUNDA_HUB_CLIENT_SECRET     OAuth client secret
#   CAMUNDA_OAUTH_URL             Token issuer URL
#   CAMUNDA_HUB_REST_URL          Camunda Hub API base URL (without /api/v2)
#
# SaaS only:
#   CAMUNDA_HUB_OAUTH_AUDIENCE    Token audience (omit in Self-Managed)
#
# See README.md for the values to use in SaaS and Self-Managed.
# ──────────────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Authenticate -------------------------------------------------------------

echo "Requesting access token..."

# The audience parameter is only used in SaaS; omit it in Self-Managed.
AUDIENCE_ARG=()
if [[ -n "${CAMUNDA_HUB_OAUTH_AUDIENCE:-}" ]]; then
  AUDIENCE_ARG=(--data-urlencode "audience=${CAMUNDA_HUB_OAUTH_AUDIENCE}")
fi

ACCESS_TOKEN=$(curl --silent --fail --request POST "${CAMUNDA_OAUTH_URL}" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  "${AUDIENCE_ARG[@]}" \
  --data-urlencode "client_id=${CAMUNDA_HUB_CLIENT_ID}" \
  --data-urlencode "client_secret=${CAMUNDA_HUB_CLIENT_SECRET}" | jq -r '.access_token')

if [[ -z "${ACCESS_TOKEN}" || "${ACCESS_TOKEN}" == "null" ]]; then
  echo "Error: failed to obtain an access token." >&2
  exit 1
fi

echo "Authentication successful."

# --- Collect each asset's template and README parts ---------------------------
#
# The multipart filename carries the asset directory as a prefix (for example,
# notify-customer/README.md) so Hub can resolve the README's `template:`
# reference relative to that directory and pair the two parts.

FORM_ARGS=()
ASSET_COUNT=0

while IFS= read -r -d '' readme; do
  asset_dir="$(dirname "${readme}")"
  rel_dir="${asset_dir#"${REPO_ROOT}/"}"

  # Read the template filename from the README frontmatter `template:` field.
  template_filename=$(awk '
    /^---[[:space:]]*$/ { delim++; next }
    delim == 1 && /^template:/ { sub(/^template:[[:space:]]*/, ""); print; exit }
  ' "${readme}")

  if [[ -z "${template_filename}" ]]; then
    echo "Warning: ${rel_dir}/README.md has no 'template:' frontmatter — skipping." >&2
    continue
  fi

  template_path="${asset_dir}/${template_filename}"
  if [[ ! -f "${template_path}" ]]; then
    echo "Warning: ${rel_dir}/${template_filename} not found — skipping." >&2
    continue
  fi

  FORM_ARGS+=(-F "template=@${template_path};type=application/json;filename=${rel_dir}/${template_filename}")
  FORM_ARGS+=(-F "readme=@${readme};type=text/markdown;filename=${rel_dir}/README.md")
  ASSET_COUNT=$((ASSET_COUNT + 1))
done < <(find "${REPO_ROOT}" -name README.md \
  -not -path '*/.git/*' \
  -not -path '*/.github/*' \
  -not -path "${REPO_ROOT}/README.md" \
  -print0 | sort -z)

if [[ "${ASSET_COUNT}" -eq 0 ]]; then
  echo "No assets found. Each asset needs a directory with a README.md and the" >&2
  echo "JSON element template it references in its 'template:' frontmatter." >&2
  exit 1
fi

echo "Submitting ${ASSET_COUNT} asset(s) to the Catalog..."

# --- Submit the full desired state --------------------------------------------

HTTP_STATUS=$(curl --silent --output /dev/null --write-out '%{http_code}' --request PUT \
  "${CAMUNDA_HUB_REST_URL}/api/v2/catalog/assets/ingestion" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${FORM_ARGS[@]}")

if [[ "${HTTP_STATUS}" == "204" ]]; then
  echo "Catalog sync completed successfully."
else
  echo "Error: Catalog sync failed (HTTP ${HTTP_STATUS})." >&2
  exit 1
fi
