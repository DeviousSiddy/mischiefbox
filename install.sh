#!/bin/bash
set -euo pipefail

# MischiefBox Installer
# Installs MischiefBox tool runner + Gitea on a Linux machine
# Usage: sudo ./install.sh

VERSION="1.0.0"
INSTALL_DIR="/opt/mischiefbox"
GITEA_PORT="${MB_GITEA_PORT:-3010}"
GITEA_SSH_PORT="${MB_GITEA_SSH_PORT:-3022}"
GITEA_DOMAIN="${MB_GITEA_DOMAIN:-$(hostname)}"
MB_USER="${MB_USER:-mischiefbox}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

# Check prerequisites
info "Checking prerequisites..."

# Check for Docker (supports Docker Desktop WSL integration)
DOCKER_FOUND=false
if command -v docker &>/dev/null; then
    DOCKER_FOUND=true
elif [[ -S "/var/run/docker.sock" ]]; then
    # Docker socket exists but binary might not be in PATH
    for dir in /usr/bin /usr/local/bin /opt/docker/bin; do
        if [[ -x "$dir/docker" ]]; then
            export PATH="$dir:$PATH"
            DOCKER_FOUND=true
            break
        fi
    done
fi

# Check Windows Docker Desktop paths (WSL2 integration)
if [[ "$DOCKER_FOUND" == "false" ]]; then
    WIN_DOCKER_DIRS=(
        "/mnt/c/Program Files/Docker/Docker/resources/bin"
        "/mnt/c/ProgramData/DockerDesktop/version-bin"
    )
    for dir in "${WIN_DOCKER_DIRS[@]}"; do
        if [[ -x "$dir/docker.exe" ]]; then
            # Create a wrapper script so 'docker' works from WSL
            mkdir -p /usr/local/bin
            cat > /usr/local/bin/docker << WRAPPER
#!/bin/bash
exec "$dir/docker.exe" "\$@"
WRAPPER
            chmod +x /usr/local/bin/docker
            export PATH="/usr/local/bin:$PATH"
            DOCKER_FOUND=true
            info "Found Docker Desktop at: $dir"
            break
        fi
    done
fi

# Last resort: try installing docker CLI package
if [[ "$DOCKER_FOUND" == "false" ]] && [[ -S "/var/run/docker.sock" ]]; then
    info "Docker socket found, installing docker CLI..."
    apt-get update -qq && apt-get install -y -qq docker.io >/dev/null 2>&1 || true
    if command -v docker &>/dev/null; then
        DOCKER_FOUND=true
    fi
fi

if [[ "$DOCKER_FOUND" == "false" ]]; then
    error "Docker not found. Install Docker Desktop for Windows with WSL2 integration enabled"
fi

if ! command -v python3 &>/dev/null; then
    error "Python 3 not found. Install Python 3.11+ first"
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
if [[ $(echo "$PYTHON_VERSION < 3.11" | bc -l) -eq 1 ]]; then
    error "Python 3.11+ required, found $PYTHON_VERSION"
fi

# Check Docker daemon (may need Docker Desktop running on Windows)
if ! docker info &>/dev/null; then
    warn "Docker daemon not responding. If using Docker Desktop:"
    warn "  1. Ensure Docker Desktop is running on Windows"
    warn "  2. Enable WSL2 integration in Docker Desktop settings"
    warn "Continuing installation anyway..."
fi

info "Prerequisites OK (Docker $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ','), Python $PYTHON_VERSION)"

# Create user if needed
if ! id -u "$MB_USER" &>/dev/null; then
    info "Creating user: $MB_USER"
    useradd -r -m -s /bin/bash -d "/home/$MB_USER" "$MB_USER"
    if getent group docker &>/dev/null; then
        usermod -aG docker "$MB_USER"
        info "User $MB_USER added to docker group (re-login required for group to take effect)"
    else
        info "Docker group not found (Docker Desktop WSL integration) - skipping group add"
    fi
fi

# Create directory structure
info "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{bin,secrets,tools,pipelines,.ssh}

# Copy files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

info "Installing MischiefBox files..."
cp "$SCRIPT_DIR/bin/mischiefbox" "$INSTALL_DIR/bin/"
cp "$SCRIPT_DIR/bin/mischiefboxlib.py" "$INSTALL_DIR/bin/"
cp "$SCRIPT_DIR/bin/mischiefbox-api" "$INSTALL_DIR/bin/"
cp "$SCRIPT_DIR/bin/mischiefbox-mcp" "$INSTALL_DIR/bin/"
chmod +x "$INSTALL_DIR/bin/mischiefbox" "$INSTALL_DIR/bin/mischiefbox-api" "$INSTALL_DIR/bin/mischiefbox-mcp"

