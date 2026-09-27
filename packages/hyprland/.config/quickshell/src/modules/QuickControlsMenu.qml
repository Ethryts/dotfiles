import QtQuick
import Quickshell
import "../components"
import "../theme"
import "../widgets"

Scope {
    id: root

    required property QtObject quickControlsController
    required property QtObject networkService
    required property QtObject audioService
    required property QtObject brightnessService
    required property QtObject powerProfilesService

    Theme {
        id: menuTheme
    }

    Variants {
        model: Quickshell.screens

        OverlayWindow {
            id: overlay
            required property var modelData

            readonly property int popupWidthPx: Math.max(menuTheme.overlayWidthPx, Math.round(320 * menuTheme.uiScale))
            controller: root.quickControlsController
            screenModel: overlay.modelData
            placement: "anchored"
            horizontalAlignment: "center"
            clampHorizontally: true
            horizontalMargin: menuTheme.contentMarginPx
            verticalOffset: menuTheme.contentMarginPx
            dimBackdrop: true

            Surface {
                id: popupFrame

                width: overlay.popupWidthPx
                theme: menuTheme
                padding: menuTheme.menuPaddingPx
                opacity: overlay.activeScreen ? 1 : 0
                scale: overlay.activeScreen ? 1 : 0.96
                transformOrigin: Item.Top

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 170
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    width: 14
                    height: 14
                    radius: 3
                    x: Math.round((parent.width - width) / 2)
                    y: -7
                    rotation: 45
                    color: menuTheme.groupColor
                    border.width: menuTheme.chipBorderWidthPx
                    border.color: menuTheme.groupBorder
                }

                Item {
                    width: popupFrame.contentWidth
                    implicitHeight: popupLoader.implicitHeight

                    Loader {
                        id: popupLoader
                        width: parent.width
                        sourceComponent: {
                            switch (root.quickControlsController ? root.quickControlsController.kind : "") {
                            case "bluetooth":
                                return bluetoothPanel;
                            case "wifi":
                                return networkPanel;
                            case "volume":
                                return volumePanel;
                            case "brightness":
                                return brightnessPanel;
                            case "battery":
                                return batteryPanel;
                            default:
                                return null;
                            }
                        }
                    }
                }
            }

            Component {
                id: bluetoothPanel

                BluetoothQuickPanel {
                    panelWidth: popupFrame.contentWidth
                    quickControlsController: root.quickControlsController
                    theme: menuTheme
                }
            }

            Component {
                id: networkPanel

                NetworkQuickPanel {
                    panelWidth: popupFrame.contentWidth
                    quickControlsController: root.quickControlsController
                    networkService: root.networkService
                    theme: menuTheme
                }
            }

            Component {
                id: volumePanel

                VolumeQuickPanel {
                    panelWidth: popupFrame.contentWidth
                    quickControlsController: root.quickControlsController
                    audioService: root.audioService
                    theme: menuTheme
                }
            }

            Component {
                id: brightnessPanel

                BrightnessQuickPanel {
                    panelWidth: popupFrame.contentWidth
                    brightnessService: root.brightnessService
                    theme: menuTheme
                }
            }

            Component {
                id: batteryPanel

                BatteryQuickPanel {
                    panelWidth: popupFrame.contentWidth
                    powerProfilesService: root.powerProfilesService
                    theme: menuTheme
                }
            }
        }
    }
}
