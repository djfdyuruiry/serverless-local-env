#! /usr/bin/env bash
set -e

scriptPath=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# extra options for this script
options=$(cat <<EOM 
    --clean-images     Rebuild custom images
    --image            Build a specific image only
EOM
)

. "${scriptPath}/common.sh" "$@" "${options}"

. "${configPath}/custom-images.env"

customBuildScript="build-docker.sh"
imageNameRegex="^.*--image ([a-zA-Z0-9_-]+[a-zA-Z0-9\_]+).*$"

args="$@"
imageToBuild=""

##
# Checks out a GIT repo and builds a docker image from source.
#
# If the ${customBuildScript} file is found, it will be invoked, otherwise
# the Dockerfile will be built using the docker command.
#
# This function has two forms:
#
#   buildImageFromGitRepo "image-name" "some-git-ssh-or-http(s)-url"                        # build 'image-name' image from the repo @ url (master branch)
#   buildImageFromGitRepo "image-name" "some-git-ssh-or-http(s)-url" "feature/some-branch"  # the above, but check out a custom repo branch
#
##
buildImageFromGitRepo() {
    name="$1"
    repoUrl="$2"
    branch="${3:-master}"

    logInfo "Building image '${name}' from branch '${branch}' in repo @ ${repoUrl}"

    # checkout repo to temp dir
    tempDir=$(mktemp -d)
    pushd "${tempDir}" > /dev/null

    git clone "${repoUrl}" "$(pwd)"
    git checkout "${branch}"

    if [ ! -f "Dockerfile" ]; then
        errorAndExit "No Dockerfile found, files: $(ls)"
    fi

    if [ ! -f "${customBuildScript}" ]; then
        docker build --tag "${name}" .
    else
        logInfo "Running custom docker build script: ${customBuildScript}"

        "./${customBuildScript}"
    fi

    revision=$(git rev-parse --short HEAD)

    popd

    logInfo "Docker image '${name}' installed from revision ${revision}"
}

##
# Builds a docker image using the provided image definition stored in
# a global bash variable. The name of this variable is the only argument
# to this function. If a docker image with the provided name exists, the
# build is skipped. 
#
# See `config/custom-images.env` for info on image definition format.
#
# If `--clean-images` is passed to this script, the image will be destroyed and
# rebuilt.
##
function buildImage() {
    imageVariable="$1"
    imageDefinition="${!imageVariable}"

    # evaluate the image definition to load parameters as bash variables
    eval "${imageDefinition}"

    if [ -n "${imageToBuild}" ] && [[ "${name}" !=  "${imageToBuild}" ]]; then
        return
    fi

    if [ -n "$(docker images -q ${name})" ]; then
        created=$(docker images ${name} --format "{{.CreatedSince}}")

        if [[ "${args}" == *"--clean-images"* ]]; then
            logInfo "Cleaning image '${name}', installed (${created})"

            deleteDockerContainersByImageName "${name}"
            docker image rm -f "${name}"
        else
            logWarn "Docker image '${name}' already installed (${created}), skipping build"
            return
        fi
    fi

    buildImageFromGitRepo "${name}" "${repoUrl}" "${branch}"
}

##
# Build custom images using definitions found in `config/custom-images.env`.
#
# Any global variable with the prefix `image_` is considered to be an image definition.
##
function buildCustomImages() {
    displayBanner "Build Custom Docker Images"        

    displayHelpIfRequested "${args}"

    if [[ "${args}" == *"--clean-images"* ]]; then
        logWarn "--clean-images parameter passed, existing custom images will be rebuilt"
    fi

    # `customImages` will contain all global variables with the prefix `image_`
    eval 'customImages=(${!'"image_"'@})'

    listOfImages="${customImages[*]}"
    listOfImages="${listOfImages//image_/}"
    listOfImages="${listOfImages// /, }"

    logInfo "Custom images: ${listOfImages}"

    if [[ "${args}" =~ ${imageNameRegex} ]]; then
        imageToBuild="${BASH_REMATCH[1]}"

        logWarn "--image parameter passed: ${imageToBuild}"
    fi  

    for customImage in "${customImages[@]}"; do
        buildImage "${customImage}"
    done

    logInfo "✅ Done\n"
}

buildCustomImages
