#! /usr/bin/env bash
set -e

# polyfill for realpath command using python
command -v realpath &> /dev/null || realpath() {
    python -c "import os; print os.path.abspath('$1')"
}

scriptsPath=$(realpath "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")

rootPath=$(realpath "${scriptsPath}/..")
configPath="${rootPath}/config"
dockerPath="${rootPath}/serverless-env"
dockerConfigPath="${dockerPath}/config"
volumesPath="${dockerPath}/.volumes"
mocksPath="${dockerPath}/mocks"
pipenvLogPath="${rootPath}/pipenv.log"

pipenvBinPath=$(command -v pipenv || "")
noColour=false
extraOptions="$2"

if [[ "$@" == *"--no-colour"* ]]; then
    noColour=true
fi

function commandIsInstalled() {
    command="$1"

    if [ -z "$(command -v "${command}")" ]; then
        return 1
    else
        return 0
    fi
}

function assertCommandIsInstalled() {
    command="$1"

    if ! commandIsInstalled "${command}"; then
        errorAndExit "${command} was not found, it is required to run this command" --useCallingFunc
    fi
}

function log() {
    level="$1"
    message="$2"
    useCallingFunc="$3"
    source="${FUNCNAME[1]}"

    if [[ "${useCallingFunc}" == "--useCallingFunc" ]] && [[ "${source}" == log* ]]; then
        # being called by another log function and asked to use calling func, get real source
        source="${FUNCNAME[3]}"
    elif [[ "${useCallingFunc}" == "--useCallingFunc" ]] || [[ "${source}" == log* ]]; then
        # being called by another log function or asked to use calling func, get real source
        source="${FUNCNAME[2]}"
    fi

    # e.x.: 23-05-2019 20:39:28 INFO  [someFunctionName] A very important message
    echo "$(date '+%d-%m-%Y %T') ${level} [${source}] ${message}"
}

function logTrace() {
    message="$1"
    useCallingFunc="$2"

    if [ "${noColour}" = true ]; then
        log TRACE "${message}" "${useCallingFunc}"
    else
        # output dark grey
        printf "\e[90m$(log TRACE "${message}" "${useCallingFunc}")\e[0m\n"
    fi
}

function logDebug() {
    message="$1"
    useCallingFunc="$2"

    if [ "${noColour}" = true ]; then
        log DEBUG "${message}" "${useCallingFunc}"
    else
        # output blue
        printf "\e[94m$(log DEBUG "${message}" "${useCallingFunc}")\e[0m\n"
    fi
}

function logInfo() {
    message="$1"
    useCallingFunc="$2"

    if [ "${noColour}" = true ]; then
        log INFO "${message}" "${useCallingFunc}"
    else
        # output cyan
        printf "\e[36m$(log "INFO " "${message}" "${useCallingFunc}")\e[0m\n"
    fi
}

function logWarn() {
    message="$1"
    useCallingFunc="$2"

    if [ "${noColour}" = true ]; then
        log WARN "${message}" "${useCallingFunc}"
    else
        # output yellow
        >&2 printf "\e[93m$(log "WARN " "${message}" "${useCallingFunc}")\e[0m\n"
    fi
}

function logError() {
    message="$1"
    useCallingFunc="$2"

    if [ "${noColour}" = true ]; then
        log ERROR "${message}" "${useCallingFunc}"
    else
        # output red
        >&2 printf "\e[91m$(log ERROR "${message}" "${useCallingFunc}")\e[0m\n"
    fi
}

function logFatal() {
    message="$1"
    useCallingFunc="$2"

    if [ "${noColour}" = true ]; then
        log FATAL "${message}" "${useCallingFunc}"
    else
        # output red
        >&2 printf "\e[31m$(log FATAL "${message}" "${useCallingFunc}")\e[0m\n"
    fi
}

function errorAndExit() {
    message="$1"
    useCallingFunc="$2"
    exitCode="${3:-1}"

    logFatal "${message}" "${useCallingFunc}"
    exit ${exitCode}
}

##
# Proxy to pipenv which ensures we have all dependencies installed
# before calling pipenv for the first time.
##
function pipenv() {
    if [ -z "${pipenvBinPath}" ]; then
        errorAndExit "Unable to find pipenv in path"
    fi

    "${pipenvBinPath}" --venv &> /dev/null || {
        # no venv created yet, attempt to create one (first time install)
        rm -f "${pipenvLogPath}"

        "${pipenvBinPath}" install -d &> "${pipenvLogPath}" || {
            errorAndExit "Error installing Pipfile:\n$(<${pipenvLogPath})"
        }
    }

    "${pipenvBinPath}" "$@"
}

##
# Proxy docker-compose calls to pipenv package.
##
function docker-compose() {
    pushd "${dockerPath}" > /dev/null

    if [ "${noColour}" = true ]; then
        pipenv run docker-compose --no-ansi "$@"
    else
        pipenv run docker-compose "$@"
    fi

    popd > /dev/null
}

##
# Proxy awslocal calls to pipenv package.
##
function awslocal() {
    pipenv run awslocal "$@"
}

function deleteDockerContainersByImageName() {
    assertCommandIsInstalled "docker"

    imageName="$1"
    containers=$(docker ps -a -q --filter ancestor="$imageName" --format="{{.ID}}")

    if [ -z "${containers}" ]; then
        # no containers found, nothing to do
        return
    fi

    logInfo "Clearing down containers for image '${imageName}': ${containers}"
    docker rm -f ${containers}
}

function clearDownLambdaContainers() {
    deleteDockerContainersByImageName "lambci/lambda:nodejs8.10"
}

##
# Heart of the whole operation. Without it, we would be nothing.
##
function displayLogo() {
    cat "${scriptsPath}/logo.txt"
}

##
# Print an awesome banner message with a box border.
##
function displayBanner() {
    message="║   ⚙  $1   ║"
    messageLength=$((${#message} - 2))
    charPlaceholders=$(eval echo -n "{1..${messageLength}}")
    border=$(printf '═%.0s' ${charPlaceholders})
    space=$(printf ' %.0s' ${charPlaceholders})

    echo
    echo "╔${border}╗"
    echo "║${space}║"
    echo "${message}"
    echo "║${space}║"
    echo "╚${border}╝"
    echo
}

##
# Print help for a script, `extraOptions` is appended to global options.
##
function printUsageAndExit() {
    cat <<EOM
Usage: $0 [OPTIONS]

Options:
${extraOptions}
    --no-colour        Disable coloured output
    --help             Show this information

EOM
    exit 1
}

function displayHelpIfRequested() {
    scriptArgs="$1"

    if [[ "${scriptArgs}" == *"--help"* ]]; then
        printUsageAndExit
    fi
}
