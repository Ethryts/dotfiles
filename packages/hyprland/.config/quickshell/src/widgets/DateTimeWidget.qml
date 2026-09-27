import QtQuick
import Quickshell
import "../theme"

Item {
    id: root

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property int precision: SystemClock.Seconds
    property string format: "h:mm:ss AP  ·  dddd, dd"
    property color textColor: root.t.accentColor
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    readonly property date date: clock.date

    implicitHeight: root.segmentHeightPx
    implicitWidth: textItem.implicitWidth

    SystemClock {
        id: clock
        precision: root.precision
    }

    Text {
        id: textItem
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, root.format)
        color: root.textColor
        font.pixelSize: root.textPx
        font.family: root.uiFont
    }
}
