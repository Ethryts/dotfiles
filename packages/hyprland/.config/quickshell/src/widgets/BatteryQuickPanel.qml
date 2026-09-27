import QtQuick
import Quickshell.Services.UPower
import "../components"
import "../theme"

Item {
    id: root

    property var theme: null
    property int panelWidth: 0
    property QtObject powerProfilesService: null

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property var device: UPower.displayDevice
    readonly property bool noBattery: !root.device || !root.device.ready || !root.device.isPresent
    readonly property int percentage: {
        if (root.noBattery) {
            return -1;
        }

        const energy = Number(root.device.energy);
        const capacity = Number(root.device.energyCapacity);
        if (Number.isFinite(energy) && Number.isFinite(capacity) && capacity > 0) {
            let derived = Math.round((energy * 100) / capacity);
            if (derived < 0) derived = 0;
            if (derived > 100) derived = 100;
            return derived;
        }

        let pct = Number(root.device.percentage);
        if (!Number.isFinite(pct)) {
            return -1;
        }

        if (pct > 0 && pct <= 1) {
            pct *= 100;
        }

        let rounded = Math.round(pct);
        if (rounded < 0) rounded = 0;
        if (rounded > 100) rounded = 100;
        return rounded;
    }
    readonly property int state: root.device ? root.device.state : UPowerDeviceState.Unknown
    readonly property bool discharging: root.state === UPowerDeviceState.Discharging
        || root.state === UPowerDeviceState.PendingDischarge
    readonly property bool charging: root.state === UPowerDeviceState.Charging
        || root.state === UPowerDeviceState.PendingCharge
        || root.state === UPowerDeviceState.FullyCharged
    readonly property int timeToEmptySeconds: root.device ? Number(root.device.timeToEmpty) : -1
    readonly property int timeToFullSeconds: root.device ? Number(root.device.timeToFull) : -1
    readonly property string batteryStateText: {
        if (root.noBattery) {
            return "No battery detected";
        }

        if (root.state === UPowerDeviceState.FullyCharged) {
            return "Fully charged";
        }

        if (root.charging) {
            return "Charging";
        }

        if (root.discharging) {
            return "On battery";
        }

        if (!UPower.onBattery) {
            return "Plugged in";
        }

        return "Battery status unavailable";
    }
    readonly property string estimateText: {
        if (root.noBattery) {
            return "";
        }

        if (root.discharging && root.timeToEmptySeconds > 0) {
            return root.formatDuration(root.timeToEmptySeconds) + " left";
        }

        if (root.charging && root.state !== UPowerDeviceState.FullyCharged && root.timeToFullSeconds > 0) {
            return root.formatDuration(root.timeToFullSeconds) + " until full";
        }

        return "";
    }
    readonly property string batterySummary: root.noBattery
        ? root.batteryStateText
        : (root.batteryStateText + " • " + (root.percentage >= 0 ? root.percentage + "%" : "--%"))
    readonly property string currentProfile: root.powerProfilesService ? root.powerProfilesService.currentProfile : ""
    readonly property string currentProfileLabel: root.powerProfilesService
        ? root.powerProfilesService.displayName(root.currentProfile)
        : "Unknown"
    readonly property bool busy: root.powerProfilesService ? root.powerProfilesService.busy : false
    readonly property bool profilesAvailable: root.powerProfilesService ? root.powerProfilesService.available : false
    readonly property var profiles: root.powerProfilesService ? root.powerProfilesService.profiles : []

    implicitWidth: root.panelWidth > 0 ? root.panelWidth : contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    function formatDuration(totalSeconds) {
        const seconds = Math.max(0, Math.round(Number(totalSeconds) || 0));
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        if (hours > 0 && minutes > 0) {
            return hours + "h " + minutes + "m";
        }

        if (hours > 0) {
            return hours + "h";
        }

        return Math.max(1, minutes) + "m";
    }

    function profileSubtitle(profile) {
        const parts = [];

        switch (profile.id) {
        case "performance":
            parts.push("Favor responsiveness over battery life");
            break;
        case "power-saver":
            parts.push("Reduce power usage to extend battery life");
            break;
        default:
            parts.push("Default mix of performance and efficiency");
            break;
        }

        if (profile.degraded) {
            parts.push(profile.degradedReason && profile.degradedReason.length > 0
                ? ("Degraded: " + profile.degradedReason)
                : "Driver reported degraded support");
        }

        return parts.join(" • ");
    }

    Column {
        id: contentColumn
        width: root.panelWidth > 0 ? root.panelWidth : implicitWidth
        spacing: root.t.innerGapPx + 2

        Text {
            width: parent.width
            text: "Power"
            color: root.t.textColor
            font.pixelSize: root.t.textPx + 2
            font.family: root.t.uiFont
            font.bold: true
        }

        Text {
            width: parent.width
            text: root.batterySummary
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            visible: root.estimateText.length > 0
            text: root.estimateText
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            visible: root.currentProfile.length > 0
            text: "Current profile: " + root.currentProfileLabel
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
        }

        QuickControlSectionLabel {
            width: parent.width
            theme: root.t
            visible: root.profiles.length > 0
            text: "Profiles"
        }

        Repeater {
            model: root.profiles

            delegate: QuickControlActionRow {
                required property var modelData
                width: parent.width
                theme: root.t
                title: root.powerProfilesService
                    ? root.powerProfilesService.displayName(modelData.id)
                    : modelData.id
                subtitle: root.profileSubtitle(modelData)
                trailingText: modelData.active ? "Active" : "Use"
                active: modelData.active
                enabled: !root.busy && !modelData.active
                onClicked: {
                    if (root.powerProfilesService) {
                        root.powerProfilesService.setProfile(modelData.id);
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.profiles.length === 0
            text: root.busy
                ? "Loading power profiles…"
                : "No power profiles were reported by power-profile-daemon."
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
        }
    }

    Component.onCompleted: {
        if (root.powerProfilesService) {
            root.powerProfilesService.refresh();
        }
    }

    onVisibleChanged: {
        if (visible && root.powerProfilesService) {
            root.powerProfilesService.refresh();
        }
    }
}
