#!/bin/bash
set -e

# Ensure storage directories exist
echo "==> Checking storage directories..."
mkdir -p /var/lib/cvr /tmp/hls

echo "==> Running database migrations..."
bin/tpro_nvr eval "TProNVR.Release.migrate"
echo "==> Migrations complete!"

exec "$@"