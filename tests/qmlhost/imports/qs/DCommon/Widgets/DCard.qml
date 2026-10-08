// API test double: production imports the DMS DCard.
import QtQuick
import qs.Common
Item {
    id: root
    property int pad: Theme.spacingM
    property string tone: ""
    property bool clickable: false
    property bool interactive: true
    signal clicked()
    readonly property color contentColor: tone === "primary" ? Theme.onPrimaryContainer : Theme.surfaceText
    readonly property color mutedColor: tone === "primary" ? Theme.withAlpha(contentColor, 0.72) : Theme.surfaceVariantText
    readonly property color accentColor: tone === "primary" ? contentColor : Theme.primary
    property alias color: surface.color
    property alias radius: surface.radius
    property alias border: surface.border
    property real restRadius: Theme.cornerRadiusM
    property real bodyRadius: restRadius
    readonly property bool floatingWindow: Theme.isFloatingWindow(root)
    readonly property color containerColor: tone === "primary" ? Theme.primaryContainer : Theme.cardSurface
    readonly property color surfaceColor: Theme.foregroundColor(containerColor,floatingWindow)
    default property alias content: host.data
    Rectangle { id: surface; anchors.fill: parent; radius: root.bodyRadius; color: root.surfaceColor; border.width: Theme.layerOutlineWidth; border.color: Theme.outlineMedium }
    MouseArea { anchors.fill: parent; enabled: root.clickable && root.interactive && root.enabled; onClicked: root.clicked() }
    Item { id: host; anchors.fill: parent; anchors.margins: root.pad }
}
