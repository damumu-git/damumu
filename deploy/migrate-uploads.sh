#!/usr/bin/env bash
# One-time, offline migration from the currently attached Docker named volume.
set -Eeuo pipefail
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TARGET="/srv/damumu/uploads"
readonly BACKUP_ROOT="/var/backups/damumu"
readonly STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"

compose() { docker compose --env-file "$REPO_ROOT/deploy/.env" -f "$REPO_ROOT/deploy/compose.yaml" "$@"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

exec 9>/tmp/damumu-deploy.lock
flock -n 9 || die "A deployment or migration is already running."
container="$(compose ps -aq api)"
[[ -n "$container" ]] || die "No existing API container; inspect the old volume manually before proceeding."
source_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/uploads"}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}{{end}}' "$container")"
[[ -n "$source_volume" ]] || die "The existing API does not mount a named volume at /app/uploads."
docker volume inspect "$source_volume" >/dev/null
image="$(docker inspect --format '{{.Image}}' "$container")"

# A stopped container can still reference an image removed by earlier cleanup.
# Resolve and check the helper before interrupting any running API.
if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'Old API image is unavailable; preparing the official Debian migration helper.\n'
  image="debian:bookworm-slim"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    docker pull "$image"
  fi
  image="$(docker image inspect --format '{{.Id}}' "$image")"
fi
docker run --rm --user 0 --entrypoint /bin/sh "$image" -ec '
  for tool in tar gzip chmod cp diff; do command -v "$tool" >/dev/null; done
'

sudo install -d -m 755 /srv/damumu "$TARGET"
sudo install -d -m 700 "$BACKUP_ROOT"
[[ -z "$(sudo find "$TARGET" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
  die "$TARGET must be empty; review existing files instead of overwriting them."

printf 'Stopping API writes; copying volume %s to %s.\n' "$source_volume" "$TARGET"
compose stop api
# Leave the API stopped on any error so uploads cannot diverge during recovery.
docker run --rm --user 0 --entrypoint /bin/sh \
  --mount "type=volume,source=$source_volume,target=/source,readonly" \
  --mount "type=bind,source=$TARGET,target=/target" \
  --mount "type=bind,source=$BACKUP_ROOT,target=/backup" \
  -e "BACKUP_NAME=uploads-$STAMP.tar.gz" "$image" -ec '
    tar -czf "/backup/$BACKUP_NAME" -C /source .
    chmod 600 "/backup/$BACKUP_NAME"
    cp -a /source/. /target/
    diff -qr /source /target
  '
# This marker permits deploy.sh to replace the old container only after success.
printf '%s\n' "$source_volume" | sudo tee /srv/damumu/.uploads-migrated-from >/dev/null
printf 'Migration verified. Backup: %s/uploads-%s.tar.gz\n' "$BACKUP_ROOT" "$STAMP"
printf 'API remains stopped. Run damumu-deploy to start it with the new mount.\n'
printf 'Keep the original volume until the new deployment and backup restore are verified.\n'
