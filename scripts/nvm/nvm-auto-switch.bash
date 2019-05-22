
# [nvm-auto-switch]
#
# Enables auto-switching node version when a .nvmrc
# file is in the current working directory.
cd() {
    builtin cd "$@" || return

    if [ -f ".nvmrc" ] && [ -s ".nvmrc" ]; then
        # .nvmrc is present and not empty
        if type nvm &> /dev/null; then
            # nvm is present
            if [ "$(nvm current)" != "v$(<.nvmrc)" ]; then
                # current version of node is different from .nvmrc
                nvm use
            fi
        fi
    fi
}

# ensure node version is correct on shell init
cd "$(pwd)"
