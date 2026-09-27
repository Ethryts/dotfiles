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
    property QtObject networkService: null
    property var openCommand: ["nm-connection-editor"]

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property bool busy: root.networkService ? root.networkService.busy : false
    readonly property string connectionKind: root.networkService ? root.networkService.connectionKind : "offline"
    readonly property string connectionLabel: root.networkService ? root.networkService.connectionLabel : "Offline"
    readonly property int connectionSignal: root.networkService ? root.networkService.connectionSignal : -1
    readonly property var networks: root.networkService ? root.networkService.networks : []
    readonly property string actionMessage: root.networkService ? root.networkService.actionMessage : ""
    readonly property string actionTone: root.networkService ? root.networkService.actionTone : "info"
    readonly property int maxListHeight: Math.round(220 * root.t.uiScale)
    readonly property string statusText: root.busy ? "Refreshing visible networks…" : root.actionMessage
    readonly property string statusTone: root.busy ? "info" : root.actionTone
    readonly property string headerSummary: {
        if (root.connectionKind === "wifi") {
            return root.connectionLabel + (root.connectionSignal >= 0 ? " • " + root.connectionSignal + "%" : "");
        }

        if (root.connectionKind === "ethernet") {
            return "Ethernet connected";
        }

        return "Offline";
    }
    readonly property bool showNetworkList: root.networks.length > 0

    implicitWidth: root.panelWidth > 0 ? root.panelWidth : contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    function networkSubtitle(network) {
        const parts = [];

        if (network.saved) {
            parts.push("Saved");
        }

        parts.push(network.open ? "Open" : (network.security || "Secured"));

        if (Number.isFinite(network.signal) && network.signal >= 0) {
            parts.push(Math.round(network.signal) + "%");
        }

        return parts.join(" • ");
    }

    function networkActionText(network) {
        if (network.active) {
            return "Connected";
        }

        if (!network.connectable) {
            return "Needs app";
        }

        return network.saved ? "Switch" : "Connect";
    }

    function connectNetwork(network) {
        if (root.networkService) {
            root.networkService.connectNetwork(network);
        }
    }

    Column {
        id: contentColumn
        width: root.panelWidth > 0 ? root.panelWidth : implicitWidth
        spacing: root.t.innerGapPx + 2

        Row {
            width: parent.width
            spacing: root.t.innerGapPx

            Text {
                width: Math.max(0, parent.width - refreshButton.width - parent.spacing)
                text: "Network"
                color: root.t.textColor
                font.pixelSize: root.t.textPx + 2
                font.family: root.t.uiFont
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }

            QuickControlHeaderButton {
                id: refreshButton
                anchors.verticalCenter: parent.verticalCenter
                theme: root.t
                text: "Refresh"
                enabled: !root.busy
                onClicked: {
                    if (!root.networkService) {
                        return;
                    }
                    root.networkService.clearActionMessage();
                    root.networkService.refreshSummary();
                    root.networkService.refreshDetails(true);
                    root.networkService.refreshNetworks();
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
            text: root.statusText
            tone: root.statusTone
        }

        QuickControlSectionLabel {
            width: parent.width
            theme: root.t
            text: "Networks"
            visible: root.showNetworkList
        }

        Flickable {
            width: parent.width
            height: Math.min(contentHeight, root.maxListHeight)
            visible: root.showNetworkList
            clip: true
            contentWidth: width
            contentHeight: networksColumn.implicitHeight

            Column {
                id: networksColumn
                width: parent.width
                spacing: root.t.innerGapPx

                Repeater {
                    model: root.networks

                    delegate: QuickControlActionRow {
                        required property var modelData
                        width: parent.width
                        theme: root.t
                        title: modelData.ssid
                        subtitle: root.networkSubtitle(modelData)
                        trailingText: root.networkActionText(modelData)
                        active: modelData.active
                        enabled: !root.busy && (modelData.active || modelData.connectable)
                        onClicked: root.connectNetwork(modelData)
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: !root.showNetworkList
            text: root.connectionKind === "ethernet"
                ? "Ethernet is active. Wi-Fi networks will appear here when a wireless device is available."
                : "No visible Wi-Fi networks found."
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
        }

        QuickControlActionRow {
            width: parent.width
            theme: root.t
            title: "Open Network Settings"
            subtitle: "Use NetworkManager tools for passwords and advanced options"
            trailingText: "Open"
            onClicked: {
                if (root.quickControlsController) {
                    root.quickControlsController.close();
                }
                Quickshell.execDetached(root.openCommand);
            }
        }
    }

    Component.onCompleted: {
        if (!root.networkService) {
            return;
        }
        root.networkService.refreshSummary();
        root.networkService.refreshDetails(true);
        root.networkService.refreshNetworks();
    }
}
