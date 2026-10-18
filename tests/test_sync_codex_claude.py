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

    def test_a_table_prepended_above_the_block_is_refused_not_repaired(self):
        """
        A `[table]` header above the managed block makes
        `developer_instructions` a member of that table, so Codex reads no
        instructions -- and `--check` compared text while never checking
        placement, so it printed "match". Repairing it automatically swept the
        root keys below the header into that table, twice, so this refuses and
        names the line instead.
        """
        self.target.write_text(
            'model = "example-model"\nsandbox_mode = "danger"\n\n[mcp_servers.foo]\ncommand = "x"\n'
        )
        self.assertEqual(self.run_sync().returncode, 0)
        synced = self.target.read_text()
        self.assertLess(synced.index("developer_instructions"), synced.index("[mcp_servers.foo]"))
        self.assertEqual(self.run_sync("--check").returncode, 0)

        self.target.write_text('[mcp_servers.bar]\ncommand = "y"\n' + synced)
        captured = self.target.read_bytes()
        failed = self.run_sync()
        self.assertNotEqual(failed.returncode, 0, "a captured key must fail the sync")
        self.assertIn("would adopt root keys", failed.stderr)
        self.assertEqual(self.target.read_bytes(), captured, "a refusal must not write")
        checked = self.run_sync("--check")
        self.assertNotEqual(checked.returncode, 0, "--check must not report a match")

    def test_a_table_inside_the_managed_markers_is_refused(self):
        """
        Preserved runtime settings are re-emitted AFTER the block, so a table
        among them adopts every root key that follows. `assert_top_level` only
        looks above the block, so it could not see a table the sync itself
        moved down -- the same destruction the automatic relocation caused.
        """
        self.assertEqual(self.run_sync().returncode, 0)
        synced = self.target.read_text()
        marker = synced.index("# END managed:")
        poisoned = (
            synced[:marker]
            + '[projects."/w"]\ntrust_level = "trusted"\n\n'
            + synced[marker:]
        )
        self.target.write_text(poisoned)
        before = self.target.read_bytes()
        failed = self.run_sync()
        self.assertNotEqual(failed.returncode, 0, "a table inside the markers must fail")
        self.assertIn("[table] header", failed.stderr)
        self.assertEqual(self.target.read_bytes(), before, "a refusal must not write")
        self.assertNotEqual(self.run_sync("--check").returncode, 0)

    def test_an_indented_unmanaged_assignment_is_not_overwritten(self):
        """
        `^developer_instructions` missed a leading space, so the guard passed
        and a SECOND root assignment was appended -- the emitted file then did
        not parse as TOML at all, and Codex lost every setting. Worse than the
        adoption bug the guard exists to stop.
        """
        self.target.write_text('  developer_instructions = "mine"\nmodel = "gpt-5"\n')
        before = self.target.read_bytes()
        failed = self.run_sync()
        self.assertNotEqual(failed.returncode, 0, "an indented assignment must be refused")
        self.assertIn("unmanaged developer_instructions", failed.stderr)
        self.assertEqual(self.target.read_bytes(), before, "a refusal must not write")

    def test_every_emitted_config_parses_as_toml_with_its_keys_at_the_root(self):
        """The guards exist to keep the file parseable; assert that directly."""
        try:
            import tomllib
        except ModuleNotFoundError:
            try:
                import tomli as tomllib
            except ModuleNotFoundError:
                self.skipTest("no TOML parser available")
        layouts = [
            'model = "example-model"\n',
            'model = "m"\n\n[mcp_servers.foo]\ncommand = "x"\n',
            '# a comment\nmodel = "m"\napproval_policy = "never"\n',
            '',
        ]
        for layout in layouts:
            self.target.write_text(layout)
            self.assertEqual(self.run_sync().returncode, 0, layout)
            parsed = tomllib.loads(self.target.read_text())
            self.assertIn("developer_instructions", parsed, layout)
            self.assertIsInstance(parsed["developer_instructions"], str)
            if "model" in layout:
                self.assertEqual(parsed.get("model"), "m" if 'model = "m"' in layout else "example-model")
            self.assertEqual(self.run_sync("--check").returncode, 0, layout)

    def test_root_keys_below_the_block_survive_an_ordinary_sync(self):
        """Two repair attempts swallowed these into a prepended mcp server."""
        self.target.write_text(
            'model = "example-model"\napproval_policy = "never"\n\n[mcp_servers.foo]\ncommand = "x"\n'
        )
        self.assertEqual(self.run_sync().returncode, 0)
        config = self.target.read_text()
        head = config[: config.index("[mcp_servers.foo]")]
        for key in ("model", "approval_policy", "developer_instructions"):
            self.assertRegex(head, rf"(?m)^{key}\s*=", f"{key} left the document root")

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
