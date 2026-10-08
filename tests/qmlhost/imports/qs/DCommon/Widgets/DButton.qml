import QtQuick
import QtQuick.Controls
import qs.Common
Button {
    id: root
    property string iconName: ""
    property bool busy: false
    property color backgroundColor: Theme.buttonBg
    property color textColor: Theme.buttonText
    property int buttonHeight: Theme.buttonHeightS
    property string shape: "round"
    property bool wrapText: false
    property alias radius: surface.radius
    implicitHeight: wrapText ? Math.max(buttonHeight, label.implicitHeight + Theme.spacingS * 2) : buttonHeight
    implicitWidth: Math.max(80, label.implicitWidth + 48)
    background: Rectangle { id: surface; radius: Theme.buttonRadius(root.width, root.height, root.buttonHeight, root.pressed, root.shape === "round"); color: root.enabled ? root.backgroundColor : Theme.withAlpha(Theme.surfaceText, 0.12) }
    contentItem: Text { id: label; text: root.text; color: root.enabled ? root.textColor : Theme.withAlpha(Theme.surfaceText, 0.38); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMedium; font.weight: Theme.fontWeightMedium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
}
