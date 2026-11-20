#!/usr/bin/env python3
"""Local context packets and isolated Git worktrees. No model calls or deployment."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

CORE_CONTEXT = ["AGENTS.md", "docs/PROJECT.md", "docs/STATUS.md", "docs/DECISIONS.md",
                "tools/agents/roles.json", "tools/agents/WORKER.md"]


def git(root, *args):
    result = subprocess.run(
        ["git", "-C", str(root), *args], capture_output=True, encoding="utf-8",
        errors="replace", check=False,
    )
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Git command failed")
    return result.stdout.strip() if "-z" not in args else result.stdout


def repository(start):
    top = Path(git(start, "rev-parse", "--show-toplevel")).resolve()
    common = Path(git(top, "rev-parse", "--git-common-dir"))
    common = (top / common).resolve() if not common.is_absolute() else common.resolve()
    root = common.parent
    if not (root / "tools/agents/roles.json").is_file():
        raise ValueError("Run inside the DAMUMU checkout containing tools/agents/roles.json")
    return root


def slug(value):
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,47}", value):
        raise ValueError("Task ID must be 1–48 lowercase letters, numbers or hyphens, starting with a letter")
    return value


def contained(root, *parts):
    root = root.resolve()
    path = root.joinpath(*parts).resolve()
    if not path.is_relative_to(root) or path == root:
        raise ValueError("Path escapes the managed workspace")
    return path


def managed(root):
    return contained(root, ".agent-work")


@contextmanager
def task_lock(root, task_id):
    path = contained(managed(root), "locks", slug(task_id) + ".lock")
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        handle = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise ValueError("Task is locked by another command. If interrupted, inspect and remove its .lock file manually")
    try:
        os.write(handle, str(os.getpid()).encode())
        os.close(handle)
        yield
    finally:
        path.unlink()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def save(path, value):
    temporary = path.with_suffix(".tmp")
    write(temporary, json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def load_roles(root):
    return json.loads((root / "tools/agents/roles.json").read_text(encoding="utf-8"))["roles"]


def task_paths(root, task_id):
    slug(task_id)
    directory = contained(managed(root), "tasks", task_id)
    return directory, directory / "task.json"


def load_task(root, task_id):
    directory, path = task_paths(root, task_id)
    task = json.loads(path.read_text(encoding="utf-8"))
    if task["id"] != task_id:
        raise ValueError("Task manifest ID mismatch")
    roles = load_roles(root)
    if any(role not in roles for role in task["roles"]):
        raise ValueError("Unknown role in task manifest")
    return directory, task


def dependencies(values, roles):
    graph = {role: [] for role in roles}
    for value in values:
        child, separator, parent = value.partition(":")
        if not separator or child not in graph or parent not in graph or child == parent:
            raise ValueError("Dependencies use --depends consumer:provider with selected roles")
        if parent not in graph[child]:
            graph[child].append(parent)
    def visit(role, trail):
        if role in trail:
            raise ValueError("Cyclic task dependencies")
        for parent in graph[role]:
            visit(parent, trail | {role})
    for role in graph:
        visit(role, set())
    return graph


def fingerprint(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() if path.is_file() else "missing"


def sources(root, directory, role):
    paths = CORE_CONTEXT + role["reads"]
    result = {path: fingerprint(root / path) for path in paths}
    result["@brief"] = fingerprint(directory / "brief.md")
    return result


def packet(root, directory, task, name):
    if name not in task["roles"]:
        raise ValueError("Role is not assigned to this task")
    role = load_roles(root)[name]
    destination = contained(directory, name)
    worker = task.get("worktrees", {}).get(name)
    source_root = contained(managed(root), "worktrees", task["id"], name) if worker else root
    if worker and str(source_root) != worker["path"]:
        raise ValueError("Worker path does not match its assigned checkout")
    if worker and any(fingerprint(root / path) != fingerprint(source_root / path) for path in CORE_CONTEXT):
        raise ValueError("Worker canonical context differs from coordinator. Start a new task from the current context commit")
    hashes = sources(source_root, directory, role)
    reading = "\n".join(f"- `{path}` — SHA256 `{digest}`" for path, digest in hashes.items() if path != "@brief")
    checks = "\n".join("- " + value for value in role["checks"])
    owned = ", ".join(role["owns"]) or "none (read-only)"
    checkout = task.get("worktrees", {}).get(name, {}).get("path", "Not prepared; do not write in shared checkout")
    brief = (directory / "brief.md").read_text(encoding="utf-8")
    instructions = (root / "tools/agents/WORKER.md").read_text(encoding="utf-8")
    content = f"""# Task {task['id']} / {name}

