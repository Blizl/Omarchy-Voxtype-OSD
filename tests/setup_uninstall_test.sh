#!/usr/bin/env bash
#
# tests/setup_uninstall_test.sh - End-to-End Setup & Uninstall Lifecycle Tests
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/voxtype-config.sh"

setup_test_work_dir

test_setup_uninstall_round_trip() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"
  local original_config_content
  original_config_content="$(<"$VOXTYPE_CONFIG_FILE")"

  # Execute setup
  "$PROJECT_ROOT/bin/setup" --yes --skip-service

  # Verify installation
  assert_file_exists "$BLIZL_VOXTYPE_OSD_STATE_DIR/install.json"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/shell.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/OsdSurface.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/voxtype-shared/Theme.qml"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "enabled")" "true" "osd.enabled is true"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "frontend")" "quickshell" "osd.frontend is quickshell"
  pass "Setup successfully installed QML components and configured VoxType"

  # Execute uninstall
  "$PROJECT_ROOT/bin/uninstall" --skip-service

  # Verify uninstallation & restoration
  assert_path_not_exists "$BLIZL_VOXTYPE_OSD_STATE_DIR/install.json"
  assert_path_not_exists "$VOXTYPE_QUICKSHELL_DIR/shell.qml"
  assert_eq "$(<"$VOXTYPE_CONFIG_FILE")" "$original_config_content" "config.toml restored to exact original"
  pass "Uninstall successfully restored config.toml and removed installed files"
}

test_setup_idempotency() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"

  # Run setup first time
  "$PROJECT_ROOT/bin/setup" --yes --skip-service
  local config_after_first
  config_after_first="$(<"$VOXTYPE_CONFIG_FILE")"

  # Run setup second time
  "$PROJECT_ROOT/bin/setup" --yes --skip-service
  local config_after_second
  config_after_second="$(<"$VOXTYPE_CONFIG_FILE")"

  assert_eq "$config_after_first" "$config_after_second" "config.toml identical after second setup run"
  assert_file_exists "$BLIZL_VOXTYPE_OSD_STATE_DIR/install.json"
  pass "Setup is completely idempotent"

  # Clean uninstall
  "$PROJECT_ROOT/bin/uninstall" --skip-service
}

test_setup_creates_fresh_environment() {
  make_temp_home
  rm -f -- "$VOXTYPE_CONFIG_FILE"
  rm -rf -- "$VOXTYPE_QUICKSHELL_DIR"

  # Run setup in empty environment
  "$PROJECT_ROOT/bin/setup" --yes --skip-service

  assert_file_exists "$VOXTYPE_CONFIG_FILE"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/shell.qml"
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "enabled")" "true"

  # Uninstall should remove created files cleanly
  "$PROJECT_ROOT/bin/uninstall" --skip-service
  assert_path_not_exists "$VOXTYPE_CONFIG_FILE"
  assert_path_not_exists "$VOXTYPE_QUICKSHELL_DIR/shell.qml"
  pass "Setup and uninstall work cleanly in fresh/empty environment"
}

# Run tests
printf 'Running setup_uninstall_test.sh:\n'
test_setup_uninstall_round_trip
test_setup_idempotency
test_setup_creates_fresh_environment
printf 'All setup/uninstall lifecycle tests passed.\n'
