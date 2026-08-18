// VoxType Modern Floating Capsule OSD (Quickshell Frontend)
//
// Sleek, glassy capsule HUD with:
//   - Clean minimalist microphone glyph matching desktop accent color (no red button)
//   - Dynamic Omarchy theme color synchronization
//   - Responsive animated equalizer bars with organic bounce physics
//   - Harmonic traveling sine wave animation during transcription
//   - Clean Linux copy ("Transcribing...", duration timer, VAD activity)

import QtQuick
import Quickshell
import Quickshell.Wayland
import "voxtype-shared" as VT

PanelWindow {
    id: panel

    /// Current daemon state: idle / recording / streaming / transcribing
    property string daemonState: "idle"

    /// The audio bridge instance
    property var audio: null

    /// Visibility flag
    readonly property bool isStateActive: daemonState !== "idle" && daemonState !== ""

    /// True while showing a brief "theme peek" - a confirmation glimpse
    /// of the idle/"Ready" pill in the newly-applied theme, shown after
    /// a real (de-duplicated) Omarchy theme change even though the OSD
    /// isn't otherwise active. Never overrides a genuinely active state.
    property bool themePeek: false

    visible: isStateActive || themePeek || container.opacity > 0.01

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    WlrLayershell.namespace: "voxtype-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Passthrough mouse clicks to underlying windows
    mask: Region {
        intersection: Intersection.Subtract
        x: 0; y: 0
        width: panel.width
        height: panel.height
    }

    // State accent color
    readonly property color stateColor:
        daemonState === "recording"    ? VT.Theme.accentColor
      : daemonState === "streaming"    ? VT.Theme.streamingColor
      : daemonState === "transcribing" ? VT.Theme.transcribingColor
      :                                  VT.Theme.idleColor

    // Recording duration timer state
    property int elapsedSeconds: 0

    Timer {
        id: durationTimer
        interval: 1000
        running: panel.daemonState === "recording"
        repeat: true
        onTriggered: {
            panel.elapsedSeconds += 1;
        }
    }

    // Transcription traveling wave animation phase
    property real transcribePhase: 0.0
    Timer {
        id: transcribeAnimTimer
        interval: 30
        running: panel.daemonState === "transcribing"
        repeat: true
        onTriggered: {
            panel.transcribePhase += 0.18;
        }
    }

    // Equalizer bars data (16 bars)
    readonly property int barCount: 16
    property var barHeights: [4,4,4,4, 4,4,4,4, 4,4,4,4, 4,4,4,4]
    property var peakHistory: []

    function _resetState() {
        elapsedSeconds = 0;
        transcribePhase = 0.0;
        peakHistory = [];
        var resetBars = [];
        for (var i = 0; i < barCount; i++) {
            resetBars.push(4);
        }
        barHeights = resetBars;
    }

    onDaemonStateChanged: {
        VT.Theme.reload();
        if (daemonState === "recording") {
            _resetState();
        } else if (daemonState === "idle" || daemonState === "") {
            _resetState();
        }
    }

    onVisibleChanged: {
        if (visible) {
            VT.Theme.reload();
        }
    }

    onIsStateActiveChanged: {
        if (isStateActive) {
            VT.Theme.reload();
            // A genuine daemon state change always takes precedence
            // over a theme peek: stop the peek timer so it can't later
            // hide a surface that's now visible for a real reason, and
            // drop the flag since visibility is already covered by
            // isStateActive.
            if (panel.themePeek) {
                themePeekTimer.stop();
                panel.themePeek = false;
            }
        }
    }

    // Theme-change confirmation peek: briefly show the idle pill (with
    // the newly-applied theme colours) even when the OSD would
    // otherwise stay hidden, so the user gets visual confirmation the
    // Omarchy theme switch landed. Only fires on a real, de-duplicated
    // theme commit (Theme.themeChanged), never during unrelated
    // reload() calls (which don't touch that signal). ThemeReveal isn't
    // used for the peek itself - the window isn't mapped yet at
    // themeAboutToChange time, so there's no "old" snapshot to wipe
    // from; this is a plain fade-in of the new-theme idle appearance.
    Connections {
        target: VT.Theme
        function onThemeChanged() {
            if (!VT.Theme.themePeekEnabled) return;
            if (panel.isStateActive) return; // real state already visible; don't interfere
            panel.themePeek = true;
            themePeekTimer.restart();
        }
    }

    Timer {
        id: themePeekTimer
        interval: VT.Theme.themePeekDurationMs || 1400
        repeat: false
        onTriggered: panel.themePeek = false
    }

    // Audio bridge listener
    Connections {
        target: panel.audio
        enabled: panel.audio !== null
        function onFrameReceived(peak, rms, vad, tsMs) {
            if (panel.daemonState !== "recording" && panel.daemonState !== "streaming") {
                return;
            }

            // Maintain rolling audio peaks
            var history = panel.peakHistory.slice();
            history.push(peak);
            if (history.length > 20) history.shift();
            panel.peakHistory = history;

            // Compute heights for each equalizer bar with dynamic natural arc
            var nextBars = [];
            var maxH = 26;
            var minH = 4;
            var center = (panel.barCount - 1) / 2.0;

            for (var i = 0; i < panel.barCount; i++) {
                var distFromCenter = Math.abs(i - center) / center;
                var arcWeight = 1.0 - (distFromCenter * 0.45);

                var sampleIdx = Math.max(0, history.length - 1 - (i % (history.length || 1)));
                var p = history[sampleIdx] !== undefined ? history[sampleIdx] : peak;

                var gain = VT.Theme.waveformGain || 12.0;
                var scaled = Math.min(1.0, Math.max(0.0, (p * gain * 0.25) + (rms * 0.75)));

                var h = minH + (scaled * (maxH - minH) * arcWeight);
                var jitter = Math.sin((i * 1.3) + (tsMs * 0.008)) * 2.5 * scaled;
                h = Math.max(minH, Math.min(maxH, h + jitter));
                nextBars.push(h);
            }
            panel.barHeights = nextBars;
        }
    }

    // Formatting elapsed seconds as M:SS
    function formatTime(totalSecs) {
        var m = Math.floor(totalSecs / 60);
        var s = totalSecs % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // Center container for the floating capsule HUD
    Item {
        id: container
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: VT.Theme.marginPx || 80
        width: VT.Theme.defaultWidthPx || 320
        height: VT.Theme.defaultHeightPx || 48

        // themePeek reuses the same show/hide animation as a real
        // state, just displaying the idle content (daemonState stays
        // "idle" while peeking, so the pill naturally renders "Ready").
        readonly property bool shown: panel.isStateActive || panel.themePeek
        opacity: container.shown ? (VT.Theme.defaultOpacity || 0.96) : 0.0
        scale: container.shown ? 1.0 : 0.88

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
        }

        // Capsule wrapper: geometry includes the outer aura halo so
        // ThemeReveal's grabToImage() captures the glow, not just the
        // pill body (an Item's own rect clips what grabToImage sees).
        Item {
            id: capsule
            anchors.centerIn: parent
            width: parent.width + 8
            height: parent.height + 8

            // Ambient outer glow aura
            Rectangle {
                anchors.fill: pillBg
                anchors.margins: -3
                radius: pillBg.radius + 3
                color: "transparent"
                border.color: (panel.daemonState === "transcribing") ? VT.Theme.transcribingColor : panel.stateColor
                border.width: 1
                opacity: panel.daemonState === "recording" ? 0.25 : (panel.isStateActive ? 0.15 : 0.0)
                z: 0

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
                Behavior on border.color {
                    ColorAnimation { duration: 200 }
                }
            }

            // Capsule Background (Frosted Glass)
            Rectangle {
                id: pillBg
                anchors.fill: parent
                anchors.margins: 4
                radius: VT.Theme.cornerRadius || 24
                color: VT.Theme.bgColor
                border.color: VT.Theme.borderColor
                border.width: 1
                z: 1

                // Inner Capsule Layout
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: VT.Theme.padding || 16
                    anchors.rightMargin: VT.Theme.padding || 16
                    spacing: 12

                    // Left: Minimalist State Glyph (No Red Button)
                    Item {
                        id: stateGlyphContainer
                        width: 20
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter

                        // Subtle VAD soft aura (only when speaking)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            radius: 9
                            color: (panel.audio && panel.audio.vad) ? VT.Theme.vadActiveColor : panel.stateColor
                            opacity: (panel.audio && panel.audio.vad) ? 0.22 : 0.0
                            scale: (panel.audio && panel.audio.vad) ? 1.25 : 1.0

                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 200 } }
                        }

                        // Minimalist Vector Microphone Glyph
                        Canvas {
                            id: micGlyphCanvas
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            visible: panel.daemonState === "recording" || panel.daemonState === "streaming"
                            opacity: visible ? 1.0 : 0.0

                            readonly property color glyphColor: (panel.audio && panel.audio.vad)
                                ? VT.Theme.vadActiveColor
                                : VT.Theme.accentColor

                            onGlyphColorChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                ctx.strokeStyle = glyphColor;
                                ctx.fillStyle = glyphColor;
                                ctx.lineWidth = 1.4;
                                ctx.lineCap = "round";
                                ctx.lineJoin = "round";

                                // Mic Capsule
                                ctx.beginPath();
                                if (ctx.roundRect) {
                                    ctx.roundRect(5.5, 2, 5, 8, 2.5);
                                } else {
                                    ctx.rect(5.5, 2, 5, 8);
                                }
                                ctx.fill();

                                // Mic Cradle U-arc
                                ctx.beginPath();
                                ctx.arc(8, 6.5, 4.5, 0, Math.PI, false);
                                ctx.stroke();

                                // Mic Stem & Base
                                ctx.beginPath();
                                ctx.moveTo(8, 11);
                                ctx.lineTo(8, 14);
                                ctx.moveTo(5.5, 14);
                                ctx.lineTo(10.5, 14);
                                ctx.stroke();
                            }
                        }

                        // Transcribing Harmonic Dot Indicator
                        Item {
                            id: transcribingDots
                            anchors.fill: parent
                            visible: panel.daemonState === "transcribing"
                            opacity: visible ? 1.0 : 0.0

                            Row {
                                anchors.centerIn: parent
                                spacing: 2
                                Repeater {
                                    model: 3
                                    Rectangle {
                                        required property int index
                                        width: 3
                                        height: 3
                                        radius: 1.5
                                        color: VT.Theme.transcribingColor
                                        opacity: 0.35 + 0.65 * Math.abs(Math.sin(panel.transcribePhase + index * 0.8))
                                    }
                                }
                            }
                        }
                    }

                    // Middle: Visualizer Area (Equalizer or Traveling Sine Wave)
                    Item {
                        id: visualizerArea
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - stateGlyphContainer.width - rightLabel.width - (parent.spacing * 2)

                        // Equalizer bars (during Recording or Streaming)
                        Row {
                            id: eqRow
                            anchors.centerIn: parent
                            spacing: 3
                            visible: panel.daemonState === "recording" || panel.daemonState === "streaming"
                            opacity: visible ? 1.0 : 0.0

                            Repeater {
                                model: panel.barCount
                                Rectangle {
                                    required property int index
                                    width: 3
                                    height: panel.barHeights[index] !== undefined ? panel.barHeights[index] : 4
                                    radius: 1.5
                                    color: (index === 7 || index === 8) ? VT.Theme.waveformPeakColor : VT.Theme.waveformColor
                                    anchors.verticalCenter: parent.verticalCenter

                                    Behavior on height {
                                        NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                                    }
                                }
                            }
                        }

                        // Traveling Sine Wave (during Transcribing)
                        Row {
                            id: transcribeWaveRow
                            anchors.centerIn: parent
                            spacing: 4
                            visible: panel.daemonState === "transcribing"
                            opacity: visible ? 1.0 : 0.0

                            Repeater {
                                model: 12
                                Rectangle {
                                    required property int index
                                    width: 4
                                    radius: 2
                                    anchors.verticalCenter: parent.verticalCenter

                                    readonly property real waveVal: Math.sin(panel.transcribePhase + (index * 0.55))
                                    height: 4 + Math.abs(waveVal) * 18
                                    color: Qt.tint(VT.Theme.transcribingColor, Qt.rgba(1.0, 1.0, 1.0, (index / 12.0) * 0.25))

                                    Behavior on height {
                                        NumberAnimation { duration: 30 }
                                    }
                                }
                            }
                        }

                        // Idle placeholder dots
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            visible: panel.daemonState === "idle" || panel.daemonState === ""
                            opacity: 0.4
                            Repeater {
                                model: 5
                                Rectangle {
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: VT.Theme.idleColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    // Right: Status Text or Duration Timer
                    Item {
                        id: rightLabel
                        width: Math.max(68, statusText.implicitWidth)
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: statusText
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (panel.daemonState === "recording") {
                                    return panel.formatTime(panel.elapsedSeconds);
                                } else if (panel.daemonState === "transcribing") {
                                    return "Transcribing...";
                                } else if (panel.daemonState === "streaming") {
                                    return "Streaming";
                                } else {
                                    return "Ready";
                                }
                            }
                            color: (panel.daemonState === "recording") ? VT.Theme.textColor
                                 : (panel.daemonState === "transcribing") ? VT.Theme.transcribingColor
                                 : VT.Theme.subtextColor
                            font.pixelSize: (panel.daemonState === "recording") ? 13 : 11
                            font.weight: (panel.daemonState === "recording") ? Font.DemiBold : Font.Medium
                            font.family: "Sans Serif"
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            } // pillBg
        } // capsule

        // Theme-change reveal wipe, anchored over the capsule (aura +
        // pill). Must come after `capsule` in this same parent so it
        // paints above it.
        VT.ThemeReveal {
            target: capsule
        }
    }
}
