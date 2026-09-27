import QtQuick
import Quickshell.Services.UPower
import "../theme"

Rectangle {
    id: root

    required property QtObject overlayHost
    property QtObject powerProfilesService: null
    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property color backgroundColor: "transparent"
    property color hoverColor: root.t.interactiveHoverColor
    property color pressedColor: root.t.interactivePressedColor
    property color hoverBorderColor: root.t.interactiveBorderColor
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    property int horizontalPadding: 8
    property color chargingColor: root.t.successColor
    property color warningColor: root.t.warningColor
    property color criticalColor: root.t.errorColor
    property color normalDischargeColor: root.t.accentColor

    readonly property var device: UPower.displayDevice
    readonly property int percentage: {
        if (!root.device || !root.device.ready || !root.device.isPresent) {
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

        // Some runtimes expose this as 0..1 instead of 0..100.
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
    readonly property bool noBattery: !root.device || !root.device.ready || !root.device.isPresent
    readonly property bool pluggedIn: root.charging || !UPower.onBattery
    readonly property int timeToEmptySeconds: root.device ? Number(root.device.timeToEmpty) : -1
    readonly property int timeToFullSeconds: root.device ? Number(root.device.timeToFull) : -1
    readonly property bool quickControlsOpen: !!root.overlayHost
        && root.overlayHost.quickControlOpen("battery", root)
    readonly property string profileText: root.powerProfilesService && root.powerProfilesService.currentProfile.length > 0
        ? root.powerProfilesService.displayName(root.powerProfilesService.currentProfile)
        : ""
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
    readonly property string statusText: {
        if (root.noBattery) {
            return "AC power";
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
    readonly property string tooltipText: {
        const parts = [];

        if (root.noBattery) {
            parts.push("AC power");
        } else {
            parts.push("Battery " + (root.percentage >= 0 ? root.percentage + "%" : "--%"));
            parts.push(root.statusText);
        }

        if (root.profileText.length > 0) {
            parts.push(root.profileText);
        }

        if (root.estimateText.length > 0) {
            parts.push(root.estimateText);
        }

        return parts.join(" • ");
    }
    readonly property string label: {
        if (root.noBattery) {
            return " --%";
        }

        const pct = root.percentage >= 0 ? (root.percentage + "%") : "--%";
        if (root.pluggedIn) {
            return " " + pct;
        }

        let icon = "";
        if (root.percentage >= 90) {
            icon = "";
        } else if (root.percentage >= 70) {
            icon = "";
        } else if (root.percentage >= 45) {
            icon = "";
        } else if (root.percentage >= 20) {
            icon = "";
        }

        return icon + " " + pct;
    }
    readonly property color textColor: {
        if (root.noBattery || root.pluggedIn) {
            return root.chargingColor;
        }

        if (root.percentage >= 0 && root.percentage <= 15) {
            return root.criticalColor;
        }

        if (root.percentage >= 0 && root.percentage <= 30) {
            return root.warningColor;
        }

        return root.normalDischargeColor;
    }

    radius: root.t.chipRadiusPx
    color: root.quickControlsOpen
        ? root.hoverColor
        : (area.pressed ? root.pressedColor : (area.containsMouse ? root.hoverColor : root.backgroundColor))
    border.width: root.quickControlsOpen || area.containsMouse ? 1 : 0
    border.color: root.quickControlsOpen ? root.t.accentColor : root.hoverBorderColor
    implicitHeight: root.segmentHeightPx
    implicitWidth: textItem.implicitWidth + (root.horizontalPadding * 2)

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

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

    Text {
        id: textItem
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.quickControlsOpen ? root.t.accentColor : root.textColor
        font.pixelSize: root.textPx
        font.family: root.uiFont
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.overlayHost) {
                root.overlayHost.toggleQuickControl("battery", root);
            }
        }
        onContainsMouseChanged: {
            if (!root.overlayHost) {
                return;
            }

            root.overlayHost.syncTooltip(root.tooltipText, root, containsMouse, root.quickControlsOpen);
        }
    }

    onQuickControlsOpenChanged: {
        if (root.overlayHost) {
            root.overlayHost.syncTooltip(root.tooltipText, root, area.containsMouse, root.quickControlsOpen);
        }
    }

    onTooltipTextChanged: {
        if (root.overlayHost) {
            root.overlayHost.syncTooltip(root.tooltipText, root, area.containsMouse, root.quickControlsOpen);
        }
    }
}
