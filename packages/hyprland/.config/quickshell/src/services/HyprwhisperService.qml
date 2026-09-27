import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int activeRefreshIntervalMs: 180
    property int idleRefreshIntervalMs: 500
    property string state: "stopped"
    property string label: "Voice Typing"
    property string detail: "Tap to start dictation"
    property string tone: "muted"
    property real progress: 0
    property bool overlayVisible: false
    property bool indeterminate: false
    property string buttonLabel: "Talk"
    property string buttonIcon: "󰍬"
    property string buttonTone: "muted"
    property bool toggleEnabled: true
    property var scriptCommandPrefix: ["bash", Quickshell.shellPath("scripts/hyprwhisper.sh")]
    readonly property bool statusVisible: root.state === "recording"
        || root.state === "processing"
        || root.state === "paused"
        || root.state === "success"
        || root.state === "error"

    readonly property int refreshIntervalMs: root.overlayVisible
        || root.state === "recording"
        || root.state === "processing"
        || root.state === "paused"
        || root.state === "success"
        ? root.activeRefreshIntervalMs
        : root.idleRefreshIntervalMs

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function stringValue(value, fallbackValue) {
        const normalized = String(value || "").trim();
        return normalized.length ? normalized : fallbackValue;
    }

    function numberValue(value, fallbackValue) {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : fallbackValue;
    }

    function applyPayload(raw) {
        const input = String(raw || "").trim();
        if (!input.length) {
            return;
        }

        let payload = null;

        try {
            payload = JSON.parse(input);
        } catch (error) {
            return;
        }

        root.state = root.stringValue(payload.state, "stopped");
        root.label = root.stringValue(payload.label, "Voice Typing");
        root.detail = root.stringValue(payload.detail, "Tap to start dictation");
        root.tone = root.stringValue(payload.tone, "muted");
        root.progress = root.clamp(root.numberValue(payload.progress, 0), 0, 100);
        root.overlayVisible = Boolean(payload.overlayVisible);
        root.indeterminate = Boolean(payload.indeterminate);
        root.buttonLabel = root.stringValue(payload.buttonLabel, "Talk");
        root.buttonIcon = root.stringValue(payload.buttonIcon, "󰍬");
        root.buttonTone = root.stringValue(payload.buttonTone, "muted");
        root.toggleEnabled = Boolean(payload.toggleEnabled);
    }

    function refresh() {
        if (!statusProcess.running) {
            statusProcess.running = true;
        }
    }

    function toggleRecording() {
        if (!root.toggleEnabled) {
            return;
        }

        const command = root.state === "recording" ? "stop" : "record";
        Quickshell.execDetached(root.scriptCommandPrefix.concat([command]));
        postToggleRefresh.restart();
    }

    readonly property QtObject statusProcess: Process {
        id: statusProcess
        command: root.scriptCommandPrefix.concat(["status"])
        running: false
        stdout: StdioCollector {
            id: statusStdout
            waitForEnd: true
        }
        onExited: root.applyPayload(statusStdout.text)
    }

    readonly property QtObject refreshTimer: Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    readonly property QtObject postToggleRefresh: Timer {
        id: postToggleRefresh
        interval: 240
        repeat: false
        onTriggered: root.refresh()
    }
}
