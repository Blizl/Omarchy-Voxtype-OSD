#!/usr/bin/env bash
#
# tests/helpers/test_helper.sh - Common Test Helper & Mock Environment
#

set -euo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_ROOT="$(cd -- "$TESTS_DIR/.." && pwd -P)"
export PROJECT_ROOT TESTS_DIR

WORK_DIR=""
FIXTURE_COUNT=0

setup_test_work_dir() {
  WORK_DIR="$(mktemp -d "/tmp/voxtype-osd-test.XXXXXX")"
  trap 'cleanup_test_work_dir' EXIT
}

cleanup_test_work_dir() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}

make_temp_home() {
  FIXTURE_COUNT=$((FIXTURE_COUNT + 1))
  local home="$WORK_DIR/home-$FIXTURE_COUNT"
  mkdir -p -- "$home/.config/voxtype" "$home/.local/share/voxtype" "$home/.local/state/blizl.voxtype-osd" "$home/.local/bin"

  export HOME="$home"
  export XDG_CONFIG_HOME="$home/.config"
  export XDG_DATA_HOME="$home/.local/share"
  export XDG_STATE_HOME="$home/.local/state"
  export VOXTYPE_CONFIG_FILE="$home/.config/voxtype/config.toml"
  export VOXTYPE_QUICKSHELL_DIR="$home/.local/share/voxtype/quickshell"
  export BLIZL_VOXTYPE_OSD_STATE_DIR="$home/.local/state/blizl.voxtype-osd"
  export BLIZL_VOXTYPE_SKIP_SERVICE=true
  export BLIZL_VOXTYPE_NONINTERACTIVE=true
  export BLIZL_VOXTYPE_CONFIRM=yes
  export BLIZL_VOXTYPE_SKIP_DEPENDENCY_CHECK=true
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="${3:-}"
  if [[ "$actual" != "$expected" ]]; then
    fail "${msg:+$msg: }Expected [$expected], got [$actual]"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "$path" ]] || fail "Expected file to exist: $path"
}

assert_dir_exists() {
  local path="$1"
  [[ -d "$path" ]] || fail "Expected directory to exist: $path"
}

assert_path_not_exists() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "Expected path NOT to exist: $path"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "${msg:+$msg: }Expected string to contain [$needle], but it did not. Content: $haystack"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "${msg:+$msg: }Expected string NOT to contain [$needle], but it did."
  fi
}

pass() {
  printf '  ✓ %s\n' "$*"
}
