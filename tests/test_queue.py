import os
import subprocess
import tempfile
import unittest
from pathlib import Path


QUEUE = Path(__file__).resolve().parents[1] / "bin" / "queue"


class QueueCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.repo = Path(self.tmp.name) / "repo"
        self.home.mkdir()
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True)

    def tearDown(self):
        self.tmp.cleanup()

    def run_queue(self, agent, *args):
        env = os.environ.copy()
        env["HOME"] = str(self.home)
        env["AIMUX_SESSION_ID"] = agent
        env.pop("CLAUDE_CODE_SESSION_ID", None)
        env.pop("CODEX_SESSION_ID", None)
        env.pop("CODEX_THREAD_ID", None)
        return subprocess.run(
            [str(QUEUE), *args],
            cwd=self.repo,
            env=env,
            text=True,
            capture_output=True,
        )

    def add_item(self, creator="claude-overseer", ask="do the thing"):
        result = self.run_queue(creator, "add", ask)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.split()[0]

    def start_item(self, item_id, creator="claude-overseer", assignee="codex-worker"):
        result = self.run_queue(creator, "start", item_id, "--by", assignee)
        self.assertEqual(result.returncode, 0, result.stderr)

    def done_item(self, agent, item_id, clauses="1 requirement: DONE"):
        return self.run_queue(
            agent,
            "done",
            item_id,
            "--commit",
            "abc1234",
            "--proof",
            "proved with scratch queue subprocess test",
            "--clauses",
            clauses,
        )

    def test_assigned_agent_can_close_without_hand(self):
        item_id = self.add_item()
        self.start_item(item_id, assignee="codex-worker")

        result = self.done_item("codex-worker", item_id)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"{item_id}  doing", result.stdout)
        self.assertIn("done", result.stdout)

    def test_creator_can_close_item_it_dispatched(self):
        item_id = self.add_item()
        hand = self.run_queue("claude-overseer", "hand", item_id, "--to", "codex-worker")
        self.assertEqual(hand.returncode, 0, hand.stderr)
        self.start_item(item_id, creator="codex-worker", assignee="codex-worker")

        result = self.done_item("claude-overseer", item_id)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"{item_id}  doing", result.stdout)
        self.assertIn("done", result.stdout)

    def test_unrelated_agent_cannot_close_someone_elses_item(self):
        item_id = self.add_item()
        self.start_item(item_id, assignee="codex-worker")

        result = self.done_item("codex-other", item_id)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("belongs to claude-overseer, assigned to codex-worker", result.stderr)
        self.assertIn("you are codex-other", result.stderr)

    def test_done_still_requires_proof_for_assigned_agent(self):
        item_id = self.add_item()
        self.start_item(item_id, assignee="codex-worker")

        result = self.run_queue(
            "codex-worker",
            "done",
            item_id,
            "--commit",
            "abc1234",
            "--clauses",
            "1 requirement: DONE",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("done requires --proof", result.stderr)

    def test_done_still_refuses_unmet_clauses_for_assigned_agent(self):
        item_id = self.add_item()
        self.start_item(item_id, assignee="codex-worker")

        result = self.done_item("codex-worker", item_id, clauses="1 requirement: NOT DONE")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--clauses says a requirement is not met", result.stderr)


if __name__ == "__main__":
    unittest.main()
