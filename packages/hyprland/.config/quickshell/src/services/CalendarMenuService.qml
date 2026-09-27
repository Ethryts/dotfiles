import QtQuick


QtObject {
    id: root

    property bool open: false
    property var screen: null
    property var parentWindow: null
    property var anchorItem: null

    function toggle(anchorItem, parentWindow, screen) {
        if (root.open
                && root.anchorItem === anchorItem
                && root.parentWindow === parentWindow
                && root.screen === screen) {
            root.close();
            return;
        }

        root.anchorItem = anchorItem;
        root.parentWindow = parentWindow;
        root.screen = screen;
        root.open = true;
    }

    function close() {
        root.open = false;
        root.anchorItem = null;
        root.parentWindow = null;
        root.screen = null;
    }
}
