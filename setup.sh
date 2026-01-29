#!/bin/bash
# some bind mounts may need root access
#
# I am testing this by backing up the current containers and then create new ones appending -dummy 
# to the names by modifying the docker-compose files temporarily and the current container variables and directories

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo."
   exit 1
fi

set -eo pipefail

assert_dir_exists() {
    if [ ! -d "$1" ]; then
        echo "Directory $1 does not exist. Exiting..."
        exit 1
    fi
}

assert_dir_not_exists() {
    if [ -d "$1" ]; then
        echo "Directory $1 does exist. Exiting..."
        exit 1
    fi
}

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 {backup|restore}"
    exit 1
fi

ROOT_DIR="/srv/selfhosted"
BACKUP_PARENT_DIR="${ROOT_DIR}/data/backups"
assert_dir_exists "$BACKUP_PARENT_DIR"
#DATE_TO_BACKUP="$(date +%Y_%m_%d)"
#BACKUP_DIR=${BACKUP_PARENT_DIR}/${DATE_TO_BACKUP}
BACKUP_DIR=${BACKUP_PARENT_DIR}

AUTHENTIK_SQL_USER="authentik"
AUTHENTIK_SQL_NAME="authentik"
AUTHENTIK_DIR="${ROOT_DIR}/authentik"
AUTHENTIK_POSTGRES_BACKUP_FILENAME="authentik_postgres_backup.gz"
AUTHENTIK_ENV_BACKUP_FILE="${BACKUP_DIR}/authentik_env_backup.tar.gz"
AUTHENTIK_POSTGRES_BACKUP_FILE="${BACKUP_DIR}/${AUTHENTIK_POSTGRES_BACKUP_FILENAME}"
AUTHENTIK_SERVER_CONTAINER="authentik-server"
AUTHENTIK_POSTGRESQL_CONTAINER="authentik-postgresql"
AUTHENTIK_WORKER_CONTAINER="authentik-worker"

GRAFANA_DIR="${ROOT_DIR}/grafana"
GRAFANA_CONTAINER="grafana"
GRAFANA_BACKUP_FILENAME="grafana_backup.tar.gz"
GRAFANA_BACKUP_FILE="${BACKUP_DIR}/${GRAFANA_BACKUP_FILENAME}"

HEADSCALE_DIR="${ROOT_DIR}/headscale"
HEADSCALE_CONTAINER="headscale"
HEADSCALE_BACKUP_FILENAME="headscale_backup.tar.gz"
HEADSCALE_BACKUP_FILE="${BACKUP_DIR}/${HEADSCALE_BACKUP_FILENAME}"

UPTIME_KUMA_DIR="${ROOT_DIR}/uptime-kuma"
UPTIME_KUMA_CONTAINER="uptime-kuma"
UPTIME_KUMA_BACKUP_FILENAME="uptime_kuma_backup.tar.gz"
UPTIME_KUMA_BACKUP_FILE="${BACKUP_DIR}/${UPTIME_KUMA_BACKUP_FILENAME}"

ENTE_DIR="${ROOT_DIR}/ente"
ENTE_BACKUP_FILENAME=
ENTE_POSTGRES_BACKUP_FILENAME="ente_postgres_backup.gz"
ENTE_POSTGRES_BACKUP_FILE="${BACKUP_DIR}/${ENTE_POSTGRES_BACKUP_FILENAME}"
ENTE_BACKUP_FILE="${BACKUP_DIR}/ente_backup.tar.gz"
ENTE_POSTGRES_CONTAINER="ente-postgres"
ENTE_MUSEUM_CONTAINER="ente-museum"
ENTE_WEB_CONTAINER="ente-web"
ENTE_MINIO_CONTAINER="ente-minio"
ENTE_MINIO_VOLUME="ente_minio-data"
ENTE_SQL_USER="pguser"
ENTE_SQL_NAME="ente_db"

backup_bashrc() {
    cp ~/.bashrc ${BACKUP_DIR}/bashrc_backup
}

backup_postgres() {
    # Wait for PostgreSQL to be ready if it was paused
    docker start $1
    until docker exec $1 pg_isready -U $2 -d $3 &>/dev/null; do
        echo "Waiting for PostgreSQL to start..."
        sleep 1
    done

    docker exec $1 pg_dumpall -U $2 | gzip > $4
}

