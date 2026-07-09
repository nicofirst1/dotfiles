"""PYTHONSTARTUP shim: park REPL history under XDG state (Python < 3.13 has no PYTHON_HISTORY)."""
import atexit
import os
import readline

# history is state, not config -> $XDG_STATE_HOME/python/history
state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
histfile = os.path.join(state, "python", "history")
os.makedirs(os.path.dirname(histfile), exist_ok=True)

try:
    readline.read_history_file(histfile)
except FileNotFoundError:
    pass  # first run, nothing to load

atexit.register(readline.write_history_file, histfile)
