#!/usr/bin/env bash

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

if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}[!] Please run this installer as root:${NC}"
  echo "sudo bash <(curl -fsSL https://raw.githubusercontent.com/viag0/SKYMC/main/install.sh)"
  exit 1
fi

DOWNLOADER=""

if command -v curl >/dev/null 2>&1; then
  DOWNLOADER="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOADER="wget -qO-"
else
  echo -e "${RED}[!] curl or wget is required to continue.${NC}"
  exit 1
fi

TMP_FILE="/tmp/skymc-core.sh"

echo -e "${YELLOW}[*] Downloading SkyMC core installer...${NC}"
$DOWNLOADER https://raw.githubusercontent.com/viag0/SKYMC/main/skymc-core.sh > "$TMP_FILE"

chmod +x "$TMP_FILE"

lecho -e "${YELLOW}[*] Running SkyMC installer...${NC}"
bash "$TMP_FILE"

rm -f "$TMP_FILE"

echo -e "${GREEN}[✓] SkyMC installation completed successfully!${NC}"
