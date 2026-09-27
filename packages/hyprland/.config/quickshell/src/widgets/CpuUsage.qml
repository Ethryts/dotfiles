import QtQuick
import Quickshell.Io
import "../theme"

Rectangle {
    id: root

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property int refreshIntervalMs: 2000
    property bool flat: true
    property color textColor: root.t.textColor
    property color backgroundColor: "transparent"
    property color borderColor: "transparent"
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    property int horizontalPadding: 8

    property int _prevTotal: -1
    property int _prevIdle: -1
    property int usagePercent: 0
    property bool hasSample: false

    readonly property string label: root.hasSample ? (" " + root.usagePercent + "%") : " --%"

    function parseCpuStat(raw) {
        if (!raw) {
            return;
        }

        const line = String(raw).split("\n")[0].trim();
        if (!line.startsWith("cpu")) {
            return;
        }

        const parts = line.split(/\s+/);
        if (parts.length < 5) {
            return;
        }

        let total = 0;
        let idle = 0;
        for (let i = 1; i < parts.length; i++) {
            const val = Number(parts[i]);
            if (!Number.isFinite(val)) {
                continue;
            }

            total += val;
            if (i === 4 || i === 5) {
                idle += val;
            }
        }

        if (total <= 0) {
            return;
        }

        if (root._prevTotal >= 0 && total > root._prevTotal) {
            const deltaTotal = total - root._prevTotal;
            const deltaIdle = idle - root._prevIdle;

            if (deltaTotal > 0) {
                let usage = Math.round(((deltaTotal - deltaIdle) * 100) / deltaTotal);
                if (usage < 0) usage = 0;
                if (usage > 100) usage = 100;
                root.usagePercent = usage;
                root.hasSample = true;
            }
        }

        root._prevTotal = total;
        root._prevIdle = idle;
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

    FileView {
        id: cpuStatFile
        path: "/proc/stat"
        preload: true
        watchChanges: false
        onLoaded: root.parseCpuStat(cpuStatFile.text())
        onTextChanged: root.parseCpuStat(cpuStatFile.text())
    }

    Timer {
        interval: root.refreshIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: cpuStatFile.reload()
    }
}
