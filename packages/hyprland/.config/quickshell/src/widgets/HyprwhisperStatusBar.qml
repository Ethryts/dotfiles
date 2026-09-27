import QtQuick
import "../theme"

Rectangle {
    id: root

    required property QtObject hyprwhisperService
    property var theme: null

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property string state: root.hyprwhisperService
        ? String(root.hyprwhisperService.state || "")
        : "stopped"
    readonly property color toneColor: root.colorForTone(root.hyprwhisperService
        ? String(root.hyprwhisperService.tone || "accent")
        : "accent")
    readonly property real progressRatio: root.clamp((root.hyprwhisperService
        ? root.numberValue(root.hyprwhisperService.progress, 0)
        : 0) / 100, 0, 1)
    readonly property bool indeterminate: !!root.hyprwhisperService && !!root.hyprwhisperService.indeterminate
    readonly property string iconText: {
        switch (root.state) {
        case "recording":
            return "";
        case "processing":
            return "󱎫";
        case "paused":
            return "󰐊";
        case "success":
            return "󰄬";
        case "error":
            return "󰀦";
        default:
            return "󰍬";
        }
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function numberValue(value, fallbackValue) {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : fallbackValue;
    }

    function colorForTone(tone) {
        switch (String(tone || "").trim()) {
        case "success":
            return root.t.successColor;
        case "warning":
            return root.t.warningColor;
        case "error":
            return root.t.errorColor;
        default:
            return root.t.accentColor;
        }
    }

    width: Math.max(272, contentColumn.implicitWidth + (root.t.menuPaddingPx * 2))
    height: contentColumn.implicitHeight + (root.t.menuPaddingPx * 2)
    radius: root.t.menuRadiusPx
    color: root.t.groupColor
    border.width: root.t.chipBorderWidthPx
    border.color: Qt.rgba(root.toneColor.r, root.toneColor.g, root.toneColor.b, 0.75)
    opacity: root.hyprwhisperService && root.hyprwhisperService.overlayVisible ? 1 : 0
    scale: root.hyprwhisperService && root.hyprwhisperService.overlayVisible ? 1 : 0.97

    Behavior on opacity {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Column {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: root.t.menuPaddingPx
        spacing: root.t.innerGapPx

        Row {
            width: parent.width
            spacing: root.t.innerGapPx

            Text {
                id: iconLabel
                text: root.iconText
                color: root.toneColor
                font.pixelSize: root.t.textPx + 4
                font.family: root.t.uiFont
                verticalAlignment: Text.AlignVCenter
            }

            Column {
                width: Math.max(0, parent.width - iconLabel.implicitWidth - parent.spacing)
                spacing: 2

                Text {
                    width: parent.width
                    text: root.hyprwhisperService
                        ? String(root.hyprwhisperService.label || "Voice Typing")
                        : "Voice Typing"
                    color: root.t.textColor
                    font.pixelSize: root.t.textPx + 1
                    font.family: root.t.uiFont
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.hyprwhisperService
                        ? String(root.hyprwhisperService.detail || "")
                        : ""
                    color: root.t.mutedTextColor
                    font.pixelSize: root.t.textPx - 1
                    font.family: root.t.uiFont
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            id: track
            width: parent.width
            height: Math.max(6, root.t.overlayBarHeightPx)
            radius: Math.round(height / 2)
            color: root.t.chipColor
            border.width: 1
            border.color: root.t.chipBorder
            clip: true

            Rectangle {
                visible: !root.indeterminate
                width: track.width * root.progressRatio
                height: parent.height
                radius: parent.radius
                color: root.toneColor

                Behavior on width {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Rectangle {
                id: indeterminateBar
                visible: root.indeterminate
                width: parent.width * 0.32
                height: parent.height
                radius: parent.radius
                color: root.toneColor
                x: -width
            }
        }
    }

    SequentialAnimation {
        running: root.indeterminate && root.opacity > 0
        loops: Animation.Infinite

        NumberAnimation {
            target: indeterminateBar
            property: "x"
            from: -indeterminateBar.width
            to: track.width
            duration: 900
            easing.type: Easing.InOutQuad
        }
    }
}
