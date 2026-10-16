import importlib.machinery
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
router = importlib.machinery.SourceFileLoader("claude_router", str(ROOT / "bin/claude-router")).load_module()


class ClaudeRouterTests(unittest.TestCase):
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
            merged = json.loads(args[args.index("--settings") + 1])
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
        merged = json.loads(next(arg.split("=", 1)[1] for arg in args if arg.startswith("--settings=")))
        self.assertEqual(merged["env"]["CUSTOM"], "kept")
        self.assertEqual(merged["hooks"], {"Stop": []})

    def test_default_model_and_first_settings_precedence(self):
        defaults = router.prepare_gpt(["--gpt", "--continue"])
        self.assertEqual(defaults[:2], ["--model", router.GPT_MODEL])
        self.assertEqual(json.loads(defaults[3])["env"], router.GPT_ENV)
        self.assertEqual(defaults[-1], "--continue")
        args = router.prepare_gpt(["--gpt", "--settings", '{"env":{"FIRST":"yes"}}',
                                   "--settings", '{"env":{"SECOND":"yes"}}'])
        self.assertEqual(args[:2], ["--model", router.GPT_MODEL])
        first = json.loads(args[args.index("--settings") + 1])
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
                patch.object(router.time, "sleep"), patch.object(router, "launchctl") as control:
            control.return_value.stdout = "last exit code = 1"
            with self.assertRaisesRegex(RuntimeError, "last exit code = 1"):
                router.wait_healthy(previous_pid=12)


if __name__ == "__main__":
    unittest.main()
