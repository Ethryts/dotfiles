import QtQuick
import Quickshell
import "../theme"

Rectangle {
    id: root

    required property QtObject overlayHost
    property QtObject networkService: null
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

    property var openCommand: ["nm-connection-editor"]
    readonly property bool quickControlsOpen: !!root.overlayHost
        && root.overlayHost.quickControlOpen("wifi", root)
    readonly property string connectionKind: root.networkService ? root.networkService.connectionKind : "offline"
    readonly property int wifiSignal: root.networkService ? root.networkService.wifiSignal : 0
    readonly property string tooltipText: root.networkService ? root.networkService.tooltipText : "Offline"

    readonly property string iconText: {
        if (root.connectionKind === "ethernet") {
            return "󰈀";
        }

        if (root.connectionKind === "wifi") {
            if (root.wifiSignal >= 80) {
                return "󰤨";
            }
            if (root.wifiSignal >= 60) {
                return "󰤥";
            }
            if (root.wifiSignal >= 40) {
                return "󰤢";
            }
            if (root.wifiSignal >= 20) {
                return "󰤟";
            }
            return "󰤯";
        }

        return "󰤮";
    }
    readonly property color displayColor: root.connectionKind === "offline"
        ? root.t.mutedTextColor
        : root.textColor

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
                root.overlayHost.toggleQuickControl("wifi", root);
                return;
            }

            Quickshell.execDetached(root.openCommand);
        }
        onContainsMouseChanged: {
            if (!root.overlayHost) {
                return;
            }

            if (containsMouse) {
                if (root.networkService) {
                    root.networkService.refreshDetails();
                }
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
