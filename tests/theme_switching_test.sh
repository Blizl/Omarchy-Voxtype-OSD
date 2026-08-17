#!/usr/bin/env bash
# ==============================================================================
# tests/theme_switching_test.sh - Validate dynamic Omarchy theme switching
# ==============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

# Source test helpers
# shellcheck disable=SC1091
source "$DIR/helpers/test_helper.sh"

echo "Running theme_switching_test.sh:"

setup_test_work_dir
make_temp_home

STATE_DIR="$HOME/.local/state/omarchy/current"
THEME_DIR="$STATE_DIR/theme"
NEXT_THEME_DIR="$HOME/.local/state/omarchy/current/next-theme"

mkdir -p "$STATE_DIR"

THEMES=(
  "catppuccin:#89b4fa:dark"
  "gruvbox:#7daea3:dark"
  "tokyo-night:#7aa2f7:dark"
  "nord:#81a1c1:dark"
  "osaka-jade:#509475:dark"
  "retro-82:#faa968:dark"
  "rose-pine:#56949f:light"
  "vantablack:#8d8d8d:dark"
  "everforest:#7fbbb3:dark"
)

# Helper to simulate omarchy theme switch exactly as /usr/share/omarchy/bin/omarchy-theme-set does
simulate_omarchy_theme_set() {
  local theme_name="$1"
  local expected_accent="${2:-#81a1c1}"
  local expected_mode="${3:-dark}"
  local src_colors="/usr/share/omarchy/themes/$theme_name/colors.toml"

  rm -rf "$NEXT_THEME_DIR"
  mkdir -p "$NEXT_THEME_DIR"

  if [[ -f "$src_colors" ]]; then
    cp "$src_colors" "$NEXT_THEME_DIR/colors.toml"
  else
    cat <<EOF > "$NEXT_THEME_DIR/colors.toml"
mode = "$expected_mode"
accent = "$expected_accent"
selection = "#434c5e"
muted = "#4c566a"
background = "#2e3440"
dark_background = "#222730"
foreground = "#d8dee9"
EOF
  fi

  # Swap next theme in as current (rm -rf + mv recreates directory inode)
  rm -rf "$THEME_DIR"
  mv "$NEXT_THEME_DIR" "$THEME_DIR"

  # Update theme.name (rewritten in place)
  echo "$theme_name" > "$STATE_DIR/theme.name"
}

# ------------------------------------------------------------------------------
# Test 1: Static Parsing Verification for All Diverse Themes
# ------------------------------------------------------------------------------
for entry in "${THEMES[@]}"; do
  IFS=":" read -r theme_name accent_col theme_mode <<< "$entry"
  simulate_omarchy_theme_set "$theme_name" "$accent_col" "$theme_mode"

  assert_file_exists "$THEME_DIR/colors.toml"
  assert_file_exists "$STATE_DIR/theme.name"

  actual_name="$(cat "$STATE_DIR/theme.name")"
  assert_eq "$actual_name" "$theme_name" "Theme name in state file"
done
pass "All 9 diverse themes simulate filesystem layout correctly"

# ------------------------------------------------------------------------------
# Test 2: Live Dynamic Theme Switching in Quickshell Runtime
# ------------------------------------------------------------------------------
if command -v qs >/dev/null 2>&1; then
  # Initialize with first theme
  simulate_omarchy_theme_set "catppuccin" "#89b4fa" "dark"

  # Create a test harness QML that imports Theme and logs color changes
  HARNESS_QML="$WORK_DIR/theme_harness.qml"
  cat <<'EOF' > "$HARNESS_QML"
import QtQuick
import Quickshell
import "voxtype-shared" as VT

PanelWindow {
  id: testPanel
  color: "transparent"
  visible: false

  Connections {
    target: VT.Theme
    function onAccentColorChanged() {
      console.log("ACCENT_CHANGED:" + VT.Theme.currentThemeName + ":" + VT.Theme.accentColor + ":" + VT.Theme.themeMode);
    }
  }

  Component.onCompleted: {
    console.log("INITIAL_THEME:" + VT.Theme.currentThemeName + ":" + VT.Theme.accentColor + ":" + VT.Theme.themeMode);
  }
}
EOF

  # Copy voxtype-shared directory to harness work dir
  mkdir -p "$WORK_DIR/voxtype-shared"
  cp "$ROOT"/voxtype-shared/* "$WORK_DIR/voxtype-shared/"

  OUTPUT_LOG="$WORK_DIR/qs_theme_test.log"

  # Launch Quickshell in background
  qs -p "$HARNESS_QML" > "$OUTPUT_LOG" 2>&1 &
  QS_PID=$!

  sleep 0.8

  # Perform dynamic switching across all themes in sequence
  for entry in "${THEMES[@]}"; do
    IFS=":" read -r theme_name accent_col theme_mode <<< "$entry"
    simulate_omarchy_theme_set "$theme_name" "$accent_col" "$theme_mode"
    sleep 0.25
  done

  sleep 0.5
  kill $QS_PID 2>/dev/null || true
  wait $QS_PID 2>/dev/null || true

  LOG_CONTENT="$(cat "$OUTPUT_LOG" 2>/dev/null || true)"

  for entry in "${THEMES[@]}"; do
    IFS=":" read -r theme_name _ _ <<< "$entry"
    # Verify that either INITIAL_THEME or ACCENT_CHANGED logged this theme
    if ! echo "$LOG_CONTENT" | grep -qE "(ACCENT_CHANGED|INITIAL_THEME):$theme_name:"; then
      echo "Quickshell Output Log:" >&2
      cat "$OUTPUT_LOG" >&2
      fail "Dynamic theme switch failed to register theme '$theme_name' in live Quickshell"
    fi
  done

  pass "Live dynamic theme switching succeeded across all 9 diverse themes"
else
  echo "  - qs binary not found, skipping live runtime theme switch test"
fi

echo "All theme switching tests passed."
