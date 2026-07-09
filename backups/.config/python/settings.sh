
# PYENV_ROOT is set in exports.sh (XDG data dir); fall back to the conventional
# path if this file is ever sourced standalone.
: "${PYENV_ROOT:=${XDG_DATA_HOME:-$HOME/.local/share}/pyenv}"
if [ -d "$PYENV_ROOT" ]; then
    export PATH="$PYENV_ROOT/bin:$PATH"
    # `pyenv init -` forks bash + sources completions + runs `pyenv rehash`
    # on every shell start (~500ms). Cache the generated script and skip
    # rehash (only needed after installing a new version/package script —
    # run `pyenv rehash` by hand then). Mirrors the compinit 24h cache below.
    # ponytail: mtime cache, drop it if pyenv ever gets a native fast init.
    _pyenv_cache="${XDG_CACHE_HOME:-$HOME/.cache}/pyenv-init.zsh"
    () {
        setopt local_options extended_glob
        if [[ ! -s $_pyenv_cache || -z $_pyenv_cache(#qN.mh-24) ]]; then
            pyenv init - --no-rehash > $_pyenv_cache
        fi
    }
    source $_pyenv_cache
    unset _pyenv_cache
fi


# Fix uv autocomplete with run python.py

function py() {
    uv run $1
}