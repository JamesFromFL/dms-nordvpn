// Native theme/policy API fixture; host reparenting and momentum stay in DMS.
import QtQuick
import QtQuick.Controls
import qs.Common

ScrollBar {
    id: root
    property Flickable targetFlickable: null
    property bool allowed: true
    property real topMargin: 0
    property bool _scrollBarActive: false
    property alias hideTimer: hideScrollBarTimer
    readonly property Item scrollTarget: targetFlickable || parent
    readonly property bool scrollable: !!scrollTarget && scrollTarget.contentHeight > scrollTarget.height
    readonly property bool shouldShow: pressed || hovered || active || _scrollBarActive
        || (!!scrollTarget && (scrollTarget.moving || scrollTarget.flicking))
    policy: Theme.scrollbarsEnabled && allowed && scrollable ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    minimumSize: 0.08
    padding: 0
    leftPadding: Theme.scrollbarGap
    rightPadding: Theme.scrollbarGap
    topPadding: Theme.spacingXXS + topMargin
    bottomPadding: Theme.spacingXXS
    interactive: true
    hoverEnabled: true
    visible: policy !== ScrollBar.AlwaysOff && (!!scrollTarget && scrollTarget.visible)
    opacity: policy !== ScrollBar.AlwaysOff && shouldShow ? 1 : 0
    contentItem: Rectangle {
        implicitWidth: Theme.scrollbarThickness
        radius: Theme.fullRadius(width,height)
        color: root.pressed ? Theme.primary : Theme.outline
    }
    background: Item {}
    Timer { id: hideScrollBarTimer; interval: Theme.scrollbarHideDelay; onTriggered: root._scrollBarActive = false }
}
