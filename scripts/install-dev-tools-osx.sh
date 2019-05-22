#! /usr/bin/env bash
scriptPath=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# extra options for this script
options=$(cat << EOM 
    --report           Output a report showing versions of current dev tools and exit
    --force            Do not ask for confirmation for each install/upgrade
EOM
)

. "${scriptPath}/common.sh" "$@" "${options}"

# prevent script exiting due to strange exit codes from homebrew
set +e

args="$@"

scopePath="/usr/local/bin/scope"
force=false
input=""

function brewPackageIsInstalled() {
    package="$1"

    if commandIsInstalled "brew" && brew list | grep -q "${package}"; then
        return 0
    else
        return 1
    fi
}

function getToolVersionIfPresent() {
    tool="$1"
    versionCommand="$2"

    if commandIsInstalled "${tool}"; then
        if [ -z "${versionCommand}" ]; then
            versionCommand="${tool} --version"
        fi

        eval "${versionCommand}"
    else
        echo "[Not Installed]"
    fi
}

function assertBrewPackageIsInstalled() {
    package="$1"

    assertCommandIsInstalled "brew"

    if ! brew list | grep -q "${package}"; then
        errorAndExit "$1 is required for this step" --useCallingFunc
    fi
}

##
# Ask a user to confirm an install or upgrade of a tool.
#
# The anwser is saved to the global `input` variable.
#
# This function accepts three forms:
#
#  askIfOkToProceed "nvm" -i         # install
#  askIfOkToProceed "nvm" -i "brew"  # install with a required tool
#  askIfOkToProceed "nvm" -u         # upgrade
#
# If `--force` was passed to this script no confirmation
# will be requested.
##
function askIfOkToProceed() {
    tool="$1"
    actionTypeFlag="$2"
    requiredTool="$3"

    if [ -n "${requiredTool}" ]; then
        # bold + underline the 'requires' message
        requiredTool=" (\e[1;4mrequires ${requiredTool}\e[24m\e[21m)"
    fi

    if [ "${force}" = true ]; then
        # don't ask, just log out action
        if [ "${actionTypeFlag}" == "-i" ]; then
            logInfo "Installing ${tool}" --useCallingFunc
        elif [ "${actionTypeFlag}" == "-u" ]; then
            logWarn "Upgrading ${tool}" --useCallingFunc
        else
            # bad actionTypeFlag, let below logic throw error
            break
        fi

        return
    fi

    # ask for confirmation of action
    if [ "${actionTypeFlag}" == "-i" ]; then
        logInfo "Install ${tool}?${requiredTool}" --useCallingFunc
    elif [ "${actionTypeFlag}" == "-u" ]; then
        logWarn "${tool} already installed, upgrade?" --useCallingFunc
    else
        errorAndExit "askIfOkToProceed requires the second parameter to be either -i or -u"
    fi

    read -p "[Y/n]: " input
}

##
# Inspect input from user to check it's ok to proceed.
#
# If input was received and it was anything other than 'n' return 0.
# If input was received and it equals 'n' return 1.
#   
#  (matches are case-insensitive) 
#
# If `--force` was passed it will always return 0.
##
function okToProceed() {
    if [ "${force}" = true ]; then
        return 0
    fi

    if [ "$(echo "${input}" | tr "[:upper:]" "[:lower:]")" == "n" ]; then
        return 1
    else
        return 0
    fi
}

##
# Brew package installer.
#
# This function has three forms:
#
#   installOrUpdateHomebrewPackage "nvm"                             # install package
#   installOrUpdateHomebrewPackage "nvm" "--verbose"                 # install package, passing arguments to brew
#   installOrUpdateHomebrewPackage "nvm" "--verbose" "callbackFunc"  # install package, passing arguments to brew and call 'callbackFunc' if the package was installed or is up to date
#
##
function installOrUpdateHomebrewPackage() {
    package="$1"
    opts="$2"
    installCallback="$3"

    askIfOkToProceed "${package}" -i "brew"

    if ! okToProceed; then
        return
    fi

    assertCommandIsInstalled "brew"

    if ! brewPackageIsInstalled "${package}"; then
        brew install "${package}" ${opts}
    else 
        if brew outdated | grep -q "${package}"; then
            askIfOkToProceed "${package}" -u

            if ! okToProceed; then
                break
            fi

            brew upgrade "${package}"
        else
            logInfo "${package} already installed & up to date" --useCallingFunc
        fi
    fi 

    if [ -n "${installCallback}" ]; then
        "${installCallback}"
    fi
}

