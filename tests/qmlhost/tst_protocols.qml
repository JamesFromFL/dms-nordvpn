import QtQuick
import QtTest
import Quickshell.Io
import qs.Services
import "../.." as Nord

TestCase {
    id: tests
    name: "NordVpnProtocolCompatibility"
    when: windowShown
    visible: true
    width: 880
    height: 730
    property var panel: null
    property var vpn: null
    property var savedService: ({})
    property var savedTransport: ({})
    property var savedPreferences
    property Component panelComponent: Component { Nord.NordVpnPanel { width: 880; height: 730; panelLive: false } }
    readonly property var protocolValues: ["nordlynx", "openvpn_udp", "openvpn_tcp", "nordwhisper"]
    readonly property var protocolLabels: ["NordLynx", "OpenVPN (UDP)", "OpenVPN (TCP)", "NordWhisper"]

    function child(name) {
        const item = findChild(panel, name);
        verify(item !== null, "Missing setting control " + name);
        return item;
    }
    function idle() {
        tryVerify(() => TransportState.activeRequests === 0 && !vpn.current
            && vpn.queue.length === 0 && !vpn.statusRequest && !vpn.busy, 5000);
    }
    function actionRequests(index) {
        return TransportState.requests.slice(index || 0).filter(request => request.operation === "action")
            .map(request => JSON.parse(request.args[0]));
    }
    function snapshot(settings) {
        return {ok: true, status: {state: "disconnected"}, settings: settings};
    }
    function modernCapabilities(protocols) {
        return {ok: true, version: "NordVPN 6 fixture", commands: ["connect", "disconnect"],
            settingKeys: ["protocol", "notify", "post-quantum", "meshnet"],
            protocolMode: "unified", protocols: protocols || protocolValues};
    }
    function modernSettings(protocol) {
        return {protocol: protocol || "nordlynx", notify: true, "post-quantum": false, meshnet: false};
    }
    function configure(settings, capabilities) {
        idle();
        const before = actionRequests().length;
        TransportState.planResponse({operation: "probe", payload: capabilities || modernCapabilities()});
        TransportState.planResponse({operation: "snapshot", payload: snapshot(settings)});
        vpn.enqueue("probe", [], "", true);
        vpn.enqueue("snapshot", []);
        idle();
        panel.tabIndex = 2;
        wait(0);
        compare(actionRequests().length, before, "Loading capabilities and snapshots must not send settings");
    }
    function respondToSetting(settings, latency) {
        TransportState.planResponse({operation: "action", latencyMs: latency || 50,
            payload: {ok: true, snapshot: snapshot(settings)}});
    }
    function activate(selector, value) {
        // Native DDropdown writes this property before emitting the user callback.
        selector.currentValue = value;
        selector.valueChanged(value);
    }
    function initTestCase() {
        vpn = Nord.NordVpnService;
        tryVerify(() => TransportState.activeRequests === 0 && !vpn.current
            && vpn.queue.length === 0 && !vpn.statusRequest, 5000);
        const serviceKeys = ["status", "settings", "capabilities", "countries", "groups", "cities", "citiesCountry",
            "cityCatalogs", "cityCatalogUpdated", "cityCatalogAttempts", "cityPreloadAttempts", "errorMessage",
            "settingsError", "errorCode", "actionError", "busy", "reading", "pendingLabel", "version", "queue",
            "current", "lastLocations", "consumers", "activePanels", "actionRevision", "statusReadSequence",
            "latestStatusSequence", "probeFinished", "lastProbeAttempt", "cacheStore", "cacheInitialized",
            "restoredCatalogs", "preloadIntervalMs", "preloadPriorities", "statusWanted"];
        const transportKeys = ["connected", "killSwitch", "lastRequest", "actionCount", "locationReadCount",
            "cityReadCount", "responsePlans", "requests", "events", "latencyMs", "clockOverride", "nextRequestId",
            "activeRequests", "maxActiveRequests", "activeMainRequests", "maxActiveMainRequests",
            "activeStatusRequests", "maxActiveStatusRequests"];
        const serviceCopy = {}, transportCopy = {};
        serviceKeys.forEach(key => { serviceCopy[key] = vpn[key]; });
        transportKeys.forEach(key => { transportCopy[key] = TransportState[key]; });
        savedService = serviceCopy; savedTransport = transportCopy; savedPreferences = PluginService.values;
        compare(vpn.consumers, 0, "Protocol checks must own their test surface");
        vpn.preloadIntervalMs = 3600000;
        TransportState.resetTransport();
        TransportState.connected = false;
        TransportState.planResponse({operation: "status", payload: {ok: true, status: {state: "disconnected"}}});
        TransportState.planResponse({operation: "locations", payload: {ok: true, countries: [], groups: []}});
        TransportState.planResponse({operation: "probe", payload: modernCapabilities()});
        TransportState.planResponse({operation: "snapshot", payload: snapshot(modernSettings())});
        panel = panelComponent.createObject(tests);
        verify(panel !== null);
        idle();
        panel.tabIndex = 2;
        compare(actionRequests().length, 0, "Opening the settings panel must not send a setter");
    }
    function init() { configure(modernSettings()); TransportState.resetTransport(); }
    function cleanup() {
        idle();
        compare(TransportState.responsePlans.length, 0, "Every planned reply must correspond to a request");
    }
    function cleanupTestCase() {
        if (panel) { panel.destroy(); panel = null; wait(0); }
        idle();
        Object.keys(savedService).forEach(key => { vpn[key] = savedService[key]; });
        Object.keys(savedTransport).forEach(key => { TransportState[key] = savedTransport[key]; });
        PluginService.values = savedPreferences;
    }
    function test_01_modern_snapshot_has_protocol_and_notify_without_technology() {
        verify(vpn.settings.technology === undefined);
        verify(child("connectionCard").visible);
        verify(child("protocolSelector").visible);
        compare(child("protocolSelector").options, protocolLabels);
        compare(child("protocolSelector").currentValue, "NordLynx");
        verify(!child("technologySelector").visible);
        verify(!child("transportSelector").visible);
        const notify = child("settingToggle_notify");
        verify(notify.visible); verify(notify.enabled); compare(notify.checked, true);
    }
    function test_02_modern_choices_dispatch_exact_cli_values_and_wait_for_snapshot() {
        const selector = child("protocolSelector");
        for (const index of [1, 2, 3, 0]) {
            const previous = vpn.settings.protocol, before = TransportState.requests.length;
            respondToSetting(modernSettings(protocolValues[index]), 80);
            activate(selector, protocolLabels[index]);
            compare(vpn.busy, true);
            compare(vpn.settings.protocol, previous, "Selecting a protocol must not optimistically replace the snapshot");
            compare(selector.currentValue, protocolLabels[protocolValues.indexOf(previous)], "Native optimistic writes must restore snapshot binding");
            compare(actionRequests(before), [{name: "set", key: "protocol", value: protocolValues[index]}]);
            idle();
            compare(vpn.settings.protocol, protocolValues[index]);
            compare(selector.currentValue, protocolLabels[index]);
        }
    }
    function test_03_authoritative_readback_can_keep_previous_protocol() {
        const selector = child("protocolSelector"), before = TransportState.requests.length;
        respondToSetting(modernSettings("nordlynx"));
        activate(selector, "OpenVPN (TCP)");
        idle();
        compare(actionRequests(before), [{name: "set", key: "protocol", value: "openvpn_tcp"}]);
        compare(vpn.settings.protocol, "nordlynx");
        compare(selector.currentValue, "NordLynx", "The actual snapshot remains the source of truth");
    }
    function test_04_only_advertised_protocols_are_offered_or_dispatched() {
        configure(modernSettings(), modernCapabilities(["nordlynx", "openvpn_tcp"]));
        const selector = child("protocolSelector");
        compare(selector.options, ["NordLynx", "OpenVPN (TCP)"]);
        const before = TransportState.requests.length;
        activate(selector, "OpenVPN (UDP)");
        activate(selector, "NordWhisper");
        activate(selector, "unknown-protocol");
        wait(80);
        compare(actionRequests(before), [], "An unadvertised value must never reach the CLI");
        respondToSetting(modernSettings("openvpn_tcp"));
        activate(selector, "OpenVPN (TCP)"); idle();
        compare(actionRequests(before), [{name: "set", key: "protocol", value: "openvpn_tcp"}]);
    }
    function test_05_missing_or_unknown_capabilities_never_invent_protocol_choices() {
        for (const protocols of [[], ["future_protocol"]]) {
            configure(modernSettings(), modernCapabilities(protocols));
            compare(child("protocolSelector").options, []);
            const before = TransportState.requests.length;
            activate(child("protocolSelector"), "NordWhisper");
            wait(50); compare(actionRequests(before), []);
        }
        configure(modernSettings(), {ok: true, commands: [], settingKeys: ["protocol", "notify"]});
        verify(!child("protocolSelector").visible, "Unknown help format cannot activate the unified selector");
        verify(!child("technologySelector").visible);
        compare(actionRequests().length, 0);
    }
    function test_06_notify_boolean_action_and_snapshot_reconciliation() {
        const notify = child("settingToggle_notify"), before = TransportState.requests.length;
        // A successful action can still read back the previous setting; display that fact.
        respondToSetting(modernSettings(), 80);
        notify.toggled(false);
        compare(vpn.busy, true); compare(notify.checked, true);
        compare(actionRequests(before), [{name: "set", key: "notify", value: false}]);
        idle(); compare(notify.checked, true);
        const next = modernSettings(); next.notify = false;
        respondToSetting(next); notify.toggled(false); idle();
        compare(vpn.settings.notify, false); compare(notify.checked, false);
        respondToSetting(modernSettings()); notify.toggled(true); idle();
        compare(actionRequests(before).map(request => request.value), [false, false, true]);
        compare(notify.checked, true);
    }
    function test_07_legacy_technology_and_openvpn_transport_are_retained() {
        const capabilities = {ok: true, version: "NordVPN 4 fixture", commands: ["connect", "disconnect"],
            settingKeys: ["technology", "protocol", "notify"],
            technologies: ["NORDLYNX", "OPENVPN", "NORDWHISPER"], protocols: ["UDP", "TCP"], protocolMode: "legacy"};
        configure({technology: "NORDLYNX", protocol: "UDP", notify: false}, capabilities);
        const technology = child("technologySelector"), transport = child("transportSelector");
        verify(child("connectionCard").visible); verify(technology.visible);
        verify(!child("protocolSelector").visible); verify(!transport.visible);
        compare(technology.options, capabilities.technologies); compare(technology.currentValue, "NORDLYNX");
        let before = TransportState.requests.length;
        respondToSetting({technology: "OPENVPN", protocol: "UDP", notify: false});
        activate(technology, "OPENVPN"); idle();
        compare(actionRequests(before), [{name: "set", key: "technology", value: "OPENVPN"}]);
        verify(transport.visible); compare(transport.options, ["UDP", "TCP"]); compare(transport.currentValue, "UDP");
        before = TransportState.requests.length;
        respondToSetting({technology: "OPENVPN", protocol: "TCP", notify: false});
        activate(transport, "TCP"); idle();
        compare(actionRequests(before), [{name: "set", key: "protocol", value: "TCP"}]);
        compare(transport.currentValue, "TCP");
    }
    function test_08_refresh_and_dropdown_readback_changes_send_no_setters() {
        const before = TransportState.requests.length;
        TransportState.planResponse({operation: "status", payload: {ok: true, status: {state: "disconnected"}}});
        TransportState.planResponse({operation: "snapshot", payload: snapshot(modernSettings("openvpn_udp"))});
        vpn.refresh(); idle();
        compare(child("protocolSelector").currentValue, "OpenVPN (UDP)");
        compare(actionRequests(before), []);
        configure(modernSettings("nordwhisper"), modernCapabilities(["nordwhisper", "openvpn_tcp"]));
        compare(child("protocolSelector").options, ["NordWhisper", "OpenVPN (TCP)"]);
        compare(child("protocolSelector").currentValue, "NordWhisper");
        compare(actionRequests(before), [], "Capability and currentValue bindings must not invoke a setter");
    }
    function test_09_post_quantum_support_follows_unified_protocol() {
        const toggle = child("settingToggle_post-quantum");
        verify(toggle.visible); verify(toggle.enabled);
        for (const protocol of ["openvpn_udp", "openvpn_tcp", "nordwhisper"]) {
            configure(modernSettings(protocol));
            verify(!toggle.enabled, "Post-quantum must not enable for " + protocol);
            const checked = modernSettings(protocol); checked["post-quantum"] = true;
            configure(checked); verify(toggle.enabled, "An enabled setting can still be turned off");
        }
        const mesh = modernSettings(); mesh.meshnet = true;
        configure(mesh); verify(!toggle.enabled);
        configure(modernSettings()); verify(toggle.enabled);
        compare(actionRequests().length, 0);
    }
}
