#!/usr/bin/env python3
"""Audit installed-but-unused stuff. Read-only: it suggests, never removes.

Covers: Homebrew formulae, macOS apps (incl. casks), Claude Code skills,
plugins, and MCP servers. Usage is mined from your Claude transcripts
(~/.claude/projects/*.jsonl), your zsh history, Homebrew receipts, and
Spotlight's last-opened metadata (mdls).

  audit-unused.py                 # candidates only (never / stale)
  audit-unused.py --all           # include things you actively use
  audit-unused.py --stale-days 60 # what counts as "stale" (default 90)
  audit-unused.py --only skills,brew
  audit-unused.py --selftest

Signal quality, honestly:
  skills / mcp / plugins  strong  - exact invocation records in transcripts
  apps                    strong  - Spotlight kMDItemLastUsedDate
  brew                    fair    - name seen in transcript Bash cmds + zsh
                                    history; binary!=formula aliases handled
                                    for the common cases, rest may false-flag
"""
import argparse, glob, json, os, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
PROJECTS = HOME / ".claude" / "projects"
NOW = datetime.now(timezone.utc)

# --- regexes over raw transcript lines (faster than json.loads per line) ---
TS = re.compile(r'"timestamp":"([^"]+)"')
SKILL_TOOL = re.compile(r'"skill":"([^"]+)"')          # Skill tool_use
SLASH_CMD = re.compile(r"<command-name>/([A-Za-z0-9:._-]+)")  # user typed /x
MCP_CALL = re.compile(r'"name":"mcp__(.+?)__')          # mcp__server__tool
BASH_CMD = re.compile(r'"command":"((?:[^"\\]|\\.)*)"')  # Bash tool_use cmd
WORD = re.compile(r"[A-Za-z0-9_.+-]+")

# formula name -> binary(ies) it actually installs, for the notorious mismatches
BREW_ALIASES = {
    "ripgrep": ["rg"], "neovim": ["nvim"], "fd-find": ["fd"], "bat": ["bat"],
    "the-silver-searcher": ["ag"], "git-delta": ["delta"], "lazygit": ["lazygit"],
    "python-tk@3.12": ["python3.12"], "libgit2@1.7": [], "midnight-commander": ["mc"],
    "dua-cli": ["dua"], "gitlab-ci-local": ["gitlab-ci-local"], "ncdu": ["ncdu"],
    "git-lfs": ["git-lfs"], "ruby-install": ["ruby-install"], "wireguard-tools": ["wg"],
}


def days_since(iso):
    if not iso:
        return None
    try:
        d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return (NOW - d).days
    except ValueError:
        return None


