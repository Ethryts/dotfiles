import QtQuick
import "../theme"

Rectangle {
    id: root

    property var theme: null
    property string text: ""
    property string tone: "info"

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property color toneColor: {
        switch (root.tone) {
        case "success":
            return root.t.successColor;
        case "warning":
            return root.t.warningColor;
        case "error":
            return root.t.errorColor;
        default:
            return root.t.accentColor;
        }
    }

    visible: root.text.length > 0
    radius: Math.max(6, root.t.chipRadiusPx - 1)
    color: Qt.rgba(root.toneColor.r, root.toneColor.g, root.toneColor.b, 0.14)
    border.width: 1
    border.color: Qt.rgba(root.toneColor.r, root.toneColor.g, root.toneColor.b, 0.35)
    implicitWidth: parent ? parent.width : messageText.implicitWidth + 20
    implicitHeight: messageText.implicitHeight + 16
    opacity: visible ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 140
        }
    }

    Text {
        id: messageText
        anchors.fill: parent
        anchors.margins: 8
        text: root.text
        color: root.t.textColor
        font.pixelSize: Math.max(11, root.t.textPx - 1)
        font.family: root.t.uiFont
        wrapMode: Text.Wrap
    }
}