# Install Gitea
info "Installing Gitea..."
cp "$SCRIPT_DIR/gitea/docker-compose.yml" "$INSTALL_DIR/gitea/"

# Install documentation
info "Installing documentation..."
mkdir -p "$INSTALL_DIR/docs"
if [[ -d "$SCRIPT_DIR/docs" ]]; then
    cp "$SCRIPT_DIR/docs/"*.md "$INSTALL_DIR/docs/"
    chown -R "$MB_USER:$MB_USER" "$INSTALL_DIR/docs"
    info "Documentation installed to $INSTALL_DIR/docs/"
else
    warn "No docs/ directory found in installer — MCP resources will not be available"
fi

# Set permissions
chown -R "$MB_USER:$MB_USER" "$INSTALL_DIR"
chmod 700 "$INSTALL_DIR/secrets"
chmod 700 "$INSTALL_DIR/.ssh"

# Install systemd service
info "Installing systemd service..."
cp "$SCRIPT_DIR/etc/mischiefbox-api.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable mischiefbox-api.service

# Generate SSH key pair for Gitea deploy key
DEPLOY_KEY="$INSTALL_DIR/.ssh/id_ed25519"
if [[ ! -f "$DEPLOY_KEY" ]]; then
    info "Generating Gitea deploy key..."
    sudo -u "$MB_USER" ssh-keygen -t ed25519 -f "$DEPLOY_KEY" -N "" -q
    chown "$MB_USER:$MB_USER" "$DEPLOY_KEY" "$DEPLOY_KEY.pub"
fi

# Create .env template
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
    info "Creating .env template..."
    cat > "$INSTALL_DIR/.env" << 'EOF'
# MischiefBox Environment Configuration
# Copy this file to .env and fill in your values

# Gitea configuration
MB_GITEA_URL=http://localhost:3010
MB_GITEA_SSH_HOST=localhost
MB_GITEA_SSH_PORT=3022
MB_GITEA_DOMAIN=localhost
MB_GITEA_PORT=3010
MB_GITEA_ORG=mischiefbox

# API configuration
MB_API_HOST=127.0.0.1
MB_API_PORT=8731

# Documentation directory (for MCP resources)
MB_DOCS_DIR=/opt/mischiefbox/docs

# Home directory
MB_HOME=/opt/mischiefbox
EOF
    chown "$MB_USER:$MB_USER" "$INSTALL_DIR/.env"
fi

# Create initial pipeline if pipelines dir is empty
PIPELINE_DIR="$INSTALL_DIR/pipelines/write-new-notepad"
if [[ ! -d "$PIPELINE_DIR" ]]; then
    info "Creating example pipeline: write-new-notepad"
    mkdir -p "$PIPELINE_DIR"
    cat > "$PIPELINE_DIR/pipeline.toml" << 'EOF'
[meta]
name = "write-new-notepad"
version = "0.1.0"
description = "open a new notepad window and type a message"

[meta.inputs.message]
type = "string"
required = true

[[steps]]
tool = "open-notepad"
args = ["--new"]

[[steps]]
tool = "get-focus"
args = ["--process", "notepad.exe", "--last"]

[[steps]]
tool = "key-writer"
args = ["--message", "{{message}}", "--noquotes"]
EOF
    chown -R "$MB_USER:$MB_USER" "$PIPELINE_DIR"
fi

# Create helper scripts
info "Creating helper scripts..."
cat > "$INSTALL_DIR/bin/mb" << 'EOF'
#!/bin/bash
# MischiefBox CLI wrapper
exec python3 /opt/mischiefbox/bin/mischiefbox "$@"
EOF
chmod +x "$INSTALL_DIR/bin/mb"

cat > "$INSTALL_DIR/bin/mb-api" << 'EOF'
#!/bin/bash
# Start MischiefBox API server
exec python3 /opt/mischiefbox/bin/mischiefbox-api "$@"
EOF
chmod +x "$INSTALL_DIR/bin/mb-api"

cat > "$INSTALL_DIR/bin/mb-mcp" << 'EOF'
#!/bin/bash
# Start MischiefBox MCP adapter
exec python3 /opt/mischiefbox/bin/mischiefbox-mcp "$@"
EOF
chmod +x "$INSTALL_DIR/bin/mb-mcp"

chown "$MB_USER:$MB_USER" "$INSTALL_DIR/bin/mb" "$INSTALL_DIR/bin/mb-api" "$INSTALL_DIR/bin/mb-mcp"

