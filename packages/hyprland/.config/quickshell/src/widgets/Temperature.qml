import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

Rectangle {
    id: root

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property int refreshIntervalMs: 5000
    property bool flat: true
    property color textColor: root.t.textColor
    property color backgroundColor: "transparent"
    property color borderColor: "transparent"
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    property int horizontalPadding: 8
    property var scriptCommandPrefix: ["bash", Quickshell.shellPath("scripts/temperature.sh")]
    property string label: " --"

    function parseOutput(raw) {
        const line = String(raw || "").trim();
        root.label = line.length > 0 ? line : " n/a";
    }

    radius: root.flat ? 0 : 6
    color: root.backgroundColor
    border.width: root.flat ? 0 : 1
    border.color: root.borderColor
    implicitHeight: root.segmentHeightPx
    implicitWidth: textItem.implicitWidth + (root.horizontalPadding * 2)

    Text {
        id: textItem
        anchors.centerIn: parent
        text: root.label
        color: root.textColor
        font.pixelSize: root.textPx
        font.family: root.uiFont
    }

    Process {
        id: tempProcess
        command: root.scriptCommandPrefix.concat(["get"])
        running: false
        stdout: StdioCollector {
            id: tempStdout
            waitForEnd: true
        }
        onExited: root.parseOutput(tempStdout.text)
    }

    Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!tempProcess.running) {
                tempProcess.running = true;
            }
        }
    }
}
