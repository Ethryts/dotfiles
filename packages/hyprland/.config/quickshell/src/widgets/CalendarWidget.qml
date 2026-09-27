import QtQuick
import QtQuick.Controls
import Quickshell
import "../theme"

Item {
    id: root

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property date referenceDate: clock.date
    property color textColor: root.t.textColor
    property color mutedTextColor: root.t.mutedTextColor
    property color accentColor: root.t.accentColor
    property color highlightTextColor: root.t.groupColor
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int titlePx: root.t.textPx + 2
    property int cellSizePx: root.t.calendarCellSizePx
    property int cellGapPx: root.t.calendarCellGapPx
    readonly property var locale: Qt.locale()
    readonly property int shownMonth: root.referenceDate.getMonth()
    readonly property int shownYear: root.referenceDate.getFullYear()
    readonly property date today: clock.date

    implicitWidth: contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    function isToday(model) {
        return model.year === root.today.getFullYear()
            && model.month === root.today.getMonth()
            && model.day === root.today.getDate();
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        id: contentColumn
        spacing: root.t.innerGapPx

        Text {
            text: Qt.formatDate(root.referenceDate, "dddd, MMMM d, yyyy")
            color: root.textColor
            font.pixelSize: root.titlePx
            font.family: root.uiFont
            font.bold: true
        }

        Text {
            text: Qt.formatDate(root.referenceDate, "MMMM yyyy")
            color: root.accentColor
            font.pixelSize: root.textPx
            font.family: root.uiFont
        }

        DayOfWeekRow {
            locale: root.locale
            spacing: root.cellGapPx

            delegate: Text {
                width: root.cellSizePx
                horizontalAlignment: Text.AlignHCenter
                color: root.mutedTextColor
                font.pixelSize: root.textPx
                font.family: root.uiFont
                font.bold: true
                text: shortName

                required property string shortName
            }
        }

        MonthGrid {
            month: root.shownMonth
            year: root.shownYear
            locale: root.locale
            spacing: root.cellGapPx

            delegate: Rectangle {
                required property var model

                readonly property bool inCurrentMonth: model.month === root.shownMonth
                readonly property bool todayCell: root.isToday(model)

                width: root.cellSizePx
                height: root.cellSizePx
                radius: Math.max(4, root.t.chipRadiusPx - 1)
                color: todayCell ? root.accentColor : "transparent"
                opacity: inCurrentMonth ? 1 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: parent.model.day
                    color: parent.todayCell ? root.highlightTextColor : root.textColor
                    font.pixelSize: root.textPx
                    font.family: root.uiFont
                }
            }
        }
    }
}
