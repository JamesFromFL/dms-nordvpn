import QtQuick
import QtTest
import Quickshell.Io
import qs.Services
import "../.." as Nord

TestCase {
    id: tests
    name: "NordVpnServiceReliability"
    when: windowShown
    visible: true
    width: 100
    height: 100
    property var vpn: null
    property real seededAt: 0

    function idle() {
        tryVerify(() => TransportState.activeRequests === 0 && !vpn.current
            && vpn.queue.length === 0 && !vpn.statusRequest, 5000);
    }
    function requestsSince(index, channel) {
        return TransportState.requests.slice(index).filter(r => !channel || r.channel === channel);
    }
    function eventFor(id, phase) {
        return TransportState.events.find(e => e.id === id && e.phase === phase);
    }
    function restoreStatus() {
        vpn.requestStatus();
        tryVerify(() => vpn.ready, 3000);
        idle();
    }
    function initTestCase() {
        TransportState.resetTransport();
        TransportState.connected = true;
        seededAt = Date.now();
        PluginService.values = {cityCatalogCache:{schema:1,catalogs:{
            United_States:{cities:["Chicago","Miami"],checkedAt:seededAt-1000},
            France:{cities:["Cached_Only"],checkedAt:seededAt-26*3600000},
            Denmark:{cities:[],checkedAt:seededAt-1000},
            Mexico:{cities:["Expired_Only"],checkedAt:seededAt-8*24*3600000},
            Ghost_Country:{cities:["Ghost_City"],checkedAt:seededAt-1000}
        }}};
        TransportState.planResponse({operation:"locations",latencyMs:260});
        TransportState.planResponse({operation:"snapshot",latencyMs:220});
        TransportState.planResponse({operation:"probe",latencyMs:180});
        vpn = Nord.NordVpnService;
        vpn.preloadIntervalMs = 3600000;
        vpn.initializeCache(PluginService);
        compare(vpn.ready, false);
        compare(Object.keys(vpn.cityCatalogs).length, 0);
        vpn.retain();
    }
    function cleanupTestCase() { vpn.release(); }
    function cleanup() {
        vpn.preloadIntervalMs = 3600000;
        TransportState.responsePlans = [];
        idle();
        compare(TransportState.maxActiveMainRequests, 1, "The main command lane must remain serial");
        compare(TransportState.maxActiveStatusRequests, 1, "Status refreshes must coalesce");
    }
    function test_01_fast_status_precedes_slow_metadata_and_cache_publication() {
        tryVerify(() => vpn.ready, 1000);
        compare(vpn.connected, true);
        compare(vpn.status.server, "test-server");
        compare(TransportState.requests[0].operation, "status");
        compare(vpn.countries.length, 0, "Metadata is deliberately slower than status");
        compare(Object.keys(vpn.cityCatalogs).length, 0, "Cache waits for live country validation");
        verify(TransportState.activeMainRequests > 0, "Status must not wait for the metadata lane");
    }
    function test_02_warm_cache_prunes_and_serves_fresh_lists_without_commands() {
        tryVerify(() => vpn.countries.length === 150);
        compare(vpn.cityCatalogs.United_States, ["Chicago","Miami"]);
        compare(vpn.cityCatalogs.France, ["Cached_Only"]);
        compare(vpn.cityCatalogs.Denmark, []);
        verify(vpn.cityCatalogs.Mexico === undefined, "Hard-expired catalogs cannot become visible");
        verify(vpn.cityCatalogs.Ghost_Country === undefined, "Absent CLI countries cannot become visible");
        const start = TransportState.requests.length;
        vpn.fetchCities("United_States");
        compare(vpn.cities, ["Chicago","Miami"]);
        vpn.fetchCities("Denmark");
        compare(vpn.cities, []);
        wait(80);
        compare(requestsSince(start).filter(r => r.operation === "cities").length, 0,
            "Fresh and valid empty catalogs must not trigger duplicate CLI reads");
    }
    function test_03_stale_cache_stays_visible_until_authoritative_replacement() {
        TransportState.planResponse({operation:"cities",country:"France",order:"exit-first",
            stdoutDelayMs:140,stderrDelayMs:140,exitDelayMs:25});
        vpn.fetchCities("France");
        compare(vpn.cities, ["Cached_Only"]);
        const request = TransportState.requests[TransportState.requests.length-1];
        tryVerify(() => eventFor(request.id,"exit") !== undefined);
        compare(vpn.cities, ["Cached_Only"], "Exiting before stdout closes cannot erase the cache");
        tryVerify(() => JSON.stringify(vpn.cities) === JSON.stringify(TransportState.catalog.France));
        verify(vpn.cities.indexOf("Cached_Only") < 0);
        idle(); vpn.persistCatalogs();
        const saved = PluginService.loadPluginState("nordVpnControl","cityCatalogCache",null);
        compare(saved.catalogs.France.cities, TransportState.catalog.France);
        verify(saved.catalogs.France.checkedAt > seededAt);
    }
    function test_04_failed_background_catalog_is_not_persisted_or_reported_as_status_failure() {
        const beforeStatus = JSON.stringify(vpn.status), beforeError = vpn.errorMessage;
        TransportState.planResponse({operation:"cities",country:"Japan",
            payload:{ok:false,error:"timeout",message:"Fixture background timeout"}});
        vpn.ensureCities("Japan",true);
        idle(); vpn.persistCatalogs();
        verify(vpn.cityCatalogs.Japan === undefined);
        const saved = PluginService.loadPluginState("nordVpnControl","cityCatalogCache",null);
        verify(saved.catalogs.Japan === undefined);
        compare(JSON.stringify(vpn.status), beforeStatus);
        compare(vpn.errorMessage, beforeError);
    }
    function test_05_stdout_before_exit_waits_for_both_transport_events() {
        vpn.status = {state:"unknown"};
        TransportState.planResponse({operation:"status",stdoutDelayMs:25,stderrDelayMs:25,
            exitDelayMs:130});
        vpn.requestStatus();
        const request = TransportState.requests[TransportState.requests.length-1];
        tryVerify(() => eventFor(request.id,"stdout") !== undefined);
        compare(vpn.ready, false, "Complete stdout without process exit is not yet an accepted result");
        verify(vpn.statusRequest !== null);
        tryVerify(() => vpn.ready);
        verify(eventFor(request.id,"stdout").at <= eventFor(request.id,"exit").at);
    }
    function test_06_exit_before_stdout_does_not_parse_previous_or_empty_output() {
        vpn.status = {state:"unknown"}; vpn.errorMessage = "";
        TransportState.planResponse({operation:"status",order:"exit-first",exitDelayMs:25,
            stdoutDelayMs:130,stderrDelayMs:130});
        vpn.requestStatus();
        const request = TransportState.requests[TransportState.requests.length-1];
        tryVerify(() => eventFor(request.id,"exit") !== undefined);
        compare(vpn.ready, false); compare(vpn.errorMessage, "");
        verify(vpn.statusRequest !== null);
        tryVerify(() => vpn.ready);
        verify(eventFor(request.id,"exit").at < eventFor(request.id,"stdout").at);
    }
    function test_07_status_requests_coalesce_while_a_response_is_pending() {
        const start = TransportState.requests.length;
        TransportState.planResponse({operation:"status",latencyMs:120});
        vpn.requestStatus(); vpn.requestStatus(); vpn.requestStatus();
        compare(requestsSince(start,"status").length, 1);
        idle();
        compare(requestsSince(start,"status").length, 2, "Repeated refreshes need one follow-up, not one process each");
    }
    function test_08_stderr_only_and_failed_start_recover_without_restart() {
        TransportState.planResponse({operation:"status",stdoutText:"",stderrText:"Fixture Python failure",exitCode:127});
        vpn.requestStatus(); idle();
        compare(vpn.ready, false); compare(vpn.errorCode,"adapter-error");
        verify(vpn.errorMessage.length > 0);
        restoreStatus();
        TransportState.planResponse({operation:"status",failedStart:true});
        vpn.requestStatus(); idle();
        compare(vpn.ready, false);
        verify(vpn.statusRequest === null);
        restoreStatus();
    }
    function test_09_crashed_json_cannot_publish_untrusted_status_or_hold_action_busy() {
        const untrusted = {ok:true,status:{state:"connected",server:"untrusted-crash-server",
            country:"Japan",city:"Tokyo"}};
        TransportState.planResponse({operation:"status",crash:true,payload:untrusted});
        vpn.requestStatus(); idle();
        verify(vpn.status.server !== "untrusted-crash-server", "CrashExit must invalidate an otherwise parseable status payload");
        restoreStatus();
        TransportState.planResponse({operation:"action",crash:true,payload:{ok:true,snapshot:untrusted}});
        vpn.connectTo("Japan","Tokyo",""); idle();
        compare(vpn.busy, false); compare(vpn.pendingLabel, "");
        verify(vpn.status.server !== "untrusted-crash-server");
        verify(vpn.errorMessage.length > 0 || vpn.actionError.length > 0);
        restoreStatus();
    }
    function test_10_old_status_cannot_overwrite_an_action_result() {
        TransportState.connected = false; restoreStatus();
        const start = TransportState.requests.length;
        TransportState.planResponse({operation:"status",latencyMs:160});
        vpn.requestStatus();
        vpn.connectTo("United_States","Miami","");
        tryVerify(() => !vpn.busy);
        compare(vpn.connected, true); compare(vpn.status.city,"Miami");
        idle();
        compare(vpn.connected, true); compare(vpn.status.city,"Miami");
        verify(requestsSince(start,"status").length >= 1);
    }
    function test_11_status_and_actions_are_not_starved_by_background_city_backlog() {
        const start = TransportState.requests.length;
        TransportState.planResponse({operation:"cities",country:"Austria",latencyMs:180});
        vpn.enqueue("cities",["Austria"],"",true,true);
        vpn.enqueue("cities",["Belgium"],"",true,true);
        vpn.enqueue("cities",["Finland"],"",true,true);
        vpn.refresh();
        tryVerify(() => requestsSince(start,"status").length > 0);
        tryVerify(() => !vpn.statusRequest);
        compare(vpn.current.operation,"cities");
        compare(vpn.current.args[0],"Austria", "Fast status should finish while the current catalog read remains active");
        vpn.disconnect(); idle();
        const main = requestsSince(start,"main");
        compare(main.map(r => r.operation),["cities","action","snapshot","cities","cities"]);
        verify(main[0].args.indexOf("--background") >= 0);
        verify(main[3].args.indexOf("--background") >= 0);
        compare(vpn.connected,false);
    }
    function test_12_preloading_is_paced_and_prioritizes_requested_countries() {
        const start = TransportState.requests.length;
        vpn.prioritizeCountries(["Germany"]);
        vpn.preloadIntervalMs = 90;
        tryVerify(() => requestsSince(start,"main").filter(r => r.operation === "cities").length >= 3,2000);
        vpn.preloadIntervalMs = 3600000;
        idle();
        const reads = requestsSince(start,"main").filter(r => r.operation === "cities");
        compare(reads[0].args[0],"Germany");
        verify(reads.every(r => r.args.indexOf("--background") >= 0));
        for (let i=1;i<reads.length;i++) verify(reads[i].startedAt-reads[i-1].startedAt >= 70,
            "Preloader must add one catalog per paced tick, not drain all countries together");
        compare(vpn.busy,false);
    }
    function test_13_failed_action_start_releases_busy_and_allows_the_next_command() {
        TransportState.planResponse({operation:"action",failedStart:true});
        vpn.connectTo("United_States","Miami","");
        compare(vpn.busy,true);
        vpn.enqueue("probe",[],"",true);
        idle();
        compare(vpn.busy,false); compare(vpn.pendingLabel,"");
        verify(vpn.errorMessage.length > 0);
        compare(vpn.version,"Test fixture", "The command lane must continue after a failed process start");
        restoreStatus();
    }
    function test_14_foreground_city_request_retries_a_failed_preload() {
        const start = TransportState.requests.length, status = JSON.stringify(vpn.status);
        TransportState.planResponse({operation:"cities",country:"Greece",latencyMs:100,
            payload:{ok:false,error:"timeout",message:"Fixture preload timeout"}});
        vpn.ensureCities("Greece",true);
        vpn.fetchCities("Greece");
        tryVerify(() => JSON.stringify(vpn.cities) === JSON.stringify(TransportState.catalog.Greece));
        idle();
        const reads = requestsSince(start,"main").filter(r => r.operation === "cities");
        compare(reads.length,2);
        verify(reads[0].args.indexOf("--background") >= 0);
        verify(reads[1].args.indexOf("--background") < 0,
            "An active user request must retry with the foreground timeout");
        compare(vpn.citiesCountry,"Greece");
        compare(JSON.stringify(vpn.status),status);
    }
    function test_15_old_full_snapshot_cannot_replace_newer_fast_status() {
        TransportState.connected = false;
        TransportState.planResponse({operation:"snapshot",latencyMs:160});
        vpn.enqueue("snapshot",[]);
        wait(20);
        TransportState.connected = true;
        vpn.requestStatus();
        tryVerify(() => vpn.connected);
        idle();
        compare(vpn.connected,true, "A slower snapshot must not overwrite the newer status response");
    }
    function test_16_closing_the_surface_preserves_a_requested_action() {
        const start = TransportState.requests.length;
        TransportState.planResponse({operation:"cities",country:"Croatia",latencyMs:100});
        vpn.enqueue("cities",["Croatia"],"",true,true);
        vpn.enqueue("cities",["Cyprus"],"",true,true);
        vpn.disconnect();
        compare(vpn.busy,true);
        vpn.release();
        try {
            compare(vpn.consumers,0);
            idle();
            compare(requestsSince(start,"main").map(r => r.operation),["cities","action"]);
            compare(vpn.connected,false);
            compare(vpn.busy,false); compare(vpn.pendingLabel,"");
            compare(vpn.queue.length,0, "A completed action cannot schedule metadata after its last surface closes");
        } finally {
            vpn.retain(); idle();
        }
    }
    function test_17_failed_capability_probe_retries_after_backoff() {
        vpn.probeFinished = false;
        TransportState.planResponse({operation:"probe",payload:{ok:false,error:"timeout",message:"Fixture probe timeout"}});
        vpn.enqueue("probe",[],"",true); idle();
        compare(vpn.probeFinished,false);
        const start = TransportState.requests.length;
        restoreStatus();
        compare(requestsSince(start,"main").filter(r => r.operation === "probe").length,0,
            "Fast status polling must respect the capability retry backoff");
        vpn.lastProbeAttempt = Date.now()-10001;
        restoreStatus();
        compare(vpn.probeFinished,true);
        compare(requestsSince(start,"main").filter(r => r.operation === "probe").length,1);
    }
    function test_18_fresh_catalogs_stop_background_preloading() {
        const savedLists = vpn.cityCatalogs, savedTimes = vpn.cityCatalogUpdated;
        const lists = {}, times = {}, now = Date.now(), start = TransportState.requests.length;
        vpn.countries.forEach(country => { lists[country] = savedLists[country] || []; times[country] = now; });
        try {
            vpn.cityCatalogs = lists; vpn.cityCatalogUpdated = times;
            compare(vpn.preloadNeeded,false);
            vpn.preloadIntervalMs = 30;
            wait(120);
            compare(requestsSince(start,"main").filter(r => r.operation === "cities").length,0);
        } finally {
            vpn.preloadIntervalMs = 3600000;
            vpn.cityCatalogs = savedLists; vpn.cityCatalogUpdated = savedTimes;
        }
    }
    function test_19_same_clock_tick_preserves_request_order() {
        const savedClock = TransportState.clockOverride, frozenTime = Date.now();
        let oldSnapshot, newStatus, oldTransport, newTransport;
        try {
            // Date globals belong to different QML realms. Freeze fixture time
            // explicitly and reproduce equal legacy status timestamps directly.
            TransportState.clockOverride = frozenTime;
            TransportState.connected = false;
            TransportState.planResponse({operation:"snapshot",latencyMs:130});
            vpn.enqueue("snapshot",[]); oldSnapshot = vpn.current;
            oldSnapshot.startedAt = frozenTime;
            oldTransport = TransportState.requests[TransportState.requests.length-1];
            TransportState.connected = true;
            vpn.requestStatus(); newStatus = vpn.statusRequest;
            newStatus.startedAt = frozenTime;
            newTransport = TransportState.requests[TransportState.requests.length-1];
        } finally { TransportState.clockOverride = savedClock; }
        compare(newTransport.startedAt,oldTransport.startedAt, "The fixture must reproduce a real wall-clock tie");
        verify(newStatus.sequence > oldSnapshot.statusSequence,
            "Concurrent lanes need monotonic ordering even within one clock tick");
        tryVerify(() => vpn.connected);
        idle();
        compare(vpn.connected,true, "An older snapshot cannot win merely because wall-clock milliseconds match");
    }
}
