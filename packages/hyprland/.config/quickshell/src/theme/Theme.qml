import QtQuick
import "../services"

QtObject {
    id: root

    readonly property string uiFont: ThemeService.uiFont

    readonly property color groupColor: ThemeService.groupColor
    readonly property color groupBorder: ThemeService.groupBorder
    readonly property color chipColor: ThemeService.chipColor
    readonly property color chipHoverColor: ThemeService.chipHoverColor
    readonly property color chipPressedColor: ThemeService.chipPressedColor
    readonly property color chipBorder: ThemeService.chipBorder
    readonly property color textColor: ThemeService.textColor
    readonly property color mutedTextColor: ThemeService.mutedTextColor
    readonly property color accentColor: ThemeService.accentColor
    readonly property color interactiveHoverColor: ThemeService.interactiveHoverColor
    readonly property color interactivePressedColor: ThemeService.interactivePressedColor
    readonly property color interactiveBorderColor: ThemeService.interactiveBorderColor
    readonly property color successColor: ThemeService.successColor
    readonly property color warningColor: ThemeService.warningColor
    readonly property color errorColor: ThemeService.errorColor
    readonly property color workspaceActiveFillColor: ThemeService.workspaceActiveFillColor
    readonly property color workspaceActiveBorderColor: ThemeService.workspaceActiveBorderColor
    readonly property color workspaceActiveTextColor: ThemeService.workspaceActiveTextColor
    readonly property color workspaceVisibleFillColor: ThemeService.workspaceVisibleFillColor
    readonly property color workspaceVisibleBorderColor: ThemeService.workspaceVisibleBorderColor
    readonly property color workspaceVisibleTextColor: ThemeService.workspaceVisibleTextColor

    readonly property real uiScale: ThemeService.uiScale
    readonly property int textPx: ThemeService.textPx
    readonly property int barHeightPx: ThemeService.barHeightPx
    readonly property int moduleHeightPx: ThemeService.moduleHeightPx
    readonly property int segmentHeightPx: ThemeService.segmentHeightPx
    readonly property int workspaceButtonHeightPx: ThemeService.workspaceButtonHeightPx
    readonly property int chipRadiusPx: ThemeService.chipRadiusPx
    readonly property int chipBorderWidthPx: ThemeService.chipBorderWidthPx
    readonly property int chipHorizontalPaddingPx: ThemeService.chipHorizontalPaddingPx
    readonly property int chipVerticalPaddingPx: ThemeService.chipVerticalPaddingPx

    readonly property int contentMarginPx: ThemeService.contentMarginPx
    readonly property int sectionGapPx: ThemeService.sectionGapPx
    readonly property int barSectionSpacingPx: ThemeService.barSectionSpacingPx
    readonly property int innerGapPx: ThemeService.innerGapPx
    readonly property int menuPaddingPx: ThemeService.menuPaddingPx
    readonly property int menuRadiusPx: ThemeService.menuRadiusPx
    readonly property int calendarCellSizePx: ThemeService.calendarCellSizePx
    readonly property int calendarCellGapPx: ThemeService.calendarCellGapPx
    readonly property int launcherWidthPx: ThemeService.launcherWidthPx
    readonly property int launcherRowHeightPx: ThemeService.launcherRowHeightPx
    readonly property int launcherInputHeightPx: ThemeService.launcherInputHeightPx
    readonly property int overlayWidthPx: ThemeService.overlayWidthPx
    readonly property int overlayBottomMarginPx: ThemeService.overlayBottomMarginPx
    readonly property int overlayIconSizePx: ThemeService.overlayIconSizePx
    readonly property int overlayBarHeightPx: ThemeService.overlayBarHeightPx
    readonly property int tooltipMaxWidthPx: ThemeService.tooltipMaxWidthPx
    readonly property int tooltipOffsetPx: ThemeService.tooltipOffsetPx
    readonly property int notificationWidthPx: ThemeService.notificationWidthPx
    readonly property int notificationImageHeightPx: ThemeService.notificationImageHeightPx
    readonly property int notificationGapPx: ThemeService.notificationGapPx
    readonly property int defaultNotificationTimeoutPx: ThemeService.defaultNotificationTimeoutPx
    readonly property int notificationStripeWidthPx: ThemeService.notificationStripeWidthPx
    readonly property int notificationStripeMarginPx: ThemeService.notificationStripeMarginPx
    readonly property int notificationCloseButtonSizePx: ThemeService.notificationCloseButtonSizePx
    readonly property int notificationContentOffsetPx: ThemeService.notificationContentOffsetPx
    readonly property int notificationIconSizePx: ThemeService.notificationIconSizePx
    readonly property int workspaceGapPx: ThemeService.workspaceGapPx
    readonly property int scrollThrottleMs: ThemeService.scrollThrottleMs
}
