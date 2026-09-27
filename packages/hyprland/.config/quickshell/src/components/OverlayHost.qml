import QtQuick

QtObject {
    id: root

    property QtObject tooltipController: null
    property QtObject quickControlsController: null
    property QtObject launcherController: null
    property QtObject calendarController: null
    property var screenModel: null
    property var hostWindow: null

    function toggleQuickControl(kind, anchorItem) {
        if (root.quickControlsController && root.hostWindow && root.screenModel && anchorItem) {
            root.quickControlsController.toggle(kind, anchorItem, root.hostWindow, root.screenModel);
        }
    }

    function quickControlOpen(kind, anchorItem) {
        return !!root.quickControlsController
            && !!root.hostWindow
            && !!root.screenModel
            && !!anchorItem
            && root.quickControlsController.matches(kind, anchorItem, root.hostWindow, root.screenModel);
    }

    function showTooltip(text, anchorItem) {
        if (root.tooltipController && root.hostWindow && root.screenModel && anchorItem) {
            root.tooltipController.show(text, anchorItem, root.hostWindow, root.screenModel);
        }
    }

    function closeTooltip(anchorItem) {
        if (root.tooltipController) {
            root.tooltipController.close(anchorItem);
        }
    }

    function syncTooltip(text, anchorItem, hovered, blocked) {
        if (!root.tooltipController || !root.hostWindow || !root.screenModel || !anchorItem) {
            return;
        }

        if (hovered && !blocked && String(text || "").trim().length > 0) {
            root.tooltipController.show(text, anchorItem, root.hostWindow, root.screenModel);
            return;
        }

        root.tooltipController.close(anchorItem);
    }

    function toggleLauncher() {
        if (root.launcherController && root.screenModel) {
            root.launcherController.toggle(root.screenModel);
        }
    }

    function toggleCalendar(anchorItem) {
        if (root.calendarController && root.hostWindow && root.screenModel && anchorItem) {
            root.calendarController.toggle(anchorItem, root.hostWindow, root.screenModel);
        }
    }
}