Generated: {datetime.now(timezone.utc).isoformat()}
Base SHA: `{task['base']}`
Checkout: `{checkout}`
Assigned branch: `{worker['branch'] if worker else 'Not prepared'}` — use this branch, do not create another.
Mode: {role['mode']}
Owned paths: {owned}
Depends on completed handoff: {', '.join(task['depends'][name]) or 'none'}
Brief SHA256: `{hashes['@brief']}`

## Task brief

{brief}

## Canonical sources to read in your checkout

{reading}

Read AGENTS.md and relevant nested AGENTS.md first. Read PROJECT.md and the
current STATUS.md; select only applicable ADRs and module source. These hashes
are freshness checks, not permissions. Follow current user and host instructions.
Do not ingest .env, credentials, database dumps, uploads or full chat histories.

## Required verification selection

{checks}

{instructions}
"""
    if len(content.encode("utf-8")) > 24000:
        raise ValueError("Packet exceeds 24 KB. Shorten the task brief and link reference files instead")
    write(destination / "packet.md", content)
    handoff = destination / "handoff.md"
    if not handoff.exists():
        write(handoff, "# Handoff — NOT COMPLETED\n\n" +
              "\n".join("## " + title + "\n\nTODO\n" for title in
                        ["Result and commit", "Changed paths", "Contract and dependencies", "Validation evidence",
                         "Risks and missing checks", "Migration / server / App release", "Next action"]))
    task.setdefault("packets", {})[name] = hashes
    task.setdefault("coordinator_context", {})[name] = sources(root, directory, role)
    save(directory / "task.json", task)
    return destination / "packet.md"


def create_task(root, args):
    directory, path = task_paths(root, args.task)
    if directory.exists():
        raise ValueError("Task already exists; use packet to refresh it")
    roles = args.roles.split(",")
    if len(set(roles)) != len(roles) or any(role not in load_roles(root) for role in roles):
        raise ValueError("Select unique roles from tools/agents/roles.json")
    graph = dependencies(args.depends, roles)
    base = git(root, "rev-parse", "--verify", args.base + "^{commit}")
    task = {"version": 1, "id": args.task, "base": base, "roles": roles,
            "depends": graph, "worktrees": {}, "packets": {}}
    brief = f"""# {args.task}

## Outcome

{args.goal}

## Scope and exclusions

TODO — assign exact files where a role owns too broad a module.

## Acceptance criteria

TODO — observable behavior and failure cases, including security boundaries.

## Shared API / data / UI contract

TODO — request/response, error behavior, migration owner/number, localization
owner and consumer compatibility. Write 'not applicable' with a reason if local.

## Dependencies and integration order

{json.dumps(graph, ensure_ascii=False)}

## Validation and server impact

