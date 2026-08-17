#!/usr/bin/env bash
#
# lib/transaction.sh - Atomic File Transaction & Rollback Manager
#
# Provides transaction safety for config edits and file installations.
# Backs up target files to a timestamped backup directory before modification.
# If any step fails, transaction_restore reverts all recorded files cleanly.

set -euo pipefail

# Initialize a new transaction backup directory
# Arguments:
#   $1 - State root directory (e.g. ~/.local/state/blizl.voxtype-osd)
transaction_begin() {
  local state_root="${1:-${BLIZL_VOXTYPE_OSD_STATE_DIR:-$HOME/.local/state/blizl.voxtype-osd}}"
  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  TRANSACTION_DIR="$state_root/backups/$stamp"
  mkdir -p -- "$TRANSACTION_DIR/files"
  : >"$TRANSACTION_DIR/targets.tsv"
  export TRANSACTION_DIR
}

# Verify that a path is safe for transaction operations
# Rejects paths outside user config/data/state directories to prevent accidental system changes.
transaction_safe_target() {
  local target="$1" canonical
  [[ "$target" == /* ]] || return 1
  canonical="$(realpath -m -- "$target")" || return 1
  case "$canonical" in
    "$HOME/.config"/* | "$HOME/.local/share"/* | "$HOME/.local/state"/* | "$HOME/.local/bin"/* | /tmp/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Record and back up a target file before modifying or creating it
# Arguments:
#   $1 - Absolute path to target file or directory
transaction_backup() {
  local target="$1"
  local relative="${target#/}"
  local destination="$TRANSACTION_DIR/files/$relative"

  transaction_safe_target "$target" || {
    echo "Refusing unsafe transaction target: $target" >&2
    return 1
  }

  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p -- "$(dirname -- "$destination")"
    cp -a --reflink=auto -- "$target" "$destination"
    printf 'present\t%s\n' "$target" >>"$TRANSACTION_DIR/targets.tsv"
  else
    printf 'absent\t%s\n' "$target" >>"$TRANSACTION_DIR/targets.tsv"
  fi
}

# Safely remove a target during rollback
transaction_remove_target() {
  local target="$1"
  transaction_safe_target "$target" || {
    echo "Refusing unsafe rollback target: $target" >&2
    return 1
  }
  [[ "$target" != "$HOME" && "$target" != "$HOME/.config" && "$target" != "$HOME/.local" ]] || {
    echo "Refusing broad rollback target: $target" >&2
    return 1
  }
  if [[ -e "$target" || -L "$target" ]]; then
    rm -rf -- "$target"
  fi
}

# Restore all targets tracked in the transaction to their original state
# Arguments:
#   $1 - Transaction directory (defaults to $TRANSACTION_DIR)
transaction_restore() {
  local transaction_dir="${1:-${TRANSACTION_DIR:-}}"
  [[ -n "$transaction_dir" && -f "$transaction_dir/targets.tsv" ]] || return 0

  local state target source

  while IFS=$'\t' read -r state target; do
    [[ -n "$target" ]] || continue
    transaction_safe_target "$target" || {
      echo "Refusing unsafe rollback target: $target" >&2
      return 1
    }
    if [[ "$state" == "present" ]]; then
      source="$transaction_dir/files/${target#/}"
      [[ -e "$source" || -L "$source" ]] || return 1
      mkdir -p -- "$(dirname -- "$target")"
      transaction_remove_target "$target"
      cp -a --reflink=auto -- "$source" "$target"
    else
      transaction_remove_target "$target"
    fi
  done <"$transaction_dir/targets.tsv"
}
