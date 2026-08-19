// Voxtype engine picker popup for Quickshell.
//
// A floating panel that lists every transcription engine voxtype knows
// about, marks the one currently selected in the on-disk config, and
// switches the active engine by shelling out to
// `voxtype config set engine <name>` (added in PR #382). No new daemon
// IPC is introduced.
//
// ## Read path
//
// 1. Available engines: the canonical list of 8 transcription engines
//    is hardcoded here to match `ENGINE_NAMES` in `src/config_set.rs`.
//    Whether the running binary was compiled with the matching Cargo
//    feature is discovered by spawning `voxtype info variants --json`
//    once when the panel opens and reading the `compiled_features`
//    array (fixed in #384 to enumerate every ONNX engine, not just
//    parakeet + GPU backends). Engines absent from that array are
    //    demoted under a visible "Unavailable" heading. An engine is
    //    ready only when it is compiled into the running binary AND
    //    its model is on disk. Missing-binary rows hint at
    //    `voxtype configure`; missing-model rows hint at
    //    `voxtype setup model`. When the JSON parse fails (older
    //    binary that predates #384, or `--json` returning text), ONNX
    //    engines are treated as not compiled. Whisper is always
    //    compiled; it is not a Cargo feature.
//
// 2. Currently-active engine: read from
//    `~/.config/voxtype/config.toml` via FileView. The file is parsed
//    line-by-line for `engine = "<name>"`; if the key is absent the
//    default is whisper (matches `TranscriptionEngine::default()`).
//
// ## Open/close trigger
//
// Mirrors `MeetingControls.qml`: the picker watches a flag file at
// `$XDG_RUNTIME_DIR/voxtype/engine-picker.flag`. Touching the flag
// toggles visibility; the picker removes the flag on read so a
// subsequent `touch` reliably retoggles.
//
//   # Hyprland
//   bind = SUPER, E, exec, touch $XDG_RUNTIME_DIR/voxtype/engine-picker.flag
//
//   # Sway
//   bindsym $mod+e exec touch $XDG_RUNTIME_DIR/voxtype/engine-picker.flag
//
// ## Switching
//
// On Enter or click, the picker spawns
// `voxtype config set engine <name>`. Once the process exits, the
// picker re-reads the config file and inspects the CLI's stderr to
// classify the outcome:
//
//   config now contains <name>            → success
//   stderr matches "not compiled"/"unknown engine" → feature gate failure
//   anything else                         → I/O failure
//
// Quickshell 0.2.1's Process binding doesn't reliably surface the
// child exit code as a QML property across all distro builds, so the
// dispatch leans on the post-mutation config file as the source of
// truth and uses stderr only to render an accurate error message when
// the mutation didn't happen.
//
// On success the panel auto-closes after ~1.5 s so the user reads the
// confirmation before it disappears. The picker does NOT restart the
// daemon automatically; restart is the user's choice and matches the
// behavior of the CLI command.
//
// ## Why this lives outside shell.qml
//
// shell.qml is the OSD composition root and is wired up by the
// maintainer. This file is a self-contained sibling: it exposes a
// PanelWindow at the top of its tree so it can be instantiated either
// as a sibling in ShellRoot or hoisted into another shell config.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "voxtype-shared" as VT

