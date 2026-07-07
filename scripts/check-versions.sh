#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Fail if any changed element template's content changed without its `version`
# field increasing.
#
# The Camunda Hub Catalog rejects a submission when a template's content changed
# but its `version` is not greater than the latest stored version. This check
# catches that mistake in a pull request, before the sync runs against the
# Catalog.
#
# It mirrors the Catalog's own rule: the `version` field is ignored when the
# template content (everything except `version`) is unchanged, so a README-only
# edit does not require a bump.
#
# Usage:
#   bash scripts/check-versions.sh [BASE_REF]
#
# BASE_REF is the git ref to compare against (default: origin/main). Every asset
# whose template file differs from BASE_REF is validated.
# ──────────────────────────────────────────────────────────────────────────────

BASE_REF="${1:-origin/main}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
checked=0

# Discover assets the same way the sync script does: a README.md plus the .json
# element template it references in its `template:` frontmatter.
while IFS= read -r -d '' readme; do
  asset_dir="$(dirname "${readme}")"
  rel_dir="${asset_dir#"${REPO_ROOT}/"}"

  template_filename=$(awk '
    /^---[[:space:]]*$/ { delim++; next }
    delim == 1 && /^template:/ { sub(/^template:[[:space:]]*/, ""); print; exit }
  ' "${readme}")

  [[ -z "${template_filename}" ]] && continue

  template_path="${asset_dir}/${template_filename}"
  rel_path="${rel_dir}/${template_filename}"
  [[ -f "${template_path}" ]] || continue

  # Skip assets whose template did not change in this branch.
  if git diff --quiet "${BASE_REF}" -- "${template_path}"; then
    continue
  fi

  # A template that does not exist in the base ref is a new asset — nothing to
  # compare against, so any version is acceptable.
  if ! git cat-file -e "${BASE_REF}:${rel_path}" 2>/dev/null; then
    echo "✓ ${rel_path}: new asset"
    checked=$((checked + 1))
    continue
  fi

  old_json="$(git show "${BASE_REF}:${rel_path}")"

  # Compare content excluding `version`. If it is unchanged, the Catalog treats
  # the submission as identical and no bump is required.
  old_content="$(echo "${old_json}" | jq -S 'del(.version)')"
  new_content="$(jq -S 'del(.version)' "${template_path}")"

  if [[ "${old_content}" == "${new_content}" ]]; then
    echo "✓ ${rel_path}: content unchanged (no version bump required)"
    checked=$((checked + 1))
    continue
  fi

  old_version="$(echo "${old_json}" | jq -r '.version // empty')"
  new_version="$(jq -r '.version // empty' "${template_path}")"

  if [[ -z "${new_version}" ]]; then
    echo "✗ ${rel_path}: content changed but 'version' is missing. The Catalog requires a version." >&2
    failures=$((failures + 1))
    continue
  fi

  # Numeric comparison. Reject anything that is not a strict increase.
  if ! awk -v a="${old_version}" -v b="${new_version}" 'BEGIN { exit !(b > a) }'; then
    echo "✗ ${rel_path}: content changed but 'version' did not increase (${old_version} → ${new_version}). Increment the version." >&2
    failures=$((failures + 1))
    continue
  fi

  echo "✓ ${rel_path}: version ${old_version} → ${new_version}"
  checked=$((checked + 1))
done < <(find "${REPO_ROOT}" -name README.md \
  -not -path '*/.git/*' \
  -not -path '*/.github/*' \
  -not -path "${REPO_ROOT}/README.md" \
  -print0 | sort -z)

echo
if [[ "${failures}" -gt 0 ]]; then
  echo "Version check failed: ${failures} asset(s) need a version increment." >&2
  exit 1
fi

echo "Version check passed (${checked} changed asset(s) validated)."
