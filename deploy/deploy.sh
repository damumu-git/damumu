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

ACKNOWLEDGE_MIGRATIONS=false
CHECK_PUBLIC=true
UPDATE_NGINX=true
PRUNE_IMAGES=true
COMPOSE_STARTED=false
OLD_REVISION="unknown"
NEW_REVISION="unknown"
STATE_FILE=""

usage() {
  cat <<'EOF'
Usage: damumu-deploy [options]

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

show_failure_context() {
  local exit_code=$?
  trap - ERR
  printf '\nDeployment failed (exit %s). Previous revision: %s; target revision: %s.\n' \
    "$exit_code" "$OLD_REVISION" "$NEW_REVISION" >&2
  if [[ "$COMPOSE_STARTED" == true ]]; then
    compose ps >&2 || true
    compose logs --tail=100 site api admin >&2 || true
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

for command in git docker curl flock readlink stat; do
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

pending_migrations="$(git diff --name-only "$OLD_REVISION" "$NEW_REVISION" -- 'restapi/Migrations/*.sql')"
if [[ "$checkout_revision" == "$NEW_REVISION" ]]; then
  log "origin/main is already checked out; rebuilding the current revision"
else
  log "Fast-forwarding main from ${checkout_revision:0:12} to ${NEW_REVISION:0:12}"
  git merge --ff-only "origin/$DEPLOY_BRANCH"
fi

if [[ -n "$pending_migrations" && "$ACKNOWLEDGE_MIGRATIONS" != true ]]; then
  printf '\nNew database migration files were detected:\n%s\n' "$pending_migrations" >&2
  cat >&2 <<'EOF'

The source checkout was updated, but the running containers were not changed.
Create a database backup, review and apply the listed migrations in order, then run:
  damumu-deploy --migrations-applied
EOF
  exit 2
fi

log "Validating Compose configuration"
compose config --quiet

available_kb="$(df -Pk "$REPO_ROOT" | awk 'NR == 2 {print $4}')"
if ((available_kb < 2097152)); then
  printf 'WARNING: less than 2 GiB is available on the deployment filesystem.\n' >&2
  df -h "$REPO_ROOT" >&2
fi

log "Building site, API, and Admin images"
compose build --pull site api admin

log "Starting containers and waiting for health checks"
COMPOSE_STARTED=true
compose up -d --remove-orphans --wait --wait-timeout "$HEALTH_TIMEOUT" site api admin

log "Checking services through their loopback ports"
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8081/healthz >/dev/null
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8080/api/v1/health >/dev/null
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8082/healthz >/dev/null

if [[ "$UPDATE_NGINX" == true ]]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required to update Nginx."
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
  curl --fail --silent --show-error --max-time 20 https://api.damumu.com/api/v1/health >/dev/null
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