PanelWindow {
    id: root

    // ----- public API -----

    /// Path or PATH-resolvable name of the voxtype CLI. Mirrors
    /// MeetingControls so a single override flips both widgets.
    property string voxtypeBinary: "voxtype"

    /// Directory containing the daemon's runtime files (the
    /// `engine-picker.flag` toggle). Mirrors the resolution in
    /// `Config::runtime_dir()` so the widget never disagrees with the
    /// daemon about where to look.
    property string runtimeDir: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR");
        if (xdg && xdg.length > 0) {
            return xdg + "/voxtype";
        }
        const uid = Quickshell.env("UID");
        if (uid && uid.length > 0) {
            return "/run/user/" + uid + "/voxtype";
        }
        return "/run/user/1000/voxtype";
    }

    /// Path to the on-disk config file. Mirrors
    /// `Config::default_path()`: `$XDG_CONFIG_HOME/voxtype/config.toml`
    /// with a `$HOME/.config/voxtype/config.toml` fallback.
    property string configPath: {
        const xdgConfig = Quickshell.env("XDG_CONFIG_HOME");
        if (xdgConfig && xdgConfig.length > 0) {
            return xdgConfig + "/voxtype/config.toml";
        }
        const home = Quickshell.env("HOME");
        if (home && home.length > 0) {
            return home + "/.config/voxtype/config.toml";
        }
        return "/tmp/voxtype-config.toml";
    }

    /// Directory where voxtype stores downloaded models.
    /// Mirrors `$XDG_DATA_HOME/voxtype/models` with a
    /// `$HOME/.local/share/voxtype/models` fallback.
    property string modelsDir: {
        const xdgData = Quickshell.env("XDG_DATA_HOME");
        if (xdgData && xdgData.length > 0) {
            return xdgData + "/voxtype/models";
        }
        const home = Quickshell.env("HOME");
        if (home && home.length > 0) {
            return home + "/.local/share/voxtype/models";
        }
        return "/tmp/voxtype-models";
    }

    /// Whether the panel is currently visible. Compositors can flip
    /// this directly as an alternative to the flag-file trigger.
    property bool open: false

    // ----- derived state -----

    /// Currently-selected engine name (the one written to config.toml).
    /// Falls back to "whisper" when the key is absent or unreadable.
    readonly property string activeEngine: _activeEngine

    /// List of engines the running binary advertises via
    /// `voxtype info variants --json` `compiled_features`. Used to
    /// distinguish "definitely available" from "may not be compiled
    /// in" in the row styling.
    readonly property var compiledFeatures: _compiledFeatures

    // ----- panel surface -----

    visible: root.open
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "voxtype-engine-picker"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive
                                           : WlrKeyboardFocus.None

    // ----- engine catalog -----

    // Hardcoded list keeps the UI deterministic and matches
    // `ENGINE_NAMES` in src/config_set.rs. If a new engine lands
    // upstream, add it here.
    readonly property var engines: [
        { name: "whisper",     label: "Whisper",     summary: "Multilingual · CPU or GPU",              defaultModel: "base.en" },
        { name: "parakeet",    label: "Parakeet",    summary: "English · Fast",                         defaultModel: "parakeet-tdt-0.6b-v3" },
        { name: "moonshine",   label: "Moonshine",   summary: "English",                                defaultModel: "base" },
        { name: "sensevoice",  label: "SenseVoice",  summary: "Chinese · English · Japanese · Korean", defaultModel: "sensevoice-small" },
        { name: "paraformer",  label: "Paraformer",  summary: "Chinese and English",                    defaultModel: "paraformer-zh" },
        { name: "dolphin",     label: "Dolphin",     summary: "Dictation · no English",                 defaultModel: "dolphin-base" },
        { name: "omnilingual", label: "Omnilingual", summary: "Broad language coverage",                defaultModel: "omnilingual-large" },
        { name: "cohere",      label: "Cohere",      summary: "High accuracy · multilingual",           defaultModel: "cohere-transcribe-int8" }
    ]

    // ----- internal state -----

    property string _activeEngine: "whisper"
    property var _compiledFeatures: []
    property var _configModels: ({})
    property var _modelDirEntries: []
    property var _availableEngines: []
    property var _unavailableEngines: []
    property int _unavailableBinaryCount: 0
    property int _unavailableModelCount: 0
    property int _selectedIndex: 0
    // Transient line for switch progress / errors. Cleared after a few
    // seconds or replaced by the next action.
    property string _actionStatus: ""
    // "info" | "ok" | "error" — drives the status line color.
    property string _actionKind: "info"
    // Engine the user just attempted to switch to. Used by exit-code
    // dispatch to compose accurate status messages without races on
    // `_selectedIndex` (the user could have moved the cursor between
    // pressing Enter and the process exit).
    property string _pendingEngine: ""
    // "binary" | "model" | "" — flashes the matching unavailable header hint.
    property string _pulsedHint: ""

    // ----- config.toml watcher (read current engine) -----

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        printErrors: false

        onLoaded: {
            const parsed = root._parseEngineFromToml(text() || "");
            if (parsed !== root._activeEngine) {
                root._activeEngine = parsed;
            }
            root._configModels = root._parseSectionModels(text() || "");
            root._refreshEngineLists();
            root._syncSelectionToActive();
        }

        onLoadFailed: {
            // No config file yet → effective engine is the default
            // (whisper). Keep cursor on Whisper so the empty state is
            // obvious.
            if (root._activeEngine !== "whisper") {
                root._activeEngine = "whisper";
            }
            root._configModels = {};
            root._refreshEngineLists();
            root._syncSelectionToActive();
        }

        onFileChanged: reload()
    }

    // ----- engine-picker.flag (toggle visibility) -----

    FileView {
        id: flagFile
        path: root.runtimeDir + "/engine-picker.flag"
        watchChanges: true
        printErrors: false

        onLoaded: {
            root.open = !root.open;
            removeFlagProcess.start();
        }

        onFileChanged: reload()
    }

    Process {
        id: removeFlagProcess
        command: ["rm", "-f", root.runtimeDir + "/engine-picker.flag"]
        running: false

        function start() {
            if (!removeFlagProcess.running) {
                removeFlagProcess.running = true;
            }
        }
    }

    // ----- `voxtype info variants --json` (compiled features) -----

    Process {
        id: featuresProcess
        command: [root.voxtypeBinary, "info", "variants", "--json"]
        running: false

        property string _buffer: ""

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { featuresProcess._buffer += line + "\n"; }
        }

        onRunningChanged: {
            if (!featuresProcess.running) {
                root._parseFeaturesJson(featuresProcess._buffer);
                featuresProcess._buffer = "";
            }
        }

        function refresh() {
            if (featuresProcess.running) return;
            featuresProcess._buffer = "";
            featuresProcess.running = true;
        }
    }

    // ----- downloaded models (ls of modelsDir) -----

    Process {
        id: modelsListProcess
        command: ["ls", "-1", root.modelsDir]
        running: false

        property string _buffer: ""

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { modelsListProcess._buffer += line + "\n"; }
        }

        onRunningChanged: {
            if (!modelsListProcess.running) {
                root._parseModelDirListing(modelsListProcess._buffer);
                modelsListProcess._buffer = "";
            }
        }

        function refresh() {
            if (modelsListProcess.running) return;
            modelsListProcess._buffer = "";
            modelsListProcess.running = true;
        }
    }

    // ----- `voxtype config set engine <name>` (switch) -----

    Process {
        id: switchProcess
        // Command is rebuilt on each invocation since the target
        // engine changes; Process.command is read at start time so
        // updating it before flipping `running` is sufficient.
        command: [root.voxtypeBinary, "config", "set", "engine", "whisper"]
        running: false

        // stderr accumulator. The CLI's error messages identify the
        // failure mode by phrase (e.g. "is not compiled into this
        // binary"), which is the authoritative way to distinguish
        // exit code 2 from exit code 1 without depending on a
        // potentially-absent `exitCode` property on Quickshell's
        // Process binding.
        property string _stderrBuffer: ""

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                switchProcess._stderrBuffer += line + "\n";
            }
        }

        onRunningChanged: {
            if (!switchProcess.running) {
                root._handleSwitchExit(switchProcess._stderrBuffer);
                switchProcess._stderrBuffer = "";
            }
        }
    }

    Timer {
        id: hintPulseTimer
        interval: 1400
        repeat: false
        onTriggered: root._pulsedHint = ""
    }

    Timer {
        id: actionStatusTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root._actionStatus = "";
            root._actionKind = "info";
        }
    }

    // Auto-close after a successful switch so the user sees the
    // confirmation briefly before the panel disappears.
    Timer {
        id: autoCloseTimer
        interval: 1500
        repeat: false
        onTriggered: root._close()
    }

    // ----- lifecycle -----

    // Refresh feature list whenever the panel opens. Cheap (one
    // subprocess) and the user's binary could have been swapped
    // between opens via `voxtype-bin` package upgrades.
    onOpenChanged: {
        if (root.open) {
            VT.Theme.reload();
            configFile.reload();
            featuresProcess.refresh();
            modelsListProcess.refresh();
            // Reset transient state so a previous "Failed to..." line
            // doesn't carry over into a fresh open.
            root._actionStatus = "";
            root._actionKind = "info";
            root._pulsedHint = "";
            autoCloseTimer.stop();
            hintPulseTimer.stop();
            Qt.callLater(function() {
                listFlick.ensureIndexVisible(root._selectedIndex);
            });
        }
    }

    on_CompiledFeaturesChanged: {
        root._refreshEngineLists();
        root._syncSelectionToActive();
    }

    on_ModelDirEntriesChanged: {
        root._refreshEngineLists();
        root._syncSelectionToActive();
    }

    Component.onCompleted: {
        root._refreshEngineLists();
        modelsListProcess.refresh();
    }

    // ----- helpers -----

    function _indexInList(list, name) {
        for (let i = 0; i < list.length; ++i) {
            if (list[i].name === name) return i;
        }
        return -1;
    }

    function _focusRows() {
        const rows = root._availableEngines.slice();
        for (let i = 0; i < root._unavailableEngines.length; ++i) {
            rows.push(root._unavailableEngines[i]);
        }
        return rows;
    }

    function _focusIndexOf(name) {
        const rows = root._focusRows();
        return root._indexInList(rows, name);
    }

    function _refreshEngineLists() {
        const avail = [];
        const unavail = [];
        for (let i = 0; i < root.engines.length; ++i) {
            const engine = root.engines[i];
            if (root._engineAvailable(engine.name)) {
                avail.push(engine);
            } else {
                unavail.push(engine);
            }
        }
        root._availableEngines = avail;
        root._unavailableEngines = unavail;
        let binaryCount = 0;
        let modelCount = 0;
        for (let j = 0; j < unavail.length; ++j) {
            if (!root._engineCompiled(unavail[j].name)) {
                binaryCount++;
            } else {
                modelCount++;
            }
        }
        root._unavailableBinaryCount = binaryCount;
        root._unavailableModelCount = modelCount;
    }

    function _syncSelectionToActive() {
        const idx = root._focusIndexOf(root._activeEngine);
        root._selectedIndex = idx >= 0 ? idx : 0;
    }

    function _parseEngineFromToml(content) {
        // Minimal TOML scan: find `engine = "<value>"` at the top
        // level. The setting lives on the root table in voxtype's
        // schema (see `Config.engine` in src/config.rs), so we stop
        // scanning when a `[section]` header is reached to avoid
        // matching a hypothetical `[xyz] engine = ...` inside a
        // nested table. Comments after the value are tolerated.
        if (!content || content.length === 0) return "whisper";
        const lines = content.split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const raw = lines[i];
            const line = raw.replace(/^\s+/, "");
            if (line.length === 0 || line[0] === "#") continue;
            if (line[0] === "[") break;
            // Match: engine = "<name>"  (single or double quotes,
            // optional trailing comment).
            const m = line.match(/^engine\s*=\s*["']([^"']+)["']/);
            if (m) {
                return m[1];
            }
        }
        return "whisper";
    }

    function _parseSectionModels(content) {
        const map = {};
        if (!content || content.length === 0) return map;
        for (let i = 0; i < root.engines.length; ++i) {
            const name = root.engines[i].name;
            const value = root._tomlSectionKey(content, name, "model");
            if (value.length > 0) {
                map[name] = value;
            }
        }
        return map;
    }

    function _tomlSectionKey(content, section, key) {
        const header = "[" + section + "]";
        const lines = content.split("\n");
        let inSection = false;
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].replace(/^\s+/, "");
            if (line.length === 0 || line[0] === "#") continue;
            if (line[0] === "[") {
                inSection = (line.replace(/\s+/g, "") === header);
                continue;
            }
            if (!inSection) continue;
            const m = line.match(new RegExp("^" + key + "\\s*=\\s*[\"']([^\"']+)[\"']"));
            if (m) return m[1];
        }
        return "";
    }

    function _parseModelDirListing(buf) {
        const entries = [];
        const lines = (buf || "").split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const name = lines[i].trim();
            if (name.length > 0) entries.push(name);
        }
        root._modelDirEntries = entries;
    }

    function _catalogEntry(name) {
        for (let i = 0; i < root.engines.length; ++i) {
            if (root.engines[i].name === name) return root.engines[i];
        }
        return null;
    }

    function _modelNameFor(name) {
        const configured = root._configModels[name];
        if (configured && configured.length > 0) return configured;
        const entry = root._catalogEntry(name);
        return entry && entry.defaultModel ? entry.defaultModel : "";
    }

    function _modelDownloaded(name) {
        const raw = root._modelNameFor(name);
        if (!raw || raw.length === 0) return false;
        if (raw[0] === "/") {
            const base = raw.substring(raw.lastIndexOf("/") + 1);
            return root._modelDirEntries.indexOf(base) >= 0;
        }
        const entries = root._modelDirEntries;
        if (name === "whisper") {
            return entries.indexOf("ggml-" + raw + ".bin") >= 0
                || entries.indexOf(raw + ".bin") >= 0
                || entries.indexOf(raw) >= 0;
        }
        if (name === "moonshine") {
            return entries.indexOf("moonshine-" + raw) >= 0
                || entries.indexOf(raw) >= 0;
        }
        return entries.indexOf(raw) >= 0;
    }

    function _parseFeaturesJson(buf) {
        if (!buf || buf.length === 0) return;
        try {
            const obj = JSON.parse(buf);
            if (obj && Array.isArray(obj.compiled_features)) {
                root._compiledFeatures = obj.compiled_features;
            } else {
                root._compiledFeatures = [];
            }
        } catch (e) {
            // Older voxtype binaries that predate `info variants
            // --json` print human-readable text; treat as "unknown
            // features" and let the switch-time check be authoritative.
            root._compiledFeatures = [];
        }
    }

    function _engineCompiled(name) {
        if (name === "whisper") return true;
        // Unknown feature list: do not claim ONNX engines are ready.
        if (root._compiledFeatures.length === 0) return false;
        return root._compiledFeatures.indexOf(name) >= 0;
    }

    function _engineAvailable(name) {
        return root._engineCompiled(name) && root._modelDownloaded(name);
    }

    function _unavailableHintKind(name) {
        if (!root._engineCompiled(name)) return "binary";
        return "model";
    }

    function _pulseUnavailableHint(name) {
        const kind = root._unavailableHintKind(name);
        if (root._pulsedHint === kind) return;
        root._pulsedHint = kind;
        hintPulseTimer.restart();
    }

    function _selectEngine(idx) {
        const rows = root._focusRows();
        if (idx < 0 || idx >= rows.length) return;
        root._selectedIndex = idx;
        listFlick.ensureIndexVisible(idx);
    }

    function _commit() {
        const rows = root._focusRows();
        const idx = root._selectedIndex;
        if (idx < 0 || idx >= rows.length) return;
        const engine = rows[idx];
        if (!root._engineAvailable(engine.name)) {
            root._pulseUnavailableHint(engine.name);
            return;
        }
        if (engine.name === root._activeEngine) {
            root._actionStatus = "";
            root._actionKind = "info";
            actionStatusTimer.stop();
            autoCloseTimer.stop();
            return;
        }
        if (switchProcess.running) return;
        root._pendingEngine = engine.name;
        root._actionKind = "info";
        root._actionStatus = "Switching to " + engine.name + "...";
        actionStatusTimer.stop();
        autoCloseTimer.stop();
        switchProcess.command = [
            root.voxtypeBinary, "config", "set", "engine", engine.name
        ];
        switchProcess.running = true;
    }

    function _handleSwitchExit(stderrText) {
        const name = root._pendingEngine;
        // Force a config-file re-read first; FileView will fire
        // onLoaded synchronously below (Quickshell reads synchronously
        // for local files), updating `_activeEngine` in time for the
        // success check.
        configFile.reload();

        const stderr = (stderrText || "");
        const notCompiled = stderr.indexOf("not compiled") >= 0
                         || stderr.indexOf("unknown engine") >= 0;

        if (root._activeEngine === name) {
            root._actionKind = "ok";
            root._actionStatus = "Switched to " + name + ". Restart voxtype to apply.";
            autoCloseTimer.restart();
        } else if (notCompiled) {
            root._actionKind = "error";
            root._pulseUnavailableHint(name);
            actionStatusTimer.restart();
        } else {
            root._actionKind = "error";
            root._actionStatus = "Failed to write config (see voxtype logs).";
            actionStatusTimer.restart();
        }
        root._pendingEngine = "";
    }

    function _close() {
        root.open = false;
        autoCloseTimer.stop();
    }

    // ----- card UI -----

    Rectangle {
        id: card
        width: 420
        // Size from content so a new engine cannot clip the last row.
        // Cap at 80% of the overlay and scroll the list if needed.
        readonly property int maxHeight: Math.max(160, Math.floor(root.height * 0.8))
        implicitHeight: body.implicitHeight + 2 * VT.Theme.padding + 4
        height: Math.min(implicitHeight, maxHeight)
        clip: true
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        radius: VT.Theme.cornerRadius
        color: VT.Theme.bgColor
        border.width: 2
        border.color: VT.Theme.accentColor

        focus: true

        Keys.onEscapePressed: root._close()
        Keys.onUpPressed: function(event) {
            const rows = root._focusRows();
            if (rows.length === 0) {
                event.accepted = true;
                return;
            }
            const next = root._selectedIndex > 0
                       ? root._selectedIndex - 1
                       : rows.length - 1;
            root._selectEngine(next);
            event.accepted = true;
        }
        Keys.onDownPressed: function(event) {
            const rows = root._focusRows();
            if (rows.length === 0) {
                event.accepted = true;
                return;
            }
            const next = (root._selectedIndex + 1) % rows.length;
            root._selectEngine(next);
            event.accepted = true;
        }
        Keys.onReturnPressed: function(event) {
            root._commit();
            event.accepted = true;
        }
        Keys.onEnterPressed: function(event) {
            root._commit();
            event.accepted = true;
        }
        Keys.onPressed: function(event) {
            // Number keys jump-select among available engines only.
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                const idx = event.key - Qt.Key_1;
                if (idx < root._availableEngines.length) {
                    root._selectEngine(idx);
                    root._commit();
                    event.accepted = true;
                }
            }
        }

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.leftMargin: VT.Theme.padding
            anchors.rightMargin: VT.Theme.padding
            anchors.topMargin: VT.Theme.padding
            anchors.bottomMargin: VT.Theme.padding + 4
            spacing: 8

            // --- header ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Transcription engine"
                    font.family: "JetBrainsMono Nerd Font"
                    font.bold: true
                    font.pixelSize: 16
                    color: VT.Theme.textColor
                }

                Text {
                    text: "Esc  Close"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    color: VT.Theme.subtextColor
                    opacity: 0.7
                }
            }

            // --- engine rows ---
            Flickable {
                id: listFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: engineColumn.implicitHeight
                Layout.minimumHeight: 36
                clip: true
                contentWidth: width
                contentHeight: engineColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height + 1
                flickableDirection: Flickable.VerticalFlick

                ColumnLayout {
                    id: engineColumn
                    width: listFlick.width
                    spacing: 8

                    Repeater {
                        id: availableRepeater
                        model: root._availableEngines

                        EngineRow {
                            Layout.fillWidth: true
                            engineName: modelData.name
                            engineLabel: modelData.label
                            summary: modelData.summary
                            shortcut: (index + 1).toString()
                            isActive: modelData.name === root._activeEngine
                            isSelected: index === root._selectedIndex
                            isAvailable: true

                            onClicked: {
                                root._selectEngine(index);
                                root._commit();
                            }
                        }
                    }

                    ColumnLayout {
                        id: unavailableHeader
                        visible: root._unavailableEngines.length > 0
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            Layout.topMargin: 4
                            text: "Unavailable (" + root._unavailableEngines.length + ")"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            color: VT.Theme.subtextColor
                        }

                        Text {
                            visible: root._unavailableBinaryCount > 0
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            textFormat: Text.StyledText
                            text: "Use <b>voxtype configure</b> to switch binaries"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            color: root._pulsedHint === "binary"
                                   ? VT.Theme.accentColor
                                   : VT.Theme.subtextColor
                            opacity: root._pulsedHint === "binary" ? 1.0 : 0.7
                        }

                        Text {
                            visible: root._unavailableModelCount > 0
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            Layout.bottomMargin: 4
                            textFormat: Text.StyledText
                            text: "Download with <b>voxtype setup model</b>"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            color: root._pulsedHint === "model"
                                   ? VT.Theme.accentColor
                                   : VT.Theme.subtextColor
                            opacity: root._pulsedHint === "model" ? 1.0 : 0.7
                        }
                    }

                    Repeater {
                        id: unavailableRepeater
                        model: root._unavailableEngines

                        EngineRow {
                            Layout.fillWidth: true
                            engineName: modelData.name
                            engineLabel: modelData.label
                            summary: modelData.summary
                            shortcut: ""
                            isActive: modelData.name === root._activeEngine
                            isSelected: (root._availableEngines.length + index) === root._selectedIndex
                            isAvailable: false

                            onClicked: {
                                root._selectEngine(root._availableEngines.length + index);
                                root._commit();
                            }
                        }
                    }
                }

                function ensureIndexVisible(idx) {
                    const rows = root._focusRows();
                    if (idx < 0 || idx >= rows.length || height <= 0) return;
                    const name = rows[idx].name;
                    let item = null;
                    const availIdx = root._indexInList(root._availableEngines, name);
                    if (availIdx >= 0) {
                        item = availableRepeater.itemAt(availIdx);
                    } else {
                        const unavailIdx = root._indexInList(root._unavailableEngines, name);
                        if (unavailIdx >= 0) {
                            item = unavailableRepeater.itemAt(unavailIdx);
                        }
                    }
                    if (!item) return;
                    const pos = item.mapToItem(engineColumn, 0, 0);
                    const y = pos.y;
                    const bottom = y + item.height;
                    if (contentHeight <= height + 1) {
                        contentY = 0;
                        return;
                    }
                    if (y < contentY) {
                        contentY = Math.max(0, y);
                    } else if (bottom > contentY + height) {
                        contentY = Math.min(contentHeight - height, bottom - height);
                    }
                }
            }

            // --- transient status line ---
            Text {
                Layout.fillWidth: true
                visible: root._actionStatus.length > 0
                text: root._actionStatus
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                color: root._actionKind === "ok"    ? VT.Theme.streamingColor
                     : root._actionKind === "error" ? VT.Theme.recordingColor
                     :                                VT.Theme.textColor
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }

    // Theme-change reveal wipe over the card. Must be a sibling placed
    // after `card` so it paints above it; grabToImage/hideSource keep
    // keyboard and mouse input on `card` working while it's active.
    VT.ThemeReveal {
        target: card
    }

    // ----- inline component definition: engine row -----
    //
    // Mirrors MeetingControls' inline MeetingButton: defined inline so
    // EnginePicker.qml stays a single file. Lift into voxtype-shared
    // if a third widget ever needs the same row styling.

    component EngineRow: Rectangle {
        id: row
        property string engineName: ""
        property string engineLabel: ""
        property string summary: ""
        property string shortcut: ""
        property bool isActive: false
        property bool isSelected: false
        property bool isAvailable: true

        signal clicked()

        implicitHeight: contentRow.implicitHeight + 16
        Layout.preferredHeight: implicitHeight
        radius: 6
        color: row.isSelected ? VT.Theme.selectedFill
              : mouse.containsMouse ? VT.Theme.rowHoverFill
              : VT.Theme.rowIdleFill
        border.width: row.isSelected ? 1 : 0
        border.color: VT.Theme.accentColor

        RowLayout {
            id: contentRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            // Active / unavailable glyph; blank for available-but-inactive
            // so the name column stays aligned across all rows.
            Text {
                Layout.preferredWidth: 14
                text: row.isActive ? "✓" : (row.isAvailable ? "" : "–")
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
                font.bold: true
                color: row.isActive ? VT.Theme.streamingColor : VT.Theme.subtextColor
                horizontalAlignment: Text.AlignHCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: row.engineLabel
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.bold: row.isActive
                    color: row.isActive ? VT.Theme.accentColor : VT.Theme.textColor
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: row.summary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    color: VT.Theme.subtextColor
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: row.shortcut.length > 0
                text: "[" + row.shortcut + "]"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                color: VT.Theme.subtextColor
                opacity: 0.7
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: row.isAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: row.clicked()
        }
    }
}
