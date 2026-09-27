import QtQuick
import Quickshell.Bluetooth
import "../theme"

Rectangle {
    id: root

    required property QtObject overlayHost
    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property color textColor: root.t.textColor
    property color backgroundColor: "transparent"
    property color hoverColor: root.t.interactiveHoverColor
    property color pressedColor: root.t.interactivePressedColor
    property color hoverBorderColor: root.t.interactiveBorderColor
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    property int horizontalPadding: 8

    property var openCommand: ["blueman-manager"]

    readonly property bool adapterEnabled: {
        const adapter = Bluetooth.defaultAdapter;
        return !!adapter && !!adapter.enabled;
    }
    readonly property bool hasConnectedDevice: {
        if (!root.adapterEnabled) {
            return false;
        }

        const devices = Bluetooth.devices.values || [];
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            if (device.connected) {
                return true;
            }
        }

        return false;
    }
    readonly property string iconText: {
        if (!root.adapterEnabled) {
            return "󰂲";
        }

        return root.hasConnectedDevice ? "󰂱" : "󰂯";
    }
    readonly property color displayColor: root.adapterEnabled
        ? root.textColor
        : root.t.mutedTextColor
    readonly property bool quickControlsOpen: !!root.overlayHost
        && root.overlayHost.quickControlOpen("bluetooth", root)
    readonly property string tooltipText: {
        if (!root.adapterEnabled) {
            return "Bluetooth off";
        }

        const connectedNames = [];
        const devices = Bluetooth.devices.values || [];

        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            if (device.connected) {
                connectedNames.push(device.name || device.deviceName || "Connected device");
            }
        }

        if (connectedNames.length > 0) {
            return connectedNames.join(", ");
        }

        return "Bluetooth on";
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

    Text {
        id: textItem
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        text: root.iconText
        color: root.quickControlsOpen ? root.t.accentColor : root.displayColor
        font.pixelSize: root.textPx
        font.family: root.uiFont
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.overlayHost) {
                root.overlayHost.toggleQuickControl("bluetooth", root);
                return;
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
