pragma Singleton
import QtQuick
import Quickshell.Io
import "catalogCache.js" as Cache

QtObject {
    id: root
    property var status: ({ state: "unknown" })
    property var settings: ({})
    property var capabilities: ({ commands: [], settingKeys: [] })
    property var countries: []
    property var groups: []
    property var cities: []
    property string citiesCountry: ""
    property var cityCatalogs: ({})
    property var cityCatalogUpdated: ({})
    property var cityCatalogAttempts: ({})
    property var cityPreloadAttempts: ({})
    property string errorMessage: ""
    property string settingsError: ""
    property string errorCode: ""
    property string actionError: ""
    property bool busy: false
    property bool reading: false
    property string pendingLabel: ""
    property string version: ""
    property var queue: []
    property var current: null
    property real lastLocations: 0
    property int consumers: 0
    property int activePanels: 0
    property int actionRevision: 0
    property real statusReadSequence: 0
    property real latestStatusSequence: 0
    property bool probeFinished: false
    property real lastProbeAttempt: 0
    property var cacheStore: null
    property bool cacheInitialized: false
    property var restoredCatalogs: ({})
    property int preloadIntervalMs: 2000
    property var preloadPriorities: ["United_States", "United_Kingdom", "Canada", "Germany", "France", "Netherlands", "Australia", "Japan", "Sweden", "Spain"]
    property bool mainStarted: false
    property bool mainExited: false
    property bool mainOutputEnded: false
    property int mainExitCode: 0
    property int mainExitStatus: 0
    property var statusRequest: null
    property bool statusStarted: false
    property bool statusExited: false
    property bool statusOutputEnded: false
    property int statusExitCode: 0
    property int statusExitStatus: 0
    property bool statusWanted: false
    readonly property bool connected: status.state === "connected"
    readonly property bool ready: status.state !== "unknown"
    readonly property bool preloadNeeded: countries.some(country => !Cache.fresh(cityCatalogUpdated[country], Date.now()))
    readonly property string stateLabel: busy ? pendingLabel : ({ connected: "Connected", disconnected: "Disconnected", connecting: "Connecting", disconnecting: "Disconnecting", paused: "Paused", unknown: "Status unavailable" })[status.state] || "Status unavailable"
    readonly property string bridgePath: decodeURIComponent(Qt.resolvedUrl("scripts/nord_bridge.py").toString().replace(/^file:\/\//, "").replace(/\?.*$/, ""))

    function initializeCache(store) {
        if (cacheInitialized || !store || typeof store.loadPluginState !== "function" || typeof store.savePluginState !== "function") return;
        cacheInitialized = true; cacheStore = store;
        try {
            restoredCatalogs = Cache.read(store.loadPluginState("nordVpnControl", "cityCatalogCache", null), Date.now()).catalogs;
            prioritizeCountries(store.loadPluginData("nordVpnControl", "favorites", []));
        } catch (error) { restoredCatalogs = {}; }
        if (lastLocations) reconcileCatalogs();
    }
    function reconcileCatalogs() {
        const allowed = new Set(countries), lists = {}, times = {};
        for (const country of Object.keys(restoredCatalogs)) {
            if (!allowed.has(country)) continue;
            lists[country] = restoredCatalogs[country].cities;
            times[country] = restoredCatalogs[country].checkedAt;
        }
        for (const country of Object.keys(cityCatalogs)) {
            if (!allowed.has(country)) continue;
            lists[country] = cityCatalogs[country]; times[country] = cityCatalogUpdated[country];
        }
        restoredCatalogs = {}; cityCatalogs = lists; cityCatalogUpdated = times;
        if (citiesCountry) cities = lists[citiesCountry] || [];
        if (cacheInitialized) cacheWriter.restart();
    }
    function persistCatalogs() {
        if (!cacheStore || !lastLocations) return;
        try { cacheStore.savePluginState("nordVpnControl", "cityCatalogCache", Cache.pack(cityCatalogs, cityCatalogUpdated, countries, Date.now())); }
        catch (error) { /* A disk-cache failure must not stop the live controller. */ }
    }
    function prioritizeCountries(values) {
        if (!Array.isArray(values)) return;
        preloadPriorities = Array.from(new Set(values.filter(v => typeof v === "string").concat(preloadPriorities))).slice(0, 300);
    }
    function retain() {
        consumers++;
        if (consumers === 1) {
            requestStatus();
            enqueue("locations", [], "", true);
            enqueue("probe", [], "", true);
            enqueue("snapshot", []);
        }
    }
    function release() {
        consumers = Math.max(0, consumers - 1);
        if (!consumers) {
            // A previously requested VPN action must still finish if its surface closes.
            queue = queue.filter(item => item.operation === "action");
            if (busy && (!current || current.operation !== "action") && !queue.length) { busy = false; pendingLabel = ""; }
            if (cacheWriter.running) { cacheWriter.stop(); persistCatalogs(); }
        }
    }
    function setPanelActive(value) {
        activePanels = Math.max(0, activePanels + (value ? 1 : -1));
        if (value) refresh();
    }
    function hasSetting(key) { return capabilities.settingKeys.indexOf(key) >= 0 && settings[key] !== undefined; }
    function hasCommand(name) { return capabilities.commands.indexOf(name) >= 0; }
    function priority(item) {
        if (item.operation === "action") return 0;
        if (item.operation === "snapshot") return 1;
        if (item.operation === "cities") return item.background ? 4 : 2;
        return 3;
    }
    function enqueue(operation, args, label, quiet, background) {
        if (current && current.operation === operation && JSON.stringify(current.args) === JSON.stringify(args) && operation !== "action") {
            if (!quiet) current.quiet = false;
            if (operation === "cities" && !background) current.foregroundRequested = true;
            return;
        }
        const duplicate = queue.findIndex(item => item.operation === operation && JSON.stringify(item.args) === JSON.stringify(args));
        let previous = null;
        if (duplicate >= 0) {
            previous = queue[duplicate];
            if (quiet && (background || !previous.background)) return;
            queue = queue.filter((_, i) => i !== duplicate);
        }
        const item = { operation, args, label: label || "", quiet: quiet === true && (!previous || previous.quiet),
            background: operation === "cities" && background === true, foregroundRequested: operation === "cities" && !background };
        const nextQueue = queue.slice(), index = nextQueue.findIndex(other => priority(other) > priority(item));
        nextQueue.splice(index < 0 ? nextQueue.length : index, 0, item);
        queue = nextQueue; next();
    }
    function next() {
        if (current || runner.running || !queue.length) return;
        current = queue[0]; queue = queue.slice(1); current.startedAt = Date.now();
        if (current.operation === "snapshot" || current.operation === "action") current.statusSequence = ++statusReadSequence;
        mainStarted = false; mainExited = false; mainOutputEnded = false; mainExitCode = 0; mainExitStatus = 0;
        if (current.operation === "probe") lastProbeAttempt = current.startedAt;
        reading = current.operation !== "action";
        runner.command = ["python3", bridgePath, current.operation].concat(current.args, current.background ? ["--background"] : []);
        runner.running = true;
    }
    function mainStopped() {
        const item = current;
        if (!item) return;
        Qt.callLater(function() {
            if (root.current === item && !root.mainStarted && !root.mainExited) root.finish("", 127);
        });
    }
    function completeMain() {
        if (current && mainExited && mainOutputEnded) finish(mainExitStatus === 0 ? output.text : "", mainExitCode);
    }
    function requestStatus() {
        if (!consumers) return;
        if (busy || statusRequest || statusRunner.running) { statusWanted = true; return; }
        statusWanted = false;
        statusRequest = { revision: actionRevision, sequence: ++statusReadSequence };
        statusStarted = false; statusExited = false; statusOutputEnded = false; statusExitCode = 0; statusExitStatus = 0;
        statusRunner.command = ["python3", bridgePath, "status"]; statusRunner.running = true;
    }
    function statusStopped() {
        const request = statusRequest;
        if (!request) return;
        Qt.callLater(function() {
            if (root.statusRequest === request && !root.statusStarted && !root.statusExited) root.finishStatus("", 127);
        });
    }
    function completeStatus() {
        if (statusRequest && statusExited && statusOutputEnded) finishStatus(statusExitStatus === 0 ? statusOutput.text : "", statusExitCode);
    }
    function finishStatus(text, code) {
        const request = statusRequest;
        if (!request) return;
        let data;
        try { data = JSON.parse(text); }
        catch (error) { data = {ok:false,status:{state:"unknown"},error:"adapter-error",message:code === 127 ? "Python 3 is required." : "Could not read the NordVPN adapter response."}; }
        statusRequest = null;
        if (request.revision === actionRevision && !busy) applyStatus(data, request.sequence);
        if (statusWanted && !busy) Qt.callLater(requestStatus);
    }
    function refresh(clearError) {
        if (clearError === true) { actionError = ""; errorMessage = ""; }
        requestStatus(); enqueue("snapshot", []);
    }
    function fetchCities(country) {
        if (!country) return;
        citiesCountry = country; cities = cityCatalogs[country] || [];
        prioritizeCountries([country]);
        if (Cache.fresh(cityCatalogUpdated[country], Date.now())) return;
        cityCatalogAttempts = Object.assign({}, cityCatalogAttempts, { [country]: Date.now() });
        enqueue("cities", [country]);
    }
    function ensureCities(country, background) {
        if (!country || countries.indexOf(country) < 0) return;
        const now = Date.now();
        if (Cache.fresh(cityCatalogUpdated[country], now)) return;
        const attempts = background ? cityPreloadAttempts : cityCatalogAttempts;
        if (attempts[country] && now - attempts[country] < 60000) return;
        if (background) cityPreloadAttempts = Object.assign({}, cityPreloadAttempts, { [country]: now });
        else cityCatalogAttempts = Object.assign({}, cityCatalogAttempts, { [country]: now });
        enqueue("cities", [country], "", true, background === true);
    }
    function preloadCities() {
        if (!consumers || !ready || !lastLocations || !probeFinished || busy || current || runner.running || queue.length) return;
        const key = value => String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
        const connectedCountry = countries.find(country => key(country) === key(status.country));
        const candidates = Array.from(new Set((connectedCountry ? [connectedCountry] : []).concat(preloadPriorities, countries)));
        const now = Date.now();
        for (const country of candidates) {
            if (countries.indexOf(country) < 0 || Cache.fresh(cityCatalogUpdated[country], now)) continue;
            if (cityPreloadAttempts[country] && now - cityPreloadAttempts[country] < 60000) continue;
            ensureCities(country, true); return;
        }
    }
    function perform(request, label) {
        if (busy || !ready) return;
        actionRevision++; busy = true; pendingLabel = label; errorMessage = ""; actionError = "";
        enqueue("action", [JSON.stringify(request)], label);
    }
    function connectTo(country, city, group) {
        const request = { name: "connect" };
        if (country) request.country = country;
        if (city) request.city = city;
        if (group) request.group = group;
        perform(request, "Connecting…");
    }
    function disconnect() { perform({ name: "disconnect" }, "Disconnecting…"); }
    function pause(duration) { if (hasCommand("pause")) perform({ name: "pause", duration }, "Pausing…"); }
    function setOption(key, value) { if (hasSetting(key)) perform({ name: "set", key, value }, "Applying setting…"); }
    function applyStatus(data, sequence) {
        if (sequence < latestStatusSequence) return;
        latestStatusSequence = sequence;
        const value = data && data.status;
        const valid = value && ["connected", "disconnected", "connecting", "disconnecting", "paused"].indexOf(value.state) >= 0;
        status = data && data.ok && valid ? value : {state:"unknown"};
        if (!data || !data.ok || !valid) {
            errorMessage = data && data.message || "Could not confirm VPN status.";
            errorCode = data && data.error || "unrecognized-output";
        } else {
            errorMessage = actionError; errorCode = actionError ? "command-failed" : "";
            if (consumers && (!lastLocations || Date.now() - lastLocations > 300000)) enqueue("locations", [], "", true);
            if (consumers && !probeFinished && Date.now() - lastProbeAttempt >= 10000) enqueue("probe", [], "", true);
        }
    }
    function applySnapshot(data, sequence) {
        applyStatus(data, sequence);
        settings = data.settings || {}; settingsError = data.settingsError || "";
    }
    function finish(text, code) {
        const item = current;
        if (!item) return;
        let retryCity = "";
        try {
            const data = JSON.parse(text);
            if (item.operation === "action") {
                if (data.snapshot) applySnapshot(data.snapshot, item.statusSequence);
                else status = { state: "unknown" };
                if (!data.ok) { actionError = data.message || "The action failed."; errorMessage = actionError; errorCode = data.error || "command-failed"; }
            } else if (item.operation === "snapshot") {
                applySnapshot(data, item.statusSequence);
            } else if (!data.ok) {
                if (item.background && item.foregroundRequested) retryCity = item.args[0];
                else if (!item.quiet) { errorMessage = data.message || "NordVPN command failed."; errorCode = data.error || "command-failed"; }
            } else if (item.operation === "probe") {
                if (!Array.isArray(data.commands) || !Array.isArray(data.settingKeys)) throw new Error("Invalid capability response");
                capabilities = data; version = data.version || ""; probeFinished = true;
            } else if (item.operation === "locations") {
                countries = data.countries || []; groups = data.groups || [];
                lastLocations = Date.now(); reconcileCatalogs();
            } else if (item.operation === "cities") {
                const country = item.args[0];
                if (data.country !== country || !Array.isArray(data.cities)) throw new Error("Invalid city catalog");
                const now = Date.now(), validated = Cache.read({schema:1,catalogs:{[country]:{cities:data.cities,checkedAt:now}}}, now).catalogs[country];
                if (!validated) throw new Error("Invalid city catalog");
                cityCatalogs = Object.assign({}, cityCatalogs, { [country]: validated.cities });
                cityCatalogUpdated = Object.assign({}, cityCatalogUpdated, { [country]: now });
                if (country === citiesCountry) cities = validated.cities;
                if (cacheInitialized) cacheWriter.restart();
            }
        } catch (error) {
            if (item.operation === "snapshot" || item.operation === "action") {
                applyStatus({ok:false,status:{state:"unknown"},error:"adapter-error",message:code === 127 ? "Python 3 is required." : "Could not read the NordVPN adapter response."}, item.statusSequence);
                settings = {};
            } else if (item.background && item.foregroundRequested) retryCity = item.args[0];
            else if (!item.quiet) { errorMessage = code === 127 ? "Python 3 is required." : "Could not read the NordVPN adapter response."; errorCode = "adapter-error"; }
        }
        if (item.operation === "action") { busy = false; pendingLabel = ""; }
        reading = false; current = null;
        if (retryCity) enqueue("cities", [retryCity], "", item.quiet);
        if (item.operation === "action" && statusWanted) Qt.callLater(requestStatus);
        Qt.callLater(next);
    }
    property var runner: Process {
        id: runner
        stdout: StdioCollector { id: output; onStreamFinished: { root.mainOutputEnded = true; root.completeMain(); } }
        stderr: StdioCollector { }
        onStarted: root.mainStarted = true
        onExited: (exitCode, exitStatus) => { root.mainExitCode = exitCode; root.mainExitStatus = exitStatus; root.mainExited = true; root.completeMain(); }
        onRunningChanged: { if (!running) root.mainStopped(); }
    }
    property var statusRunner: Process {
        id: statusRunner
        stdout: StdioCollector { id: statusOutput; onStreamFinished: { root.statusOutputEnded = true; root.completeStatus(); } }
        stderr: StdioCollector { }
        onStarted: root.statusStarted = true
        onExited: (exitCode, exitStatus) => { root.statusExitCode = exitCode; root.statusExitStatus = exitStatus; root.statusExited = true; root.completeStatus(); }
        onRunningChanged: { if (!running) root.statusStopped(); }
    }
    property var poller: Timer {
        interval: root.ready ? (root.activePanels > 0 ? 3000 : 15000) : 2000
        repeat: true
        running: root.consumers > 0
        onTriggered: root.requestStatus()
    }
    property var settingsPoller: Timer {
        interval: 30000; repeat: true; running: root.consumers > 0
        onTriggered: { if (!root.busy) root.enqueue("snapshot", []); }
    }
    property var preloader: Timer {
        interval: Math.max(20, root.preloadIntervalMs); repeat: true
        running: root.consumers > 0 && root.ready && root.lastLocations > 0 && root.preloadNeeded
        onTriggered: root.preloadCities()
    }
    property var cacheWriter: Timer { interval: 1000; onTriggered: root.persistCatalogs() }
}
