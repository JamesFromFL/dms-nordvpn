pragma Singleton
import QtQuick
import "CatalogFixture.js" as Fixture
QtObject {
    property bool connected: false
    property bool killSwitch: true
    property var lastRequest: ({})
    property int actionCount: 0
    property int locationReadCount: 0
    property var countryNames: Fixture.countries
    property var catalog: Fixture.cities
    // Read-only NordVPN U.S. CLI/catalog snapshot used as an independent fixture.
    property var usCities: ["Chicago", "Albuquerque", "Anchorage", "Ashburn", "Atlanta", "Baltimore", "Billings", "Boise", "Boston", "Buffalo", "Burlington", "Charleston", "Charlotte", "Cheyenne", "Columbus", "Dallas", "Denver", "Des_Moines", "Detroit", "Fargo", "Honolulu", "Houston", "Huntington", "Indianapolis", "Jackson", "Kansas_City", "Las_Vegas", "Lewiston", "Little_Rock", "Los_Angeles", "Louisville", "McAllen", "Miami", "Milwaukee", "Minneapolis", "Montgomery", "Nashua", "Nashville", "New_Haven", "New_Orleans", "New_York", "Oklahoma_City", "Omaha", "Phoenix", "Pittsburgh", "Portland", "Providence", "Saint_Louis", "Salt_Lake_City", "San_Francisco", "Seattle", "Sioux_Falls", "Trenton", "Wichita", "Wilmington", "Unmapped_City"]
    property var cityReadCount: ({})
    // Plans affect one matching request, never the live NordVPN process.
    property var responsePlans: []
    property var requests: []
    property var events: []
    property int latencyMs: 30
    property real clockOverride: 0
    property int nextRequestId: 0
    property int activeRequests: 0
    property int maxActiveRequests: 0
    property int activeMainRequests: 0
    property int maxActiveMainRequests: 0
    property int activeStatusRequests: 0
    property int maxActiveStatusRequests: 0
    function planResponse(plan) { responsePlans = responsePlans.concat([plan]); }
    function beginRequest(operation, args) {
        const index = responsePlans.findIndex(p => (!p.operation || p.operation === operation)
            && (!p.country || p.country === args[0]));
        const plan = index < 0 ? {} : responsePlans[index];
        if (index >= 0) responsePlans = responsePlans.filter((_, i) => i !== index);
        const request = {id: ++nextRequestId, operation, args: args.slice(), plan,
            channel: operation === "status" ? "status" : "main",
            startedAt: clockOverride > 0 ? clockOverride : Date.now()};
        requests = requests.concat([request]);
        activeRequests++;
        maxActiveRequests = Math.max(maxActiveRequests, activeRequests);
        if (request.channel === "status") {
            activeStatusRequests++;
            maxActiveStatusRequests = Math.max(maxActiveStatusRequests, activeStatusRequests);
        } else {
            activeMainRequests++;
            maxActiveMainRequests = Math.max(maxActiveMainRequests, activeMainRequests);
        }
        recordEvent(request, "requested");
        return request;
    }
    function recordEvent(request, phase) {
        events = events.concat([{id: request.id, operation: request.operation,
            phase, at: Date.now()}]);
    }
    function endProcess(request) {
        // A collector can close after exit; only the process occupies its lane.
        if (request.processEnded) return;
        request.processEnded = true;
        if (request.channel === "status") activeStatusRequests--;
        else activeMainRequests--;
    }
    function endRequest(request) {
        activeRequests--;
        recordEvent(request, "complete");
    }
    function resetTransport() {
        responsePlans = []; requests = []; events = [];
        latencyMs = 30; clockOverride = 0; maxActiveRequests = activeRequests;
        maxActiveMainRequests = activeMainRequests;
        maxActiveStatusRequests = activeStatusRequests;
    }
    function snapshot() { return { ok:true, status: { state:connected ? "connected":"disconnected", country:connected?"United States":"", city:connected ? (lastRequest.city || "Chicago").replace(/_/g," ") : "", server:connected?"test-server":"", technology:"NORDLYNX" }, settings: { killswitch:killSwitch, technology:"NORDLYNX", protocol:"UDP", dns:"disabled", protection:true, "post-quantum":false, meshnet:false } }; }
}
