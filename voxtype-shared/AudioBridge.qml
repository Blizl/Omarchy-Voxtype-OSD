// VoxType audio-bridge wrapper.
//
// Spawns the `voxtype-audio-bridge` sidecar binary as a child Process and
// parses one NDJSON object per line of stdout. The sidecar reads from
// the daemon's audio Unix socket (`$XDG_RUNTIME_DIR/voxtype/audio.sock`)
// and emits frames in this locked protocol:
//
//   {"peak":0.421,"rms":0.180,"vad":1,"ts_ms":1234567}
//   {"status":"connected"}
//   {"status":"disconnected"}
//
// Usage:
//
//   import "voxtype-shared" as VT
//   VT.AudioBridge {
//       id: audio
//       onFrameReceived: function(peak, rms, vad, tsMs) {
//           // Push into ring buffer, drive equalizer animation, etc.
//       }
//       onDisconnected: console.warn("daemon audio socket dropped")
//   }

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    /// Path or PATH-resolvable name of the audio-bridge binary.
    property string bridgeBinary: "voxtype-audio-bridge"

    /// Additional command-line arguments to pass to the bridge.
    property var bridgeArgs: []

    /// Milliseconds to wait before respawning the bridge after it exits.
    property int restartDelayMs: 1000

    /// True once the bridge process has emitted at least one frame.
    property bool running: false

    /// Latest peak amplitude, 0.0..=1.0.
    property real peak: 0.0

    /// Latest RMS amplitude, 0.0..=1.0.
    property real rms: 0.0

    /// Latest voice-activity-detection result.
    property bool vad: false

    /// Latest frame timestamp in milliseconds.
    property var tsMs: 0

    /// Emitted on every parsed audio frame.
    signal frameReceived(real peak, real rms, bool vad, var tsMs)

    /// Emitted on `{"status":"connected"}` lines from the bridge.
    signal connected()

    /// Emitted on `{"status":"disconnected"}` lines or when the bridge process exits.
    signal disconnected()

    function _handleLine(line) {
        const trimmed = (line || "").trim();
        if (trimmed.length === 0) return;
        let obj;
        try {
            obj = JSON.parse(trimmed);
        } catch (e) {
            console.warn("voxtype audio-bridge: non-JSON stdout line:", trimmed);
            return;
        }
        if (obj.status === "connected") {
            root.connected();
            return;
        }
        if (obj.status === "disconnected") {
            if (root.running) {
                root.running = false;
            }
            root.disconnected();
            return;
        }
        if (typeof obj.peak === "number" && typeof obj.rms === "number") {
            root.peak = obj.peak;
            root.rms = obj.rms;
            root.vad = !!obj.vad;
            root.tsMs = obj.ts_ms !== undefined ? obj.ts_ms : 0;
            if (!root.running) {
                root.running = true;
            }
            root.frameReceived(root.peak, root.rms, root.vad, root.tsMs);
        }
    }

    Process {
        id: process
        command: [root.bridgeBinary].concat(root.bridgeArgs)
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { root._handleLine(data); }
        }

        onRunningChanged: {
            if (!process.running) {
                if (root.running) {
                    root.running = false;
                    root.disconnected();
                }
                restartTimer.restart();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: root.restartDelayMs
        repeat: false
        onTriggered: {
            if (!process.running) {
                process.running = true;
            }
        }
    }
}
