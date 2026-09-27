import QtQuick
import "../theme"

Rectangle {
    id: root

    property var theme: null
    property bool checked: false
    property bool enabled: true
    signal toggled(bool checked)

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme

    width: 38
    height: 22
    radius: height / 2
    color: root.checked ? root.t.accentColor : root.t.chipColor
    border.width: 1
    border.color: root.checked ? root.t.accentColor : root.t.groupBorder
    opacity: root.enabled ? 1 : 0.55

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Behavior on opacity {
        NumberAnimation { duration: 120 }
    }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        x: root.checked ? (root.width - width - 3) : 3
        anchors.verticalCenter: parent.verticalCenter
        color: root.t.groupColor

        Behavior on x {
            NumberAnimation { duration: 120 }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: enabled
        acceptedButtons: Qt.LeftButton
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled(!root.checked)
    }
}
