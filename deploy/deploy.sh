#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
readonly REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
readonly COMPOSE_FILE="$REPO_ROOT/deploy/compose.yaml"
readonly ENV_FILE="$REPO_ROOT/deploy/.env"
readonly NGINX_SOURCE="$REPO_ROOT/deploy/nginx/damumu.conf"
readonly NGINX_TARGET="/etc/nginx/sites-available/damumu"
readonly DEPLOY_BRANCH="main"
readonly LOCK_FILE="/tmp/damumu-deploy.lock"
readonly HEALTH_TIMEOUT="180"
readonly -a SERVICES=(site api admin app-web)

APPLY_MIGRATIONS=false
if [[ "${0##*/}" == damumu-deploy-migration ]]; then
  APPLY_MIGRATIONS=true
fi
ACKNOWLEDGE_MIGRATIONS=false
CHECK_PUBLIC=true
UPDATE_NGINX=true
PRUNE_IMAGES=true
COMPOSE_STARTED=false
OLD_REVISION="unknown"
NEW_REVISION="unknown"
STATE_FILE=""
STATE_INITIALIZED=false

usage() {
  cat <<'EOF'
Usage: damumu-deploy [options]
       damumu-deploy-migration [options]

The migration command backs up PostgreSQL and applies new SQL before deployment.

Update the production checkout from origin/main, rebuild the DAMUMU containers,
reload Nginx when its checked-in configuration changed, and verify health.

Options:
  --migrations-applied  Confirm that every newly detected SQL migration was
                        backed up and applied before this run.
  --skip-public-checks  Skip HTTPS checks for the public domains.
  --skip-nginx          Do not install or reload the checked-in Nginx config.
  --no-prune            Keep dangling Docker images after a successful deploy.
  -h, --help            Show this help.
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

apply_migrations() {
  local migration filename backup checksum recorded sql
  local -a unapplied=()
  local -a psql=(sudo -u postgres -- psql -X -F "|" -v ON_ERROR_STOP=1 -d damumu)
  local applied

  applied="$("${psql[@]}" -Atc "SELECT to_regclass('public.damumu_deploy_migration') IS NOT NULL")"
  if [[ "$applied" == t ]]; then
    applied="$("${psql[@]}" -Atc 'SELECT filename, checksum FROM public.damumu_deploy_migration')"
  else
    applied=""
  fi
  while IFS= read -r migration; do
    filename="${migration##*/}"
    [[ "$filename" =~ ^[0-9]{3}_[a-z0-9_]+[.]sql$ ]] || die "Unsupported migration filename: $filename"
    checksum="$(git rev-parse "$NEW_REVISION:$migration")"
    recorded="$(awk -F '|' -v name="$filename" '$1 == name { print $2 }' <<<"$applied")"
    if [[ -z "$recorded" ]]; then
      unapplied+=("$migration")
    elif [[ "$recorded" != "$checksum" ]]; then
      die "Previously applied migration has changed: $filename"
    fi
  done <<<"$pending_migrations"

  if ((${#unapplied[@]} == 0)); then
    log "All detected migrations were already applied by this command"
    return
  fi

  log "Backing up the host PostgreSQL database"
  sudo install -d -m 700 /var/backups/damumu
  backup="$(sudo mktemp /var/backups/damumu/pre-migration.XXXXXXXX.dump)"
  sudo bash -c 'runuser -u postgres -- pg_dump -Fc damumu >"$1" && pg_restore -l "$1" >/dev/null' _ "$backup"
  log "Database backup saved at $backup"

  for migration in "${unapplied[@]}"; do
    filename="${migration##*/}"
    checksum="$(git rev-parse "$NEW_REVISION:$migration")"
    log "Applying $filename"
    # Historical files may already wrap their SQL in BEGIN/COMMIT.
    # Keep the SQL and its completion record in the same transaction.
    sql="$(git show "$NEW_REVISION:$migration" | sed -E '/^[[:space:]]*(BEGIN|COMMIT);[[:space:]]*$/Id')"
    {
      printf '%s\n' "$sql"
      printf '\nCREATE TABLE IF NOT EXISTS public.damumu_deploy_migration (filename text PRIMARY KEY, checksum text NOT NULL);\n'
      printf "INSERT INTO public.damumu_deploy_migration (filename, checksum) VALUES ('%s', '%s');\n" "$filename" "$checksum"
    } | "${psql[@]}" --single-transaction -f -
  done
}

show_failure_context() {
  local exit_code=$?
  trap - ERR
  printf '\nDeployment failed (exit %s). Previous revision: %s; target revision: %s.\n' \
    "$exit_code" "$OLD_REVISION" "$NEW_REVISION" >&2
  if [[ "$COMPOSE_STARTED" == true ]]; then
    compose ps >&2 || true
    compose logs --tail=100 "${SERVICES[@]}" >&2 || true
  fi
  printf 'The script does not delete volumes or roll back database changes.\n' >&2
  exit "$exit_code"
}

trap show_failure_context ERR

while (($#)); do
  case "$1" in
    --migrations-applied) ACKNOWLEDGE_MIGRATIONS=true ;;
    --skip-public-checks) CHECK_PUBLIC=false ;;
    --skip-nginx) UPDATE_NGINX=false ;;
    --no-prune) PRUNE_IMAGES=false ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
  shift
done

if [[ "$APPLY_MIGRATIONS" == true && "$ACKNOWLEDGE_MIGRATIONS" == true ]]; then
  die "Use --migrations-applied with damumu-deploy for manually applied migrations."
fi

for command in git docker curl find flock readlink stat; do
  command -v "$command" >/dev/null 2>&1 || die "Required command not found: $command"
done
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 plugin is not available."
docker compose up --help | grep -q -- '--wait-timeout' || \
  die "Docker Compose is too old; install a version that supports up --wait-timeout."

exec 9>"$LOCK_FILE"
flock -n 9 || die "Another DAMUMU deployment is already running."

cd "$REPO_ROOT"
STATE_FILE="$(git rev-parse --git-path damumu-last-deployed)"

[[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE. Copy deploy/.env.example and add the server secrets first."
for key in DATABASE_CONNECTION AUTH_TOKEN_KEY ADMIN_API_KEY; do
  grep -Eq "^${key}=.+" "$ENV_FILE" || die "Missing required ${key} in deploy/.env."
done
if grep -Eq 'replace-me|replace-with-' "$ENV_FILE"; then
  die "deploy/.env still contains example placeholder secrets."
fi

env_mode="$(stat -c '%a' "$ENV_FILE")"
if [[ "$env_mode" != "600" ]]; then
  die "deploy/.env permissions are ${env_mode}; run: chmod 600 deploy/.env"
fi

[[ "$(git branch --show-current)" == "$DEPLOY_BRANCH" ]] || \
  die "Server checkout must stay on main. Run: git switch main"
[[ -z "$(git status --porcelain)" ]] || \
  die "Working tree is not clean. Review server-side changes before deploying."

checkout_revision="$(git rev-parse HEAD)"
if [[ -f "$STATE_FILE" ]] && git cat-file -e "$(<"$STATE_FILE")^{commit}" 2>/dev/null; then
  OLD_REVISION="$(<"$STATE_FILE")"
  STATE_INITIALIZED=true
else
  OLD_REVISION="$checkout_revision"
fi

log "Fetching origin/$DEPLOY_BRANCH"
git fetch --prune origin "$DEPLOY_BRANCH"
NEW_REVISION="$(git rev-parse "origin/$DEPLOY_BRANCH")"
git merge-base --is-ancestor "$checkout_revision" "$NEW_REVISION" || \
  die "Local main has diverged from origin/main; automatic deployment stopped."
git merge-base --is-ancestor "$OLD_REVISION" "$NEW_REVISION" || \
  die "The last successful deployment is not an ancestor of origin/main."

pending_migrations="$(git diff --name-only --no-renames "$OLD_REVISION" "$NEW_REVISION" -- 'restapi/Migrations/*.sql')"
if [[ "$checkout_revision" == "$NEW_REVISION" ]]; then
  log "origin/main is already checked out; rebuilding the current revision"
else
  log "Fast-forwarding main from ${checkout_revision:0:12} to ${NEW_REVISION:0:12}"
  git merge --ff-only "origin/$DEPLOY_BRANCH"
fi

if [[ "$STATE_INITIALIZED" != true && "$ACKNOWLEDGE_MIGRATIONS" != true ]]; then
  latest_migration="$(find restapi/Migrations -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort | tail -n 1)"
  cat >&2 <<EOF

This is the first deployment managed by this script, so the previously deployed
database migration level is unknown. The newest migration in this checkout is:
  ${latest_migration}

The running containers were not changed. Back up the database, verify that all
required migrations through this file are applied, then run:
  damumu-deploy --migrations-applied
EOF
  exit 2
fi

if [[ -n "$pending_migrations" && "$APPLY_MIGRATIONS" != true && "$ACKNOWLEDGE_MIGRATIONS" != true ]]; then
  printf '\nNew database migration files were detected:\n%s\n' "$pending_migrations" >&2
  cat >&2 <<'EOF'

The source checkout was updated, but the running containers were not changed.
Run damumu-deploy-migration to back up the database, apply the migrations and deploy.
EOF
  exit 2
fi

if [[ "$APPLY_MIGRATIONS" == true && -n "$pending_migrations" ]]; then
  [[ -z "$(git diff --name-only --diff-filter=DMRTUXB --no-renames "$OLD_REVISION" "$NEW_REVISION" -- 'restapi/Migrations/*.sql')" ]] || \
    die "Existing migration files changed or were removed. Review the changes before deploying."
  pending_migrations="$(LC_ALL=C sort <<<"$pending_migrations")"
fi

if [[ "$UPDATE_NGINX" == true ]]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required to update Nginx."
  if ! sudo openssl x509 -in /etc/letsencrypt/live/damumu.com/fullchain.pem \
    -noout -checkhost app.damumu.com | grep -Fxq 'Hostname app.damumu.com does match certificate'; then
    die "The DAMUMU certificate must cover app.damumu.com. Complete the one-time setup in deploy/README.md."
  fi
fi

log "Validating Compose configuration"
compose config --quiet

[[ -d /srv/damumu/uploads && -r /srv/damumu/uploads ]] || \
  die "Prepare /srv/damumu/uploads first; see deploy/README.md. Docker will not create a missing media directory."
api_container="$(compose ps -aq api)"
if [[ -n "$api_container" ]]; then
  old_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/uploads"}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}{{end}}' "$api_container")"
  if [[ -n "$old_volume" ]]; then
    [[ -f /srv/damumu/.uploads-migrated-from && "$(cat /srv/damumu/.uploads-migrated-from)" == "$old_volume" ]] || \
      die "Existing uploads are in $old_volume. Run bash deploy/migrate-uploads.sh before replacing the API container."
    [[ "$(docker inspect --format '{{.State.Running}}' "$api_container")" == false ]] || \
      die "Old API resumed after migration; stop writes and verify/copy any new uploads before deployment."
  fi
fi

available_kb="$(df -Pk "$REPO_ROOT" | awk 'NR == 2 {print $4}')"
if ((available_kb < 2097152)); then
  printf 'WARNING: less than 2 GiB is available on the deployment filesystem.\n' >&2
  df -h "$REPO_ROOT" >&2
fi

log "Building the standalone web app image"
compose build --pull app-web

log "Building site, API, and Admin images"
compose build --pull site api admin

if [[ "$APPLY_MIGRATIONS" == true && -n "$pending_migrations" ]]; then
  apply_migrations
fi

log "Starting containers and waiting for health checks"
COMPOSE_STARTED=true
compose up -d --remove-orphans --wait --wait-timeout "$HEALTH_TIMEOUT" "${SERVICES[@]}"

log "Checking services through their loopback ports"
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8081/healthz >/dev/null
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8080/api/v1/health >/dev/null
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8082/healthz >/dev/null
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8083/healthz >/dev/null
curl --fail --silent --show-error --max-time 15 \
  http://127.0.0.1:8080/uploads/system-avatars/green-sprout.jpg >/dev/null

if [[ "$UPDATE_NGINX" == true ]]; then
  sudo nginx -v >/dev/null 2>&1 || die "Nginx is not installed on the host."
  sudo test -f "$NGINX_TARGET" || \
    die "Nginx site is not installed. Complete the first-deployment steps in deploy/README.md."

  if ! sudo cmp --silent "$NGINX_SOURCE" "$NGINX_TARGET"; then
    log "Installing and validating the updated Nginx configuration"
    nginx_backup="${NGINX_TARGET}.deploy-backup"
    sudo cp "$NGINX_TARGET" "$nginx_backup"
    sudo install -m 644 "$NGINX_SOURCE" "$NGINX_TARGET"
    if ! sudo nginx -t; then
      sudo cp "$nginx_backup" "$NGINX_TARGET"
      sudo rm -f "$nginx_backup"
      sudo nginx -t || true
      die "New Nginx configuration was invalid; the previous file was restored."
    fi
    sudo systemctl reload nginx
    sudo rm -f "$nginx_backup"
  else
    log "Nginx configuration is unchanged"
    sudo nginx -t
  fi
fi

if [[ "$CHECK_PUBLIC" == true ]]; then
  log "Checking public HTTPS routes"
  curl --fail --silent --show-error --max-time 20 https://www.damumu.com/healthz >/dev/null
  curl --fail --silent --show-error --max-time 20 https://app.damumu.com/healthz >/dev/null
  curl --fail --silent --show-error --max-time 20 https://api.damumu.com/api/v1/health >/dev/null
  curl --fail --silent --show-error --max-time 20 \
    https://api.damumu.com/uploads/system-avatars/green-sprout.jpg >/dev/null
  admin_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --max-time 20 https://admin.damumu.com/healthz)"
  [[ "$admin_status" == "401" ]] || \
    die "Admin public protection check expected HTTP 401, received ${admin_status}."
fi

if [[ "$PRUNE_IMAGES" == true ]]; then
  log "Removing dangling Docker images"
  docker image prune -f >/dev/null
fi

log "Deployment succeeded"
compose ps
printf '%s\n' "$NEW_REVISION" >"$STATE_FILE"
printf '\nRevision: %s\n' "$(git rev-parse HEAD)"
printf 'Public site: https://www.damumu.com\n'
printf 'Public API:  https://api.damumu.com/api/v1/health\n'
printf 'Admin:       https://admin.damumu.com\n'
printf 'Web app:     https://app.damumu.com\n'
