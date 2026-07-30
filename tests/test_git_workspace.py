"""Black-box regression tests for the git-workspace CLI.

These drive the real CLI (via `python git-workspace <cmd>`) against
throwaway local git repositories, so they need git on PATH and PyYAML
installed (the CLI imports it). They are the regression net for the issues
found in code review: path/symlink escape, `--locked` reproduction, read-only
drift, cache-key collision, and `verify` false-success.

Run:  python -m unittest discover -s tests -v
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "git-workspace"

GIT_IDENTITY = {
    "GIT_AUTHOR_NAME": "ci",
    "GIT_AUTHOR_EMAIL": "ci@test.local",
    "GIT_COMMITTER_NAME": "ci",
    "GIT_COMMITTER_EMAIL": "ci@test.local",
}


def _have_git():
    return shutil.which("git") is not None


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class WorkspaceTest(unittest.TestCase):
    """Base: a temp scratch dir and helpers to build repos + run the CLI."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="gw-test-"))
        self.env = {**os.environ, **GIT_IDENTITY}
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    # ---- helpers ---------------------------------------------------------

    def git(self, args, cwd):
        proc = subprocess.run(
            ["git", *args], cwd=str(cwd), env=self.env,
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            raise AssertionError(f"git {args} failed in {cwd}:\n{proc.stderr}")
        return proc.stdout.strip()

    def make_repo(self, name, files, branch="main"):
        """Create a source repo with {relpath: content}; return (path, head_sha)."""
        repo = self.tmp / "repos" / name
        repo.mkdir(parents=True, exist_ok=True)
        self.git(["init", "-q"], repo)
        for rel, content in files.items():
            write(repo / rel, content)
        self.git(["add", "-A"], repo)
        self.git(["commit", "-qm", f"init {name}"], repo)
        self.git(["branch", "-M", branch], repo)
        return repo, self.git(["rev-parse", "HEAD"], repo)

    def commit(self, repo, files, msg="change"):
        for rel, content in files.items():
            write(repo / rel, content)
        self.git(["add", "-A"], repo)
        self.git(["commit", "-qm", msg], repo)
        return self.git(["rev-parse", "HEAD"], repo)

    def make_ws(self, yaml_text):
        ws = self.tmp / "ws"
        write(ws / "git-workspace.yaml", yaml_text)
        return ws

    def run_cli(self, ws, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args], cwd=str(ws), env=self.env,
            capture_output=True, text=True,
        )

    def cfg(self, *sources):
        """Build a minimal config from (name, url, path, extra_yaml) tuples."""
        lines = ["version: 1", "sources:"]
        for name, url, path, extra in sources:
            url_str = str(url).replace("\\", "/")
            lines.append(f"  {name}:")
            lines.append(f"    url: {url_str}")
            lines.append("    revision: main")
            lines.append(f"    path: {path}")
            for ln in extra or []:
                lines.append(f"    {ln}")
        return "\n".join(lines) + "\n"


