import QtQuick

QtObject {
    id: root

    property bool open: false
    property string kind: ""
    property var screen: null
    property var parentWindow: null
    property var anchorItem: null

    function matches(kind, anchorItem, parentWindow, screen) {
        return root.open
            && root.kind === String(kind || "").trim().toLowerCase()
            && root.anchorItem === anchorItem
            && root.parentWindow === parentWindow
            && root.screen === screen;
    }

    function show(kind, anchorItem, parentWindow, screen) {
        const normalizedKind = String(kind || "").trim().toLowerCase();
        if (!normalizedKind.length || !anchorItem || !parentWindow || !screen) {
            root.close();
            return;
        }

        root.kind = normalizedKind;
        root.anchorItem = anchorItem;
        root.parentWindow = parentWindow;
        root.screen = screen;
        root.open = true;
    }

    function toggle(kind, anchorItem, parentWindow, screen) {
        if (root.matches(kind, anchorItem, parentWindow, screen)) {
            root.close();
            return;
        }

        root.show(kind, anchorItem, parentWindow, screen);
    }

    function close(anchorItem) {
        if (anchorItem && root.anchorItem && anchorItem !== root.anchorItem) {
            return;
        }

        root.open = false;
        root.kind = "";
        root.screen = null;
        root.parentWindow = null;
        root.anchorItem = null;
    }
}
