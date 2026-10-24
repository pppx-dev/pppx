#!/usr/bin/env bash
#
# PPPx installer for Linux, macOS and Windows.
#
#   One-line install (Linux / macOS terminal, or Git Bash / MSYS2 on Windows):
#     curl -fsSL https://raw.githubusercontent.com/pppx-dev/pppx/main/install.sh | bash
#
#   From a cloned repository, ./install.sh uses the local table and scripts folders.
#
#   Advanced: set PPPX_HOME to change the installation folder
#     (default: ~/.pppx, or %LOCALAPPDATA%\Programs\PPPx on Windows)
#
# Layout:
#   $PPPX_HOME/bin      pppx, pppx.sh, and other scripts (and DLLs on Windows)  <- added to PATH
#   $PPPX_HOME/table    table files used by pppx.sh
#   $PPPX_HOME/VERSION  installed release and table commit
#

# The whole installer lives in main() so a truncated download never runs half a script
main() {

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
# Branch that the table files and scripts are fetched from
BRANCH="main"
# Used only if the latest release does not ship its own Windows DLL bundle
DLL_FALLBACK_URL="https://github.com/$REPO/releases/download/v1.2.1/pppx_windows_dlls.zip"

# Local mode when run from a cloned repository, remote mode when piped from curl
SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/scripts/pppx.sh" ] && [ -d "$SCRIPT_DIR/table" ]; then
        SRC_DIR="$SCRIPT_DIR"
    fi
fi

echo -e "${CYAN}${BOLD}==========================================${NC}"
echo -e "${CYAN}${BOLD}       PPPx Automated Installer           ${NC}"
echo -e "${CYAN}${BOLD}==========================================${NC}\n"

echo -e "${CYAN}[1/6] Detecting System Environment...${NC}"
# 1. Detect Operating System
case "$(uname -s)" in
    Linux*)               OS="linux" ;;
    Darwin*)              OS="macos" ;;
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    *)
        echo -e "${RED}Error: Unsupported OS '$(uname -s)'. Supported: Linux, macOS and Windows (Git Bash or MSYS2).${NC}"
        exit 1
        ;;
esac

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

# 3. Platform-specific settings
if [ "$OS" = "windows" ]; then
    EXE_NAME="pppx.exe"
    if [ -z "$LOCALAPPDATA" ]; then
        echo -e "${RED}Error: LOCALAPPDATA is not set. Please run this script from Git Bash.${NC}"
        exit 1
    fi
    PPPX_HOME="${PPPX_HOME:-$(cygpath -u "$LOCALAPPDATA")/Programs/PPPx}"
else
    EXE_NAME="pppx"
    PPPX_HOME="${PPPX_HOME:-${HOME}/.pppx}"
fi
BIN_DIR="$PPPX_HOME/bin"

echo -e "      OS:     ${BOLD}$OS${NC}"
echo -e "      Arch:   ${BOLD}$ARCH${NC}"
echo -e "      Target: ${BOLD}$PPPX_HOME${NC}"
if [ -n "$SRC_DIR" ]; then
    echo -e "      Source: ${BOLD}local repository ($SRC_DIR)${NC}\n"
else
    echo -e "      Source: ${BOLD}github.com/$REPO ($BRANCH)${NC}\n"
fi

# Verify required tools
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: 'curl' is not installed.${NC}"
    exit 1
fi
if ! command -v unzip &> /dev/null && [ "$OS" != "windows" ]; then
    echo -e "${RED}Error: 'unzip' is not installed.${NC}"
    echo -e "Please install it using your system's package manager (e.g., 'sudo apt install unzip') and run this script again."
    exit 1
fi

# Extract a zip archive: unzip if available, otherwise PowerShell on Windows
extract_zip() {
    if command -v unzip &> /dev/null; then
        unzip -q -o "$1" -d "$2"
    else
        powershell.exe -NoProfile -Command \
            "Expand-Archive -Path '$(cygpath -w "$1")' -DestinationPath '$(cygpath -w "$2")' -Force" < /dev/null
    fi
}

# Git blob SHA-1 of a file, comparable with the "sha" field of the GitHub contents API
git_blob_sha() {
    local sha1="sha1sum"
    command -v sha1sum &> /dev/null || sha1="shasum -a 1"
    { printf 'blob %s\0' "$(wc -c < "$1" | tr -d ' ')"; cat "$1"; } | $sha1 | cut -d ' ' -f 1
}

# 4. Fetch the latest release download URL from GitHub API
echo -e "${CYAN}[2/6] Fetching Latest Release...${NC}"
if ! LATEST_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest"); then
    echo -e "${RED}Error: Could not reach the GitHub API.${NC}"
    exit 1
