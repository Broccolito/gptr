import importlib.util
import json
import shutil
import sys
import tempfile
import tomllib
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("build_brxt", ROOT / "scripts" / "build_brxt.py")
build_brxt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_brxt)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def copy(self) -> Path:
        work = Path(self.tmp.name) / "repo"
        shutil.copytree(ROOT, work, ignore=shutil.ignore_patterns(".git", ".venv", "dist", "__pycache__"))
        return work

    def test_the_bundle_is_reproducible_and_holds_only_the_allowlist(self):
        manifest, files = build_brxt.check(ROOT)
        out = Path(self.tmp.name) / "dist"
        first, _, digest = build_brxt.build(ROOT, out, files, manifest)
        data = first.read_bytes()
        again, versioned, digest2 = build_brxt.build(ROOT, out, files, manifest)
        self.assertEqual(again.read_bytes(), data)
        self.assertEqual(versioned.read_bytes(), data)
        self.assertEqual(digest, digest2)
        with zipfile.ZipFile(first) as archive:
            names = set(archive.namelist())
            for info in archive.infolist():
                # the same bytes on every system that builds it, Windows included
                self.assertEqual((info.create_system, info.external_attr >> 16, info.date_time),
                                 (3, 0o100644, build_brxt.ZIP_TIME), info.filename)
        expected = {"manifest.json", "README.md", "LICENSE", "NOTICE", "pyproject.toml", "uv.lock", "r/attach.R",
                    "skills/gptr-live-r/SKILL.md", "src/gptragent/__init__.py", "src/gptragent/__main__.py",
                    "src/gptragent/server.py", "src/gptragent/discovery.py", "src/gptragent/client.py"}
        self.assertEqual(names, expected)
        self.assertIn(f"{digest}  gptragent.brxt", (out / "SHA256SUMS").read_text())

    def test_biorouters_four_structural_checks_pass(self):
        manifest, files = build_brxt.check(ROOT)
        bundle, _, _ = build_brxt.build(ROOT, Path(self.tmp.name) / "dist", files, manifest)
        with zipfile.ZipFile(bundle) as archive:
            names = archive.namelist()
            shipped = json.loads(archive.read("manifest.json"))
        self.assertIn("manifest.json", names)
        self.assertTrue(any(n.lower() == "readme.md" for n in names))
        self.assertIn("pyproject.toml", names)
        self.assertTrue(any(n.startswith("src/") for n in names))
        for key in ("name", "display_name", "description", "version", "entry_point", "repository"):
            self.assertTrue(shipped[key])
        self.assertEqual(shipped["name"], "gptragent")
        self.assertEqual(shipped["tools_count"], 3)
        self.assertEqual(shipped["env_vars"], [])

    def test_versions_agree(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        project = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]
        self.assertEqual(project["version"], manifest["version"])
        self.assertEqual(project["dependencies"], [])
        skill = (ROOT / "skills/gptr-live-r/SKILL.md").read_text()
        self.assertIn(f"  version: {manifest['version']}", skill)

    def test_a_wrong_tool_count_is_refused(self):
        work = self.copy()
        manifest = json.loads((work / "manifest.json").read_text())
        manifest["tools_count"] = 4
        (work / "manifest.json").write_text(json.dumps(manifest))
        with self.assertRaises(build_brxt.Refused) as caught:
            build_brxt.check(work)
        self.assertIn("tools_count", caught.exception.message)

    def test_a_dependency_is_refused(self):
        work = self.copy()
        text = (work / "pyproject.toml").read_text().replace("dependencies = []", 'dependencies = ["httpx"]')
        (work / "pyproject.toml").write_text(text)
        with self.assertRaises(build_brxt.Refused):
            build_brxt.check(work)

    def test_disagreeing_versions_are_refused(self):
        work = self.copy()
        init = work / "src/gptragent/__init__.py"
        init.write_text(init.read_text().replace('"0.', '"9.'))
        with self.assertRaises(build_brxt.Refused) as caught:
            build_brxt.check(work)
        self.assertIn("disagree", caught.exception.message)

    def test_a_previous_release_must_keep_its_skills_and_move_forward(self):
        manifest, files = build_brxt.check(ROOT)
        previous, _, _ = build_brxt.build(ROOT, Path(self.tmp.name) / "prev", files, manifest)
        with self.assertRaises(build_brxt.Refused) as caught:
            build_brxt.check(ROOT, previous)
        self.assertIn("does not move forward", caught.exception.message)

    def test_a_multi_line_skill_description_is_refused(self):
        work = self.copy()
        skill = work / "skills/gptr-live-r/SKILL.md"
        text = skill.read_text()
        start = text.index("description:")
        end = text.index("\n", start)
        skill.write_text(text[:start] + "description:\n  folded over lines" + text[end:])
        with self.assertRaises(build_brxt.Refused):
            build_brxt.check(work)


if __name__ == "__main__":
    unittest.main()
