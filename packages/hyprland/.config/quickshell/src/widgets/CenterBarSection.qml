import QtQuick
import "../theme"

Item {
    id: root

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    anchors.centerIn: parent

    property int sectionHeightPx: root.t.moduleHeightPx
    property alias moduleHeightPx: root.sectionHeightPx

    default property alias content: centeredContent.data
    property alias contentData: centeredContent.data
    readonly property alias contentItem: centeredContent

    implicitHeight: root.sectionHeightPx
    implicitWidth: centeredContent.childrenRect.width

    Item {
        id: centeredContent
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }
}
