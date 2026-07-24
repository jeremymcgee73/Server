#!/bin/bash

set -e

DB_URL=jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}

# Wait for the server to become available. Commands used as an `until`
# condition are exempt from `set -e`, so connection retries remain safe while
# actual schema setup failures stop the job.
until nc -zw3 "${POSTGRES_HOST}" "${POSTGRES_PORT}"; do
    sleep 1
done

java -jar SchemaManager.jar -url ${DB_URL} -user ${POSTGRES_USER} -password ${POSTGRES_PASSWORD}  SetupGenericDatabase
java -jar SchemaManager.jar -url ${DB_URL} -user ${POSTGRES_USER} -password ${POSTGRES_PASSWORD}  upgrade

if curl -sL --fail http://localhost:15021/healthz/ready -o /dev/null; then
  # Shutdown Istio sidecar if it exists
  curl -fsI -X POST http://localhost:15020/quitquitquit
fi
