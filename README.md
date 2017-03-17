# docker-airflow-bootstrap

Dockerfile for quickly running Airflow projects in a Docker container.

Uses Python 3 with compatible AMQP libraries.

## Usage

Make sure you have an `airflow_home` folder in your project. This will get copied over.

In the root of the repo for your Airflow project, add a Dockerfile for the project. For example, this file could contain:

  FROM picsa/airflow-bootstrap
  ARG VCS_HASH=NOT_SET

You're done.

## Releases

2017-03-17: Initial version with Airflow 1.7.1.3
