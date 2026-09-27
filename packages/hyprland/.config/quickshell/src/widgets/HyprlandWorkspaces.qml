import QtQuick
import QtQuick.Layouts

import Quickshell.Hyprland
import "../theme"

Rectangle {
    id: root

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property var screenModel: null
    property color mutedTextColor: root.t.mutedTextColor
    property string uiFont: root.t.uiFont
    property int textPx: root.t.textPx
    property int segmentHeightPx: root.t.segmentHeightPx
    property color workspaceFillColor: Qt.alpha(root.t.chipColor, 0.72)
    property color workspaceHoverColor: Qt.alpha(root.t.chipHoverColor, 0.88)
    property color workspaceBorderColor: Qt.alpha(root.t.chipBorder, 0.9)
    property color workspaceActiveFillColor: root.t.workspaceActiveFillColor
    property color workspaceActiveBorderColor: root.t.workspaceActiveBorderColor
    property color workspaceActiveTextColor: root.t.workspaceActiveTextColor
    property color workspaceVisibleFillColor: root.t.workspaceVisibleFillColor
    property color workspaceVisibleBorderColor: root.t.workspaceVisibleBorderColor
    property color workspaceVisibleTextColor: root.t.workspaceVisibleTextColor
    property int workspaceButtonGapPx: root.t.workspaceGapPx + 2
    readonly property var workspaceLabels: ({
        1: " 1",
        2: " 2",
    })
    readonly property var workspaceList: {
        const values = Hyprland.workspaces.values || [];
        const list = values.slice().filter((ws) => ws.id > 0);
        list.sort((a, b) => a.id - b.id);
        return list;
    }
    readonly property string widestWorkspaceLabel: {
        let widest = "0";

        for (const ws of root.workspaceList) {
            const label = root.workspaceLabel(ws);
            if (label.length > widest.length) {
                widest = label;
            }
        }

        return widest;
    }
    readonly property int workspaceButtonWidthPx: Math.max(18, widthProbe.implicitWidth + 10)

    function workspaceLabel(ws) {
        if (!ws) {
            return "";
        }

        const mappedLabel = root.workspaceLabels[ws.id];
        if (mappedLabel) {
            return mappedLabel;
        }

        if (ws.name && ws.name !== String(ws.id)) {
            return ws.name;
        }

        return String(ws.id);
    }

    radius: 5
    color: "transparent"
    implicitHeight: root.segmentHeightPx
    implicitWidth: wsRow.implicitWidth + 6

    RowLayout {
        id: wsRow
        anchors.fill: parent
        anchors.margins: 2
        spacing: root.workspaceButtonGapPx

        Text {
            id: widthProbe
            visible: false
            text: root.widestWorkspaceLabel
            font.pixelSize: root.textPx
            font.family: root.uiFont
        }

        Repeater {
            model: root.workspaceList

            Rectangle {
                required property var modelData

                readonly property var ws: modelData
                readonly property var monitor: Hyprland.monitorFor(root.screenModel)
                readonly property bool activeOnScreen: ws && ws.monitor === monitor
                readonly property bool focusedWorkspace: ws && ws.focused
                readonly property bool selectedOnScreen: !!monitor
                    && !!monitor.activeWorkspace
                    && monitor.activeWorkspace === ws
                readonly property bool visibleOnUnfocusedScreen: selectedOnScreen && !focusedWorkspace
                readonly property bool hovered: area.containsMouse

                visible: activeOnScreen
                radius: 5
                color: focusedWorkspace
                    ? root.workspaceActiveFillColor
                    : (visibleOnUnfocusedScreen
                        ? root.workspaceVisibleFillColor
                        : (hovered ? root.workspaceHoverColor : root.workspaceFillColor))
                border.width: 1
                border.color: focusedWorkspace
                    ? root.workspaceActiveBorderColor
                    : (visibleOnUnfocusedScreen
                        ? root.workspaceVisibleBorderColor
                        : root.workspaceBorderColor)
                implicitHeight: root.segmentHeightPx - 4
                implicitWidth: root.workspaceButtonWidthPx

                Behavior on color {
                    ColorAnimation { duration: 100 }
                }

                Behavior on border.color {
                    ColorAnimation { duration: 100 }
                }

                Text {
                    id: wsLabel
                    anchors.fill: parent
                    text: root.workspaceLabel(ws)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: focusedWorkspace
                        ? root.workspaceActiveTextColor
                        : (visibleOnUnfocusedScreen
                            ? root.workspaceVisibleTextColor
                            : root.mutedTextColor)
                    font.pixelSize: root.textPx
                    font.family: root.uiFont
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (ws) {
                            ws.activate();
                        }
                    }
                }
            }
        }
    }
}
