
# [nvm-auto-switch]
#
# Enables auto-switching node version when a .nvmrc
# file is in the current working directory.
autoload -U add-zsh-hook

nvm-check() {
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

add-zsh-hook chpwd nvm-check

# ensure node version is correct on shell init
nvm-check
