import QtQuick
import qs.Common

Item {
    id: root
    property string name: ""
    property int size: Theme.fontSizeMedium
    property color color: Theme.surfaceText
    property bool filled: false
    implicitWidth: Math.round(size)
    implicitHeight: Math.round(size)
    Text {
        anchors.fill: parent
        text: ({vpn_lock:"◈",verified_user:"◆",refresh:"↻",star:"★",star_border:"☆"})[root.name] || "◈"
        font.pixelSize: root.size
        color: root.color
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
    }
}
