#!/usr/bin/env bash
#
# lib/service.sh - Systemd User Service & Daemon Lifecycle Manager
#
# Provides safe query, reload, and restart mechanisms for voxtype.service.
# Degrades gracefully in containerized, test, or non-systemd environments.

set -euo pipefail

# Check if a user service is active
service_is_active() {
  local unit="${1:-voxtype.service}"
  if [[ "${BLIZL_VOXTYPE_SKIP_SERVICE:-false}" == true ]]; then
    return 1
  fi
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user is-active --quiet "$unit" 2>/dev/null
}

# Check if a user service is enabled
service_is_enabled() {
  local unit="${1:-voxtype.service}"
  if [[ "${BLIZL_VOXTYPE_SKIP_SERVICE:-false}" == true ]]; then
    return 1
  fi
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl --user is-enabled --quiet "$unit" 2>/dev/null
}

# Safely restart a user service if it is running
service_restart_if_active() {
  local unit="${1:-voxtype.service}"
  if [[ "${BLIZL_VOXTYPE_SKIP_SERVICE:-false}" == true ]]; then
    return 0
  fi
  command -v systemctl >/dev/null 2>&1 || return 0

  if service_is_active "$unit"; then
    timeout 5s systemctl --user restart "$unit" >/dev/null 2>&1 || {
      echo "Warning: Failed to restart $unit" >&2
      return 1
    }
  fi
  return 0
}

# Safely reload or restart a user service
service_restart() {
  local unit="${1:-voxtype.service}"
  if [[ "${BLIZL_VOXTYPE_SKIP_SERVICE:-false}" == true ]]; then
    return 0
  fi
  command -v systemctl >/dev/null 2>&1 || return 0

  timeout 5s systemctl --user restart "$unit" >/dev/null 2>&1 || {
    echo "Warning: Failed to restart $unit" >&2
    return 1
  }
  return 0
}

# Restore previous service state
service_restore_state() {
  local unit="$1"
  local was_enabled="$2"
  local was_active="$3"

  if [[ "${BLIZL_VOXTYPE_SKIP_SERVICE:-false}" == true ]]; then
    return 0
  fi
  command -v systemctl >/dev/null 2>&1 || return 0

  if [[ "$was_enabled" == "true" ]]; then
    timeout 5s systemctl --user enable "$unit" >/dev/null 2>&1 || true
  else
    timeout 5s systemctl --user disable "$unit" >/dev/null 2>&1 || true
  fi

  if [[ "$was_active" == "true" ]]; then
    timeout 5s systemctl --user start "$unit" >/dev/null 2>&1 || true
  else
    timeout 5s systemctl --user stop "$unit" >/dev/null 2>&1 || true
  fi
}
