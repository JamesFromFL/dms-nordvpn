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
