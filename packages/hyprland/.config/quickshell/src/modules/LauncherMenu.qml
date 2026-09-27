import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "../services"
import "../theme"

Scope {
    id: root

    required property QtObject launcherController

    Theme {
        id: menuTheme
    }

    Variants {
        model: Quickshell.screens

        OverlayWindow {
            id: overlay
            required property var modelData

            property string activeModeId: root.launcherController.defaultModeId
            readonly property var activeMode: root.launcherController.mode(overlay.activeModeId)
            property string query: ""
            property int selectedIndex: 0
            property var results: []
            property bool searchQueued: false
            property bool launchQueued: false
            property bool suppressTextChange: false
            property string inFlightSearchToken: ""
            property int searchLimit: 24
            property int visibleRows: 8
            property int pendingFocusAttempts: 0
            property var oskCommandPrefix: ["bash", Quickshell.shellPath("scripts/osk-toggle.sh")]
            readonly property bool tabletMode: !!PostureService.tabletMode
            readonly property bool singleScreenMode: (Quickshell.screens || []).length <= 1
            readonly property int paneWidthPx: menuTheme.launcherWidthPx
            readonly property int rowHeightPx: menuTheme.launcherRowHeightPx
            readonly property int inputHeightPx: menuTheme.launcherInputHeightPx

            function activeModeText(key, fallback) {
                const modeSpec = overlay.activeMode || {};
                const value = String(modeSpec[key] || "");
                return value.length ? value : fallback;
            }

            function searchToken() {
                return overlay.activeModeId + "\t" + overlay.query;
            }

            function startSearch() {
                if (overlay.activeModeId === "apps") {
                    overlay.searchQueued = false;
                    overlay.results = root.launcherController.searchApplications(overlay.query, overlay.searchLimit);
                    overlay.clampSelection();
                    if (overlay.launchQueued) {
                        overlay.launchQueued = false;
                        overlay.launchSelected();
                    }
                    return;
                }
                overlay.inFlightSearchToken = overlay.searchToken();
                searchProcess.running = true;
            }

            function clampSelection() {
                if (overlay.results.length <= 0) {
                    overlay.selectedIndex = -1;
                    return;
                }

                if (overlay.selectedIndex < 0) {
                    overlay.selectedIndex = 0;
                } else if (overlay.selectedIndex >= overlay.results.length) {
                    overlay.selectedIndex = overlay.results.length - 1;
                }

                resultList.currentIndex = overlay.selectedIndex;
                resultList.positionViewAtIndex(overlay.selectedIndex, ListView.Contain);
            }

            function parseResults(raw) {
                const nextResults = [];
                const lines = String(raw || "").split("\n");

                for (const line of lines) {
                    if (!line.length) {
                        continue;
                    }

                    const parts = line.split("\t");
                    nextResults.push({
                        id: parts[0] || "",
                        name: parts[1] || "",
                        subtitle: parts[2] || ""
                    });
                }

                overlay.results = nextResults;
                overlay.clampSelection();
            }

            function requestSearch(immediate) {
                if (!overlay.activeScreen) {
                    return;
                }

                if (immediate) {
                    searchTimer.stop();
                    if (searchProcess.running) {
                        overlay.searchQueued = true;
                        return;
                    }

                    overlay.startSearch();
                    return;
                }

                searchTimer.restart();
            }

            function moveSelection(delta) {
                if (overlay.results.length <= 0) {
                    return;
                }

                overlay.selectedIndex = Math.max(0, Math.min(overlay.results.length - 1, overlay.selectedIndex + delta));
                overlay.clampSelection();
            }

            function switchMode(delta) {
                if ((root.launcherController.modes || []).length < 2) {
                    return;
                }

                overlay.activeModeId = root.launcherController.nextModeId(overlay.activeModeId, delta);
                overlay.selectedIndex = 0;
                overlay.launchQueued = false;
                overlay.requestSearch(true);
                overlay.requestSearchFocus();
                overlay.requestTabletKeyboard();
            }

            function launchSelected() {
                if (searchTimer.running || searchProcess.running || overlay.searchQueued) {
                    overlay.launchQueued = true;
                    overlay.requestSearch(true);
                    return;
                }

                if (overlay.selectedIndex < 0 || overlay.selectedIndex >= overlay.results.length) {
                    return;
                }

                const entry = overlay.results[overlay.selectedIndex];
                if (!entry || !String(entry.id || "").length) {
                    return;
                }

                const modeId = overlay.activeModeId;
                overlay.launchQueued = false;
                root.launcherController.activateResult(modeId, entry);
                root.launcherController.close();
            }

            function resetState() {
                overlay.activeModeId = root.launcherController.normalizeModeId(root.launcherController.openModeId);
                overlay.query = "";
                overlay.results = [];
                overlay.selectedIndex = 0;
                overlay.searchQueued = false;
                overlay.launchQueued = false;
                overlay.inFlightSearchToken = "";
                searchTimer.stop();
                overlay.suppressTextChange = true;
                searchField.text = "";
                overlay.suppressTextChange = false;
            }

            function requestSearchFocus() {
                if (!overlay.visible) {
                    return;
                }

                searchField.forceActiveFocus(Qt.ActiveWindowFocusReason);

                if (searchField.activeFocus) {
                    overlay.pendingFocusAttempts = 0;
                    focusTimer.stop();
                    return;
                }

                if (overlay.pendingFocusAttempts > 0 && !focusTimer.running) {
                    focusTimer.start();
                }
            }

            function requestTabletKeyboard() {
                if (!overlay.tabletMode || !overlay.singleScreenMode || !overlay.visible) {
                    return;
                }

                Quickshell.execDetached(overlay.oskCommandPrefix.concat(["apply"]));
                Qt.callLater(function() {
                    if (overlay.visible && searchField.activeFocus) {
                        Qt.inputMethod.show();
                    }
                });
            }

            controller: root.launcherController
            screenModel: overlay.modelData
            placement: "centered"
            closeOnBackdrop: true
            windowFocusable: true

            onVisibleChanged: {
                if (visible) {
                    overlay.resetState();
                    overlay.requestSearch(true);
                    overlay.pendingFocusAttempts = 20;
                    overlay.requestSearchFocus();
                    overlay.requestTabletKeyboard();
                    delayedFocusTimer.restart();
                } else {
                    overlay.pendingFocusAttempts = 0;
                    overlay.searchQueued = false;
                    overlay.launchQueued = false;
                    focusTimer.stop();
                    delayedFocusTimer.stop();
                    searchTimer.stop();
                    overlay.resetState();
                }
            }

            Connections {
                target: root.launcherController

                function onApplicationsChanged() {
                    if (overlay.activeScreen && overlay.activeModeId === "apps") {
                        overlay.launchQueued = false;
                        overlay.requestSearch(true);
                    }
                }

                function onOpenModeIdChanged() {
                    if (!overlay.visible || root.launcherController.screen !== overlay.modelData) {
                        return;
                    }

                    const nextModeId = root.launcherController.normalizeModeId(root.launcherController.openModeId);
                    if (nextModeId === overlay.activeModeId) {
                        return;
                    }

                    overlay.activeModeId = nextModeId;
                    overlay.selectedIndex = 0;
                    overlay.launchQueued = false;
                    overlay.requestSearch(true);
                    overlay.requestSearchFocus();
                    overlay.requestTabletKeyboard();
                }
            }

            Surface {
                id: launcherPane

                width: overlay.paneWidthPx
                theme: menuTheme
                padding: menuTheme.menuPaddingPx
                implicitHeight: (menuTheme.menuPaddingPx * 2)
                    + searchBox.height
                    + menuTheme.innerGapPx
                    + resultViewport.height

                Column {
                    anchors.fill: parent
                    spacing: menuTheme.innerGapPx

                    Rectangle {
                        id: searchBox

                        width: parent.width
                        height: overlay.inputHeightPx
                        radius: menuTheme.chipRadiusPx
                        color: menuTheme.chipColor
                        border.width: menuTheme.chipBorderWidthPx
                        border.color: menuTheme.chipBorder

                        TapHandler {
                            onTapped: {
                                overlay.pendingFocusAttempts = 3;
                                overlay.requestSearchFocus();
                                overlay.requestTabletKeyboard();
                            }
                        }

                        TextInput {
                            id: searchField

                            function deletePreviousWord() {
                                if (selectionStart !== selectionEnd) {
                                    remove(selectionStart, selectionEnd);
                                    cursorPosition = Math.min(selectionStart, selectionEnd);
                                    return;
                                }

                                if (cursorPosition <= 0) {
                                    return;
                                }

                                let start = cursorPosition;

                                while (start > 0 && /\s/.test(text.charAt(start - 1))) {
                                    start--;
                                }

                                while (start > 0 && !/\s/.test(text.charAt(start - 1))) {
                                    start--;
                                }

                                remove(start, cursorPosition);
                                cursorPosition = start;
                            }

                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            color: menuTheme.textColor
                            font.pixelSize: menuTheme.textPx + 2
                            font.family: menuTheme.uiFont
                            verticalAlignment: Text.AlignVCenter
                            activeFocusOnPress: true
                            selectByMouse: true
                            selectedTextColor: menuTheme.groupColor
                            selectionColor: menuTheme.accentColor
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase

                            onTextChanged: {
                                if (overlay.suppressTextChange) {
                                    return;
                                }

                                overlay.query = text;
                                overlay.selectedIndex = 0;
                                overlay.launchQueued = false;
                                overlay.requestSearch(false);
                            }

                            Keys.onPressed: function(event) {
                                if (event.modifiers & Qt.ControlModifier) {
                                    switch (event.key) {
                                    case Qt.Key_N:
                                        overlay.moveSelection(1);
                                        event.accepted = true;
                                        return;
                                    case Qt.Key_P:
                                        overlay.moveSelection(-1);
                                        event.accepted = true;
                                        return;
                                    case Qt.Key_Y:
                                        overlay.launchSelected();
                                        event.accepted = true;
                                        return;
                                    case Qt.Key_W:
                                        searchField.deletePreviousWord();
                                        event.accepted = true;
                                        return;
                                    default:
                                        break;
                                    }
                                }

                                switch (event.key) {
                                case Qt.Key_Tab:
                                    overlay.switchMode((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Backtab:
                                    overlay.switchMode(-1);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Down:
                                    overlay.moveSelection(1);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Up:
                                    overlay.moveSelection(-1);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                    overlay.launchSelected();
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Escape:
                                    root.launcherController.close();
                                    event.accepted = true;
                                    break;
                                default:
                                    break;
                                }
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !searchField.text.length
                            text: overlay.activeModeText("placeholderText", "Search")
                            color: menuTheme.mutedTextColor
                            font.pixelSize: menuTheme.textPx + 2
                            font.family: menuTheme.uiFont
                        }
                    }

                    Rectangle {
                        id: resultViewport

                        width: parent.width
                        height: overlay.rowHeightPx * overlay.visibleRows
                        radius: menuTheme.chipRadiusPx
                        color: "transparent"
                        clip: true

                        ListView {
                            id: resultList

                            anchors.fill: parent
                            anchors.rightMargin: 2
                            clip: true
                            model: overlay.results
                            interactive: overlay.results.length > overlay.visibleRows
                            currentIndex: overlay.selectedIndex
                            boundsBehavior: Flickable.StopAtBounds
                            spacing: 2

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: resultList.width
                                height: overlay.rowHeightPx
                                radius: menuTheme.chipRadiusPx
                                color: index === overlay.selectedIndex ? menuTheme.accentColor : "transparent"

                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        text: modelData.name
                                        color: index === overlay.selectedIndex ? menuTheme.groupColor : menuTheme.textColor
                                        font.pixelSize: menuTheme.textPx + 1
                                        font.family: menuTheme.uiFont
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: modelData.subtitle.length > 0
                                        text: modelData.subtitle
                                        color: index === overlay.selectedIndex ? Qt.alpha(menuTheme.groupColor, 0.85) : menuTheme.mutedTextColor
                                        font.pixelSize: Math.max(10, menuTheme.textPx - 1)
                                        font.family: menuTheme.uiFont
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        overlay.selectedIndex = index;
                                        overlay.launchSelected();
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: overlay.results.length === 0
                                text: overlay.query.length
                                    ? overlay.activeModeText("noMatchText", "No matches found")
                                    : overlay.activeModeText("emptyText", "No items found")
                                color: menuTheme.mutedTextColor
                                font.pixelSize: menuTheme.textPx
                                font.family: menuTheme.uiFont
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            hoverEnabled: true

                            onPositionChanged: function(mouse) {
                                const hoveredIndex = resultList.indexAt(mouse.x, mouse.y + resultList.contentY);
                                if (hoveredIndex >= 0) {
                                    overlay.selectedIndex = hoveredIndex;
                                    overlay.clampSelection();
                                }
                            }
                        }
                    }
                }
            }

            Process {
                id: searchProcess

                command: root.launcherController.searchCommand(overlay.activeModeId, overlay.query, overlay.searchLimit)
                running: false
                stdout: StdioCollector {
                    id: searchStdout
                    waitForEnd: true
                }

                onExited: {
                    const completedToken = overlay.inFlightSearchToken;
                    const currentToken = overlay.searchToken();
                    const searchStillCurrent = overlay.activeModeId !== "apps" && completedToken === currentToken;

                    overlay.inFlightSearchToken = "";

                    if (searchStillCurrent) {
                        overlay.parseResults(searchStdout.text);
                    }

                    if (overlay.searchQueued && overlay.activeScreen) {
                        overlay.searchQueued = false;
                        overlay.startSearch();
                        return;
                    }

                    if (overlay.launchQueued && overlay.activeScreen) {
                        if (!searchStillCurrent) {
                            overlay.requestSearch(true);
                            return;
                        }

                        overlay.launchQueued = false;
                        overlay.launchSelected();
                    }
                }
            }

            Timer {
                id: searchTimer
                interval: 60
                repeat: false
                onTriggered: {
                    if (!overlay.activeScreen) {
                        return;
                    }

                    if (searchProcess.running) {
                        overlay.searchQueued = true;
                        return;
                    }

                    overlay.startSearch();
                }
            }

            Timer {
                id: focusTimer
                interval: 40
                repeat: true
                onTriggered: {
                    if (!overlay.visible) {
                        stop();
                        return;
                    }

                    if (searchField.activeFocus) {
                        overlay.pendingFocusAttempts = 0;
                        stop();
                        overlay.requestTabletKeyboard();
                        return;
                    }

                    if (overlay.pendingFocusAttempts <= 0) {
                        stop();
                        return;
                    }

                    overlay.pendingFocusAttempts--;
                    overlay.requestSearchFocus();
                }
            }

            Timer {
                id: delayedFocusTimer
                interval: 120
                repeat: false
                onTriggered: {
                    if (!overlay.visible || searchField.activeFocus) {
                        return;
                    }

                    overlay.pendingFocusAttempts = Math.max(overlay.pendingFocusAttempts, 10);
                    overlay.requestSearchFocus();
                }
            }
        }
    }
}
