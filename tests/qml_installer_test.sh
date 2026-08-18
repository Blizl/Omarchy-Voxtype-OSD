#!/usr/bin/env bash
#
# tests/qml_installer_test.sh - Unit Tests for QML File Installer
#

set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/helpers/test_helper.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/lib/qml-installer.sh"

setup_test_work_dir

test_qml_installer_verifies_sources() {
  make_temp_home
  qml_verify_sources "$PROJECT_ROOT" || fail "Source verification failed for project root"
  pass "Source QML files verification succeeded"
}

test_qml_installer_installs_and_uninstalls() {
  make_temp_home

  # Install
  qml_install "$PROJECT_ROOT" "$VOXTYPE_QUICKSHELL_DIR"
  assert_dir_exists "$VOXTYPE_QUICKSHELL_DIR"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/shell.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/OsdSurface.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/EnginePicker.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/MeetingControls.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/voxtype-shared/qmldir"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/voxtype-shared/Theme.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/voxtype-shared/ThemeReveal.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/voxtype-shared/StateReader.qml"
  assert_file_exists "$VOXTYPE_QUICKSHELL_DIR/voxtype-shared/AudioBridge.qml"
  pass "All QML and shared components installed successfully"

  # Verify
  qml_verify_installed "$VOXTYPE_QUICKSHELL_DIR" || fail "Installed verification failed"
  pass "Installed verification passed"

  # Uninstall
  qml_uninstall "$VOXTYPE_QUICKSHELL_DIR"
  assert_path_not_exists "$VOXTYPE_QUICKSHELL_DIR/shell.qml"
  assert_path_not_exists "$VOXTYPE_QUICKSHELL_DIR/OsdSurface.qml"
  assert_path_not_exists "$VOXTYPE_QUICKSHELL_DIR/voxtype-shared/Theme.qml"
  pass "QML files and directories cleanly uninstalled"
}

# Run tests
printf 'Running qml_installer_test.sh:\n'
test_qml_installer_verifies_sources
test_qml_installer_installs_and_uninstalls
printf 'All QML installer tests passed.\n'
