#! /usr/bin/env bash
set -e

scriptPath=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# extra options for this script
options=$(cat <<EOM 
    --clean-resources  Recreate existing AWS resources
EOM
)

. "${scriptPath}/common.sh" "$@" "${options}"

. "${dockerConfigPath}/aws-config.env"
. "${configPath}/aws-services.env"

args="$@"
cleanExistingResources=false

if [[ "$@" == *"--clean-resources"* ]]; then
    cleanExistingResources=true
fi

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION

function createSqsSubscriptionToSnsTopicIfMissing() {
    sqsQueueName="$1"
    snsTopicName="$2"

    sqsQueueArn="arn:aws:sqs:elasticmq:000000000000:${sqsQueueName}"
    snsTopicArn="arn:aws:sns:${AWS_DEFAULT_REGION}:123456789012:${snsTopicName}"

    if echo "$(awslocal sns list-subscriptions)" | grep -q "${sqsQueueArn}"; then
        if [ "${cleanExistingResources}" = false ]; then
            logWarn "SNS subscription for queue '${sqsQueueName}' to topic '${snsTopicName}' already exists"
            return
        fi

        logWarn "Unsubscribing queue '${sqsQueueName}' from SNS topic: ${snsTopicName}"

        subscriptionArn=$(awslocal sns list-subscriptions-by-topic --topic-arn "${snsTopicArn}" | grep -A 2 "${sqsQueueArn}" | tail -n 1)
        subscriptionArn=${subscriptionArn/            \"TopicArn\": \"/}
        subscriptionArn=${subscriptionArn/\"\,/}

        echo "${subscriptionArn}"

        awslocal sns unsubscribe --subscription-arn "${subscriptionArn}"
    fi

    logInfo "Subscribing queue '${sqsQueueName}' to SNS topic: ${snsTopicName}"

    awslocal sns subscribe \
        --topic-arn "${snsTopicArn}" \
        --proto sqs \
        --notification-endpoint "${sqsQueueArn}"
}

function createSnsTopicIfMissing() {
    snsTopicName="$1"
    snsTopicArn="arn:aws:sns:eu-west-1:123456789012:${snsTopicName}"

    if echo "$(awslocal sns list-topics)" | grep -q "${snsTopicArn}"; then
        if [ "${cleanExistingResources}" = false ]; then
            logWarn "SNS topic already exists: ${bucketName}"
            return
        fi

        logWarn "Deleting SNS topic: ${snsTopicName}"
        awslocal sns delete-topic --topic-arn "${snsTopicArn}"
    fi

    logInfo "Creating SNS topic: ${snsTopicName}"
    
    awslocal sns create-topic --name "${snsTopicName}"
}

function createSqsQueueIfMissing() {
    sqsQueueName="$1"

    if echo "$(awslocal sqs list-queues)" | grep -q "${sqsQueueName}"; then
        if [ "${cleanExistingResources}" = false ]; then
            logWarn "SQS queue already exists: ${sqsQueueName}"
            return
        fi

        logWarn "Deleting SQS queue: ${sqsQueueName}"
        awslocal sqs delete-queue --queue-url "http://localhost:4576/queue/${sqsQueueName}"
    fi

    logInfo "Creating SQS queue: ${sqsQueueName}"

    awslocal sqs create-queue --queue-name "${sqsQueueName}"
}

function createSqsQueueAndDeadLettersQueueIfMissing() {
    sqsQueueName="$1"

    createSqsQueueIfMissing "${sqsQueueName}"
    createSqsQueueIfMissing "${sqsQueueName}-dead-letters"
}

function createS3BucketIfMissing() {
    bucketName="$1"

    if echo "$(awslocal s3api list-buckets)" | grep -q "${bucketName}"; then
        if [ "${cleanExistingResources}" = false ]; then
            logWarn "S3 bucket already exists: ${bucketName}"
            return
        fi

        logWarn "Deleting S3 bucket: ${bucketName}"
        awslocal s3 rm "s3://${bucket}/" --recursive --quiet
        awslocal s3api delete-bucket --bucket "${bucketName}"
    fi

    logInfo "Creating S3 bucket: ${bucketName}"

    awslocal s3api create-bucket --bucket "${bucketName}"

    bucketInfo=$(awslocal s3api list-buckets | grep -B 2 -A 1 "${bucketName}")

    # cleanup misaligned output
    bucketInfo=${bucketInfo/        \{/\{}
    bucketInfo=${bucketInfo/        \}/\}}
    bucketInfo=${bucketInfo//            /    }
    bucketInfo=${bucketInfo/\},/\}}

    echo "${bucketInfo}"
}

##
# Create AWS resources configured in `config/aws-services.env`.
##
function createAwsResources() {
    displayBanner "Create AWS Resources"

    displayHelpIfRequested "${args}"

    if [ "${cleanExistingResources}" = true ]; then
        logWarn "--clean-resources parameter passed, existing resources will be recreated"
    fi

    for bucket in ${s3Buckets//,/ }; do
        createS3BucketIfMissing "${bucket}"
    done

    for queue in ${sqsQueues//,/ }; do
        createSqsQueueAndDeadLettersQueueIfMissing "${queue}"
    done

    for topic in ${snsTopics//,/ }; do
        createSnsTopicIfMissing "${topic}"
    done

    # add subscriptions for SNS testing/debug SQS queues here 
    # createSqsSubscriptionToSnsTopicIfMissing "${snsTestingQueue}" "?"
    # createSqsSubscriptionToSnsTopicIfMissing "${snsDebugQueue}" "?"

    logInfo "✅ Done\n"
}

createAwsResources
