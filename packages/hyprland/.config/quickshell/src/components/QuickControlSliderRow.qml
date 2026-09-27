import QtQuick
import QtQuick.Controls
import "../theme"

Item {
    id: root

    property var theme: null
    property string title: ""
    property string subtitle: ""
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property real value: 0
    property bool enabled: true
    property bool busy: false
    property string valueText: Math.round(root.value) + "%"
    signal valueChanging(real value)
    signal valueCommitted(real value)

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme

    implicitWidth: parent ? parent.width : 280
    implicitHeight: contentColumn.implicitHeight

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function steppedValue(value) {
        if (root.stepSize <= 0) {
            return value;
        }

        const steps = Math.round((value - root.from) / root.stepSize);
        return root.from + (steps * root.stepSize);
    }

    function valueForMouseX(mouseX) {
        const usableWidth = Math.max(1, slider.availableWidth);
        const relativeX = root.clamp(mouseX - slider.leftPadding, 0, usableWidth);
        const ratio = relativeX / usableWidth;
        const rawValue = root.from + ((root.to - root.from) * ratio);
        return root.clamp(root.steppedValue(rawValue), root.from, root.to);
    }

    Column {
        id: contentColumn
        width: parent.width
        spacing: 8

        Row {
            width: parent.width
            spacing: root.t.innerGapPx

            Column {
                width: Math.max(0, parent.width - valueLabel.implicitWidth - parent.spacing)
                spacing: subtitleLabel.visible ? 2 : 0

                Text {
                    width: parent.width
                    text: root.title
                    color: root.t.textColor
                    font.pixelSize: root.t.textPx
                    font.family: root.t.uiFont
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    id: subtitleLabel
                    width: parent.width
                    visible: text.length > 0
                    text: root.subtitle
                    color: root.t.mutedTextColor
                    font.pixelSize: Math.max(11, root.t.textPx - 1)
                    font.family: root.t.uiFont
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Text {
                id: valueLabel
                anchors.verticalCenter: parent.verticalCenter
                text: root.valueText
                color: root.enabled ? root.t.accentColor : root.t.mutedTextColor
                font.pixelSize: root.t.textPx
                font.family: root.t.uiFont
                font.bold: true
            }
        }

        Slider {
            id: slider
            width: parent.width
            implicitHeight: 28
            height: implicitHeight
            leftPadding: 8
            rightPadding: 8
            topPadding: 6
            bottomPadding: 6
            from: root.from
            to: root.to
            stepSize: root.stepSize
            value: root.value
            enabled: root.enabled && !root.busy
            live: false

            background: Rectangle {
                implicitWidth: 120
                implicitHeight: 6
                x: slider.leftPadding
                y: Math.round((slider.height - height) / 2)
                width: slider.availableWidth
                height: 6
                radius: 3
                color: root.t.chipColor

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: root.t.accentColor
                }
            }

            handle: Rectangle {
                implicitWidth: 16
                implicitHeight: 16
                x: slider.leftPadding + (slider.visualPosition * (slider.availableWidth - width))
                y: Math.round((slider.height - height) / 2)
                width: 16
                height: 16
                radius: 8
                color: slider.pressed ? root.t.accentColor : root.t.groupColor
                border.width: 1
                border.color: root.t.accentColor
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.enabled && !root.busy
                acceptedButtons: Qt.LeftButton
                hoverEnabled: enabled
                preventStealing: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                onPressed: function(mouse) {
                    const nextValue = root.valueForMouseX(mouse.x);
                    slider.value = nextValue;
                    root.valueChanging(nextValue);
                    mouse.accepted = true;
                }

                onPositionChanged: function(mouse) {
                    if (!pressed) {
                        return;
                    }

                    const nextValue = root.valueForMouseX(mouse.x);
                    slider.value = nextValue;
                    root.valueChanging(nextValue);
                }

                onReleased: function(mouse) {
                    const nextValue = root.valueForMouseX(mouse.x);
                    slider.value = nextValue;
                    root.valueChanging(nextValue);
                    root.valueCommitted(nextValue);
                }
            }
        }
    }
}
