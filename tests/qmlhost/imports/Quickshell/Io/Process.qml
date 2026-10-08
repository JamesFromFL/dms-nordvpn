import QtQuick
QtObject {
    id: root
    property var command: []
    property bool running: false
    property var stdout: null
    property var stderr: null
    signal started()
    signal exited(int exitCode, int exitStatus)
    function response(operation, args) {
        if (operation === "probe") return {ok:true,version:"Test fixture",commands:["connect","disconnect","pause"],settingKeys:["killswitch","technology","protocol","dns","protection","post-quantum","meshnet"],technologies:["NORDLYNX","OPENVPN","NORDWHISPER"]};
        if (operation === "snapshot") return TransportState.snapshot();
        if (operation === "status") return {ok:true,status:TransportState.snapshot().status};
        if (operation === "locations") {
            TransportState.locationReadCount++;
            return {ok:true,countries:TransportState.countryNames,groups:["Double_VPN","Onion_Over_VPN"]};
        }
        if (operation === "cities") {
            const country = args[0];
            TransportState.cityReadCount = Object.assign({}, TransportState.cityReadCount,
                {[country]: (TransportState.cityReadCount[country] || 0) + 1});
            return {ok:true,country,cities:country === "United_States" ? TransportState.usCities : TransportState.catalog[country] || []};
        }
        if (operation === "action") {
            const request = JSON.parse(args[0]);
            TransportState.actionCount++;
            TransportState.lastRequest = request;
            if (request.name === "connect") TransportState.connected = true;
            if (request.name === "disconnect") TransportState.connected = false;
            if (request.key === "killswitch") TransportState.killSwitch = request.value;
            return {ok:true,snapshot:TransportState.snapshot()};
        }
        return {ok:false,error:"fixture-operation",message:"Unknown fixture operation"};
    }
    onRunningChanged: {
        if (!running) return;
        stdout.fixtureBegin(); stderr.fixtureBegin();
        const python = command.findIndex(arg => /^python3(?:\.\d+)?$/.test(arg.split("/").pop()));
        const operationIndex = python < 0 ? 2 : python + 2;
        const request = TransportState.beginRequest(command[operationIndex], command.slice(operationIndex + 1));
        const plan = request.plan;
        request.payload = plan.failedStart ? null : plan.payload === undefined ? response(request.operation, request.args) : plan.payload;
        request.stdoutText = plan.stdoutText === undefined ? JSON.stringify(request.payload) : plan.stdoutText;
        request.stderrText = plan.stderrText || "";
        jobComponent.createObject(root, {request});
    }
    property Component jobComponent: Component {
        QtObject {
            id: job
            required property var request
            property int delivered: 0
            readonly property var plan: request.plan
            readonly property int latency: plan.latencyMs === undefined ? TransportState.latencyMs : plan.latencyMs
            readonly property bool exitFirst: plan.order === "exit-first"
            function done() {
                delivered++;
                if (delivered < (plan.failedStart ? 1 : 3)) return;
                TransportState.endRequest(request);
                destroy();
            }
            property var startTimer: Timer {
                interval: 0
                running: !job.plan.failedStart
                onTriggered: { TransportState.recordEvent(job.request, "started"); root.started(); }
            }
            property var stdoutTimer: Timer {
                interval: job.plan.stdoutDelayMs === undefined ? job.latency + (job.exitFirst ? 30 : 0) : job.plan.stdoutDelayMs
                running: !job.plan.failedStart
                onTriggered: {
                    TransportState.recordEvent(job.request, "stdout");
                    root.stdout.fixtureFinish(job.request.stdoutText); job.done();
                }
            }
            property var stderrTimer: Timer {
                interval: job.plan.stderrDelayMs === undefined ? job.latency + (job.exitFirst ? 30 : 0) : job.plan.stderrDelayMs
                running: !job.plan.failedStart
                onTriggered: {
                    TransportState.recordEvent(job.request, "stderr");
                    root.stderr.fixtureFinish(job.request.stderrText); job.done();
                }
            }
            property var exitTimer: Timer {
                interval: job.plan.exitDelayMs === undefined ? job.latency : job.plan.exitDelayMs
                running: true
                onTriggered: {
                    TransportState.recordEvent(job.request, job.plan.failedStart ? "failed-start" : "exit");
                    TransportState.endProcess(job.request);
                    root.running = false;
                    if (!job.plan.failedStart) root.exited(job.plan.exitCode || 0, job.plan.crash ? 1 : 0);
                    job.done();
                }
            }
        }
    }
}
