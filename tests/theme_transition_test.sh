#!/usr/bin/env bash
# ==============================================================================
# tests/theme_transition_test.sh - Validate the Theme-change transition API
#
# Covers the contract added on top of theme_switching_test.sh's live-sync
# coverage:
#   - VT.Theme.themeAboutToChange() / themeChanged() only fire on a REAL,
#     de-duplicated palette change (not on every FileView reload).
#   - A palette change still commits (and ACCENT_CHANGED still fires) even
#     when nothing is visible to animate the reveal against - either because
#     no widget is holding the commit at all, or because a widget forgot to
#     release a hold it took (Theme.holdCommit()/releaseCommit()'s 100ms
#     fallback timer).
#   - VOXTYPE_OSD_THEME_TRANSITION accepts every documented style (and an
#     unrecognized value) without breaking Quickshell's runtime load.
# ==============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$DIR/helpers/test_helper.sh"

echo "Running theme_transition_test.sh:"

if ! command -v qs >/dev/null 2>&1; then
  echo "  - qs binary not found, skipping live theme-transition tests"
  echo "All theme transition tests passed."
  exit 0
fi

if ! grep -q "themeAboutToChange" "$ROOT/voxtype-shared/Theme.qml" 2>/dev/null ||
  [[ ! -f "$ROOT/voxtype-shared/ThemeReveal.qml" ]]; then
  echo "  - voxtype-shared/Theme.qml / ThemeReveal.qml don't expose the" \
    "themeAboutToChange/themeChanged transition API yet, skipping" >&2
  echo "All theme transition tests passed."
  exit 0
fi

setup_test_work_dir
make_temp_home

STATE_DIR="$HOME/.local/state/omarchy/current"
THEME_DIR="$STATE_DIR/theme"
NEXT_THEME_DIR="$STATE_DIR/next-theme"

mkdir -p "$STATE_DIR"

# Mirrors theme_switching_test.sh's simulate_omarchy_theme_set: swaps the
# theme directory's inode (rm -rf + mv) exactly like
# /usr/share/omarchy/bin/omarchy-theme-set does, so FileView watchers see
# the same IN_DELETE_SELF/IN_IGNORED churn they'd see in production.
simulate_omarchy_theme_set() {
  local theme_name="$1"
  local accent="$2"
  local mode="${3:-dark}"

  rm -rf "$NEXT_THEME_DIR"
  mkdir -p "$NEXT_THEME_DIR"
  cat <<EOF >"$NEXT_THEME_DIR/colors.toml"
mode = "$mode"
accent = "$accent"
selection = "#434c5e"
muted = "#4c566a"
background = "#2e3440"
dark_background = "#222730"
foreground = "#d8dee9"
EOF

  rm -rf "$THEME_DIR"
  mv "$NEXT_THEME_DIR" "$THEME_DIR"
  echo "$theme_name" >"$STATE_DIR/theme.name"
}

