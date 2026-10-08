pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as D

D.DIconButton {
    id: root
    objectName: marker.kind + ":" + (marker.country || "") + ":" + (marker.city || "")
    property var marker: ({kind:"country",count:1,label:"",tooltip:"",code:""})
    property bool selected: false
    property bool active: false
    property bool labelVisible: false
    property bool compactOverview: false
    property real viewportWidth: 0
    property real viewportHeight: 0
    readonly property bool bubble: marker.kind !== "city"
    readonly property bool countryDot: compactOverview && marker.kind === "country"
    width: countryDot ? 18 : bubble ? Math.max(compactOverview ? 26 : 32, glyph.width) : 34
    height: width
    iconName: ""
    variant: "standard"
    backgroundColor: "transparent"
    tooltipText: marker.tooltip
    Accessible.name: marker.tooltip
    Rectangle {
        id: glyph
        objectName: "markerGlyph"
        anchors.centerIn: parent
        width: root.countryDot ? 10 : root.bubble ? Math.max(root.compactOverview ? 26 : root.marker.kind === "cluster" ? 32 : 28,
            count.implicitWidth + Theme.spacingXS * 2, count.implicitHeight + Theme.spacingXXS * 2) : root.selected || root.active ? 16 : 12
        height: width
        radius: width / 2
        color: root.selected || root.countryDot ? Theme.primary : root.bubble ? Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root)) : Theme.primary
        border.width: root.active ? 3 : root.bubble ? 1 : 2
        border.color: root.active ? Theme.primary : root.countryDot ? Theme.surfaceContainerHigh : root.bubble ? Theme.withAlpha(Theme.surfaceVariantText,0.65) : Theme.surfaceContainerHigh
        StyledText {
            id: count
            objectName: "markerCountText"
            anchors.centerIn: parent
            visible: root.bubble && !root.countryDot
            text: root.marker.kind === "cluster" ? root.marker.count : root.marker.code
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: root.selected ? Theme.primaryText : Theme.surfaceText
        }
    }
    Rectangle {
        id: labelBox
        objectName: "markerLabelBox"
        // Keep hover/selected labels inside the map, including markers near an edge.
        x:Math.max(Theme.spacingXS-root.x,Math.min(root.viewportWidth-Theme.spacingXS-root.x-width,(root.width-width)/2))
        y:root.y+root.height+Theme.spacingXXS+height<=root.viewportHeight-Theme.spacingXS ? root.height+Theme.spacingXXS : -height-Theme.spacingXXS
        implicitWidth: label.implicitWidth + Theme.spacingS * 2
        width: root.viewportWidth > 0 ? Math.min(implicitWidth, Math.max(0, root.viewportWidth - Theme.spacingXS * 2)) : implicitWidth
        height: label.implicitHeight + Theme.spacingXS * 2
        radius: Theme.cornerRadiusS
        color: Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        visible: root.labelVisible || (root.selected && root.marker.kind === "city")
        StyledText {
            id: label
            objectName: "markerLabelText"
            anchors.centerIn: parent
            width: Math.max(0, parent.width - Theme.spacingS * 2)
            text: root.marker.label
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.NoWrap
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
