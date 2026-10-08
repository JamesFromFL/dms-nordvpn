#!/usr/bin/env python3
"""Small, bounded CLI adapter. No shell, credentials, or VPN implementation."""
import fcntl
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
TOKEN = re.compile(r"[A-Za-z][A-Za-z0-9_-]{0,79}\Z")
BOOL_KEYS = {
    "killswitch", "autoconnect", "protection", "notify", "meshnet", "obfuscate",
    "lan-discovery", "virtual-location", "post-quantum", "analytics", "ech",
}
LABELS = {
    "kill switch": "killswitch", "auto-connect": "autoconnect",
    "real-time protection": "protection", "threat protection lite": "protection",
    "threat protection": "protection", "cybersec": "protection",
    "notifications": "notify", "lan discovery": "lan-discovery",
    "virtual location": "virtual-location", "virtual locations": "virtual-location",
    "post-quantum vpn": "post-quantum", "post-quantum encryption": "post-quantum",
    "post-quantum": "post-quantum", "obfuscate": "obfuscate",
    "obfuscation": "obfuscate", "obfuscated servers": "obfuscate",
    "meshnet": "meshnet", "analytics": "analytics", "ech": "ech",
    "technology": "technology", "protocol": "protocol", "dns": "dns",
    "encrypted client hello": "ech",
}


def clean(value):
    return ANSI.sub("", value).replace("\r", "").strip()


def classify(message):
    low = message.lower()
    if "permission denied" in low or "not permitted" in low:
        return "permission-denied"
    if "daemon" in low or "connection refused" in low:
        return "daemon-unavailable"
    if any(s in low for s in ("not logged", "log in", "login first", "logged out")):
        return "logged-out"
    return "command-failed"


def run_cli(args, timeout=12):
    if not shutil.which("nordvpn"):
        return {"ok": False, "error": "cli-missing", "message": "Install the NordVPN Linux CLI."}
    try:
        p = subprocess.run(
            ["nordvpn", *args], stdin=subprocess.DEVNULL, capture_output=True,
            text=True, timeout=timeout, env={**os.environ, "LC_ALL": "C", "LANG": "C", "NO_COLOR": "1"},
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "timeout", "message": "NordVPN did not finish in time. Refresh to check its current state."}
    except OSError as exc:
        return {"ok": False, "error": "command-failed", "message": str(exc)}
    out = clean(p.stdout)
    # Nord can report semantic errors even if an older client exits successfully.
    low = (out + "\n" + clean(p.stderr)).lower()
    failed = p.returncode != 0 or any(s in low for s in (
        "couldn't reach system daemon", "cannot reach system daemon", "permission denied",
        "you are not logged in", "you're not logged in", "please log in",
    ))
    if failed:
        message = out or clean(p.stderr) or "NordVPN rejected the command."
        return {"ok": False, "error": classify(message), "message": message[:1400]}
    return {"ok": True, "text": out}


def key_values(text):
    result = {}
    for line in clean(text).splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            result[key.strip().lower()] = value.strip()
    return result


def parse_status(text):
    values = key_values(text)
    state = values.get("status", "").lower()
    if re.search(r"\bpaused?\b", clean(text), re.I):
        state = "paused"
    if state not in {"connected", "disconnected", "connecting", "disconnecting", "paused"}:
        return {"state": "unknown", "error": "unrecognized-output", "message": "The CLI returned an unfamiliar status. Protection is unconfirmed."}
    return {
        "state": state, "country": values.get("country", ""), "city": values.get("city", ""),
        "server": values.get("current server", values.get("hostname", values.get("server", ""))),
        "ip": values.get("ip", ""), "technology": values.get("current technology", values.get("technology", "")),
        "protocol": values.get("current protocol", values.get("protocol", "")),
        "uptime": values.get("uptime", ""), "transfer": values.get("transfer", ""),
    }


def parse_settings(text):
    result = {}
    for label, value in key_values(text).items():
        key = LABELS.get(label)
        if not key:
            continue
        if key in BOOL_KEYS:
            word = value.lower().split()[0] if value else ""
            if word in {"enabled", "on", "true", "1", "disabled", "off", "false", "0"}:
                result[key] = word in {"enabled", "on", "true", "1"}
        else:
            result[key] = value
    return result


def parse_list(text):
    text = clean(text)
    # CLI location lists are whitespace-separated underscore identifiers.
    # Refuse prose instead of turning an error message into location choices.
    items = text.split()
    if not items or not all(TOKEN.fullmatch(item) for item in items):
        raise ValueError("The CLI returned an unfamiliar location list.")
    return sorted(set(items), key=str.casefold)


def identifier(value):
    if not isinstance(value, str) or not TOKEN.fullmatch(value):
        raise ValueError("Invalid location identifier.")
    return value


