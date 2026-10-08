import QtQuick
import QtQuick.Controls

ListView {
    id: root
    property real scrollBarTopMargin: 0
    property bool showScrollBar: true
    property bool isMomentumActive: false
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: DScrollbar {
        id: bar
        targetFlickable: root
        allowed: root.showScrollBar
        topMargin: root.scrollBarTopMargin
    }
    WheelHandler {
        onWheel: event => {
            root.contentY = Math.max(root.originY, Math.min(root.contentHeight-root.height+root.originY,
                root.contentY-event.angleDelta.y/120*60));
            bar._scrollBarActive = true; bar.hideTimer.restart();
            event.accepted = true;
        }
    }
}
