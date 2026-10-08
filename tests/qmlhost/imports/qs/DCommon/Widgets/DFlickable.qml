import QtQuick
import QtQuick.Controls

Flickable {
    id: root
    property alias verticalScrollBar: bar
    property bool showScrollBar: true
    property bool wheelEnabled: true
    property bool isMomentumActive: false
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    function stopMomentum() { cancelFlick(); isMomentumActive = false; }
    ScrollBar.vertical: DScrollbar {
        id: bar
        targetFlickable: root
        allowed: root.showScrollBar
    }
    WheelHandler {
        enabled: root.wheelEnabled
        onWheel: event => {
            root.contentY = Math.max(0, Math.min(root.contentHeight-root.height,
                root.contentY-event.angleDelta.y/120*60));
            bar._scrollBarActive = true; bar.hideTimer.restart();
            event.accepted = true;
        }
    }
}
