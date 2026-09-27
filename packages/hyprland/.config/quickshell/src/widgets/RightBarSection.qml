import QtQuick
import "../theme"

Item {
    id: root

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    anchors.right: parent ? parent.right : undefined
    anchors.rightMargin: root.edgeMarginPx
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    property int sectionHeightPx: root.t.moduleHeightPx
    property int edgeMarginPx: root.t.contentMarginPx
    property alias moduleHeightPx: root.sectionHeightPx
    property alias spacingPx: contentRow.spacing
    property alias contentSpacingPx: contentRow.spacing

    default property alias content: contentRow.data
    property alias contentData: contentRow.data
    readonly property alias contentItem: contentRow

    implicitHeight: root.sectionHeightPx
    implicitWidth: contentRow.implicitWidth

    Row {
        id: contentRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.t.barSectionSpacingPx
    }
}
