import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property var scriptCommandPrefix: ["bash", Quickshell.shellPath("scripts/powerprofiles.sh")]

    property string currentProfile: ""
    property var profiles: []
    property string actionMessage: ""
    property string actionTone: "info"

    readonly property bool busy: listProcess.running || actionProcess.running
    readonly property bool available: root.currentProfile.length > 0 || root.profiles.length > 0

    function displayName(profileId) {
        switch (String(profileId || "")) {
        case "power-saver":
            return "Power Saver";
        case "balanced":
            return "Balanced";
        case "performance":
            return "Performance";
        default:
            if (String(profileId || "").length === 0) {
                return "Unknown";
            }

            return String(profileId)
                .split("-")
                .map(function(part) {
                    return part.length > 0
                        ? (part.charAt(0).toUpperCase() + part.slice(1))
                        : "";
                })
                .join(" ");
        }
    }

    function parseList(raw) {
        const lines = String(raw || "").trim().split(/\n+/);
        const parsedProfiles = [];
        let nextCurrentProfile = "";
        let nextActionMessage = "";
        let nextActionTone = "info";

        for (let index = 0; index < lines.length; ++index) {
            const line = lines[index];
            if (!line.length) {
                continue;
            }

            const parts = line.split("\t");
            if (parts[0] === "error") {
                nextActionTone = "error";
                nextActionMessage = parts.length > 1 ? parts.slice(1).join(" ") : "Unable to read power profiles";
                continue;
            }

            if (parts[0] !== "profile" || parts.length < 3) {
                continue;
            }

            const profile = {
                id: parts[1],
                active: parts[2] === "yes",
                degraded: parts.length > 3 ? parts[3] === "yes" : false,
                degradedReason: parts.length > 4 ? parts[4] : "",
                cpuDriver: parts.length > 5 ? parts[5] : "",
                platformDriver: parts.length > 6 ? parts[6] : ""
            };

            if (profile.active) {
                nextCurrentProfile = profile.id;
            }

            parsedProfiles.push(profile);
        }

        root.profiles = parsedProfiles;
        root.currentProfile = nextCurrentProfile;

        if (nextActionMessage.length > 0) {
            root.actionTone = nextActionTone;
            root.actionMessage = nextActionMessage;
        } else if (!root.busy) {
            root.actionMessage = "";
            root.actionTone = "info";
        }
    }

    function refresh() {
        if (!listProcess.running && !actionProcess.running) {
            listProcess.running = true;
        }
    }

    function clearActionMessage() {
        root.actionMessage = "";
        root.actionTone = "info";
    }

    function setProfile(profileId) {
        if (!profileId || root.busy || profileId === root.currentProfile) {
            return;
        }

        root.clearActionMessage();
        actionProcess.exec(root.scriptCommandPrefix.concat(["set", profileId]));
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
            const status = parts.length > 0 ? parts[0] : "";
            const selectedProfile = parts.length > 1 ? parts[1] : "";

            if (status === "ok") {
                root.actionTone = "success";
                root.actionMessage = "Switched to " + root.displayName(selectedProfile);
            } else {
                root.actionTone = "error";
                root.actionMessage = parts.length > 1 ? parts.slice(1).join(" ") : "Unable to change power profile";
            }

            clearMessageTimer.restart();
            refreshDelay.restart();
        }
    }

    readonly property QtObject refreshDelay: Timer {
        id: refreshDelay
        interval: 250
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