fi
RELEASE_TAG=$(echo "$LATEST_JSON" | grep -m 1 '"tag_name":' | cut -d '"' -f 4)
ASSET_URLS=$(echo "$LATEST_JSON" | grep '"browser_download_url":' | cut -d '"' -f 4)

# Search for the zip asset that matches the OS and Architecture
DOWNLOAD_URL=$(echo "$ASSET_URLS" | grep -i "pppx.*${OS}-${ARCH}\.zip$" | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}Error: Could not find a matching release asset for $OS $ARCH.${NC}"
    echo -e "Please download and install manually from: https://github.com/$REPO/releases/latest"
    exit 1
fi
echo -e "      Release: ${BOLD}$RELEASE_TAG${NC}"
echo -e "      Found:   ${DOWNLOAD_URL##*/}"

if [ "$OS" = "windows" ]; then
    DLL_URL=$(echo "$ASSET_URLS" | grep -i "pppx_windows_dlls\.zip$" | head -n 1)
    DLL_URL="${DLL_URL:-$DLL_FALLBACK_URL}"
    echo -e "      DLLs:    ${DLL_URL##*/}"
fi

# Pin the table files and scripts to one commit, so all files come from the same snapshot
if [ -n "$SRC_DIR" ]; then
    REF_SHA=$(git -C "$SRC_DIR" rev-parse --short HEAD 2>/dev/null || true)
    if [ -n "$REF_SHA" ] && ! git -C "$SRC_DIR" diff --quiet HEAD -- table scripts 2>/dev/null; then
        REF_SHA="$REF_SHA (with local changes)"
    fi
    TABLE_SOURCE="local ${SRC_DIR}${REF_SHA:+ @ $REF_SHA}"
else
    REF_SHA=$(curl -fsSL -H "Accept: application/vnd.github.sha" "https://api.github.com/repos/$REPO/commits/$BRANCH" || true)
    if ! [[ "$REF_SHA" =~ ^[0-9a-f]{40}$ ]]; then
        echo -e "${RED}Error: Could not resolve '$BRANCH' in $REPO.${NC}"
        exit 1
    fi
    RAW_BASE="https://raw.githubusercontent.com/$REPO/$REF_SHA"
    TABLE_SOURCE="$REPO $BRANCH @ ${REF_SHA:0:7}"
fi
echo -e "      Tables:  ${TABLE_SOURCE}"
echo ""

# 5. Download and Extract to a temporary directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR" "$PPPX_HOME/table.new"' EXIT

echo -e "${CYAN}[3/6] Installing pppx to $BIN_DIR...${NC}"
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/release.zip"
mkdir -p "$TMP_DIR/release"
extract_zip "$TMP_DIR/release.zip" "$TMP_DIR/release"

# Find the executable
EXTRACTED_EXE=$(find "$TMP_DIR/release" -type f -name "$EXE_NAME" | head -n 1)
if [ -z "$EXTRACTED_EXE" ]; then
    echo -e "${RED}Error: Could not find the '$EXE_NAME' executable inside the downloaded archive.${NC}"
    exit 1
fi

if [ "$OS" = "windows" ]; then
    curl -fsSL "$DLL_URL" -o "$TMP_DIR/dlls.zip"
    mkdir -p "$TMP_DIR/dlls"
    extract_zip "$TMP_DIR/dlls.zip" "$TMP_DIR/dlls"
fi

mkdir -p "$BIN_DIR"
cp -f "$EXTRACTED_EXE" "$BIN_DIR/$EXE_NAME"
chmod +x "$BIN_DIR/$EXE_NAME"

if [ "$OS" = "windows" ]; then
    DLL_COUNT=0
    while IFS= read -r -d '' dll; do
        cp -f "$dll" "$BIN_DIR/"
        DLL_COUNT=$((DLL_COUNT + 1))
    done < <(find "$TMP_DIR/dlls" -type f -iname '*.dll' -print0)
    if [ "$DLL_COUNT" -gt 0 ]; then
        echo -e "      Installed $DLL_COUNT DLLs."
    else
        echo -e "${YELLOW}      Warning: No DLLs found in the downloaded zip.${NC}"
    fi
fi