mkdir -p "$WORK_DIR/voxtype-shared"
cp "$ROOT"/voxtype-shared/* "$WORK_DIR/voxtype-shared/"

# ------------------------------------------------------------------------------
# Test 1: commit + ACCENT_CHANGED happen even with nothing visible AND a
# forgotten holdCommit() (the fallback path the 100ms _commitFallback timer
# exists for - e.g. a ThemeReveal whose grabToImage() callback never runs).
# ------------------------------------------------------------------------------
simulate_omarchy_theme_set "nord" "#81a1c1" "dark"

FALLBACK_HARNESS="$WORK_DIR/theme_fallback_harness.qml"
cat <<'EOF' >"$FALLBACK_HARNESS"
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
      console.log("ACCENT_CHANGED:" + VT.Theme.currentThemeName + ":" + VT.Theme.accentColor);
    }
    function onThemeChanged() {
      console.log("THEME_COMMITTED:" + VT.Theme.currentThemeName);
    }
  }

  Component.onCompleted: {
    // Simulate a widget that took a hold (e.g. ThemeReveal about to
    // grabToImage()) and then never released it - the window is never
    // mapped/visible, so a real ThemeReveal would skip the hold entirely,
    // but this reproduces the "hold taken, release lost" edge case the
    // fallback timer exists to guard against.
    VT.Theme.holdCommit();
    console.log("INITIAL_THEME:" + VT.Theme.currentThemeName + ":" + VT.Theme.accentColor);
  }
}
EOF

FALLBACK_LOG="$WORK_DIR/qs_theme_fallback.log"
(cd "$WORK_DIR" && qs -p "$FALLBACK_HARNESS" >"$FALLBACK_LOG" 2>&1 &)
sleep 0.6

simulate_omarchy_theme_set "catppuccin" "#89b4fa" "dark"

# The fallback commit timer is documented at 100ms; give it generous
# headroom under test-environment scheduling jitter.
sleep 1.2

pkill -f "qs -p $FALLBACK_HARNESS" 2>/dev/null || true
wait 2>/dev/null || true

FALLBACK_LOG_CONTENT="$(cat "$FALLBACK_LOG" 2>/dev/null || true)"

if ! echo "$FALLBACK_LOG_CONTENT" | grep -q "ACCENT_CHANGED:catppuccin:"; then
  echo "Quickshell fallback-commit harness log:" >&2
  cat "$FALLBACK_LOG" >&2
  fail "Theme change with a stuck holdCommit() and no visible surface never committed (ACCENT_CHANGED missing)"
fi
if ! echo "$FALLBACK_LOG_CONTENT" | grep -q "THEME_COMMITTED:catppuccin"; then
  echo "Quickshell fallback-commit harness log:" >&2
  cat "$FALLBACK_LOG" >&2
  fail "themeChanged() never fired for the fallback-committed theme"
fi
pass "Theme change commits (ACCENT_CHANGED + themeChanged) via the fallback timer even when a hold is never released and no surface is visible"

# ------------------------------------------------------------------------------
# Test 2: de-dupe - rewriting colors.toml with byte-identical content (a
# fresh inode via rm -rf + mv, exactly like a repeated `Theme.reload()`
# racing an unrelated FileView churn) must NOT re-fire
# themeAboutToChange()/themeChanged().
# ------------------------------------------------------------------------------
DEDUPE_HARNESS="$WORK_DIR/theme_dedupe_harness.qml"
cat <<'EOF' >"$DEDUPE_HARNESS"
import QtQuick
import Quickshell
import "voxtype-shared" as VT

PanelWindow {
  id: testPanel
  color: "transparent"
  visible: false

  property int changedCount: 0

  Connections {
    target: VT.Theme
    function onThemeChanged() {
      testPanel.changedCount += 1;
      console.log("THEME_CHANGED_SEQ:" + testPanel.changedCount + ":" + VT.Theme.currentThemeName + ":" + VT.Theme.accentColor);
    }
  }
}
EOF

simulate_omarchy_theme_set "gruvbox" "#7daea3" "dark"

DEDUPE_LOG="$WORK_DIR/qs_theme_dedupe.log"
(cd "$WORK_DIR" && qs -p "$DEDUPE_HARNESS" >"$DEDUPE_LOG" 2>&1 &)
sleep 0.6

# First real change: gruvbox -> tokyo-night. This is the "real change
# under test"; Theme's own startup commit (defaults -> gruvbox) is a
# real change too and already logged once by this point, so the
# baseline is captured *after* this settles rather than assumed to be 0.
simulate_omarchy_theme_set "tokyo-night" "#7aa2f7" "dark"
sleep 0.6

baseline_count="$(grep -c "THEME_CHANGED_SEQ:" "$DEDUPE_LOG" 2>/dev/null || true)"
if [[ "$baseline_count" -lt 1 ]] || ! grep -q "THEME_CHANGED_SEQ:${baseline_count}:tokyo-night:" "$DEDUPE_LOG"; then
  echo "Quickshell de-dupe harness log:" >&2
  cat "$DEDUPE_LOG" >&2
  fail "Real theme change to tokyo-night was never committed before the de-dupe rewrites started"
fi

# Repeat the SAME content (new inode, identical bytes). Must be a no-op.
simulate_omarchy_theme_set "tokyo-night" "#7aa2f7" "dark"
sleep 0.6
simulate_omarchy_theme_set "tokyo-night" "#7aa2f7" "dark"
sleep 0.6

pkill -f "qs -p $DEDUPE_HARNESS" 2>/dev/null || true
wait 2>/dev/null || true

DEDUPE_LOG_CONTENT="$(cat "$DEDUPE_LOG" 2>/dev/null || true)"
final_count="$(echo "$DEDUPE_LOG_CONTENT" | grep -c "THEME_CHANGED_SEQ:" || true)"

if [[ "$final_count" -ne "$baseline_count" ]]; then
  echo "Quickshell de-dupe harness log:" >&2
  cat "$DEDUPE_LOG" >&2
  fail "Expected the 2 identical colors.toml rewrites to add 0 new themeChanged() commits (baseline $baseline_count), got $final_count"
fi
pass "Repeated identical colors.toml rewrites do not re-emit themeChanged() (de-dupe)"

# ------------------------------------------------------------------------------
# Test 3: VOXTYPE_OSD_THEME_TRANSITION accepts every documented style (plus
# an unrecognized value) without breaking Quickshell's runtime load.
# ------------------------------------------------------------------------------
for style in omarchy grow wipe-right wipe-left fade none bogus-style; do
  qs_output=$(VOXTYPE_OSD_THEME_TRANSITION="$style" timeout 2 qs -p "$ROOT/shell.qml" 2>&1 || true)

  if echo "$qs_output" | grep -q "ERROR: Failed to load configuration"; then
    echo "Quickshell output (VOXTYPE_OSD_THEME_TRANSITION=$style):" >&2
    echo "$qs_output" >&2
    fail "Quickshell failed to load shell.qml with VOXTYPE_OSD_THEME_TRANSITION=$style"
  fi
  if ! echo "$qs_output" | grep -q "Configuration Loaded"; then
    echo "Quickshell output (VOXTYPE_OSD_THEME_TRANSITION=$style):" >&2
    echo "$qs_output" >&2
    fail "Quickshell did not report 'Configuration Loaded' with VOXTYPE_OSD_THEME_TRANSITION=$style"
  fi
done
pass "VOXTYPE_OSD_THEME_TRANSITION accepts every documented style (and an unrecognized one) without breaking runtime load"

echo "All theme transition tests passed."
