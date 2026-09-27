import QtQuick
import QtQml
import "../components"
import "../theme"

Item {
    id: root

    property var theme: null
    property int panelWidth: 0
    property QtObject brightnessService: null
    property int displayBrightnessPercent: root.brightnessService ? root.brightnessService.brightnessPercent : -1
    property bool editingSlider: false

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property bool busy: root.brightnessService ? root.brightnessService.busy : false
    readonly property bool available: root.brightnessService ? root.brightnessService.available : false

    implicitWidth: root.panelWidth > 0 ? root.panelWidth : contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    function commitBrightness(value) {
        root.editingSlider = false;
        root.displayBrightnessPercent = Math.max(1, Math.min(100, Math.round(value)));
        if (root.brightnessService) {
            root.brightnessService.setBrightness(root.displayBrightnessPercent);
        }
    }

    Column {
        id: contentColumn
        width: root.panelWidth > 0 ? root.panelWidth : implicitWidth
        spacing: root.t.innerGapPx + 2

        QuickControlSliderRow {
            width: parent.width
            theme: root.t
            title: "Brightness"
            subtitle: ""
            from: 1
            to: 100
            stepSize: 1
            value: root.displayBrightnessPercent > 0 ? root.displayBrightnessPercent : 1
            busy: root.busy
            enabled: root.available
            valueText: root.available ? (root.displayBrightnessPercent + "%") : "--"
            onValueChanging: {
                root.editingSlider = true;
                root.displayBrightnessPercent = Math.max(1, Math.min(100, Math.round(value)));
            }
            onValueCommitted: root.commitBrightness(value)
        }
    }

    Connections {
        target: root.brightnessService

        function onBrightnessPercentChanged() {
            if (!root.editingSlider) {
                root.displayBrightnessPercent = root.brightnessService.brightnessPercent;
            }
        }

        function onBusyChanged() {
            if (!root.brightnessService.busy) {
                root.editingSlider = false;
                root.displayBrightnessPercent = root.brightnessService.brightnessPercent;
            }
        }
    }

    Component.onCompleted: {
        if (!root.brightnessService) {
            return;
        }
        root.displayBrightnessPercent = root.brightnessService.brightnessPercent;
        root.brightnessService.refresh();
    }
}
