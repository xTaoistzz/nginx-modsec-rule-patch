#!/bin/bash
set -e

# =============================================================================
# NGINX MODSECURITY3 INSTALLATION SCRIPT
# =============================================================================
# This script installs ModSecurity v3 WAF with OWASP Core Rule Set for Nginx
# Supports Nginx >= 1.9.11 (dynamic module support required)
# =============================================================================

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

log_header() {
    echo ""
    echo -e "${BLUE}${BOLD}=============================================================================${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}=============================================================================${NC}"
    echo ""
}

log_subheader() {
    echo ""
    echo -e "${CYAN}${BOLD}--- $1 ---${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BOLD}  ➜${NC} $1"
}

log_success() {
    echo -e "${GREEN}${BOLD}  ✔${NC} $1"
}

# -----------------------------------------------------------------------------
# VARIABLES
# -----------------------------------------------------------------------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
MODULE_PATH="/etc/nginx/modules"
SO_FILENAME="ngx_http_modsecurity_module.so"
NGINX_CONF="/etc/nginx/nginx.conf"
MODSEC_CONF_DIR="/etc/nginx/modsec"
MODSECURITY_VERSION="v3.0.12"

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

# Function to compare versions
vercomp () {
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

log_header "NGINX MODSECURITY3 INSTALLATION"
log_info "Script directory: $SCRIPT_DIR"
log_info "ModSecurity version: $MODSECURITY_VERSION"

# =============================================================================
# 1. VALIDATION
# =============================================================================
log_header "1. VALIDATION"

# Ensure script is run as root
log_step "Checking root privileges..."
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi
log_success "Running as root"

# Check Nginx installation
log_step "Checking Nginx installation..."
if ! command -v nginx &> /dev/null; then
    log_error "Nginx could not be found. Please install Nginx first."
    exit 1
fi
log_success "Nginx is installed"

# Extract version number (e.g., 1.18.0)
NGINX_VERSION=$(nginx -v 2>&1 | grep -oP 'nginx/\K([0-9.]*)')
log_info "Detected Nginx version: $NGINX_VERSION"

# Check Compatibility (>= 1.9.11)
log_step "Checking version compatibility (>= 1.9.11 required for dynamic modules)..."
vercomp "$NGINX_VERSION" "1.9.11" || VERSION_RESULT=$?
if [ "${VERSION_RESULT:-0}" -eq 2 ]; then
    log_error "Nginx version $NGINX_VERSION is older than 1.9.11"
    log_error "Dynamic modules are not supported. Exiting gracefully."
    exit 0
fi
log_success "Version check passed: $NGINX_VERSION >= 1.9.11"

# Create module directory if needed
log_step "Ensuring module directory exists..."
if [ ! -d "$MODULE_PATH" ]; then
    mkdir -p "$MODULE_PATH"
    log_success "Created $MODULE_PATH"
else
    log_success "Module directory exists: $MODULE_PATH"
fi

# =============================================================================
# 2. LIBMODSECURITY COMPILATION
# =============================================================================
log_header "2. LIBMODSECURITY COMPILATION"

export DEBIAN_FRONTEND=noninteractive

# Clean up old apt versions
log_subheader "Cleaning up existing apt packages"
log_step "Checking for existing apt-installed libmodsecurity3..."
if dpkg -l | grep -q libmodsecurity; then
    log_warn "Found apt-installed libmodsecurity packages"
    log_step "Removing to avoid conflicts..."
    apt-get remove -y libmodsecurity3 libmodsecurity-dev 2>/dev/null || true
    apt-get purge -y libmodsecurity3 libmodsecurity-dev 2>/dev/null || true
    apt-get autoremove -y
    log_success "Removed apt packages"
else
    log_success "No apt libmodsecurity packages found"
fi

# Install dependencies
log_subheader "Installing build dependencies"
log_step "Updating package lists..."
apt-get update -qq
log_step "Installing required packages..."
apt-get install -y -qq git build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev \
    libtool autoconf automake pkg-config libcurl4-openssl-dev libgeoip-dev \
    liblmdb-dev libxml2-dev libyajl-dev wget
log_success "Build dependencies installed"

# Compile ModSecurity
log_subheader "Compiling ModSecurity $MODSECURITY_VERSION"
cd /usr/local/src

log_step "Cleaning up previous source directory..."
if [ -d "ModSecurity" ]; then
    rm -rf ModSecurity
    log_success "Removed existing ModSecurity source"
fi

log_step "Cloning ModSecurity repository..."
git clone --depth 1 -b $MODSECURITY_VERSION https://github.com/owasp-modsecurity/ModSecurity.git
cd ModSecurity

log_step "Initializing submodules..."
git submodule init
git submodule update
log_success "Submodules initialized"

log_step "Running build.sh..."
./build.sh

log_step "Configuring ModSecurity..."
./configure

log_step "Compiling ModSecurity (this may take a while)..."
make -j$(nproc)

log_step "Installing ModSecurity..."
make install
log_success "ModSecurity installed to /usr/local/modsecurity/"

log_step "Updating library cache..."
ldconfig
log_success "Library cache updated"

cd /usr/local/src

# =============================================================================
# 3. NGINX CONNECTOR COMPILATION
# =============================================================================
log_header "3. NGINX CONNECTOR COMPILATION"

# Set environment variables
export MODSECURITY_INC="/usr/local/modsecurity/include"
export MODSECURITY_LIB="/usr/local/modsecurity/lib"
log_info "MODSECURITY_INC: $MODSECURITY_INC"
log_info "MODSECURITY_LIB: $MODSECURITY_LIB"

# Download Nginx Source
log_subheader "Downloading Nginx source"
log_step "Cleaning up previous Nginx source..."
if [ -f "nginx-$NGINX_VERSION.tar.gz" ]; then
    rm -f "nginx-$NGINX_VERSION.tar.gz"
fi
if [ -d "nginx-$NGINX_VERSION" ]; then
    rm -rf "nginx-$NGINX_VERSION"
fi

log_step "Downloading Nginx $NGINX_VERSION source..."
wget -q "http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"
log_success "Downloaded nginx-$NGINX_VERSION.tar.gz"

log_step "Extracting Nginx source..."
tar -zxf "nginx-$NGINX_VERSION.tar.gz"
log_success "Extracted Nginx source"

# Clone ModSecurity-nginx Connector
log_subheader "Cloning ModSecurity-nginx connector"
log_step "Cleaning up previous connector source..."
if [ -d "ModSecurity-nginx" ]; then
    rm -rf ModSecurity-nginx
fi

log_step "Cloning ModSecurity-nginx connector..."
git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git
log_success "Cloned ModSecurity-nginx connector"

# Build the module
log_subheader "Building dynamic module"
cd "nginx-$NGINX_VERSION"

log_step "Configuring Nginx module (--with-compat)..."
./configure --with-compat --add-dynamic-module=../ModSecurity-nginx

log_step "Compiling dynamic module..."
make modules
log_success "Module compiled successfully"

log_step "Installing compiled module to $MODULE_PATH..."
cp objs/$SO_FILENAME "$MODULE_PATH/$SO_FILENAME"
log_success "Module installed: $MODULE_PATH/$SO_FILENAME"

cd "$SCRIPT_DIR"

# =============================================================================
# 4. MODSECURITY & OWASP CORE RULE SET CONFIGURATION
# =============================================================================
log_header "4. MODSECURITY & OWASP CORE RULE SET CONFIGURATION"

# Ensure library path is configured
log_subheader "Configuring library path"
if ! grep -q "/usr/local/modsecurity/lib" /etc/ld.so.conf.d/*.conf 2>/dev/null; then
    log_step "Adding ModSecurity library path to ld.so.conf.d..."
    echo "/usr/local/modsecurity/lib" > /etc/ld.so.conf.d/modsecurity.conf
    ldconfig
    log_success "Library path configured"
else
    log_success "Library path already configured"
fi

# Configure nginx.conf
log_subheader "Configuring Nginx"
if [ -f "$NGINX_CONF" ]; then
    # Add load_module directive
    if ! grep -q "$SO_FILENAME" "$NGINX_CONF"; then
        log_step "Adding load_module directive to $NGINX_CONF..."
        sed -i "1i load_module $MODULE_PATH/$SO_FILENAME;" "$NGINX_CONF"
        log_success "load_module directive added"
    else
        log_success "load_module directive already present"
    fi
    
    # Add modsecurity directives to http block
    if ! grep -q "modsecurity on;" "$NGINX_CONF"; then
        log_step "Adding modsecurity directives to http block..."
        sed -i '/http[[:space:]]*{/a\    modsecurity on;\n    modsecurity_rules_file /etc/nginx/modsec/main.conf;' "$NGINX_CONF"
        log_success "modsecurity directives added to http block"
    else
        log_success "modsecurity directives already present in http block"
    fi
else
    log_warn "$NGINX_CONF not found. Skipping Nginx configuration."
fi

# Create ModSecurity config directory
log_subheader "Setting up ModSecurity configuration files"
log_step "Creating config directory $MODSEC_CONF_DIR..."
mkdir -p $MODSEC_CONF_DIR
log_success "Config directory created"

# Download recommended config
log_step "Downloading recommended ModSecurity config..."
wget -q https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended -O $MODSEC_CONF_DIR/modsecurity.conf
log_success "Downloaded modsecurity.conf"

log_step "Downloading unicode.mapping..."
wget -q https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping -O $MODSEC_CONF_DIR/unicode.mapping
log_success "Downloaded unicode.mapping"

# Enable Rule Engine
log_step "Enabling SecRuleEngine..."
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' $MODSEC_CONF_DIR/modsecurity.conf
log_success "SecRuleEngine enabled"

# Clone OWASP CRS
log_subheader "Setting up OWASP Core Rule Set"
if [ -d "$MODSEC_CONF_DIR/coreruleset" ]; then
    log_step "Removing existing coreruleset directory..."
    rm -rf $MODSEC_CONF_DIR/coreruleset
fi

log_step "Cloning OWASP Core Rule Set..."
git clone -q --depth 1 https://github.com/coreruleset/coreruleset $MODSEC_CONF_DIR/coreruleset
log_success "OWASP CRS cloned"

log_step "Creating crs-setup.conf..."
cp $MODSEC_CONF_DIR/coreruleset/crs-setup.conf.example $MODSEC_CONF_DIR/coreruleset/crs-setup.conf
log_success "crs-setup.conf created"

# Create main.conf
log_step "Creating main.conf..."
cat > $MODSEC_CONF_DIR/main.conf <<EOF
# =============================================================================
# ModSecurity Main Configuration
# =============================================================================

# 1. Include the Base Configuration
Include $MODSEC_CONF_DIR/modsecurity.conf

# 2. Include the OWASP CRS Setup
Include $MODSEC_CONF_DIR/coreruleset/crs-setup.conf

# 3. Include the OWASP Rules
Include $MODSEC_CONF_DIR/coreruleset/rules/*.conf
EOF
log_success "main.conf created"

# Add UTF-8 support
log_step "Adding UTF-8 support configuration..."
tee -a $MODSEC_CONF_DIR/coreruleset/crs-setup.conf > /dev/null <<'EOF'

# UTF-8 Encoding Support
SecAction \
 "id:900220,\
 phase:1,\
 pass,\
 t:none,\
 nolog,\
 tag:'OWASP_CRS',\
 ver:'OWASP_CRS/4.21.0-dev',\
 setvar:'tx.allowed_request_content_type=|application/x-www-form-urlencoded| |multipart/form-data| |text/xml| |application/xml| |application/soap+xml| |application/json| |application/reports+json| |application/csp-report|',\
 setvar:tx.crs_validate_utf8_encoding=1"
EOF
log_success "UTF-8 support configured"

# =============================================================================
# INSTALLATION COMPLETE
# =============================================================================
log_header "INSTALLATION COMPLETE"

echo -e "${GREEN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════════════════════╗"
echo "  ║                    ModSecurity Installation Complete!                      ║"
echo "  ╠═══════════════════════════════════════════════════════════════════════════╣"
echo "  ║  ModSecurity Version : $MODSECURITY_VERSION                                           ║"
echo "  ║  Nginx Version       : $NGINX_VERSION                                             ║"
echo "  ║  Module Path         : $MODULE_PATH/$SO_FILENAME      ║"
echo "  ║  Config Directory    : $MODSEC_CONF_DIR                                  ║"
echo "  ╠═══════════════════════════════════════════════════════════════════════════╣"
echo "  ║  NEXT STEPS:                                                              ║"
echo "  ║  1. Verify configuration:  nginx -t                                       ║"
echo "  ║  2. Reload Nginx:          nginx -s reload                                ║"
echo "  ╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"