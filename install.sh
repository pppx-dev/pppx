#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define colors for beautiful output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

REPO="pppx-dev/pppx"
EXE_NAME="pppx"
INSTALL_DIR="${HOME}/.local/bin"

# Locate the repository root (the directory containing this script)
PPPX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PPPX_SH_SRC="$PPPX_ROOT/scripts/pppx.sh"
TABLE_DIR="$PPPX_ROOT/table"

echo -e "${CYAN}${BOLD}==========================================${NC}"
echo -e "${CYAN}${BOLD}       PPPx Automated Installer           ${NC}"
echo -e "${CYAN}${BOLD}==========================================${NC}\n"

# Ensure the script is run from inside the cloned repository
if [ ! -f "$PPPX_SH_SRC" ] || [ ! -d "$TABLE_DIR" ]; then
    echo -e "${RED}Error: install.sh must be run from the root of the cloned PPPx repository.${NC}"
    echo -e "Please clone the repository first and run the installer from its root folder:"
    echo -e "${BOLD}  git clone https://github.com/$REPO.git${NC}"
    echo -e "${BOLD}  cd pppx${NC}"
    echo -e "${BOLD}  ./install.sh${NC}"
    exit 1
fi

echo -e "${CYAN}[1/6] Detecting System Environment...${NC}"
# 1. Detect Operating System
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [ "$OS" = "darwin" ]; then
    OS="macos"
elif [ "$OS" != "linux" ]; then
    echo -e "${RED}Error: Unsupported OS '$OS'. This script only supports Linux and macOS.${NC}"
    exit 1
fi

# 2. Detect Architecture
ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    ARCH="x86_64"
elif [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
else
    echo -e "${RED}Error: Unsupported architecture '$ARCH'.${NC}"
    exit 1
fi

echo -e "      OS:   ${BOLD}$OS${NC}"
echo -e "      Arch: ${BOLD}$ARCH${NC}\n"

# Verify 'unzip' is installed
if ! command -v unzip &> /dev/null; then
    echo -e "${RED}Error: 'unzip' is not installed.${NC}"
    echo -e "Please install it using your system's package manager (e.g., 'sudo apt install unzip') and run this script again."
    exit 1
fi

# 3. Fetch the latest release download URL from GitHub API
echo -e "${CYAN}[2/6] Fetching Latest Release...${NC}"
LATEST_JSON=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")

# Search for the zip asset that matches the OS and Architecture
DOWNLOAD_URL=$(echo "$LATEST_JSON" | grep '"browser_download_url":' | grep -i "pppx.*${OS}-${ARCH}\.zip" | head -n 1 | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}Error: Could not find a matching release asset for $OS $ARCH.${NC}"
    echo -e "Please download and install manually from: https://github.com/$REPO/releases/latest"
    exit 1
fi

echo -e "      Found: ${DOWNLOAD_URL##*/}\n"

# 4. Download and Extract to a temporary directory
TMP_DIR=$(mktemp -d)
ZIP_FILE="$TMP_DIR/release.zip"

echo -e "${CYAN}[3/6] Downloading & Extracting...${NC}"
curl -sL "$DOWNLOAD_URL" -o "$ZIP_FILE"
unzip -q "$ZIP_FILE" -d "$TMP_DIR"

# Find the executable
EXTRACTED_EXE=$(find "$TMP_DIR" -type f -name "$EXE_NAME" | head -n 1)

if [ -z "$EXTRACTED_EXE" ]; then
    echo -e "${RED}Error: Could not find the '$EXE_NAME' executable inside the downloaded archive.${NC}"
    rm -rf "$TMP_DIR"
    exit 1
fi
echo -e "      Extraction successful.\n"

# 5. Move to the installation directory
echo -e "${CYAN}[4/6] Installing to $INSTALL_DIR...${NC}"
mkdir -p "$INSTALL_DIR"
mv "$EXTRACTED_EXE" "$INSTALL_DIR/$EXE_NAME"
chmod +x "$INSTALL_DIR/$EXE_NAME"

# macOS Quarantine bypass
if [ "$OS" = "macos" ]; then
    echo -e "      Applying macOS specific security configurations..."
    xattr -d com.apple.quarantine "$INSTALL_DIR/$EXE_NAME" 2>/dev/null || true
fi
echo -e "      Installed successfully.\n"

# 6. Install the pppx.sh wrapper script, pointing it at the repo's table folder
echo -e "${CYAN}[5/6] Installing pppx.sh wrapper...${NC}"
sed "s|PACKAGE_ROOT|$PPPX_ROOT|" "$PPPX_SH_SRC" > "$INSTALL_DIR/pppx.sh"
chmod +x "$INSTALL_DIR/pppx.sh"
echo -e "      Configured table directory: ${BOLD}$TABLE_DIR${NC}"
echo -e "      Installed successfully.\n"

# 7. Check and Update PATH Variable
echo -e "${CYAN}[6/6] Checking Environment PATH...${NC}"
NEED_RESTART=false

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    # Determine the correct profile file based on the user's shell
    USER_SHELL=$(basename "$SHELL")
    if [ "$USER_SHELL" = "zsh" ]; then
        PROFILE_FILE="${HOME}/.zshrc"
    elif [ "$USER_SHELL" = "bash" ]; then
        PROFILE_FILE="${HOME}/.bashrc"
    else
        PROFILE_FILE="${HOME}/.profile"
    fi

    echo -e "      Adding $INSTALL_DIR to $PROFILE_FILE"
    echo "" >> "$PROFILE_FILE"
    echo "# Added by pppx installer" >> "$PROFILE_FILE"
    echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$PROFILE_FILE"
    NEED_RESTART=true
else
    echo -e "      Directory is already in your PATH."
fi

# 8. Clean up
rm -rf "$TMP_DIR"

echo -e "\n${GREEN}${BOLD}Installation complete!${NC}"
echo -e "Installed '${BOLD}pppx${NC}' and the wrapper '${BOLD}pppx.sh${NC}' to ${BOLD}$INSTALL_DIR${NC}."
echo -e "'${BOLD}pppx.sh${NC}' is configured to use the table files in ${BOLD}$TABLE_DIR${NC}."

if [ "$NEED_RESTART" = true ]; then
    echo -e "${YELLOW}NOTE: The installation directory was just added to your PATH.${NC}"
    echo -e "${YELLOW}Please restart your terminal or run the following command to use pppx:${NC}"
    echo -e "${BOLD}source $PROFILE_FILE${NC}"
else
    echo -e "You can now run '${BOLD}$EXE_NAME${NC}' from anywhere in your terminal."
fi
