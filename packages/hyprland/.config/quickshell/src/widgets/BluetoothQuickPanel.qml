import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../components"
import "../theme"

Item {
    id: root

    property var theme: null
    property int panelWidth: 0
    property var quickControlsController: null
    property var openCommand: ["blueman-manager"]

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property int connectedCount: {
        let count = 0;
        const devices = root.knownDevices || [];
        for (let index = 0; index < devices.length; ++index) {
            if (devices[index] && devices[index].connected) {
                count += 1;
            }
        }
        return count;
    }
    readonly property string adapterStatusText: {
        if (!root.adapter) {
            return "No Bluetooth adapter detected";
        }

        switch (root.adapter.state) {
        case BluetoothAdapterState.Enabling:
            return "Turning Bluetooth on…";
        case BluetoothAdapterState.Disabling:
            return "Turning Bluetooth off…";
        case BluetoothAdapterState.Blocked:
            return "Bluetooth is blocked by the system";
        default:
            return "";
        }
    }
    readonly property string adapterStatusTone: root.adapter && root.adapter.state === BluetoothAdapterState.Blocked
        ? "error"
        : "info"
    readonly property bool adapterBusy: !!root.adapter
        && (root.adapter.state === BluetoothAdapterState.Enabling
            || root.adapter.state === BluetoothAdapterState.Disabling)
    readonly property string headerSummary: {
        if (!root.adapter) {
            return "No Bluetooth adapter";
        }

        if (!root.adapter.enabled) {
            return "Bluetooth off";
        }

        if (root.connectedCount > 0) {
            return root.connectedCount + " connected";
        }

        if (root.knownDevices.length > 0) {
            return root.knownDevices.length + " saved devices";
        }

        return "No saved devices";
    }
    readonly property var knownDevices: {
        const source = Bluetooth.devices.values || [];
        const filtered = [];

        for (let index = 0; index < source.length; ++index) {
            const device = source[index];
            if (device && (device.connected || device.paired || device.bonded)) {
                filtered.push(device);
            }
        }

        filtered.sort(function(left, right) {
            const leftConnected = left && left.connected ? 1 : 0;
            const rightConnected = right && right.connected ? 1 : 0;
            if (leftConnected !== rightConnected) {
                return rightConnected - leftConnected;
            }

            const leftName = root.deviceName(left).toLowerCase();
            const rightName = root.deviceName(right).toLowerCase();
            return leftName.localeCompare(rightName);
        });

        return filtered;
    }

    implicitWidth: root.panelWidth > 0 ? root.panelWidth : contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    function deviceName(device) {
        if (!device) {
            return "Unknown device";
        }

        return device.name || device.deviceName || device.address || "Unknown device";
    }

    function deviceSubtitle(device) {
        if (!device) {
            return "";
        }

        const parts = [];

        switch (device.state) {
        case BluetoothDeviceState.Connecting:
            parts.push("Connecting");
            break;
        case BluetoothDeviceState.Disconnecting:
            parts.push("Disconnecting");
            break;
        case BluetoothDeviceState.Connected:
            parts.push("Connected");
            break;
        default:
            parts.push(device.paired || device.bonded ? "Paired" : "Available");
            break;
        }

        if (device.batteryAvailable) {
            parts.push(Math.round(device.battery) + "% battery");
        }

        return parts.join(" • ");
    }

    function connectDevice(device) {
        if (!device || !root.adapter || !root.adapter.enabled) {
            return;
        }

        device.connected = !device.connected;
    }

    Column {
        id: contentColumn
        width: root.panelWidth > 0 ? root.panelWidth : implicitWidth
        spacing: root.t.innerGapPx + 2

        Row {
            width: parent.width
            spacing: root.t.innerGapPx

            Text {
                width: Math.max(0, parent.width - bluetoothToggle.width - parent.spacing)
                text: "Bluetooth"
                color: root.t.textColor
                font.pixelSize: root.t.textPx + 2
                font.family: root.t.uiFont
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }

            QuickControlHeaderToggle {
                id: bluetoothToggle
                anchors.verticalCenter: parent.verticalCenter
                theme: root.t
                checked: !!root.adapter && !!root.adapter.enabled
                enabled: !!root.adapter && !root.adapterBusy
                onToggled: function(checked) {
                    if (root.adapter) {
                        root.adapter.enabled = checked;
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: root.headerSummary
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
        }

        QuickControlStatusBanner {
            width: parent.width
            theme: root.t
            text: root.adapterStatusText
            tone: root.adapterStatusTone
        }

        QuickControlSectionLabel {
            width: parent.width
            theme: root.t
            visible: !!root.adapter && root.adapter.enabled && root.knownDevices.length > 0
            text: "Devices"
        }

        Repeater {
            model: !!root.adapter && root.adapter.enabled ? root.knownDevices : []

            delegate: QuickControlActionRow {
                required property var modelData
                width: parent.width
                theme: root.t
                title: root.deviceName(modelData)
                subtitle: root.deviceSubtitle(modelData)
                trailingText: modelData.connected ? "Disconnect" : "Connect"
                active: modelData.connected
                enabled: !!root.adapter
                    && root.adapter.enabled
                    && modelData.state !== BluetoothDeviceState.Connecting
                    && modelData.state !== BluetoothDeviceState.Disconnecting
                onClicked: root.connectDevice(modelData)
            }
        }

        Text {
            width: parent.width
            visible: !!root.adapter && root.adapter.enabled && root.knownDevices.length === 0
            text: "No paired devices are available yet."
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
        }

        QuickControlActionRow {
            width: parent.width
            theme: root.t
            title: "Open Bluetooth Manager"
            subtitle: "Use Blueman for pairing and discovery"
            trailingText: "Open"
            onClicked: {
                if (root.quickControlsController) {
                    root.quickControlsController.close();
                }
                Quickshell.execDetached(root.openCommand);
            }
        }
    }
}
