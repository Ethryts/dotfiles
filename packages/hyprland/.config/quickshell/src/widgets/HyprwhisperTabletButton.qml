import QtQuick
import "../theme"

Rectangle {
    id: root

    required property QtObject hyprwhisperService
    property var theme: null

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property string state: root.hyprwhisperService
        ? String(root.hyprwhisperService.state || "")
        : "stopped"
    readonly property color accentColor: root.colorForTone(root.hyprwhisperService
        ? String(root.hyprwhisperService.buttonTone || "muted")
        : "muted")
    readonly property string buttonText: {
        const iconText = root.hyprwhisperService
            ? String(root.hyprwhisperService.buttonIcon || "󰍬")
            : "󰍬";
        const labelText = root.hyprwhisperService
            ? String(root.hyprwhisperService.buttonLabel || "Talk")
            : "Talk";
        return iconText + " " + labelText;
    }

    property color backgroundColor: "transparent"
    property color hoverColor: root.t.interactiveHoverColor
    property color pressedColor: root.t.interactivePressedColor
    property color hoverBorderColor: root.t.interactiveBorderColor
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    property int horizontalPadding: 8

    function colorForTone(tone) {
        switch (String(tone || "").trim()) {
        case "success":
            return root.t.successColor;
        case "warning":
            return root.t.warningColor;
        case "error":
            return root.t.errorColor;
        case "accent":
            return root.t.accentColor;
        default:
            return root.t.mutedTextColor;
        }
    }

    radius: root.t.chipRadiusPx
    color: area.pressed ? root.pressedColor : (area.containsMouse ? root.hoverColor : root.backgroundColor)
    border.width: area.containsMouse ? 1 : 0
    border.color: root.hoverBorderColor
    implicitHeight: root.segmentHeightPx
    implicitWidth: textItem.implicitWidth + (root.horizontalPadding * 2)

    Behavior on color {
        ColorAnimation { duration: 100 }
    }

    Text {
        id: textItem
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        text: root.buttonText
        color: root.accentColor
        font.pixelSize: root.textPx
        font.family: root.uiFont
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: !!root.hyprwhisperService && !!root.hyprwhisperService.toggleEnabled
        acceptedButtons: enabled ? Qt.LeftButton : Qt.NoButton
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.hyprwhisperService.toggleRecording()
    }
}
