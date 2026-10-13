#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT_DIR/.dev-logs"
API_PORT="${API_PORT:-8080}"
ADMIN_PORT="${ADMIN_PORT:-5173}"
API_BASE_URL="${API_BASE_URL:-https://api.damumu.com/api/v1}"
SERVICES_ONLY=false

if [[ "${1:-}" == "--services" ]]; then
  SERVICES_ONLY=true
  shift
fi

find_command() {
  local command_name="$1"
  shift

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return
  fi

  local candidate
  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  return 1
}

if [[ "$SERVICES_ONLY" == false ]]; then
  FLUTTER="$(find_command flutter "$HOME/flutter/bin/flutter")" || {
    echo "错误：找不到 flutter。" >&2
    exit 1
  }
  echo "启动 Flutter App（API：${API_BASE_URL}）"
  cd "$ROOT_DIR/app"
  exec "$FLUTTER" run --dart-define="API_BASE_URL=$API_BASE_URL" "$@"
fi

if [[ -z "${ConnectionStrings__Muda:-}" && -f "$ROOT_DIR/dev.local.sh" ]]; then
  source "$ROOT_DIR/dev.local.sh"
fi
DATABASE_CONNECTION="${ConnectionStrings__Muda:-}"
if [[ -z "$DATABASE_CONNECTION" ]]; then
  POSTGRES_HOST="${DAMUMU_POSTGRES_HOST:-}"
  POSTGRES_PORT="${DAMUMU_POSTGRES_PORT:-5432}"
  POSTGRES_DATABASE="${DAMUMU_POSTGRES_DATABASE:-damumu}"
  POSTGRES_USERNAME="${DAMUMU_POSTGRES_USERNAME:-postgres}"
  POSTGRES_PASSWORD="${DAMUMU_POSTGRES_PASSWORD:-}"
  if [[ -z "$POSTGRES_HOST" || -z "$POSTGRES_PASSWORD" ]]; then
    echo "错误：启动本地 REST API 需要 ConnectionStrings__Muda，或同时设置 DAMUMU_POSTGRES_HOST 和 DAMUMU_POSTGRES_PASSWORD。AWS PostgreSQL 不开放公网 5432；需要本地 API 时请使用本地数据库或 SSH 隧道。" >&2
    exit 1
  fi
  DATABASE_CONNECTION="Host=${POSTGRES_HOST};Port=${POSTGRES_PORT};Database=${POSTGRES_DATABASE};Username=${POSTGRES_USERNAME};Password=${POSTGRES_PASSWORD};SSL Mode=Disable"
fi

latest_node_bin="$(find "$HOME/.nvm/versions/node" -maxdepth 3 -type f -name node -perm -111 2>/dev/null | sort -V | tail -1 || true)"
if [[ -n "$latest_node_bin" ]]; then
  node_bin_dir="$(dirname "$latest_node_bin")"
  export PATH="$node_bin_dir:$PATH"
fi

NPM="$(find_command npm "${node_bin_dir:-}/npm")" || {
  echo "错误：找不到 npm。请先安装 Node.js。" >&2
  exit 1
}

DOTNET=""
for dotnet_candidate in \
  "$HOME/.dotnet-sdk/dotnet" \
  "$(command -v dotnet 2>/dev/null || true)"; do
  if [[ -x "$dotnet_candidate" ]] && [[ -n "$("$dotnet_candidate" --list-sdks 2>/dev/null)" ]]; then
    DOTNET="$dotnet_candidate"
    break
  fi
done
[[ -n "$DOTNET" ]] || {
  echo "错误：找不到 dotnet。请先安装 .NET 10 SDK。" >&2
  exit 1
}

mkdir -p "$LOG_DIR"
api_pid=""
admin_pid=""

cleanup() {
  trap - EXIT INT TERM
  echo
  echo "正在停止 DAMUMU 开发服务…"
  [[ -n "$api_pid" ]] && pkill -TERM -P "$api_pid" 2>/dev/null || true
  [[ -n "$admin_pid" ]] && pkill -TERM -P "$admin_pid" 2>/dev/null || true
  [[ -n "$api_pid" ]] && kill "$api_pid" 2>/dev/null || true
  [[ -n "$admin_pid" ]] && kill "$admin_pid" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "启动 REST API：http://localhost:${API_PORT}/api/v1"
(
  cd "$ROOT_DIR/restapi"
  exec env ASPNETCORE_ENVIRONMENT=Development \
    ASPNETCORE_URLS="http://localhost:${API_PORT}" \
    ConnectionStrings__Muda="$DATABASE_CONNECTION" \
    "$DOTNET" run --no-launch-profile
) >"$LOG_DIR/restapi.log" 2>&1 &
api_pid=$!

echo "启动 Admin：http://localhost:${ADMIN_PORT}"
(
  cd "$ROOT_DIR/admin"
  exec env VITE_API_BASE="http://localhost:${API_PORT}/api/v1" \
    "$NPM" run dev -- --host 127.0.0.1 --port "$ADMIN_PORT"
) >"$LOG_DIR/admin.log" 2>&1 &
admin_pid=$!

sleep 2
if ! kill -0 "$api_pid" 2>/dev/null; then
  echo "REST API 启动失败：" >&2
  tail -30 "$LOG_DIR/restapi.log" >&2
  exit 1
fi
if ! kill -0 "$admin_pid" 2>/dev/null; then
  echo "Admin 启动失败：" >&2
  tail -30 "$LOG_DIR/admin.log" >&2
  exit 1
fi

echo "日志目录：$LOG_DIR"

echo "Admin 和 REST API 已启动；按 Ctrl+C 停止。"
wait
