import QtQuick
import QtQuick.Controls
import qs.Common
Item {
    id: root
    property bool checked: false
    property bool toggling: false
    signal toggled(bool checked)
    implicitWidth: 52; implicitHeight: 32
    Rectangle { objectName: "toggleTrack"; anchors.fill: parent; radius: Theme.fullRadius(width,height); color: root.checked ? Theme.primary : Theme.surfaceContainerHigh; border.width: root.checked ? 0 : 2; border.color: Theme.surfaceVariantText }
    Rectangle { objectName: "toggleThumb"; width: root.checked ? 24 : 16; height: width; radius: Theme.fullRadius(width,height); x: root.checked ? parent.width-width-4 : 8; anchors.verticalCenter: parent.verticalCenter; color: root.checked ? Theme.primaryText : Theme.surfaceVariantText }
    MouseArea { anchors.fill: parent; enabled: root.enabled && !root.toggling; onClicked: root.toggled(!root.checked) }
}
