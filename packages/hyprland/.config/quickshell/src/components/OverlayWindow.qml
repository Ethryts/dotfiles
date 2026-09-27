import QtQuick
import Quickshell

PanelWindow {
    id: root

    required property QtObject controller
    property var screenModel: null

    property string placement: "anchored"
    property string horizontalAlignment: "center"
    property bool clampHorizontally: false
    property int horizontalMargin: 0
    property int verticalOffset: 0
    property bool closeOnBackdrop: true
    property bool closeOnEscape: false
    property bool windowFocusable: false
    property bool dimBackdrop: false
    property real dimOpacity: 0.1

    readonly property bool activeScreen: !!root.controller
        && !!root.controller.open
        && root.controller.screen === root.screenModel
    readonly property var parentWindowRef: root.activeScreen ? root.controller.parentWindow : null
    readonly property var anchorItemRef: root.activeScreen ? root.controller.anchorItem : null
    readonly property rect anchorRect: root.activeScreen && root.parentWindowRef && root.anchorItemRef
        ? root.parentWindowRef.itemRect(root.anchorItemRef)
        : Qt.rect(0, 0, 0, 0)
    readonly property int popupX: {
        const popupWidth = popupContainer.width;

        if (root.placement === "centered") {
            return Math.round((root.width - popupWidth) / 2);
        }

        let x = 0;

        switch (root.horizontalAlignment) {
        case "left":
            x = Math.round(root.anchorRect.x);
            break;
        case "right":
            x = Math.round(root.anchorRect.x + root.anchorRect.width - popupWidth);
            break;
        default:
            x = Math.round(root.anchorRect.x + ((root.anchorRect.width - popupWidth) / 2));
            break;
        }

        if (!root.clampHorizontally) {
            return x;
        }

        const minX = root.horizontalMargin;
        const maxX = Math.max(minX, root.width - popupWidth - root.horizontalMargin);
        return Math.max(minX, Math.min(maxX, x));
    }
    readonly property int popupY: {
        const popupHeight = popupContainer.height;

        if (root.placement === "centered") {
            return Math.round((root.height - popupHeight) / 2);
        }

        if (root.parentWindowRef) {
            return Math.round(root.parentWindowRef.height + root.verticalOffset);
        }

        return Math.round(root.verticalOffset);
    }

    function closeController(sourceItem) {
        if (root.controller && root.controller.close) {
            root.controller.close(sourceItem);
        }
    }

    default property alias content: popupContainer.data
    property alias contentData: popupContainer.data
    readonly property alias contentItem: popupContainer

    screen: root.screenModel
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    aboveWindows: true
    color: "transparent"
    visible: root.activeScreen
    focusable: root.windowFocusable || root.closeOnEscape

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.dimBackdrop && root.activeScreen ? root.dimOpacity : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: 140
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.closeOnBackdrop
        acceptedButtons: enabled ? Qt.AllButtons : Qt.NoButton
        onClicked: function(mouse) {
            const insidePopup = mouse.x >= popupContainer.x
                && mouse.x <= popupContainer.x + popupContainer.width
                && mouse.y >= popupContainer.y
                && mouse.y <= popupContainer.y + popupContainer.height;

            if (!insidePopup) {
                root.closeController();
            }
        }
    }

    Item {
        id: popupContainer

        x: root.popupX
        y: root.popupY
        width: childrenRect.width
        height: childrenRect.height
    }
}
