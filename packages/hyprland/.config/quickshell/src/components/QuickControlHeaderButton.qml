import QtQuick
import "../theme"

Rectangle {
    id: root

    property var theme: null
    property string text: ""
    property bool enabled: true
    signal clicked()

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property color fillColor: {
        if (!root.enabled) {
            return "transparent";
        }

        if (buttonArea.pressed) {
            return root.t.interactivePressedColor;
        }

        if (buttonArea.containsMouse) {
            return root.t.interactiveHoverColor;
        }

        return "transparent";
    }

    radius: Math.max(6, root.t.chipRadiusPx - 1)
    color: root.fillColor
    border.width: 1
    border.color: root.enabled ? root.t.interactiveBorderColor : root.t.groupBorder
    implicitWidth: label.implicitWidth + 18
    implicitHeight: Math.max(root.t.segmentHeightPx - 6, label.implicitHeight + 10)
    opacity: root.enabled ? 1 : 0.55

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Behavior on opacity {
        NumberAnimation { duration: 120 }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.enabled ? root.t.textColor : root.t.mutedTextColor
        font.pixelSize: Math.max(11, root.t.textPx - 1)
        font.family: root.t.uiFont
        font.bold: true
    }

    MouseArea {
        id: buttonArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: enabled
        acceptedButtons: Qt.LeftButton
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
