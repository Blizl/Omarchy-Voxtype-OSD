pragma Singleton

// VoxType Quickshell Theme Singleton (Omarchy Nord Adaptive Capsule Design)
//
// Styled to harmonize with the Omarchy / Nord aesthetic with glassy
// translucent overlays, sleek accent colors, and refined pill geometry.

import QtQuick

QtObject {
    id: theme

    /// Window / card background. Translucent dark frosted glass.
    property color bgColor: Qt.rgba(0.12, 0.14, 0.18, 0.88)

    /// Glass inner border / outline.
    property color borderColor: Qt.rgba(1.0, 1.0, 1.0, 0.12)

    /// Subtle ambient drop shadow / glow.
    property color shadowColor: Qt.rgba(0.0, 0.0, 0.0, 0.40)

    /// Theme accent. Nord Cyan / Frost (#88c0d0).
    property color accentColor: "#88c0d0"

    /// Secondary accent / highlight (#8fbcbb).
    property color accentLightColor: "#8fbcbb"

    /// Idle-state indicator color (#4c566a).
    property color idleColor: "#4c566a"

    /// Recording-state indicator color. Nord Red (#bf616a) / scarlet.
    property color recordingColor: "#bf616a"

    /// Streaming-state indicator color. Nord Cyan (#88c0d0).
    property color streamingColor: "#88c0d0"

    /// Transcribing-state indicator color. Nord Yellow (#ebcb8b) / warm amber.
    property color transcribingColor: "#ebcb8b"

    /// VAD active voice color. Nord Green (#a3be8c).
    property color vadActiveColor: "#a3be8c"

    /// Foreground primary text color (#eceff4).
    property color textColor: "#eceff4"

    /// Foreground muted/secondary text color (#9aa3b2).
    property color subtextColor: "#9aa3b2"

    /// Equalizer bar base color.
    property color waveformColor: theme.accentColor

    /// Equalizer bar peak / highlight color.
    property color waveformPeakColor: "#8fbcbb"

    /// Capsule corner radius (fully rounded pill ends).
    property int cornerRadius: 24

    /// Inner horizontal padding (px).
    property int padding: 16

    /// Bottom margin from screen edge.
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
}