@unittest.skipUnless(_have_git(), "git is required")
class LockedSyncTests(WorkspaceTest):
    def test_locked_reproduces_sha_under_upstream_drift(self):
        repo, sha_a = self.make_repo("src", {"f.txt": "one"})
        ws = self.make_ws(self.cfg(("s", repo, "sub", None)))
        self.assertEqual(self.run_cli(ws, "sync").returncode, 0)
        lock_before = (ws / "git-workspace.lock.yaml").read_text()
        self.assertIn(sha_a, lock_before)

        sha_b = self.commit(repo, {"f.txt": "two"})
        self.assertNotEqual(sha_a, sha_b)

        p = self.run_cli(ws, "sync", "--locked")
        self.assertEqual(p.returncode, 0, p.stderr)
        # pinned at A, not B
        head = self.git(["rev-parse", "HEAD"], ws / "sub")
        self.assertEqual(head, sha_a)
        self.assertEqual((ws / "sub" / "f.txt").read_text(), "one")
        # lock not rewritten
        self.assertEqual((ws / "git-workspace.lock.yaml").read_text(), lock_before)

    def test_locked_rejects_revision_mismatch(self):
        repo, _ = self.make_repo("src", {"f.txt": "x"})
        ws = self.make_ws(self.cfg(("s", repo, "sub", None)))
        self.assertEqual(self.run_cli(ws, "sync").returncode, 0)
        write(ws / "git-workspace.yaml", self.cfg(("s", repo, "sub", None)).replace("revision: main", "revision: other"))
        p = self.run_cli(ws, "sync", "--locked")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("disagree", p.stderr)

    def test_locked_rejects_url_mismatch(self):
        repo, _ = self.make_repo("src", {"f.txt": "x"})
        other, _ = self.make_repo("other", {"f.txt": "y"})
        ws = self.make_ws(self.cfg(("s", repo, "sub", None)))
        self.assertEqual(self.run_cli(ws, "sync").returncode, 0)
        write(ws / "git-workspace.yaml", self.cfg(("s", other, "sub", None)))
        p = self.run_cli(ws, "sync", "--locked")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("disagree", p.stderr)

    def test_locked_rejects_source_added_since_lock(self):
        repo, _ = self.make_repo("src", {"f.txt": "x"})
        repo2, _ = self.make_repo("src2", {"f.txt": "y"})
        ws = self.make_ws(self.cfg(("s", repo, "sub", None)))
        self.assertEqual(self.run_cli(ws, "sync").returncode, 0)
        write(ws / "git-workspace.yaml", self.cfg(("s", repo, "sub", None), ("s2", repo2, "sub2", None)))
        p = self.run_cli(ws, "sync", "--locked")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("not present in lock", p.stderr)


@unittest.skipUnless(_have_git(), "git is required")
class PathContainmentTests(WorkspaceTest):
    def test_absolute_path_rejected(self):
        repo, _ = self.make_repo("src", {"f.txt": "x"})
        outside = self.tmp / "escape-abs"
        cfg = self.cfg(("s", repo, str(outside).replace("\\", "/"), None))
        ws = self.make_ws(cfg)
        p = self.run_cli(ws, "sync")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("absolute", p.stderr)
        self.assertFalse(outside.exists())

    def test_symlink_ancestor_escape_rejected(self):
        repo, _ = self.make_repo("src", {"f.txt": "x"})
        outside = self.tmp / "outside"
        outside.mkdir()
        ws = self.make_ws("placeholder")
        link = ws / "linkdir"
        ws.mkdir(parents=True, exist_ok=True)
        try:
            os.symlink(str(outside), str(link))
        except (OSError, NotImplementedError):
            self.skipTest("symlinks not permitted on this platform")
        write(ws / "git-workspace.yaml", self.cfg(("s", repo, "linkdir/foo", None)))
        p = self.run_cli(ws, "sync")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("escapes", p.stderr)
        self.assertFalse((outside / "foo").exists())


@unittest.skipUnless(_have_git(), "git is required")
class CacheCollisionTests(WorkspaceTest):
    def test_distinct_urls_with_colliding_slugs_get_separate_caches(self):
        # .../repos/a/b  and  .../repos/a-b  slug to the same string; the old
        # key scheme handed both sources the first repo's cache.
        repo1 = self.tmp / "repos" / "a" / "b"
        repo2 = self.tmp / "repos" / "a-b"
        for repo, marker in ((repo1, "one"), (repo2, "two")):
            repo.mkdir(parents=True, exist_ok=True)
            self.git(["init", "-q"], repo)
            write(repo / "marker.txt", marker)
            self.git(["add", "-A"], repo)
            self.git(["commit", "-qm", "init"], repo)
            self.git(["branch", "-M", "main"], repo)

        ws = self.make_ws(self.cfg(("s1", repo1, "one", None), ("s2", repo2, "two", None)))
        p = self.run_cli(ws, "sync")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual((ws / "one" / "marker.txt").read_text(), "one")
        self.assertEqual((ws / "two" / "marker.txt").read_text(), "two")

    def test_explicit_shared_cache_key_across_urls_rejected(self):
        repo1, _ = self.make_repo("r1", {"f.txt": "x"})
        repo2, _ = self.make_repo("r2", {"f.txt": "y"})
        cfg = self.cfg(
            ("s1", repo1, "one", ["cache: shared"]),
            ("s2", repo2, "two", ["cache: shared"]),
        )
        ws = self.make_ws(cfg)
        p = self.run_cli(ws, "sync")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("exactly one URL", p.stderr)


