This directory contains scripts that are ran by the `mock_watcher` service.

`watch-mocks.sh` - The entrypoint for the `mock_watcher` service that monitors JSON mapping files under `serverless-env/mocks` for changes using watchman.

`reaload-mock-mappings.sh` - Triggers the WireMock server hosting a given mapping to reload it's mappings from disk. Called by watchman on mapping file change.

See: https://facebook.github.io/watchman/
