import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

QtObject {
    id: root

    property bool open: false
    property var screen: null
    property string openModeId: root.defaultModeId

    readonly property string defaultModeId: "apps"
    readonly property var modes: [
        {
            id: "apps",
            label: "Apps",
            placeholderText: "Launch an app",
            emptyText: "No applications found",
            noMatchText: "No matching apps",
            launchType: "desktop"
        },
        {
            id: "ssh",
            label: "SSH",
            placeholderText: "Connect to SSH host",
            emptyText: "No SSH hosts found",
            noMatchText: "No matching SSH hosts",
            searchCommandPrefix: [
                "bash",
                Quickshell.shellPath("scripts/ssh-launcher-search.sh")
            ],
            launchType: "ssh"
        }
    ]

    function focusedScreen() {
        const screens = Quickshell.screens || [];
        const focusedMonitor = Hyprland.focusedMonitor;

        if (focusedMonitor) {
            for (let i = 0; i < screens.length; ++i) {
                const nextScreen = screens[i];
                if (Hyprland.monitorFor(nextScreen) === focusedMonitor) {
                    return nextScreen;
                }
            }
        }

        return screens.length > 0 ? screens[0] : null;
    }

    function modeIndex(modeId) {
        const resolvedModeId = String(modeId || "");

        for (let i = 0; i < root.modes.length; ++i) {
            if (root.modes[i].id === resolvedModeId) {
                return i;
            }
        }

        return -1;
    }

    function normalizeModeId(modeId) {
        return root.modeIndex(modeId) >= 0 ? String(modeId) : root.defaultModeId;
    }

    function mode(modeId) {
        const index = root.modeIndex(modeId);
        return index >= 0 ? root.modes[index] : root.modes[0];
    }

    function nextModeId(modeId, delta) {
        if (root.modes.length <= 0) {
            return root.defaultModeId;
        }

        const startIndex = Math.max(0, root.modeIndex(modeId));
        const offset = Number(delta) || 0;
        let nextIndex = (startIndex + offset) % root.modes.length;

        if (nextIndex < 0) {
            nextIndex += root.modes.length;
        }

        return root.modes[nextIndex].id;
    }

    readonly property var applications: DesktopEntries.applications.values

    function searchApplications(query, limit) {
        const text = String(query || "").trim().toLowerCase();
        const terms = text.split(/\s+/).filter(term => term.length > 0);
        const matches = [];
        for (const app of root.applications) {
            const name = String(app.name || "");
            const normalizedName = name.toLowerCase();
            const searchable = [name, app.genericName, app.comment, app.id]
                .concat(app.keywords || []).join(" ").toLowerCase();
            if (!terms.every(term => searchable.includes(term))) {
                continue;
            }
            matches.push({
                id: app.id,
                name: name,
                subtitle: String(app.genericName || app.comment || ""),
                rank: !text.length ? 3 : normalizedName === text ? 0
                    : normalizedName.startsWith(text) ? 1 : normalizedName.includes(text) ? 2 : 3
            });
        }
        matches.sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
        return matches.slice(0, Math.max(0, Number(limit) || 24));
    }

    function searchCommand(modeId, query, limit) {
        const modeSpec = root.mode(modeId);
        const commandPrefix = Array.isArray(modeSpec.searchCommandPrefix)
            ? modeSpec.searchCommandPrefix.slice(0)
            : [];

        commandPrefix.push(String(query || ""));
        commandPrefix.push(String(limit || 24));
        return commandPrefix;
    }

    function activateResult(modeId, entry) {
        const modeSpec = root.mode(modeId);
        const entryId = String(entry && entry.id || "");
        const entryName = String(entry && entry.name || entryId);

        if (!entryId.length) {
            return;
        }

        switch (modeSpec.launchType) {
        case "desktop":
            Quickshell.execDetached(["gtk-launch", entryId]);
            break;
        case "ssh":
            Quickshell.execDetached([
                "bash",
                Quickshell.shellPath("scripts/ssh-launcher-connect.sh"),
                entryId,
                entryName
            ]);
            break;
        default:
            break;
        }
    }

    function openWithMode(screen, modeId) {
        root.screen = screen;
        root.openModeId = root.normalizeModeId(modeId);
        root.open = true;
    }

    function toggle(screen, modeId) {
        const requestedModeId = root.normalizeModeId(modeId);

        if (root.open
                && root.screen === screen
                && root.openModeId === requestedModeId) {
            root.close();
            return;
        }

        root.openWithMode(screen, requestedModeId);
    }

    function close() {
        root.open = false;
        root.screen = null;
    }

    readonly property QtObject ipcHandler: IpcHandler {
        target: "launcher"

        function toggleFocused() {
            toggleFocusedMode(root.defaultModeId);
        }

        function toggleFocusedMode(modeId: string) {
            const focused = root.focusedScreen();
            if (!focused) {
                return;
            }

            root.toggle(focused, modeId);
        }

        function toggleSshFocused() {
            toggleFocusedMode("ssh");
        }

        function closeLauncher() {
            root.close();
        }
    }
}
