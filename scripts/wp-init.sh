#!/bin/sh
set -eu

cd /var/www/html

# Ensure wp-content runtime dirs exist and are writable.
# (Keeps compose simple by avoiding separate permission-fix containers.)
mkdir -p /var/www/html/wp-content/upgrade /var/www/html/wp-content/uploads /var/www/html/wp-content/languages /var/www/html/wp-content/cache

# Ensure bind-mounted plugins directory exists and is writable.
mkdir -p /var/www/html/wp-content/plugins

# Ensure core files are writable for updates.
# The WordPress container typically runs as www-data; the shared volume can end up
# with ownership that prevents wp-cli from updating core.
if [ "$(id -u)" = "0" ]; then
  # Use numeric uid/gid to avoid mismatches between wordpress and wordpress:cli images.
  chown -R 33:33 /var/www/html || true
  chown -R 33:33 /var/www/html/wp-content/plugins || true
  chmod -R u+rwX,g+rwX /var/www/html/wp-content/plugins || true
  chown -R 33:33 /var/www/html/wp-content/upgrade /var/www/html/wp-content/uploads /var/www/html/wp-content/languages /var/www/html/wp-content/cache || true
  chmod -R u+rwX,g+rwX /var/www/html/wp-content/upgrade /var/www/html/wp-content/uploads /var/www/html/wp-content/languages /var/www/html/wp-content/cache || true
fi

# Wait for WordPress files volume to be ready.
# (The wordpress service populates /var/www/html on first run, but files can appear incrementally.)
i=0
while [ ! -f /var/www/html/wp-settings.php ] || [ ! -f /var/www/html/wp-includes/version.php ] || [ ! -f /var/www/html/wp-admin/install.php ]; do
  i=$((i+1))
  if [ "$i" -gt 60 ]; then
    echo "Timed out waiting for WordPress core files to appear in /var/www/html" >&2
    exit 1
  fi
  echo "Waiting for WordPress core files..." 
  sleep 2
done

# Generate wp-config.php if not present
if [ ! -f wp-config.php ]; then
  echo "Creating wp-config.php"
  wp config create \
    --dbname="${WORDPRESS_DB_NAME}" \
    --dbuser="${WORDPRESS_DB_USER}" \
    --dbpass="${WORDPRESS_DB_PASSWORD}" \
    --dbhost="${WORDPRESS_DB_HOST}" \
    --skip-check \
    --allow-root

  if [ -n "${WP_LOCALE:-}" ]; then
    wp config set WPLANG "${WP_LOCALE}" --type=constant --allow-root
  fi
fi

# Ensure file operations work without FTP prompts.
wp config set FS_METHOD direct --type=constant --allow-root || true

# Wait for DB to accept connections (after wp-config.php exists).
# We intentionally avoid `wp db check` here because the mysql client inside
# some wp-cli images can require SSL depending on defaults.
db_host="${WORDPRESS_DB_HOST:-db:3306}"
db_hostname="$db_host"
db_port="3306"
case "$db_host" in
  *:*)
    db_hostname="${db_host%:*}"
    db_port="${db_host##*:}"
    ;;
esac

i=0
until DB_HOST="$db_hostname" DB_PORT="$db_port" DB_USER="$WORDPRESS_DB_USER" DB_PASS="$WORDPRESS_DB_PASSWORD" DB_NAME="$WORDPRESS_DB_NAME" \
  php -r 'mysqli_report(MYSQLI_REPORT_OFF); $h=getenv("DB_HOST"); $u=getenv("DB_USER"); $p=getenv("DB_PASS"); $d=getenv("DB_NAME"); $port=(int)getenv("DB_PORT"); $m=@mysqli_connect($h,$u,$p,$d,$port); if($m){ mysqli_close($m); exit(0);} exit(1);' \
  >/dev/null 2>&1; do
  i=$((i+1))
  if [ "$i" -gt 60 ]; then
    echo "Timed out waiting for database connection" >&2
    exit 1
  fi
  echo "Waiting for database..."
  sleep 2
done

# Install WordPress if not installed
if ! wp core is-installed --allow-root >/dev/null 2>&1; then
  echo "Installing WordPress..."
  wp core install \
    --url="${WP_SITE_URL}" \
    --title="${WP_SITE_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASSWORD}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --skip-email \
    --allow-root

  if [ -n "${WP_LOCALE:-}" ]; then
    wp language core install "${WP_LOCALE}" --activate --allow-root || true
  fi

  echo "WordPress installed. Admin: ${WP_SITE_URL}/wp-admin/"
else
  desired_url="${WP_SITE_URL:-}"
  desired_url_norm="${desired_url%/}"

  if [ -n "$desired_url_norm" ]; then
    current_home="$(wp option get home --skip-plugins --skip-themes --allow-root 2>/dev/null || true)"
    current_siteurl="$(wp option get siteurl --skip-plugins --skip-themes --allow-root 2>/dev/null || true)"

    if [ "${current_home%/}" != "$desired_url_norm" ] || [ "${current_siteurl%/}" != "$desired_url_norm" ]; then
      echo "Updating WordPress URLs (home/siteurl) to: ${desired_url_norm}"
      wp option update home "$desired_url_norm" --skip-plugins --skip-themes --allow-root
      wp option update siteurl "$desired_url_norm" --skip-plugins --skip-themes --allow-root
    else
      echo "WordPress already installed. URLs already match."
    fi
  else
    echo "WordPress already installed. Nothing to do."
  fi
fi
