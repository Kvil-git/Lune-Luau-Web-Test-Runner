"""
Parse_Scripts_For_Tests - Luau Test Pipeline

Prepares Luau source files for the Lune-based test runner by:
  1. Optionally renaming .lua files to .luau in the source tree.
  2. Discovering all .luau scripts under the source directory.
  3. Copying them into a flat output folder with rewritten require() paths.
  4. Auto-discovering mock libraries from the submodule's built-in mocks/
     directory AND an optional project-specific mocks directory, copying them
     to the same output folder, and injecting require() lines into every
     processed script that references the corresponding global name.
  5. Removing "folder" variables that existed solely to build Roblox-style
     require paths (e.g. `local RS = game.ReplicatedStorage`).

Usage:
    python Parse_Scripts_For_Tests.py <source> <output> [--project-mocks <dir>]
    python Parse_Scripts_For_Tests.py <source> <output>                 (built-in mocks only)
    python Parse_Scripts_For_Tests.py --test                            (self-test)
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import traceback

from pathlib import Path
from typing  import Dict, List, Optional, Set


# ---------------------------------------------------------------------------
# 1. File Discovery
# ---------------------------------------------------------------------------

LUAU_EXTENSIONS = (".luau",)


def rename_lua_to_luau(directory: Path) -> int:
    """Rename every .lua file under *directory* to .luau.  Returns count."""
    count = 0
    for lua_file in directory.rglob("*.lua"):
        target = lua_file.with_suffix(".luau")
        if target.exists():
            print(f"  SKIP (target exists): {lua_file}")
            continue
        lua_file.rename(target)
        count += 1
    return count


def find_luau_files(source_dir: Path, exclude_dir: Optional[Path] = None) -> List[Path]:
    """Recursively find all .luau files, skipping *exclude_dir*."""
    results: List[Path] = []
    seen_names: Set[str] = set()

    for path in sorted(source_dir.rglob("*.luau")):
        if exclude_dir and path.is_relative_to(exclude_dir):
            continue
        if not path.is_file():
            continue
        if path.name in seen_names:
            print(f"  WARNING: duplicate filename '{path.name}' - may cause conflicts")
        seen_names.add(path.name)
        results.append(path)

    return results


def discover_mock_libraries(mock_dir: Path) -> List[Path]:
    """Return every .luau file directly inside *mock_dir* (non-recursive)."""
    if not mock_dir.is_dir():
        return []
    return sorted(p for p in mock_dir.iterdir() if p.suffix == ".luau" and p.is_file())


# ---------------------------------------------------------------------------
# 2. Require Rewriting
# ---------------------------------------------------------------------------

# Matches `require("...")` or `require('...')`.
_RE_REQUIRE_STR = re.compile(r'require\s*\(\s*["\']([^"\']+)["\']\s*\)')

# Matches a "local Foo = <game-path>" definition used purely for require routing.
_RE_FOLDER_DEF = re.compile(
    r'^local\s+([A-Za-z_]\w*)\s*=\s*(game\b.+|[A-Za-z_]\w*\s*\..+)$'
)


def _extract_module_name(expr: str) -> Optional[str]:
    """Given the inner expression of a `require(...)` call, return the final
    dotted segment (the module name) or *None* if we can't resolve it."""
    clean = re.sub(r'\s+', '', expr)
    parts = clean.split('.')
    return parts[-1] if parts else None


def _find_matching_paren(content: str, open_paren_idx: int) -> Optional[int]:
    """Return the index of the closing paren that matches *open_paren_idx*."""
    depth = 0
    quote: Optional[str] = None
    escape = False

    for idx in range(open_paren_idx, len(content)):
        ch = content[idx]

        if quote is not None:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            continue

        if ch in ('"', "'"):
            quote = ch
            continue

        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return idx

    return None


def _rewrite_require_call(call_text: str) -> str:
    """Rewrite a single `require(...)` call if we can resolve its target."""
    inner = call_text[len("require("):-1]
    stripped = inner.strip()

    if not stripped:
        return call_text

    if stripped[0] in ('"', "'") and stripped[-1] == stripped[0]:
        path = stripped[1:-1]
        if path.startswith("@lune/"):
            return call_text
        if path.startswith("./") and "/" not in path[2:]:
            return call_text
        module = path.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
        for ext in (".luau", ".lua"):
            if module.endswith(ext):
                module = module[: -len(ext)]
                break
        return f'require("./{module}")'

    module = _extract_module_name(inner)
    if module:
        return f'require("./{module}")'
    return call_text