backup_authentik() {
    echo "Creating Authentik backup..."
    docker stop ${AUTHENTIK_SERVER_CONTAINER} ${AUTHENTIK_WORKER_CONTAINER}
    backup_postgres ${AUTHENTIK_POSTGRESQL_CONTAINER} ${AUTHENTIK_SQL_USER} ${AUTHENTIK_SQL_NAME} ${AUTHENTIK_POSTGRES_BACKUP_FILE}
    tar -czf ${AUTHENTIK_ENV_BACKUP_FILE} -C ${AUTHENTIK_DIR} .env
    echo "Authentik backup created at $AUTHENTIK_POSTGRES_BACKUP_FILE and $AUTHENTIK_ENV_BACKUP_FILE"
    docker start ${AUTHENTIK_SERVER_CONTAINER} ${AUTHENTIK_WORKER_CONTAINER}
}

backup_grafana() {
    # config not used custom.ini
    # we need to backup plugins and the sqlite db
    echo "Creating grafana backup..."
    docker stop ${GRAFANA_CONTAINER}
    tar -czf ${GRAFANA_BACKUP_FILE} -C ${GRAFANA_DIR} data/plugins data/grafana.db
    echo "Grafana backup created at $GRAFANA_BACKUP_FILE"
    docker start ${GRAFANA_CONTAINER}
}

backup_headscale() {
    echo "Creating Headscale backup..."
    docker stop ${HEADSCALE_CONTAINER}
    tar -czf ${HEADSCALE_BACKUP_FILE} -C ${HEADSCALE_DIR} data/db.sqlite .env
    echo "Headscale backup created."
    docker start ${HEADSCALE_CONTAINER}
}

backup_uptime_kuma() {
    echo "Creating Uptime Kuma backup..."
    docker stop ${UPTIME_KUMA_CONTAINER}
    tar -czf ${UPTIME_KUMA_BACKUP_FILE} -C ${UPTIME_KUMA_DIR} data/kuma.db
    echo "Uptime Kuma backup created."
    docker start ${UPTIME_KUMA_CONTAINER}
}

backup_ente() {
    echo "Creating Ente backup..."
    # Placeholder for Ente backup logic
    tar -czf ${ENTE_BACKUP_FILE} -C ${ENTE_DIR} credentials/museum.yaml .env config/cli/ente-cli.db secrets.txt data/minio/
    docker stop ${ENTE_MUSEUM_CONTAINER} ${ENTE_WEB_CONTAINER} ${ENTE_MINIO_CONTAINER}
    backup_postgres ${ENTE_POSTGRES_CONTAINER} ${ENTE_SQL_USER} ${ENTE_SQL_NAME} ${ENTE_POSTGRES_BACKUP_FILE}
    #docker run --rm -v ${ENTE_MINIO_VOLUME}:/data -v ${BACKUP_DIR}:/backup alpine tar -czf /backup/ente_minio_backup.tar.gz -C /data .
    echo "Ente backup created."
    docker start ${ENTE_MUSEUM_CONTAINER} ${ENTE_WEB_CONTAINER} ${ENTE_MINIO_CONTAINER}
}

restore_common() {
    mkdir -p $1/data $1/config
}

restore_bashrc() {
    cp ${RESTORE_DIR}/bashrc_backup ~/.bashrc
}

restore_ente() {
    restore_common ${ENTE_DIR}
    ENTE_RESTORE_POSTGRES_FILE="${RESTORE_DIR}/${ENTE_POSTGRES_BACKUP_FILENAME}"
    echo "Restoring Ente backup..."
    tar -xzf ${ENTE_BACKUP_FILE} -C ${ENTE_DIR}
    docker compose -f ${ENTE_DIR}/docker-compose.yaml up -d
    docker stop ${ENTE_MUSEUM_CONTAINER} ${ENTE_WEB_CONTAINER} ${ENTE_MINIO_CONTAINER}
    docker start ${ENTE_POSTGRES_CONTAINER}
    docker exec -i ${ENTE_POSTGRES_CONTAINER} psql -U ${ENTE_SQL_USER} -d postgres -c "DROP DATABASE ${ENTE_SQL_NAME};"
    docker exec -i ${ENTE_POSTGRES_CONTAINER} psql -U ${ENTE_SQL_USER} -d postgres -c "CREATE DATABASE ${ENTE_SQL_NAME};"
    echo "Restoring Ente PostgreSQL database..."
    echo ${ENTE_RESTORE_POSTGRES_FILE}
    gunzip -c ${ENTE_RESTORE_POSTGRES_FILE} | docker exec -i ${ENTE_POSTGRES_CONTAINER} psql -U ${ENTE_SQL_USER} -d postgres
    #docker run --rm -v ${ENTE_MINIO_VOLUME}:/data -v ${RESTORE_DIR}:/backup alpine sh -c "cd /data && tar -xzf /backup/ente_minio_backup.tar.gz"
    echo "Ente restored from $ENTE_BACKUP_FILE and $ENTE_RESTORE_POSTGRES_FILE"
    docker start ${ENTE_MUSEUM_CONTAINER} ${ENTE_WEB_CONTAINER} ${ENTE_MINIO_CONTAINER}
}

