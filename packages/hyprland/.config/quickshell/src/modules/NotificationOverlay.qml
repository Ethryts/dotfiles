import QtQuick
import Quickshell
import "../theme"
import "../widgets"

Scope {
    id: root

    required property QtObject notificationService

    Theme {
        id: overlayTheme
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData

            readonly property var screenNotificationViews: root.notificationService
                ? root.notificationService.activeNotificationViewsForScreen(overlay.modelData)
                : []

            screen: overlay.modelData
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
            visible: screenNotificationViews.length > 0
            mask: Region {
                item: toastColumn
            }

            Column {
                id: toastColumn

                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: overlayTheme.barHeightPx + (overlayTheme.contentMarginPx * 2)
                anchors.rightMargin: overlayTheme.contentMarginPx * 2
                spacing: overlayTheme.notificationGapPx

                Repeater {
                    model: overlay.screenNotificationViews

                    NotificationToast {
                        required property var modelData

                        notificationService: root.notificationService
                        notificationData: modelData
                        theme: overlayTheme
                    }
                }
            }
        }
    }
}
