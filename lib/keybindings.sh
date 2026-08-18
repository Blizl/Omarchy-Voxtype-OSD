#!/usr/bin/env bash
#
# lib/keybindings.sh - Hyprland/Omarchy Keybinding Manager
#
# Adds (and removes) the SUPER+E / SUPER+M bindings that toggle the
# Engine Picker and Meeting Controls panels. Bindings are written as a
# clearly-marked block appended to ~/.config/hypr/bindings.lua so they
# can be removed cleanly without disturbing user edits.

set -euo pipefail

KEYBIND_MARK_BEGIN='-- >>> blizl.voxtype-osd keybindings (managed; removed by bin/uninstall) >>>'
KEYBIND_MARK_END='-- <<< blizl.voxtype-osd keybindings <<<'

KEYBIND_ENGINE_KEYS="${BLIZL_VOXTYPE_ENGINE_KEYS:-SUPER + E}"
KEYBIND_MEETING_KEYS="${BLIZL_VOXTYPE_MEETING_KEYS:-SUPER + M}"
# shellcheck disable=SC2016  # expanded by Hyprland at exec time, not here
KEYBIND_ENGINE_CMD='mkdir -p $XDG_RUNTIME_DIR/voxtype && touch $XDG_RUNTIME_DIR/voxtype/engine-picker.flag'
# shellcheck disable=SC2016
KEYBIND_MEETING_CMD='mkdir -p $XDG_RUNTIME_DIR/voxtype && touch $XDG_RUNTIME_DIR/voxtype/meeting-controls.flag'

# Path to the user's Omarchy Hyprland bindings file
keybindings_file() {
  printf '%s\n' "${BLIZL_VOXTYPE_BINDINGS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua}"
}

# True when the file's directory exists (i.e. this looks like an Omarchy/Hyprland setup)
keybindings_supported() {
  local file
  file="$(keybindings_file)"
  [[ -d "$(dirname -- "$file")" ]]
}

# True if the file already contains our managed block
keybindings_installed() {
  local file="${1:-$(keybindings_file)}"
  [[ -f "$file" ]] && grep -qF -- "$KEYBIND_MARK_BEGIN" "$file"
}

# Convert "SUPER + SHIFT + E" into a Hyprland modmask number
_keybind_modmask() {
  local keys="$1" mask=0 part
  IFS='+' read -ra parts <<<"$keys"
  for part in "${parts[@]}"; do
    part="$(printf '%s' "$part" | tr -d ' ' | tr '[:lower:]' '[:upper:]')"
    case "$part" in
      SHIFT) mask=$((mask | 1)) ;;
      CAPS | CAPSLOCK) mask=$((mask | 2)) ;;
      CTRL | CONTROL) mask=$((mask | 4)) ;;
      ALT) mask=$((mask | 8)) ;;
      MOD2) mask=$((mask | 16)) ;;
      MOD3) mask=$((mask | 32)) ;;
      SUPER | WIN | LOGO | MOD4) mask=$((mask | 64)) ;;
      MOD5) mask=$((mask | 128)) ;;
      *) : ;; # last token is the key
    esac
  done
  printf '%s\n' "$mask"
}

_keybind_key() {
  local keys="$1"
  printf '%s\n' "${keys##*+}" | tr -d ' ' | tr '[:upper:]' '[:lower:]'
}

# Prints the description of an existing binding for $1 (e.g. "SUPER + E"),
# excluding our own managed block. Returns 1 if the combo is free.
keybinding_in_use() {
  local keys="$1" file="${2:-$(keybindings_file)}" desc

  # 1. Live compositor state (most accurate: includes Omarchy defaults)
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local mask key
    mask="$(_keybind_modmask "$keys")"
    key="$(_keybind_key "$keys")"
    desc="$(hyprctl binds -j 2>/dev/null | jq -r --argjson m "$mask" --arg k "$key" \
      '[.[] | select(.modmask == $m and (.key | ascii_downcase) == $k)] | first // empty | (.description // .arg // "bound")' 2>/dev/null || true)"
    if [[ -n "$desc" ]]; then
      # Ignore hits that are our own managed binding
      case "$desc" in *"VoxType"*) return 1 ;; esac
      printf '%s\n' "$desc"
      return 0
    fi
  fi

  # 2. Static check of the user's bindings.lua (outside our block)
  if [[ -f "$file" ]]; then
    desc="$(awk -v b="$KEYBIND_MARK_BEGIN" -v e="$KEYBIND_MARK_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip { print }
      ' "$file" |
      grep -E '^[[:space:]]*(o\.bind|o\.bind_toggle|hl\.bind)\(' |
      grep -F "(\"${keys}\"" | head -n1 || true)"
    if [[ -n "$desc" ]]; then
      printf '%s\n' "$desc"
      return 0
    fi
  fi
  return 1
}

# Remove our managed block from the file (no-op if absent)
keybindings_remove() {
  local file="${1:-$(keybindings_file)}" tmp
  [[ -f "$file" ]] || return 0
  keybindings_installed "$file" || return 0
  tmp="$(mktemp)"
  awk -v b="$KEYBIND_MARK_BEGIN" -v e="$KEYBIND_MARK_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }
  ' "$file" >"$tmp"
  # Trim a single trailing blank line we may have added
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
  cat "$tmp" >"$file"
  rm -f -- "$tmp"
}

# Write our managed block.
# Arguments:
#   $1 - bindings file
#   $2 - install engine binding (true/false)
#   $3 - unbind existing engine binding first (true/false)
#   $4 - install meeting binding (true/false)
#   $5 - unbind existing meeting binding first (true/false)
keybindings_install() {
  local file="$1" engine="${2:-true}" engine_override="${3:-false}" meeting="${4:-true}" meeting_override="${5:-false}"
  [[ "$engine" == true || "$meeting" == true ]] || return 0
  mkdir -p -- "$(dirname -- "$file")"
  [[ -f "$file" ]] || : >"$file"
  keybindings_remove "$file"
  {
    printf '\n%s\n' "$KEYBIND_MARK_BEGIN"
    if [[ "$engine" == true ]]; then
      [[ "$engine_override" == true ]] && printf 'hl.unbind("%s")\n' "$KEYBIND_ENGINE_KEYS"
      printf 'o.bind("%s", "VoxType engine picker", "%s")\n' "$KEYBIND_ENGINE_KEYS" "$KEYBIND_ENGINE_CMD"
    fi
    if [[ "$meeting" == true ]]; then
      [[ "$meeting_override" == true ]] && printf 'hl.unbind("%s")\n' "$KEYBIND_MEETING_KEYS"
      printf 'o.bind("%s", "VoxType meeting controls", "%s")\n' "$KEYBIND_MEETING_KEYS" "$KEYBIND_MEETING_CMD"
    fi
    printf '%s\n' "$KEYBIND_MARK_END"
  } >>"$file"
}

# Ask Hyprland to reload its config so new bindings take effect
keybindings_reload() {
  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && "${BLIZL_VOXTYPE_SKIP_SERVICE:-}" != true ]] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
  fi
}
