pragma Singleton

import QtQuick
import Quickshell.Io
import "../theme"

QtObject {
    id: root

    property string gtkThemeName: "Materia-dark-compact"
    readonly property bool isMateriaDarkCompact: root.gtkThemeName === "Materia-dark-compact"
        || root.gtkThemeName === "Materia-dark"
        || root.gtkThemeName.indexOf("Materia-dark") === 0
    readonly property string resolvedThemeName: root.isMateriaDarkCompact ? "Materia-dark-compact" : "Materia-dark-compact"
    readonly property QtObject materiaDarkCompact: MateriaDarkCompactTheme {}
    readonly property QtObject activePalette: materiaDarkCompact

    readonly property string uiFont: activePalette.uiFont
    readonly property color groupColor: activePalette.groupColor
    readonly property color groupBorder: activePalette.groupBorder
    readonly property color chipColor: activePalette.chipColor
    readonly property color chipHoverColor: activePalette.chipHoverColor
    readonly property color chipPressedColor: activePalette.chipPressedColor
    readonly property color chipBorder: activePalette.chipBorder
    readonly property color textColor: activePalette.textColor
    readonly property color mutedTextColor: activePalette.mutedTextColor
    readonly property color accentColor: activePalette.accentColor
    readonly property color interactiveHoverColor: activePalette.interactiveHoverColor
    readonly property color interactivePressedColor: activePalette.interactivePressedColor
    readonly property color interactiveBorderColor: activePalette.interactiveBorderColor
    readonly property color successColor: activePalette.successColor
    readonly property color warningColor: activePalette.warningColor
    readonly property color errorColor: activePalette.errorColor
    readonly property color workspaceActiveFillColor: activePalette.workspaceActiveFillColor
    readonly property color workspaceActiveBorderColor: activePalette.workspaceActiveBorderColor
    readonly property color workspaceActiveTextColor: activePalette.workspaceActiveTextColor
    readonly property color workspaceVisibleFillColor: activePalette.workspaceVisibleFillColor
    readonly property color workspaceVisibleBorderColor: activePalette.workspaceVisibleBorderColor
    readonly property color workspaceVisibleTextColor: activePalette.workspaceVisibleTextColor

    readonly property real uiScale: activePalette.uiScale
    readonly property int textPx: activePalette.textPx
    readonly property int barHeightPx: activePalette.barHeightPx
    readonly property int moduleHeightPx: activePalette.moduleHeightPx
    readonly property int segmentHeightPx: activePalette.segmentHeightPx
    readonly property int workspaceButtonHeightPx: activePalette.workspaceButtonHeightPx
    readonly property int chipRadiusPx: activePalette.chipRadiusPx
    readonly property int chipBorderWidthPx: activePalette.chipBorderWidthPx
    readonly property int chipHorizontalPaddingPx: activePalette.chipHorizontalPaddingPx
    readonly property int chipVerticalPaddingPx: activePalette.chipVerticalPaddingPx
    readonly property int contentMarginPx: activePalette.contentMarginPx
    readonly property int sectionGapPx: activePalette.sectionGapPx
    readonly property int barSectionSpacingPx: activePalette.barSectionSpacingPx
    readonly property int innerGapPx: activePalette.innerGapPx
    readonly property int menuPaddingPx: activePalette.menuPaddingPx
    readonly property int menuRadiusPx: activePalette.menuRadiusPx
    readonly property int calendarCellSizePx: activePalette.calendarCellSizePx
    readonly property int calendarCellGapPx: activePalette.calendarCellGapPx
    readonly property int launcherWidthPx: activePalette.launcherWidthPx
    readonly property int launcherRowHeightPx: activePalette.launcherRowHeightPx
    readonly property int launcherInputHeightPx: activePalette.launcherInputHeightPx
    readonly property int overlayWidthPx: activePalette.overlayWidthPx
    readonly property int overlayBottomMarginPx: activePalette.overlayBottomMarginPx
    readonly property int overlayIconSizePx: activePalette.overlayIconSizePx
    readonly property int overlayBarHeightPx: activePalette.overlayBarHeightPx
    readonly property int tooltipMaxWidthPx: activePalette.tooltipMaxWidthPx
    readonly property int tooltipOffsetPx: activePalette.tooltipOffsetPx
    readonly property int notificationWidthPx: activePalette.notificationWidthPx
    readonly property int notificationImageHeightPx: activePalette.notificationImageHeightPx
    readonly property int notificationGapPx: activePalette.notificationGapPx
    readonly property int defaultNotificationTimeoutPx: activePalette.defaultNotificationTimeoutPx
    readonly property int notificationStripeWidthPx: activePalette.notificationStripeWidthPx
    readonly property int notificationStripeMarginPx: activePalette.notificationStripeMarginPx
    readonly property int notificationCloseButtonSizePx: activePalette.notificationCloseButtonSizePx
    readonly property int notificationContentOffsetPx: activePalette.notificationContentOffsetPx
    readonly property int notificationIconSizePx: activePalette.notificationIconSizePx
    readonly property int workspaceGapPx: activePalette.workspaceGapPx
    readonly property int scrollThrottleMs: activePalette.scrollThrottleMs

    function parseThemeName(raw) {
        const line = String(raw || "").trim().replace(/^'+|'+$/g, "");
        if (line.length > 0) {
            root.gtkThemeName = line;
        }
    }

    readonly property QtObject themeProcess: Process {
        command: [
            "bash",
            "-lc",
            "theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d \"'\"); " +
            "if [ -z \"$theme\" ] && [ -f \"$HOME/.config/gtk-3.0/settings.ini\" ]; then " +
            "theme=$(sed -n 's/^gtk-theme-name=//p' \"$HOME/.config/gtk-3.0/settings.ini\" | head -n 1); " +
            "fi; printf '%s\\n' \"$theme\""
        ]
        running: true
        stdout: StdioCollector {
            id: themeStdout
            waitForEnd: true
        }
        onExited: root.parseThemeName(themeStdout.text)
    }
}
