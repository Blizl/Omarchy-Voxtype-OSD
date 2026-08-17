// VoxType OSD Omarchy Plugin Overlay Entry Point
//
// Injected into Quickshell / Omarchy-shell runtime when enabled as a plugin.
// Manages StateReader, AudioBridge, OsdSurface HUD, EnginePicker, and MeetingControls.

import QtQuick
import Quickshell
import "voxtype-shared" as VT

Item {
    id: root

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
