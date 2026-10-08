// Portable API fixture only. Actual rounded masking is verified in Quickshell;
// plain qmltestrunner cannot load its statically embedded Widgets plugin.
import QtQuick

Rectangle {
    id: root
    readonly property bool isMockClippingRectangle: true
    property bool contentInsideBorder: true
    property bool contentUnderBorder: false
    readonly property Item contentItem: host
    default property alias content: host.data
    color: "transparent"
    clip: true
    property Item fixtureHost: Item {
        id: host
        parent: root
        anchors.fill: parent
    }
}
