import QtQuick

QtObject {
    id: root

    property string uiFont: "JetBrainsMono Nerd Font"

    property color groupColor: "#272727"
    property color groupBorder: "#1FFFFFFF"
    property color chipColor: "#1e1e1e"
    property color chipHoverColor: "#252525"
    property color chipPressedColor: "#303030"
    property color chipBorder: "#66666666"
    property color textColor: "#DEFFFFFF"
    property color mutedTextColor: "#a5a5a5"
    property color accentColor: "#8ab4f8"
    property color interactiveHoverColor: "#1a8ab4f8"
    property color interactivePressedColor: "#2e8ab4f8"
    property color interactiveBorderColor: "#4d8ab4f8"
    property color successColor: "#81c995"
    property color warningColor: "#fdd663"
    property color errorColor: "#f28b82"
    property color workspaceActiveFillColor: "#8ab4f8"
    property color workspaceActiveBorderColor: "#8ab4f8"
    property color workspaceActiveTextColor: "#000000"
    property color workspaceVisibleFillColor: "#2f4059"
    property color workspaceVisibleBorderColor: "#6f98d1"
    property color workspaceVisibleTextColor: "#DEFFFFFF"

    property real uiScale: 1.24
    property int textPx: Math.round(11 * uiScale)
    property int barHeightPx: Math.round(38 * uiScale)
    property int moduleHeightPx: Math.round(24 * uiScale)
    property int segmentHeightPx: Math.round(22 * uiScale)
    property int workspaceButtonHeightPx: Math.round(18 * uiScale)
    property int chipRadiusPx: 7
    property int chipBorderWidthPx: 1
    property int chipHorizontalPaddingPx: 1
    property int chipVerticalPaddingPx: 1

    property int contentMarginPx: 4
    property int sectionGapPx: 8
    property int barSectionSpacingPx: 2
    property int innerGapPx: 6
    property int menuPaddingPx: Math.round(12 * uiScale)
    property int menuRadiusPx: Math.round(10 * uiScale)
    property int calendarCellSizePx: Math.round(28 * uiScale)
    property int calendarCellGapPx: Math.round(4 * uiScale)
    property int launcherWidthPx: Math.round(460 * uiScale)
    property int launcherRowHeightPx: Math.round(46 * uiScale)
    property int launcherInputHeightPx: Math.round(34 * uiScale)
    property int overlayWidthPx: Math.round(280 * uiScale)
    property int overlayBottomMarginPx: Math.round(40 * uiScale)
    property int overlayIconSizePx: Math.round(22 * uiScale)
    property int overlayBarHeightPx: Math.max(8, Math.round(10 * uiScale))
    property int tooltipMaxWidthPx: Math.round(220 * uiScale)
    property int tooltipOffsetPx: Math.round(6 * uiScale)
    property int notificationWidthPx: Math.round(340 * uiScale)
    property int notificationImageHeightPx: Math.round(120 * uiScale)
    property int notificationGapPx: Math.round(8 * uiScale)
    property int defaultNotificationTimeoutPx: 5000
    property int notificationStripeWidthPx: Math.round(4 * uiScale)
    property int notificationStripeMarginPx: Math.round(8 * uiScale)
    property int notificationCloseButtonSizePx: Math.round(20 * uiScale)
    property int notificationContentOffsetPx: Math.round(10 * uiScale)
    property int notificationIconSizePx: Math.round(20 * uiScale)
    property int workspaceGapPx: 3
    property int scrollThrottleMs: 120
}
