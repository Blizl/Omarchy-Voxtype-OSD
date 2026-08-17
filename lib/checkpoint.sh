#!/usr/bin/env bash
#
# lib/checkpoint.sh - VoxType OSD Baseline & Checkpoint State Manager
#
# Creates cryptographic snapshots of VoxType configuration, quickshell files,
# and service states. Allows full rollback to previous snapshots.

set -euo pipefail

checkpoint_state_root() {
  printf '%s\n' "${BLIZL_VOXTYPE_OSD_STATE_DIR:-$HOME/.local/state/blizl.voxtype-osd}"
}

checkpoint_root() {
  printf '%s/checkpoints\n' "$(checkpoint_state_root)"
}

checkpoint_valid_id() {
  [[ "${1:-}" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]]
}

checkpoint_safe_path() {
  local path="$1" root canonical
  root="$(checkpoint_root)"
  [[ "$path" == /* && "$path" != *"/../"* && "$path" != */.. && "$path" != *"/./"* && "$path" != */. ]] || return 1
  canonical="$(realpath -m -- "$path")" || return 1
  case "$canonical" in
    "$HOME/.config"/* | "$HOME/.local/share"/* | "$HOME/.local/state"/* | "$HOME/.local/bin"/* | /tmp/*) ;;
    *) return 1 ;;
  esac
  [[ "$canonical" != "$root" && "$canonical" != "$root"/* ]]
}

checkpoint_paths() {
  if [[ -n "${BLIZL_VOXTYPE_CHECKPOINT_PATHS:-}" ]]; then
    local old_ifs="$IFS" path
    local -a paths
    IFS=:
    read -ra paths <<<"$BLIZL_VOXTYPE_CHECKPOINT_PATHS"
    IFS="$old_ifs"
    for path in "${paths[@]}"; do printf '%s\n' "$path"; done
    return
  fi
  printf '%s\n' \
    "${VOXTYPE_CONFIG_FILE:-$HOME/.config/voxtype/config.toml}" \
    "${VOXTYPE_QUICKSHELL_DIR:-$HOME/.local/share/voxtype/quickshell}" \
    "$(checkpoint_state_root)/install.json"
}

checkpoint_type() {
  local path="$1"
  if [[ -L "$path" ]]; then
    printf 'symlink\n'
  elif [[ -f "$path" ]]; then
    printf 'file\n'
  elif [[ -d "$path" ]]; then
    printf 'directory\n'
  else
    printf 'absent\n'
  fi
}

checkpoint_hash_files() {
  local target="$1" output="$2" file
  if [[ -f "$target" && ! -L "$target" ]]; then
    sha256sum -- "$target" | awk -v path="$target" '{print path "\t" $1}' >>"$output"
  elif [[ -d "$target" && ! -L "$target" ]]; then
    while IFS= read -r -d '' file; do
      sha256sum -- "$file" | awk -v path="$file" '{print path "\t" $1}' >>"$output"
    done < <(find "$target" -type f -print0 | sort -z)
  fi
}

checkpoint_snapshot_services() {
  local directory="$1" enabled active
  enabled=false
  active=false
  if [[ "${BLIZL_VOXTYPE_SKIP_SERVICE:-false}" != true ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user is-enabled --quiet voxtype.service 2>/dev/null && enabled=true || enabled=false
    systemctl --user is-active --quiet voxtype.service 2>/dev/null && active=true || active=false
  fi
  jq -n --argjson enabled "$enabled" --argjson active "$active" \
    '{unit:"voxtype.service",enabled:$enabled,active:$active}' >"$directory/service-state.json"
}

checkpoint_has_space() {
  local root="$1" required=5120 available path size
  while IFS= read -r path; do
    [[ -e "$path" || -L "$path" ]] || continue
    size="$(du -sk -- "$path" 2>/dev/null | awk '{print $1}')"
    required=$((required + size))
  done < <(checkpoint_paths)

  if command -v df >/dev/null 2>&1; then
    available="$(df -Pk -- "$root" 2>/dev/null | awk 'NR == 2 { print $4 }' || printf '9999999')"
    if [[ "$available" =~ ^[0-9]+$ ]]; then
      [[ "$available" -ge "$required" ]] || return 1
    fi
  fi
  return 0
}

# Create a full snapshot checkpoint
checkpoint_create() {
  local root id directory path type relative archive entries_file hashes_file
  root="$(checkpoint_root)"
  id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  directory="$root/$id"
  entries_file="$directory/entries.jsonl"
  hashes_file="$directory/hashes.txt"

  mkdir -p -- "$root"
  checkpoint_has_space "$root" || {
    echo "Insufficient disk space for checkpoint" >&2
    return 1
  }

  mkdir -p -- "$directory/files"
  : >"$entries_file"
  : >"$hashes_file"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    checkpoint_safe_path "$path" || {
      rm -rf -- "$directory"
      echo "Unsafe checkpoint path: $path" >&2
      return 1
    }
    type="$(checkpoint_type "$path")"
    relative="${path#/}"
    archive="files/$relative"
    if [[ "$type" != absent ]]; then
      mkdir -p -- "$directory/files/$(dirname -- "$relative")"
      cp -a --reflink=auto -- "$path" "$directory/files/$relative"
      checkpoint_hash_files "$directory/$archive" "$hashes_file"
    fi
    jq -cn --arg path "$path" --arg type "$type" --arg archive "$archive" \
      '{path:$path, existed:($type != "absent"), type:$type, archive:$archive}' >>"$entries_file"
  done < <(checkpoint_paths)

  jq -s '.' "$entries_file" >"$directory/manifest.json"
  rm -f -- "$entries_file"
  checkpoint_snapshot_services "$directory"
  printf '%s\n' "$id"
}

# Verify integrity of a checkpoint
checkpoint_verify() {
  local id="$1" directory path expected actual
  directory="$(checkpoint_root)/$id"
  checkpoint_valid_id "$id" || return 1
  [[ -f "$directory/manifest.json" && -f "$directory/hashes.txt" && -f "$directory/service-state.json" ]] || return 1

  while IFS=$'\t' read -r path expected; do
    [[ -n "$path" ]] || continue
    [[ -f "$path" ]] || return 1
    actual="$(sha256sum -- "$path" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || return 1
  done <"$directory/hashes.txt"
  return 0
}

# Restore files and service state from a checkpoint
checkpoint_restore() {
  local id="$1" directory path existed archive source
  directory="$(checkpoint_root)/$id"
  checkpoint_verify "$id" || {
    echo "Checkpoint verification failed: $id" >&2
    return 1
  }

  while IFS=$'\t' read -r path existed archive; do
    checkpoint_safe_path "$path" || return 1
    if [[ "$existed" == "true" ]]; then
      source="$directory/$archive"
      [[ -e "$source" || -L "$source" ]] || return 1
      mkdir -p -- "$(dirname -- "$path")"
      rm -rf -- "$path"
      cp -a --reflink=auto -- "$source" "$path"
    else
      rm -rf -- "$path"
    fi
  done < <(jq -r '.[] | [.path, (.existed|tostring), .archive] | @tsv' "$directory/manifest.json")

  # Restore service state if recorded
  if [[ -f "$directory/service-state.json" && "${BLIZL_VOXTYPE_SKIP_SERVICE:-false}" != true ]]; then
    local enabled active
    enabled="$(jq -r '.enabled' "$directory/service-state.json")"
    active="$(jq -r '.active' "$directory/service-state.json")"
    if command -v systemctl >/dev/null 2>&1; then
      if [[ "$enabled" == "true" ]]; then
        timeout 5s systemctl --user enable voxtype.service >/dev/null 2>&1 || true
      else
        timeout 5s systemctl --user disable voxtype.service >/dev/null 2>&1 || true
      fi
      if [[ "$active" == "true" ]]; then
        timeout 5s systemctl --user start voxtype.service >/dev/null 2>&1 || true
      else
        timeout 5s systemctl --user stop voxtype.service >/dev/null 2>&1 || true
      fi
    fi
  fi
  return 0
}

# Discard/delete a checkpoint
checkpoint_discard() {
  local id="$1" directory
  directory="$(checkpoint_root)/$id"
  checkpoint_valid_id "$id" || return 1
  [[ -d "$directory" ]] || return 0
  rm -rf -- "$directory"
}

# List all available checkpoints
checkpoint_list() {
  local root directory id
  root="$(checkpoint_root)"
  [[ -d "$root" ]] || return 0

  for directory in "$root"/*; do
    [[ -d "$directory" ]] || continue
    id="$(basename -- "$directory")"
    checkpoint_valid_id "$id" || continue
    printf '%s\n' "$id"
  done
}
