import QtQuick
import "../theme"

Rectangle {
    id: root

    required property QtObject overlayHost

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property color textColor: root.t.accentColor
    property color backgroundColor: "transparent"
    property color hoverColor: root.t.interactiveHoverColor
    property color pressedColor: root.t.interactivePressedColor
    property color hoverBorderColor: root.t.interactiveBorderColor
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    property int horizontalPadding: 8
    property string labelText: "Apps"

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
        text: root.labelText
        color: root.textColor
        font.pixelSize: root.textPx
        font.family: root.uiFont
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.overlayHost.toggleLauncher()
    }
}
