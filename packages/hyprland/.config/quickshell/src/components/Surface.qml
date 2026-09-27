import QtQuick
import "../theme"

Rectangle {
    id: root

    property var theme: null
    property string variant: "default"
    property color backgroundColor: root.t.groupColor
    property color borderColor: root.t.groupBorder
    property int borderWidth: root.t.chipBorderWidthPx
    property int padding: 0
    property int horizontalPadding: -1
    property int verticalPadding: -1

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property int resolvedHorizontalPadding: root.horizontalPadding >= 0
        ? root.horizontalPadding
        : root.padding
    readonly property int resolvedVerticalPadding: root.verticalPadding >= 0
        ? root.verticalPadding
        : root.padding
    readonly property int contentWidth: Math.max(0, root.width - (root.resolvedHorizontalPadding * 2))

    default property alias content: contentItem.data
    property alias contentData: contentItem.data
    readonly property alias contentItemRef: contentItem

    radius: root.t.menuRadiusPx
    color: root.backgroundColor
    border.width: root.borderWidth
    border.color: root.borderColor
    implicitWidth: contentItem.childrenRect.width + (root.resolvedHorizontalPadding * 2)
    implicitHeight: contentItem.childrenRect.height + (root.resolvedVerticalPadding * 2)

    Item {
        id: contentItem

        anchors.fill: parent
        anchors.leftMargin: root.resolvedHorizontalPadding
        anchors.rightMargin: root.resolvedHorizontalPadding
        anchors.topMargin: root.resolvedVerticalPadding
        anchors.bottomMargin: root.resolvedVerticalPadding
    }
}
