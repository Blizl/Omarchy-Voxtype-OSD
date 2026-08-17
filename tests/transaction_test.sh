#!/usr/bin/env bash
#
# tests/transaction_test.sh - Unit Tests for Transaction Rollback Manager
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/transaction.sh"

setup_test_work_dir

test_transaction_restores_modified_file() {
  make_temp_home
  local test_file="$HOME/.config/test.txt"
  echo "original content" >"$test_file"

  transaction_begin "$BLIZL_VOXTYPE_OSD_STATE_DIR"
  transaction_backup "$test_file"

  echo "modified content" >"$test_file"
  assert_eq "$(<"$test_file")" "modified content"

  transaction_restore "$TRANSACTION_DIR"
  assert_eq "$(<"$test_file")" "original content" "file reverted"
  pass "Transaction cleanly reverts modified file"
}

test_transaction_removes_created_file() {
  make_temp_home
  local new_file="$HOME/.config/new_file.txt"
  rm -f -- "$new_file"

  transaction_begin "$BLIZL_VOXTYPE_OSD_STATE_DIR"
  transaction_backup "$new_file"

  echo "created file" >"$new_file"
  assert_file_exists "$new_file"

  transaction_restore "$TRANSACTION_DIR"
  assert_path_not_exists "$new_file"
  pass "Transaction cleanly deletes newly created file on rollback"
}

test_transaction_rejects_unsafe_target() {
  make_temp_home
  local unsafe_file="/etc/shadow"

  transaction_begin "$BLIZL_VOXTYPE_OSD_STATE_DIR"
  if transaction_backup "$unsafe_file" 2>/dev/null; then
    fail "Should have rejected unsafe path: $unsafe_file"
  fi
  pass "Rejects unsafe paths outside allowed home subdirectories"
}

# Run tests
printf 'Running transaction_test.sh:\n'
test_transaction_restores_modified_file
test_transaction_removes_created_file
test_transaction_rejects_unsafe_target
printf 'All transaction tests passed.\n'
