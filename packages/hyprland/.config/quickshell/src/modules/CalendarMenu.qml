import QtQuick
import Quickshell
import "../components"
import "../theme"
import "../widgets"

Scope {
    id: root

    required property QtObject calendarController
    property string popupAlignment: "center"

    Theme {
        id: menuTheme
    }

    Variants {
        model: Quickshell.screens

        OverlayWindow {
            id: overlay
            required property var modelData

            controller: root.calendarController
            screenModel: overlay.modelData
            placement: "anchored"
            horizontalAlignment: root.popupAlignment
            verticalOffset: menuTheme.contentMarginPx

            Surface {
                id: calendarFrame

                theme: menuTheme
                padding: menuTheme.menuPaddingPx

                CalendarWidget {
                    id: calendarWidget
                    theme: menuTheme
                }
            }
        }
    }
}
