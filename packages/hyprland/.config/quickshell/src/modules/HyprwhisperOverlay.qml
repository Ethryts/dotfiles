import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../theme"
import "../widgets"

Scope {
    id: root

    required property QtObject hyprwhisperService

    Theme {
        id: overlayTheme
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlayWindow
            required property var modelData

            readonly property bool focusedScreen: !Hyprland.focusedMonitor
                || Hyprland.monitorFor(overlayWindow.modelData) === Hyprland.focusedMonitor

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
            focusable: false
            color: "transparent"
            visible: !!root.hyprwhisperService
                && !!root.hyprwhisperService.overlayVisible
                && focusedScreen
            mask: Region {
                item: statusBar
            }

            HyprwhisperStatusBar {
                id: statusBar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: overlayTheme.barHeightPx + overlayTheme.contentMarginPx
                hyprwhisperService: root.hyprwhisperService
                theme: overlayTheme
            }
        }
    }
}
