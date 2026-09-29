#!/bin/sh
set -e

cd /var/www

export PORT="${PORT:-8080}"

# Create .env from example if missing (needed for artisan commands)
if [ ! -f .env ]; then
    cp .env.example .env 2>/dev/null || touch .env
fi

# Pass DATABASE_URL to Laravel's native URL parser (handles query params safely)
if [ -n "$DATABASE_URL" ]; then
    export DB_CONNECTION="pgsql"
    export DB_URL="$DATABASE_URL"
fi

# Create SQLite database if using sqlite driver
if [ "${DB_CONNECTION:-sqlite}" = "sqlite" ]; then
    touch database/database.sqlite
    chown www-data:www-data database/database.sqlite
    chmod 664 database/database.sqlite
fi

# Generate app key if not set
if [ -z "$APP_KEY" ]; then
    php artisan key:generate --force
    export APP_KEY=$(grep '^APP_KEY=' .env | cut -d '=' -f2-)
fi

# Render Nginx config with dynamic PORT
sed "s/\${PORT}/$PORT/g" /etc/nginx/http.d/default.conf.template > /etc/nginx/http.d/default.conf

# Cache configuration for performance
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Avoid mutating an already-provisioned shared database
EXISTING_SCHEMA=$(php -r '
require "vendor/autoload.php";
$app = require "bootstrap/app.php";
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();
echo Illuminate\Support\Facades\Schema::hasTable("businesses") ? "yes" : "no";
' 2>/dev/null || echo "no")

if [ "$EXISTING_SCHEMA" = "yes" ]; then
    echo "Existing database schema detected; skipping migrate/seed"
else
    php artisan migrate --force || echo "WARNING: Migration failed"
    php artisan db:seed --force 2>/dev/null || echo "WARNING: Seeding skipped"
fi

# Create storage symlink if missing
php artisan storage:link 2>/dev/null || true

exec "$@"
