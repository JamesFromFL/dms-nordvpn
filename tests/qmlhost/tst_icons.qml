import QtQuick
import QtTest
import qs.Common
import qs.Services
import Quickshell.Io
import "../.." as Nord

TestCase {
    id: tests
    name: "NordVpnIconPreferences"
    when: windowShown
    visible: true
    width: 520; height: 180
    property var widget
    property var preferences
    property var horizontal
    property var vertical
    property Component widgetComponent: Component { Nord.NordVpnWidget { pluginService: PluginService } }
    property Component settingsComponent: Component { Nord.Settings { width: 500; pluginService: PluginService } }
    property Component iconComponent: Component { Nord.NordVpnIcon {} }
    function child(parent,name) {
        const item=findChild(parent,name); verify(item!==null,"Missing icon/settings item " + name); return item;
    }
    function bars() { return [child(horizontal,"barIcon"),child(vertical,"barIcon")]; }
    function logo(parent) {
        tryVerify(() => findChild(parent,"nordvpnLogo")!==null,1000,"Nord artwork loads on demand");
        return child(parent,"nordvpnLogo");
    }
    function selectSetting(name,value) {
        const setting=child(preferences,name);
        const option=setting.options.find(option => option.value===value);
        verify(option!==undefined,"Missing preference option " + value);
        // Exercise the same label-to-value callback as a dropdown selection.
        child(setting,name+"Control").valueChanged(option.label);
        compare(setting.value,value);
    }
    function initTestCase() {
        Nord.NordVpnService.preloadIntervalMs=3600000;
        widget=widgetComponent.createObject(tests);
        preferences=settingsComponent.createObject(tests,{visible:false});
        horizontal=widget.horizontalBarPill.createObject(tests,{x:12,y:16});
        vertical=widget.verticalBarPill.createObject(tests,{x:460,y:16});
        verify(widget!==null && preferences!==null && horizontal!==null && vertical!==null);
        tryVerify(() => Nord.NordVpnService.ready,3000);
    }
    function init() {
        Theme.palette={};
        Nord.NordVpnService.status={state:"disconnected"};
        PluginService.savePluginData("nordVpnControl","iconStyle","system");
        PluginService.savePluginData("nordVpnControl","connectedColor","primary");
        PluginService.savePluginData("nordVpnControl","showLabel",true);
    }
    function cleanup() {
        compare(TransportState.actionCount,0,"Appearance preferences must never issue a VPN action");
        Theme.palette={};
        Theme.fontScale=1; preferences.width=500;
    }
    function cleanupTestCase() {
        horizontal.destroy(); vertical.destroy(); preferences.destroy(); widget.destroy();
    }
    function test_01_defaults_and_invalid_saved_values_have_safe_fallbacks() {
        compare(child(preferences,"iconStyleSetting").defaultValue,"system");
        compare(child(preferences,"connectedColorSetting").defaultValue,"primary");
        bars().forEach(icon => {
            compare(icon.iconStyle,"system"); compare(icon.connectedColor,"primary");
            compare(icon.color,Theme.widgetIconColor);
            verify(child(icon,"systemIcon").visible);
        });
        const standalone=createTemporaryObject(iconComponent,tests,{connected:true,iconStyle:"unsupported",connectedColor:"unsupported"});
        verify(standalone!==null);
        compare(standalone.color,Theme.primary); verify(child(standalone,"systemIcon").visible);
        compare(findChild(standalone,"nordvpnLogo"),null,"The system style must not load a logo texture/shader");
        PluginService.savePluginData("nordVpnControl","iconStyle","unsupported");
        PluginService.savePluginData("nordVpnControl","connectedColor","unsupported");
        Nord.NordVpnService.status={state:"connected",country:"United States"};
        bars().forEach(icon => {
            verify(child(icon,"systemIcon").visible); compare(icon.color,Theme.primary);
        });
    }
    function test_02_settings_save_and_update_both_existing_bar_orientations() {
        const original=bars();
        const disconnected=child(preferences,"disconnectedIconPreview"), connected=child(preferences,"connectedIconPreview");
        selectSetting("iconStyleSetting","nordvpn");
        selectSetting("connectedColorSetting","secondary");
        compare(PluginService.loadPluginData("nordVpnControl","iconStyle",null),"nordvpn");
        compare(PluginService.loadPluginData("nordVpnControl","connectedColor",null),"secondary");
        compare(disconnected.iconStyle,"nordvpn"); compare(connected.iconStyle,"nordvpn");
        compare(disconnected.color,Qt.rgba(1,1,1,1)); compare(connected.color,Theme.secondary);
        bars().forEach((icon,index) => {
            compare(icon,original[index],"A settings change must update the existing bar icon");
            compare(icon.iconStyle,"nordvpn"); compare(icon.connectedColor,"secondary");
            verify(logo(icon).visible); verify(!child(icon,"systemIcon").visible);
        });
        selectSetting("iconStyleSetting","system");
        compare(child(preferences,"disconnectedIconPreview"),disconnected);
        compare(child(preferences,"connectedIconPreview"),connected);
        compare(disconnected.iconStyle,"system"); compare(connected.iconStyle,"system");
        bars().forEach((icon,index) => { compare(icon,original[index]); verify(child(icon,"systemIcon").visible); });
    }
    function test_03_nordvpn_logo_is_pure_white_without_a_confirmed_connection() {
        selectSetting("iconStyleSetting","nordvpn");
        selectSetting("connectedColorSetting","warning");
        Theme.palette={primary:"#118822",widgetIconColor:"#334455",widgetInactiveIconColor:"#667788",warning:"#ffee00"};
        for (const state of ["disconnected","unknown","connecting","paused"]) {
            Nord.NordVpnService.status={state};
            bars().forEach(icon => compare(icon.color,Qt.rgba(1,1,1,1),"Disconnected Nord artwork must stay white"));
        }
    }
    function test_04_selected_connected_role_tracks_live_theme_changes_in_both_bars() {
        Nord.NordVpnService.status={state:"connected",country:"United States"};
        for (const style of ["system","nordvpn"]) {
            selectSetting("iconStyleSetting",style);
            const original=bars();
            for (const role of ["primary","secondary","tertiary","success","info","warning","widgetIconColor"]) {
                selectSetting("connectedColorSetting",role);
                let palette={}; palette[role]="#e8a34b"; Theme.palette=palette;
                bars().forEach((icon,index) => { compare(icon,original[index]); compare(icon.color,Theme[role]); });
                palette=Object.assign({},palette); palette[role]="#37a6c2"; Theme.palette=palette;
                bars().forEach(icon => compare(icon.color,Theme[role],"The saved role must resolve the new live color"));
                compare(child(preferences,"connectedIconPreview").color,Theme[role]);
            }
        }
    }
    function test_05_recreated_preferences_and_widget_restore_the_saved_choices() {
        selectSetting("iconStyleSetting","nordvpn"); selectSetting("connectedColorSetting","success");
        const restoredSettings=createTemporaryObject(settingsComponent,tests,{visible:false});
        const restoredWidget=createTemporaryObject(widgetComponent,tests);
        verify(restoredSettings!==null && restoredWidget!==null);
        tryCompare(child(restoredSettings,"iconStyleSetting"),"value","nordvpn");
        tryCompare(child(restoredSettings,"connectedColorSetting"),"value","success");
        compare(child(restoredSettings,"iconStyleSetting").value,"nordvpn");
        compare(child(restoredSettings,"connectedColorSetting").value,"success");
        const restoredBar=restoredWidget.horizontalBarPill.createObject(tests,{y:80});
        try {
            const icon=child(restoredBar,"barIcon");
            compare(icon.iconStyle,"nordvpn"); compare(icon.connectedColor,"success");
        } finally { restoredBar.destroy(); }
    }
    function test_06_icon_only_preference_and_host_sizing_remain_live() {
        const label=child(horizontal,"barLabel"), original=bars();
        const showLabel=preferences.children.find(item => item.settingKey==="showLabel");
        verify(showLabel!==undefined); showLabel.value=false;
        compare(PluginService.loadPluginData("nordVpnControl","showLabel",true),false);
        compare(label.visible,false);
        for (const style of ["system","nordvpn"]) {
            selectSetting("iconStyleSetting",style);
            bars().forEach((icon,index) => {
                compare(icon,original[index]); compare(icon.size,widget.iconSize);
                compare(icon.width,widget.iconSize); compare(icon.height,widget.iconSize);
            });
            tryCompare(horizontal,"width",widget.iconSize);
        }
        showLabel.value=true; compare(label.visible,true);
        tryVerify(() => horizontal.width>widget.iconSize);
        const previewGrid=child(preferences,"iconPreviewGrid");
        compare(previewGrid.columns,2);
        Theme.fontScale=1.6; preferences.width=180;
        tryCompare(previewGrid,"columns",1);
        const card=child(preferences,"iconPreviewCard"), content=child(preferences,"iconPreviewContent");
        tryVerify(() => card.height>=content.height+card.pad*2);
        Theme.fontScale=1; preferences.width=500;
    }
}
