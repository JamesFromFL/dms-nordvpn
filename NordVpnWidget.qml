pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.DCommon.Widgets as D
import qs.Modules.Plugins
import qs.Services
import "." as Nord

PluginComponent {
    id: root
    property var popoutService: null
    readonly property var vpn: Nord.NordVpnService
    property bool retained: false
    Component.onCompleted: { vpn.initializeCache(root.pluginService || PluginService); vpn.retain(); retained = true; }
    Component.onDestruction: { if (retained) vpn.release(); }
    popoutWidth: 880
    popoutHeight: 760
    ccWidgetIcon: vpn.connected ? "verified_user" : "vpn_lock"
    ccWidgetPrimaryText: "NordVPN"
    ccWidgetSecondaryText: vpn.connected ? vpn.status.country : vpn.stateLabel
    ccWidgetIsActive: vpn.connected
    onCcWidgetToggled: { if (!vpn.busy && vpn.ready) { if (vpn.connected) vpn.disconnect(); else vpn.connectTo("", "", ""); } }
    ccDetailHeight: 540

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            width: implicitWidth
            height: root.widgetThickness
            NordVpnIcon {
                objectName: "barIcon"
                size: root.iconSize
                connected: root.vpn.connected
                ready: root.vpn.ready
                iconStyle: root.pluginData.iconStyle || "system"
                connectedColor: root.pluginData.connectedColor || "primary"
                anchors.verticalCenter: parent.verticalCenter
            }
            D.StyledText {
                objectName: "barLabel"
                text: root.vpn.busy ? "NordVPN…" : root.vpn.connected ? root.vpn.status.country : "NordVPN"
                visible: root.pluginData.showLabel !== false
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    verticalBarPill: Component {
        Item {
            width: root.widgetThickness
            height: root.iconSize + Theme.spacingS * 2
            NordVpnIcon {
                objectName: "barIcon"
                anchors.centerIn: parent
                size: root.iconSize
                connected: root.vpn.connected
                ready: root.vpn.ready
                iconStyle: root.pluginData.iconStyle || "system"
                connectedColor: root.pluginData.connectedColor || "primary"
            }
        }
    }
    popoutContent: Component {
        PopoutComponent {
            headerText: ""
            NordVpnPanel { width: parent.width; height: 730; pluginService: root.pluginService; panelLive: root.interactionActive }
        }
    }
    ccDetailContent: Component {
        NordVpnPanel { height: 540; compact: true; pluginService: root.pluginService }
    }
}
