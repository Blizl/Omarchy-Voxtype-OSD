pragma Singleton

// VoxType Quickshell Theme Singleton (Dynamic Omarchy Theme Sync)
//
// Dynamically tracks and binds to the user's active Omarchy theme
// ($XDG_STATE_HOME/omarchy/current/theme/colors.toml) via Quickshell.Io.FileView.
// Whenever the user switches desktop themes (Nord, Catppuccin, Gruvbox, Tokyo Night,
// Osaka Jade, etc.), this singleton immediately reparses the TOML and reactively
// updates all color properties live across all HUD components.

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme

    /// Filesystem path to Omarchy's active theme colors TOML file.
    property string colorsTomlPath: {
        const xdgState = Quickshell.env("XDG_STATE_HOME");
        if (xdgState && xdgState.length > 0) {
            return xdgState + "/omarchy/current/theme/colors.toml";
        }
        const home = Quickshell.env("HOME");
        if (home && home.length > 0) {
            return home + "/.local/state/omarchy/current/theme/colors.toml";
        }
        return "/run/user/1000/omarchy/colors.toml";
    }

    /// Active theme mode: "dark" or "light"
    property string themeMode: "dark"

    /// Window / card background: translucent frosted glass matching theme.
    property color bgColor: Qt.rgba(0.12, 0.14, 0.18, 0.88)

    /// Glass inner border / outline.
    property color borderColor: Qt.rgba(1.0, 1.0, 1.0, 0.12)

    /// Ambient drop shadow / glow.
    property color shadowColor: Qt.rgba(0.0, 0.0, 0.0, 0.40)

    /// Theme accent.
    property color accentColor: "#88c0d0"

    /// Secondary accent / peak highlight.
    property color accentLightColor: "#8fbcbb"

    /// Idle-state indicator color.
    property color idleColor: "#4c566a"

    /// Recording-state accent color.
    property color recordingColor: "#bf616a"

    /// Streaming-state accent color.
    property color streamingColor: "#88c0d0"

    /// Transcribing-state accent color.
    property color transcribingColor: "#ebcb8b"

    /// VAD active voice color.
    property color vadActiveColor: "#a3be8c"

    /// Foreground primary text color.
    property color textColor: "#eceff4"

    /// Foreground muted / secondary text color.
    property color subtextColor: "#9aa3b2"

    /// Equalizer bar base color.
    property color waveformColor: theme.accentColor

    /// Equalizer bar peak / highlight color.
    property color waveformPeakColor: theme.accentLightColor

    /// Capsule corner radius.
    property int cornerRadius: 24

    /// Inner horizontal padding (px).
    property int padding: 16

    /// Bottom margin from screen edge (px).
    property int marginPx: 80

    /// Default pill width (px).
    property int defaultWidthPx: 320

    /// Default pill height (px).
    property int defaultHeightPx: 48

    /// Default background opacity.
    property real defaultOpacity: 0.96

    /// Waveform / equalizer gain scaling for quiet inputs.
    property real waveformGain: 12.0

    /// Visible waveform window in seconds.
    property real waveformWindowSecs: 3.0

    /// Held-peak decay rate (dB/sec).
    property real peakDecayDbPerSec: 6.0

    /// dBFS floor for peak calculations.
    property real meterFloorDbfs: -60.0

    // ----- Live FileView Watcher for Omarchy colors.toml -----
    property FileView _themeWatcher: FileView {
        path: theme.colorsTomlPath
        watchChanges: true
        printErrors: false

        onLoaded: {
            theme._parseColorsToml(text() || "");
        }

        onLoadFailed: {
            theme._loadDefaults();
        }

        onFileChanged: reload()
    }

    // Zero-dependency, robust TOML parser for Omarchy key-value colors
    function _parseColorsToml(content) {
        if (!content || content.length === 0) {
            _loadDefaults();
            return;
        }

        var map = {};
        var lines = content.split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.length === 0 || line.charAt(0) === '#' || line.charAt(0) === '[') {
                continue;
            }

            var eqIdx = line.indexOf('=');
            if (eqIdx === -1) continue;

            var key = line.substring(0, eqIdx).trim();
            var rawVal = line.substring(eqIdx + 1).trim();

            var val = "";
            if (rawVal.charAt(0) === '"' || rawVal.charAt(0) === "'") {
                var quote = rawVal.charAt(0);
                var endQuote = rawVal.indexOf(quote, 1);
                if (endQuote !== -1) {
                    val = rawVal.substring(1, endQuote);
                } else {
                    val = rawVal.substring(1);
                }
            } else {
                var commentIdx = rawVal.indexOf('#');
                if (commentIdx !== -1) {
                    rawVal = rawVal.substring(0, commentIdx).trim();
                }
                val = rawVal;
            }

            if (key.length > 0 && val.length > 0) {
                map[key] = val;
            }
        }

        _applyColors(map);
    }

    function _applyColors(map) {
        themeMode = map["mode"] || "dark";

        // Background with frosted glass translucency
        var rawBg = map["dark_background"] || map["background"] || "#222730";
        var bg = Qt.color(rawBg);
        bgColor = Qt.rgba(bg.r, bg.g, bg.b, themeMode === "light" ? 0.92 : 0.88);

        // Foreground and text
        var rawFg = map["foreground"] || map["bright_foreground"] || "#eceff4";
        var fg = Qt.color(rawFg);
        textColor = fg;

        var rawMuted = map["muted"] || map["dark_foreground"] || "#4c566a";
        var rawSubtext = map["light_foreground"] || rawMuted;
        subtextColor = Qt.color(rawSubtext);
        idleColor = Qt.color(rawMuted);

        // Glass border and shadow
        if (themeMode === "light") {
            borderColor = Qt.rgba(0.0, 0.0, 0.0, 0.12);
            shadowColor = Qt.rgba(0.0, 0.0, 0.0, 0.15);
        } else {
            borderColor = Qt.rgba(fg.r, fg.g, fg.b, 0.12);
            shadowColor = Qt.rgba(0.0, 0.0, 0.0, 0.40);
        }

        // Functional accent colors
        accentColor = Qt.color(map["accent"] || map["blue"] || map["cyan"] || "#88c0d0");
        accentLightColor = Qt.color(map["bright_cyan"] || map["cyan"] || map["accent"] || "#8fbcbb");
        recordingColor = Qt.color(map["red"] || map["bright_red"] || "#bf616a");
        streamingColor = Qt.color(map["cyan"] || map["accent"] || "#88c0d0");
        transcribingColor = Qt.color(map["yellow"] || map["bright_yellow"] || map["orange"] || "#ebcb8b");
        vadActiveColor = Qt.color(map["green"] || map["bright_green"] || "#a3be8c");

        waveformColor = accentColor;
        waveformPeakColor = accentLightColor;
    }

    function _loadDefaults() {
        themeMode = "dark";
        bgColor = Qt.rgba(0.12, 0.14, 0.18, 0.88);
        borderColor = Qt.rgba(1.0, 1.0, 1.0, 0.12);
        shadowColor = Qt.rgba(0.0, 0.0, 0.0, 0.40);
        accentColor = Qt.color("#88c0d0");
        accentLightColor = Qt.color("#8fbcbb");
        idleColor = Qt.color("#4c566a");
        recordingColor = Qt.color("#bf616a");
        streamingColor = Qt.color("#88c0d0");
        transcribingColor = Qt.color("#ebcb8b");
        vadActiveColor = Qt.color("#a3be8c");
        textColor = Qt.color("#eceff4");
        subtextColor = Qt.color("#9aa3b2");
        waveformColor = accentColor;
        waveformPeakColor = accentLightColor;
    }
}
