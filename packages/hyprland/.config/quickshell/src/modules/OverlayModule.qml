import QtQuick
import Quickshell
import "../components"
import "../services"
import "../theme"
import "../widgets"

Scope {
    id: root

    Theme {
        id: overlayTheme
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlayWindow
            required property var modelData

            readonly property bool activeScreen: OverlayService.visible
                && OverlayService.screen === overlayWindow.modelData
                && OverlayService.activeOverlay

            screen: overlayWindow.modelData
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            aboveWindows: true
            color: "transparent"
            visible: activeScreen

            Surface {
                id: popup

                theme: overlayTheme
                padding: overlayTheme.menuPaddingPx
                width: overlayTheme.overlayWidthPx
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: overlayTheme.overlayBottomMarginPx

                SystemOverlayWidget {
                    width: popup.contentWidth
                    overlayData: OverlayService.activeOverlay
                    theme: overlayTheme
                }
            }
        }
    }
}
