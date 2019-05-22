#! /usr/bin/env bash
set -e

scriptPath=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# extra options for this script
options=$(cat <<EOM 
    --clean-env        Clear down lambdas, docker containers and volumes
EOM
)

. "${scriptPath}/common.sh" "$@" "${options}"

args="$@"

##
# Clear down lambda containers, docker-compose environment and
# container volumes (if any).
##
function clearDownEnv() {
    logWarn "❗Tearing down any running lambda's or docker services"

    clearDownLambdaContainers
    docker-compose down --remove-orphans

    if [ -d "${volumesPath}" ]; then
        logWarn "❗Cleaning volumes, this may request sudo permission"
        sudo rm -rf "${volumesPath}"
    fi
}

##
# Spin up local serverless environment.
#
# If `--clean-env` is passed to this script, clearDownEnv will be called.
##
function up-env() {
    displayBanner "Up Environment"

    displayHelpIfRequested "${args}"

    if [[ "${args}" == *"--clean-env"* ]]; then
        clearDownEnv
    fi

    "${scriptsPath}/up-aws.sh" "${args}"
    
    logInfo "Starting docker services"

    docker-compose up -d

    echo ""
    logInfo "✨✨ serverless local environment is now running ✨✨"
    logDebug "Please be patient, on first start it will take a minute or two for all services to fully boot\n"

    logInfo "✅ Done\n"
}

up-env