def _rewrite_require_expr(match: re.Match) -> str:
    """Callback for re.sub - rewrite a game-path require to a string require."""
    module = _extract_module_name(match.group(1))
    if module:
        return f'require("./{module}")'
    return match.group(0)


def _flatten_string_require(match: re.Match) -> str:
    """Callback for re.sub - flatten a string require to `./ModuleName`."""
    path = match.group(1)
    if path.startswith("@lune/"):
        return match.group(0)
    # Already a flat relative require - keep it.
    if path.startswith("./") and "/" not in path[2:]:
        return match.group(0)
    # Extract the last path segment as the module name.
    module = path.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
    # Strip extension if present.
    for ext in (".luau", ".lua"):
        if module.endswith(ext):
            module = module[: -len(ext)]
            break
    return f'require("./{module}")'


def rewrite_requires(content: str) -> str:
    """Rewrite all require() calls in *content* to flat `./Module` form.

    Handles both expression-style (`require(Folder.Module)`) and string-style
    (`require("../some/path")`) requires.  Lune built-ins (`@lune/...`) are
    left untouched.
    """
    rewritten: List[str] = []
    idx = 0

    while True:
        match = re.search(r'require\s*\(', content[idx:])
        if not match:
            rewritten.append(content[idx:])
            break

        start = idx + match.start()
        open_paren_idx = idx + match.end() - 1
        end = _find_matching_paren(content, open_paren_idx)

        if end is None:
            rewritten.append(content[idx:])
            break

        rewritten.append(content[idx:start])
        call_text = content[start:end + 1]
        rewritten.append(_rewrite_require_call(call_text))
        idx = end + 1

    content = "".join(rewritten)
    content = _RE_REQUIRE_STR.sub(_flatten_string_require, content)
    return content


# ---------------------------------------------------------------------------
# 3. Folder-Variable Removal
# ---------------------------------------------------------------------------

def _find_folder_definitions(lines: List[str]) -> Dict[str, int]:
    """Return {var_name: line_index} for folder variables."""
    defs: Dict[str, int] = {}
    for i, line in enumerate(lines):
        m = _RE_FOLDER_DEF.match(line.strip())
        if m:
            defs[m.group(1)] = i
    return defs


def _variable_used_outside_requires(var: str, lines: List[str], def_idx: int) -> bool:
    """True if *var* appears in a non-require, non-definition context."""
    pattern = re.compile(rf'\b{re.escape(var)}\b')
    for i, line in enumerate(lines):
        if i == def_idx:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("--"):
            continue
        for m in pattern.finditer(line):
            # Inside a require() call - skip.
            prefix = line[:m.start()]
            suffix = line[m.end():]
            if re.search(r'require\s*\(\s*$', prefix) or re.search(r'require\s*\(', prefix):
                # Check if there's a closing paren soon after.
                if re.search(r'^[^)]*\)', suffix):
                    continue
            # Check we're not inside a string or comment.
            before = line[:m.start()]
            if "--" in before:
                comment_pos = before.index("--")
                if m.start() > comment_pos:
                    continue
            if (before.count('"') + before.count("'")) % 2 != 0:
                continue
            return True
    return False


def remove_folder_variables(content: str) -> str:
    """Remove `local Foo = game.X.Y.Z` lines whose variable is only used
    inside require() calls (i.e. pure routing variables)."""
    lines = content.split("\n")
    folder_defs = _find_folder_definitions(lines)
    indices_to_remove: Set[int] = set()

    for var, idx in folder_defs.items():
        if not _variable_used_outside_requires(var, lines, idx):
            indices_to_remove.add(idx)

    if not indices_to_remove:
        return content

    return "\n".join(line for i, line in enumerate(lines) if i not in indices_to_remove)


# ---------------------------------------------------------------------------
# 4. Mock Library Injection
# ---------------------------------------------------------------------------

