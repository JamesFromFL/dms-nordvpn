import QtQuick
import qs.Common
Item {
    id: root
    property string pluginId: "nordVpnControl"
    property var pluginService: null
    property var pluginData: ({})
    property int widgetThickness: 30
    property real barThickness: 48
    property var barConfig: null
    readonly property int iconSize: Theme.barIconSize(barThickness,-4,barConfig?.maximizeWidgetIcons,barConfig?.iconScale)
    readonly property int textSize: Theme.barTextSize(barThickness,barConfig?.fontScale,barConfig?.maximizeWidgetText)
    property bool interactionActive: true
    property int popoutWidth: 400
    property int popoutHeight: 400
    property Component horizontalBarPill
    property Component verticalBarPill
    property Component popoutContent
    property Component ccDetailContent
    property string ccWidgetIcon
    property string ccWidgetPrimaryText
    property string ccWidgetSecondaryText
    property bool ccWidgetIsActive
    property int ccDetailHeight
    signal ccWidgetToggled()
    function loadPluginData() {
        pluginData = pluginService && pluginId ? pluginService.settingsForPlugin(pluginId) : {};
    }
    Component.onCompleted: loadPluginData()
    onPluginServiceChanged: loadPluginData()
    onPluginIdChanged: loadPluginData()
    Connections {
        target: root.pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId) root.loadPluginData();
        }
    }
}
