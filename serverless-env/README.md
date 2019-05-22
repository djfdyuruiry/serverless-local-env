# Serverless Docker Environment

This directory holds a serverless docker environment, managed by docker-compose.

- [Directory Structure](#dirs)
- [Network](#network)
- [Service URLs](#urls)
- [AWS Services](#aws)
- [WireMock Admin API](#admin)

## <a id="dirs"></a>Directory Structure

- `.volumes`: container data for docker services
    - `.volumes/logs`: central location for all application log files
- `config`: service configuration files and environment variables stored as `.env` files
- `mocks`: WireMock stub mappings that can mock services (these are monitored by the `mock_watcher` service and will be auto reloaded when changes are detected)
- `scripts`: scripts used by different services on startup (create databases, users, etc.)

See the `docker-compose.yml` file for more documentation on the services.

----

## <a id="network"></a>Network

All containers in this docker environment all reside on the docker network `serverless-env_default`. This name is based on the name of the directory that contains the `docker-compose.yml` file.

If you want to connect an external container to this network, use the `--network` flag in docker run:

```bash
# check an api status using curl
docker run --rm -it --network serverless-env_default byrnedo/alpine-curl http://api:5555/api/v1/status
```

----

## <a id="urls"></a>Service URLs

Below is a list of the services in the local environment and the ports they run on:

| Service              | External Url           | Internal Url         | Notes                                                   |
|----------------------|------------------------|----------------------|---------------------------------------------------------|
| AWS ALB for Lambdas* | http://localhost:9000  | http://alb:8080      | Lambdas follow the pattern: '/lambda-name/api-endpoint' |
| AWS Dashboard        | http://localhost:11000 | http://aws:8080      | Provided by localstack                                  |

\* Mock ALB using the `lambda-alb` NPM package `Dockerfile`, see: https://github.com/djfdyuruiry/lambda-alb 

Internal means: how to access the service from within the docker network hosting the environment; i.e. from another container.

External means: how to access the service from your machine; e.g. using a browser or HTTP client.

----

## <a id="aws"></a>AWS Services

This environment provides mock services using [localstack](https://github.com/localstack/localstack), which can be used with the AWS command line and SDKs.

Amongst other things, it provides:

- Cloudwatch
- DynamoDB
- DynamoDB Streams
- Elasticsearch Service
- Lambda
- S3
- SNS
- SQS

For a full list of services and their ports see: https://github.com/localstack/localstack#overview

A wrapper around the [awslocal](https://github.com/localstack/awscli-local) python package is present in the root of this repo @ `./aws`:

    ./aws s3api list-buckets

This has the exact same interface as the normal AWS cli, see: https://docs.aws.amazon.com/cli/latest/reference/

----

## <a id="admin"></a>WireMock Admin API

Each mock API in this environment has an admin API built in, provided by WireMock. This provides a record of requests and methods for configuring endpoint stubs.

For example, to get all the requests made to a mock listening on port 8888, navigate to: http://localhost:8888/__admin/requests

For a full overview, see: http://wiremock.org/docs/api/

OpenAPI Spec: http://wiremock.org/assets/js/wiremock-admin-api.json (Import this into Postman!)
