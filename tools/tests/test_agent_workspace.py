import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "agent_workspace.py"
spec = importlib.util.spec_from_file_location("agent_workspace", SCRIPT)
workspace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workspace)


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="damumu-agent-test-")
        self.root = Path(self.temp.name).resolve()
        self.git("init")
        self.git("config", "user.name", "Isolated Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "core.autocrlf", "false")
        for source in workspace.CORE_CONTEXT:
            workspace.write(self.root / source, "fixture context\n")
        workspace.write(self.root / "tools/agents/roles.json", json.dumps({"roles": {
            "api": {"mode": "write", "owns": ["restapi/"], "reads": [], "checks": ["test"]},
            "review": {"mode": "read-only", "owns": [], "reads": [], "checks": ["review"]}
        }}))
        workspace.write(self.root / ".gitignore", ".agent-work/\n")
        workspace.write(self.root / "restapi/sample.txt", "initial\n")
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        self.base = self.git("rev-parse", "HEAD")

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args, root=None):
        return workspace.git(root or self.root, *args)

    def create(self, task="example"):
        args = argparse.Namespace(task=task, goal="Fixture outcome", roles="api,review", base="HEAD", depends=["review:api"])
        directory = workspace.create_task(self.root, args)
        brief = directory / "brief.md"
        brief.write_text(brief.read_text(encoding="utf-8").replace("TODO", "Agreed"), encoding="utf-8")
        directory, state = workspace.load_task(self.root, task)
        return directory, state

    def prepare(self):
        directory, state = self.create()
        path = workspace.prepare_worktree(self.root, directory, state, "api")
        return directory, state, path

    def test_packets_dependencies_and_non_overwriting_handoff(self):
        directory, state = self.create()
        handoff = directory / "api/handoff.md"
        handoff.write_text("Verified result", encoding="utf-8")
        packet = workspace.packet(self.root, directory, state, "api")
        self.assertIn(self.base, packet.read_text(encoding="utf-8"))
        self.assertEqual(state["depends"]["review"], ["api"])
        self.assertEqual(handoff.read_text(encoding="utf-8"), "Verified result")
        self.assertLess(packet.stat().st_size, 24000)

    def test_path_traversal_and_cycle_rejected(self):
        for value in ("../escape", "x/y", "bad name", "--all"):
            with self.assertRaises(ValueError):
                workspace.slug(value)
        with self.assertRaises(ValueError):
            workspace.dependencies(["api:review", "review:api"], ["api", "review"])
        with self.assertRaises(ValueError):
            workspace.contained(self.root, "../outside")

    def test_incomplete_contract_blocks_worktree(self):
        args = argparse.Namespace(task="incomplete", goal="Example", roles="api", base="HEAD", depends=[])
        workspace.create_task(self.root, args)
        directory, state = workspace.load_task(self.root, args.task)
        with self.assertRaisesRegex(ValueError, "Complete brief"):
            workspace.prepare_worktree(self.root, directory, state, "api")

    def test_isolation_and_committed_scope_drift(self):
        directory, state, path = self.prepare()
        workspace.write(path / "restapi/sample.txt", "worker\n")
        self.assertEqual((self.root / "restapi/sample.txt").read_text(), "initial\n")
        self.assertEqual(workspace.audit(self.root, directory, state, "api")["scope_check"], "passed")
        workspace.write(path / "unexpected.txt", "out of scope\n")
        with self.assertRaisesRegex(ValueError, "Scope violations"):
            workspace.audit(self.root, directory, state, "api")
        self.git("add", ".", root=path)
        self.git("commit", "-m", "drift", root=path)
        with self.assertRaisesRegex(ValueError, "unexpected.txt"):
            workspace.audit(self.root, directory, state, "api")

    def test_stale_context_and_refresh_rejection(self):
        directory, state, path = self.prepare()
        workspace.write(self.root / "docs/STATUS.md", "Updated canonical state\n")
        with self.assertRaisesRegex(ValueError, "stale context: True"):
            workspace.audit(self.root, directory, state, "api")
        with self.assertRaisesRegex(ValueError, "canonical context differs"):
            workspace.packet(self.root, directory, state, "api")

    def test_old_base_rejected_before_worktree_creation(self):
        directory, state = self.create()
        workspace.write(self.root / "docs/STATUS.md", "New context\n")
        with self.assertRaisesRegex(ValueError, "Base context differs"):
            workspace.prepare_worktree(self.root, directory, state, "api")
        self.assertNotIn("api", state["worktrees"])

    def test_read_only_reviewer_and_branch_identity(self):
        directory, state = self.create()
        path = workspace.prepare_worktree(self.root, directory, state, "review")
        workspace.write(path / "restapi/sample.txt", "review must not write\n")
        with self.assertRaisesRegex(ValueError, "Scope violations"):
            workspace.audit(self.root, directory, state, "review")
        self.git("switch", "--detach", root=path)
        with self.assertRaisesRegex(ValueError, "unassigned branch"):
            workspace.audit(self.root, directory, state, "review")

    def test_task_lock_prevents_parallel_manifest_writes(self):
        with workspace.task_lock(self.root, "example"):
            with self.assertRaisesRegex(ValueError, "locked"):
                with workspace.task_lock(self.root, "example"):
                    self.fail("Second writer acquired the task lock")
        with workspace.task_lock(self.root, "example"):
            pass

    def test_external_managed_symlink_rejected(self):
        with tempfile.TemporaryDirectory(prefix="damumu-agent-outside-") as outside:
            try:
                (self.root / ".agent-work").symlink_to(outside, target_is_directory=True)
            except OSError:
                if os.name != "nt":
                    self.skipTest("Creating symlinks requires unavailable OS privileges")
                result = subprocess.run(["cmd", "/c", "mklink", "/J", str(self.root / ".agent-work"), outside],
                                        capture_output=True)
                if result.returncode:
                    self.skipTest("Creating directory junctions requires unavailable OS privileges")
            try:
                with self.assertRaisesRegex(ValueError, "escapes"):
                    workspace.task_paths(self.root, "escape")
            finally:
                if (self.root / ".agent-work").is_symlink():
                    (self.root / ".agent-work").unlink()
                else:
                    os.rmdir(self.root / ".agent-work")


if __name__ == "__main__":
    unittest.main()
