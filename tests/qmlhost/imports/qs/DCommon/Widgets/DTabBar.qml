import QtQuick
import QtQuick.Layouts
import qs.Common
Item {
    id: root
    property var model: []
    property bool showIcons: false
    property int currentIndex: 0
    signal tabClicked(int index)
    implicitHeight: 48
    RowLayout {
        anchors.fill: parent; spacing: 8
        Repeater {
            model: root.model
            DButton {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                text: modelData.text
                backgroundColor: "transparent"
                textColor: index === root.currentIndex ? Theme.primary : Theme.surfaceVariantText
                onClicked: root.tabClicked(index)
                Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: 48; height: 3; radius: 2; color: Theme.primary; visible: parent.index === root.currentIndex }
            }
        }
    }
}
