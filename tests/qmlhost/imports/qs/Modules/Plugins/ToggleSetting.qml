import QtQuick
import qs.Common
import qs.DCommon.Widgets as D

Row {
    id: root
    property string settingKey
    property string label
    property string description
    property bool defaultValue: false
    property bool value: defaultValue
    property bool isInitialized: false
    spacing: Theme.spacingM
    function settings() {
        for (let item=parent;item;item=item.parent) if (typeof item.saveValue === "function") return item;
        return null;
    }
    function loadValue() {
        const owner = settings();
        if (!owner || !owner.pluginService) return;
        value = owner.loadValue(settingKey,defaultValue); isInitialized = true;
    }
    Component.onCompleted: Qt.callLater(loadValue)
    onValueChanged: { const owner=settings(); if (isInitialized && owner) owner.saveValue(settingKey,value); }
    D.StyledText { text: root.label; font.pixelSize: Theme.fontSizeLarge }
    D.DToggle { checked: root.value; onToggled: value => root.value = value }
}
