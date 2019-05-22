#! /usr/bin/env sh
set -e

##
# Follow the watchman log (this also prevents the container from exiting).
##
function tailWatchmanLogfile() {
    tail -f /usr/local/var/run/watchman/root-state/log
}

##
# Watch for any mapping changes, on change `reset-mock-server.sh` is
# called with the paths to any changed mappings as the arguments.
##
function startWatchingMappings() {
    echo "Starting watchman..."

    watchman -j <<-EOT
[
    "trigger",
    "/etc/serverless/mocks", {
        "name": "mapping-changed",
        "command": [
            "/opt/serverless/scripts/reload-mock-mappings.sh"
        ],
        "append_files": true
    }
]
EOT
}

##
# We use curl in `reset-mock-server.sh`, but it is not intalled
# by default on Alpine linux, install it if missing.
##
function installCurlIfMissing() {
    if [ -x "$(command -v curl)" ]; then
        return
    fi

    echo "Installing curl..."

    apk add curl &> /tmp/apk_add_curl.log || {
        echo "Error installing curl:"
        cat apk_add_curl.log

        exit 1
    }

    echo "Curl installed successfully"
}

##
# Entrypoint for the mock_watcher service.
##
watchMocks() {
    installCurlIfMissing
    startWatchingMappings
    tailWatchmanLogfile
}

watchMocks
