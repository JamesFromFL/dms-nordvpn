import QtQuick
import QtTest
import qs.Common
import Quickshell.Io
import "../../locationLookup.js" as Geo
import "../../locationData.js" as Locations
import "../../mapLogic.js" as MapMath
import "../.." as Nord

TestCase {
    id: tests
    name: "NordVpnPlugin"
    when: windowShown
    visible: true
    width: 880; height: 730
    property var panel
    property Component panelComponent: Component { Nord.NordVpnPanel { width: 880; height: 730; Rectangle { anchors.fill: parent; color: Theme.lightMode ? "#f9f9f9" : "#131313"; z: -1 } } }
    property Component widgetComponent: Component { Nord.NordVpnWidget { } }
    property Component settingsComponent: Component { Nord.Settings { } }
    function initTestCase() {
        // Service scheduling is exercised separately; keep map captures deterministic.
        Nord.NordVpnService.preloadIntervalMs = 3600000;
        panel = panelComponent.createObject(tests);
        verify(panel !== null);
        verify(createTemporaryObject(widgetComponent, tests) !== null);
        verify(createTemporaryObject(settingsComponent, tests) !== null);
        tryVerify(() => Nord.NordVpnService.ready, 10000);
        tryVerify(() => Nord.NordVpnService.countries.length > 0, 10000);
    }
    function cleanupTestCase() { panel.destroy(); }
    function waitIdle() { tryVerify(() => !Nord.NordVpnService.current && Nord.NordVpnService.queue.length === 0, 10000); }
    function withoutCountry(object, country) {
        const copy = Object.assign({}, object); delete copy[country]; return copy;
    }
    function focusGeography(west, south, east, north, maxLevel) {
        panel.mapView.focusBounds([(west + 180) / 360, (90 - north) / 180, (east + 180) / 360, (90 - south) / 180], maxLevel || 128);
    }
    function settleMap() {
        // Let debounced catalog discovery run, then capture its completed scene.
        wait(250); waitIdle(); wait(160);
    }
    function mapMarker(kind, country, city) {
        const marker = findChild(panel.mapView, kind + ":" + country + ":" + (city || ""));
        verify(marker !== null, "Missing " + kind + " marker for " + country + " " + (city || ""));
        verify(marker.visible, "Marker is outside the viewport");
        return marker;
    }
    function test_01_locations_and_shared_service() {
        compare(panel.vpn, Nord.NordVpnService);
        panel.selectCountry("United_States");
        tryVerify(() => Nord.NordVpnService.cities.length > 0, 10000);
        compare(Nord.NordVpnService.cities[0], "Chicago");
        compare(Nord.NordVpnService.connected, false);
    }
    function test_02_connect_uses_authoritative_snapshot() {
        Nord.NordVpnService.connectTo("United_States", "Chicago", "");
        compare(Nord.NordVpnService.busy, true);
        tryVerify(() => !Nord.NordVpnService.busy, 10000);
        compare(Nord.NordVpnService.connected, true);
        compare(Nord.NordVpnService.status.server, "test-server");
    }
    function test_03_settings_reconcile() {
        Nord.NordVpnService.setOption("killswitch", false);
        tryVerify(() => !Nord.NordVpnService.busy, 10000);
        compare(Nord.NordVpnService.settings.killswitch, false);
    }
    function test_04_disconnect() {
        Nord.NordVpnService.disconnect();
        tryVerify(() => !Nord.NordVpnService.busy, 10000);
        compare(Nord.NordVpnService.connected, false);
    }
    function test_05_favorites_persist() {
        panel.toggleFavorite("United_States");
        panel.loadFavorites();
        verify(panel.favorites.indexOf("United_States") >= 0);
        panel.toggleFavorite("United_States");
        verify(panel.favorites.indexOf("United_States") < 0);
    }
    function test_06_capture() {
        wait(100);
        const image = grabImage(panel);
        verify(image.width > 0);
        image.save("qml-panel.png");
    }
    function test_07_state_click_selects_real_city() {
        panel.selectCountry("United_States", true);
        tryVerify(() => panel.currentCities.indexOf("Miami") >= 0);
        const map = panel.mapView;
        tryVerify(() => map.showStates);
        mouseClick(map, map.screenX(-82.4), map.screenY(29.6));
        compare(panel.region, "Florida");
        compare(panel.city, "Miami");
        verify(map.zoom > 4, "zoom=" + map.zoom + ", map=" + map.width + "x" + map.height);
        const connect = findChild(panel, "connectButton");
        verify(connect.enabled);
        mouseClick(connect);
        tryVerify(() => !Nord.NordVpnService.busy);
        compare(TransportState.lastRequest.country, "United_States");
        compare(TransportState.lastRequest.city, "Miami");
        verify(TransportState.lastRequest.region === undefined);
    }
    function test_08_unavailable_state_cannot_connect() {
        const previous = TransportState.lastRequest;
        const catalogs = Nord.NordVpnService.cityCatalogs;
        const previousRegion = panel.region, previousCity = panel.city;
        const unavailable = Object.assign({}, catalogs, { United_States: catalogs.United_States.filter(c => c !== "Billings") });
        try {
            Nord.NordVpnService.cityCatalogs = unavailable;
            panel.selectRegion("Montana");
            compare(panel.filteredCities.length, 0);
            compare(panel.city, "");
            verify(!findChild(panel, "connectButton").enabled);
            panel.connectSelection();
            compare(TransportState.lastRequest, previous);
        } finally {
            Nord.NordVpnService.cityCatalogs = catalogs;
            panel.selectRegion(previousRegion);
            panel.selectCity(previousCity);
        }
    }
    function test_09_wheel_zoom_anchor_and_drag() {
        const map = panel.mapView;
        map.hoveredRegion = "Florida";
        map.resetView(); compare(map.hoveredRegion, "");
        map.zoom=4;map.centerX=0.5;map.centerY=0.5;
        const x = Math.round(map.width * 0.3), y = Math.round(map.height * 0.45);
        const anchorX = map.centerX + (x - map.width / 2) / (map.mapWidth * map.zoom);
        const anchorY = map.centerY + (y - map.height / 2) / (map.mapHeight * map.zoom);
        map.hoveredRegion = "Florida";
        mouseWheel(map, x, y, 0, 120);
        verify(map.zoom > 1);
        compare(map.hoveredRegion, "");
        fuzzyCompare(map.centerX + (x - map.width / 2) / (map.mapWidth * map.zoom), anchorX, 0.000001);
        fuzzyCompare(map.centerY + (y - map.height / 2) / (map.mapHeight * map.zoom), anchorY, 0.000001);
        map.zoom = 4; map.centerX = 0.5; map.centerY = 0.5;
        mouseDrag(map, map.width / 2, map.height / 2, 60, 0);
        verify(map.centerX < 0.5);
        map.zoomAt(1000, map.width / 2, map.height / 2);
        compare(map.zoom, map.maxZoom);
        map.zoomAt(0.000001, map.width / 2, map.height / 2);
        compare(map.zoom, 1);
    }
    function test_10_live_catalog_and_unmapped_fallback() {
        verify(panel.currentCities.indexOf("Unmapped_City") >= 0);
        verify(Geo.cityMarkers("United_States", panel.currentCities).every(p => p.city !== "Unmapped_City"));
        verify(Geo.cityMarkers("United_States", ["Chicago"]).every(p => p.city !== "Miami"));
        panel.selectCity("Unmapped_City");
        compare(panel.city, "Unmapped_City");
        compare(panel.region, "");
        panel.selectCity("Unsupported_City");
        compare(panel.city, "Unmapped_City");
        panel.selectCountry("France", true);
        tryVerify(() => panel.currentCities.indexOf("Paris") >= 0);
        compare(panel.city, "");
        compare(panel.region, "");
    }
    function contrast(a, b) {
        function luminance(c) {
            function linear(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
            return linear(c.r) * 0.2126 + linear(c.g) * 0.7152 + linear(c.b) * 0.0722;
        }
        const x = luminance(a), y = luminance(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }
    function test_11_theme_pairs_and_captures() {
        panel.selectCountry("United_States", true);
        tryVerify(() => panel.currentCities.indexOf("Miami") >= 0);
        panel.selectRegion("Florida");
        panel.mapView.focusRegion("Florida");
        for (let light of [false, true]) {
            Theme.lightMode = light;
            verify(contrast(Theme.surfaceText, Theme.surfaceContainer) >= 4.5);
            verify(contrast(Theme.surfaceVariantText, Theme.surfaceContainerHigh) >= 4.5);
            verify(contrast(Theme.primaryText, Theme.primary) >= 4.5);
            verify(contrast(Theme.primaryContainerText, Theme.primaryContainer) >= 4.5);
            compare(findChild(panel, "connectButton").backgroundColor, Theme.primary);
            panel.tabIndex = 0;
            wait(100);
            grabImage(panel).save(light ? "qml-map-light.png" : "qml-map-dark.png");
            panel.tabIndex = 2;
            wait(100);
            grabImage(panel).save(light ? "qml-settings-light.png" : "qml-settings-dark.png");
        }
        Theme.lightMode = false;
        panel.tabIndex = 0;
    }
    function test_12_full_catalog_country_click_connects_fastest_without_zoom() {
        waitIdle();
        compare(Nord.NordVpnService.countries.length, 150);
        panel.selectCountry("United_States"); waitIdle(); panel.selectCity("New_York");
        panel.group = "Double_VPN";
        const map = panel.mapView;
        map.resetView(); wait(100);
        compare(map.cityPoints.length, 0);
        const us = mapMarker("country", "United_States", "");
        const zoom = map.zoom, actions = TransportState.actionCount;
        // Click through the map so an overlapping delegate would break this check.
        mouseClick(map, us.x + us.width / 2, us.y + us.height / 2);
        tryVerify(() => TransportState.actionCount === actions + 1);
        waitIdle();
        compare(TransportState.lastRequest.country, "United_States");
        verify(TransportState.lastRequest.city === undefined);
        verify(TransportState.lastRequest.group === undefined);
        compare(panel.city, ""); compare(panel.region, ""); compare(panel.group, "");
        compare(map.zoom, zoom);
    }
    function test_13_viewport_catalog_loading_preserves_target_and_does_not_connect() {
        panel.selectCountry("United_States"); waitIdle(); panel.selectCity("Miami");
        panel.group = "Double_VPN";
        const vpn = Nord.NordVpnService, map = panel.mapView;
        map.resetView(); wait(220); waitIdle();
        vpn.cityCatalogs = withoutCountry(vpn.cityCatalogs, "France");
        vpn.cityCatalogUpdated = withoutCountry(vpn.cityCatalogUpdated, "France");
        vpn.cityCatalogAttempts = withoutCountry(vpn.cityCatalogAttempts, "France");
        const reads = TransportState.cityReadCount.France || 0, actions = TransportState.actionCount;
        map.focusCountry("France");
        tryVerify(() => (vpn.cityCatalogs.France || []).indexOf("Paris") >= 0, 10000);
        verify((TransportState.cityReadCount.France || 0) > reads);
        compare(panel.country, "United_States"); compare(panel.city, "Miami");
        compare(panel.region, "Florida"); compare(panel.group, "Double_VPN");
        compare(TransportState.actionCount, actions);
        verify(map.cityPoints.some(p => p.country === "France" && p.city === "Paris"));
    }
    function test_14_cluster_click_only_zooms() {
        const map = panel.mapView;
        map.resetView(); wait(100); waitIdle();
        const singles = map.markers.filter(m => m.kind !== "cluster");
        const bubble = map.markers.find(m => m.kind === "cluster" && m.x > 32 && m.x < map.width - 100
            && m.y > 55 && m.y < map.height - 55
            && !singles.some(s => Math.abs(s.x - m.x) < 17 && Math.abs(s.y - m.y) < 17));
        verify(bubble !== undefined, "Full country catalog should offer an unobscured count bubble");
        const zoom = map.zoom, actions = TransportState.actionCount, request = JSON.stringify(TransportState.lastRequest);
        mouseClick(map, bubble.x, bubble.y);
        verify(map.zoom > zoom);
        settleMap();
        compare(TransportState.actionCount, actions);
        compare(JSON.stringify(TransportState.lastRequest), request);
    }
    function test_15_actual_city_marker_uses_exact_cli_destination() {
        panel.selectCountry("United_States"); waitIdle(); panel.selectCity("Chicago");
        panel.group = "Double_VPN";
        panel.mapView.focusRegion("Florida"); settleMap();
        const map = panel.mapView, miami = mapMarker("city", "United_States", "Miami");
        // These coordinates are from the independent Nord API fixture, not mapData.js.
        const x = map.screenX(-80.1938889), y = map.screenY(25.7738889);
        fuzzyCompare(miami.x + miami.width / 2, x, 0.00001);
        fuzzyCompare(miami.y + miami.height / 2, y, 0.00001);
        const actions = TransportState.actionCount;
        mouseClick(map, x, y);
        tryVerify(() => TransportState.actionCount === actions + 1); waitIdle();
        compare(TransportState.lastRequest.country, "United_States");
        compare(TransportState.lastRequest.city, "Miami");
        verify(TransportState.lastRequest.group === undefined);
        compare(panel.city, "Miami"); compare(panel.region, "Florida");
    }
    function test_16_wheel_zooms_over_marker_without_connecting() {
        const map = panel.mapView;
        map.focusRegion("Florida"); settleMap();
        const miami = mapMarker("city", "United_States", "Miami");
        const x = Math.round(miami.x + miami.width / 2), y = Math.round(miami.y + miami.height / 2);
        const before = map.pointAt(x, y), zoom = map.zoom, actions = TransportState.actionCount;
        mouseWheel(map, x, y, 0, 120);
        verify(map.zoom > zoom);
        const after = map.pointAt(x, y);
        fuzzyCompare(after.x, before.x, 0.000001); fuzzyCompare(after.y, before.y, 0.000001);
        compare(TransportState.actionCount, actions);
    }
    function test_17_compact_overview_usa_is_clickable_and_nearby_cities_split() {
        const originalHeight = panel.height, originalCompact = panel.compact;
        try {
            panel.height = 540; panel.compact = true;
            panel.mapView.resetView(); settleMap();
            const map = panel.mapView;
            verify(map.mapHeight < 240, "Compact map is " + map.width + "x" + map.height);
            const us = mapMarker("country", "United_States", "");
            compare(us.width, 18);
            const actions = TransportState.actionCount;
            mouseClick(map, us.x + us.width / 2, us.y + us.height / 2);
            tryVerify(() => TransportState.actionCount === actions + 1); waitIdle();
            compare(TransportState.lastRequest.country, "United_States");
            verify(TransportState.lastRequest.city === undefined);
            compare(map.zoom, 1);
            map.focusPoints([{lon:-71.0602778,lat:42.3583333},{lon:-71.4680556,lat:42.7652778}], map.maxZoom);
            map.zoom = map.maxZoom; map.clampCenter(); settleMap();
            verify(map.markers.some(m => m.kind === "city" && m.city === "Boston"));
            verify(map.markers.some(m => m.kind === "city" && m.city === "Nashua"));
        } finally { panel.height = originalHeight; panel.compact = originalCompact; }
    }
    function test_18_overview_and_detail_captures() {
        panel.selectCountry("United_States"); waitIdle(); panel.selectCity("Miami");
        panel.connectCityFromMap("United_States", "Miami"); waitIdle();
        const map = panel.mapView, originalHeight = panel.height;
        for (const light of [false, true]) {
            Theme.lightMode = light;
            const suffix = light ? "light" : "dark";
            map.resetView(); settleMap(); mouseMove(map, 1, 1); wait(80);
            grabImage(panel).save("qml-world-" + suffix + ".png");
            map.focusCountry("United_States"); settleMap(); mouseMove(map, 1, 1); wait(80);
            grabImage(panel).save("qml-us-" + suffix + ".png");
            map.focusRegion("Florida"); settleMap(); mouseMove(map, 1, 1); wait(80);
            grabImage(panel).save("qml-miami-" + suffix + ".png");
            focusGeography(-8, 42, 24, 56, 16); settleMap(); mouseMove(map, 1, 1); wait(80);
            grabImage(panel).save("qml-europe-" + suffix + ".png");
            panel.height = 540; panel.compact = true; map.resetView(); settleMap(); mouseMove(map, 1, 1); wait(80);
            grabImage(panel).save("qml-compact-" + suffix + ".png");
            panel.height = originalHeight; panel.compact = false;
        }
        Theme.lightMode = false;
    }
    function test_19_continuous_overview_zoom_retains_country_delegate() {
        const map = panel.mapView;
        map.resetView(); settleMap();
        const us = mapMarker("country", "United_States", "");
        for (let i = 0; i < 24; i++) {
            map.zoomAt(1.006, map.width / 2, map.height / 2);
            wait(16);
            compare(findChild(map, "country:United_States:"), us,
                    "An unchanged country target must survive continuous wheel zoom");
        }
        wait(100);
        compare(findChild(map, "country:United_States:"), us);
        verify(map.zoom < 2.4, "This scenario keeps the U.S. as a country target");
    }
    function test_20_drag_and_wheel_keep_city_and_geometry_aligned() {
        panel.selectCountry("United_States"); waitIdle();
        const map = panel.mapView;
        map.focusRegion("Florida"); settleMap();
        const miami = mapMarker("city", "United_States", "Miami");
        const geometry = findChild(map, "mapGeometry");
        verify(geometry !== null);
        const shape = findChild(geometry, "worldCountryShape");
        verify(shape !== null);
        const countryPath = findChild(geometry, "detailCountryPath:US:USA");
        verify(countryPath !== null);
        const path = countryPath.pathElements[0];
        verify(path !== null);
        const sourcePath = path.path;
        let sourceChanges = 0;
        const changed = function() { sourceChanges++; };
        path.pathChanged.connect(changed);
        const p = MapMath.project(-80.1938889, 25.7738889);
        const centerX = map.centerX, centerY = map.centerY;
        function verifyAlignment() {
            compare(findChild(map, "city:United_States:Miami"), miami,
                    "An unchanged city target must keep its control during navigation");
            compare(findChild(map, "mapGeometry"), geometry);
            compare(findChild(geometry, "worldCountryShape"), shape);
            compare(findChild(geometry, "detailCountryPath:US:USA"), countryPath);
            compare(countryPath.pathElements[0], path);
            const coastPoint = geometry.mapToItem(map, p.x * geometry.width, p.y * geometry.height);
            fuzzyCompare(miami.x + miami.width / 2, coastPoint.x, 0.00001);
            fuzzyCompare(miami.y + miami.height / 2, coastPoint.y, 0.00001);
        }
        try {
            for (let i = 0; i < 24; i++) {
                map.centerX = centerX + Math.sin(i / 6) * 0.0002;
                map.centerY = centerY + Math.cos(i / 6) * 0.0002;
                wait(16); verifyAlignment();
            }
            for (let i = 0; i < 24; i++) {
                map.zoomAt(1.004, map.width / 2, map.height / 2);
                wait(16); verifyAlignment();
            }
            wait(100); verifyAlignment();
            compare(sourceChanges, 0, "Pan and zoom must transform the existing coastline path");
            compare(path.path, sourcePath);
        } finally { path.pathChanged.disconnect(changed); }
    }
}
