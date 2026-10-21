#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Run this backup as root.' >&2; exit 1; }
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT=/var/backups/damumu/scheduled
readonly KEY=/etc/damumu/backup.key
[[ -s "$KEY" && "$(stat -c '%a' "$KEY")" == 600 ]] || {
  echo 'Prepare /etc/damumu/backup.key with mode 600 first.' >&2; exit 1;
}
for tool in docker pg_dump runuser tar gpg flock; do command -v "$tool" >/dev/null; done
exec 9>/tmp/damumu-deploy.lock
flock -n 9 || { echo 'A deployment, migration or backup is running.' >&2; exit 1; }
install -d -m 700 "$ROOT"
work="$(mktemp -d "$ROOT/.work.XXXXXXXX")"
restart_api=false
compose() { docker compose --env-file "$REPO_ROOT/deploy/.env" -f "$REPO_ROOT/deploy/compose.yaml" "$@"; }
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$restart_api" == true ]]; then compose start api || status=1; fi
  [[ "$work" == "$ROOT"/.work.* ]] && rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT
container="$(compose ps -q api)"
if [[ -n "$container" && "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]]; then
  restart_api=true
  compose stop api
fi
runuser -u postgres -- pg_dump -Fc damumu >"$work/database.dump"
tar -czf "$work/uploads.tar.gz" -C /srv/damumu uploads
if [[ "$restart_api" == true ]]; then compose start api; restart_api=false; fi
tar -czf "$work/archive.tar.gz" -C "$work" database.dump uploads.tar.gz
destination="$ROOT/damumu-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz.gpg"
gpg --batch --yes --pinentry-mode loopback --cipher-algo AES256 \
  --passphrase-file "$KEY" --symmetric --output "$destination" "$work/archive.tar.gz"
chmod 600 "$destination"
# Only this job's own encrypted archives are rotated; migration backups are untouched.
find "$ROOT" -maxdepth 1 -type f -name 'damumu-*.tar.gz.gpg' -mtime +29 -delete
printf 'Encrypted backup completed: %s\n' "$destination"
printf 'Copy this archive off the instance and keep the recovery key separately.\n'
