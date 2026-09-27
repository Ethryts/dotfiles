import QtQuick
import QtQuick.Controls
import "../theme"

Item {
    id: root

    property var theme: null
    property string title: ""
    property string subtitle: ""
    property var model: []
    property int currentIndex: -1
    property bool enabled: true
    property string placeholderText: ""
    signal activated(int index, var item)

    Theme { id: fallbackTheme }

    readonly property var t: root.theme || fallbackTheme
    readonly property var comboModel: Array.isArray(root.model) ? root.model : []

    implicitWidth: parent ? parent.width : 280
    implicitHeight: contentColumn.implicitHeight

    Column {
        id: contentColumn
        width: parent.width
        spacing: 8

        Column {
            width: parent.width
            spacing: subtitleLabel.visible ? 2 : 0

            Text {
                width: parent.width
                text: root.title
                color: root.t.textColor
                font.pixelSize: root.t.textPx
                font.family: root.t.uiFont
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                id: subtitleLabel
                width: parent.width
                visible: text.length > 0
                text: root.subtitle
                color: root.t.mutedTextColor
                font.pixelSize: Math.max(11, root.t.textPx - 1)
                font.family: root.t.uiFont
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        ComboBox {
            id: combo
            width: parent.width
            model: root.comboModel
            textRole: "label"
            currentIndex: root.currentIndex
            enabled: root.enabled
            implicitHeight: Math.max(34, Math.round(36 * root.t.uiScale))
            leftPadding: 10
            rightPadding: 28
            topPadding: 6
            bottomPadding: 6

            onActivated: function(index) {
                if (index >= 0 && index < root.comboModel.length) {
                    root.activated(index, root.comboModel[index]);
                }
            }

            delegate: ItemDelegate {
                required property var modelData
                required property int index
                width: combo.width
                implicitHeight: Math.max(32, Math.round(34 * root.t.uiScale))
                highlighted: combo.highlightedIndex === index
                padding: 0

                contentItem: Item {
                    implicitHeight: parent.implicitHeight

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData && modelData.label ? modelData.label : ""
                        color: root.t.textColor
                        font.pixelSize: root.t.textPx
                        font.family: root.t.uiFont
                        font.bold: modelData && modelData.active
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }

                background: Rectangle {
                    color: parent.highlighted ? root.t.interactiveHoverColor : "transparent"
                    radius: Math.max(6, root.t.chipRadiusPx - 2)
                }
            }

            indicator: Text {
                x: combo.width - width - 10
                anchors.verticalCenter: parent.verticalCenter
                text: "v"
                color: combo.enabled ? root.t.mutedTextColor : root.t.groupBorder
                font.pixelSize: root.t.textPx
                font.family: root.t.uiFont
            }

            contentItem: Item {
                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 0
                    anchors.rightMargin: 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: combo.currentIndex >= 0 ? combo.displayText : root.placeholderText
                    color: combo.enabled
                        ? root.t.textColor
                        : (root.placeholderText.length > 0 ? root.t.mutedTextColor : root.t.groupBorder)
                    font.pixelSize: root.t.textPx
                    font.family: root.t.uiFont
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            background: Rectangle {
                radius: Math.max(6, root.t.chipRadiusPx - 1)
                color: combo.enabled ? root.t.chipColor : "transparent"
                border.width: 1
                border.color: combo.visualFocus ? root.t.accentColor : root.t.groupBorder
                opacity: combo.enabled ? 1 : 0.6

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
            }

            popup: Popup {
                y: combo.height + 6
                width: combo.width
                padding: 4
                implicitHeight: Math.min(contentItem.implicitHeight + (padding * 2), Math.round(220 * root.t.uiScale))

                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: combo.popup.visible ? combo.delegateModel : null
                    currentIndex: combo.highlightedIndex
                }

                background: Rectangle {
                    radius: Math.max(6, root.t.chipRadiusPx)
                    color: root.t.groupColor
                    border.width: 1
                    border.color: root.t.groupBorder
                }
            }
        }
    }
}
