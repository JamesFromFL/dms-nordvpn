import QtQuick
import QtQuick.Controls
import qs.Common
Item {
    id: root
    property var options: []
    property string currentValue: ""
    property bool enableFuzzySearch: false
    property int triggerHeight: Theme.iconButtonSize
    property real triggerRadius: Theme.cornerRadiusXS
    property color backgroundColor: Theme.chipSurface
    property color normalBorderColor: Theme.outlineVariant
    property color focusedBorderColor: Theme.primary
    signal valueChanged(string value)
    implicitWidth: 200; implicitHeight: triggerHeight
    ComboBox {
        anchors.fill: parent
        model: root.options
        currentIndex: Math.max(0, root.options.indexOf(root.currentValue))
        onActivated: index => root.valueChanged(root.options[index])
        background: Rectangle { radius: root.triggerRadius; color: root.backgroundColor; border.width: 1; border.color: root.activeFocus ? root.focusedBorderColor : root.normalBorderColor }
        contentItem: Text { text: root.currentValue; leftPadding: 12; rightPadding: 28; font.family: Theme.fontFamily; font.weight: Theme.fontWeight; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    }
}
