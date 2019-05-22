#! /usr/bin/env sh
set -e

firstChangedMappingFilePath="$1"

##
# Get the mock name using the name of the root directory in the mapping path.
##
function getMockServerNameFromPath() {
    echo "$1" | cut -d "/" -f 1
}

##
# Call the WireMock admin API reset endpoint to force it to
# reload mappings from disk. (one of which has just changed!)
#
# This script will be invoked by watchman when mapping file(s)
# are changed.
##
function reloadMockMappings() {
    mockServerName=$(getMockServerNameFromPath "${firstChangedMappingFilePath}")

    echo "Reloading ${mockServerName} mock mappings..."

    curl -vvvv -X POST "http://${mockServerName}:8080/__admin/mappings/reset"
}

reloadMockMappings
