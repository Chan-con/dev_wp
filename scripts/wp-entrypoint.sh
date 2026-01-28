#!/bin/sh
set -eu

DOCROOT="/var/www/html"
WP_CONTENT="$DOCROOT/wp-content"

# Populate WordPress core into the persistent volume on first boot.
# (We do this here so we can also guarantee permissions before Apache starts.)
if [ ! -f "$DOCROOT/wp-includes/version.php" ]; then
  echo "Populating WordPress core into $DOCROOT"
  cp -a /usr/src/wordpress/. "$DOCROOT"/
fi

# Ensure wp-content runtime dirs exist.
mkdir -p \
  "$WP_CONTENT/uploads" \
  "$WP_CONTENT/upgrade" \
  "$WP_CONTENT/languages" \
  "$WP_CONTENT/cache"

# Ensure WordPress (www-data uid/gid 33) can write uploads and upgrades.
# This fixes errors like: "アップロードしたファイルを wp-content/uploads/YYYY/MM に移動できませんでした".
if [ "$(id -u)" = "0" ]; then
  chown -R 33:33 "$WP_CONTENT" || true
  chmod -R u+rwX,g+rwX "$WP_CONTENT" || true
fi

# Compose can override/lose the image CMD when entrypoint is replaced.
# Fallback to the default command used by the official wordpress image.
if [ "$#" -eq 0 ]; then
  set -- apache2-foreground
fi

exec "$@"
