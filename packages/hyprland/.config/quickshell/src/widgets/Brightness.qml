import QtQuick
import "../components"
import "../theme"

Rectangle {
    id: root

    required property QtObject overlayHost
    property QtObject brightnessService: null
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
    property int scrollThrottleMs: root.t.scrollThrottleMs
    readonly property bool quickControlsOpen: !!root.overlayHost
        && root.overlayHost.quickControlOpen("brightness", root)
    readonly property int brightnessPercent: root.brightnessService ? root.brightnessService.brightnessPercent : -1

    readonly property string iconText: {
        if (root.brightnessPercent < 0) {
            return "󰃠";
        }

        if (root.brightnessPercent < 25) {
            return "󰃞";
        }

        if (root.brightnessPercent < 60) {
            return "󰃟";
        }

        return "󰃠";
    }
    readonly property string tooltipText: root.brightnessPercent >= 0
        ? ("Brightness " + root.brightnessPercent + "%")
        : "Brightness unavailable"
    readonly property color displayColor: root.brightnessPercent >= 0
        ? root.textColor
        : root.t.mutedTextColor

    ScrollAccelerator {
        id: scrollAccelerator
        baseIntervalMs: root.scrollThrottleMs
        onStep: function(direction) {
            if (!root.brightnessService || root.brightnessPercent < 0) {
                return;
            }

            root.brightnessService.setBrightness(
                Math.max(1, Math.min(100, root.brightnessPercent + direction))
            );
        }
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
                root.overlayHost.toggleQuickControl("brightness", root);
            }
        }
        onContainsMouseChanged: {
            if (!root.overlayHost) {
                return;
            }

            root.overlayHost.syncTooltip(root.tooltipText, root, containsMouse, root.quickControlsOpen);
        }
        onWheel: function(wheel) {
            scrollAccelerator.handleWheel(wheel.angleDelta.y);
            wheel.accepted = true;
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
