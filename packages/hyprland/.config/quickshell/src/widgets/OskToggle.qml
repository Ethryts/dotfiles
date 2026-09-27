import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

Rectangle {
    id: root

    required property QtObject postureService
    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property int refreshIntervalMs: 2500
    property color onColor: root.t.successColor
    property color offColor: root.t.errorColor
    property color backgroundColor: "transparent"
    property color hoverColor: root.t.interactiveHoverColor
    property color pressedColor: root.t.interactivePressedColor
    property color hoverBorderColor: root.t.interactiveBorderColor
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    property int horizontalPadding: 8
    property string policy: "off"
    property string tooltipText: ""
    property var scriptCommandPrefix: ["bash", Quickshell.shellPath("scripts/osk-toggle.sh")]
    readonly property bool singleScreenMode: (Quickshell.screens || []).length <= 1

    readonly property bool enabledState: root.policy === "auto"
        && root.postureService
        && root.postureService.tabletMode
        && root.singleScreenMode
    readonly property color resolvedTextColor: root.enabledState ? root.onColor : root.offColor
    readonly property string labelText: root.enabledState ? "On" : "Off"

    function parseOutput(raw) {
        const line = String(raw || "").trim();
        if (!line.length) {
            root.policy = "off";
            root.tooltipText = "";
            return;
        }

        const policyMatch = /"policy":"([^"]*)"/.exec(line);
        const tooltipMatch = /"tooltip":"([^"]*)"/.exec(line);

        root.policy = policyMatch ? policyMatch[1] : "off";
        root.tooltipText = tooltipMatch ? tooltipMatch[1] : "";
    }

    function refreshState() {
        if (!stateProcess.running) {
            stateProcess.running = true;
        }
    }

    radius: root.t.chipRadiusPx
    color: area.pressed ? root.pressedColor : (area.containsMouse ? root.hoverColor : root.backgroundColor)
    border.width: area.containsMouse ? 1 : 0
    border.color: root.hoverBorderColor
    implicitHeight: root.segmentHeightPx
    implicitWidth: textItem.implicitWidth + (root.horizontalPadding * 2)

    Behavior on color {
        ColorAnimation { duration: 100 }
    }

    Text {
        id: textItem
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        text: "󰌌 " + root.labelText
        color: root.resolvedTextColor
        font.pixelSize: root.textPx
        font.family: root.uiFont
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Quickshell.execDetached(root.scriptCommandPrefix.concat(["toggle"]));
            delayedRefresh.restart();
        }
    }

    Process {
        id: stateProcess
        command: root.scriptCommandPrefix.concat(["get"])
        running: false
        stdout: StdioCollector {
            id: stateStdout
            waitForEnd: true
        }
        onExited: root.parseOutput(stateStdout.text)
    }

    Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshState()
    }

    Timer {
        id: delayedRefresh
        interval: 240
        repeat: false
        onTriggered: root.refreshState()
    }
}