# macOS Quarantine bypass
if [ "$OS" = "macos" ]; then
    echo -e "      Applying macOS specific security configurations..."
    xattr -d com.apple.quarantine "$BIN_DIR/$EXE_NAME" 2>/dev/null || true

    # pppx links against Homebrew's ceres-solver; install (or upgrade) it if pppx cannot load it
    if ! "$BIN_DIR/$EXE_NAME" -h > /dev/null 2> "$TMP_DIR/dyld.err" && grep -q "Library not loaded" "$TMP_DIR/dyld.err"; then
        BREW=$(command -v brew || ls /opt/homebrew/bin/brew /usr/local/bin/brew 2>/dev/null | head -n 1 || true)
        if [ -n "$BREW" ]; then
            echo -e "      Installing ceres-solver with Homebrew (this may take a while)..."
            "$BREW" install ceres-solver < /dev/null || true
        fi
        if ! "$BIN_DIR/$EXE_NAME" -h > /dev/null 2>&1; then
            echo -e "${YELLOW}      Warning: pppx cannot load its libraries (ceres-solver).${NC}"
            if [ -z "$BREW" ]; then
                echo -e "${YELLOW}      Homebrew is not installed. Install it from https://brew.sh, then run:${NC}"
            else
                echo -e "${YELLOW}      Please run:${NC}"
            fi
            echo -e "${BOLD}        brew install ceres-solver${NC}"
        fi
    fi
fi
echo -e "      Installed successfully.\n"

# 6. Install the table files. Changed files are staged first, so a failed download
#    keeps the old tables; files that are already up to date are not downloaded again.
echo -e "${CYAN}[4/6] Installing table files to $PPPX_HOME/table...${NC}"
STAGE_DIR="$PPPX_HOME/table.new"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$PPPX_HOME/table"
if [ -n "$SRC_DIR" ]; then
    cp -R "$SRC_DIR/table/." "$STAGE_DIR/"
else
    if ! TABLE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/contents/table?ref=$REF_SHA"); then
        echo -e "${RED}Error: Could not list the table files of $REPO ($BRANCH).${NC}"
        exit 1
    fi
    # One "sha" and one "download_url" per entry (null for folders), in the same order
    TABLE_SHAS=$(echo "$TABLE_JSON" | grep '"sha":' | cut -d '"' -f 4)
    TABLE_URLS=$(echo "$TABLE_JSON" | grep '"download_url":' | cut -d '"' -f 4)
    TABLE_COUNT=0
    while read -r sha url; do
        [ -z "$url" ] && continue
        name="${url##*/}"
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ -f "$PPPX_HOME/table/$name" ] && [ "$(git_blob_sha "$PPPX_HOME/table/$name")" = "$sha" ]; then
            echo -e "      Up to date:  $name"
        else
            echo -e "      Downloading: $name"
            curl -fsSL "$url" -o "$STAGE_DIR/$name"
        fi
    done < <(paste -d ' ' <(echo "$TABLE_SHAS") <(echo "$TABLE_URLS"))
    if [ "$TABLE_COUNT" -eq 0 ]; then
        echo -e "${RED}Error: No table files found in $REPO ($BRANCH).${NC}"
        exit 1
    fi
