#! /usr/bin/env bash
set -e

scriptPath=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# extra options for this script
options=$(cat <<EOM 
    --clean-functions  Redeploy existing lambda functions
    --function         Deploy a specific lambda function only
EOM
)

. "${scriptPath}/common.sh" "$@" "${options}"

. "${configPath}/lambda-functions.env"
. "${dockerConfigPath}/aws-config.env"

customBuildScript="build-docker.sh"
functionNameRegex="^.*--function ([a-zA-Z0-9_-]+[a-zA-Z0-9\_]+).*$"
lambdaAlbConfigPath="${dockerConfigPath}/lambda-alb/config.json"
lambdaLoggerConfigPath="${dockerConfigPath}/lambda-logger/config.env"
lambdaEndpoint="http://aws:4574"
cloudwatchLogsEndpoint="http://aws:4586"

args="$@"
functionToDeploy=""
lambdaFunctionNames=()

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

function configureLambdaLogger() {
    logInfo "Generating lambda-logger configuration file: ${lambdaLoggerConfigPath}"

    echo "cloudwatchUrl='${cloudwatchLogsEndpoint}'" > "${lambdaLoggerConfigPath}"
    echo "lambdaNames='$(printf '%s ' "${lambdaFunctionNames[@]}")'" >> "${lambdaLoggerConfigPath}"

    logInfo "lambda-logger configuration:"
    cat "${lambdaLoggerConfigPath}"

    logInfo "Restarting lambda-logger container to update config"

    docker-compose stop lambda_logger
    docker-compose up -d lambda_logger
}

##
# Generate JSON configuration file `serverless-env/config/lambda-alb/config.json`
# with the names of lambda functions so they can be accessed using the 
# `alb` service url.
##
function configureLambdaAlb() {
    logInfo "Generating lambda-alb configuration file: ${lambdaAlbConfigPath}"

    targetsJson=""

    for lambdaFunctionName in "${lambdaFunctionNames[@]}"; do
        # for each lambda, generate a json config entry
        targetsJson=$(cat <<EOM
${targetsJson}
        "${lambdaFunctionName}": { 
            "lambdaName": "${lambdaFunctionName}" 
        },
EOM
)
    done

    # cleanup trailing comma
    targetsJson="${targetsJson/%\,/}"

    # populate config template
    albConfigJson=$(cat <<EOM
{
    "lambdaEndpoint": "${lambdaEndpoint}",
    "region": "${AWS_DEFAULT_REGION}",
    "targets": { ${targetsJson}
    }
}
EOM
)

    echo "${albConfigJson}" > "${lambdaAlbConfigPath}"

    logInfo "lambda-alb configuration:"
    cat "${lambdaAlbConfigPath}"

    logInfo "Restarting ALB container to update config"

    docker-compose stop alb
    docker-compose up -d alb
}

function downloadLambdaPackageToTempDir() {
    tempDir=$(mktemp -d)
    pushd "${tempDir}" > /dev/null

    logInfo "Downloading Lambda package from URL: ${packageUrl}"

    wget --trust-server-names "${packageUrl}"

    packageUrl=$(realpath *.zip)

    popd > /dev/null
}

##
# Deploys an AWS Lambda Function package.
#
# If the `packageUrl` is a HTTP(S) URL, the package will be downloaded to a temp folder.
##
deployLambdaPackage() {
    functionVariable="$1"
    functionDefinition="${!functionVariable}"

    # evaluate the function definition to load parameters as bash variables
    eval "${functionDefinition}"

    # capture the lambda name so we can use it in `configureLambdaAlb` later
    lambdaFunctionNames+=("${name}")

    if [ -n "${functionToDeploy}" ] && [[ "${name}" !=  "${functionToDeploy}" ]]; then
        return
    fi

    if echo "$(awslocal lambda list-functions)" | grep -q "${name}"; then
        if [[ "${args}" != *"--clean-functions"* ]]; then
            logWarn "Lambda function '${name}' already exists"
            return
        fi

        logWarn "Deleting Lambda function: ${name}"
        awslocal lambda delete-function --function-name "${name}"
    fi

    logInfo "Deploying Lambda function: ${name}"

    if [[ "${packageUrl}" == "http"* ]]; then
        downloadLambdaPackageToTempDir "${packageUrl}"
    fi
    
    awslocal lambda create-function \
        --function-name "${name}" \
        --runtime "${runtime}" \
        --role "mock-role" \
        --handler "${handler}" \
        --zip-file "fileb://${packageUrl}"
}

##
# Deploy lambda functions using definitions found in `config/lambda-functions.env`.
#
# Any global variable with the prefix `lambda_` is considered to be a lambda definition.
##
function deployLambdaFunctions() {
    displayBanner "Deploy Lambda Functions"        

    displayHelpIfRequested "${args}"

    if [[ "${args}" == *"--clean-functions"* ]]; then
        logWarn "--clean-functions parameter passed, existing functions will be redeployed"
    fi

    # `lambdaFunctions` will contain all global variables with the prefix `image_`
    eval 'lambdaFunctions=(${!'"lambda_"'@})'

    listOfFunctions="${lambdaFunctions[*]}"
    listOfFunctions="${listOfFunctions//lambda_/}"
    listOfFunctions="${listOfFunctions// /, }"

    logInfo "Lambda Functions: ${listOfFunctions}"

    if [[ "${args}" =~ ${functionNameRegex} ]]; then
        functionToDeploy="${BASH_REMATCH[1]}"

        logWarn "--function parameter passed: ${functionToDeploy}"
    fi  

    for lambdaFunction in "${lambdaFunctions[@]}"; do
        deployLambdaPackage "${lambdaFunction}"
    done

    configureLambdaAlb
    configureLambdaLogger

    logInfo "✅ Done\n"
}

deployLambdaFunctions
