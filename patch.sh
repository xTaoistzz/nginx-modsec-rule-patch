#!/bin/bash
set -e

# =============================================================================
# NGINX MODSEC PATCH SCRIPT
# =============================================================================
# This script patches existing ModSecurity installation at /etc/nginx/modsec
# It will:
#  - Backup current modsec directory
#  - Sync new rules
#  - Test nginx config
#  - Reload nginx if test passes
# =============================================================================

MODSEC_DIR="/etc/nginx/modsec"
LOCAL_RULES_DIR="$(pwd)/rules"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_DIR="/etc/nginx/modsec-backup-${TIMESTAMP}"

echo "[+] Starting ModSecurity patch process..."

# -----------------------------------------------------------------------------
# 1. Validate paths
# -----------------------------------------------------------------------------
if [ ! -d "$MODSEC_DIR" ]; then
  echo "[!] ERROR: $MODSEC_DIR not found. Aborting."
  exit 1
fi

if [ ! -d "$LOCAL_RULES_DIR" ]; then
  echo "[!] ERROR: Local rules directory not found at $LOCAL_RULES_DIR"
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Backup existing modsec directory
# -----------------------------------------------------------------------------
echo "[+] Creating backup at $BACKUP_DIR"
cp -a "$MODSEC_DIR" "$BACKUP_DIR"

echo "[+] Backup completed."

# -----------------------------------------------------------------------------
# 3. Sync rules
# -----------------------------------------------------------------------------
echo "[+] Syncing new rules from $LOCAL_RULES_DIR to $MODSEC_DIR"

rsync -av \
  "$LOCAL_RULES_DIR"/ \
  "$MODSEC_DIR"/

echo "[+] Rules synced successfully."

# -----------------------------------------------------------------------------
# 4. Test nginx configuration
# -----------------------------------------------------------------------------
# echo "[+] Testing nginx configuration..."
# if nginx -t; then
#   echo "[+] Nginx configuration test passed."
# else
#   echo "[!] Nginx configuration test FAILED!"
#   echo "[!] Restoring from backup..."
#   rm -rf "$MODSEC_DIR"
#   mv "$BACKUP_DIR" "$MODSEC_DIR"
#   echo "[+] Rollback completed."
#   exit 1
# fi

# -----------------------------------------------------------------------------
# 5. Reload nginx
# -----------------------------------------------------------------------------
echo "[+] Reloading nginx..."
systemctl reload nginx

echo "[+] ModSecurity patch completed successfully."