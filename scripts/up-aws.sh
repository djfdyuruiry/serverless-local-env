#! /usr/bin/env bash
set -e

scriptPath=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# extra options for this script
options=$(cat <<EOM 
    --clean-aws        Clear down localstack volume and container (implies --clean-resources and --clean-functions)
    --clean-resources  Recreate existing AWS resources
    --clean-functions  Redeploy existing lambda functions
    --function         Deploy a specific lambda function only
EOM
)

. "${scriptPath}/common.sh" "$@" "${options}"

args="$@"

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

function deployLambda() {
    logInfo "Deploying AWS Lambda Functions"

    "${scriptsPath}/deploy-lambda-functions.sh" "${args}"
}

function configureAwsServices() {
    logInfo "Configuring AWS Services"

    "${scriptsPath}/create-aws-resources.sh" "${args}"
}

function waitForLocalstackToBeReady() {
    if [[ "$(docker-compose logs aws)" == *"Ready."* ]]; then
        # localstack is already up and ready
        return
    fi

    logInfo "⏲  - Waiting for localstack to come online"

    until [[ "$(docker-compose logs aws)" == *"Ready."* ]]; do
        # wait for the magical `Ready.` line from localstack
        printf "……"
        sleep 1
    done

    echo "⏰"
    logInfo "👍  - Localstack is online"
}

function clearDownAws() {
    logInfo "❗Destroying existing localstack container (if running)"

    docker-compose rm -f -s aws

    if [ -d "${volumesPath}/localstack" ]; then
        echo "❗Cleaning localstack volume, this may request sudo permission"
        sudo rm -rf "${volumesPath}/localstack"
    fi
}

##
# Create AWS services.
#
# If `--clean-aws` is passed to this script, the localstack container and
# volume directory will be cleared down if present.
##
function up-aws() {
    displayBanner "Up AWS Services"

    displayHelpIfRequested "${args}"

    if [[ "${args}" == *"--clean-aws"* ]]; then
        clearDownAws
    fi

    logInfo "Pausing Environment"

    docker-compose down

    logInfo "Ensuring localstack container is started"

    docker-compose up -d aws

    waitForLocalstackToBeReady

    configureAwsServices
    deployLambda

    logInfo "Resuming Environment"

    docker-compose up -d

    logInfo "✅ Done\n"
}

up-aws
