# VoxType OSD HUD for Omarchy Quattro

A floating, click-through voice HUD for [VoxType](https://github.com/Blizl/voxtype) that automatically matches your Omarchy theme.

![VoxType OSD Demo](assets/voxtype-osd-demo.gif)

`blizl.voxtype-osd` is a clean-architecture Omarchy Quattro plugin providing a modern floating capsule HUD on-screen display (OSD), dynamic equalizer visualizer, live theme synchronization, engine switcher, and meeting controls for VoxType.

---

## Features

- **Modern Floating Capsule HUD**: Sleek, glassy pill design matching the Omarchy Nord aesthetic with glassmorphic translucent backdrops (`#2e3440` base with `#88c0d0` Frost accents).
- **Responsive Dynamic Equalizer**: 16-bar animated audio equalizer driven by real-time audio socket peaks and RMS levels with organic micro-jitter and bounce physics.
- **Harmonic AI Wave Animation**: Smooth traveling sine-wave visualizer active during AI transcription phases.
- **Multi-State Feedback**:
  - 🔴 **Recording**: Pulsing Nord scarlet indicator + live elapsed timer (`0:14`) + dynamic equalizer.
  - 🔵 **Streaming**: Nord Frost cyan glow with live voice activity.
  - 🟡 **Transcribing**: Nord amber glow + animated traveling wave.
  - 🟢 **Voice Activity (VAD)**: Dynamic green halo trigger on active speech.
- **Click-Through Wayland Overlay**: Transparent `WlrLayershell` overlay with mouse event pass-through mask so the HUD never intercepts cursor clicks.
- **Engine Picker Modal**: Floating popup (`EnginePicker.qml`) to switch between Whisper, Parakeet, SenseVoice, Moonshine, and Sherpa-ONNX engines on the fly.
- **Meeting Controls HUD**: Floating controls panel (`MeetingControls.qml`) surfacing active meeting title, duration, chunk count, and Start / Pause / Resume / Stop triggers.
- **Atomic Rollback & Safety**: Full transactional backups, automated checkpoints, and clean uninstaller restoring previous configurations without leaving orphaned files.

---

## Installation

### Via Omarchy Plugin Manager

```bash
omarchy plugin add https://github.com/Blizl/Omarchy-VoxType-OSD.git --enable \
  && ~/.config/omarchy/plugins/blizl.voxtype-osd/bin/setup
```

### Direct / Local Setup

```bash
git clone https://github.com/Blizl/Omarchy-VoxType-OSD.git
cd Omarchy-VoxType-OSD
./bin/setup
```

Pass `--yes` or `-y` for non-interactive automated installations (e.g. scripts or CI):

```bash
./bin/setup --yes
```

---

## Uninstallation & Recovery

### Uninstalling

To restore previous configurations and cleanly remove installed components:

```bash
./bin/uninstall
```

### Recovery Utility

The included `bin/restore` utility allows rolling back configuration at any time:

```bash
# Revert to the pre-setup state:
./bin/restore --latest

# List available snapshot checkpoints:
./bin/restore --list

# Revert to a specific snapshot ID:
./bin/restore --checkpoint 20260816T230800Z-12345

# Reset to clean stock defaults (disabling OSD):
./bin/restore --stock
```

---

## Configuration Reference

VoxType configuration is stored in `~/.config/voxtype/config.toml`. The `[osd]` table governs HUD behavior:

```toml
[osd]
# Enable or disable the OSD overlay
enabled = true

# OSD frontend implementation ("quickshell", "egui", "cli", "none")
frontend = "quickshell"

# Placement on screen ("bottom-center", "top-center", "bottom-right", etc.)
position = "bottom-center"

# Pill dimensions (pixels)
width_px = 320
height_px = 48

# Distance from bottom screen edge (pixels)
margin_px = 80

# Backdrop glass opacity (0.0 - 1.0)
opacity = 0.96

# Audio visualizer gain multiplier for quiet inputs
waveform_gain = 12.0

# Equalizer peak decay rate in dB per second
peak_decay_db_per_sec = 6.0

# Visible rolling waveform buffer window in seconds
waveform_window_secs = 3.0
```

---

## Architecture & Codebase Structure

The plugin follows clean-architecture principles, separating pure logic libraries, executables, QML components, and tests:

```
Omarchy-VoxType-OSD/
├── manifest.json                  # Omarchy plugin manifest (schemaVersion 1, id: blizl.voxtype-osd)
├── LICENSE                        # MIT License
├── README.md                      # Documentation & guides
├── .gitignore                     # Git ignore rules
│
├── VoxTypeOsdOverlay.qml          # Omarchy shell plugin entrypoint
├── shell.qml                      # Quickshell standalone / VoxType entrypoint
├── OsdSurface.qml                 # Floating capsule HUD component
├── EnginePicker.qml               # Floating engine switcher modal
├── MeetingControls.qml            # Floating meeting controls HUD
│
├── voxtype-shared/
│   ├── qmldir                     # QML module definition & singletons
│   ├── Theme.qml                  # Adaptive theme singleton (Nord palette & geometry)
│   ├── StateReader.qml            # Reactive FileView state watcher ($XDG_RUNTIME_DIR/voxtype/state)
│   └── AudioBridge.qml            # Sidecar NDJSON audio bridge process manager
│
├── bin/
│   ├── setup                      # Safe installer with confirmation, backups, and idempotency
│   ├── uninstall                  # Clean uninstaller with state restoration
│   └── restore                    # Snapshot checkpoint and stock recovery utility
│
├── lib/
│   ├── transaction.sh             # Atomic file rollback transaction manager
│   ├── checkpoint.sh              # Checkpoint snapshot, space check, and verification
│   ├── voxtype-config.sh          # TOML parser, modifier, and state inspector
│   ├── qml-installer.sh           # Safe QML component installer and verifier
│   └── service.sh                 # Systemd user service lifecycle management
│
└── tests/
    ├── run                        # Test runner script (executes all test suites)
    ├── helpers/
    │   └── test_helper.sh         # Isolated mock $HOME fixture generator & assertions
    ├── fixtures/
    │   └── sample_config.toml     # Sample TOML configuration for testing
    ├── config_test.sh             # Unit tests for TOML configuration engine
    ├── transaction_test.sh        # Unit tests for transaction rollback manager
    ├── qml_installer_test.sh      # Unit tests for QML file installer
    ├── checkpoint_test.sh         # Unit tests for snapshot checkpointing
    ├── service_test.sh            # Unit tests for service manager
    ├── setup_uninstall_test.sh    # E2E lifecycle and idempotency tests
    ├── restore_test.sh            # Recovery utility tests
    └── manifest_validation_test.sh# Manifest schema validation tests
```

---

## Development & Verification

All scripts and libraries are strictly linted, formatted, and tested:

```bash
# Run unit and integration tests (100% pass rate):
./tests/run

# Shell script static analysis:
shellcheck bin/* lib/*.sh tests/*.sh tests/helpers/*.sh tests/run

# Shell script code formatting check:
shfmt -d -i 2 -ci bin/* lib/*.sh tests/*.sh tests/helpers/*.sh tests/run

# Validate plugin manifest with Omarchy CLI:
omarchy plugin validate .
```

---

## Plugin Submission Checklist Compliance

| Checklist Item | Status | Details |
|---|:---:|---|
| `manifest.json` schemaVersion 1 | ✅ | Exactly integer `1`, non-reserved `blizl.voxtype-osd` ID |
| Valid entryPoints & kinds | ✅ | `kinds: ["overlay"]`, `entryPoints.overlay: "VoxTypeOsdOverlay.qml"` |
| No symlinks in repository | ✅ | 100% regular files and directories |
| User confirmation before mutation | ✅ | `bin/setup` prompts before changing config (bypassable with `--yes`) |
| Automated rollback on error | ✅ | Trap-based atomic transaction restoration on any failure |
| Clean uninstaller | ✅ | `bin/uninstall` restores pre-install config and removes files |
| Idempotency | ✅ | Setup can be run repeatedly without duplicate entries or drift |
| Isolated unit test suite | ✅ | `tests/run` executes 8 test suites with mock `$HOME` environments |
| Shellcheck & shfmt clean | ✅ | Zero warnings or formatting discrepancies |

---

## License

Released under the [MIT License](LICENSE). Copyright &copy; 2026 Blizl Labs LLC.
