# agentmemory (decommissioned 2026-08-13)

These scripts and LaunchAgent plists provisioned and ran [agentmemory](https://github.com/rohitg00/agentmemory), a local Claude Code memory plugin. Moved here (not deleted) instead of removed, in case any of it is useful reference if agentmemory — or a future memory tool — gets revisited.

Not stowed from this location, so nothing here runs. The live install (npm package, Claude Code plugin, LaunchAgents) has been fully uninstalled.

Why: a 2026-08-13 status check + content audit found it wasn't worth its recurring operational cost. Full writeup in the wiki: `claude_memory/wiki/projects/claude-memory/agentmemory.md`, `agentmemory-2026-08-13-status.md`, `is-agentmemory-worth-it-2026-08-13.md`.

The actual data (`~/.agentmemory`, ~1.9GB) was left untouched on disk and is backed up daily via restic — see `scripts/backup-restic.sh`. Not deleted; manual extraction of anything useful is deferred to a future session.

The LiteLLM router (`config/litellm/`, `scripts/install-litellm-router.sh`, `scripts/litellm-router-run.sh`) was kept running standalone — it has no agentmemory-exclusive logic worth archiving, just some now-dead code paths (checks for an agentmemory daemon that no longer exists) left as-is.
