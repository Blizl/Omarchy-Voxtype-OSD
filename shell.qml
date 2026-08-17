// VoxType Quickshell shell entry point.
//
// Run standalone for testing:
//   qs -p .
//
// Quickshell treats this file as the entry of a config directory. The
// shared theme/state/audio modules live at `voxtype-shared/` (sibling dir).
//
// Composes:
//   - OsdSurface: state-driven recording HUD.
//   - EnginePicker: floating engine switcher, toggled via flag.
//   - MeetingControls: meeting status + start/stop/pause/resume, toggled via flag.

import QtQuick
import Quickshell
import "voxtype-shared" as VT

ShellRoot {
    id: shell

    VT.StateReader {
        id: stateReader
    }

    VT.AudioBridge {
        id: audio
    }

    OsdSurface {
        id: osd
        daemonState: stateReader.state
        audio: audio
    }

    EnginePicker {
        id: enginePicker
    }

    MeetingControls {
        id: meetingControls
    }
}
