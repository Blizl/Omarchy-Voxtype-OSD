#!/usr/bin/env bash
#
# tests/config_test.sh - Unit Tests for VoxType TOML Config Parser & Modifier
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/voxtype-config.sh"

setup_test_work_dir

test_config_reads_existing_values() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"

  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "hotkey" "enabled")" "true" "read hotkey.enabled"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "hotkey" "key")" "space" "read hotkey.key"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "audio" "sample_rate")" "16000" "read audio.sample_rate"
  pass "Reads existing TOML sections and values accurately"
}

test_config_adds_osd_section_to_clean_file() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"

  voxtype_config_configure_osd "$VOXTYPE_CONFIG_FILE" "true" "quickshell" "bottom-center" "320" "48" "80" "0.96" "12.0"

  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "enabled")" "true" "osd.enabled"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "frontend")" "quickshell" "osd.frontend"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "position")" "bottom-center" "osd.position"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "width_px")" "320" "osd.width_px"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "height_px")" "48" "osd.height_px"

  # Ensure original comments and sections are preserved
  local content
  content="$(<"$VOXTYPE_CONFIG_FILE")"
  assert_contains "$content" "# Hotkey activation settings" "comments preserved"
  assert_contains "$content" "sample_rate = 16000" "audio section preserved"
  pass "Appends [osd] section cleanly while preserving existing content"
}

test_config_updates_existing_osd_section() {
  make_temp_home
  cat <<EOF >"$VOXTYPE_CONFIG_FILE"
[hotkey]
enabled = true

[osd]
enabled = false
frontend = "egui"
position = "top-left"
EOF

  voxtype_config_configure_osd "$VOXTYPE_CONFIG_FILE" "true" "quickshell" "bottom-center" "400" "56" "100" "0.90" "15.0"

  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "enabled")" "true" "osd.enabled updated"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "frontend")" "quickshell" "osd.frontend updated"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "position")" "bottom-center" "osd.position updated"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "width_px")" "400" "osd.width_px updated"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "waveform_gain")" "15.0" "osd.waveform_gain added"
  pass "Updates existing [osd] section in place without duplicates"
}

test_config_disables_osd() {
  make_temp_home
  cat <<EOF >"$VOXTYPE_CONFIG_FILE"
[osd]
enabled = true # inline comment
frontend = "quickshell"
EOF

  voxtype_config_disable_osd "$VOXTYPE_CONFIG_FILE"

  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "enabled")" "false" "osd disabled"
  if voxtype_config_is_osd_enabled "$VOXTYPE_CONFIG_FILE"; then
    fail "is_osd_enabled should return false"
  fi
  pass "Disables OSD cleanly"
}

test_config_creates_new_file_if_missing() {
  make_temp_home
  rm -f -- "$VOXTYPE_CONFIG_FILE"

  voxtype_config_configure_osd "$VOXTYPE_CONFIG_FILE" "true" "quickshell"

  assert_file_exists "$VOXTYPE_CONFIG_FILE"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "frontend")" "quickshell"
  pass "Creates brand new config.toml if none exists"
}

# Run tests
printf 'Running config_test.sh:\n'
test_config_reads_existing_values
test_config_adds_osd_section_to_clean_file
test_config_updates_existing_osd_section
test_config_disables_osd
test_config_creates_new_file_if_missing
printf 'All config tests passed.\n'
