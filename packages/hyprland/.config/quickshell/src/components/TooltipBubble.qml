import QtQuick

Surface {
    id: root

    required property string text
    horizontalPadding: root.t.menuPaddingPx
    verticalPadding: root.t.chipVerticalPaddingPx + Math.round(root.t.innerGapPx / 2)
    implicitWidth: Math.min(root.t.tooltipMaxWidthPx, tooltipText.implicitWidth + (root.t.menuPaddingPx * 2))
    implicitHeight: tooltipText.implicitHeight + (root.verticalPadding * 2)

    Text {
        id: tooltipText

        anchors.fill: parent
        text: root.text
        color: root.t.textColor
        font.pixelSize: root.t.textPx
        font.family: root.t.uiFont
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
    }
}