# `task` is a Lune built-in, not a file-based mock - handled separately.
_TASK_REQUIRE = 'local task = require("@lune/task")'


def build_mock_require_line(mock_stem: str) -> str:
    """Return the require line for a file-based mock, e.g. `local Vector3 = require("./Vector3")`."""
    return f'local {mock_stem} = require("./{mock_stem}")'


def inject_mock_requires(
    content: str,
    filename: str,
    mock_stems: List[str],
) -> str:
    """Prepend require lines for every mock library whose name appears in
    *content*, unless the file IS the mock itself or the require already
    exists.

    Also injects the Lune `task` require when `task.` appears in *content*.
    """
    base_stem = filename.rsplit(".", 1)[0] if "." in filename else filename

    imports_to_add: List[str] = []

    # File-based mocks.
    for stem in mock_stems:
        if stem == base_stem:
            continue
        marker = f'require("./{stem}")'
        if marker in content:
            continue
        # Only inject if the mock name actually appears in the file.
        if re.search(rf'\b{re.escape(stem)}\b', content):
            imports_to_add.append(build_mock_require_line(stem))

    # Lune task built-in.
    if "task." in content and 'require("@lune/task")' not in content:
        imports_to_add.insert(0, _TASK_REQUIRE)

    if not imports_to_add:
        return content

    lines = content.split("\n")

    # Insert after the leading comment / --!strict block.
    insert_idx = 0
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped and not stripped.startswith("--"):
            insert_idx = idx
            break

    for import_line in reversed(imports_to_add):
        lines.insert(insert_idx, import_line)

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 5. Single-File Processing (orchestration of 2 + 3 + 4)
# ---------------------------------------------------------------------------

def process_file(content: str, filename: str, mock_stems: List[str]) -> str:
    """Full processing pipeline for one source file."""
    content = rewrite_requires(content)
    content = remove_folder_variables(content)
    content = inject_mock_requires(content, filename, mock_stems)
    return content


# ---------------------------------------------------------------------------
# 6. Pipeline Runner
# ---------------------------------------------------------------------------

def run_pipeline(
    source_dir: Path,
    output_dir: Path,
    project_mock_dir: Optional[Path] = None,
    *,
    rename_lua: bool = True,
) -> None:
    """Execute the full pipeline.

    Mock libraries are sourced from two locations:
      1. The submodule's built-in mocks/ directory (always, if it exists).
      2. An optional project-specific mocks directory (--project-mocks).

    Project-specific mocks override built-in mocks when filenames collide.
    """
    built_in_mocks_dir = Path(__file__).resolve().parent / "mocks"

    print(f"Source:      {source_dir}")
    print(f"Output:      {output_dir}")
    print(f"Built-in mocks: {built_in_mocks_dir}")
    print(f"Project mocks:  {project_mock_dir or '(none)'}")
    print()

    # Step 1 - optional .lua => .luau rename.
    if rename_lua:
        count = rename_lua_to_luau(source_dir)
        if count:
            print(f"[1] Renamed {count} .lua file(s) to .luau")
        else:
            print("[1] No .lua files to rename")

    # Step 2 - clean output directory.
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    # Step 3 - discover and copy mock libraries from BOTH locations.
    # Project-specific mocks override built-in mocks (same filename wins).
    mock_stems: List[str] = []
    mock_names: Set[str] = set()

    # Copy built-in mocks first.
    built_in_files = discover_mock_libraries(built_in_mocks_dir)
    for mock_file in built_in_files:
        shutil.copy2(mock_file, output_dir / mock_file.name)
        stem = mock_file.stem
        if stem not in mock_names:
            mock_stems.append(stem)
            mock_names.add(stem)
        print(f"[2] Copied built-in mock: {mock_file.name}")

    # Copy project-specific mocks (may override built-in).
    if project_mock_dir:
        project_files = discover_mock_libraries(project_mock_dir)
        for mock_file in project_files:
            shutil.copy2(mock_file, output_dir / mock_file.name)
            stem = mock_file.stem
            if stem not in mock_names:
                mock_stems.append(stem)
                mock_names.add(stem)
                print(f"[2] Copied project mock: {mock_file.name}")
            else:
                print(f"[2] Copied project mock (overrides built-in): {mock_file.name}")
        if not project_files:
            print("[2] No project-specific mock libraries found")
    else:
        print("[2] No project-specific mock directory specified")

    # Step 4 - discover, process, and copy source files.
    source_files = find_luau_files(source_dir, exclude_dir=output_dir)
    if not source_files:
        print("[3] No .luau source files found")
        return

    # Build set of mock filenames so source files with the same name are skipped.
    mock_filenames = set(stem + ".luau" for stem in mock_stems)

    print(f"[3] Processing {len(source_files)} source file(s)...")
    skipped_for_mock = 0
    for src_path in source_files:
        if src_path.name in mock_filenames:
            skipped_for_mock += 1
            continue
        try:
            content = src_path.read_text(encoding="utf-8")
            processed = process_file(content, src_path.name, mock_stems)
            (output_dir / src_path.name).write_text(processed, encoding="utf-8")
            print(f"     {src_path.name}")
        except Exception as exc:
            print(f"  ERROR processing {src_path}: {exc}")
            traceback.print_exc()
    if skipped_for_mock:
        print(f"     ({skipped_for_mock} source file(s) skipped — overridden by mock)")

    print()
    print(f"Done - {len(source_files) - skipped_for_mock} file(s) written to {output_dir}")


