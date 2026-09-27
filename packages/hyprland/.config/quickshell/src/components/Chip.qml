import QtQuick
import "../theme"

Rectangle {
    id: root

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property color backgroundColor: root.t.groupColor
    property color borderColor: root.t.groupBorder
    property int borderWidth: root.t.chipBorderWidthPx
    property color hoverColor: root.t.chipHoverColor
    property color pressedColor: root.t.chipPressedColor
    property bool interactive: false
    property int acceptedButtons: Qt.LeftButton
    property int horizontalPadding: root.t.chipHorizontalPaddingPx
    property int verticalPadding: root.t.chipVerticalPaddingPx

    signal clicked(var mouse)
    signal scrolled(real deltaY)

    default property alias content: contentItem.data
    property alias contentData: contentItem.data
    readonly property alias contentItemRef: contentItem

    radius: root.t.chipRadiusPx
    clip: true
    color: area.pressed
        ? root.pressedColor
        : (area.containsMouse && root.interactive ? root.hoverColor : root.backgroundColor)
    border.width: root.borderWidth
    border.color: root.borderColor
    implicitHeight: Math.max(root.t.segmentHeightPx, contentItem.childrenRect.height + (root.verticalPadding * 2))
    implicitWidth: contentItem.childrenRect.width + (root.horizontalPadding * 2)

    Behavior on color {
        ColorAnimation { duration: 100 }
    }

    Item {
        id: contentItem
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }

    MouseArea {
        id: area
        enabled: root.interactive
        anchors.fill: parent
        hoverEnabled: root.interactive
        acceptedButtons: root.interactive ? root.acceptedButtons : Qt.NoButton
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: function(mouse) {
            root.clicked(mouse);
        }
        onWheel: function(wheel) {
            if (!root.interactive) {
                return;
            }

            root.scrolled(wheel.angleDelta.y);
            wheel.accepted = true;
        }
    }
}