function displayVersionReport() {
    # prevent using proxy function defined in `common.sh`
    pipenvPath=$(getToolVersionIfPresent "pipenv" 'echo $(brew --prefix pipenv)/bin/pipenv')
    pipenvVersion="[Not Installed]"

    # get raw version output for editing
    dockerVersion=$(getToolVersionIfPresent "docker")
    homebrewVersion=$(getToolVersionIfPresent "brew" 'printf "$(brew --version)" | head -n 1')
    scopeVersion=$(getToolVersionIfPresent "scope" "scope version")

    # clean up version outputs to be more sucinict
    if [ "${dockerVersion}" != "[Not Installed]" ]; then
        dockerVersion=${dockerVersion/Docker version /}
    fi

    if [ "${homebrewVersion}" != "[Not Installed]" ]; then
        homebrewVersion=${homebrewVersion/Homebrew /}
    fi 

    if [ "${pipenvPath}" != "[Not Installed]" ] && [ -x "${pipenvPath}" ]; then
        pipenvVersion=$("${pipenvPath}" --version)
        pipenvVersion=${pipenvVersion/pipenv, version /}
    fi

    if [ "${scopeVersion}" != "[Not Installed]" ]; then
        scopeVersion=${scopeVersion/Weave Scope version /}
    fi

    cat <<EOM

Tool Versions:

    docker........${dockerVersion}
    homebrew......${homebrewVersion}
    pipenv........${pipenvVersion}
    scope.........${scopeVersion}

EOM
}

function installScope() {
    askIfOkToProceed  "scope" -i

    if ! okToProceed; then
        return
    fi

    if [ ! -x "${scopePath}" ]; then
        logInfo "Installing scope"
    else
        askIfOkToProceed  "scope" -u

        if ! okToProceed; then
            return
        fi
    fi

    logWarn "scope install script may request sudo permission"

    sudo curl -s -L "git.io/scope" -o "${scopePath}"
    sudo chmod a+x "${scopePath}"
}

function installPipenv() {
    installOrUpdateHomebrewPackage "pipenv"
}

function installHomebrew() {
    askIfOkToProceed "Homebrew" -i

    if ! okToProceed; then
        return
    fi

    if [ ! -x $(command -v brew) ]; then
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    else
        askIfOkToProceed "Homebrew" -u

        if ! okToProceed; then
            return
        fi
    fi

    brew update
}

function checkForDocker() {
    if [ ! -f "$(command -v docker)" ]; then
        logWarn "Docker for Mac was not found, please install it from https://docs.docker.com/docker-for-mac/release-notes/"
    fi
}

function assertXcodeIsInstalled() {
    xcodeVersion=$(getToolVersionIfPresent "xcodebuild" "xcodebuild -version")

    if [ "${xcodeVersion}" == "[Not Installed]" ]; then
        errorAndExit "Unable to find Xcode, please install it from the App Store"
    fi

    logDebug "$(echo "${xcodeVersion}" | head -n 1) is installed"
}

function processCommandLineOptions() {
    displayHelpIfRequested "${args}"

    if [[ "${args}" == *"--report"* ]]; then
        logInfo "Dev tools version report"

        displayVersionReport
        exit 0
    fi

    if [[ "${args}" == *"--force"* ]]; then
        force=true
    fi
}

function installDevTools() {
    displayBanner "Serverless OSX Dev Tools Installer"

    processCommandLineOptions

    logWarn "Pre-install version report"
    displayVersionReport

    assertXcodeIsInstalled
    checkForDocker

    # package managers
    installHomebrew
    installPipenv

    # tools
    installScope

    displayBanner "Install Complete"

    displayVersionReport

    logInfo "✅ Done\n"
}

installDevTools
