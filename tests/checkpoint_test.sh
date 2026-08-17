#!/usr/bin/env bash
#
# tests/checkpoint_test.sh - Unit Tests for Checkpoint Snapshot Manager
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/checkpoint.sh"

setup_test_work_dir

test_checkpoint_create_verify_and_restore() {
  make_temp_home
  echo "original config" >"$VOXTYPE_CONFIG_FILE"
  mkdir -p -- "$VOXTYPE_QUICKSHELL_DIR"
  echo "original qml" >"$VOXTYPE_QUICKSHELL_DIR/shell.qml"

  # Create checkpoint
  local cp_id
  cp_id="$(checkpoint_create)"
  [[ -n "$cp_id" ]] || fail "Checkpoint creation failed"
  checkpoint_verify "$cp_id" || fail "Checkpoint verification failed"
  pass "Checkpoint created and verified successfully: $cp_id"

  # Mutate files
  echo "modified config" >"$VOXTYPE_CONFIG_FILE"
  echo "modified qml" >"$VOXTYPE_QUICKSHELL_DIR/shell.qml"

  # Restore
  checkpoint_restore "$cp_id"
  assert_eq "$(<"$VOXTYPE_CONFIG_FILE")" "original config" "config restored"
  assert_eq "$(<"$VOXTYPE_QUICKSHELL_DIR/shell.qml")" "original qml" "quickshell restored"
  pass "Checkpoint restored files to exact baseline state"

  # List
  local list
  list="$(checkpoint_list)"
  assert_contains "$list" "$cp_id" "listed checkpoint"
  pass "Checkpoint appears in checkpoint_list"

  # Discard
  checkpoint_discard "$cp_id"
  local remaining
  remaining="$(checkpoint_list)"
  assert_not_contains "$remaining" "$cp_id" "discarded checkpoint"
  pass "Checkpoint discarded cleanly"
}

# Run tests
printf 'Running checkpoint_test.sh:\n'
test_checkpoint_create_verify_and_restore
printf 'All checkpoint tests passed.\n'
