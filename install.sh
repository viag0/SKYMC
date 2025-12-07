#!/usr/bin/env bash
# ============================================
# SkyMC One-Command Installer
# https://github.com/viag0/SKYMC
# ============================================

set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo -e "${GREEN}"
echo "==============================================="
echo "        SkyMC Installer"
echo "        https://github.com/viag0/SKYMC"
echo "==============================================="
echo -e "${NC}"

# --------------------------------------------
# Root check
# --------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}[!] Please run this installer as root:${NC}"
  echo "sudo bash install.sh"
  exit 1
fi

# --------------------------------------------
# Downloader check
# --------------------------------------------
DOWNLOADER=""

if command -v curl >/dev/null 2>&1; then
  DOWNLOADER="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOADER="wget -qO-"
else
  echo -e "${RED}[!] curl or wget is required to continue.${NC}"
  exit 1
fi

# --------------------------------------------
# Download core installer
# --------------------------------------------
TMP_FILE="/tmp/skymc-core.sh"

echo -e "${YELLOW}[*] Downloading SkyMC core installer...${NC}"
$DOWNLOADER https://raw.githubusercontent.com/viag0/SKYMC/main/skymc-core.sh > "$TMP_FILE"

if [ ! -s "$TMP_FILE" ]; then
  echo -e "${RED}[!] Failed to download skymc-core.sh${NC}"
  exit 1
fi

chmod +x "$TMP_FILE"

# --------------------------------------------
# Run core installer
# --------------------------------------------
echo -e "${YELLOW}[*] Running SkyMC installer...${NC}"
bash "$TMP_FILE"

# --------------------------------------------
# Cleanup
# --------------------------------------------
rm -f "$TMP_FILE"

echo -e "${GREEN}[✓] SkyMC installation completed successfully!${NC}"
