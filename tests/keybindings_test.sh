#!/usr/bin/env bash
#
# tests/keybindings_test.sh - SUPER+E / SUPER+M panel keybinding installer tests
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/keybindings.sh"

setup_test_work_dir

# Force the static (file-based) conflict check regardless of the host session
unset HYPRLAND_INSTANCE_SIGNATURE || true

bindings_path() { printf '%s\n' "$HOME/.config/hypr/bindings.lua"; }

test_setup_adds_free_bindings_and_uninstall_removes_them() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"
  mkdir -p "$HOME/.config/hypr"
  printf -- '-- user file\no.bind("ALT + SPACE", "Toggle dictation", "voxtype record toggle")\n' >"$(bindings_path)"
  local original
  original="$(<"$(bindings_path)")"

  "$PROJECT_ROOT/bin/setup" --yes --skip-service

  assert_contains "$(<"$(bindings_path)")" 'o.bind("SUPER + E", "VoxType engine picker"' "SUPER+E bound"
  assert_contains "$(<"$(bindings_path)")" 'o.bind("SUPER + M", "VoxType meeting controls"' "SUPER+M bound"
  assert_not_contains "$(<"$(bindings_path)")" 'hl.unbind' "no unbind when keys are free"
  assert_contains "$(<"$(bindings_path)")" 'ALT + SPACE' "user bindings preserved"
  assert_eq "$(jq -r .keybindingsInstalled "$BLIZL_VOXTYPE_OSD_STATE_DIR/install.json")" "true" "install.json records keybindings"
  pass "Setup adds SUPER+E / SUPER+M when free"

  # Idempotent: second run yields exactly one managed block
  "$PROJECT_ROOT/bin/setup" --yes --skip-service
  assert_eq "$(grep -c 'VoxType engine picker' "$(bindings_path)")" "1" "single engine bind after re-run"
  pass "Keybinding install is idempotent"

  "$PROJECT_ROOT/bin/uninstall" --skip-service
  assert_eq "$(<"$(bindings_path)")" "$original" "bindings.lua restored byte-for-byte"
  pass "Uninstall removes only the managed block"
}

test_conflicts_are_skipped_non_interactively_unless_override() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"
  mkdir -p "$HOME/.config/hypr"
  printf 'o.bind("SUPER + E", "Email", "xdg-open mailto:")\n' >"$(bindings_path)"

  "$PROJECT_ROOT/bin/setup" --yes --skip-service
  assert_not_contains "$(<"$(bindings_path)")" 'VoxType engine picker' "conflicting SUPER+E left alone"
  assert_contains "$(<"$(bindings_path)")" 'VoxType meeting controls' "free SUPER+M still bound"
  pass "Non-interactive setup skips conflicting keys"

  "$PROJECT_ROOT/bin/setup" --yes --skip-service --override-keybindings
  assert_contains "$(<"$(bindings_path)")" 'hl.unbind("SUPER + E")' "override unbinds existing SUPER+E"
  assert_contains "$(<"$(bindings_path)")" 'VoxType engine picker' "SUPER+E rebound to engine picker"
  assert_not_contains "$(<"$(bindings_path)")" 'hl.unbind("SUPER + M")' "free SUPER+M is not unbound"
  pass "--override-keybindings replaces conflicting keys"

  "$PROJECT_ROOT/bin/uninstall" --skip-service
  assert_eq "$(<"$(bindings_path)")" 'o.bind("SUPER + E", "Email", "xdg-open mailto:")' "original user bind restored"
  pass "Uninstall after override restores the user's binding"
}

test_skip_flag_and_missing_hypr_dir() {
  make_temp_home
  cp "$TESTS_DIR/fixtures/sample_config.toml" "$VOXTYPE_CONFIG_FILE"
  # No ~/.config/hypr at all
  "$PROJECT_ROOT/bin/setup" --yes --skip-service
  assert_path_not_exists "$(bindings_path)"
  pass "Setup does not create bindings.lua when Hyprland config is absent"
  "$PROJECT_ROOT/bin/uninstall" --skip-service

  mkdir -p "$HOME/.config/hypr"
  "$PROJECT_ROOT/bin/setup" --yes --skip-service --skip-keybindings
  assert_path_not_exists "$(bindings_path)"
  pass "--skip-keybindings leaves bindings untouched"
  "$PROJECT_ROOT/bin/uninstall" --skip-service
}

test_keybinding_in_use_detection() {
  local f="$WORK_DIR/detect.lua"
  printf 'o.bind("SUPER + M", "Music", "spotify")\n%s\no.bind("SUPER + E", "VoxType engine picker", "x")\n%s\n' \
    "$KEYBIND_MARK_BEGIN" "$KEYBIND_MARK_END" >"$f"
  keybinding_in_use "SUPER + M" "$f" >/dev/null || fail "SUPER + M should be detected as in use"
  if keybinding_in_use "SUPER + E" "$f" >/dev/null; then
    fail "our own managed SUPER + E must not count as a conflict"
  fi
  pass "Conflict detection ignores the managed block"
}

printf 'Running keybindings_test.sh:\n'
test_setup_adds_free_bindings_and_uninstall_removes_them
test_conflicts_are_skipped_non_interactively_unless_override
test_skip_flag_and_missing_hypr_dir
test_keybinding_in_use_detection
printf 'All keybinding tests passed.\n'
