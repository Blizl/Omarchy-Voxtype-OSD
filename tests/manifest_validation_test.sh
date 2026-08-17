#!/usr/bin/env bash
#
# tests/manifest_validation_test.sh - Plugin Manifest & Schema Validation Tests
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"

setup_test_work_dir

test_manifest_schema_and_integrity() {
  local manifest="$PROJECT_ROOT/manifest.json"
  assert_file_exists "$manifest"

  # Validate JSON syntax
  jq -e . "$manifest" >/dev/null || fail "manifest.json is not valid JSON"

  # Validate schemaVersion
  assert_eq "$(jq -r '.schemaVersion' "$manifest")" "1" "schemaVersion is 1"

  # Validate id format
  local id
  id="$(jq -r '.id' "$manifest")"
  assert_eq "$id" "blizl.voxtype-osd" "id is blizl.voxtype-osd"
  [[ "$id" != omarchy.* ]] || fail "id uses reserved omarchy.* namespace"

  # Validate required fields
  for field in id name version kinds entryPoints; do
    jq -e --arg f "$field" 'has($f)' "$manifest" >/dev/null || fail "Missing required field: $field"
  done

  # Validate entryPoints exist
  while IFS= read -r ep; do
    assert_file_exists "$PROJECT_ROOT/$ep"
  done < <(jq -r '.entryPoints | to_entries[] | .value' "$manifest")

  pass "manifest.json passes all schema requirements"
}

test_omarchy_plugin_validate() {
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin validate "$PROJECT_ROOT" || fail "omarchy plugin validate failed on $PROJECT_ROOT"
    pass "omarchy plugin validate succeeded with zero errors"
  else
    pass "omarchy CLI not available in environment; skipping CLI validation"
  fi
}

# Run tests
printf 'Running manifest_validation_test.sh:\n'
test_manifest_schema_and_integrity
test_omarchy_plugin_validate
printf 'All manifest validation tests passed.\n'