@unittest.skipUnless(_have_git(), "git is required")
class VerifyTests(WorkspaceTest):
    def _synced(self, extra=None):
        repo, sha = self.make_repo("src", {"f.txt": "x"})
        ws = self.make_ws(self.cfg(("s", repo, "sub", extra)))
        self.assertEqual(self.run_cli(ws, "sync").returncode, 0)
        return repo, ws, sha

    def test_verify_ok_on_clean_locked_workspace(self):
        _, ws, _ = self._synced()
        p = self.run_cli(ws, "verify")
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_verify_fails_when_lock_missing(self):
        _, ws, _ = self._synced()
        (ws / "git-workspace.lock.yaml").unlink()
        p = self.run_cli(ws, "verify")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("lock file missing", p.stderr)

    def test_verify_fails_on_dirty_writable_source(self):
        _, ws, _ = self._synced()
        write(ws / "sub" / "f.txt", "tampered")
        p = self.run_cli(ws, "verify")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("DIRTY", p.stderr)

    def test_verify_fails_when_source_not_in_lock(self):
        repo, ws, _ = self._synced()
        repo2, _ = self.make_repo("src2", {"f.txt": "y"})
        write(ws / "git-workspace.yaml", self.cfg(("s", repo, "sub", None), ("s2", repo2, "sub2", None)))
        p = self.run_cli(ws, "verify")
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("not present in lock", p.stderr)


@unittest.skipUnless(_have_git(), "git is required")
class ReadOnlyTests(WorkspaceTest):
    @unittest.skipIf(sys.platform == "win32", "POSIX permission-bit locking is not enforced on Windows")
    def test_sync_rejects_dirty_readonly_source(self):
        repo, _ = self.make_repo("src", {"f.txt": "x"})
        ws = self.make_ws(self.cfg(("s", repo, "ro", ["readonly: true"])))
        self.assertEqual(self.run_cli(ws, "sync").returncode, 0)
        # restore write permission (as the file owner can) and tamper
        for p in (ws / "ro").rglob("*"):
            os.chmod(p, p.stat().st_mode | 0o200)
        write(ws / "ro" / "f.txt", "tampered")
        r = self.run_cli(ws, "sync")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("read-only source has local modifications", r.stderr)


@unittest.skipUnless(_have_git(), "git is required")
class MiscTests(WorkspaceTest):
    def test_repeat_sync_is_idempotent(self):
        repo, _ = self.make_repo("src", {"f.txt": "x"})
        ws = self.make_ws(self.cfg(("s", repo, "sub", None)))
        self.assertEqual(self.run_cli(ws, "sync").returncode, 0)
        p = self.run_cli(ws, "sync")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("up to date", p.stdout)

    def test_nested_sources_both_materialize(self):
        repo, _ = self.make_repo("src", {"f.txt": "x"})
        ws = self.make_ws(self.cfg(("parent", repo, "p", None), ("child", repo, "p/c", None)))
        p = self.run_cli(ws, "sync")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertTrue((ws / "p" / ".git").exists())
        self.assertTrue((ws / "p" / "c" / ".git").exists())


if __name__ == "__main__":
    unittest.main()
