import QtQuick
import QtQuick.Controls
import qs.Common
Button {
    id: root
    property string iconName: ""
    property int iconSize: 24
    property color iconColor: variant === "tonal" ? Theme.primaryContainerText : Theme.surfaceVariantText
    property string variant: "standard"
    property color backgroundColor: root.variant === "tonal" ? Theme.primaryContainer : "transparent"
    property var tooltipText: ""
    property bool round: true
    property alias radius: surface.radius
    implicitWidth: 40; implicitHeight: 40
    background: Rectangle { id: surface; color: root.backgroundColor; radius: Theme.buttonRadius(root.width, root.height, root.height, root.pressed, root.round) }
    contentItem: Text { text: root.iconName ? ({add:"+",remove:"−",public:"◎",location_on:"●",radio_button_checked:"◉",refresh:"↻",star:"★",star_border:"☆"})[root.iconName] || "◈" : ""; color: root.enabled ? root.iconColor : Theme.withAlpha(root.iconColor,0.38); font.pixelSize: root.iconSize; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
}