fi
UPDATED_COUNT=0
for f in "$STAGE_DIR"/*; do
    [ -f "$f" ] || continue
    mv -f "$f" "$PPPX_HOME/table/"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
done
echo -e "      Updated $UPDATED_COUNT of $(ls "$PPPX_HOME/table" | wc -l | tr -d ' ') table files.\n"

# 7. Install the pppx.sh wrapper and auxiliary scripts
echo -e "${CYAN}[5/6] Installing scripts to $BIN_DIR...${NC}"
for script in pppx.sh plot_ppppos.py; do
    if [ -n "$SRC_DIR" ]; then
        cp -f "$SRC_DIR/scripts/$script" "$TMP_DIR/$script"
    else
        curl -fsSL "$RAW_BASE/scripts/$script" -o "$TMP_DIR/$script"
    fi
    mv -f "$TMP_DIR/$script" "$BIN_DIR/$script"
    chmod +x "$BIN_DIR/$script"
    echo -e "      Installed $script"
done
echo ""

{
    echo "release: $RELEASE_TAG"
    echo "tables:  $TABLE_SOURCE"
    echo "date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "$PPPX_HOME/VERSION"

# Remove files left by the previous installer layout, so they do not shadow the new ones
OLD_FILES=()
if [ "$OS" = "windows" ]; then
    for f in "$PPPX_HOME/pppx.exe" "$PPPX_HOME/pppx.sh" "$PPPX_HOME"/*.dll; do
        [ -f "$f" ] && OLD_FILES+=("$f")
    done
elif [ "$BIN_DIR" != "${HOME}/.local/bin" ]; then
    [ -f "${HOME}/.local/bin/pppx" ] && OLD_FILES+=("${HOME}/.local/bin/pppx")
    grep -qs "GNSS data processing with PPPx" "${HOME}/.local/bin/pppx.sh" && OLD_FILES+=("${HOME}/.local/bin/pppx.sh")
fi
if [ "${#OLD_FILES[@]}" -gt 0 ]; then
    echo -e "${YELLOW}      Removing files from a previous installation:${NC}"
    for f in "${OLD_FILES[@]}"; do
        echo -e "        $f"
        rm -f "$f"
    done
    echo ""
fi

# 8. Check and Update PATH Variable
echo -e "${CYAN}[6/6] Checking Environment PATH...${NC}"
NEED_RESTART=false

if [ "$OS" = "windows" ]; then
    # Update the Windows user PATH so pppx works in PowerShell, cmd.exe and Git Bash.
    # The old layout put PPPX_HOME itself on PATH; that entry is replaced by PPPX_HOME\bin.
    WIN_BIN_DIR="$(cygpath -w "$BIN_DIR")"
    WIN_OLD_DIR="$(cygpath -w "$PPPX_HOME")"
    PATH_RESULT=$(PPPX_DIR="$WIN_BIN_DIR" PPPX_OLD_DIR="$WIN_OLD_DIR" powershell.exe -NoProfile -Command '
        $dir  = $env:PPPX_DIR
        $old  = $env:PPPX_OLD_DIR
        $path = [Environment]::GetEnvironmentVariable("PATH", "User")
        $parts = @(); if ($path) { $parts = @($path -split ";" | Where-Object { $_ }) }
        $kept = @($parts | Where-Object { $_ -ne $old })
        if (($kept -contains $dir) -and ($kept.Count -eq $parts.Count)) { "present" } else {
            if (-not ($kept -contains $dir)) { $kept += $dir }
            [Environment]::SetEnvironmentVariable("PATH", ($kept -join ";"), "User")
            "added"
        }' < /dev/null | tr -d '\r')
    # printf '%s' rather than echo -e: Windows paths contain backslashes ("\bin" would print a backspace)
    if [ "$PATH_RESULT" = "added" ]; then
        printf "      Added %s to your user PATH.\n" "$WIN_BIN_DIR"
        NEED_RESTART=true
    elif [ "$PATH_RESULT" = "present" ]; then
        echo -e "      Directory is already in your PATH."
    else
        printf "${YELLOW}      Warning: Could not update PATH. Please add %s to your user PATH manually.${NC}\n" "$WIN_BIN_DIR"
    fi
fi

# Shell profile, also on Windows: MSYS2 does not inherit the Windows user PATH by default
# Determine the correct profile file based on the user's shell
USER_SHELL=$(basename "${SHELL:-sh}")
if [ "$USER_SHELL" = "zsh" ]; then
    PROFILE_FILE="${HOME}/.zshrc"
elif [ "$USER_SHELL" = "bash" ] && [ "$OS" = "macos" ]; then
    PROFILE_FILE="${HOME}/.bash_profile"
    for f in "${HOME}/.bash_profile" "${HOME}/.bash_login" "${HOME}/.profile"; do
        [ -f "$f" ] && PROFILE_FILE="$f" && break
    done
elif [ "$USER_SHELL" = "bash" ]; then
    PROFILE_FILE="${HOME}/.bashrc"
else
    PROFILE_FILE="${HOME}/.profile"
fi

PATH_LINE="export PATH=\"$BIN_DIR:\$PATH\""
if grep -qsF "$PATH_LINE" "$PROFILE_FILE"; then
    echo -e "      $BIN_DIR is already set in $PROFILE_FILE."
else
    echo -e "      Adding $BIN_DIR to $PROFILE_FILE"
    echo "" >> "$PROFILE_FILE"
    echo "# Added by pppx installer" >> "$PROFILE_FILE"
    echo "$PATH_LINE" >> "$PROFILE_FILE"
    NEED_RESTART=true
fi

echo -e "\n${GREEN}${BOLD}Installation complete!${NC}"
echo -e "Installed PPPx ${BOLD}$RELEASE_TAG${NC} to ${BOLD}$PPPX_HOME${NC}:"
echo -e "  bin/      ${BOLD}$EXE_NAME${NC} and auxiliary scripts (on your PATH)"
echo -e "  table/    table files used by pppx.sh"
echo -e "Update:        re-run the installer"
echo -e "Uninstall:     remove ${BOLD}$PPPX_HOME${NC} and its PATH entry"
echo -e "Examples:      ${BOLD}https://github.com/$REPO/tree/$BRANCH/example${NC}"
echo -e "Documentation: ${BOLD}https://pppx.dev/docs${NC}"

if [ "$NEED_RESTART" = true ]; then
    echo -e "${YELLOW}NOTE: The installation directory was just added to your PATH.${NC}"
    if [ "$OS" = "windows" ]; then
        echo -e "${YELLOW}Please close and reopen Git Bash, MSYS2, PowerShell or cmd.exe to use pppx.${NC}"
    else
        echo -e "${YELLOW}Please restart your terminal or run the following command to use pppx:${NC}"
        echo -e "${BOLD}source $PROFILE_FILE${NC}"
    fi
else
    echo -e "You can now run '${BOLD}pppx${NC}' from anywhere in your terminal."
fi

}

main "$@"