TODO — isolated test resources, commands, device/browser checks and release effects.
"""
    write(directory / "brief.md", brief)
    save(path, task)
    for name in roles:
        packet(root, directory, task, name)
    return directory


def prepare_worktree(root, directory, task, role):
    if role not in task["roles"]:
        raise ValueError("Role is not assigned to this task")
    if "TODO" in (directory / "brief.md").read_text(encoding="utf-8"):
        raise ValueError("Complete brief.md before preparing worker checkouts")
    checkout = contained(managed(root), "worktrees", task["id"], role)
    if role in task["worktrees"] or checkout.exists():
        raise ValueError("Worker checkout already exists; inspect it with status")
    branch = f"feature/agent-{task['id']}-{role}"
    for path in CORE_CONTEXT:
        try:
            base_content = subprocess.run(["git", "-C", str(root), "show", task["base"] + ":" + path],
                                          capture_output=True, check=True).stdout
        except subprocess.CalledProcessError:
            raise ValueError("Base is missing development context. Commit the workflow and start from that commit")
        # Git may normalize line endings; hash the working-tree bytes consistently.
        current = (root / path).read_bytes().replace(b"\r\n", b"\n")
        if base_content.replace(b"\r\n", b"\n") != current:
            raise ValueError("Base context differs from current canonical files. Commit context and create a fresh task")
    checkout.parent.mkdir(parents=True, exist_ok=True)
    git(root, "worktree", "add", "-b", branch, str(checkout), task["base"])
    task["worktrees"][role] = {"path": str(checkout), "branch": branch}
    save(directory / "task.json", task)
    packet(root, directory, task, role)
    return checkout


def changed_paths(checkout, base):
    paths = set()
    for args in [("diff", "--no-renames", "--name-only", "-z", base, "HEAD"),
                 ("diff", "--no-renames", "--name-only", "-z", "HEAD"),
                 ("ls-files", "--others", "--exclude-standard", "-z")]:
        paths.update(path for path in git(checkout, *args).split("\0") if path)
    return sorted(paths)


def audit(root, directory, task, name):
    role = load_roles(root)[name]
    if name not in task["worktrees"]:
        raise ValueError("Prepare this role's worktree first")
    entry = task["worktrees"][name]
    checkout = contained(managed(root), "worktrees", task["id"], name)
    if str(checkout) != entry["path"]:
        raise ValueError("Worktree path does not match managed path")
    if git(checkout, "branch", "--show-current") != entry["branch"]:
        raise ValueError("Worker changed to an unassigned branch")
    git(checkout, "merge-base", "--is-ancestor", task["base"], "HEAD")
    paths = changed_paths(checkout, task["base"])
    escaped = [path for path in paths if not any(path.startswith(prefix) for prefix in role["owns"])]
    stale = (sources(checkout, directory, role) != task["packets"].get(name)
             or sources(root, directory, role) != task.get("coordinator_context", {}).get(name))
    if escaped or stale:
        raise ValueError(f"Scope violations: {escaped}; stale context: {stale}. Refresh packet and review scope")
    git(checkout, "diff", "--check", task["base"])
    return {"role": name, "scope_check": "passed", "changed_paths": paths,
            "head": git(checkout, "rev-parse", "HEAD"),
            "note": "Scope/freshness only. Review handoff, secrets and real test evidence before integration."}


def doctor(root):
    result = {"root": str(root), "git": shutil.which("git"), "python": sys.version.split()[0],
              "codex": shutil.which("codex") or shutil.which("codex.cmd"),
              "branch": git(root, "branch", "--show-current"),
              "workers": 3, "model_calls": "none — dispatch with host tools or Codex worktree sessions"}
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor")
    create = commands.add_parser("new")
    create.add_argument("task", type=slug)
    create.add_argument("--goal", required=True)
    create.add_argument("--roles", default="api,app,web,review")
    create.add_argument("--base", default="HEAD")
    create.add_argument("--depends", action="append", default=[])
    for command in ("packet", "worktree", "check", "status"):
        item = commands.add_parser(command)
        item.add_argument("task", type=slug)
        if command != "status":
            item.add_argument("--role", required=True)
    args = parser.parse_args(argv)
    try:
        root = repository(args.root)
        if args.command == "doctor":
            result = doctor(root)
        else:
            with task_lock(root, args.task):
                if args.command == "new":
                    result = str(create_task(root, args))
                else:
                    directory, task = load_task(root, args.task)
                    if args.command != "status" and args.role not in task["roles"]:
                        raise ValueError("Role is not assigned to this task")
                    if args.command == "packet":
                        result = str(packet(root, directory, task, args.role))
                    elif args.command == "worktree":
                        result = str(prepare_worktree(root, directory, task, args.role))
                    elif args.command == "check":
                        result = audit(root, directory, task, args.role)
                    else:
                        result = task
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (ValueError, OSError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
