#!/usr/bin/env bash
#
# lib/voxtype-config.sh - Modular VoxType TOML Config Parser & Modifier
#
# Provides robust, safe reading and updating of ~/.config/voxtype/config.toml.
# Preserves existing comments, spacing, and other TOML sections.

set -euo pipefail

# Status constants
VOXTYPE_CONFIG_OK=0
VOXTYPE_CONFIG_ERROR=1
VOXTYPE_CONFIG_NO_CHANGE=2

voxtype_config_default_path() {
  printf '%s\n' "${VOXTYPE_CONFIG_FILE:-$HOME/.config/voxtype/config.toml}"
}

# Check if the config file exists
voxtype_config_exists() {
  local config_file="${1:-$(voxtype_config_default_path)}"
  [[ -f "$config_file" ]]
}

# Check if a specific TOML section header exists in the config file
# Example: voxtype_config_has_section "$config_file" "osd"
voxtype_config_has_section() {
  local config_file="$1"
  local section="$2"

  [[ -f "$config_file" ]] || return 1
  awk -v sec="[$section]" '
    function trim(s) { sub(/^[[:space:]]*/, "", s); sub(/[[:space:]]*(#.*)?$/, "", s); return s; }
    {
      line = trim($0)
      if (line == sec) { found = 1; exit 0; }
    }
    END { exit (found ? 0 : 1); }
  ' "$config_file"
}

# Read a specific key from a section in TOML
# Example: voxtype_config_get_value "$config_file" "osd" "frontend"
voxtype_config_get_value() {
  local config_file="$1"
  local section="$2"
  local key="$3"

  [[ -f "$config_file" ]] || return "$VOXTYPE_CONFIG_ERROR"

  awk -v target_sec="[$section]" -v target_key="$key" '
    function trim(s) { sub(/^[[:space:]]*/, "", s); sub(/[[:space:]]*$/, "", s); return s; }
    function strip_comment(s) { sub(/[[:space:]]*#.*$/, "", s); return s; }
    function unquote(s) {
      s = trim(s);
      if (s ~ /^".*"$/ || s ~ /^\x27.*\x27$/) {
        return substr(s, 2, length(s) - 2);
      }
      return s;
    }
    /^[[:space:]]*\[/ {
      header = strip_comment($0);
      header = trim(header);
      in_sec = (header == target_sec);
      next;
    }
    in_sec && /^[[:space:]]*[^#=]+[[:space:]]*=/ {
      split($0, parts, "=");
      k = trim(parts[1]);
      if (k == target_key) {
        val = strip_comment(parts[2]);
        val = unquote(val);
        print val;
        found = 1;
        exit 0;
      }
    }
    END { exit (found ? 0 : 1); }
  ' "$config_file"
}

# Check if OSD is enabled
voxtype_config_is_osd_enabled() {
  local config_file="${1:-$(voxtype_config_default_path)}"
  local val
  val="$(voxtype_config_get_value "$config_file" "osd" "enabled" 2>/dev/null || printf 'false')"
  [[ "$val" == "true" ]]
}

# Get current OSD frontend (e.g. "quickshell", "egui", "none")
voxtype_config_get_osd_frontend() {
  local config_file="${1:-$(voxtype_config_default_path)}"
  local val
  val="$(voxtype_config_get_value "$config_file" "osd" "frontend" 2>/dev/null || printf '')"
  printf '%s\n' "$val"
}

# Safely configure or update the [osd] section in config.toml
#
# Arguments:
#   $1 - Path to config.toml
#   $2 - enabled ("true" or "false", default "true")
#   $3 - frontend (default "quickshell")
#   $4 - position (default "bottom-center")
#   $5 - width_px (default 320)
#   $6 - height_px (default 48)
#   $7 - margin_px (default 80)
#   $8 - opacity (default 0.96)
#   $9 - waveform_gain (default 12.0)
voxtype_config_configure_osd() {
  local config_file="$1"
  local enabled="${2:-true}"
  local frontend="${3:-quickshell}"
  local position="${4:-bottom-center}"
  local width_px="${5:-320}"
  local height_px="${6:-48}"
  local margin_px="${7:-80}"
  local opacity="${8:-0.96}"
  local waveform_gain="${9:-12.0}"

  mkdir -p -- "$(dirname -- "$config_file")"

  if [[ ! -f "$config_file" ]]; then
    # Create clean initial config with [osd]
    cat <<EOF >"$config_file"
# VoxType configuration file

[osd]
enabled = $enabled
frontend = "$frontend"
position = "$position"
width_px = $width_px
height_px = $height_px
margin_px = $margin_px
opacity = $opacity
waveform_gain = $waveform_gain
EOF
    return "$VOXTYPE_CONFIG_OK"
  fi

  # Modify existing config.toml atomically
  local temporary
  temporary="$(mktemp "${config_file}.tmp.XXXXXX")" || return "$VOXTYPE_CONFIG_ERROR"

  if voxtype_config_has_section "$config_file" "osd"; then
    # Update keys inside existing [osd] section
    perl -e '
      use strict;
      use warnings;

      my $file = shift @ARGV;
      my $enabled = shift @ARGV;
      my $frontend = shift @ARGV;
      my $position = shift @ARGV;
      my $width = shift @ARGV;
      my $height = shift @ARGV;
      my $margin = shift @ARGV;
      my $opacity = shift @ARGV;
      my $gain = shift @ARGV;

      open my $fh, "<", $file or die $!;
      my @lines = <$fh>;
      close $fh;

      my %seen = (
        enabled => 0,
        frontend => 0,
        position => 0,
        width_px => 0,
        height_px => 0,
        margin_px => 0,
        opacity => 0,
        waveform_gain => 0,
      );

      my $in_osd = 0;
      my @output;

      for my $line (@lines) {
        if ($line =~ /^\s*\[([^\]]+)\]/) {
          my $sec = $1;
          if ($in_osd) {
            # Append any missing keys before closing osd section
            if (!$seen{enabled}) { push @output, "enabled = $enabled\n"; }
            if (!$seen{frontend}) { push @output, "frontend = \"$frontend\"\n"; }
            if (!$seen{position}) { push @output, "position = \"$position\"\n"; }
            if (!$seen{width_px}) { push @output, "width_px = $width\n"; }
            if (!$seen{height_px}) { push @output, "height_px = $height\n"; }
            if (!$seen{margin_px}) { push @output, "margin_px = $margin\n"; }
            if (!$seen{opacity}) { push @output, "opacity = $opacity\n"; }
            if (!$seen{waveform_gain}) { push @output, "waveform_gain = $gain\n"; }
            $in_osd = 0;
          }
          if ($sec eq "osd") {
            $in_osd = 1;
          }
        }

        if ($in_osd) {
          if ($line =~ /^(\s*enabled\s*=).*/) {
            $line = "$1 $enabled\n";
            $seen{enabled} = 1;
          } elsif ($line =~ /^(\s*frontend\s*=).*/) {
            $line = "$1 \"$frontend\"\n";
            $seen{frontend} = 1;
          } elsif ($line =~ /^(\s*position\s*=).*/) {
            $line = "$1 \"$position\"\n";
            $seen{position} = 1;
          } elsif ($line =~ /^(\s*width_px\s*=).*/) {
            $line = "$1 $width\n";
            $seen{width_px} = 1;
          } elsif ($line =~ /^(\s*height_px\s*=).*/) {
            $line = "$1 $height\n";
            $seen{height_px} = 1;
          } elsif ($line =~ /^(\s*margin_px\s*=).*/) {
            $line = "$1 $margin\n";
            $seen{margin_px} = 1;
          } elsif ($line =~ /^(\s*opacity\s*=).*/) {
            $line = "$1 $opacity\n";
            $seen{opacity} = 1;
          } elsif ($line =~ /^(\s*waveform_gain\s*=).*/) {
            $line = "$1 $gain\n";
            $seen{waveform_gain} = 1;
          }
        }
        push @output, $line;
      }

      if ($in_osd) {
        if (!$seen{enabled}) { push @output, "enabled = $enabled\n"; }
        if (!$seen{frontend}) { push @output, "frontend = \"$frontend\"\n"; }
        if (!$seen{position}) { push @output, "position = \"$position\"\n"; }
        if (!$seen{width_px}) { push @output, "width_px = $width\n"; }
        if (!$seen{height_px}) { push @output, "height_px = $height\n"; }
        if (!$seen{margin_px}) { push @output, "margin_px = $margin\n"; }
        if (!$seen{opacity}) { push @output, "opacity = $opacity\n"; }
        if (!$seen{waveform_gain}) { push @output, "waveform_gain = $gain\n"; }
      }

      print join("", @output);
    ' "$config_file" "$enabled" "$frontend" "$position" "$width_px" "$height_px" "$margin_px" "$opacity" "$waveform_gain" >"$temporary"
  else
    # Append [osd] section at bottom
    cp -a -- "$config_file" "$temporary"
    {
      printf '\n[osd]\n'
      printf 'enabled = %s\n' "$enabled"
      printf 'frontend = "%s"\n' "$frontend"
      printf 'position = "%s"\n' "$position"
      printf 'width_px = %s\n' "$width_px"
      printf 'height_px = %s\n' "$height_px"
      printf 'margin_px = %s\n' "$margin_px"
      printf 'opacity = %s\n' "$opacity"
      printf 'waveform_gain = %s\n' "$waveform_gain"
    } >>"$temporary"
  fi

  chmod --reference="$config_file" "$temporary" 2>/dev/null || chmod 644 "$temporary"
  mv -- "$temporary" "$config_file"
  return "$VOXTYPE_CONFIG_OK"
}

# Disable OSD in config.toml
voxtype_config_disable_osd() {
  local config_file="$1"

  [[ -f "$config_file" ]] || return "$VOXTYPE_CONFIG_NO_CHANGE"
  voxtype_config_has_section "$config_file" "osd" || return "$VOXTYPE_CONFIG_NO_CHANGE"

  local temporary
  temporary="$(mktemp "${config_file}.tmp.XXXXXX")" || return "$VOXTYPE_CONFIG_ERROR"

  perl -e '
    use strict;
    use warnings;

    my $file = shift @ARGV;
    open my $fh, "<", $file or die $!;
    my $in_osd = 0;

    while (my $line = <$fh>) {
      if ($line =~ /^\s*\[([^\]]+)\]/) {
        $in_osd = ($1 eq "osd");
      }
      if ($in_osd && $line =~ /^(\s*enabled\s*=\s*)true(\s*(?:#.*)?)$/) {
        $line = "${1}false${2}\n";
      }
      print $line;
    }
    close $fh;
  ' "$config_file" >"$temporary"

  chmod --reference="$config_file" "$temporary" 2>/dev/null || chmod 644 "$temporary"
  mv -- "$temporary" "$config_file"
  return "$VOXTYPE_CONFIG_OK"
}

# Print human-readable summary of OSD configuration
# Restore only the [osd] section from a baseline copy of config.toml, keeping
# every other section of the *current* file untouched (so user edits made after
# installation survive an uninstall).
# Arguments:
#   $1 - current config file
#   $2 - baseline config file (may be empty/non-existent: [osd] is then removed)
voxtype_config_restore_osd_section() {
  local config_file="$1" baseline_file="${2:-}"

  [[ -f "$config_file" ]] || return "$VOXTYPE_CONFIG_NO_CHANGE"

  local temporary
  temporary="$(mktemp "${config_file}.tmp.XXXXXX")" || return "$VOXTYPE_CONFIG_ERROR"

  perl -e '
    use strict;
    use warnings;

    my ($current, $baseline) = @ARGV;

    # Split a file into (before-osd, osd-block, after-osd)
    sub split_osd {
      my ($path) = @_;
      my (@before, @osd, @after);
      my $state = "before";
      return (\@before, \@osd, \@after) unless defined $path && -f $path;
      open my $fh, "<", $path or die $!;
      while (my $line = <$fh>) {
        if ($line =~ /^\s*\[([^\]]+)\]/) {
          if ($1 eq "osd" && $state eq "before") { $state = "osd"; push @osd, $line; next; }
          if ($state eq "osd") { $state = "after"; }
        }
        if ($state eq "before") { push @before, $line; }
        elsif ($state eq "osd") { push @osd, $line; }
        else { push @after, $line; }
      }
      close $fh;
      return (\@before, \@osd, \@after);
    }

    my ($cb, $co, $ca) = split_osd($current);
    my (undef, $bo, undef) = split_osd($baseline);

    my @out;
    if (@$bo) {
      # Baseline had an [osd] section: put it back where the current one is
      if (@$co) { @out = (@$cb, @$bo, @$ca); }
      else      { @out = (@$cb, ("\n"), @$bo, @$ca); }
    } else {
      # Baseline had no [osd]: drop the current one (and the blank line setup added before it)
      if (@$co && @$cb && $cb->[-1] =~ /^\s*$/) { pop @$cb; }
      @out = (@$cb, @$ca);
    }
    print join("", @out);
  ' "$config_file" "$baseline_file" >"$temporary"

  chmod --reference="$config_file" "$temporary" 2>/dev/null || chmod 644 "$temporary"
  mv -- "$temporary" "$config_file"

  # If setup created the file from scratch and nothing else was ever added, remove it
  if [[ ! -f "$baseline_file" ]]; then
    local remaining
    remaining="$(grep -vE '^\s*(#.*)?$' "$config_file" || true)"
    [[ -z "$remaining" ]] && rm -f -- "$config_file"
  fi
  return "$VOXTYPE_CONFIG_OK"
}

voxtype_config_summary() {
  local config_file="${1:-$(voxtype_config_default_path)}"

  if [[ ! -f "$config_file" ]]; then
    printf 'Config file: (none)\n'
    return 0
  fi

  local enabled frontend position width height
  enabled="$(voxtype_config_get_value "$config_file" "osd" "enabled" 2>/dev/null || printf 'not set')"
  frontend="$(voxtype_config_get_value "$config_file" "osd" "frontend" 2>/dev/null || printf 'not set')"
  position="$(voxtype_config_get_value "$config_file" "osd" "position" 2>/dev/null || printf 'not set')"
  width="$(voxtype_config_get_value "$config_file" "osd" "width_px" 2>/dev/null || printf 'not set')"
  height="$(voxtype_config_get_value "$config_file" "osd" "height_px" 2>/dev/null || printf 'not set')"

  printf 'VoxType Config: %s\n' "$config_file"
  printf '  OSD Enabled:  %s\n' "$enabled"
  printf '  Frontend:     %s\n' "$frontend"
  printf '  Position:     %s\n' "$position"
  printf '  Dimensions:   %sx%spx\n' "$width" "$height"
}
