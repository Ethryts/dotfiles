import QtQuick
import Quickshell
import "../theme"

OverlayWindow {
    id: root

    required property QtObject overlayHost
    property var theme: null

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property QtObject tooltipController: root.overlayHost ? root.overlayHost.tooltipController : null

    controller: root.tooltipController
    screenModel: root.overlayHost ? root.overlayHost.screenModel : null
    placement: "anchored"
    horizontalAlignment: "center"
    clampHorizontally: true
    horizontalMargin: root.t.contentMarginPx
    verticalOffset: root.t.tooltipOffsetPx
    closeOnBackdrop: false
    closeOnEscape: false
    windowFocusable: false
    dimBackdrop: false
    color: "transparent"
    mask: Region {
        item: tooltipBubble
    }

    TooltipBubble {
        id: tooltipBubble

        text: root.tooltipController ? root.tooltipController.text : ""
        theme: root.t
    }
}
