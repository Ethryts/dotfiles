import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    required property QtObject postureService

    property int refreshIntervalMs: 1500
    property var scriptCommandPrefix: ["bash", Quickshell.shellPath("scripts/osk-toggle.sh")]
    property int lastScreenCount: -1
    property string lastPosture: ""
    property bool syncQueued: false

    function currentScreenCount() {
        const screens = Quickshell.screens || [];
        return screens.length;
    }

    function syncIfNeeded(force) {
        const screenCount = root.currentScreenCount();
        const posture = root.postureService ? root.postureService.posture : "laptop";

        if (!force && screenCount === root.lastScreenCount && posture === root.lastPosture) {
            return;
        }

        root.lastScreenCount = screenCount;
        root.lastPosture = posture;

        if (syncProcess.running) {
            root.syncQueued = true;
            return;
        }

        syncProcess.exec(root.scriptCommandPrefix.concat([
            "apply-smart",
            posture,
            String(Math.max(0, screenCount))
        ]));
    }

    readonly property QtObject syncProcess: Process {
        id: syncProcess
        onExited: {
            if (!root.syncQueued) {
                return;
            }

            root.syncQueued = false;
            root.syncIfNeeded(true);
        }
    }

    readonly property QtObject postureConnections: Connections {
        target: root.postureService

        function onPostureChanged() {
            root.syncIfNeeded(false);
        }
    }

    readonly property QtObject refreshTimer: Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.syncIfNeeded(false)
    }
}
