#!/usr/bin/env bash
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo "Run with sudo." >&2; exit 1; }
[[ "$(readlink -f /srv/damumu/uploads)" == /srv/damumu/uploads ]] || {
  echo "Verify the existing /srv/damumu/uploads directory first." >&2; exit 1;
}
[[ -d /srv/damumu/uploads ]] || { echo "Media directory does not exist." >&2; exit 1; }
[[ ! -L /srv/damumu/keys ]] || { echo "The key directory must not be a symlink." >&2; exit 1; }
install -d -m 700 -o 1654 -g 1654 /srv/damumu/keys
chown -R --no-dereference 1654:1654 /srv/damumu/uploads
chmod u+rwx /srv/damumu/uploads
echo "Prepared persistent key storage and API media ownership."
