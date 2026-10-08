import QtQuick
import QtQuick.Controls
import qs.Common
TextField {
    id: root
    property string leftIconName: ""
    property bool showClearButton: false
    property real cornerRadius: Theme.cornerRadiusXS
    property alias radius: surface.radius
    implicitHeight: Theme.fieldHeight
    color: Theme.surfaceText
    placeholderTextColor: Theme.surfaceVariantText
    font.pixelSize: Theme.fontSizeMedium
    font.family: Theme.fontFamily
    font.weight: Theme.fontWeight
    background: Rectangle { id: surface; radius: root.cornerRadius; color: Theme.foregroundColor(Theme.chipSurface,Theme.isFloatingWindow(root)); border.width: 1; border.color: root.activeFocus ? Theme.primary : Theme.outlineVariant }
}
