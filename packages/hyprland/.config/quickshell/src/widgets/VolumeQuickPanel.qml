import QtQuick
import QtQml
import Quickshell
import "../components"
import "../theme"

Item {
    id: root

    property var theme: null
    property int panelWidth: 0
    property var quickControlsController: null
    property QtObject audioService: null
    property var openCommand: ["pavucontrol"]
    property int displayVolumePercent: root.audioService ? root.audioService.volumePercent : 0
    property bool editingSlider: false

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property bool busy: root.audioService ? root.audioService.busy : false
    readonly property bool muted: root.audioService ? root.audioService.muted : false
    readonly property var outputDevices: root.audioService ? root.audioService.outputDevices : []
    readonly property var inputDevices: root.audioService ? root.audioService.inputDevices : []
    readonly property string currentOutputId: root.audioService ? root.audioService.currentOutputId : ""
    readonly property string currentInputId: root.audioService ? root.audioService.currentInputId : ""
    readonly property string currentOutputLabel: root.audioService ? root.audioService.currentOutputLabel : ""
    readonly property string currentInputLabel: root.audioService ? root.audioService.currentInputLabel : ""
    readonly property string statusText: {
        if (!root.audioService) {
            return "";
        }

        return root.audioService.actionMessage.length > 0
            ? root.audioService.actionMessage
            : root.audioService.statusMessage;
    }
    readonly property string statusTone: {
        if (!root.audioService) {
            return "info";
        }

        return root.audioService.actionMessage.length > 0
            ? root.audioService.actionTone
            : root.audioService.statusTone;
    }

    implicitWidth: root.panelWidth > 0 ? root.panelWidth : contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    function commitSetVolume(value) {
        root.editingSlider = false;
        root.displayVolumePercent = Math.max(0, Math.min(100, Math.round(value)));
        if (root.audioService) {
            root.audioService.setVolume(root.displayVolumePercent);
        }
    }

    function deviceIndex(devices, currentId) {
        for (let index = 0; index < devices.length; ++index) {
            if (devices[index] && String(devices[index].id || "") === String(currentId || "")) {
                return index;
            }
        }

        return -1;
    }

    Column {
        id: contentColumn
        width: root.panelWidth > 0 ? root.panelWidth : implicitWidth
        spacing: root.t.innerGapPx + 2

        Row {
            width: parent.width
            spacing: root.t.innerGapPx

            Text {
                width: Math.max(0, parent.width - muteToggle.width - parent.spacing)
                text: "Volume"
                color: root.t.textColor
                font.pixelSize: root.t.textPx + 2
                font.family: root.t.uiFont
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }

            QuickControlHeaderToggle {
                id: muteToggle
                anchors.verticalCenter: parent.verticalCenter
                theme: root.t
                checked: !root.muted
                enabled: !root.busy
                onToggled: {
                    if (root.audioService) {
                        root.audioService.toggleMute();
                    }
                }
            }
        }

        QuickControlSliderRow {
            width: parent.width
            theme: root.t
            title: ""
            subtitle: ""
            from: 0
            to: 100
            stepSize: 1
            value: root.displayVolumePercent
            busy: root.busy
            valueText: root.muted ? "Muted" : (root.displayVolumePercent + "%")
            onValueChanging: {
                root.editingSlider = true;
                root.displayVolumePercent = Math.max(0, Math.min(100, Math.round(value)));
            }
            onValueCommitted: root.commitSetVolume(value)
        }

        Text {
            width: parent.width
            text: root.muted
                ? "Output muted"
                : (root.currentOutputLabel.length > 0 ? root.currentOutputLabel : "Output")
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
        }

        QuickControlStatusBanner {
            width: parent.width
            theme: root.t
            text: root.statusText
            tone: root.statusTone
        }

        QuickControlSectionLabel {
            width: parent.width
            theme: root.t
            text: "Devices"
        }

        QuickControlComboRow {
            width: parent.width
            theme: root.t
            title: "Output Device"
            subtitle: root.outputDevices.length > 1
                ? "Choose where playback goes"
                : (root.outputDevices.length === 1
                    ? "Only one output device is available"
                    : "No output devices detected")
            model: root.outputDevices
            currentIndex: root.deviceIndex(root.outputDevices, root.currentOutputId)
            enabled: !root.busy && root.outputDevices.length > 1
            placeholderText: root.currentOutputLabel.length > 0 ? root.currentOutputLabel : "No output device"
            onActivated: function(index, item) {
                if (item && root.audioService) {
                    root.audioService.setOutputDevice(item.id);
                }
            }
        }

        QuickControlComboRow {
            width: parent.width
            theme: root.t
            title: "Input Device"
            subtitle: root.inputDevices.length > 1
                ? "Choose which microphone or capture source is active"
                : (root.inputDevices.length === 1
                    ? "Only one input device is available"
                    : "No input devices detected")
            model: root.inputDevices
            currentIndex: root.deviceIndex(root.inputDevices, root.currentInputId)
            enabled: !root.busy && root.inputDevices.length > 1
            placeholderText: root.currentInputLabel.length > 0 ? root.currentInputLabel : "No input device"
            onActivated: function(index, item) {
                if (item && root.audioService) {
                    root.audioService.setInputDevice(item.id);
                }
            }
        }

        QuickControlActionRow {
            width: parent.width
            theme: root.t
            title: "Open Mixer"
            subtitle: "Launch pavucontrol for per-app routing and advanced controls"
            trailingText: "Open"
            enabled: !root.busy
            onClicked: {
                if (root.quickControlsController) {
                    root.quickControlsController.close();
                }
                Quickshell.execDetached(root.openCommand);
            }
        }
    }

    Connections {
        target: root.audioService

        function onVolumePercentChanged() {
            if (!root.editingSlider) {
                root.displayVolumePercent = root.audioService.volumePercent;
            }
        }

        function onBusyChanged() {
            if (!root.audioService.busy) {
                root.editingSlider = false;
                root.displayVolumePercent = root.audioService.volumePercent;
            }
        }
    }

    Component.onCompleted: {
        if (!root.audioService) {
            return;
        }
        root.displayVolumePercent = root.audioService.volumePercent;
        root.audioService.refresh();
    }
}
