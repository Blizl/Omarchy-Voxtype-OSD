#!/usr/bin/env bash
#
# lib/qml-installer.sh - VoxType Quickshell QML Component Installer
#
# Handles installing, verifying, and uninstalling QML components
# to ~/.local/share/voxtype/quickshell.

set -euo pipefail

qml_target_dir() {
  printf '%s\n' "${VOXTYPE_QUICKSHELL_DIR:-$HOME/.local/share/voxtype/quickshell}"
}

# List of all files managed by the QML installer
qml_managed_files() {
  printf '%s\n' \
    "shell.qml" \
    "OsdSurface.qml" \
    "EnginePicker.qml" \
    "MeetingControls.qml" \
    "voxtype-shared/qmldir" \
    "voxtype-shared/Theme.qml" \
    "voxtype-shared/StateReader.qml" \
    "voxtype-shared/AudioBridge.qml"
}

# Verify that source files exist
qml_verify_sources() {
  local source_dir="$1" file
  [[ -d "$source_dir" ]] || return 1

  while IFS= read -r file; do
    [[ -f "$source_dir/$file" ]] || return 1
  done < <(qml_managed_files)
  return 0
}

# Verify that installed files exist and match expected structure
qml_verify_installed() {
  local target_dir="${1:-$(qml_target_dir)}" file
  [[ -d "$target_dir" ]] || return 1

  while IFS= read -r file; do
    [[ -f "$target_dir/$file" ]] || return 1
  done < <(qml_managed_files)
  return 0
}

# Install QML files into target directory
qml_install() {
  local source_dir="$1"
  local target_dir="${2:-$(qml_target_dir)}"
  local file dest_file

  qml_verify_sources "$source_dir" || {
    echo "qml_install: Source directory missing required files: $source_dir" >&2
    return 1
  }

  mkdir -p -- "$target_dir/voxtype-shared"

  while IFS= read -r file; do
    dest_file="$target_dir/$file"
    mkdir -p -- "$(dirname -- "$dest_file")"
    cp -a --reflink=auto -- "$source_dir/$file" "$dest_file"
    chmod 644 "$dest_file"
  done < <(qml_managed_files)

  qml_verify_installed "$target_dir"
}

# Remove installed QML files
qml_uninstall() {
  local target_dir="${1:-$(qml_target_dir)}"
  local file

  if [[ ! -d "$target_dir" ]]; then
    return 0
  fi

  while IFS= read -r file; do
    if [[ -f "$target_dir/$file" ]]; then
      rm -f -- "$target_dir/$file"
    fi
  done < <(qml_managed_files)

  # Remove voxtype-shared directory if empty
  if [[ -d "$target_dir/voxtype-shared" ]]; then
    rmdir --ignore-fail-on-non-empty "$target_dir/voxtype-shared" 2>/dev/null || true
  fi
  if [[ -d "$target_dir" ]]; then
    rmdir --ignore-fail-on-non-empty "$target_dir" 2>/dev/null || true
  fi
  return 0
}
