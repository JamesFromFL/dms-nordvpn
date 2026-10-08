pragma Singleton
import QtQuick
QtObject {
    property var values: ({})
    property var stateWrites: []
    signal pluginDataChanged(string id)
    function loadPluginData(id,key,fallback) { return values[key] === undefined ? fallback : values[key]; }
    function savePluginData(id,key,value) { const copy=Object.assign({},values); copy[key]=value; values=copy; pluginDataChanged(id); }
    // Native PluginComponent receives this object from SettingsData.
    function settingsForPlugin(id) { return Object.assign({},values); }
    function loadPluginState(id,key,fallback) { return loadPluginData(id,key,fallback); }
    function savePluginState(id,key,value) {
        stateWrites = stateWrites.concat([{id,key,value}]);
        savePluginData(id,key,value);
    }
}
