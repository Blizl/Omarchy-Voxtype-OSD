pragma Singleton

// VoxType Quickshell Theme Singleton (Dynamic Omarchy Theme Sync)
//
// Dynamically tracks and binds to the user's active Omarchy theme
// ($XDG_STATE_HOME/omarchy/current/theme/colors.toml and theme.name).
//
// Omarchy theme switches recreate the theme directory inode (via rm -rf + mv),
// causing direct inotify watches on colors.toml to receive IN_DELETE_SELF/IN_IGNORED.
// To ensure 100% rock-solid live synchronization:
// 1. We watch ~/.local/state/omarchy/current/theme.name (persistent inode rewritten in-place).
// 2. We watch ~/.local/state/omarchy/current/theme/colors.toml with automatic reload & retry.
// 3. We provide an idempotent `reload()` function invoked on theme changes, OSD visibility
//    toggles, daemon state changes, and periodic sanity checks.

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

    /// Filesystem path to Omarchy's active theme name file.
    property string themeNamePath: {
        const xdgState = Quickshell.env("XDG_STATE_HOME");
        if (xdgState && xdgState.length > 0) {
            return xdgState + "/omarchy/current/theme.name";
        }
        const home = Quickshell.env("HOME");
        if (home && home.length > 0) {
            return home + "/.local/state/omarchy/current/theme.name";
        }
        return "/run/user/1000/omarchy/theme.name";
    }

    /// Active theme name (e.g. "nord", "catppuccin", "gruvbox", "tokyo-night")
    property string currentThemeName: ""

    /// Flag indicating whether at least one valid theme configuration has been loaded.
    property bool _hasLoadedValidTheme: false

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

    // ----- Live FileView Watcher for theme.name -----
    // Survives directory swaps because ~/.local/state/omarchy/current/ is not removed.
    property FileView _themeNameWatcher: FileView {
        path: theme.themeNamePath
        watchChanges: true
        printErrors: false

        onLoaded: {
            var name = (text() || "").trim();
            if (name.length > 0 && name !== theme.currentThemeName) {
                theme.currentThemeName = name;
            }
            theme.reload();
        }

        onFileChanged: {
            reload();
            theme.reload();
        }
    }

    // ----- Live FileView Watcher for Omarchy colors.toml -----
    property FileView _colorsWatcher: FileView {
        path: theme.colorsTomlPath
        watchChanges: true
        printErrors: false

        onLoaded: {
            var content = text() || "";
            if (content.length > 0) {
                theme._parseColorsToml(content);
            }
        }

        onLoadFailed: {
            // Do NOT immediately discard valid theme colors during atomic directory swap
            if (!theme._hasLoadedValidTheme) {
                theme._loadDefaults();
            }
            if (theme._retryTimer) {
                theme._retryTimer.restart();
            }
        }

        onFileChanged: {
            reload();
            var content = text() || "";
            if (content.length > 0) {
                theme._parseColorsToml(content);
            }
        }
    }

    // Short delayed retry timer to catch the recreated colors.toml inode
    property Timer _retryTimer: Timer {
        interval: 60
        repeat: false
        onTriggered: {
            if (theme._colorsWatcher) {
                theme._colorsWatcher.reload();
                var content = theme._colorsWatcher.text() || "";
                if (content.length > 0) {
                    theme._parseColorsToml(content);
                }
            }
        }
    }

    // Periodic sanity check timer (every 2s) to guarantee freshness across suspend/resume
    property Timer _sanityTimer: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (theme._themeNameWatcher) {
                var name = (theme._themeNameWatcher.text() || "").trim();
                if (name.length > 0 && name !== theme.currentThemeName) {
                    theme.currentThemeName = name;
                    theme.reload();
                }
            }
        }
    }

    /// Public method to force an immediate reload and reparsing of theme colors.
    function reload() {
        if (_themeNameWatcher) {
            _themeNameWatcher.reload();
            var name = (_themeNameWatcher.text() || "").trim();
            if (name.length > 0) {
                currentThemeName = name;
            }
        }
        if (_colorsWatcher) {
            _colorsWatcher.reload();
            var content = _colorsWatcher.text() || "";
            if (content.length > 0) {
                _parseColorsToml(content);
            } else if (_retryTimer) {
                _retryTimer.restart();
            }
        }
    }

    // Zero-dependency, robust TOML parser for Omarchy key-value colors
    function _parseColorsToml(content) {
        if (!content || content.length === 0) {
            if (!_hasLoadedValidTheme) {
                _loadDefaults();
            }
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

        if (Object.keys(map).length > 0) {
            _applyColors(map);
            _hasLoadedValidTheme = true;
        }
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
