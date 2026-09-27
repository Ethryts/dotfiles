pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property int refreshIntervalMs: 1500
    property string posture: "laptop"

    readonly property bool tabletMode: root.posture === "tablet"
    readonly property bool laptopMode: !root.tabletMode

    function parseOutput(raw) {
        const line = String(raw || "").trim();
        root.posture = line === "tablet" ? "tablet" : "laptop";
    }

    function refresh() {
        if (!readProcess.running) {
            readProcess.running = true;
        }
    }

    readonly property QtObject readProcess: Process {
        id: readProcess
        command: [
            "bash",
            "-lc",
            "if [ -r \"$HOME/.config/hypr/.tablet_posture\" ]; then posture=$(tr -d '\\r' < \"$HOME/.config/hypr/.tablet_posture\"); else posture=laptop; fi; " +
            "if [ \"$posture\" = tablet ] || [ \"$posture\" = laptop ]; then printf '%s\\n' \"$posture\"; else printf 'laptop\\n'; fi"
        ]
        running: false
        stdout: StdioCollector {
            id: postureStdout
            waitForEnd: true
        }
        onExited: root.parseOutput(postureStdout.text)
    }

    readonly property QtObject refreshTimer: Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: false
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
