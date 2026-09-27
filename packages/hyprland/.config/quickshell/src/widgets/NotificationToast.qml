import QtQuick
import Quickshell.Widgets
import "../theme"

Rectangle {
    id: root

    required property QtObject notificationService
    required property var notificationData

    property var theme: null
    Theme { id: fallbackTheme }
    readonly property var t: root.theme || fallbackTheme
    readonly property string appLabel: root.stringValue(root.notificationData ? root.notificationData.appLabel : "")
    readonly property string summaryText: root.stringValue(root.notificationData ? root.notificationData.summary : "")
    readonly property string bodyText: root.stringValue(root.notificationData ? root.notificationData.body : "")
    readonly property string imageSource: root.stringValue(root.notificationData ? root.notificationData.imageSource : "")
    readonly property string iconSource: root.stringValue(root.notificationData ? root.notificationData.iconSource : "")
    readonly property int timeoutMs: root.notificationData ? root.notificationData.timeoutMs : root.t.defaultNotificationTimeoutPx
    readonly property bool persistent: root.notificationData ? root.notificationData.persistent : false
    readonly property bool hasDefaultAction: root.notificationData ? root.notificationData.hasDefaultAction : false
    readonly property bool hovered: cardArea.containsMouse || closeArea.containsMouse
    readonly property color accentStripeColor: {
        if (!root.notificationData) {
            return root.t.accentColor;
        }

        switch (root.notificationData.urgency) {
        case 2:
            return root.t.errorColor;
        case 0:
            return root.t.mutedTextColor;
        default:
            return root.t.accentColor;
        }
    }

    function stringValue(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    width: root.t.notificationWidthPx
    implicitHeight: contentColumn.implicitHeight + (root.t.menuPaddingPx * 2)
    radius: root.t.menuRadiusPx
    color: root.t.groupColor
    border.width: root.t.chipBorderWidthPx
    border.color: root.t.groupBorder

    Rectangle {
        width: root.t.notificationStripeWidthPx
        radius: width / 2
        color: root.accentStripeColor
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: root.t.notificationStripeMarginPx
    }

    MouseArea {
        id: cardArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (root.hasDefaultAction) {
                root.notificationService.invokeDefaultAction(root.notificationData.id);
            } else {
                root.notificationService.dismissNotification(root.notificationData.id);
            }
        }
    }

    Column {
        id: contentColumn

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.t.menuPaddingPx
        anchors.leftMargin: root.t.menuPaddingPx + root.t.notificationContentOffsetPx
        anchors.rightMargin: root.t.menuPaddingPx
        anchors.bottomMargin: root.t.menuPaddingPx
        spacing: root.t.innerGapPx

        Row {
            width: parent.width
            height: Math.max(Math.max(appIcon.implicitHeight, appNameText.implicitHeight), closeButton.height)
            spacing: root.t.innerGapPx

            IconImage {
                id: appIcon

                visible: root.iconSource.length > 0
                width: visible ? root.t.notificationIconSizePx : 0
                height: width
                implicitSize: root.t.notificationIconSizePx
                source: root.iconSource
                asynchronous: true
            }

            Text {
                id: appNameText

                width: parent.width
                    - closeButton.width
                    - (appIcon.visible ? appIcon.width : 0)
                    - (parent.spacing * (appIcon.visible ? 2 : 1))
                text: root.appLabel
                color: root.t.mutedTextColor
                font.pixelSize: Math.max(10, root.t.textPx - 1)
                font.family: root.t.uiFont
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                id: closeButton

                width: root.t.notificationCloseButtonSizePx
                height: root.t.notificationCloseButtonSizePx
                radius: Math.round(width / 2)
                color: closeArea.pressed ? root.t.interactivePressedColor
                    : (closeArea.containsMouse ? root.t.interactiveHoverColor : "transparent")
                border.width: closeArea.containsMouse ? 1 : 0
                border.color: root.t.interactiveBorderColor

                Text {
                    anchors.centerIn: parent
                    text: "x"
                    color: root.t.textColor
                    font.pixelSize: root.t.textPx
                    font.family: root.t.uiFont
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onClicked: function(mouse) {
                        mouse.accepted = true;
                        root.notificationService.dismissNotification(root.notificationData.id);
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: root.summaryText
            visible: root.summaryText.length > 0
            color: root.t.textColor
            font.pixelSize: root.t.textPx + 1
            font.family: root.t.uiFont
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.bodyText
            visible: root.bodyText.length > 0
            color: root.t.mutedTextColor
            font.pixelSize: root.t.textPx
            font.family: root.t.uiFont
            wrapMode: Text.Wrap
            maximumLineCount: 6
            textFormat: Text.RichText
            elide: Text.ElideRight
        }

        Image {
            width: parent.width
            height: root.t.notificationImageHeightPx
            visible: root.imageSource.length > 0
            source: visible ? root.imageSource : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            clip: true
        }
    }

    Timer {
        id: expiryTimer
        interval: root.timeoutMs
        repeat: false
        running: root.visible && !root.persistent && !root.hovered
        onTriggered: root.notificationService.expireNotification(root.notificationData.id)
    }

    property bool revealed: false

    Component.onCompleted: revealed = true

    opacity: revealed ? 1 : 0
    scale: revealed ? 1 : 0.96

    Behavior on scale {
        NumberAnimation { duration: 140 }
    }

    Behavior on opacity {
        NumberAnimation { duration: 140 }
    }

    Behavior on y {
        NumberAnimation { duration: 140 }
    }
}
