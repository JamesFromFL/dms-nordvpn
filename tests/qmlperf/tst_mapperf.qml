import QtQuick
import QtQuick.Window
import QtTest
import "../.." as Nord
import "../qmlhost/imports/Quickshell/Io/CatalogFixture.js" as Catalog

// Comparative rendering measurements, kept separate from the functional fixture suite.
// QtTest's wait(16) is event-loop driven, so observedFps is not the display refresh rate.
TestCase {
    id: tests
    name: "NordMapPerformance"
    visible: true
    when: windowShown
    width: 880
    height: 400
    property var map
    property bool recording: false
    property var frameTimes: []
    property int paints: 0
    property int markerUpdates: 0
    property int detailUpdates: 0
    property real startupStartedAt: 0
    property real mapCreationMs: 0
    property real firstGeometryReadyMs: -1
    property Component mapComponent: Component {
        Nord.WorldMap {
            x: 16
            y: 16
            width: 848
            height: 334
            availableCountries: Catalog.countries
            cityCatalogs: Catalog.cities
        }
    }
    Connections {
        target: tests.Window.window
        function onFrameSwapped() {
            if (tests.recording) tests.frameTimes.push(Date.now());
        }
    }
    function percentile(values, p) {
        const a = values.slice().sort((x, y) => x - y);
        return a[Math.floor((a.length - 1) * p)] || 0;
    }
    function stats(values) {
        return {medianMs: percentile(values, .5), p95Ms: percentile(values, .95),
            maxMs: values.length ? Math.max(...values) : 0};
    }
    function rendererName(type) {
        return ["unknown", "geometry", "nvpr", "software", "curve"][type] || "unknown";
    }
    function clippingName() {
        const loader = findChild(map,"mapRoundedClipLoader");
        if (!loader || !loader.active) return "software-rectangular";
        return loader.item?.isMockClippingRectangle === true ? "api-fixture" : "native-rounded";
    }
    function recordFirstReady(geometry) {
        if (!geometry.ready || firstGeometryReadyMs >= 0) return;
        firstGeometryReadyMs = Date.now() - startupStartedAt;
        console.info("PERF_STARTUP " + JSON.stringify({mapCreationMs,
            firstGeometryReadyMs, rendererType: geometry.rendererType,
            renderer: rendererName(geometry.rendererType), clipping: clippingName()}));
    }
    function initTestCase() {
        startupStartedAt = Date.now();
        map = mapComponent.createObject(tests);
        mapCreationMs = Date.now() - startupStartedAt;
        verify(map !== null);
        const geometry = findChild(map, "mapGeometry");
        if (geometry) {
            geometry.readyChanged.connect(function() { tests.recordFirstReady(geometry); });
            recordFirstReady(geometry);
        }
        wait(300);
        map.markersChanged.connect(function() {
            if (tests.recording) tests.markerUpdates++;
        });
        map.detailCountriesKeyChanged.connect(function() {
            if (tests.recording) tests.detailUpdates++;
        });
        // Allows the same harness to measure older Canvas versions for comparison.
        for (const child of map.children) {
            if (typeof child.getContext !== "function") continue;
            child.paint.connect(function() {
                if (tests.recording) tests.paints++;
            });
            break;
        }
    }
    function cleanupTestCase() { map.destroy(); }
    function measure(name, setup, mutate, identityName) {
        const geometry = findChild(map, "mapGeometry");
        const setupStartedAt = Date.now();
        let sceneReadyAt = -1;
        const recordSceneReady = function() {
            if (geometry.ready && sceneReadyAt < 0) sceneReadyAt = Date.now();
        };
        if (geometry) geometry.readyChanged.connect(recordSceneReady);
        setup();
        if (geometry) recordSceneReady();
        wait(300);
        const readyStartedAt = Date.now();
        if (geometry) {
            try {
                tryVerify(() => geometry.ready, 5000, "Map geometry must finish preparing before measurement");
            } finally {
                geometry.readyChanged.disconnect(recordSceneReady);
                if (!geometry.ready) console.info("PERF_READINESS " + JSON.stringify({name,
                    ready: false, readyGateWaitMs: Date.now() - readyStartedAt,
                    startupElapsedMs: Date.now() - startupStartedAt,
                    rendererType: geometry.rendererType}));
            }
        }
        const readyGateWaitMs = Date.now() - readyStartedAt;
        const sceneGeometryReadyMs = sceneReadyAt < 0 ? -1 : sceneReadyAt - setupStartedAt;
        tryVerify(() => findChild(map, identityName) !== null, 5000, "Expected location control must be visible");
        recording = false;
        frameTimes = [];
        paints = 0;
        markerUpdates = 0;
        detailUpdates = 0;
        const first = findChild(map, identityName);
        const mutations = [], gaps = [];
        let same = 0, found = 0;
        const steps = 90, start = Date.now();
        recording = true;
        for (let i = 0; i < steps; i++) {
            const tick = Date.now();
            mutate(i);
            mutations.push(Date.now() - tick);
            const current = findChild(map, identityName);
            if (current) found++;
            if (current === first) same++;
            wait(16);
            gaps.push(Date.now() - tick);
        }
        const elapsed = Date.now() - start;
        recording = false;
        const intervals = [];
        for (let i = 1; i < frameTimes.length; i++) intervals.push(frameTimes[i] - frameTimes[i - 1]);
        const rendererType = geometry ? geometry.rendererType : 0;
        console.info("PERF_REPORT " + JSON.stringify({
            name, steps, elapsedMs: elapsed, step: stats(gaps), mutation: stats(mutations),
            frame: stats(intervals), frames: frameTimes.length,
            observedFps: frameTimes.length / (elapsed / 1000), rendererType,
            clipping: clippingName(),
            renderer: geometry ? rendererName(rendererType) : "canvas",
            geometryTier: geometry ? (geometry.detailed ? "detailed" : "overview") : "canvas",
            mapCreationMs, firstGeometryReadyMs, sceneGeometryReadyMs, readyGateWaitMs,
            paints, markerSnapshotChanges: markerUpdates, detailKeyChanges: detailUpdates,
            identityChecks: found, retainedIdentity: same,
            mapHeight: map.mapHeight, finalMarkers: map.markers.length
        }));
    }
    function test_01_overview_wheel() {
        measure("overview-wheel", () => map.resetView(),
            i => map.zoomAt(1.007, map.width / 2, map.height / 2), "country:United_States:");
    }
    function test_02_florida_pan() {
        let x, y;
        measure("florida-pan", () => { map.focusRegion("Florida"); x = map.centerX; y = map.centerY; },
            i => { map.centerX = x + Math.sin(i / 12) * .0002; map.centerY = y + Math.cos(i / 12) * .0002; },
            "city:United_States:Miami");
    }
    function test_03_florida_wheel() {
        measure("florida-wheel", () => map.focusRegion("Florida"),
            i => map.zoomAt(1.004, map.width / 2, map.height / 2), "city:United_States:Miami");
    }
    function test_04_compact_overview_wheel() {
        measure("compact-overview-wheel", () => { map.height = 144; map.resetView(); },
            i => map.zoomAt(1.007, map.width / 2, map.height / 2), "country:United_States:");
    }
}
