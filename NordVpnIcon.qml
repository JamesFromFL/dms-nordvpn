pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.DCommon.Widgets as D

Item {
    id: root

    property int size: 24
    property bool connected: false
    property bool ready: true
    property string iconStyle: "system"
    property string connectedColor: "primary"

    // The supplied artwork is 1540 × 1226. Preserve that aspect even when
    // texture downsampling rounds its pixel dimensions for small bar icons.
    readonly property real logoAspectRatio: 1540 / 1226

    readonly property color color: {
        if (!connected) {
            if (iconStyle === "nordvpn")
                return "#ffffff";
            return ready ? Theme.widgetIconColor : Theme.widgetInactiveIconColor;
        }
        switch (connectedColor) {
        case "secondary": return Theme.secondary;
        case "tertiary": return Theme.tertiary;
        case "success": return Theme.success;
        case "info": return Theme.info;
        case "warning": return Theme.warning;
        case "widgetIconColor": return Theme.widgetIconColor;
        case "primary":
        default: return Theme.primary;
        }
    }

    implicitWidth: size
    implicitHeight: size
    width: implicitWidth
    height: implicitHeight

    D.DIcon {
        objectName: "systemIcon"
        anchors.centerIn: parent
        visible: root.iconStyle !== "nordvpn"
        name: root.connected ? "verified_user" : "vpn_lock"
        size: root.size
        color: root.color
    }

    Loader {
        anchors.fill: parent
        active: root.iconStyle === "nordvpn"

        sourceComponent: Item {
            Image {
                id: logoImage
                objectName: "logoImage"
                anchors.fill: parent
                source: Qt.resolvedUrl("assets/nordvpn.png")
                sourceSize.width: Math.max(1, root.size * 2)
                sourceSize.height: -1
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                cache: true
                visible: false
            }

            ShaderEffect {
                objectName: "nordvpnLogo"
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height * root.logoAspectRatio)
                height: width / root.logoAspectRatio
                property var source: logoImage
                property color tint: root.color
                fragmentShader: Qt.resolvedUrl("shaders/alpha-tint.frag.qsb")
            }
        }
    }
}