def action_args(request):
    if not isinstance(request, dict):
        raise ValueError("An action must be an object.")
    name = request.get("name")
    if name == "connect":
        if set(request) - {"name", "country", "city", "group", "server"}:
            raise ValueError("Unknown connection option.")
        args = ["connect"]
        if request.get("server"):
            if any(request.get(k) for k in ("country", "city", "group")):
                raise ValueError("A server cannot be combined with a location or group.")
            return args + [identifier(request["server"])]
        if request.get("group"):
            args += ["--group", identifier(request["group"])]
        if request.get("city") and not request.get("country"):
            raise ValueError("Choose a country before a city.")
        for key in ("country", "city"):
            if request.get(key):
                args.append(identifier(request[key]))
        return args
    if name == "disconnect" and set(request) == {"name"}:
        return ["disconnect"]
    if name == "pause" and set(request) == {"name", "duration"}:
        if request["duration"] not in {"5m", "15m", "30m", "1h", "24h"}:
            raise ValueError("Unsupported pause duration.")
        return ["pause", request["duration"]]
    if name == "set" and set(request) == {"name", "key", "value"}:
        key, value = request["key"], request["value"]
        if key in BOOL_KEYS and isinstance(value, bool):
            return ["set", key, "on" if value else "off"]
        if key == "technology" and value in {"NORDLYNX", "OPENVPN", "NORDWHISPER"}:
            return ["set", key, value]
        if key == "protocol" and value in {"UDP", "TCP"}:
            return ["set", key, value]
        if key == "dns" and isinstance(value, str):
            if value.lower() in {"off", "disabled"}:
                return ["set", "dns", "off"]
            ips = value.split()
            if not 1 <= len(ips) <= 3 or any(ipaddress.ip_address(ip).version != 4 for ip in ips):
                raise ValueError("Enter one to three IPv4 DNS addresses.")
            return ["set", "dns", *ips]
    raise ValueError("Unsupported action or value.")


def probe():
    help_result = run_cli(["help"])
    if not help_result["ok"]:
        return help_result
    settings = run_cli(["set", "--help"])
    version = run_cli(["--version"])
    technology = run_cli(["set", "technology", "--help"])
    commands = re.findall(r"^\s+([a-z][a-z-]*)(?:,\s*\w+)?\s{2,}", help_result["text"], re.M)
    keys = re.findall(r"^\s+([a-z][a-z-]*)(?:,\s*\w+)?\s{2,}", settings.get("text", ""), re.M)
    technologies = [name for name in ("NORDLYNX", "OPENVPN", "NORDWHISPER") if name in technology.get("text", "").upper()]
    return {"ok": True, "version": version.get("text", "Unknown version"), "commands": commands, "settingKeys": keys, "technologies": technologies}


def snapshot():
    status_result = run_cli(["status"])
    if not status_result["ok"]:
        return {**status_result, "status": {"state": "unknown"}, "settings": {}}
    status = parse_status(status_result["text"])
    settings_result = run_cli(["settings"])
    return {
        "ok": "error" not in status, "status": status,
        "settings": parse_settings(settings_result["text"]) if settings_result["ok"] else {},
        "settingsError": settings_result.get("message", ""),
        "error": status.get("error", ""), "message": status.get("message", ""),
    }


def status_snapshot():
    """Confirm connection state without waiting for unrelated settings reads."""
    response = run_cli(["status"])
    if not response["ok"]:
        return {**response, "status": {"state": "unknown"}}
    status = parse_status(response["text"])
    return {
        "ok": "error" not in status, "status": status,
        "error": status.get("error", ""), "message": status.get("message", ""),
    }


def action(request):
    args = action_args(request)
    # A second shell process or reloaded plugin cannot issue a concurrent action.
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir()))
    lock = runtime / ("nordvpn-dms-" + str(os.getuid()) + ".lock")
    with lock.open("a") as file:
        try:
            fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"ok": False, "error": "busy", "message": "Another NordVPN action is still running."}
        result = run_cli(args, timeout=70)
        # Do not infer connected state from a successful action response.
        return {**result, "snapshot": snapshot()}


def dispatch(argv):
    if argv == ["probe"]:
        return probe()
    if argv == ["status"]:
        return status_snapshot()
    if argv == ["snapshot"]:
        return snapshot()
    if argv == ["locations"]:
        result = {}
        for key in ("countries", "groups"):
            response = run_cli([key])
            if not response["ok"]:
                return response
            result[key] = parse_list(response["text"])
        return {"ok": True, **result}
    if len(argv) in {2, 3} and argv[0] == "cities":
        background = len(argv) == 3
        if background and argv[2] != "--background":
            raise ValueError("Unknown city catalog option.")
        country = identifier(argv[1])
        if background:
            try:
                os.nice(10)
            except OSError:
                pass  # Scheduling priority is an optional optimization.
            response = run_cli(["cities", country], timeout=2)
        else:
            response = run_cli(["cities", country])
        return {"ok": True, "country": country, "cities": parse_list(response["text"])} if response["ok"] else response
    if len(argv) == 2 and argv[0] == "action":
        return action(json.loads(argv[1]))
    raise ValueError("Unknown bridge operation.")


def main():
    try:
        result = dispatch(sys.argv[1:])
    except (ValueError, TypeError, OSError) as exc:
        result = {"ok": False, "error": "invalid-request", "message": str(exc)}
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
