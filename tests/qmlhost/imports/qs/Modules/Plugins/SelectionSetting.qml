// Native value/label and persistence contract, backed by the portable dropdown.
import QtQuick
import qs.Common
import qs.DCommon.Widgets as D

Column {
    id: root
    required property string settingKey
    required property string label
    property string description: ""
    required property var options
    property string defaultValue: ""
    property string value: defaultValue
    spacing: Theme.spacingS
    function settings() {
        for (let item=parent;item;item=item.parent) if (typeof item.saveValue === "function") return item;
        return null;
    }
    function loadValue() {
        const owner=settings();
        if (owner && owner.pluginService) value=owner.loadValue(settingKey,defaultValue);
    }
    readonly property var optionLabels: options.map(option => option.label || option)
    readonly property var valueToLabel: {
        const labels={}; options.forEach(option => labels[typeof option === "object" ? option.value : option]=option.label || option); return labels;
    }
    readonly property var labelToValue: {
        const values={}; options.forEach(option => values[option.label || option]=typeof option === "object" ? option.value : option); return values;
    }
    Component.onCompleted: loadValue()
    onValueChanged: { const owner=settings(); if (owner) owner.saveValue(settingKey,value); }
    D.StyledText { text: root.label; font.pixelSize: Theme.fontSizeLarge }
    D.StyledText { text: root.description; font.pixelSize: Theme.fontSizeSmall; visible: !!text }
    D.DDropdown {
        objectName: root.objectName+"Control"
        options: root.optionLabels
        currentValue: root.valueToLabel[root.value] || root.value
        onValueChanged: value => root.value=root.labelToValue[value] || value
    }
}
