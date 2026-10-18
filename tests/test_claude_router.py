import importlib.machinery
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
router = importlib.machinery.SourceFileLoader("claude_router", str(ROOT / "bin/claude-router")).load_module()


class ClaudeRouterTests(unittest.TestCase):
    def test_status_rejects_an_unmanaged_healthy_listener(self):
        state = subprocess.CompletedProcess([], 1, "", "not loaded")
        with patch.object(router.subprocess, "check_output", return_value="claude-codex " + router.CONFIG["proxy_version"]), \
                patch.object(router, "service_state", return_value=state), \
                patch.object(router, "loaded", return_value=False), patch.object(router, "health", return_value=None):
            self.assertEqual(router.main(["status"]), 1)

    def test_macos_install_uses_this_users_home_and_does_not_start(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "different user"
            binary = home / ".local/bin/claude-codex"
            binary.parent.mkdir(parents=True)
            binary.touch()
            binary.chmod(0o755)
            plist = home / "Library/LaunchAgents/proxy.plist"
            with patch.multiple(router, HOME=home, BINARY=binary, PLIST=plist,
                                STATE=home / "state", LINUX=False), \
                    patch.object(router.sys, "platform", "darwin"), patch.object(router, "launchctl") as control:
                router.install()
                control.assert_not_called()
            config = plistlib.loads(plist.read_bytes())
            self.assertEqual(config["ProgramArguments"][0], str(binary))
            self.assertEqual(config["EnvironmentVariables"], {"HOME": str(home)})
            self.assertEqual(config["ProgramArguments"][-1], str(router.PORT))
            self.assertTrue(config["KeepAlive"])

    def test_linux_install_and_restart_use_user_systemd(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / "linux user"
            binary = home / ".local/bin/claude-codex"
            binary.parent.mkdir(parents=True)
            binary.touch()
            binary.chmod(0o755)
            unit = home / ".config/systemd/user" / router.UNIT_NAME
            with patch.multiple(router, HOME=home, BINARY=binary, UNIT=unit,
                                STATE=home / "state", LINUX=True), \
                    patch.object(router, "systemctl") as control, patch.object(router, "launchctl") as mac:
                router.install()
                control.assert_called_once_with("daemon-reload")
                text = unit.read_text()
                self.assertIn(f'ExecStart="{binary}" serve --no-monitor --port {router.PORT}', text)
                self.assertIn(f'Environment="HOME={home}"', text)
                self.assertIn("Restart=always", text)
                mac.assert_not_called()
                control.reset_mock()
                with patch.object(router, "loaded", return_value=True), \
                        patch.object(router, "job_pid", return_value=123), \
                        patch.object(router, "wait_healthy") as wait:
                    router.main(["restart"])
                    control.assert_called_once_with("restart", router.UNIT_NAME)
                    wait.assert_called_once_with(123)

    def test_linux_inactive_pid_and_start_enable_the_service(self):
        result = subprocess.CompletedProcess([], 0, "MainPID=0\nActiveState=inactive", "")
        with patch.object(router, "LINUX", True), patch.object(router, "service_state", return_value=result):
            self.assertIsNone(router.job_pid())
        with patch.object(router, "LINUX", True), patch.object(router, "UNIT") as unit, \
                patch.object(router, "loaded", return_value=False), patch.object(router, "socket") as sockets, \
                patch.object(router, "systemctl") as control, patch.object(router, "wait_healthy"):
            unit.is_file.return_value = True
            sockets.socket.return_value.__enter__.return_value.connect_ex.return_value = 1
            router.start()
            control.assert_called_once_with("enable", "--now", router.UNIT_NAME)

    def test_start_refuses_a_port_someone_else_already_owns(self):
        """The inverse of the port check: an occupied port must stop the start."""
        with patch.object(router, "LINUX", True), patch.object(router, "UNIT") as unit, \
                patch.object(router, "loaded", return_value=False), patch.object(router, "socket") as sockets, \
                patch.object(router, "systemctl") as control, patch.object(router, "wait_healthy"):
            unit.is_file.return_value = True
            sockets.socket.return_value.__enter__.return_value.connect_ex.return_value = 0
            with self.assertRaises(RuntimeError) as refusal:
                router.start()
            self.assertIn(str(router.PORT), str(refusal.exception))
            control.assert_not_called()

    def status_exit(self, *, version, loaded_job, problem):
        """`status` returning 1 unconditionally passed every earlier test."""
        state = subprocess.CompletedProcess([], 0, "MainPID=42\nActiveState=active", "")
        with patch.object(router, "LINUX", True), \
                patch.object(router.subprocess, "check_output", return_value=version), \
                patch.object(router, "service_state", return_value=state), \
                patch.object(router, "job_pid", return_value=42), \
                patch.object(router, "loaded", return_value=loaded_job), \
                patch.object(router, "health", return_value=problem):
            return router.main(["status"])

    def test_status_exit_code_separates_healthy_from_each_failure(self):
        good = f"claude-codex v{router.CONFIG['proxy_version']}\n"
        self.assertEqual(
            self.status_exit(version=good, loaded_job=True, problem=None), 0,
            "a healthy proxy must exit 0",
        )
        self.assertEqual(
            self.status_exit(version=good, loaded_job=True, problem="proxy down"), 1,
            "an unhealthy proxy must exit 1",
        )
        self.assertEqual(
            self.status_exit(version=good, loaded_job=False, problem=None), 1,
            "an unloaded service must exit 1",
        )
        self.assertEqual(
            self.status_exit(version="claude-codex v0.0.0-stale\n", loaded_job=True, problem=None), 1,
            "a version mismatch must exit 1",
        )

    def test_flag_dispatches_after_aimux_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / ".local/bin/claude-router"
            helper.parent.mkdir(parents=True)
            helper.write_text('import json,sys\nprint(json.dumps(sys.argv[1:]))\n')
            args = ["--settings", '{"hooks":{}}', "--session-id", "session", "--gpt"]
            result = subprocess.run([str(ROOT / "volta/claude"), *args],
                                    env={"HOME": directory}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), ["gpt", *args])

    def test_native_exec_preserves_arguments_environment_and_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            native = home / ".volta/bin/claude"
            native.parent.mkdir(parents=True)
            native.write_text('#!/usr/bin/python3\nimport json,os,sys\n'
                              'print(json.dumps({"args":sys.argv[1:],"env":dict(os.environ)}))\n'
                              'sys.exit(7)\n')
            native.chmod(0o755)
            environment = {"HOME": directory, "PATH": "/usr/bin:/bin", "NATIVE_MARKER": "kept"}
            args = ["--settings", '{"hooks":{"Stop":[]}}', "--resume", "session", "hello world"]
            for invocation in (args, ["--version"], ["--", "--gpt"]):
                result = subprocess.run([str(ROOT / "volta/claude"), *invocation], env=environment,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 7, result.stderr)
                captured = json.loads(result.stdout)
                self.assertEqual(captured["args"], invocation)
                self.assertEqual(captured["env"]["NATIVE_MARKER"], "kept")
                self.assertFalse(any(key in captured["env"] for key in router.GPT_ENV))

    def test_aimux_settings_file_keeps_hooks_session_and_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "aimux settings.json"
            original = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "aimux hook"}]}]},
                        "env": {"AIMUX_SESSION_ID": "session", "ANTHROPIC_BASE_URL": "old"},
                        "permissions": {"allow": ["Read"]}}
            source.write_text(json.dumps(original))
            args = router.prepare_gpt(["--settings", str(source), "--resume", "session", "--gpt"])
            merged = self.settings_payload(args)
            self.assertEqual(merged["hooks"], original["hooks"])
            self.assertEqual(merged["permissions"], original["permissions"])
            self.assertEqual(merged["env"]["AIMUX_SESSION_ID"], "session")
            self.assertEqual(merged["env"]["ANTHROPIC_BASE_URL"], router.URL)
            self.assertEqual(json.loads(source.read_text()), original)
            self.assertEqual(args[-2:], ["--resume", "session"])
            self.assertNotIn("--gpt", args)

    def test_inline_settings_model_override_and_literal_argument(self):
        args = router.prepare_gpt(["--gpt", '--settings={"env":{"CUSTOM":"kept"},"hooks":{"Stop":[]}}',
                                   "--model=gpt-6-luna", "--", "--gpt"])
        self.assertIn("--model=gpt-6-luna", args)
        self.assertNotIn("--model", args)
        self.assertEqual(args[-2:], ["--", "--gpt"])
        inline = next(arg for arg in args if arg.startswith("--settings="))
        merged = self.settings_payload([inline.split("=", 1)[1]], 0)
        self.assertEqual(merged["env"]["CUSTOM"], "kept")
        self.assertEqual(merged["hooks"], {"Stop": []})

    def settings_payload(self, args, index=None):
        """`--settings` now names a 0600 file; argv must never carry the JSON."""
        import os
        import stat
        position = args.index("--settings") + 1 if index is None else index
        path = args[position]
        self.assertFalse(path.lstrip().startswith("{"), f"settings inlined into argv: {path}")
        mode = stat.S_IMODE(os.stat(path).st_mode)
        self.assertEqual(mode, 0o600, f"settings file is {oct(mode)}, not 0600")
        with open(path) as handle:
            return json.load(handle)

    def test_default_model_and_first_settings_precedence(self):
        defaults = router.prepare_gpt(["--gpt", "--continue"])
        self.assertEqual(defaults[:2], ["--model", router.GPT_MODEL])
        self.assertEqual(self.settings_payload(defaults, 3)["env"], router.GPT_ENV)
        self.assertEqual(defaults[-1], "--continue")
        args = router.prepare_gpt(["--gpt", "--settings", '{"env":{"FIRST":"yes"}}',
                                   "--settings", '{"env":{"SECOND":"yes"}}'])
        self.assertEqual(args[:2], ["--model", router.GPT_MODEL])
        first = self.settings_payload(args)
        self.assertEqual(first["env"]["FIRST"], "yes")
        self.assertNotIn("SECOND", first["env"])
        self.assertEqual(args[-1], '{"env":{"SECOND":"yes"}}')

    def test_settings_errors_are_visible(self):
        for args in (["--settings"], ["--settings", "{bad"], ["--settings", '{"env":null}']):
            with self.assertRaises(ValueError):
                router.prepare_gpt(args)
        with self.assertRaises(FileNotFoundError):
            router.prepare_gpt(["--settings", "/nonexistent/claude-settings.json"])

    def test_gpt_execs_native_binary_with_invocation_only_environment(self):
        with patch.object(router, "health", return_value=None), patch.object(router.os, "execve") as execute:
            router.launch_gpt(["--gpt", "--resume", "session"])
            executable, args, environment = execute.call_args.args
            self.assertEqual(executable, str(router.HOME / ".volta/bin/claude"))
            self.assertEqual(args[-2:], ["--resume", "session"])
            self.assertEqual(environment["ANTHROPIC_BASE_URL"], router.URL)
        with patch.object(router, "health", return_value="connection refused"), patch.object(router.os, "execve") as execute:
            with self.assertRaisesRegex(RuntimeError, "claude-router start"):
                router.launch_gpt(["--gpt"])
            execute.assert_not_called()

    def test_restart_waits_for_new_process_and_fails_visibly(self):
        with patch.object(router, "job_pid", side_effect=[12, 13]), patch.object(router, "health", return_value=None), \
                patch.object(router.time, "sleep"):
            router.wait_healthy(previous_pid=12)
        with patch.object(router, "job_pid", return_value=12), patch.object(router, "health", return_value="down"), \
                patch.object(router.time, "sleep"), patch.object(router, "service_state") as control:
            control.return_value.stdout = "last exit code = 1"
            with self.assertRaisesRegex(RuntimeError, "last exit code = 1"):
                router.wait_healthy(previous_pid=12)


if __name__ == "__main__":
    unittest.main()
