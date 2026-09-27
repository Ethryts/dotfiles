import QtQuick
import Quickshell
import "../components"
import "../theme"

Rectangle {
    id: root

    required property QtObject overlayHost
    property QtObject audioService: null
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
    property var openMixerCommand: ["pavucontrol"]
    readonly property bool quickControlsOpen: !!root.overlayHost
        && root.overlayHost.quickControlOpen("volume", root)
    readonly property int volumePercent: root.audioService ? root.audioService.volumePercent : 0
    readonly property bool muted: root.audioService ? root.audioService.muted : false

    readonly property string iconText: {
        if (root.muted) {
            return "";
        }

        if (root.volumePercent <= 0) {
            return "";
        }

        if (root.volumePercent < 34) {
            return "";
        }

        if (root.volumePercent < 67) {
            return "";
        }

        return "";
    }
    readonly property string tooltipText: root.muted
        ? "Muted"
        : ("Volume " + root.volumePercent + "%")
    readonly property color displayColor: root.muted
        ? root.t.mutedTextColor
        : root.textColor

    function toggleMute() {
        if (root.audioService) {
            root.audioService.toggleMute();
        }
    }

    ScrollAccelerator {
        id: scrollAccelerator
        baseIntervalMs: root.scrollThrottleMs
        onStep: function(direction) {
            if (!root.audioService) {
                return;
            }

            root.audioService.setVolume(
                Math.max(0, Math.min(100, root.volumePercent + direction))
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) {
                root.toggleMute();
            } else if (root.overlayHost) {
                root.overlayHost.toggleQuickControl("volume", root);
            } else {
                Quickshell.execDetached(root.openMixerCommand);
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
