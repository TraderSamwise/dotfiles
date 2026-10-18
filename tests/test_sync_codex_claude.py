import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "sync-codex-claude"


class SyncInstructionsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        (self.home / ".claude").mkdir()
        (self.home / ".codex").mkdir()
        self.shared = self.home / ".claude" / "CLAUDE.md"
        self.private = self.home / "CLAUDE.md"
        self.target = self.home / ".codex" / "config.toml"
        self.shared.write_text(self.source("Shared policy"))
        self.private.write_text(self.source("Private policy"))
        self.target.write_text('model = "example-model"\n')

    def source(self, body):
        return f"<!-- codex:sync-start -->\n{body}\n<!-- codex:sync-end -->\nClaude only\n"

    def run_sync(self, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            env={**os.environ, "HOME": str(self.home)},
            text=True,
            capture_output=True,
        )

    def test_check_detects_drift_without_writing(self):
        original = self.target.read_bytes()
        result = self.run_sync("--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("out of sync", result.stderr)
        self.assertEqual(self.target.read_bytes(), original)
        self.assertEqual(self.run_sync().returncode, 0)
        synced = self.target.read_bytes()
        self.assertEqual(self.run_sync("--check").returncode, 0)
        self.shared.write_text(self.source("Changed policy"))
        self.assertNotEqual(self.run_sync("--check").returncode, 0)
        self.assertEqual(self.target.read_bytes(), synced)

    def test_a_table_prepended_above_the_block_does_not_capture_the_key(self):
        """
        A `[table]` header above the managed block makes
        `developer_instructions` a member of that table, so Codex reads no
        instructions -- and keeping the old position was sticky, so every later
        sync rewrote it in place and `--check` reported a match.
        """
        self.assertEqual(self.run_sync().returncode, 0)
        self.target.write_text('[mcp_servers.bar]\ncommand = "y"\n' + self.target.read_text())
        self.assertEqual(self.run_sync().returncode, 0, "a mispositioned block must be repaired")
        config = self.target.read_text()
        head = config[: config.index("# BEGIN managed:")]
        self.assertNotRegex(head, r"(?m)^\[", f"a table header still precedes the block:\n{head}")
        self.assertIn('[mcp_servers.bar]', config, "the prepended server must survive")
        self.assertEqual(config.count("developer_instructions ="), 1)
        self.assertEqual(self.run_sync("--check").returncode, 0)

    def test_sync_preserves_config_order_and_runtime_boundaries(self):
        self.assertEqual(self.run_sync().returncode, 0)
        config = self.target.read_text()
        self.assertIn('model = "example-model"', config)
        self.assertLess(config.index("Shared policy"), config.index("Private policy"))
        self.assertNotIn("Claude only", config)
        self.assertEqual(config.count("developer_instructions ="), 1)
        self.assertEqual(self.run_sync().returncode, 0)
        self.assertEqual(self.target.read_text(), config)

    def test_invalid_source_markers_cannot_replace_working_config(self):
        self.assertEqual(self.run_sync().returncode, 0)
        original = self.target.read_bytes()
        for source in [self.source("One") + self.source("Two"), "No markers", self.source("")]:
            with self.subTest(source=source):
                self.shared.write_text(source)
                self.assertNotEqual(self.run_sync().returncode, 0)
                self.assertEqual(self.target.read_bytes(), original)

    def test_unmanaged_instructions_are_not_overwritten(self):
        config = 'developer_instructions = "custom policy"\n'
        self.target.write_text(config)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unmanaged", result.stderr)
        self.assertEqual(self.target.read_text(), config)

    def test_damaged_or_duplicate_managed_blocks_are_not_replaced(self):
        self.assertEqual(self.run_sync().returncode, 0)
        working = self.target.read_text()
        cases = [working + working, working.replace("# END managed:", "# missing:")]
        for config in cases:
            with self.subTest(config=config):
                self.target.write_text(config)
                result = self.run_sync()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.target.read_text(), config)

    def test_another_home_managed_block_is_replaced_once(self):
        self.assertEqual(self.run_sync().returncode, 0)
        self.target.write_text(self.target.read_text().replace(str(self.home), "/other/home"))
        self.assertEqual(self.run_sync().returncode, 0)
        config = self.target.read_text()
        self.assertNotIn("/other/home", config)
        self.assertEqual(config.count("developer_instructions ="), 1)
        self.assertEqual(self.run_sync("--check").returncode, 0)

    def test_runtime_settings_inside_managed_markers_are_preserved(self):
        self.assertEqual(self.run_sync().returncode, 0)
        working = self.target.read_text().replace('model = "example-model"\n', '')
        for home in [str(self.home), "/other/home"]:
            with self.subTest(home=home):
                config = working.replace(str(self.home), home)
                end = f"# END managed: {home}/CLAUDE.md -> Codex developer_instructions"
                settings = 'model = "selected-model"\nmodel_reasoning_effort = "high"\n'
                config = config.replace(end, settings + end)
                config += '[projects."/workspace"]\ntrust_level = "trusted"\n'
                self.target.write_text(config)
                self.assertEqual(self.run_sync().returncode, 0)
                synced = self.target.read_text()
                self.assertIn(settings, synced)
                self.assertLess(synced.index("# END managed:"), synced.index('model = "selected-model"'))
                self.assertLess(synced.index(settings), synced.index('[projects.'))
                self.assertEqual(self.run_sync("--check").returncode, 0)


if __name__ == "__main__":
    unittest.main()
