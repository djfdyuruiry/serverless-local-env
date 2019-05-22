#! /usr/bin/env bash
set -e

scriptPath=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# extra options for this script
options=$(cat <<EOM 
    --function         Name of the Lambda Function to get logs for
    --tail             Only output log messages written this number of seconds before this script was invoked (default is 60s)
    --watch            Watch the log output from the Lambda Function (can be combined with tail)
EOM
)

. "${scriptPath}/common.sh" "$@" "${options}"

functionNameRegex="^.*--function ([a-zA-Z0-9_-]+[a-zA-Z0-9\_]+).*$"
tailTimeRegex="^.*--tail ([0-9]+).*$"

args="$@"
functionName=""
noColour=false
watchLogs=false
tailLogs=false
logStartTime=0

if [[ "${args}" == *"--no-colour"* ]]; then
    noColour=true
fi

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

##
# Retrieve Cloudwatch events for a Lambda Function log stream.
#
# Log messages are extracted from AWS cli JSON output using a 
# python script and written to standard out.
#
# If `tailLogs` is true this function will only get the events
# since  
##
function getFunctionLogs() {
    filterArgs=""

    if [ "${tailLogs}" = true ]; then
        filterArgs="--start-time ${logStartTime}"
    fi

    awslocal logs filter-log-events --log-group-name "/aws/lambda/${functionName}" ${filterArgs} | \
        python -c "$(cat <<EOM
from json import load as parseJson
from sys import stdin

logEvents = parseJson(stdin)['events']

print "\n".join(
    map(
        lambda e: e['message'], 
        logEvents
    )
)
EOM
)"
}

function parseParameters() {
    if [[ "${args}" != *"--function"* ]]; then
        errorAndExit "--function parameter is required"
    fi

    if [[ "${args}" =~ ${functionNameRegex} ]]; then
        functionName="${BASH_REMATCH[1]}"
    fi

    if [ -z "${functionName}" ]; then
        errorAndExit "Invalid value for the --function parameter"
    fi

    if [[ "${args}" == *"--watch"* ]]; then
        watchLogs=true
    fi

    if [[ "${args}" == *"--tail"* ]]; then
        tailLogs=true
        tailSeconds=60

        if [[ "${args}" =~ ${tailTimeRegex} ]]; then
            tailSeconds="${BASH_REMATCH[1]}"
        fi

        tailMillis="${tailSeconds}000"
        logStartTime=$(($(date +%s000) - ${tailMillis}))
    fi
}

##
# Fetch the logs for an Lambda Function from Cloudwatch
##
function getLambdaLogs() {      
    displayHelpIfRequested "${args}"

    parseParameters

    if [ "${watchLogs}" = true ]; then
        export -f awslocal
        export -f getFunctionLogs

        export functionName
        export tailLogs
        export logStartTime

        if [ "${noColour}" = true ]; then
            watch --interval 0.5 getFunctionLogs
        else
            watch --color --interval 0.5 getFunctionLogs
        fi
    else
        getFunctionLogs
    fi
}

getLambdaLogs "$@"