# Create symlinks in /usr/local/bin
info "Creating symlinks in /usr/local/bin..."
ln -sf "$INSTALL_DIR/bin/mb" /usr/local/bin/mb
ln -sf "$INSTALL_DIR/bin/mb-api" /usr/local/bin/mb-api
ln -sf "$INSTALL_DIR/bin/mb-mcp" /usr/local/bin/mb-mcp

echo ""
echo "============================================"
echo "MischiefBox v$VERSION installed successfully!"
echo "============================================"
echo ""

# Detect if running in WSL
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
fi

echo "Next steps:"
echo ""

if [[ "$IS_WSL" == "true" ]]; then
    echo "WSL2 detected - use these commands from PowerShell:"
    echo ""
    echo "1. Start Gitea:"
    echo "   wsl bash -c \"cd /opt/mischiefbox/gitea && sudo docker compose up -d\""
    echo ""
    echo "2. Complete Gitea setup:"
    echo "   - Open http://localhost:$GITEA_PORT in your browser"
    echo "   - Follow the installation wizard"
    echo "   - Create an organization named 'mischiefbox'"
    echo ""
    echo "3. Configure MischiefBox:"
    echo "   - Create a Gitea API token (Settings > Applications)"
    echo "   - Scopes: read:organization, read:repository, write:repository, write:organization"
    echo "   - Run: wsl bash -c \"mb token <your-token>\""
    echo ""
    echo "4. Start the API server:"
    echo "   wsl bash -c \"nohup mb-api > /tmp/mischiefbox-api.log 2>&1 &\""
    echo "   (or run in foreground: wsl bash -c \"mb-api\")"
    echo ""
    echo "5. Discover tools (after pushing tool repos to Gitea):"
    echo "   wsl bash -c \"mb refresh\""
    echo ""
    echo "6. Run a tool:"
    echo "   wsl bash -c \"mb list\""
    echo "   wsl bash -c \"mb run <tool-name> [args]\""
    echo ""
    echo "7. Connect to OpenCode (add to ~/.config/opencode/opencode.json):"
    echo "   {"
    echo "     \"mcp\": {"
    echo "       \"mischiefbox\": {"
    echo "         \"type\": \"local\","
    echo "         \"command\": [\"wsl\", \"bash\", \"-c\", \"/opt/mischiefbox/bin/mischiefbox-mcp\"],"
    echo "         \"enabled\": true"
    echo "       }"
    echo "     }"
    echo "   }"
    echo "   Then restart OpenCode. See docs/opencode-mcp-setup.md for details."
else
    echo "1. Start Gitea:"
    echo "   cd $INSTALL_DIR/gitea && docker compose up -d"
    echo ""
    echo "2. Complete Gitea setup:"
    echo "   - Open http://localhost:$GITEA_PORT in your browser"
    echo "   - Follow the installation wizard"
    echo "   - Create an organization named 'mischiefbox'"
    echo ""
    echo "3. Configure MischiefBox:"
    echo "   - Create a Gitea API token (Settings > Applications)"
    echo "   - Scopes: read:organization, read:repository, write:repository, write:organization"
    echo "   - Run: mischiefbox token <your-token>"
    echo ""
    echo "4. Start the API server:"
    echo "   systemctl start mischiefbox-api"
    echo ""
    echo "5. Discover tools (after pushing tool repos to Gitea):"
    echo "   mischiefbox refresh"
    echo ""
    echo "6. Run a tool:"
    echo "   mischiefbox list"
    echo "   mischiefbox run <tool-name> [args]"
    echo ""
    echo "7. Connect to OpenCode (add to ~/.config/opencode/opencode.json):"
    echo "   {"
    echo "     \"mcp\": {"
    echo "       \"mischiefbox\": {"
    echo "         \"type\": \"local\","
    echo "         \"command\": [\"/usr/local/bin/mb-mcp\"],"
    echo "         \"enabled\": true"
    echo "       }"
    echo "     }"
    echo "   }"
    echo "   Then restart OpenCode. See docs/opencode-mcp-setup.md for details."
fi

echo ""
echo "Documentation:"
echo "   $INSTALL_DIR/README.md"
echo "   $INSTALL_DIR/docs/opencode-mcp-setup.md"
echo ""
echo "MCP configuration:"
echo "  Claude Desktop, Cursor, Windsurf: /usr/local/bin/mb-mcp"
echo "  OpenCode: see docs/opencode-mcp-setup.md"
echo ""
