import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int refreshIntervalMs: 3500
    property var scriptCommandPrefix: ["bash", Quickshell.shellPath("scripts/brightness.sh")]
    property int brightnessPercent: -1
    property int pendingBrightnessPercent: -1
    property int activeBrightnessPercent: -1

    readonly property bool available: root.brightnessPercent >= 0
    readonly property bool busy: actionProcess.running

    function parseOutput(raw) {
        if (root.busy) {
            return;
        }

        const parsed = Number(String(raw || "").trim());
        root.brightnessPercent = Number.isFinite(parsed)
            ? Math.max(0, Math.min(100, Math.round(parsed)))
            : -1;
    }

    function refresh() {
        if (!stateProcess.running && !root.busy) {
            stateProcess.running = true;
        }
    }

    function runAction(command) {
        if (!root.busy) {
            actionProcess.exec(command);
        }
    }

    function runBrightnessSet(percent) {
        root.activeBrightnessPercent = percent;
        actionProcess.exec(root.scriptCommandPrefix.concat(["set", String(percent)]));
    }

    function adjust(direction) {
        root.runAction(root.scriptCommandPrefix.concat([direction > 0 ? "up" : "down"]));
    }

    function setBrightness(percent) {
        const clamped = Math.max(1, Math.min(100, Math.round(percent)));
        root.brightnessPercent = clamped;

        if (root.busy) {
            root.pendingBrightnessPercent = clamped;
            return;
        }

        root.runBrightnessSet(clamped);
    }

    readonly property QtObject stateProcess: Process {
        id: stateProcess
        command: root.scriptCommandPrefix.concat(["get"])
        running: false
        stdout: StdioCollector {
            id: stateStdout
            waitForEnd: true
        }
        onExited: root.parseOutput(stateStdout.text)
    }

    readonly property QtObject actionProcess: Process {
        id: actionProcess
        onExited: {
            if (root.pendingBrightnessPercent >= 0
                    && root.pendingBrightnessPercent !== root.activeBrightnessPercent) {
                const pending = root.pendingBrightnessPercent;
                root.pendingBrightnessPercent = -1;
                root.runBrightnessSet(pending);
                return;
            }

            root.pendingBrightnessPercent = -1;
            root.activeBrightnessPercent = -1;
            refreshDelay.restart();
        }
    }

    readonly property QtObject refreshTimer: Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    readonly property QtObject refreshDelay: Timer {
        id: refreshDelay
        interval: 200
        repeat: false
        onTriggered: root.refresh()
    }
}
