import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int summaryRefreshIntervalMs: 5000
    property int detailsRefreshCooldownMs: 3000
    property var scriptCommandPrefix: ["bash", Quickshell.shellPath("scripts/network.sh")]

    property string connectionKind: "offline"
    property int wifiSignal: 0
    property string tooltipText: "Offline"
    property string connectionLabel: "Offline"
    property int connectionSignal: -1
    property var networks: []
    property string actionMessage: ""
    property string actionTone: "info"
    property double lastDetailsRefreshMs: 0

    readonly property bool busy: listProcess.running || actionProcess.running

    function parseSummary(raw) {
        const line = String(raw || "").trim();

        if (line === "ethernet") {
            root.connectionKind = "ethernet";
            root.wifiSignal = 0;
            return;
        }

        if (line.indexOf("wifi:") === 0) {
            root.connectionKind = "wifi";
            root.wifiSignal = Math.max(0, Math.min(100, Number(line.slice(5)) || 0));
            return;
        }

        root.connectionKind = "offline";
        root.wifiSignal = 0;
    }

    function parseDetails(raw) {
        const parts = String(raw || "").trim().split("\t");
        const detailKind = parts.length > 0 ? parts[0] : "offline";

        switch (detailKind) {
        case "ethernet":
            root.tooltipText = parts.length > 1 && parts[1].length > 0
                ? "Ethernet: " + parts[1]
                : "Ethernet connected";
            break;
        case "wifi":
            root.tooltipText = (parts.length > 1 && parts[1].length > 0 ? parts[1] : "Wi-Fi")
                + (parts.length > 2 && parts[2].length > 0 ? (" (" + parts[2] + "%)") : "");
            break;
        default:
            root.tooltipText = "Offline";
            break;
        }
    }

    function parseList(raw) {
        const lines = String(raw || "").trim().split(/\n+/);
        const parsedNetworks = [];

        root.connectionKind = "offline";
        root.connectionLabel = "Offline";
        root.connectionSignal = -1;

        for (let index = 0; index < lines.length; ++index) {
            const line = lines[index];
            if (!line.length) {
                continue;
            }

            const parts = line.split("\t");
            if (parts[0] === "current") {
                root.connectionKind = parts.length > 1 ? parts[1] : "offline";
                if (root.connectionKind === "wifi") {
                    root.connectionLabel = parts.length > 2 && parts[2].length > 0 ? parts[2] : "Wi-Fi";
                    root.connectionSignal = parts.length > 3 ? Number(parts[3]) : -1;
                } else if (root.connectionKind === "ethernet") {
                    root.connectionLabel = parts.length > 2 && parts[2].length > 0 ? parts[2] : "Ethernet";
                    root.connectionSignal = -1;
                } else {
                    root.connectionLabel = "Offline";
                    root.connectionSignal = -1;
                }
                continue;
            }

            if (parts[0] !== "network") {
                continue;
            }

            parsedNetworks.push({
                active: parts[1] === "yes",
                saved: parts[2] === "yes",
                open: parts[3] === "open",
                ssid: parts.length > 4 ? parts[4] : "Hidden network",
                bssid: parts.length > 5 ? parts[5] : "",
                signal: parts.length > 6 ? Number(parts[6]) : 0,
                security: parts.length > 7 ? parts[7] : "",
                connectable: parts.length > 8 ? parts[8] === "yes" : false
            });
        }

        parsedNetworks.sort(function(left, right) {
            const leftActive = left.active ? 1 : 0;
            const rightActive = right.active ? 1 : 0;
            if (leftActive !== rightActive) {
                return rightActive - leftActive;
            }

            if (left.signal !== right.signal) {
                return right.signal - left.signal;
            }

            return left.ssid.localeCompare(right.ssid);
        });

        root.networks = parsedNetworks;
    }

    function refreshSummary() {
        if (!summaryProcess.running) {
            summaryProcess.running = true;
        }
    }

    function refreshDetails(force) {
        const now = Date.now();
        if (!force && (now - root.lastDetailsRefreshMs) < root.detailsRefreshCooldownMs) {
            return;
        }

        if (!detailsProcess.running) {
            root.lastDetailsRefreshMs = now;
            detailsProcess.running = true;
        }
    }

    function refreshNetworks() {
        if (!listProcess.running) {
            listProcess.running = true;
        }
    }

    function clearActionMessage() {
        root.actionMessage = "";
        root.actionTone = "info";
    }

    function connectNetwork(network) {
        if (!network || !network.connectable || actionProcess.running) {
            return;
        }

        root.clearActionMessage();

        actionProcess.exec(root.scriptCommandPrefix.concat([
            "connect",
            network.ssid,
            network.bssid,
            network.saved ? "yes" : "no",
            network.open ? "yes" : "no"
        ]));
    }

    readonly property QtObject summaryProcess: Process {
        id: summaryProcess
        command: root.scriptCommandPrefix.concat(["get"])
        running: false
        stdout: StdioCollector {
            id: summaryStdout
            waitForEnd: true
        }
        onExited: root.parseSummary(summaryStdout.text)
    }

    readonly property QtObject detailsProcess: Process {
        id: detailsProcess
        command: root.scriptCommandPrefix.concat(["details"])
        running: false
        stdout: StdioCollector {
            id: detailsStdout
            waitForEnd: true
        }
        onExited: root.parseDetails(detailsStdout.text)
    }

    readonly property QtObject listProcess: Process {
        id: listProcess
        command: root.scriptCommandPrefix.concat(["list"])
        running: false
        stdout: StdioCollector {
            id: listStdout
            waitForEnd: true
        }
        onExited: root.parseList(listStdout.text)
    }

    readonly property QtObject actionProcess: Process {
        id: actionProcess
        stdout: StdioCollector {
            id: actionStdout
            waitForEnd: true
        }
        onExited: {
            const parts = String(actionStdout.text || "").trim().split("\t");
            root.actionTone = parts.length > 0 && parts[0].length > 0
                ? (parts[0] === "ok" ? "success" : (parts[0] === "needs-auth" ? "warning" : "error"))
                : "info";
            root.actionMessage = parts.length > 1 ? parts.slice(1).join(" ") : "";
            clearMessageTimer.restart();
            refreshDelay.restart();
        }
    }

    readonly property QtObject summaryTimer: Timer {
        interval: root.summaryRefreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshSummary()
    }

    readonly property QtObject refreshDelay: Timer {
        id: refreshDelay
        interval: 300
        repeat: false
        onTriggered: {
            root.refreshSummary();
            root.refreshDetails();
            root.refreshNetworks();
        }
    }

    readonly property QtObject clearMessageTimer: Timer {
        id: clearMessageTimer
        interval: 4000
        repeat: false
        onTriggered: root.actionMessage = ""
    }
}
