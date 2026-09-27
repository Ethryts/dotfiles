import QtQuick
import "../theme"

Rectangle {
    id: root

    property var theme: null
    property string title: ""
    property string subtitle: ""
    property string trailingText: ""
    property bool active: false
    property bool enabled: true
    signal clicked()

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

        return root.active ? root.t.chipColor : "transparent";
    }

    radius: Math.max(6, root.t.chipRadiusPx - 1)
    color: root.fillColor
    border.width: root.active ? 1 : 0
    border.color: root.t.interactiveBorderColor
    implicitWidth: parent ? parent.width : contentRow.implicitWidth
    implicitHeight: Math.max(
        root.t.segmentHeightPx + 8,
        titleText.implicitHeight + subtitleText.implicitHeight + 12
    )
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
        spacing: root.t.innerGapPx + 4

        Column {
            width: trailingLabel.visible
                ? Math.max(0, parent.width - trailingLabel.implicitWidth - contentRow.spacing)
                : parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: subtitleText.visible ? 2 : 0

            Text {
                id: titleText
                width: parent.width
                text: root.title
                color: root.t.textColor
                font.pixelSize: root.t.textPx
                font.family: root.t.uiFont
                font.bold: root.active
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

        Text {
            id: trailingLabel
            visible: text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.trailingText
            color: root.active ? root.t.accentColor : root.t.mutedTextColor
            font.pixelSize: Math.max(11, root.t.textPx - 1)
            font.family: root.t.uiFont
            font.bold: root.active
        }
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: root.enabled
        acceptedButtons: Qt.LeftButton
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
