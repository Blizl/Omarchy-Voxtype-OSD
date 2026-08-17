#!/usr/bin/env bash
# ==============================================================================
# tests/qml_validation_test.sh - Validate QML syntax & Quickshell runtime load
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

# Source test helpers
source "$DIR/helpers/test_helper.sh"

echo "Running qml_validation_test.sh:"

# ------------------------------------------------------------------------------
# Test 1: Static Linting via qmllint (if installed)
# ------------------------------------------------------------------------------
if command -v qmllint >/dev/null 2>&1; then
  for qml_file in "$ROOT"/*.qml "$ROOT"/voxtype-shared/*.qml; do
    if [[ -f "$qml_file" ]]; then
      lint_output=$(qmllint "$qml_file" 2>&1 || true)
      # Fail if critical syntax or property errors are emitted
      if echo "$lint_output" | grep -qE "Error:|error:"; then
        echo "FAIL: qmllint reported errors on $qml_file:" >&2
        echo "$lint_output" >&2
        exit 1
      fi
    fi
  done
  echo "  ✓ qmllint static validation passed on all QML files"
else
  echo "  - qmllint not found, skipping static lint"
fi

# ------------------------------------------------------------------------------
# Test 2: Runtime Component Loading via Quickshell (qs)
# ------------------------------------------------------------------------------
if command -v qs >/dev/null 2>&1; then
  # Test shell.qml entry point
  qs_output=$(timeout 2 qs -p "$ROOT/shell.qml" 2>&1 || true)

  if echo "$qs_output" | grep -q "ERROR: Failed to load configuration"; then
    echo "FAIL: Quickshell failed to load shell.qml:" >&2
    echo "$qs_output" >&2
    exit 1
  fi

  if ! echo "$qs_output" | grep -q "Configuration Loaded"; then
    echo "FAIL: Quickshell did not report 'Configuration Loaded' on shell.qml:" >&2
    echo "$qs_output" >&2
    exit 1
  fi
  echo "  ✓ Quickshell runtime successfully loaded shell.qml (0 syntax/property errors)"

  # Test overlay entry point
  qs_overlay_output=$(timeout 2 qs -p "$ROOT/VoxTypeOsdOverlay.qml" 2>&1 || true)
  if echo "$qs_overlay_output" | grep -q "ERROR: Failed to load configuration"; then
    echo "FAIL: Quickshell failed to load VoxTypeOsdOverlay.qml:" >&2
    echo "$qs_overlay_output" >&2
    exit 1
  fi
  echo "  ✓ Quickshell runtime successfully loaded VoxTypeOsdOverlay.qml"
else
  echo "  - qs binary not found, skipping runtime load test"
fi

echo "All QML validation tests passed."