restore_authentik() {
    restore_common ${AUTHENTIK_DIR}
    AUTHENTIK_RESTORE_POSTGRES_FILE="${RESTORE_DIR}/${AUTHENTIK_POSTGRES_BACKUP_FILENAME}"
    tar -xzf ${AUTHENTIK_ENV_BACKUP_FILE} -C ${AUTHENTIK_DIR}
    docker compose -f ${AUTHENTIK_DIR}/docker-compose.yaml up -d
    docker stop ${AUTHENTIK_SERVER_CONTAINER} ${AUTHENTIK_WORKER_CONTAINER}
    docker start ${AUTHENTIK_POSTGRESQL_CONTAINER}
    docker exec -i ${AUTHENTIK_POSTGRESQL_CONTAINER} psql -U ${AUTHENTIK_SQL_USER} -d postgres -c "DROP DATABASE ${AUTHENTIK_SQL_NAME};"
    docker exec -i ${AUTHENTIK_POSTGRESQL_CONTAINER} psql -U ${AUTHENTIK_SQL_USER} -d postgres -c "CREATE DATABASE ${AUTHENTIK_SQL_NAME};"
    gunzip -c ${AUTHENTIK_RESTORE_POSTGRES_FILE} | docker exec -i ${AUTHENTIK_POSTGRESQL_CONTAINER} psql -U ${AUTHENTIK_SQL_USER} -d postgres
    echo "Authentik restored from $AUTHENTIK_RESTORE_POSTGRES_FILE and $AUTHENTIK_ENV_BACKUP_FILE"
    docker start ${AUTHENTIK_SERVER_CONTAINER} ${AUTHENTIK_WORKER_CONTAINER}
}

restore_grafana() {
    restore_common ${GRAFANA_DIR}
    GRAFANA_RESTORE_FILE="${RESTORE_DIR}/${GRAFANA_BACKUP_FILENAME}"
    echo "Restoring Grafana backup..."
    tar -xzf ${GRAFANA_RESTORE_FILE} -C ${GRAFANA_DIR}
    chown -R 472:472 ${GRAFANA_DIR}/data
    docker compose -f ${GRAFANA_DIR}/docker-compose.yaml up -d
    echo "Grafana restored from $GRAFANA_RESTORE_FILE"
}

restore_headscale() {
    restore_common ${HEADSCALE_DIR}
    HEADSCALE_RESTORE_FILE="${RESTORE_DIR}/${HEADSCALE_BACKUP_FILENAME}"
    echo "Restoring Headscale backup..."
    tar -xzf ${HEADSCALE_RESTORE_FILE} -C ${HEADSCALE_DIR}
    docker compose -f ${HEADSCALE_DIR}/docker-compose.yaml up -d
    echo "Headscale restored from $HEADSCALE_RESTORE_FILE"
}

restore_uptime_kuma() {
    restore_common ${UPTIME_KUMA_DIR}
    UPTIME_KUMA_RESTORE_FILE="${RESTORE_DIR}/${UPTIME_KUMA_BACKUP_FILENAME}"
    echo "Restoring Uptime Kuma backup..."
    tar -xzf ${UPTIME_KUMA_RESTORE_FILE} -C ${UPTIME_KUMA_DIR}
    docker compose -f ${UPTIME_KUMA_DIR}/docker-compose.yaml up -d
    echo "Uptime Kuma restored from $UPTIME_KUMA_RESTORE_FILE"
}

backup() {
    #assert_dir_not_exists "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    backup_bashrc
    backup_authentik
    backup_grafana
    backup_headscale
    backup_uptime_kuma
    backup_ente
}

restore() {
    #DATE_TO_RESTORE="latest"
    #if [ "$DATE_TO_RESTORE" == "latest" ]; then
        #DATE_TO_RESTORE=$(ls -td ${BACKUP_PARENT_DIR}/*/ | head -1 | xargs -n 1 basename)
    #fi
    #RESTORE_DIR="${BACKUP_PARENT_DIR}/${DATE_TO_RESTORE}"
    RESTORE_DIR="${BACKUP_PARENT_DIR}"
    echo "Restore directory: $RESTORE_DIR"
    assert_dir_exists "$RESTORE_DIR"

    restore_bashrc
    restore_authentik
    restore_grafana
    restore_headscale
    restore_uptime_kuma
    restore_ente
}

if [ "$1" == "backup" ]; then
    backup
elif [ "$1" == "restore" ]; then
    restore
else
    echo "Invalid argument. Use 'backup' or 'restore'."
    exit 1
fi
