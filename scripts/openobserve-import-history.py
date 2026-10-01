#!/usr/bin/env python3
"""openobserve-import-history.py — flatten Claude Code JSONL transcripts and
bulk-ingest them into OpenObserve. Invoked by openobserve-import-history.sh,
which sources creds and resolves paths; see that script's header for the why.

Only `user` and `assistant` lines carry conversation content (the rest —
`mode`, `attachment`, `system`, `file-history-snapshot`, etc. — are UI/session
bookkeeping), so those are the two types mapped to docs.
"""
import argparse
import base64
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BATCH_SIZE = 300


def extract_text(content) -> str:
    """message.content is either a plain string or a list of typed blocks
    (text / thinking / tool_use / tool_result / image...). Flatten to one
    searchable string; tool_result content can itself be a string or a list
    of blocks, so recurse one level for that case."""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts = []
    for block in content:
        if not isinstance(block, dict):
            continue
        btype = block.get("type")
        if btype == "text":
            parts.append(block.get("text", ""))
        elif btype == "tool_use":
            parts.append(f"[tool_use:{block.get('name')}] {json.dumps(block.get('input', {}))}")
        elif btype == "tool_result":
            parts.append(extract_text(block.get("content", "")))
        elif btype == "thinking":
            parts.append(block.get("thinking", ""))
    return "\n".join(p for p in parts if p)


def tool_names(content) -> str:
    if not isinstance(content, list):
        return ""
    names = [b.get("name") for b in content if isinstance(b, dict) and b.get("type") == "tool_use"]
    return ",".join(n for n in names if n)


def to_doc(entry: dict, project: str, source_file: str) -> dict | None:
    etype = entry.get("type")
    if etype not in ("user", "assistant"):
        return None
    msg = entry.get("message") or {}
    text = extract_text(msg.get("content"))
    if not text:
        return None
    ts = entry.get("timestamp")
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (TypeError, ValueError, AttributeError):
        dt = datetime.now(timezone.utc)
    return {
        "_timestamp": int(dt.timestamp() * 1_000_000),
        "event_type": etype,
        "role": msg.get("role", etype),
        "text": text,
        "session_id": entry.get("sessionId", ""),
        "project": project,
        "cwd": entry.get("cwd", ""),
        "git_branch": entry.get("gitBranch", ""),
        "model": msg.get("model", ""),
        "tool_names": tool_names(msg.get("content")),
        "uuid": entry.get("uuid", ""),
        "version": entry.get("version", ""),
        "source_file": source_file,
        "is_subagent": bool(entry.get("isSidechain", False)),
        "agent_id": entry.get("agentId", ""),
    }


def load_state(path: Path) -> dict:
    if path.exists():
        return json.loads(path.read_text())
    return {}


def save_state(path: Path, state: dict) -> None:
    path.write_text(json.dumps(state, indent=2, sort_keys=True))


def project_name(projects_dir: Path, jsonl_path: Path) -> str:
    # Session transcripts live at projects/<project>/<session>.jsonl; subagent
    # transcripts one level deeper at projects/<project>/<session>/subagents/
    # <agent>.jsonl. Either way, the project dir is the path component right
    # under projects_dir. Names are the project cwd with "/" turned into "-"
    # (e.g. "-Users-nbrandizzi-dotfiles") — strip the leading "-".
    rel = jsonl_path.relative_to(projects_dir)
    return rel.parts[0].lstrip("-")


def post_batch(base_url: str, org: str, stream: str, user: str, password: str, docs: list) -> None:
    url = f"{base_url}/api/{org}/{stream}/_json"
    body = json.dumps(docs).encode()
    auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Basic {auth}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"ingest failed ({e.code}): {detail}")
    # OpenObserve's bulk _json endpoint returns HTTP 200 even when every doc in
    # the batch was rejected (e.g. outside the ingest time window) — the real
    # per-doc outcome is in the body, so check it explicitly.
    for status in result.get("status", []):
        if status.get("failed"):
            raise SystemExit(f"ingest partially failed: {json.dumps(status)}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--org", required=True)
    ap.add_argument("--stream", required=True)
    ap.add_argument("--projects-dir", required=True)
    ap.add_argument("--state-file", required=True)
    ap.add_argument("--user", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--file", help="import only this one transcript (smoke test)")
    args = ap.parse_args()

    projects_dir = Path(args.projects_dir)
    state_path = Path(args.state_file)
    state = load_state(state_path)

    # Recursive: top-level session transcripts (<project>/<session>.jsonl) plus
    # subagent transcripts one level deeper (<project>/<session>/subagents/*.jsonl).
    files = [Path(args.file)] if args.file else sorted(projects_dir.glob("**/*.jsonl"))

    total_docs = 0
    total_files_touched = 0
    batch: list[dict] = []

    def flush():
        nonlocal batch, total_docs
        if not batch:
            return
        if not args.dry_run:
            post_batch(args.base_url, args.org, args.stream, args.user, args.password, batch)
        total_docs += len(batch)
        batch = []

    for fp in files:
        key = str(fp)
        already = state.get(key, {}).get("lines_imported", 0)
        proj = project_name(projects_dir, fp)

        try:
            lines = fp.read_text(errors="replace").splitlines()
        except OSError as e:
            print(f"skip {fp}: {e}", file=sys.stderr)
            continue

        if len(lines) <= already:
            continue  # fully imported already, no new lines appended

        new_lines = lines[already:]
        file_docs = 0
        for line in new_lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            doc = to_doc(entry, proj, str(fp))
            if doc is None:
                continue
            batch.append(doc)
            file_docs += 1
            if len(batch) >= BATCH_SIZE:
                flush()

        if file_docs:
            total_files_touched += 1
        if not args.dry_run:
            state[key] = {"lines_imported": len(lines)}

    flush()

    if not args.dry_run:
        save_state(state_path, state)

    mode = "DRY RUN — " if args.dry_run else ""
    print(f"{mode}files scanned: {len(files)}, files with new docs: {total_files_touched}, docs ingested: {total_docs}")


if __name__ == "__main__":
    main()
