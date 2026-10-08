import QtQuick
import qs.Common
import qs.DCommon.Widgets as D
import qs.Modules.Plugins

PluginSettings {
    pluginId: "nordVpnControl"

    SelectionSetting {
        id: iconStyleChoice
        objectName: "iconStyleSetting"
        settingKey: "iconStyle"
        label: "Bar icon style"
        description: "Use the VPN and connected shield icons, or the NordVPN logo."
        defaultValue: "system"
        options: [
            { label: "VPN / shield", value: "system" },
            { label: "NordVPN logo", value: "nordvpn" }
        ]
    }

    SelectionSetting {
        id: connectedColorChoice
        objectName: "connectedColorSetting"
        settingKey: "connectedColor"
        label: "Connected icon color"
        description: "Choose a DMS theme color for the connected icon."
        defaultValue: "primary"
        options: [
            { label: "Primary", value: "primary" },
            { label: "Secondary", value: "secondary" },
            { label: "Tertiary", value: "tertiary" },
            { label: "Success", value: "success" },
            { label: "Information", value: "info" },
            { label: "Warning", value: "warning" },
            { label: "Bar icon color", value: "widgetIconColor" }
        ]
    }

    D.DCard {
        id: iconPreviewCard
        objectName: "iconPreviewCard"
        width: parent.width
        height: previewContent.implicitHeight + pad * 2
        Accessible.name: "Icon preview"

        FontMetrics {
            id: previewFontMetrics
            font: disconnectedPreviewLabel.font
        }

        Column {
            id: previewContent
            objectName: "iconPreviewContent"
            width: parent.width
            spacing: Theme.spacingM

            D.StyledText {
                text: "Icon preview"
                width: parent.width
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: iconPreviewCard.contentColor
            }

            Grid {
                id: previewGrid
                objectName: "iconPreviewGrid"
                width: parent.width
                columns: width >= previewFontMetrics.advanceWidth("Disconnected") * 2 + spacing ? 2 : 1
                spacing: Theme.spacingM

                Column {
                    width: (previewGrid.width - (previewGrid.columns - 1) * previewGrid.spacing) / previewGrid.columns
                    spacing: Theme.spacingS

                    NordVpnIcon {
                        objectName: "disconnectedIconPreview"
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: Theme.iconSizeLarge
                        connected: false
                        iconStyle: iconStyleChoice.value
                        connectedColor: connectedColorChoice.value
                    }

                    D.StyledText {
                        id: disconnectedPreviewLabel
                        objectName: "disconnectedPreviewLabel"
                        text: "Disconnected"
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeMedium
                        color: iconPreviewCard.mutedColor
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                }

                Column {
                    width: (previewGrid.width - (previewGrid.columns - 1) * previewGrid.spacing) / previewGrid.columns
                    spacing: Theme.spacingS

                    NordVpnIcon {
                        objectName: "connectedIconPreview"
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: Theme.iconSizeLarge
                        connected: true
                        iconStyle: iconStyleChoice.value
                        connectedColor: connectedColorChoice.value
                    }

                    D.StyledText {
                        objectName: "connectedPreviewLabel"
                        text: "Connected"
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeMedium
                        color: iconPreviewCard.mutedColor
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                }
            }
        }
    }

    ToggleSetting {
        objectName: "showLabelSetting"
        settingKey: "showLabel"
        label: "Show location in the bar"
        description: "Show the connected country beside the icon. Turn off for a compact status icon you can place beside Control Center."
        defaultValue: true
    }
}
