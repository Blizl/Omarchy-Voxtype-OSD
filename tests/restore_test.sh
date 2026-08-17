#!/usr/bin/env bash
#
# tests/restore_test.sh - Unit & Integration Tests for Recovery Utility
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/voxtype-config.sh"

setup_test_work_dir

test_restore_from_latest_backup() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"
  local original_content
  original_content="$(<"$VOXTYPE_CONFIG_FILE")"

  # Run setup
  "$PROJECT_ROOT/bin/setup" --yes --skip-service

  # Modify config manually
  echo "corrupted config" >"$VOXTYPE_CONFIG_FILE"

  # Run restore
  "$PROJECT_ROOT/bin/restore" --latest

  assert_eq "$(<"$VOXTYPE_CONFIG_FILE")" "$original_content" "config restored from latest backup"
  pass "bin/restore --latest restored config to pre-setup state"
}

test_restore_stock_defaults() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"

  # Run setup
  "$PROJECT_ROOT/bin/setup" --yes --skip-service
  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "enabled")" "true"

  # Run restore --stock
  "$PROJECT_ROOT/bin/restore" --stock

  assert_eq "$(voxtype_config_get_value "$VOXTYPE_CONFIG_FILE" "osd" "enabled")" "false" "osd disabled"
  assert_path_not_exists "$VOXTYPE_QUICKSHELL_DIR/shell.qml"
  pass "bin/restore --stock cleanly disabled OSD and removed components"
}

test_restore_list_command() {
  make_temp_home
  "$PROJECT_ROOT/bin/setup" --yes --skip-service

  local list_output
  list_output="$("$PROJECT_ROOT/bin/restore" --list)"
  assert_contains "$list_output" "Available snapshot checkpoints"
  pass "bin/restore --list executed successfully"
}

# Run tests
printf 'Running restore_test.sh:\n'
test_restore_from_latest_backup
test_restore_stock_defaults
test_restore_list_command
printf 'All restore tests passed.\n'
