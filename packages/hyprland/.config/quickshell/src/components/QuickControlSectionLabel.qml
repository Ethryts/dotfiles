import QtQuick
import "../theme"

Text {
    id: root

    property var theme: null

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme

    color: root.t.mutedTextColor
    font.pixelSize: Math.max(11, root.t.textPx - 1)
    font.family: root.t.uiFont
    font.bold: true
}
