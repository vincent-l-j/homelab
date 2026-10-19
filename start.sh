#!/bin/bash

ROOT_DIR=$(pwd)
SERVICE_DIRS=(
  "vpn"
  "edge"
  "nextcloud"
)

for SERVICE in "${SERVICE_DIRS[@]}"; do
  cd $SERVICE
  echo $SERVICE
  # docker compose --env-file ../.env --env-file .env up -d
  cd $ROOT_DIR
done
