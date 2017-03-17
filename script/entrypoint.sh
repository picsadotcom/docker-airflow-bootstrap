#!/usr/bin/env bash

AIRFLOW_HOME="/airflow_home"
CMD="airflow"
TRY_LOOP="10"

# Configure airflow with postgres connection string.
if [ -v AIRFLOW_POSTGRES_HOST ] && [ -v AIRFLOW_POSTGRES_PORT ] && [ -v AIRFLOW_POSTGRES_USER ] && [ -v AIRFLOW_POSTGRES_PASSWORD ]; then
    export POSTGRES_HOST=$AIRFLOW_POSTGRES_HOST
    export POSTGRES_PORT=$AIRFLOW_POSTGRES_PORT
    CONN="postgresql://$AIRFLOW_POSTGRES_USER:$AIRFLOW_POSTGRES_PASSWORD@$AIRFLOW_POSTGRES_HOST:$AIRFLOW_POSTGRES_PORT"
    echo "Setting AIRFLOW__CORE__SQL_ALCHEMY_CONN=${CONN}"
    export AIRFLOW__CORE__SQL_ALCHEMY_CONN=$CONN
fi

# Configure airflow with rabbitmq connection string.
if [ -v AIRFLOW_RABBITMQ_HOST ] && [ -v AIRFLOW_RABBITMQ_USER ] && [ -v AIRFLOW_RABBITMQ_PASSWORD ] && [ -v AIRFLOW_RABBITMQ_VHOST ]; then
    export RABBITMQ_HOST=$AIRFLOW_RABBITMQ_HOST
    export RABBITMQ_USER=$AIRFLOW_RABBITMQ_USER
    export RABBITMQ_PASSWORD=$AIRFLOW_RABBITMQ_PASSWORD
    export RABBITMQ_VHOST=$AIRFLOW_RABBITMQ_VHOST
    CREDS="$AIRFLOW_RABBITMQ_USER:$AIRFLOW_RABBITMQ_PASSWORD"
    BROKER_URL="amqp://$AIRFLOW_RABBITMQ_USER:$AIRFLOW_RABBITMQ_PASSWORD@$AIRFLOW_RABBITMQ_HOST:5672/$AIRFLOW_RABBITMQ_VHOST"

    # Another key Celery setting
    echo "Setting AIRFLOW__CELERY__BROKER_URL=${BROKER_URL}"
    export AIRFLOW__CELERY__BROKER_URL=$BROKER_URL
    echo "Setting AIRFLOW__CELERY__CELERY_RESULT_BACKEND=${BROKER_URL}"
    export AIRFLOW__CELERY__CELERY_RESULT_BACKEND=$BROKER_URL
    echo "Setting RABBITMQ_CREDS=${CREDS}"
    export RABBITMQ_CREDS=$CREDS
fi

: ${FERNET_KEY:=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print FERNET_KEY")}
# FERNET_KEY=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print FERNET_KEY")

# Load DAGs exemples (default: No)
if [ "x$LOAD_EX" = "xy" ]; then
    sed -i "s/load_examples = False/load_examples = True/" "$AIRFLOW_HOME"/airflow.cfg
fi

# Install custome python package if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    $(which pip) install --user -r /requirements.txt
fi

# Generate Fernet key
sed -i "s|\$FERNET_KEY|$FERNET_KEY|" "$AIRFLOW_HOME"/airflow.cfg

# wait for DB
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] ; then
  i=0
  while ! nc -z $POSTGRES_HOST $POSTGRES_PORT >/dev/null 2>&1 < /dev/null; do
    i=$((i+1))
    if [ $i -ge $TRY_LOOP ]; then
      echo "$(date) - ${POSTGRES_HOST}:${POSTGRES_PORT} still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for ${POSTGRES_HOST}:${POSTGRES_PORT}... $i/$TRY_LOOP"
    sleep 5
  done
  if [ "$1" = "webserver" ]; then
    echo "Initialize database..."
    $CMD initdb
  fi
  sleep 5
fi

# If we use docker-compose, we use Celery (rabbitmq container).
if [ "x$EXECUTOR" = "xCelery" ]
then
# wait for rabbitmq
  if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] || [ "$1" = "flower" ] ; then
    j=0
    while ! curl -sI -u $RABBITMQ_CREDS http://$RABBITMQ_HOST:15672/api/whoami |grep '200 OK'; do
      j=$((j+1))
      if [ $j -ge $TRY_LOOP ]; then
        echo "$(date) - $RABBITMQ_HOST still not reachable, giving up"
        exit 1
      fi
      echo "$(date) - waiting for RabbitMQ... $j/$TRY_LOOP"
      sleep 5
    done
  fi
  sed -i "s/executor = LocalExecutor/executor = CeleryExecutor/" "$AIRFLOW_HOME"/airflow.cfg
  exec $CMD "$@"
elif [ "x$EXECUTOR" = "xLocal" ]
then
  sed -i "s/executor = CeleryExecutor/executor = LocalExecutor/" "$AIRFLOW_HOME"/airflow.cfg
  exec $CMD "$@"
else
  if [ "$1" = "version" ]; then
    exec $CMD version
  fi
  sed -i "s/executor = CeleryExecutor/executor = SequentialExecutor/" "$AIRFLOW_HOME"/airflow.cfg
  sed -i "s#sql_alchemy_conn = postgresql+psycopg2://airflow:airflow@postgres/airflow#sql_alchemy_conn = sqlite:////usr/local/airflow/airflow.db#" "$AIRFLOW_HOME"/airflow.cfg
  echo "Initialize database..."
  $CMD initdb
  exec $CMD webserver
fi
