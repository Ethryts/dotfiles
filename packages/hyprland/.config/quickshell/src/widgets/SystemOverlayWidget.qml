import QtQuick
import "../theme"

Item {
    id: root

    required property var overlayData
    property var theme: null

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property real minimumValue: root.numberValue(root.overlayData ? root.overlayData.minValue : 0, 0)
    readonly property real maximumValue: root.numberValue(root.overlayData ? root.overlayData.maxValue : 100, 100)
    readonly property real normalizedProgress: {
        const span = root.maximumValue - root.minimumValue;
        if (span <= 0) {
            return 0;
        }

        return root.clamp((root.displayedValue - root.minimumValue) / span, 0, 1);
    }
    readonly property color toneColor: {
        if (!root.overlayData) {
            return root.t.accentColor;
        }

        switch (root.overlayData.tone) {
        case "error":
            return root.t.errorColor;
        case "warning":
            return root.t.warningColor;
        case "success":
            return root.t.successColor;
        default:
            return root.t.accentColor;
        }
    }

    property real displayedValue: 0
    property real pendingValue: 0

    function numberValue(value, fallbackValue) {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : fallbackValue;
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function applyOverlayData() {
        if (!root.overlayData) {
            return;
        }

        const nextValue = root.clamp(root.numberValue(root.overlayData.value, 0), root.minimumValue, root.maximumValue);
        displayedValueBehavior.enabled = false;
        valueAnimationKick.stop();

        if (root.overlayData.hasPreviousValue) {
            root.displayedValue = root.clamp(root.numberValue(root.overlayData.previousValue, nextValue), root.minimumValue, root.maximumValue);
            root.pendingValue = nextValue;
            valueAnimationKick.start();
            return;
        }

        root.pendingValue = nextValue;
        root.displayedValue = nextValue;
    }

    implicitWidth: contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    onOverlayDataChanged: root.applyOverlayData()
    Component.onCompleted: root.applyOverlayData()

    Column {
        id: contentColumn

        width: parent.width
        spacing: root.t.innerGapPx

        Row {
            width: parent.width
            spacing: root.t.innerGapPx

            Text {
                id: iconText

                visible: root.overlayData && String(root.overlayData.iconText || "").length > 0
                text: root.overlayData ? String(root.overlayData.iconText || "") : ""
                color: root.toneColor
                font.pixelSize: root.t.overlayIconSizePx
                font.family: root.t.uiFont
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                width: Math.max(
                    0,
                    parent.width
                    - valueText.implicitWidth
                    - (iconText.visible ? iconText.implicitWidth : 0)
                    - (parent.spacing * (iconText.visible ? 2 : 1))
                )
                text: root.overlayData ? String(root.overlayData.label || "") : ""
                color: root.t.textColor
                font.pixelSize: root.t.textPx + 1
                font.family: root.t.uiFont
                font.bold: true
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                id: valueText

                text: root.overlayData ? String(root.overlayData.valueText || "") : ""
                color: root.t.mutedTextColor
                font.pixelSize: root.t.textPx
                font.family: root.t.uiFont
                verticalAlignment: Text.AlignVCenter
            }
        }

        Rectangle {
            width: parent.width
            height: root.t.overlayBarHeightPx
            radius: Math.round(height / 2)
            visible: root.overlayData ? root.overlayData.showBar : false
            color: root.t.chipColor
            border.width: 1
            border.color: root.t.chipBorder
            clip: true

            Rectangle {
                width: parent.width * root.normalizedProgress
                height: parent.height
                radius: parent.radius
                color: root.toneColor

                Behavior on width {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Timer {
        id: valueAnimationKick
        interval: 0
        repeat: false
        onTriggered: {
            displayedValueBehavior.enabled = true;
            root.displayedValue = root.pendingValue;
        }
    }

    Behavior on displayedValue {
        id: displayedValueBehavior
        enabled: false
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }
}