def scan_transcripts():
    """One pass over all transcripts. Returns:
    usage[kind][name] = {'count': int, 'last': iso}   (kind: skill | mcp)
    bash_tokens: set of words seen in Bash commands (for brew usage)."""
    usage = {"skill": {}, "mcp": {}}
    bash_tokens = set()

    def bump(kind, name, ts):
        e = usage[kind].setdefault(name, {"count": 0, "last": ""})
        e["count"] += 1
        if ts and ts > e["last"]:
            e["last"] = ts

    for fp in PROJECTS.glob("**/*.jsonl"):
        try:
            with open(fp, encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    if "skill" not in line and "command-name" not in line \
                       and "mcp__" not in line and '"command"' not in line:
                        continue
                    tsm = TS.search(line)
                    ts = tsm.group(1) if tsm else ""
                    for m in SKILL_TOOL.findall(line):
                        bump("skill", m, ts)
                    for m in SLASH_CMD.findall(line):
                        bump("skill", m, ts)
                    for m in MCP_CALL.findall(line):
                        bump("mcp", m, ts)
                    for cmd in BASH_CMD.findall(line):
                        bash_tokens.update(w.lower() for w in WORD.findall(cmd))
        except OSError:
            continue
    return usage, bash_tokens


def skill_usage_for(leaf, usage):
    """Sum usage across both channels, matching installed dir-leaf to the
    invoked name (which may be plugin-prefixed: claude-obsidian:wiki-query)."""
    count, last = 0, ""
    for name, e in usage["skill"].items():
        if name == leaf or name.split(":")[-1] == leaf:
            count += e["count"]
            if e["last"] > last:
                last = e["last"]
    return count, last


def installed_skills():
    """leaf-name -> install-date-proxy (dir mtime iso). Dedup by leaf."""
    out = {}
    roots = [HOME / ".claude" / "skills", HOME / ".claude" / "plugins" / "cache"]
    for root in roots:
        for sk in root.glob("**/SKILL.md"):
            leaf = sk.parent.name
            iso = datetime.fromtimestamp(sk.stat().st_mtime, timezone.utc).isoformat()
            out.setdefault(leaf, iso)
    return out


def installed_plugins():
    """name -> {installedAt, lastUpdated, skills:[leaf...]}"""
    fp = HOME / ".claude" / "plugins" / "installed_plugins.json"
    if not fp.exists():
        return {}
    data = json.loads(fp.read_text()).get("plugins", {})
    out = {}
    for full, entries in data.items():
        name = full.split("@")[0]
        e = entries[0] if entries else {}
        skills = []
        ip = e.get("installPath", "")
        if ip:
            for sk in Path(ip).glob("**/SKILL.md"):
                skills.append(sk.parent.name)
        out[name] = {"installedAt": e.get("installedAt", ""),
                     "lastUpdated": e.get("lastUpdated", ""), "skills": skills}
    return out


def configured_mcp():
    fp = HOME / ".claude.json"
    if not fp.exists():
        return set()
    d = json.loads(fp.read_text())
    srv = set(d.get("mcpServers", {}) or {})
    for v in (d.get("projects", {}) or {}).values():
        srv.update((v.get("mcpServers") or {}).keys())
    return srv


def zsh_tokens():
    hist = os.environ.get("HISTFILE") or str(
        HOME / ".local" / "state" / "zsh" / "history")
    p = Path(hist)
    if not p.exists():
        return set()
    txt = p.read_text(encoding="utf-8", errors="ignore")
    return {w.lower() for w in WORD.findall(txt)}


def brew(cmd):
    try:
        return subprocess.run(["brew", *cmd], capture_output=True, text=True,
                              timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def brew_leaves():
    """leaf formula -> {installed: iso, binaries: [names]}"""
    names = brew(["leaves", "--installed-on-request"]).split()
    cellar = brew(["--cellar"]).strip()
    out = {}
    for f in names:
        iso, bins = "", BREW_ALIASES.get(f, [f])
        recs = glob.glob(f"{cellar}/{f}/*/INSTALL_RECEIPT.json")
        if recs:
            try:
                t = json.load(open(recs[0])).get("time")
                if t:
                    iso = datetime.fromtimestamp(t, timezone.utc).isoformat()
            except (OSError, ValueError):
                pass
        out[f] = {"installed": iso, "binaries": bins or [f]}
    return out


def mac_apps():
    """app name -> {last: iso, count: int}"""
    dirs = ["/Applications", "/Applications/Utilities", str(HOME / "Applications")]
    apps = []
    for d in dirs:
        apps += glob.glob(f"{d}/*.app")
    out = {}
    for app in sorted(set(apps)):
        try:
            r = subprocess.run(
                ["mdls", "-name", "kMDItemLastUsedDate",
                 "-name", "kMDItemUseCount", app],
                capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        last, cnt = "", 0
        for ln in r.splitlines():
            if "kMDItemLastUsedDate" in ln and "null" not in ln:
                last = ln.split("=", 1)[1].strip().strip('"').replace(" +0000", "")
                last = last.replace(" ", "T") + "+00:00"
            if "kMDItemUseCount" in ln and "null" not in ln:
                try:
                    cnt = int(ln.split("=", 1)[1].strip())
                except ValueError:
                    pass
        out[Path(app).stem] = {"last": last, "count": cnt}
    return out


# --------------------------- reporting ---------------------------
def verdict(last, installed, stale_days):
    """-> (tag, sortkey). Lower sortkey = worse (shown first)."""
    ds = days_since(last)
    if ds is None:  # never used
        inst = days_since(installed)
        if inst is not None and inst < stale_days:
            return "new, unused", (1, -inst)   # too fresh to judge harshly
        return "NEVER USED", (0, 0)
    if ds >= stale_days:
        return f"stale {ds}d", (2, -ds)
    return f"used {ds}d ago", (3, -ds)


def section(title, rows, show_all, stale_days):
    """rows: list of (name, count, last, installed). Prints candidates."""
    graded = []
    for name, count, last, inst in rows:
        tag, key = verdict(last, inst, stale_days)
        graded.append((key, name, count, tag))
    graded.sort()
    keep = [g for g in graded if not g[3].startswith("used ")]
    shown = graded if show_all else keep
    print(f"\n== {title} ==  ({len(keep)} candidate(s) of {len(rows)})")
    if not shown:
        print("  nothing flagged")
        return
    for _, name, count, tag in shown:
        print(f"  {tag:<14} {count:>4}x  {name}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stale-days", type=int, default=90)
    ap.add_argument("--all", action="store_true", help="show actively-used too")
    ap.add_argument("--only", default="", help="comma list: skills,mcp,plugins,brew,apps")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()

    want = set(a.only.split(",")) if a.only else {"skills", "mcp", "plugins", "brew", "apps"}
    sd, allf = a.stale_days, a.all
    print(f"audit-unused  (stale threshold: {sd}d; 'used Nd ago' hidden unless --all)")

    usage, bash_tokens = ({"skill": {}, "mcp": {}}, set())
    if want & {"skills", "mcp", "plugins", "brew"}:
        usage, bash_tokens = scan_transcripts()

    if "skills" in want:
        rows = []
        for leaf, inst in installed_skills().items():
            c, last = skill_usage_for(leaf, usage)
            rows.append((leaf, c, last, inst))
        section("Claude skills", rows, allf, sd)

    if "mcp" in want:
        seen = usage["mcp"]
        universe = set(seen) | configured_mcp()
        rows = [(n, seen.get(n, {}).get("count", 0), seen.get(n, {}).get("last", ""), "")
                for n in universe]
        section("MCP servers", rows, allf, sd)

    if "plugins" in want:
        rows = []
        for name, p in installed_plugins().items():
            best_c, best_last = 0, ""
            for leaf in p["skills"]:
                c, last = skill_usage_for(leaf, usage)
                best_c += c
                if last > best_last:
                    best_last = last
            rows.append((name, best_c, best_last, p["installedAt"]))
        section("Plugins (dead = none of its skills ever fired)", rows, allf, sd)

    if "brew" in want:
        cmd_tokens = bash_tokens | zsh_tokens()  # commands run in Claude + your shell
        rows = []
        for f, info in brew_leaves().items():
            names = {f.lower(), *(b.lower() for b in info["binaries"])}
            used = bool(names & cmd_tokens)
            # last-used date is unknowable for brew; treat used->recent, else never
            last = NOW.isoformat() if used else ""
            rows.append((f, 1 if used else 0, last, info["installed"]))
        section("Homebrew leaves (orphans; 'used' = name seen in your commands)",
                rows, allf, sd)

    if "apps" in want:
        rows = [(n, i["count"], i["last"], "") for n, i in mac_apps().items()]
        section("macOS apps (last opened via Spotlight)", rows, allf, sd)

    print("\nNothing was changed. Review, then remove by hand.")


def selftest():
    assert days_since(None) is None
    assert SLASH_CMD.findall("<command-name>/claude-obsidian:wiki-query") == \
        ["claude-obsidian:wiki-query"]
    assert SKILL_TOOL.findall('"skill":"tdd"') == ["tdd"]
    assert MCP_CALL.findall('"name":"mcp__home-assistant__call"') == ["home-assistant"]
    assert MCP_CALL.findall('"name":"mcp__plugin_timbro_timbro__score"') == \
        ["plugin_timbro_timbro"]
    assert BASH_CMD.findall('"command":"rg foo | jq .bar"') == ["rg foo | jq .bar"]
    u = {"skill": {"claude-obsidian:wiki-query": {"count": 213, "last": "2026-07-01"},
                   "wiki-query": {"count": 1, "last": "2026-05-01"}}}
    assert skill_usage_for("wiki-query", u) == (214, "2026-07-01")
    t, _ = verdict("", "", 90)
    assert t == "NEVER USED"
    assert verdict("2000-01-01T00:00:00+00:00", "", 90)[0].startswith("stale")
    print("selftest ok")


if __name__ == "__main__":
    main()
