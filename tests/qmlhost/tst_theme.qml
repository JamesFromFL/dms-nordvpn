import QtQuick
import QtQuick.Controls as Controls
import QtTest
import qs.Common
import Quickshell.Io
import "../.." as Nord

TestCase {
    id: tests
    name: "NordVpnLiveTheme"
    when: windowShown
    visible: true
    width: 880
    height: 780
    property var panel
    property var widget
    property var horizontalPill
    property var verticalPill
    property Component panelComponent: Component {
        Nord.NordVpnPanel {
            width: 880; height: 730
            property bool isFloatingWindowSurface: false
            Rectangle { anchors.fill: parent; color: Theme.lightMode ? "#f9f9f9" : "#131313"; z: -1 }
        }
    }
    property Component widgetComponent: Component { Nord.NordVpnWidget {} }

    function child(parent, name) {
        const item = findChild(parent,name);
        verify(item !== null,"Missing themed item " + name);
        return item;
    }
    function idle() {
        tryVerify(() => !Nord.NordVpnService.current && Nord.NordVpnService.queue.length === 0,5000);
    }
    function settleMap() { wait(200); idle(); wait(100); }
    function resetTheme() {
        Theme.palette = {}; Theme.lightMode = false;
        Theme.cornerRadius = 12; Theme.fixedRadius = -1;
        Theme.fontFamily = "DejaVu Sans"; Theme.fontScale = 1; Theme.fontWeight = Font.Normal;
        Theme.foregroundAlpha = 1; Theme.floatingWindowForegroundAlpha = 1;
        Theme.layerOutlineOpacity = 0.16; Theme.buttonColorMode = "primary";
        Theme.scrollbarsEnabled = true;
    }
    function initTestCase() {
        Nord.NordVpnService.preloadIntervalMs = 3600000;
        TransportState.connected = true;
        panel = panelComponent.createObject(tests);
        widget = widgetComponent.createObject(tests);
        verify(panel !== null && widget !== null);
        horizontalPill = widget.horizontalBarPill.createObject(tests,{x:12,y:742});
        verticalPill = widget.verticalBarPill.createObject(tests,{x:800,y:742});
        verify(horizontalPill !== null && verticalPill !== null);
        tryVerify(() => Nord.NordVpnService.ready && Nord.NordVpnService.countries.length === 150,5000);
        panel.selectCountry("United_States"); idle(); panel.selectCity("Miami");
    }
    function init() {
        resetTheme(); panel.height = 730; panel.compact = false;
        panel.isFloatingWindowSurface = false; panel.tabIndex = 0;
        child(panel,"countrySearch").text = "";
        panel.mapView.focusRegion("Florida"); settleMap();
    }
    function cleanup() { resetTheme(); panel.isFloatingWindowSurface = false; idle(); }
    function cleanupTestCase() {
        horizontalPill.destroy(); verticalPill.destroy(); widget.destroy(); panel.destroy();
    }
    function test_01_square_and_rounded_settings_update_existing_controls() {
        const map = panel.mapView, status = child(panel,"statusCard"), destination = child(panel,"destinationCard");
        const miami = child(map,"city:United_States:Miami"), label = child(miami,"markerLabelBox"), legend = child(map,"mapLegend");
        const connect = child(panel,"connectButton"), search = child(panel,"countrySearch"), dns = child(panel,"dnsInput");
        for (const radius of [0,12,24,64]) {
            Theme.cornerRadius = radius; wait(80);
            compare(panel.mapView,map); compare(child(map,"city:United_States:Miami"),miami);
            compare(map.radius,Theme.cornerRadiusM); compare(status.radius,Theme.cornerRadiusM);
            compare(destination.radius,Theme.cornerRadiusM);
            compare(label.radius,Theme.cornerRadiusS); compare(legend.radius,Theme.cornerRadiusS);
            compare(connect.radius,Theme.fullRadius(connect.width,connect.height));
            compare(search.radius,Theme.cornerRadiusXS); compare(dns.radius,Theme.cornerRadiusXS);
            const effectiveRadius = Math.min(map.radius,map.width/2,map.height/2);
            const inset = Math.max(Theme.spacingS,effectiveRadius*(1-Math.SQRT1_2)+map.border.width);
            fuzzyCompare(map.overlayInset,inset,0.000001);
            fuzzyCompare(legend.x,inset,0.000001);
            fuzzyCompare(legend.y+legend.height,map.height-inset,0.000001);
            verify(legend.width <= map.width-inset*2+0.000001);
            const track = child(panel,"toggleTrack");
            compare(track.radius,Theme.fullRadius(track.width,track.height));
        }
        // Fixed-radius mode must reach both rectangular controls and round buttons.
        Theme.fixedRadius = 5; wait(80);
        compare(map.radius,5); compare(label.radius,5); compare(search.radius,5); compare(connect.radius,5);
    }
    function test_02_live_fonts_scale_content_and_preserve_geographic_controls() {
        const map = panel.mapView, miami = child(map,"city:United_States:Miami");
        const label = child(miami,"markerLabelText"), box = child(miami,"markerLabelBox");
        const oldWidth = box.implicitWidth;
        const title = child(panel,"panelTitle"), status = child(panel,"statusTitle"), details = child(panel,"statusDetails");
        const destination = child(panel,"destinationLabel"), legend = child(map,"mapLegendText");
        const search = child(panel,"countrySearch"), dns = child(panel,"dnsInput"), button = child(panel,"connectButton");
        const barLabel = child(horizontalPill,"barLabel");
        const oldCache = map.labelWidthCache;
        Theme.fontFamily = "DejaVu Serif"; Theme.fontScale = 1.6; Theme.fontWeight = Font.Medium;
        wait(250);
        compare(child(map,"city:United_States:Miami"),miami,"Theme updates must keep the existing target control");
        [title,status,details,destination,legend,label,barLabel].forEach(item => compare(item.font.family,Theme.fontFamily));
        compare(title.font.pixelSize,Theme.fontSizeXLarge); compare(status.font.pixelSize,Theme.fontSizeLarge);
        compare(details.font.pixelSize,Theme.fontSizeSmall); compare(destination.font.pixelSize,Theme.fontSizeMedium);
        compare(label.font.pixelSize,Theme.fontSizeSmall); compare(legend.font.pixelSize,Theme.fontSizeSmall);
        compare(barLabel.font.pixelSize,widget.textSize);
        compare(search.font.family,Theme.fontFamily); compare(dns.font.family,Theme.fontFamily);
        compare(search.font.pixelSize,Theme.fontSizeMedium); compare(dns.font.pixelSize,Theme.fontSizeMedium);
        compare(button.contentItem.font.family,Theme.fontFamily); compare(button.contentItem.font.pixelSize,Theme.fontSizeMedium);
        compare(status.font.weight,Theme.fontWeightMedium);
        verify(box.implicitWidth > oldWidth,"Marker labels must measure the scaled font");
        verify(map.labelWidthCache !== oldCache,"Collision measurements must discard the previous font's cached widths");
        fuzzyCompare(miami.x+miami.width/2,map.screenX(-80.1938889),0.00001);
        fuzzyCompare(miami.y+miami.height/2,map.screenY(25.7738889),0.00001);
        const position = box.mapToItem(map,0,0);
        verify(position.x >= -0.01 && position.x+box.width <= map.width+0.01);
        verify(position.y >= -0.01 && position.y+box.height <= map.height+0.01);
    }
    function test_03_independent_surface_button_widget_and_outline_roles_update_live() {
        const map = panel.mapView, miami = child(map,"city:United_States:Miami");
        const box = child(miami,"markerLabelBox"), label = child(miami,"markerLabelText"), legend = child(map,"mapLegend");
        const destination = child(panel,"destinationCard"), button = child(panel,"connectButton");
        const status = child(panel,"statusCard"), statusText = child(panel,"statusTitle");
        Theme.palette = {primary:"#f0d17a",primaryText:"#332400",primaryContainer:"#483923",primaryContainerText:"#fff0cc",
            surfaceContainer:"#272227",surfaceContainerHigh:"#332c34",surfaceText:"#fff5f9",surfaceVariantText:"#dac2d3",
            cardSurface:"#20352c",chipSurface:"#4a3047",outline:"#ce96b7",
            widgetIconColor:"#73e8c7",widgetInactiveIconColor:"#78869c",widgetTextColor:"#ffe09b"};
        Theme.buttonColorMode = "primaryContainer"; Theme.foregroundAlpha = 0.72; Theme.layerOutlineOpacity = 0.6;
        wait(100);
        compare(map.color,Theme.foregroundColor(Theme.cardSurface,false));
        compare(child(map,"mapGeometry").mapSurfaceColor,map.color,
            "Map erase masks must follow the actual themed map surface");
        compare(destination.color,Theme.foregroundColor(Theme.cardSurface,false));
        compare(box.color,Theme.foregroundColor(Theme.chipSurface,false));
        compare(legend.color,Theme.foregroundColor(Theme.chipSurface,false));
        compare(label.color,Theme.surfaceText); compare(child(map,"mapLegendText").color,Theme.surfaceVariantText);
        compare(status.color,Theme.foregroundColor(Theme.primaryContainer,false)); compare(statusText.color,Theme.primaryContainerText);
        compare(button.backgroundColor,Theme.buttonBg); compare(button.textColor,Theme.buttonText);
        compare(button.background.color,Theme.buttonBg);
        compare(child(horizontalPill,"barLabel").color,Theme.widgetTextColor);
        compare(child(horizontalPill,"barIcon").color,Theme.primary);
        compare(map.border.color,Theme.outlineMedium); compare(box.border.color,Theme.outlineMedium);
        Theme.floatingWindowForegroundAlpha = 0.94; panel.isFloatingWindowSurface = true;
        wait(80);
        compare(map.color,Theme.foregroundColor(Theme.cardSurface,true));
        compare(destination.color,Theme.foregroundColor(Theme.cardSurface,true));
        compare(box.color,Theme.foregroundColor(Theme.chipSurface,true));
        Theme.layerOutlineOpacity = 0; wait(80);
        compare(map.border.width,0); compare(box.border.width,0); compare(legend.border.width,0);
        compare(destination.border.width,0);
        const saved = Nord.NordVpnService.status;
        try {
            Nord.NordVpnService.status = {state:"disconnected"};
            compare(child(horizontalPill,"barIcon").color,Theme.widgetIconColor);
            compare(child(verticalPill,"barIcon").color,Theme.widgetIconColor);
            Nord.NordVpnService.status = {state:"unknown"};
            compare(child(horizontalPill,"barIcon").color,Theme.widgetInactiveIconColor);
        } finally { Nord.NordVpnService.status = saved; }
    }
    function test_04_native_scrollbars_follow_target_theme_and_visibility() {
        const list = child(panel,"countryList"), countries = child(panel,"countryScrollbar");
        const settings = child(panel,"settingsScroll"), settingsBar = child(panel,"settingsScrollbar");
        compare(countries.targetFlickable,list); compare(settingsBar.targetFlickable,settings);
        panel.tabIndex = 1; wait(100);
        verify(list.contentHeight > list.height); compare(countries.policy,Controls.ScrollBar.AsNeeded);
        Theme.palette = {outline:"#cc8899",primary:"#99eedd"};
        Theme.cornerRadius = 0; wait(80);
        compare(countries.contentItem.color,Theme.outline); compare(countries.contentItem.radius,0);
        const before = list.contentY;
        mouseWheel(list,list.width/2,list.height/2,0,-120); wait(80);
        verify(list.contentY > before,"Location scrolling must remain functional with the DMS scrollbar wrapper");
        verify(countries.opacity > 0,"Wheel interaction must reveal the native scrollbar");
        mousePress(countries,countries.contentItem.x+countries.contentItem.width/2,
            countries.contentItem.y+countries.contentItem.height/2);
        try {
            compare(countries.pressed,true); compare(countries.contentItem.color,Theme.primary);
        } finally { mouseRelease(countries); }
        Theme.scrollbarsEnabled = false; compare(countries.policy,Controls.ScrollBar.AlwaysOff);
        Theme.scrollbarsEnabled = true; Theme.cornerRadius = 12;
        panel.height = 540; // Deliberately require settings overflow regardless of available CLI capabilities.
        panel.tabIndex = 2; wait(100);
        verify(settings.contentHeight > settings.height); compare(settingsBar.policy,Controls.ScrollBar.AsNeeded);
        compare(settingsBar.contentItem.color,Theme.outline);
        compare(settingsBar.contentItem.radius,Theme.fullRadius(settingsBar.contentItem.width,settingsBar.contentItem.height));
        const settingsBefore = settings.contentY;
        mouseWheel(settings,settings.width/2,settings.height/2,0,-120); wait(80);
        verify(settings.contentY > settingsBefore); verify(settingsBar.opacity > 0);
        Theme.scrollbarsEnabled = false; compare(settingsBar.policy,Controls.ScrollBar.AlwaysOff);
    }
    function test_05_country_cards_click_and_select_with_native_tone() {
        panel.tabIndex = 1;
        child(panel,"countrySearch").text = "France";
        tryVerify(() => child(panel,"countryList").count === 1);
        const row = child(panel,"country:France"), actions = TransportState.actionCount;
        verify(row.clickable);
        mouseClick(row,Math.max(12,row.width/3),row.height/2); idle();
        compare(panel.country,"France"); compare(panel.city,"");
        compare(row.tone,"primary"); compare(row.contentColor,Theme.primaryContainerText);
        compare(TransportState.actionCount,actions,"Country-list cards select a destination for the connect control");
        panel.selectCountry("United_States"); idle(); panel.selectCity("Miami");
    }
    function test_06_large_fonts_and_square_rounded_layout_captures() {
        const configs = [
            {name:"square-large-dark",radius:0,scale:1.6,light:false,height:730,compact:false},
            {name:"rounded-large-light",radius:24,scale:1.6,light:true,height:730,compact:false},
            {name:"square-large-compact",radius:0,scale:1.6,light:false,height:540,compact:true}
        ];
        for (const config of configs) {
            Theme.cornerRadius = config.radius; Theme.fontScale = config.scale;
            Theme.fontFamily = "DejaVu Serif"; Theme.lightMode = config.light;
            panel.height = config.height; panel.compact = config.compact;
            panel.tabIndex = 0; panel.mapView.focusRegion("Florida"); settleMap();
            const destination = child(panel,"destinationCard"), status = child(panel,"statusCard");
            const connect = child(panel,"connectButton");
            const bottom = destination.mapToItem(panel,0,destination.height).y;
            verify(bottom <= panel.height+0.1,"Destination controls overflow " + config.name + ": " + bottom + "/" + panel.height);
            verify(connect.height >= connect.contentItem.implicitHeight,"Scaled connect text must fit its button");
            verify(child(panel,"statusTitle").height >= child(panel,"statusTitle").implicitHeight-0.1);
            verify(status.height > 0 && panel.mapView.height >= 110);
            grabImage(panel).save("qml-theme-map-"+config.name+".png");
            panel.tabIndex = 1; wait(100);
            child(panel,"countryScrollbar")._scrollBarActive = true;
            grabImage(panel).save("qml-theme-locations-"+config.name+".png");
            panel.tabIndex = 2; wait(100);
            const scroll = child(panel,"settingsScroll");
            compare(scroll.contentWidth,scroll.width);
            child(panel,"settingsScrollbar")._scrollBarActive = true;
            grabImage(panel).save("qml-theme-settings-"+config.name+".png");
            scroll.contentY = Math.max(0,scroll.contentHeight-scroll.height); wait(80);
            const dns = child(panel,"dnsInput"), dnsBottom = dns.mapToItem(scroll,0,dns.height).y;
            verify(dnsBottom <= scroll.height+0.1 && dnsBottom >= dns.height,
                "Custom DNS remains reachable at the bottom of the settings scroll area");
            grabImage(panel).save("qml-theme-settings-bottom-"+config.name+".png");
            scroll.contentY = 0;
        }
    }
}
