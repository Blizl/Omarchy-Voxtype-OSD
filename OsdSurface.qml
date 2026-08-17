// VoxType Modern Floating Capsule OSD (Quickshell Frontend)
//
// Sleek, glassy capsule HUD with:
//   - Pulsing state glow + crisp status icon
//   - Responsive animated equalizer bars with smooth bounce physics
//   - Traveling AI wave animation during transcription
//   - Live recording timer and Voice Activity (VAD) indicator
//   - Glassmorphic translucent backdrop matching Nord / Omarchy palette

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
    visible: isStateActive || container.opacity > 0.01

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

    // Let mouse clicks fall through completely so it never intercepts clicks
    mask: Region {
        intersection: Intersection.Subtract
        x: 0; y: 0
        width: panel.width
        height: panel.height
    }

    // State accent color
    readonly property color stateColor:
        daemonState === "recording"    ? VT.Theme.recordingColor
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
        if (daemonState === "recording") {
            _resetState();
        } else if (daemonState === "idle" || daemonState === "") {
            _resetState();
        }
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
                var distFromCenter = Math.abs(i - center) / center; // 0 at center, 1 at edge
                var arcWeight = 1.0 - (distFromCenter * 0.45);

                // Sample recent peaks with frequency-like variation
                var sampleIdx = Math.max(0, history.length - 1 - (i % (history.length || 1)));
                var p = history[sampleIdx] !== undefined ? history[sampleIdx] : peak;

                // Scale with waveform gain
                var gain = VT.Theme.waveformGain || 12.0;
                var scaled = Math.min(1.0, Math.max(0.0, (p * gain * 0.25) + (rms * 0.75)));

                var h = minH + (scaled * (maxH - minH) * arcWeight);
                // Introduce organic micro-jitter per bar
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

        opacity: panel.isStateActive ? (VT.Theme.defaultOpacity || 0.96) : 0.0
        scale: panel.isStateActive ? 1.0 : 0.88

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack; overshoot: 1.15 }
        }

        // Ambient outer glow shadow
        Rectangle {
            anchors.fill: pillBg
            anchors.margins: -4
            radius: pillBg.radius + 4
            color: "transparent"
            border.color: panel.stateColor
            opacity: panel.daemonState === "recording" ? 0.35 : (panel.isStateActive ? 0.20 : 0.0)
            z: 0

            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
        }

        // Capsule Background (Frosted Glass)
        Rectangle {
            id: pillBg
            anchors.fill: parent
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

                // Left: State Indicator & Icon
                Item {
                    id: stateIconContainer
                    width: 24
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter

                    // Outer pulsing halo for recording / active VAD
                    Rectangle {
                        id: pulseHalo
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        radius: 11
                        color: panel.stateColor
                        opacity: (panel.daemonState === "recording" || (panel.audio && panel.audio.vad)) ? 0.4 : 0.0
                        scale: (panel.daemonState === "recording") ? 1.4 : 1.0

                        SequentialAnimation on scale {
                            running: panel.daemonState === "recording"
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.55; duration: 650; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.05; duration: 650; easing.type: Easing.InOutQuad }
                        }
                        SequentialAnimation on opacity {
                            running: panel.daemonState === "recording"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.15; duration: 650; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 0.55; duration: 650; easing.type: Easing.InOutQuad }
                        }
                    }

                    // Main Status Dot / Icon
                    Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: (panel.audio && panel.audio.vad) ? VT.Theme.vadActiveColor : panel.stateColor

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }
                }

                // Middle: Visualizer Area (Equalizer or Traveling Sine Wave)
                Item {
                    id: visualizerArea
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - stateIconContainer.width - rightLabel.width - (parent.spacing * 2)

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

                                // Sine wave height formula with phase offset
                                readonly property real waveVal: Math.sin(panel.transcribePhase + (index * 0.55))
                                height: 4 + Math.abs(waveVal) * 18
                                color: Qt.tint(VT.Theme.transcribingColor, Qt.rgba(1.0, 1.0, 1.0, (index / 12.0) * 0.3))

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
                    width: 76
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (panel.daemonState === "recording") {
                                return panel.formatTime(panel.elapsedSeconds);
                            } else if (panel.daemonState === "transcribing") {
                                return "AI Transcribe";
                            } else if (panel.daemonState === "streaming") {
                                return "Streaming";
                            } else {
                                return "Ready";
                            }
                        }
                        color: (panel.daemonState === "recording") ? VT.Theme.textColor : VT.Theme.subtextColor
                        font.pixelSize: (panel.daemonState === "recording") ? 13 : 11
                        font.weight: (panel.daemonState === "recording") ? Font.DemiBold : Font.Normal
                        font.family: "Sans Serif"
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
