#!/usr/bin/env python3
"""Route iTerm split/tab hotkeys to herdr when herdr is running, else to iTerm.

Bind keys (iTerm > Settings > Keys) to action "Invoke Script Function" with:
    herdr_split(direction: "right", session_id: session.id)   # side-by-side split
    herdr_split(direction: "down",  session_id: session.id)   # stacked split
    herdr_tab(session_id: session.id)                         # new tab
    herdr_close(session_id: session.id)                       # close pane (Cmd+W)

If the focused session's foreground program is herdr, the action happens inside
herdr; otherwise iTerm does its native equivalent. "right"->vertical, "down"->horizontal.

Named sessions (herdr --session NAME) each run their own server on a separate
socket, so we derive HERDR_SOCKET_PATH from the client's argv and target that
server instead of the default one.
"""
import asyncio
import json
import os
import re
import iterm2

HERDR = "/opt/homebrew/bin/herdr"  # ponytail: absolute; iTerm's GUI PATH lacks /opt/homebrew/bin
HERDR_DIR = os.path.expanduser("~/.config/herdr")
LOG = os.path.join(HERDR_DIR, "split_debug.log")


def _log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(msg + "\n")
    except Exception:
        pass


def _window_for(app, session):
    for w in app.terminal_windows:
        for t in w.tabs:
            if any(s.session_id == session.session_id for s in t.sessions):
                return w
    return None


async def main(connection):
    app = await iterm2.async_get_app(connection)

    async def _session_info(session):
        """Return (in_herdr, env). env targets the focused session's herdr socket."""
        job = await session.async_get_variable("jobName")
        pid = await session.async_get_variable("jobPid")
        argv = ""
        if pid:
            try:
                p = await asyncio.create_subprocess_exec(
                    "ps", "-o", "args=", "-p", str(pid),
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
                out, _ = await p.communicate()
                argv = out.decode(errors="replace").strip()
            except Exception:
                pass
        m = re.search(r"--session\s+(\S+)", argv)
        sock = (os.path.join(HERDR_DIR, "sessions", m.group(1), "herdr.sock")
                if m else os.path.join(HERDR_DIR, "herdr.sock"))
        env = dict(os.environ)
        env["HERDR_SOCKET_PATH"] = sock
        return (job == "herdr"), env

    async def _run(env, *args):
        p = await asyncio.create_subprocess_exec(
            HERDR, *args, env=env,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        out, err = await p.communicate()
        if p.returncode:  # only log failures, so the file stays empty when healthy
            _log(f"{args} rc={p.returncode} sock={env['HERDR_SOCKET_PATH']} "
                 f"err={err.decode(errors='replace').strip()[:200]}")
        return out

    @iterm2.RPC
    async def herdr_split(direction, session_id):
        session = app.get_session_by_id(session_id)
        if session is None:
            return
        in_herdr, env = await _session_info(session)
        if in_herdr:
            await _run(env, "pane", "split", "--current", "--direction", direction, "--focus")
        else:
            await session.async_split_pane(vertical=(direction == "right"))

    @iterm2.RPC
    async def herdr_tab(session_id):
        session = app.get_session_by_id(session_id)
        if session is None:
            return
        in_herdr, env = await _session_info(session)
        if in_herdr:
            await _run(env, "tab", "create", "--focus")
        else:
            window = _window_for(app, session)
            if window is not None:
                await window.async_create_tab()

    @iterm2.RPC
    async def herdr_close(session_id):
        session = app.get_session_by_id(session_id)
        if session is None:
            return
        in_herdr, env = await _session_info(session)
        if in_herdr:
            out = await _run(env, "pane", "current", "--current")
            try:
                pane_id = json.loads(out)["result"]["pane"]["pane_id"]
            except Exception:
                pane_id = None
            if pane_id:
                await _run(env, "pane", "close", pane_id)
        else:
            # native Cmd+W: pane -> tab -> window, iTerm's own smart close
            await iterm2.MainMenu.async_select_menu_item(connection, "Close")

    await herdr_split.async_register(connection)
    await herdr_tab.async_register(connection)
    await herdr_close.async_register(connection)


iterm2.run_forever(main)
