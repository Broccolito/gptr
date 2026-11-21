"""Check the release rules, then build the extension bundle.

Writes dist/gptragent.brxt, dist/gptragent-X.Y.Z.brxt (the same bytes) and dist/SHA256SUMS.

    uv run python scripts/build_brxt.py                  # check and build
    uv run python scripts/build_brxt.py --check          # check only
    uv run python scripts/build_brxt.py --previous old.brxt

It refuses unless:

* manifest.json, pyproject.toml, src/gptragent/__init__.py and the README's "Current version"
  line carry the same X.Y.Z;
* the project depends on nothing outside Python's standard library, and uv.lock was made for this
  version of it;
* no declared environment value is a secret with a default;
* the bundled skills are exactly the ones the manifest declares, each names itself and keeps its
  description on one line (Biorouter reads the frontmatter line by line), and every skill path
  in --previous is still present (an in place update never deletes a file);
* the server lists exactly manifest.tools_count tools, with the read-only and destructive
  annotations Biorouter's approval reads;
* with --previous, the name and repository are unchanged and the version moved forward.

The bundle is built from an explicit allowlist with fixed timestamps, so the same tree always
gives the same bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import re
import sys
import tomllib
import zipfile
from pathlib import Path
from typing import Any, Optional

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_FILES = ("manifest.json", "README.md", "LICENSE", "NOTICE", "pyproject.toml", "uv.lock", "r/attach.R")
NAME = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*")
VERSION = re.compile(r"\d+\.\d+\.\d+")
README_VERSION = re.compile(r"Current version: \*\*(\d+\.\d+\.\d+)\*\*")
INIT_VERSION = re.compile(r'(?m)^__version__ = "([^"]+)"')
ZIP_TIME = (2020, 1, 1, 0, 0, 0)
EXPECTED_TOOLS = {"sessions": "read-only", "inspect": "read-only", "r": "destructive"}


class Refused(SystemExit):
    def __init__(self, message: str) -> None:
        super().__init__(f"build_brxt: refused: {message}")
        self.message = message


def _version_tuple(text: str) -> tuple:
    return tuple(int(part) for part in text.split("."))


def _frontmatter(text: str) -> Optional[dict]:
    match = re.match(r"---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
    if not match:
        return None
    out = {}
    for line in match.group(1).splitlines():
        if ":" in line and not line.startswith((" ", "\t")):
            key, value = line.split(":", 1)
            out[key.strip()] = value.strip().strip("'\"")
    return out


def _tools(root: Path, package: str) -> list:
    sys.path.insert(0, str(root / "src"))
    try:
        for cached in [m for m in sys.modules if m == package or m.startswith(package + ".")]:
            del sys.modules[cached]
        server = importlib.import_module(f"{package}.server")
        return list(server.TOOLS)
    finally:
        sys.path.remove(str(root / "src"))


def check(root: Path, previous: Optional[Path] = None) -> tuple:
    """Run every rule and return the manifest and the files to bundle."""
    for filename in REQUIRED_FILES:
        if not (root / filename).is_file():
            raise Refused(f"{filename} is missing.")
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    project = tomllib.loads((root / "pyproject.toml").read_text(encoding="utf-8")).get("project", {})
    for key in ("name", "display_name", "description", "version", "entry_point", "repository"):
        if not isinstance(manifest.get(key), str) or not manifest[key].strip():
            raise Refused(f"manifest.json needs {key}.")
    name, version = manifest["name"], manifest["version"]
    if not NAME.fullmatch(name):
        raise Refused(f"manifest name {name!r} is not a valid extension name.")
    if not VERSION.fullmatch(version):
        raise Refused(f"manifest version {version!r} is not X.Y.Z.")
    package = name.replace("-", "_")
    source = root / "src" / package
    if not source.is_dir():
        raise Refused(f"src/{package}/ is missing.")

    init_text = (source / "__init__.py").read_text(encoding="utf-8") if (source / "__init__.py").is_file() else ""
    init_match = INIT_VERSION.search(init_text)
    readme_match = README_VERSION.search((root / "README.md").read_text(encoding="utf-8"))
    versions = {
        "manifest.json": version,
        "pyproject.toml": project.get("version"),
        f"src/{package}/__init__.py": init_match.group(1) if init_match else None,
        "README.md (Current version line)": readme_match.group(1) if readme_match else None,
    }
    if len(set(versions.values())) != 1:
        raise Refused(f"the versions disagree: {versions}. Run scripts/version.py.")
    if project.get("name") != name:
        raise Refused("pyproject project.name must equal the manifest name.")
    if manifest["entry_point"] not in (project.get("scripts") or {}):
        raise Refused("the manifest entry_point is not a pyproject script.")
    if project.get("dependencies"):
        raise Refused("gptr Agent uses Python's standard library only; pyproject lists dependencies.")
    lock = tomllib.loads((root / "uv.lock").read_text(encoding="utf-8"))
    packages = lock.get("package") or []
    own = [p for p in packages if p.get("name") == name]
    if not own or own[0].get("version") != version:
        raise Refused("uv.lock was made for another version of this project. Run uv lock.")
    others = sorted(p.get("name") for p in packages if p.get("name") != name)
    if others:
        raise Refused(f"uv.lock pins packages besides the project: {others}.")

    env_vars = manifest.get("env_vars")
    if not isinstance(env_vars, list):
        raise Refused("manifest env_vars must be a list.")
    for item in env_vars:
        if not isinstance(item, dict) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", str(item.get("key", ""))):
            raise Refused(f"env var {item!r} is not an upper case name.")
        if item.get("secret") and item.get("default"):
            raise Refused(f"secret {item['key']} must not have a default.")

    skills_dir = root / "skills"
    found = sorted(p.parent.name for p in skills_dir.glob("*/SKILL.md")) if skills_dir.is_dir() else []
    declared_skills = sorted(s["name"] for s in manifest.get("skills") or [])
    if found != declared_skills:
        raise Refused(f"bundled skills {found} differ from the manifest's {declared_skills}.")
    for skill in found:
        front = _frontmatter((skills_dir / skill / "SKILL.md").read_text(encoding="utf-8"))
        if not front or front.get("name") != skill:
            raise Refused(f"skills/{skill}/SKILL.md must name itself {skill} in its frontmatter.")
        if not front.get("description"):
            raise Refused(f"skills/{skill}/SKILL.md needs its description on the description: line.")

    if previous is not None:
        with zipfile.ZipFile(previous) as archive:
            previous_names = set(archive.namelist())
            previous_manifest = json.loads(archive.read("manifest.json"))
        if previous_manifest.get("name") != name:
            raise Refused("the manifest name changed since the previous release.")
        if previous_manifest.get("repository") != manifest["repository"]:
            raise Refused("the manifest repository changed since the previous release.")
        previous_version = str(previous_manifest.get("version", "0.0.0"))
        previous_core = re.match(r"\d+\.\d+\.\d+", previous_version)
        if previous_core and _version_tuple(version) <= _version_tuple(previous_core.group(0)):
            raise Refused(f"version {version} does not move forward from {previous_version}.")
        previous_skills = {n for n in previous_names if n.startswith("skills/") and n.endswith("/SKILL.md")}
        missing = sorted(previous_skills - {f"skills/{s}/SKILL.md" for s in found})
        if missing:
            raise Refused(f"the previous release bundled {missing}. Keep every bundled skill path "
                          "(rewrite it as a moved notice if it is no longer needed).")

    tools = _tools(root, package)
    names = [t.get("name") for t in tools]
    if manifest.get("tools_count") != len(tools):
        raise Refused(f"manifest tools_count is {manifest.get('tools_count')}, the server lists {len(tools)}: {names}.")
    if sorted(names) != sorted(EXPECTED_TOOLS):
        raise Refused(f"the server lists {names}, not {sorted(EXPECTED_TOOLS)}.")
    for tool in tools:
        notes = tool.get("annotations") or {}
        want = EXPECTED_TOOLS[tool["name"]]
        if want == "read-only" and not (notes.get("readOnlyHint") is True and notes.get("destructiveHint") is False):
            raise Refused(f"{tool['name']} must be annotated read-only.")
        if want == "destructive" and not (notes.get("readOnlyHint") is False and notes.get("destructiveHint") is True):
            raise Refused(f"{tool['name']} must be annotated destructive.")

    files = [root / f for f in REQUIRED_FILES]
    files += sorted(p for p in source.rglob("*.py") if "__pycache__" not in p.parts)
    files += [skills_dir / s / "SKILL.md" for s in found]
    for path in files:
        if path.is_symlink():
            raise Refused(f"{path.relative_to(root)} is a symbolic link.")
        relative = path.relative_to(root).as_posix()
        if any(part.startswith(".") for part in Path(relative).parts):
            raise Refused(f"{relative} is a hidden path.")
    return manifest, files


def build(root: Path, out: Path, files: list, manifest: dict) -> tuple:
    name, version = manifest["name"], manifest["version"]
    out.mkdir(parents=True, exist_ok=True)
    stable = out / f"{name}.brxt"
    versioned = out / f"{name}-{version}.brxt"
    with zipfile.ZipFile(stable, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(files, key=lambda p: p.relative_to(root).as_posix()):
            info = zipfile.ZipInfo(path.relative_to(root).as_posix(), date_time=ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            # made on Unix whichever system builds it: zipfile records Windows (0) on Windows,
            # which changes the bytes and tells unzip to ignore the Unix mode below
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            # one line ending everywhere, so a Windows checkout builds the same bytes
            archive.writestr(info, path.read_bytes().replace(b"\r\n", b"\n"))
    data = stable.read_bytes()
    versioned.write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()
    (out / "SHA256SUMS").write_text(f"{digest}  {stable.name}\n{digest}  {versioned.name}\n", encoding="utf-8")
    return stable, versioned, digest


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--previous", type=Path, help="the previous release's gptragent.brxt, for the skill path and identity checks")
    parser.add_argument("--out", type=Path, default=ROOT / "dist")
    parser.add_argument("--check", action="store_true", help="run the checks and write nothing")
    args = parser.parse_args(argv)
    manifest, files = check(ROOT, args.previous)
    if args.check:
        print(f"{manifest['name']} {manifest['version']}: every release check passed ({len(files)} files).")
        return 0
    stable, versioned, digest = build(ROOT, args.out, files, manifest)
    print(f"{stable.name} and {versioned.name}: {len(files)} files, {stable.stat().st_size} bytes, SHA-256 {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
