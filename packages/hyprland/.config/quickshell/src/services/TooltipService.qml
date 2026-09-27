import QtQuick

QtObject {
    id: root

    property bool open: false
    property string text: ""
    property var screen: null
    property var parentWindow: null
    property var anchorItem: null

    function matches(text, anchorItem, parentWindow, screen) {
        const normalizedText = String(text || "").trim();
        return root.open
            && root.text === normalizedText
            && root.anchorItem === anchorItem
            && root.parentWindow === parentWindow
            && root.screen === screen;
    }

    function show(text, anchorItem, parentWindow, screen) {
        const normalizedText = String(text || "").trim();
        if (!normalizedText.length || !anchorItem || !parentWindow || !screen) {
            root.close();
            return;
        }

        if (root.matches(normalizedText, anchorItem, parentWindow, screen)) {
            return;
        }

        root.text = normalizedText;
        root.anchorItem = anchorItem;
        root.parentWindow = parentWindow;
        root.screen = screen;
        root.open = true;
    }

    function close(anchorItem) {
        if (anchorItem && root.anchorItem && anchorItem !== root.anchorItem) {
            return;
        }

        root.open = false;
        root.text = "";
        root.screen = null;
        root.parentWindow = null;
        root.anchorItem = null;
    }
}
