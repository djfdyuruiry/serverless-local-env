#! /usr/bin/env sh
set -e

. "/etc/serverless/config.env"

logDir="/var/log/serverless"
lastEventTimestamp=$(($(date +%s000) - 1))

##
# Use the AWS CLI to get all log events for a given log
# group, starting from a given time.
#
# Python is used to sort the events by time ascending and
# extract each log event as a discreet line.
##
function getCloudwatchLogEvents() {
    logGroupName="$1"
    startTime="$2"

    aws logs filter-log-events \
        --log-group-name "${logGroupName}" \
        --max-items 100000 \
        --start-time ${startTime} \
        --endpoint-url "${cloudwatchUrl}" | \
        python -c "$(cat <<EOM
from json import load as parseJson
from re import compile as regex
from sys import stdin

logEvents = parseJson(stdin)['events']
ansiEscapeRegex = regex(r'(\x9B|\x1B\[)[0-?]*[ -\/]*[@-~]')

# emit the most recent timestamp returned in log events
if logEvents:
    print max(e['timestamp'] for e in logEvents)

# Get each message, remove any ansi esc sequences then sort messages by timestamp
# and print each message on it's own line.
print "\n".join(
    map(
        lambda e: ansiEscapeRegex.sub('', e['message']), 
        sorted(logEvents, key = lambda e: e['timestamp'])
    )
)
EOM
)"
}

###
# Get all log lines emitted by a given lambda function since a given time. 
##
function getLambdaLogs() {
    functionName="$1"
    startTime="$2"
    logGroupName="/aws/lambda/${functionName}"

    if ! aws logs describe-log-groups --endpoint-url "${cloudwatchUrl}" | grep -q "${logGroupName}"; then
        # log group doesn't exist, usually means that this function has never been invoked
        return
    fi

    getCloudwatchLogEvents "${logGroupName}" "${startTime}"
}

##
# Fetch the next set of logs for a given lambda function.
##
function fetchNextSetLambdaFunctionLogs() {
    functionName="$1"
    logFile="${logDir}/${functionName}.log"
    logTime=$((${lastEventTimestamp} + 1))

    # get logs from cloudwatch
    logs=$(getLambdaLogs "${functionName}" "${logTime}")

    if [ -n "${logs}" ]; then
        # get the most recent event timestamp from output
        lastEventTimestamp=$(echo "${logs}" | head -n 1)

        # output new log lines to file
        echo "${logs}" | tail -n +2 >> "${logFile}"
    fi

    lastLogTime="${logTime}"
}

##
# Use the Cloudwatch Logs API, via the AWS CLI, to poll log
# events in AWS Lambda log groups. The logs are streamed to
# a plain log file in the `logDir` directory, in the format
# `<lambda-name>.log`.
#
# Only log events from the script start time onward will be 
# logged out.
##
function monitorLambdaLogs() {
    lambdaFunctions=$(echo "${lambdaNames}" | tr " " "\n")

    while :; do
        for function in ${lambdaFunctions}; do
            fetchNextSetLambdaFunctionLogs "${function}"
        done

        sleep 1
    done
}

monitorLambdaLogs
