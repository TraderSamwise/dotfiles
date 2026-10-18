import os
import json
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

    def queue_log(self):
        return self.home / "cs" / "docs" / "agent-queue" / self.repo.name / "log.jsonl"

    def queue_md(self):
        return self.home / "cs" / "docs" / "agent-queue" / self.repo.name / "QUEUE.md"

    def write_events(self, events):
        log = self.queue_log()
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text("\n".join(json.dumps(e) for e in events) + "\n", encoding="utf8")

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

    def test_done_requires_nothing(self):
        """
        2026-10-17: "done requires nothing holy fuck. done should be the first
        thing you do the second you are done." Requiring evidence is what
        taught agents to sit on `doing` assembling it.
        """
        item_id = self.add_item()
        self.start_item(item_id, assignee="codex-worker")

        result = self.run_queue("codex-worker", "done", item_id)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("done", result.stdout)

    def test_todo_can_close_without_passing_through_doing(self):
        item_id = self.add_item()

        result = self.run_queue("claude-overseer", "done", item_id)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("todo", result.stdout)
        self.assertIn("done", result.stdout)

    def test_delete_removes_an_item_from_every_view(self):
        item_id = self.add_item()

        deleted = self.run_queue("claude-overseer", "delete", item_id, "--why", "cannot reproduce")
        self.assertEqual(deleted.returncode, 0, deleted.stderr)

        for view in (["ls"], ["ls", "--everything"], ["backlog"]):
            listing = self.run_queue("claude-overseer", *view)
            self.assertNotIn(item_id, listing.stdout, f"{view} still shows it")
        # The log keeps every event: a delete is a tombstone, not a rewrite.
        self.assertIn('"kind": "delete"', self.queue_log().read_text())

    def _old_todo(self, item_id, days):
        from datetime import datetime, timedelta, timezone

        when = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat(timespec="seconds")
        return {
            "id": item_id,
            "workId": item_id,
            "kind": "add",
            "at": when,
            "ask": f"queued {days} days ago",
            "by": "sam",
            "tree": self.repo.name,
        }

    def test_a_dropped_ruling_stays_dropped_and_never_returns_as_todo(self):
        """
        `dropped` was Sam answering that work would not be done. His rule now is
        that such work is deleted, so reading the old state as `todo` brought 18
        already-killed items back onto the list. A ruling is a tombstone.
        """
        added = self._old_todo("sam-1", 1)
        self.write_events(
            [
                added,
                {
                    "id": "sam-1",
                    "workId": "sam-1",
                    "kind": "state",
                    "state": "dropped",
                    "at": added["at"],
                    "why": "sam said drop it",
                    "by": "sam",
                    "tree": self.repo.name,
                },
            ]
        )
        for view in (["ls"], ["ls", "--everything"], ["backlog"], ["next"]):
            self.assertNotIn("sam-1", self.run_queue("sam", *view).stdout, view)

    def test_a_wontdo_proposal_returns_to_the_list_for_a_real_decision(self):
        """
        `wontdo` was an agent PROPOSING to abandon something, never Sam's
        answer, so unlike `dropped` it must come back as todo.
        """
        added = self._old_todo("sam-2", 1)
        self.write_events(
            [
                added,
                {
                    "id": "sam-2",
                    "workId": "sam-2",
                    "kind": "state",
                    "state": "wontdo",
                    "at": added["at"],
                    "why": "cannot reproduce",
                    "by": "claude",
                    "tree": self.repo.name,
                },
            ]
        )
        self.assertIn("sam-2", self.run_queue("sam", "ls").stdout)

    def test_a_todo_older_than_seven_days_leaves_the_working_list(self):
        self.write_events([self._old_todo("sam-1", 9), self._old_todo("sam-2", 2)])

        working = self.run_queue("sam", "ls")
        self.assertIn("sam-2", working.stdout)
        self.assertNotIn("sam-1", working.stdout, "a 9-day-old todo is backlog")

        shelved = self.run_queue("sam", "backlog")
        self.assertIn("sam-1", shelved.stdout)
        self.assertNotIn("sam-2", shelved.stdout, "backlog is only the shelved ones")

    def test_next_never_hands_back_a_backlog_item(self):
        self.write_events([self._old_todo("sam-1", 30)])

        result = self.run_queue("sam", "next")

        self.assertNotIn("sam-1  todo → doing", result.stdout)
        self.assertIn("backlog", result.stdout)

    def test_next_takes_the_newest_item_not_the_oldest(self):
        """
        2026-10-17: "assume the most recently added things are the things i
        care about the most."
        """
        self.write_events([self._old_todo("sam-1", 3), self._old_todo("sam-2", 1)])

        result = self.run_queue("sam", "next")

        self.assertIn("sam-2", result.stdout)
        self.assertNotIn("sam-1", result.stdout)

    def test_done_still_refuses_unmet_clauses_for_assigned_agent(self):
        item_id = self.add_item()
        self.start_item(item_id, assignee="codex-worker")

        result = self.done_item("codex-worker", item_id, clauses="1 requirement: NOT DONE")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--clauses says a requirement is not met", result.stderr)

    def test_closed_slot_is_not_reused_and_bare_number_stays_ergonomic(self):
        first_id = self.add_item(creator="sam", ask="first ask")
        other_id = self.add_item(creator="codex-other", ask="other agent ask")
        self.assertEqual(other_id, "other-1")
        self.start_item(first_id, creator="sam", assignee="sam")
        done = self.done_item("sam", "1")
        self.assertEqual(done.returncode, 0, done.stderr)

        second = self.run_queue("sam", "add", "second ask")

        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("sam-2  todo", second.stdout)
        start = self.run_queue("sam", "start", "2", "--by", "sam")
        self.assertEqual(start.returncode, 0, start.stderr)
        self.assertIn("sam-2  todo", start.stdout)
        done_second = self.done_item("sam", "2")
        self.assertEqual(done_second.returncode, 0, done_second.stderr)
        self.assertIn("sam-2  doing", done_second.stdout)

        events = [
            json.loads(line)
            for line in self.queue_log().read_text(encoding="utf8").splitlines()
            if line.strip()
        ]
        self.assertEqual(
            [e["id"] for e in events if e["kind"] == "add"],
            ["sam-1", "other-1", "sam-2"],
        )
        self.assertTrue(all(e.get("workId") == e["id"] for e in events))

    def test_allocator_spends_past_old_ceiling_instead_of_recycling(self):
        events = []
        for n in range(1, 100):
            eid = f"sam-{n}"
            events.extend(
                [
                    {
                        "id": eid,
                        "workId": eid,
                        "kind": "add",
                        "at": f"2026-09-15T01:{n % 60:02d}:00+00:00",
                        "ask": f"closed ask {n}",
                        "by": "sam",
                        "tree": self.repo.name,
                    },
                    {
                        "id": eid,
                        "workId": eid,
                        "kind": "move",
                        "at": f"2026-09-15T01:{n % 60:02d}:10+00:00",
                        "state": "done",
                        "by": "sam",
                        "commit": f"sha{n}",
                        "proof": f"proof {n}",
                        "clauses": f"1 ask {n}: DONE",
                    },
                ]
            )
        self.write_events(events)

        result = self.run_queue("sam", "add", "one hundredth ask")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("sam-100  todo", result.stdout)

    def test_closure_event_work_id_identifies_ask_in_recycled_looking_log(self):
        self.write_events(
            [
                {
                    "id": "sam-1",
                    "workId": "sam-1",
                    "kind": "add",
                    "at": "2026-09-15T01:00:00+00:00",
                    "ask": "first ask that once held the alias",
                    "by": "sam",
                    "tree": self.repo.name,
                },
                {
                    "id": "sam-1",
                    "workId": "sam-1",
                    "kind": "move",
                    "at": "2026-09-15T01:01:00+00:00",
                    "state": "doing",
                    "by": "sam",
                },
                {
                    "id": "sam-1",
                    "workId": "sam-1",
                    "kind": "move",
                    "at": "2026-09-15T01:02:00+00:00",
                    "state": "done",
                    "by": "sam",
                    "commit": "aaa111",
                    "proof": "first proof",
                    "clauses": "1 first: DONE",
                },
                {
                    "id": "sam-1",
                    "workId": "sam-2",
                    "kind": "add",
                    "at": "2026-09-15T02:00:00+00:00",
                    "ask": "second ask using a recycled-looking alias",
                    "by": "sam",
                    "tree": self.repo.name,
                },
                {
                    "id": "sam-1",
                    "workId": "sam-2",
                    "kind": "move",
                    "at": "2026-09-15T02:01:00+00:00",
                    "state": "doing",
                    "by": "sam",
                },
                {
                    "id": "sam-1",
                    "workId": "sam-2",
                    "kind": "move",
                    "at": "2026-09-15T02:02:00+00:00",
                    "state": "done",
                    "by": "sam",
                    "commit": "bbb222",
                    "proof": "second proof",
                    "clauses": "1 second: DONE",
                },
            ]
        )

        sync = self.run_queue("sam", "sync")
        self.assertEqual(sync.returncode, 0, sync.stderr)
        ambiguous = self.run_queue("sam", "show", "sam-1")
        self.assertNotEqual(ambiguous.returncode, 0)
        self.assertIn("multiple work ids: sam-1, sam-2", ambiguous.stderr)

        result = self.run_queue("sam", "show", "sam-2")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("workId=sam-2", result.stdout)
        self.assertIn("second ask using a recycled-looking alias", result.stdout)
        self.assertIn("second proof", result.stdout)
        self.assertLess(
            result.stdout.find("second ask using a recycled-looking alias"),
            result.stdout.find("earlier items that held this id"),
        )
        self.assertIn("first ask that once held the alias", result.stdout)
        self.assertIn("`workId`: sam-2", self.queue_md().read_text(encoding="utf8"))

    def test_existing_historical_recycled_entries_still_parse_and_render(self):
        self.write_events(
            [
                {
                    "id": "sam-1",
                    "kind": "add",
                    "at": "2026-09-15T01:00:00+00:00",
                    "ask": "old first ask",
                    "by": "sam",
                    "tree": self.repo.name,
                },
                {
                    "id": "sam-1",
                    "kind": "move",
                    "at": "2026-09-15T01:01:00+00:00",
                    "state": "landed",
                    "by": "sam",
                    "commit": "old111",
                    "proof": "old proof",
                },
                {
                    "id": "sam-1",
                    "kind": "add",
                    "at": "2026-09-15T02:00:00+00:00",
                    "ask": "old second ask",
                    "by": "sam",
                    "tree": self.repo.name,
                },
            ]
        )

        sync = self.run_queue("sam", "sync")
        show = self.run_queue("sam", "show", "sam-1")

        self.assertEqual(sync.returncode, 0, sync.stderr)
        self.assertEqual(show.returncode, 0, show.stderr)
        self.assertIn("old second ask", show.stdout)
        self.assertIn("earlier items that held this id", show.stdout)
        self.assertIn("old first ask", show.stdout)
        rendered = self.queue_md().read_text(encoding="utf8")
        self.assertIn("old second ask", rendered)
        self.assertNotIn("old first ask", rendered)


if __name__ == "__main__":
    unittest.main()