# ---------------------------------------------------------------------------

# 7. Self-Test
# ---------------------------------------------------------------------------

def self_test() -> None:
    """Quick smoke tests for core helpers."""
    print("Running self-tests...")

    # require rewriting.
    assert rewrite_requires('require(game.RS.Modules.Foo)') == 'require("./Foo")'
    assert rewrite_requires('require(Folder.Sub.Bar)') == 'require("./Bar")'
    assert rewrite_requires('require(Replicated_Storage:WaitForChild("Classes").Game_Instances.Archetypes.Build_Archetype.Build_Archetype)') == 'require("./Build_Archetype")'
    assert rewrite_requires('require("@lune/task")') == 'require("@lune/task")'
    assert rewrite_requires('require("../some/deep/Module")') == 'require("./Module")'
    assert rewrite_requires('require("./Already")') == 'require("./Already")'

    # folder variable removal.
    src = "local RS = game.ReplicatedStorage.Stuff\nlocal M = require(RS.Module)\n"
    result = remove_folder_variables(src)
    assert "local RS" not in result
    assert "require" in result

    # mock injection.
    code = "local v = Vector3.new(1,2,3)\n"
    injected = inject_mock_requires(code, "Foo.luau", ["Vector2", "Vector3"])
    assert 'require("./Vector3")' in injected
    assert 'require("./Vector2")' not in injected  # Vector2 not used.

    # task injection.
    code2 = "task.wait(1)\n"
    injected2 = inject_mock_requires(code2, "Bar.luau", [])
    assert 'require("@lune/task")' in injected2

    print("All self-tests passed.")


# ---------------------------------------------------------------------------
# 8. CLI Entry Point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Prepare Luau source files for the Lune test runner."
    )
    parser.add_argument("source", nargs="?", help="Root of the Luau source tree")
    parser.add_argument("output", nargs="?", help="Flat output directory for processed files")
    parser.add_argument(
        "--project-mocks",
        default=None,
        dest="project_mocks",
        help="Directory containing project-specific mock library .luau files (overrides built-in mocks)",
    )
    parser.add_argument("--no-rename", action="store_true", help="Skip .lua => .luau renaming step")
    parser.add_argument("--test", action="store_true", help="Run built-in self-tests")

    args = parser.parse_args()

    if args.test:
        self_test()
        return

    if not args.source or not args.output:
        parser.print_help()
        sys.exit(1)

    source_path = Path(args.source).resolve()
    output_path = Path(args.output).resolve()
    project_mock_path = Path(args.project_mocks).resolve() if args.project_mocks else None

    if not source_path.is_dir():
        print(f"Error: source directory '{args.source}' does not exist.")
        sys.exit(1)

    if project_mock_path and not project_mock_path.is_dir():
        print(f"Error: mock directory '{args.project_mocks}' does not exist.")
        sys.exit(1)

    run_pipeline(source_path, output_path, project_mock_path, rename_lua=not args.no_rename)


if __name__ == "__main__":
    main()
