#!/usr/bin/env python3
"""Route iTerm split/tab hotkeys to herdr when herdr is running, else to iTerm.

Bind keys (iTerm > Settings > Keys) to action "Invoke Script Function" with:
    herdr_split(direction: "right", session_id: session.id)   # side-by-side split
    herdr_split(direction: "down",  session_id: session.id)   # stacked split
    herdr_tab(session_id: session.id)                         # new tab
    herdr_close(session_id: session.id)                       # close pane (Cmd+W)

If the focused session's foreground program is herdr, the action happens inside
herdr; otherwise iTerm does its native equivalent. "right"->vertical, "down"->horizontal.
"""
import asyncio
import json
import iterm2

HERDR = "/opt/homebrew/bin/herdr"  # ponytail: absolute; iTerm's GUI PATH lacks /opt/homebrew/bin


def _window_for(app, session):
    for w in app.terminal_windows:
        for t in w.tabs:
            if any(s.session_id == session.session_id for s in t.sessions):
                return w
    return None


async def main(connection):
    app = await iterm2.async_get_app(connection)

    async def _in_herdr(session):
        return (await session.async_get_variable("jobName")) == "herdr"

    async def _herdr_current_pane():
        proc = await asyncio.create_subprocess_exec(
            HERDR, "pane", "current", "--current",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        out, _ = await proc.communicate()
        try:
            return json.loads(out)["result"]["pane"]["pane_id"]
        except Exception:
            return None

    @iterm2.RPC
    async def herdr_split(direction, session_id):
        session = app.get_session_by_id(session_id)
        if session is None:
            return
        if await _in_herdr(session):
            proc = await asyncio.create_subprocess_exec(
                HERDR, "pane", "split", "--current", "--direction", direction, "--focus")
            await proc.wait()
        else:
            await session.async_split_pane(vertical=(direction == "right"))

    @iterm2.RPC
    async def herdr_tab(session_id):
        session = app.get_session_by_id(session_id)
        if session is None:
            return
        if await _in_herdr(session):
            proc = await asyncio.create_subprocess_exec(HERDR, "tab", "create", "--focus")
            await proc.wait()
        else:
            window = _window_for(app, session)
            if window is not None:
                await window.async_create_tab()

    @iterm2.RPC
    async def herdr_close(session_id):
        session = app.get_session_by_id(session_id)
        if session is None:
            return
        if await _in_herdr(session):
            pane_id = await _herdr_current_pane()
            if pane_id:
                proc = await asyncio.create_subprocess_exec(HERDR, "pane", "close", pane_id)
                await proc.wait()
        else:
            # native Cmd+W: pane -> tab -> window, iTerm's own smart close
            await iterm2.MainMenu.async_select_menu_item(connection, "Close")

    await herdr_split.async_register(connection)
    await herdr_tab.async_register(connection)
    await herdr_close.async_register(connection)


iterm2.run_forever(main)
