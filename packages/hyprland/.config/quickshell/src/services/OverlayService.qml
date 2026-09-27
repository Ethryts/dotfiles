pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

QtObject {
    id: root

    property bool visible: false
    property var activeOverlay: null
    property var screen: null
    property int hideDelayMs: 1600
    property int sequenceCounter: 0
    property var previousValueByKind: ({})

    function normalizeKind(kind) {
        return String(kind || "").trim().toLowerCase();
    }

    function numberValue(value, fallbackValue) {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : fallbackValue;
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function focusedScreen() {
        const screens = Quickshell.screens || [];
        const focusedMonitor = Hyprland.focusedMonitor;

        if (focusedMonitor) {
            for (let i = 0; i < screens.length; ++i) {
                const candidate = screens[i];
                if (Hyprland.monitorFor(candidate) === focusedMonitor) {
                    return candidate;
                }
            }
        }

        return screens.length > 0 ? screens[0] : null;
    }

    function resolveScreen(screenName) {
        const requestedName = String(screenName || "").trim();
        const screens = Quickshell.screens || [];

        if (requestedName.length > 0) {
            for (let i = 0; i < screens.length; ++i) {
                if (screens[i] && screens[i].name === requestedName) {
                    return screens[i];
                }
            }
        }

        return root.focusedScreen();
    }

    function fallbackOverlay(kind, rawValue) {
        return {
            label: kind,
            iconText: "",
            value: root.clamp(Math.round(rawValue), 0, 100),
            valueText: Math.round(rawValue) + "%",
            showBar: true,
            minValue: 0,
            maxValue: 100,
            tone: "accent"
        };
    }

    function brightnessOverlay(rawValue) {
        const value = root.clamp(Math.round(rawValue), 0, 100);
        return {
            label: "Brightness",
            iconText: "󰃟",
            value: value,
            valueText: value + "%",
            showBar: true,
            minValue: 0,
            maxValue: 100,
            tone: "accent"
        };
    }

    function volumeOverlay(rawValue) {
        const value = root.clamp(Math.round(rawValue), 0, 100);
        let iconText = "";

        if (value <= 0) {
            iconText = "";
        } else if (value < 34) {
            iconText = "";
        } else if (value < 67) {
            iconText = "";
        }

        return {
            label: "Volume",
            iconText: iconText,
            value: value,
            valueText: value + "%",
            showBar: true,
            minValue: 0,
            maxValue: 100,
            tone: "accent"
        };
    }

    function muteOverlay(rawValue) {
        const muted = root.numberValue(rawValue, 0) > 0;

        return {
            label: "Audio",
            iconText: muted ? "" : "",
            value: muted ? 100 : 0,
            valueText: muted ? "Muted" : "On",
            showBar: false,
            minValue: 0,
            maxValue: 100,
            tone: muted ? "error" : "accent"
        };
    }

    function overlayForKind(kind, rawValue) {
        switch (kind) {
        case "brightness":
            return root.brightnessOverlay(rawValue);
        case "volume":
            return root.volumeOverlay(rawValue);
        case "mute":
            return root.muteOverlay(rawValue);
        default:
            return root.fallbackOverlay(kind, rawValue);
        }
    }

    function show(kind, value, screenName) {
        const normalizedKind = root.normalizeKind(kind);
        const targetScreen = root.resolveScreen(screenName);

        if (!normalizedKind.length || !targetScreen) {
            return;
        }

        const previousByKind = root.previousValueByKind || ({});
        const rawValue = root.numberValue(value, 0);
        const hasPreviousValue = normalizedKind in previousByKind;
        const overlay = root.overlayForKind(normalizedKind, rawValue);

        root.sequenceCounter += 1;
        root.previousValueByKind = Object.assign({}, previousByKind, {
            [normalizedKind]: overlay.value
        });
        root.activeOverlay = {
            sequence: root.sequenceCounter,
            kind: normalizedKind,
            label: overlay.label,
            iconText: overlay.iconText,
            value: overlay.value,
            previousValue: hasPreviousValue ? previousByKind[normalizedKind] : overlay.value,
            hasPreviousValue: hasPreviousValue,
            valueText: overlay.valueText,
            showBar: overlay.showBar,
            minValue: overlay.minValue,
            maxValue: overlay.maxValue,
            tone: overlay.tone
        };
        root.screen = targetScreen;
        root.visible = true;

        if (root.hideDelayMs > 0) {
            hideTimer.restart();
        }
    }

    function close() {
        hideTimer.stop();
        root.visible = false;
    }

    readonly property QtObject hideTimer: Timer {
        id: hideTimer
        interval: root.hideDelayMs
        repeat: false
        onTriggered: root.close()
    }

    readonly property QtObject ipcHandler: IpcHandler {
        target: "overlay"

        function brightness(value: string) {
            root.show("brightness", value, "");
        }

        function volume(value: string) {
            root.show("volume", value, "");
        }

        function mute(value: string) {
            root.show("mute", value, "");
        }

        function generic(kind: string, value: string) {
            root.show(kind, value, "");
        }

        function closeOverlay() {
            root.close();
        }
    }
}
