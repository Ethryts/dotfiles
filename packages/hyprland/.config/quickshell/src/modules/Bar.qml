import QtQuick

import Quickshell
import Quickshell.Hyprland
import "../theme"
import "../widgets"
import "../components"
import "../services"

Scope {
    id: root

    required property QtObject calendarController
    required property QtObject launcherController
    required property QtObject quickControlsController
    required property QtObject networkService
    required property QtObject audioService
    required property QtObject brightnessService
    required property QtObject powerProfilesService
    required property QtObject hyprwhisperService

    Theme {
        id: barTheme
    }

    TooltipService {
        id: tooltipService
    }

    // Tablet keyboard management is disabled for the Ubuntu laptop.

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData

            screen: modelData
            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: barTheme.barHeightPx
            color: "transparent"

            readonly property var hyprlandMonitor: Hyprland.monitorFor(modelData)
            readonly property bool fullscreenActive: !!hyprlandMonitor
                && !!hyprlandMonitor.activeWorkspace
                && hyprlandMonitor.activeWorkspace.hasFullscreen

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0.12, 0.12, 0.12, 0.94)
                opacity: bar.fullscreenActive ? 1 : 0
                z: -1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            }

            OverlayHost {
                id: overlayHost
                tooltipController: tooltipService
                quickControlsController: root.quickControlsController
                launcherController: root.launcherController
                calendarController: root.calendarController
                screenModel: bar.modelData
                hostWindow: bar
            }

            HoverHandler {
                id: barHover

                onActiveChanged: {
                    if (!active) {
                        overlayHost.closeTooltip();
                    }
                }
            }

            LeftBarSection {
                id: leftSection
                Chip {
                    HyprlandWorkspaces {
                        screenModel: bar.modelData
                    }
                }

                Chip {
                    Row {
                        spacing: 0

                        CpuUsage {}
                        Temperature {}
                    }
                }
            }

            RightBarSection {
                id: rightSection

                Chip {
                  Row {
                    spacing: 2

                    LauncherButton {
                        overlayHost: overlayHost
                    }
                        Loader {
                            active: bar.modelData
                                && bar.modelData.name === "eDP-1"
                                && PostureService.tabletMode
                            visible: active
                            asynchronous: false
                            width: active && item ? item.implicitWidth : 0
                            height: active && item ? item.implicitHeight : 0
                            sourceComponent: Component {
                                HyprwhisperTabletButton {
                                    hyprwhisperService: root.hyprwhisperService
                                    theme: barTheme
                                }
                            }
                        }
                        Loader {
                            active: bar.modelData
                                && bar.modelData.name === "eDP-1"
                                && PostureService.tabletMode
                            visible: active
                            asynchronous: false
                            width: active && item ? item.implicitWidth : 0
                            height: active && item ? item.implicitHeight : 0
                            sourceComponent: Component {
                                OskToggle {
                                    postureService: PostureService
                                    theme: barTheme
                                }
                            }
                        }
                  }
                }
                Chip {
                    Row {
                        spacing: 0

                        SystemTrayWidget {
                            overlayHost: overlayHost
                            theme: barTheme
                        }
                        Bluetooth {
                            overlayHost: overlayHost
                        }
                        Wifi {
                            overlayHost: overlayHost
                            networkService: root.networkService
                        }
                        Volume {
                            overlayHost: overlayHost
                            audioService: root.audioService
                        }
                        Brightness {
                            overlayHost: overlayHost
                            brightnessService: root.brightnessService
                        }
                        Battery {
                            overlayHost: overlayHost
                            powerProfilesService: root.powerProfilesService
                        }

                    }
                }
            }

            CenterBarSection {
                id: centerSection
                Row {
                    spacing: barTheme.innerGapPx

                    Chip {
                        id: dateChip
                        interactive: true
                        horizontalPadding: 10
                        onClicked: overlayHost.toggleCalendar(dateChip)

                        DateTimeWidget {
                            theme: barTheme
                        }
                    }
                }
            }

            TooltipHost {
                overlayHost: overlayHost
                theme: barTheme
            }
        }
    }
}
