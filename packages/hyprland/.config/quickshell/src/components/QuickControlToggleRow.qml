import QtQuick
import "../theme"

Rectangle {
    id: root

    property var theme: null
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool enabled: true
    signal toggled(bool checked)

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property color fillColor: {
        if (!root.enabled) {
            return "transparent";
        }

        if (rowArea.pressed) {
            return root.t.interactivePressedColor;
        }

        if (rowArea.containsMouse) {
            return root.t.interactiveHoverColor;
        }

        return "transparent";
    }

    radius: Math.max(6, root.t.chipRadiusPx - 1)
    color: root.fillColor
    implicitWidth: parent ? parent.width : contentRow.implicitWidth
    implicitHeight: Math.max(root.t.segmentHeightPx + 10, titleText.implicitHeight + subtitleText.implicitHeight + 14)
    opacity: root.enabled ? 1 : 0.55

    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 120
        }
    }

    Row {
        id: contentRow
        anchors.fill: parent
        anchors.margins: 10
        spacing: root.t.innerGapPx + 6

        Column {
            width: Math.max(0, parent.width - toggleTrack.width - contentRow.spacing)
            anchors.verticalCenter: parent.verticalCenter
            spacing: subtitleText.visible ? 2 : 0

            Text {
                id: titleText
                width: parent.width
                text: root.title
                color: root.t.textColor
                font.pixelSize: root.t.textPx
                font.family: root.t.uiFont
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                id: subtitleText
                width: parent.width
                visible: text.length > 0
                text: root.subtitle
                color: root.t.mutedTextColor
                font.pixelSize: Math.max(11, root.t.textPx - 1)
                font.family: root.t.uiFont
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: toggleTrack
            width: 38
            height: 22
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.checked ? root.t.accentColor : root.t.chipColor
            border.width: 1
            border.color: root.checked ? root.t.accentColor : root.t.groupBorder

            Rectangle {
                width: 16
                height: 16
                radius: 8
                x: root.checked ? toggleTrack.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                color: root.t.groupColor
                Behavior on x { NumberAnimation { duration: 120 } }
            }
        }
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: root.enabled
        acceptedButtons: Qt.LeftButton
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled(!root.checked)
    }
}
