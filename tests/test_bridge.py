import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("bridge", Path(__file__).parents[1] / "scripts/nord_bridge.py")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class ParserTests(unittest.TestCase):
    def test_connected_details(self):
        parsed = bridge.parse_status("\x1b[32mStatus: Connected\x1b[0m\nCurrent server: us123.nordvpn.com\nCountry: United States\nCity: Chicago\nCurrent technology: NORDLYNX\nUptime: 4 minutes")
        self.assertEqual(parsed["state"], "connected")
        self.assertEqual(parsed["server"], "us123.nordvpn.com")
        self.assertEqual(parsed["country"], "United States")

    def test_unknown_cannot_be_connected(self):
        self.assertEqual(bridge.parse_status("Connecting to server us123…")["state"], "unknown")

    def test_disconnected(self):
        self.assertEqual(bridge.parse_status("Status: Disconnected")["state"], "disconnected")

    def test_pause(self):
        self.assertEqual(bridge.parse_status("Status: Disconnected\nVPN connection is paused until 12:00")["state"], "paused")

    def test_settings_aliases_and_unknowns(self):
        data = bridge.parse_settings("Technology: NORDLYNX\nKill Switch: enabled\nLAN Discovery: disabled\nThreat Protection Lite: enabled\nPost-quantum VPN: disabled\nDNS: 1.1.1.1\nUnknown Thing: enabled")
        self.assertTrue(data["killswitch"])
        self.assertFalse(data["lan-discovery"])
        self.assertTrue(data["protection"])
        self.assertFalse(data["post-quantum"])
        self.assertNotIn("Unknown Thing", data)

    def test_unknown_boolean_is_not_false(self):
        self.assertNotIn("killswitch", bridge.parse_settings("Kill Switch: unavailable"))

    def test_notification_labels_from_both_cli_generations(self):
        for label in ("Notifications", "Notify"):
            for state, expected in (("enabled", True), ("disabled", False)):
                with self.subTest(label=label, state=state):
                    self.assertEqual(bridge.parse_settings(f"{label}: {state}"), {"notify": expected})
            self.assertNotIn("notify", bridge.parse_settings(f"{label}: unavailable"))

    def test_lists(self):
        self.assertEqual(bridge.parse_list("United_States   France\n\x1b[32mJapan\x1b[0m"), ["France", "Japan", "United_States"])

    def test_list_rejects_error_prose(self):
        with self.assertRaises(ValueError):
            bridge.parse_list("We couldn't reach System Daemon.")


