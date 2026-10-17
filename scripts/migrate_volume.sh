# source scripts/migrate_volume.sh
# cd vpn/
# migrate_volume vpn_etc_wireguard vpn etc_wireguard
# migrate_volume vpn_etc_pihole vpn etc_pihole

function migrate_volume() {
  EXISTING_VOLUME=$1
  PROJECT_NAME=$2
  VOLUME_YAML=$3

  docker compose down
  docker run --rm -v $EXISTING_VOLUME:/source -v "$(pwd)":/backup alpine tar cvf /backup/volume_backup.tar -C /source .
  docker volume rm $EXISTING_VOLUME
  docker volume create $EXISTING_VOLUME \
    --label com.docker.compose.project=$PROJECT_NAME \
    --label com.docker.compose.volume=$VOLUME_YAML
  docker run --rm -v $EXISTING_VOLUME:/dest -v "$(pwd)":/backup alpine sh -c "tar xvf /backup/volume_backup.tar -C /dest"
}
