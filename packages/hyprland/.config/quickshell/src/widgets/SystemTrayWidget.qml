import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../theme"

Item {
    id: root

    required property QtObject overlayHost
    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme

    property int iconSizePx: Math.max(14, Math.round(root.t.textPx * 1.2))
    property int itemSizePx: root.t.segmentHeightPx
    property int itemSpacingPx: 0
    property color textColor: root.t.textColor
    property color mutedTextColor: root.t.mutedTextColor
    property color hoverColor: root.t.interactiveHoverColor
    property color pressedColor: root.t.interactivePressedColor
    property color hoverBorderColor: root.t.interactiveBorderColor

    function itemKey(item) {
        return String((item && (item.id || item.title || item.icon)) || "").toLowerCase();
    }

    function isSpotify(item) {
        return root.itemKey(item).indexOf("spotify") !== -1;
    }

    function isSteam(item) {
        return root.itemKey(item).indexOf("steam") !== -1;
    }

    function iconSourceFor(item) {
        if (!item) {
            return "";
        }

        return String(item.icon || "").replace(/\?path=.*/, "");
    }

    function tooltipFor(item) {
        if (!item) {
            return "";
        }

        const title = String(item.tooltipTitle || item.title || item.id || "").trim();
        const description = String(item.tooltipDescription || "").trim();

        if (title.length > 0 && description.length > 0 && title !== description) {
            return title + "\n" + description;
        }

        return title || description;
    }

    function showMenu(item, anchorItem) {
        if (!item || !item.hasMenu || !root.overlayHost || !root.overlayHost.hostWindow) {
            return false;
        }

        const point = anchorItem.mapToItem(null, 0, anchorItem.height);
        item.display(root.overlayHost.hostWindow, Math.round(point.x), Math.round(point.y));
        return true;
    }

    function handlePrimaryClick(item, anchorItem) {
        if (!item) {
            return;
        }

        if (root.isSpotify(item)) {
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"media\")"]);
            return;
        }

        if (root.isSteam(item)) {
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"steam\")"]);
            return;
        }

        if (item.hasMenu && root.showMenu(item, anchorItem)) {
            return;
        }

        item.activate();
    }

    visible: trayRepeater.count > 0
    implicitHeight: root.visible ? trayRow.implicitHeight : 0
    implicitWidth: root.visible ? trayRow.implicitWidth : 0

    Row {
        id: trayRow

        visible: root.visible
        spacing: root.itemSpacingPx

        Repeater {
            id: trayRepeater

            model: SystemTray.items

            Rectangle {
                id: trayButton

                required property var modelData
                readonly property var trayItem: modelData
                readonly property string tooltipText: root.tooltipFor(trayButton.trayItem)
                readonly property string iconSource: root.iconSourceFor(trayButton.trayItem)

                radius: root.t.chipRadiusPx
                color: area.pressed
                    ? root.pressedColor
                    : (area.containsMouse ? root.hoverColor : "transparent")
                border.width: area.containsMouse ? 1 : 0
                border.color: root.hoverBorderColor
                implicitWidth: root.itemSizePx
                implicitHeight: root.itemSizePx

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                IconImage {
                    id: itemIcon

                    anchors.centerIn: parent
                    width: root.iconSizePx
                    height: root.iconSizePx
                    implicitSize: root.iconSizePx
                    source: trayButton.iconSource
                    asynchronous: true
                    mipmap: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: itemIcon.status !== Image.Ready
                    text: "󰀻"
                    color: root.mutedTextColor
                    font.family: root.t.uiFont
                    font.pixelSize: root.t.textPx
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: function(mouse) {
                        if (!trayButton.trayItem) {
                            return;
                        }

                        if (mouse.button === Qt.RightButton) {
                            root.showMenu(trayButton.trayItem, trayButton);
                            return;
                        }

                        if (mouse.button === Qt.MiddleButton) {
                            trayButton.trayItem.secondaryActivate();
                            return;
                        }

                        root.handlePrimaryClick(trayButton.trayItem, trayButton);
                    }

                    onContainsMouseChanged: {
                        if (root.overlayHost) {
                            root.overlayHost.syncTooltip(
                                trayButton.tooltipText,
                                trayButton,
                                containsMouse,
                                false
                            );
                        }
                    }

                    onWheel: function(wheel) {
                        if (!trayButton.trayItem) {
                            return;
                        }

                        trayButton.trayItem.scroll(wheel.angleDelta.y, false);
                        wheel.accepted = true;
                    }
                }

                onTooltipTextChanged: {
                    if (root.overlayHost) {
                        root.overlayHost.syncTooltip(
                            trayButton.tooltipText,
                            trayButton,
                            area.containsMouse,
                            false
                        );
                    }
                }
            }
        }
    }
}
