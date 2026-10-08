import QtQuick
Column {
    id: root
    property string pluginId
    property var pluginService: null
    signal settingChanged()
    function saveValue(key,value) {
        if (!pluginService) return;
        pluginService.savePluginData(pluginId,key,value); settingChanged();
    }
    function loadValue(key,fallback) {
        return pluginService ? pluginService.loadPluginData(pluginId,key,fallback) : fallback;
    }
    function reloadChildValues() {
        for (const child of children) if (typeof child.loadValue === "function") child.loadValue();
    }
    onPluginServiceChanged: reloadChildValues()
    Connections {
        target: root.pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId) root.reloadChildValues();
        }
    }
}