class ActionTests(unittest.TestCase):
    def test_country_city_group_are_separate_arguments(self):
        self.assertEqual(bridge.action_args({"name": "connect", "country": "United_States", "city": "Chicago", "group": "Double_VPN"}), ["connect", "--group", "Double_VPN", "United_States", "Chicago"])

    def test_fastest(self):
        self.assertEqual(bridge.action_args({"name": "connect"}), ["connect"])

    def test_server(self):
        self.assertEqual(bridge.action_args({"name": "connect", "server": "uk715"}), ["connect", "uk715"])

    def test_injection_and_flags_rejected(self):
        for value in ("--help", "us;touch /tmp/bad", "$(whoami)", "United_States\nlogout", "../../etc/passwd"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                bridge.action_args({"name": "connect", "country": value})

    def test_boolean_values_are_typed(self):
        self.assertEqual(bridge.action_args({"name": "set", "key": "killswitch", "value": True}), ["set", "killswitch", "on"])
        with self.assertRaises(ValueError):
            bridge.action_args({"name": "set", "key": "killswitch", "value": "off"})

    def test_protocol_and_technology_arguments_match_the_cli(self):
        for value in ("nordlynx", "openvpn_udp", "openvpn_tcp", "nordwhisper", "UDP", "TCP"):
            with self.subTest(protocol=value):
                self.assertEqual(bridge.action_args({"name": "set", "key": "protocol", "value": value}), ["set", "protocol", value])
        for value in ("NORDLYNX", "OPENVPN", "NORDWHISPER"):
            with self.subTest(technology=value):
                self.assertEqual(bridge.action_args({"name": "set", "key": "technology", "value": value}), ["set", "technology", value])

    def test_protocol_and_technology_reject_non_strings_and_unlisted_values(self):
        invalid = (None, True, 1, [], {}, "--help", "nordlynx;logout", "$(whoami)", "openvpn_udp\nlogout", "nordlynx extra", "AUTO")
        for key in ("protocol", "technology"):
            for value in invalid:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    bridge.action_args({"name": "set", "key": key, "value": value})
        for key in (None, True, 1, [], {}):
            with self.subTest(key=key), self.assertRaises(ValueError):
                bridge.action_args({"name": "set", "key": key, "value": "UDP"})

    def test_dns(self):
        self.assertEqual(bridge.action_args({"name": "set", "key": "dns", "value": "1.1.1.1 1.0.0.1"}), ["set", "dns", "1.1.1.1", "1.0.0.1"])
        for value in ("1.2.3.999", "::1", "1.1.1.1;logout", "1.1.1.1 " * 4):
            with self.subTest(value=value), self.assertRaises(ValueError):
                bridge.action_args({"name": "set", "key": "dns", "value": value})

    def test_only_supported_pause_duration(self):
        self.assertEqual(bridge.action_args({"name": "pause", "duration": "5m"}), ["pause", "5m"])
        with self.assertRaises(ValueError):
            bridge.action_args({"name": "pause", "duration": "2m"})

    def test_arbitrary_actions_rejected(self):
        for request in ({"name": "logout"}, {"name": "set", "key": "firewall", "value": False}, {"name": "disconnect", "extra": "x"}, {"name": "connect", "city": "London"}):
            with self.subTest(request=request), self.assertRaises(ValueError):
                bridge.action_args(request)


class ProbeTests(unittest.TestCase):
    # Real supported-values forms from NordVPN 6.0.2 and official 5.4.1 CLI help.
    MODERN_HELP = """Usage: nordvpn set protocol [command options] <protocol>

Use this command to set the protocol for VPN connection.
Supported values for <protocol>: nordlynx, openvpn_udp, openvpn_tcp, nordwhisper

Example: 'nordvpn set protocol nordlynx'
"""
    LEGACY_PROTOCOL_HELP = """Use this command to set the protocol to TCP or UDP.
Supported values for <protocol>: TCP, UDP

Example: 'nordvpn set protocol TCP'
Note: This option is not applicable to NordLynx.
"""
    LEGACY_TECHNOLOGY_HELP = """Use this command to set the technology.
Supported values for <technology>: OPENVPN, NORDLYNX or NORDWHISPER.

Example: 'nordvpn set technology OPENVPN'
"""

    def probe_with(self, keys, protocol=None, technology=None, settings_ok=True, commands=("connect", "disconnect", "set")):
        responses = {
            ("help",): {"ok": True, "text": "Commands:\n" + "".join(f"   {name}  Description\n" for name in commands)},
            ("--version",): {"ok": True, "text": "An unfamiliar version string"},
        }
        if "set" in commands:
            responses[("set", "--help")] = {"ok": settings_ok, "text": "Subcommands:\n" + "".join(f"   {key}  Description\n" for key in keys)}
        for key, response in (("protocol", protocol), ("technology", technology)):
            if response is not None:
                responses[("set", key, "--help")] = response if isinstance(response, dict) else {"ok": True, "text": response}
        with patch.object(bridge, "run_cli", side_effect=lambda args: responses[tuple(args)]) as run:
            result = bridge.probe()
        return result, [call.args[0] for call in run.call_args_list]

    def test_unified_protocol_discovery_without_a_technology_command(self):
        result, calls = self.probe_with(("protocol", "notify"), protocol=self.MODERN_HELP)
        self.assertEqual(result["protocolMode"], "unified")
        self.assertEqual(result["protocols"], ["nordlynx", "openvpn_udp", "openvpn_tcp", "nordwhisper"])
        self.assertEqual(result["technologies"], [])
        self.assertEqual(result["settingKeys"], ["protocol", "notify"])
        self.assertNotIn(["set", "technology", "--help"], calls)
        self.assertEqual(result["version"], "An unfamiliar version string")

    def test_legacy_protocols_and_technology_remain_separate(self):
        result, calls = self.probe_with(("technology", "protocol"), protocol=self.LEGACY_PROTOCOL_HELP, technology=self.LEGACY_TECHNOLOGY_HELP)
        self.assertEqual(result["protocolMode"], "legacy")
        self.assertEqual(result["protocols"], ["UDP", "TCP"])
        self.assertEqual(result["technologies"], ["NORDLYNX", "OPENVPN", "NORDWHISPER"])
        self.assertIn(["set", "technology", "--help"], calls)
        self.assertIn(["set", "protocol", "--help"], calls)

    def test_only_advertised_protocol_subset_is_exposed(self):
        for values, expected, mode in (
            ("nordlynx, openvpn_udp", ["nordlynx", "openvpn_udp"], "unified"),
            ("openvpn_tcp", ["openvpn_tcp"], "unified"),
            ("TCP", ["TCP"], "legacy"),
            ("udp", ["UDP"], "legacy"),
        ):
            with self.subTest(values=values):
                help_text = f"Supported values for <protocol>: {values}\n\nExample: nordwhisper\nFootnote: NORDLYNX is unavailable."
                result, _ = self.probe_with(("protocol",), protocol=help_text)
                self.assertEqual(result["protocolMode"], mode)
                self.assertEqual(result["protocols"], expected)

    def test_enum_tokens_do_not_match_substrings(self):
        result, _ = self.probe_with(("technology", "protocol"), protocol="Supported values for <protocol>: old_nordlynx, openvpn_udp_extra, UDP2, TCP-beta", technology="Supported values for <technology>: OPENVPN, NOT_NORDLYNX, NORDWHISPER-beta")
        self.assertEqual(result["technologies"], ["OPENVPN"])
        self.assertEqual(result["protocolMode"], "unknown")
        self.assertEqual(result["protocols"], [])

    def test_examples_and_footnotes_are_not_capability_evidence(self):
        for help_text in (
            "Example: nordvpn set protocol nordlynx\nNote: Supports NordLynx.",
            "Supported values for <protocol>:\n\nNordLynx is not available.",
            "Supported values for <technology>: NORDLYNX",
            "Supported values for <protocol>: imaginary\n\nNote: Switch technology to NordLynx.",
        ):
            with self.subTest(help_text=help_text):
                result, _ = self.probe_with(("protocol",), protocol=help_text)
                self.assertEqual(result["protocolMode"], "unknown")
                self.assertEqual(result["protocols"], [])

    def test_mixed_unfamiliar_schema_does_not_guess_a_mode(self):
        result, _ = self.probe_with(("protocol",), protocol="Supported values for <protocol>: TCP, nordlynx")
        self.assertEqual(result["protocolMode"], "unknown")
        self.assertEqual(result["protocols"], [])

    def test_failed_child_help_cannot_supply_capabilities(self):
        result, _ = self.probe_with(("technology", "protocol"), protocol={"ok": False, "text": self.MODERN_HELP}, technology={"ok": False, "text": self.LEGACY_TECHNOLOGY_HELP})
        self.assertTrue(result["ok"])
        self.assertEqual(result["protocolMode"], "unknown")
        self.assertEqual(result["protocols"], [])
        self.assertEqual(result["technologies"], [])

    def test_failed_settings_help_does_not_query_hidden_commands(self):
        result, calls = self.probe_with(("technology", "protocol"), settings_ok=False)
        self.assertEqual(result["settingKeys"], [])
        self.assertEqual(result["protocolMode"], "unknown")
        self.assertEqual(result["protocols"], [])
        self.assertEqual(result["technologies"], [])
        self.assertEqual(calls, [["help"], ["set", "--help"], ["--version"]])

    def test_unadvertised_setting_commands_are_not_probed(self):
        result, calls = self.probe_with(("notify", "killswitch"))
        self.assertEqual(result["protocolMode"], "unknown")
        self.assertEqual(result["protocols"], [])
        self.assertEqual(result["technologies"], [])
        self.assertEqual(calls, [["help"], ["set", "--help"], ["--version"]])

    def test_set_help_is_only_read_when_set_is_advertised(self):
        result, calls = self.probe_with((), commands=("connect", "disconnect"))
        self.assertEqual(result["settingKeys"], [])
        self.assertEqual(result["protocolMode"], "unknown")
        self.assertEqual(calls, [["help"], ["--version"]])

    @patch.object(bridge, "run_cli", return_value={"ok": False, "error": "cli-missing", "message": "Install NordVPN."})
    def test_main_help_failure_stops_probe(self, run):
        self.assertEqual(bridge.probe()["error"], "cli-missing")
        run.assert_called_once_with(["help"])


class CommandTests(unittest.TestCase):
    @patch.object(bridge, "run_cli", return_value={"ok": True, "text": "Status: Connected\nCountry: United States\nCity: Miami"})
    def test_status_only_does_not_read_settings(self, run):
        result = bridge.dispatch(["status"])
        run.assert_called_once_with(["status"])
        self.assertEqual(set(result), {"ok", "status", "error", "message"})
        self.assertTrue(result["ok"])
        self.assertEqual(result["status"]["state"], "connected")
        self.assertEqual(result["status"]["city"], "Miami")
        self.assertNotIn("settings", result)

    @patch.object(bridge, "run_cli", return_value={"ok": False, "error": "daemon-unavailable", "message": "We couldn't reach System Daemon."})
    def test_status_only_does_not_preserve_unconfirmed_connection(self, run):
        result = bridge.dispatch(["status"])
        run.assert_called_once_with(["status"])
        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], {"state": "unknown"})
        self.assertEqual(result["error"], "daemon-unavailable")
        self.assertNotIn("settings", result)

    @patch.object(bridge, "run_cli", return_value={"ok": True, "text": "Unexpected connection output"})
    def test_status_only_rejects_unrecognized_output(self, run):
        result = bridge.dispatch(["status"])
        run.assert_called_once_with(["status"])
        self.assertFalse(result["ok"])
        self.assertEqual(result["status"]["state"], "unknown")
        self.assertEqual(result["error"], "unrecognized-output")
        self.assertNotIn("settings", result)

    @patch.object(bridge.os, "nice")
    @patch.object(bridge, "run_cli", return_value={"ok": True, "text": "New_York Miami Miami"})
    def test_background_cities_have_short_budget_and_lower_priority(self, run, nice):
        result = bridge.dispatch(["cities", "United_States", "--background"])
        nice.assert_called_once_with(10)
        run.assert_called_once_with(["cities", "United_States"], timeout=2)
        self.assertEqual(result, {"ok": True, "country": "United_States", "cities": ["Miami", "New_York"]})

    @patch.object(bridge.os, "nice", side_effect=OSError("Priority adjustment unavailable"))
    @patch.object(bridge, "run_cli", return_value={"ok": True, "text": "Miami"})
    def test_background_cities_priority_is_best_effort(self, run, nice):
        self.assertTrue(bridge.dispatch(["cities", "United_States", "--background"])["ok"])
        nice.assert_called_once_with(10)
        run.assert_called_once_with(["cities", "United_States"], timeout=2)

    @patch.object(bridge.os, "nice")
    @patch.object(bridge, "run_cli", return_value={"ok": True, "text": "Miami"})
    def test_foreground_cities_keep_normal_budget_and_priority(self, run, nice):
        self.assertTrue(bridge.dispatch(["cities", "United_States"])["ok"])
        run.assert_called_once_with(["cities", "United_States"])
        nice.assert_not_called()

    @patch.object(bridge.os, "nice")
    @patch.object(bridge, "run_cli")
    def test_city_options_and_identifiers_are_validated_before_running(self, run, nice):
        for args in (["cities", "United_States", "--other"], ["cities", "--help", "--background"], ["cities", "United_States;logout", "--background"], ["cities", "United_States", "--background", "extra"], ["status", "extra"]):
            with self.subTest(args=args), self.assertRaises(ValueError):
                bridge.dispatch(args)
        run.assert_not_called()
        nice.assert_not_called()

    @patch.object(bridge.shutil, "which", return_value=None)
    def test_missing_cli(self, _):
        self.assertEqual(bridge.run_cli(["status"])["error"], "cli-missing")

    @patch.object(bridge.shutil, "which", return_value="/usr/bin/nordvpn")
    @patch.object(bridge.subprocess, "run", side_effect=subprocess.TimeoutExpired("nordvpn", 12))
    def test_timeout(self, _, __):
        self.assertEqual(bridge.run_cli(["status"])["error"], "timeout")

    @patch.object(bridge.shutil, "which", return_value="/usr/bin/nordvpn")
    @patch.object(bridge.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "We couldn't reach System Daemon.", ""))
    def test_semantic_failure_with_zero_exit(self, _, __):
        self.assertEqual(bridge.run_cli(["status"])["error"], "daemon-unavailable")

    @patch.object(bridge, "run_cli", return_value={"ok": False, "error": "logged-out", "message": "Please log in."})
    def test_snapshot_drops_stale_status(self, _):
        result = bridge.snapshot()
        self.assertEqual(result["status"]["state"], "unknown")
        self.assertEqual(result["settings"], {})

    @patch.object(bridge, "run_cli", side_effect=[{"ok": True, "text": "Connected successfully"}, {"ok": True, "text": "Status: Disconnected"}, {"ok": True, "text": "Kill Switch: enabled"}])
    def test_successful_action_does_not_claim_connected(self, _):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory}):
            self.assertEqual(bridge.action({"name": "connect"})["snapshot"]["status"]["state"], "disconnected")

    @patch.object(bridge, "run_cli", side_effect=[{"ok": True, "text": "Status: Connected"}, {"ok": False, "message": "Settings unavailable"}])
    def test_connection_survives_settings_failure(self, _):
        result = bridge.snapshot()
        self.assertEqual(result["status"]["state"], "connected")
        self.assertEqual(result["settings"], {})
        self.assertEqual(result["settingsError"], "Settings unavailable")


if __name__ == "__main__":
    unittest.main()
