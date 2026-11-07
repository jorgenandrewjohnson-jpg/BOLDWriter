#!/usr/bin/env python3
"""Small regression checks for worktree path-prefix matching."""
import importlib.util
import pathlib
import unittest

SPEC = importlib.util.spec_from_file_location("run_guarded", pathlib.Path(__file__).with_name("run-guarded.py"))
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class WorktreeMatchingTests(unittest.TestCase):
    def test_neighboring_worktree_prefix_is_not_a_match(self):
        self.assertFalse(MODULE.command_mentions_root(
            "/Users/example/Developer/BOLDWriter-QA/Sources/file.swift",
            pathlib.Path("/Users/example/Developer/BOLDWriter"),
        ))

    def test_root_and_descendant_paths_match(self):
        root = pathlib.Path("/Users/example/Developer/BOLDWriter-Performance")
        self.assertTrue(MODULE.command_mentions_root(str(root), root))
        self.assertTrue(MODULE.command_mentions_root(str(root / "Sources" / "Main.swift"), root))

    def test_similarly_prefixed_other_worktree_does_not_match(self):
        root = pathlib.Path("/Users/example/Developer/BOLDWriter-Performance")
        self.assertFalse(MODULE.command_mentions_root(
            "/Users/example/Developer/BOLDWriter-Performance-archive/Sources/Main.swift", root
        ))


if __name__ == "__main__":
    unittest.main(verbosity=2)
