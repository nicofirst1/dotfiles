#!/usr/bin/env bash
#
# install-pyenv.sh  —  seed pyenv Python versions at the XDG root
#
# pyenv's compiled interpreters are NOT relocatable (each hardcodes an absolute
# libpython dylib install-name + console-script shebangs + build-time sysconfig
# paths), so moving ~/.pyenv is a reinstall, not a `mv`. This script reinstalls
# the declared version set at $PYENV_ROOT (set to an XDG data dir in exports.sh),
# which doubles as fresh-machine bootstrap: on a new box there's nothing to
# migrate, it just installs the same versions from the start.
#
# Idempotent: `pyenv install --skip-existing` no-ops any version already built.
# Best-effort per version — a single compile failure (missing build dep, flaky
# download) warns and continues instead of aborting the whole run.
#
# Called best-effort from installation.sh; also runnable standalone:
#     bash ~/dotfiles/scripts/install-pyenv.sh

set -euo pipefail

_self="$(readlink -f "${BASH_SOURCE[0]}")"
# exports.sh is written for interactive shells (references $ZSH_VERSION etc.
# unconditionally), so source it with -u off, then restore.
set +u; source "$(dirname "$_self")/exports.sh"; set -u
unset _self

# The version set to keep reproducible across machines. Latest patch per minor;
# the empty duplicate minors that had accumulated (3.12.4, 3.13.2) are dropped.
PYENV_VERSIONS=(3.10.14 3.11.9 3.12.9 3.13.9)
PYENV_GLOBAL=(3.13.9 3.12.9)   # matches the multi-version global in use today

# Ensure pyenv itself is present. macOS gets it from the Brewfile; if it's
# missing (Linux, or brew step skipped) clone it straight into $PYENV_ROOT so
# the binary lands at $PYENV_ROOT/bin/pyenv, exactly where settings.sh looks.
if ! command -v pyenv &>/dev/null && [ ! -x "$PYENV_ROOT/bin/pyenv" ]; then
    if [[ "$OSTYPE" == "darwin"* ]] && command -v brew &>/dev/null; then
        echo "pyenv not found; installing via Homebrew..."
        brew install pyenv
    else
        echo "pyenv not found; cloning into $PYENV_ROOT..."
        git clone --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
    fi
fi

# Put pyenv on PATH for this non-interactive run (settings.sh does the same for
# interactive shells) and initialise shims.
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - --no-rehash 2>/dev/null)" || true

for v in "${PYENV_VERSIONS[@]}"; do
    echo "pyenv: ensuring $v ..."
    pyenv install --skip-existing "$v" || echo "warn: failed to install $v (continuing)"
done

# Set the global(s) only if every requested version actually built — otherwise
# `pyenv global` would reject the whole list and leave you with no global.
_have_all=1
for v in "${PYENV_GLOBAL[@]}"; do
    [ -d "$PYENV_ROOT/versions/$v" ] || _have_all=0
done
if [ "$_have_all" -eq 1 ]; then
    pyenv global "${PYENV_GLOBAL[@]}"
    echo "pyenv: global set to ${PYENV_GLOBAL[*]}"
else
    echo "warn: not all global versions (${PYENV_GLOBAL[*]}) are present; leaving global unchanged"
fi

pyenv rehash 2>/dev/null || true
echo "install-pyenv: done. Versions at $PYENV_ROOT/versions:"
ls "$PYENV_ROOT/versions" 2>/dev/null || true
