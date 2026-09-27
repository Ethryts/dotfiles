import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int refreshIntervalMs: 2200
    property var scriptCommandPrefix: ["bash", Quickshell.shellPath("scripts/audio.sh")]
    property int volumePercent: 0
    property bool muted: false
    property var outputDevices: []
    property var inputDevices: []
    property string currentOutputId: ""
    property string currentInputId: ""
    property string currentOutputLabel: ""
    property string currentInputLabel: ""
    property string actionMessage: ""
    property string actionTone: "info"
    property string statusMessage: ""
    property string statusTone: "info"
    property bool devicesAvailable: false
    property int pendingVolumePercent: -1
    property int activeVolumePercent: -1

    readonly property bool busy: actionProcess.running

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Math.round(value)));
    }

    function normalizeDevice(device) {
        if (!device || typeof device !== "object") {
            return null;
        }

        const id = String(device.id || "");
        const label = String(device.label || "");

        if (!id.length || !label.length) {
            return null;
        }

        return {
            id: id,
            label: label,
            active: !!device.active
        };
    }

    function normalizeDevices(devices) {
        if (!Array.isArray(devices)) {
            return [];
        }

        const normalized = [];

        for (let index = 0; index < devices.length; ++index) {
            const entry = root.normalizeDevice(devices[index]);
            if (entry) {
                normalized.push(entry);
            }
        }

        return normalized;
    }

    function setActiveDevice(devices, deviceId) {
        const updated = [];

        for (let index = 0; index < devices.length; ++index) {
            const device = devices[index];
            updated.push({
                id: device.id,
                label: device.label,
                active: device.id === deviceId
            });
        }

        return updated;
    }

    function activeDevice(devices, fallbackId) {
        for (let index = 0; index < devices.length; ++index) {
            if (devices[index].active) {
                return devices[index];
            }
        }

        if (!fallbackId.length) {
            return null;
        }

        for (let index = 0; index < devices.length; ++index) {
            if (devices[index].id === fallbackId) {
                return devices[index];
            }
        }

        return null;
    }

    function clearActionMessage() {
        root.actionMessage = "";
        root.actionTone = "info";
    }

    function parseOutput(raw) {
        if (root.busy) {
            return;
        }

        let parsed = null;

        try {
            parsed = JSON.parse(String(raw || "").trim());
        } catch (error) {
            parsed = null;
        }

        const outputDevices = root.normalizeDevices(parsed && parsed.outputDevices);
        const inputDevices = root.normalizeDevices(parsed && parsed.inputDevices);
        const parsedVolume = Number(parsed && parsed.volumePercent);
        const fallbackOutput = root.activeDevice(outputDevices, String(parsed && parsed.currentOutputId || ""));
        const fallbackInput = root.activeDevice(inputDevices, String(parsed && parsed.currentInputId || ""));

        root.volumePercent = Number.isFinite(parsedVolume) ? root.clampPercent(parsedVolume) : 0;
        root.muted = !!(parsed && parsed.muted);
        root.outputDevices = outputDevices;
        root.inputDevices = inputDevices;
        root.currentOutputId = String(parsed && parsed.currentOutputId || (fallbackOutput ? fallbackOutput.id : ""));
        root.currentInputId = String(parsed && parsed.currentInputId || (fallbackInput ? fallbackInput.id : ""));
        root.currentOutputLabel = String(parsed && parsed.currentOutputLabel || (fallbackOutput ? fallbackOutput.label : ""));
        root.currentInputLabel = String(parsed && parsed.currentInputLabel || (fallbackInput ? fallbackInput.label : ""));
        root.devicesAvailable = !!(parsed && parsed.devicesAvailable)
            || outputDevices.length > 0
            || inputDevices.length > 0;
        root.statusMessage = String(parsed && parsed.statusMessage || "");
        root.statusTone = String(parsed && parsed.statusTone || "info");
    }

    function refresh() {
        if (!stateProcess.running && !root.busy) {
            stateProcess.running = true;
        }
    }

    function runAction(command) {
        if (!root.busy) {
            root.clearActionMessage();
            actionProcess.exec(command);
        }
    }

    function runVolumeSet(percent) {
        root.activeVolumePercent = percent;
        root.clearActionMessage();
        actionProcess.exec(root.scriptCommandPrefix.concat(["set", String(percent)]));
    }

    function adjust(direction) {
        root.runAction(root.scriptCommandPrefix.concat([direction > 0 ? "up" : "down"]));
    }

    function setVolume(percent) {
        const clamped = root.clampPercent(percent);
        root.volumePercent = clamped;

        if (root.busy) {
            root.pendingVolumePercent = clamped;
            return;
        }

        root.runVolumeSet(clamped);
    }

    function toggleMute() {
        root.runAction(root.scriptCommandPrefix.concat(["mute"]));
    }

    function setOutputDevice(id) {
        const deviceId = String(id || "");
        if (!deviceId.length || root.busy || deviceId === root.currentOutputId) {
            return;
        }

        const nextDevices = root.setActiveDevice(root.outputDevices, deviceId);
        const nextDevice = root.activeDevice(nextDevices, deviceId);

        root.outputDevices = nextDevices;
        root.currentOutputId = deviceId;
        root.currentOutputLabel = nextDevice ? nextDevice.label : root.currentOutputLabel;
        root.runAction(root.scriptCommandPrefix.concat(["set-output", deviceId]));
    }

    function setInputDevice(id) {
        const deviceId = String(id || "");
        if (!deviceId.length || root.busy || deviceId === root.currentInputId) {
            return;
        }

        const nextDevices = root.setActiveDevice(root.inputDevices, deviceId);
        const nextDevice = root.activeDevice(nextDevices, deviceId);

        root.inputDevices = nextDevices;
        root.currentInputId = deviceId;
        root.currentInputLabel = nextDevice ? nextDevice.label : root.currentInputLabel;
        root.runAction(root.scriptCommandPrefix.concat(["set-input", deviceId]));
    }

    readonly property QtObject stateProcess: Process {
        id: stateProcess
        command: root.scriptCommandPrefix.concat(["state"])
        running: false
        stdout: StdioCollector {
            id: stateStdout
            waitForEnd: true
        }
        onExited: root.parseOutput(stateStdout.text)
    }

    readonly property QtObject actionProcess: Process {
        id: actionProcess
        stdout: StdioCollector {
            id: actionStdout
            waitForEnd: true
        }
        onExited: {
            const raw = String(actionStdout.text || "").trim();

            if (root.pendingVolumePercent >= 0
                    && root.pendingVolumePercent !== root.activeVolumePercent) {
                const pending = root.pendingVolumePercent;
                root.pendingVolumePercent = -1;
                root.runVolumeSet(pending);
                return;
            }

            root.pendingVolumePercent = -1;
            root.activeVolumePercent = -1;

            if (!raw.length) {
                root.clearActionMessage();
                refreshDelay.restart();
                return;
            }

            const parts = raw.split("\t");
            const status = parts.length > 0 ? parts[0] : "";
            const kind = parts.length > 1 ? parts[1] : "";
            const label = parts.length > 2 ? parts.slice(2).join(" ") : "";

            if (status === "ok") {
                root.actionTone = "success";
                root.actionMessage = kind === "input"
                    ? "Switched input to " + label
                    : "Switched output to " + label;
            } else {
                root.actionTone = "error";
                root.actionMessage = parts.length > 1
                    ? parts.slice(1).join(" ")
                    : "Unable to update audio settings";
            }

            clearMessageTimer.restart();
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
        interval: 180
        repeat: false
        onTriggered: root.refresh()
    }

    readonly property QtObject clearMessageTimer: Timer {
        id: clearMessageTimer
        interval: 4000
        repeat: false
        onTriggered: root.actionMessage = ""
    }
}
