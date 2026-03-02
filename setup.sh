#!/bin/bash

# =============================================================================
# CVR - Cloud Video Recorder
# Script cài đặt tự động cho lần đầu chạy dự án
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Versions
ERLANG_VERSION="27.0"
ELIXIR_VERSION="1.18.0-otp-27"
ASDF_VERSION="v0.14.0"

# =============================================================================
# Helper functions
# =============================================================================

print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# Main installation steps
# =============================================================================

install_system_dependencies() {
    print_header "Cài đặt system dependencies"
    
    if check_command apt-get; then
        print_info "Detected Debian/Ubuntu system"
        sudo apt-get update
        sudo apt-get install -y \
            build-essential \
            autoconf \
            m4 \
            libncurses5-dev \
            libwxgtk3.2-dev \
            libwxgtk-webview3.2-dev \
            libgl1-mesa-dev \
            libglu1-mesa-dev \
            libpng-dev \
            libssh-dev \
            unixodbc-dev \
            xsltproc \
            fop \
            libxml2-utils \
            libncurses-dev \
            openjdk-17-jdk \
            curl \
            git \
            inotify-tools \
            ffmpeg \
            libavcodec-dev \
            libavformat-dev \
            libavutil-dev \
            libswscale-dev \
            libavdevice-dev \
            pkg-config
        print_success "System dependencies installed"
    elif check_command dnf; then
        print_info "Detected Fedora/RHEL system"
        sudo dnf install -y \
            gcc \
            gcc-c++ \
            make \
            autoconf \
            ncurses-devel \
            wxGTK3-devel \
            openssl-devel \
            java-17-openjdk-devel \
            libiodbc \
            curl \
            git \
            inotify-tools \
            ffmpeg \
            ffmpeg-devel
        print_success "System dependencies installed"
    elif check_command pacman; then
        print_info "Detected Arch Linux system"
        sudo pacman -Syu --noconfirm \
            base-devel \
            ncurses \
            openssl \
            jdk17-openjdk \
            curl \
            git \
            inotify-tools \
            ffmpeg
        print_success "System dependencies installed"
    else
        print_error "Unsupported package manager. Please install dependencies manually."
        exit 1
    fi
}

install_asdf() {
    print_header "Cài đặt asdf version manager"
    
    if [ -d "$HOME/.asdf" ]; then
        print_warning "asdf đã được cài đặt, bỏ qua..."
    else
        print_info "Đang clone asdf..."
        git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch "$ASDF_VERSION"
        print_success "asdf đã được cài đặt"
    fi
    
    # Add asdf to shell config if not already present
    SHELL_CONFIG=""
    if [ -f "$HOME/.bashrc" ]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [ -f "$HOME/.zshrc" ]; then
        SHELL_CONFIG="$HOME/.zshrc"
    fi
    
    if [ -n "$SHELL_CONFIG" ]; then
        if ! grep -q "asdf.sh" "$SHELL_CONFIG" 2>/dev/null; then
            echo '' >> "$SHELL_CONFIG"
            echo '# asdf version manager' >> "$SHELL_CONFIG"
            echo '. "$HOME/.asdf/asdf.sh"' >> "$SHELL_CONFIG"
            echo '. "$HOME/.asdf/completions/asdf.bash"' >> "$SHELL_CONFIG"
            print_success "Đã thêm asdf vào $SHELL_CONFIG"
        fi
    fi
    
    # Source asdf for current session
    export ASDF_DIR="$HOME/.asdf"
    . "$HOME/.asdf/asdf.sh"
}

install_erlang() {
    print_header "Cài đặt Erlang $ERLANG_VERSION"
    
    # Add erlang plugin if not present
    if ! asdf plugin list 2>/dev/null | grep -q erlang; then
        print_info "Thêm erlang plugin..."
        asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
    fi
    
    # Check if version already installed
    if asdf list erlang 2>/dev/null | grep -q "$ERLANG_VERSION"; then
        print_warning "Erlang $ERLANG_VERSION đã được cài đặt, bỏ qua..."
    else
        print_info "Đang cài đặt Erlang $ERLANG_VERSION (có thể mất 15-30 phút)..."
        asdf install erlang "$ERLANG_VERSION"
        print_success "Erlang $ERLANG_VERSION đã được cài đặt"
    fi
    
    asdf global erlang "$ERLANG_VERSION"
    print_success "Erlang $ERLANG_VERSION đã được đặt làm phiên bản mặc định"
}

install_elixir() {
    print_header "Cài đặt Elixir $ELIXIR_VERSION"
    
    # Add elixir plugin if not present
    if ! asdf plugin list 2>/dev/null | grep -q elixir; then
        print_info "Thêm elixir plugin..."
        asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
    fi
    
    # Check if version already installed
    if asdf list elixir 2>/dev/null | grep -q "$ELIXIR_VERSION"; then
        print_warning "Elixir $ELIXIR_VERSION đã được cài đặt, bỏ qua..."
    else
        print_info "Đang cài đặt Elixir $ELIXIR_VERSION..."
        asdf install elixir "$ELIXIR_VERSION"
        print_success "Elixir $ELIXIR_VERSION đã được cài đặt"
    fi
    
    asdf global elixir "$ELIXIR_VERSION"
    print_success "Elixir $ELIXIR_VERSION đã được đặt làm phiên bản mặc định"
}

install_hex_rebar() {
    print_header "Cài đặt Hex và Rebar"
    
    print_info "Cài đặt Hex package manager..."
    mix local.hex --force
    
    print_info "Cài đặt Rebar3..."
    mix local.rebar --force
    
    print_success "Hex và Rebar đã được cài đặt"
}

setup_video_processor() {
    print_header "Setup video_processor"
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR/video_processor"
    
    print_info "Đang tải dependencies..."
    mix deps.get
    
    print_info "Đang compile..."
    mix compile
    
    print_success "video_processor đã được setup"
}

setup_ui() {
    print_header "Setup UI (Phoenix LiveView)"
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$SCRIPT_DIR/ui"
    
    print_info "Đang tải dependencies..."
    mix deps.get
    
    print_info "Đang setup assets..."
    mix assets.setup
    
    print_info "Đang compile..."
    mix compile
    
    print_success "UI đã được setup"
}

verify_installation() {
    print_header "Xác minh cài đặt"
    
    echo ""
    print_info "Erlang version:"
    erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
    
    echo ""
    print_info "Elixir version:"
    elixir --version
    
    echo ""
    print_info "FFmpeg version:"
    ffmpeg -version 2>&1 | head -n1
    
    print_success "Tất cả các thành phần đã được cài đặt thành công!"
}

print_final_instructions() {
    print_header "Hoàn tất!"
    
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              CVR đã được cài đặt thành công!                 ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Để chạy development server:${NC}"
    echo -e "  cd ui"
    echo -e "  mix phx.server"
    echo ""
    echo -e "${YELLOW}Truy cập:${NC} http://localhost:4000"
    echo ""
    echo -e "${YELLOW}Tài khoản mặc định:${NC}"
    echo -e "  Email: admin@localhost"
    echo -e "  Password: P@ssw0rd"
    echo ""
    echo -e "${BLUE}Lưu ý: Nếu bạn mới cài asdf, hãy mở terminal mới hoặc chạy:${NC}"
    echo -e "  source ~/.bashrc  # hoặc source ~/.zshrc"
    echo ""
}

# =============================================================================
# Main execution
# =============================================================================

main() {
    print_header "CVR - Cloud Video Recorder Setup"
    echo "Script này sẽ cài đặt tất cả các dependencies cần thiết."
    echo ""
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "Vui lòng không chạy script này với quyền root."
        print_info "Script sẽ yêu cầu sudo khi cần thiết."
        exit 1
    fi
    
    # Parse arguments
    SKIP_SYSTEM_DEPS=false
    SKIP_ASDF=false
    SKIP_ERLANG=false
    SKIP_ELIXIR=false
    SKIP_PROJECT=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-system-deps)
                SKIP_SYSTEM_DEPS=true
                shift
                ;;
            --skip-asdf)
                SKIP_ASDF=true
                shift
                ;;
            --skip-erlang)
                SKIP_ERLANG=true
                shift
                ;;
            --skip-elixir)
                SKIP_ELIXIR=true
                shift
                ;;
            --skip-project)
                SKIP_PROJECT=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-system-deps  Bỏ qua cài đặt system dependencies"
                echo "  --skip-asdf         Bỏ qua cài đặt asdf"
                echo "  --skip-erlang       Bỏ qua cài đặt Erlang"
                echo "  --skip-elixir       Bỏ qua cài đặt Elixir"
                echo "  --skip-project      Bỏ qua setup project dependencies"
                echo "  --help              Hiển thị hướng dẫn này"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run installation steps
    if [ "$SKIP_SYSTEM_DEPS" = false ]; then
        install_system_dependencies
    else
        print_warning "Bỏ qua cài đặt system dependencies"
    fi
    
    if [ "$SKIP_ASDF" = false ]; then
        install_asdf
    else
        print_warning "Bỏ qua cài đặt asdf"
        # Still need to source asdf if it exists
        if [ -f "$HOME/.asdf/asdf.sh" ]; then
            . "$HOME/.asdf/asdf.sh"
        fi
    fi
    
    if [ "$SKIP_ERLANG" = false ]; then
        install_erlang
    else
        print_warning "Bỏ qua cài đặt Erlang"
    fi
    
    if [ "$SKIP_ELIXIR" = false ]; then
        install_elixir
    else
        print_warning "Bỏ qua cài đặt Elixir"
    fi
    
    install_hex_rebar
    
    if [ "$SKIP_PROJECT" = false ]; then
        setup_video_processor
        setup_ui
    else
        print_warning "Bỏ qua setup project dependencies"
    fi
    
    verify_installation
    print_final_instructions
}

# Run main function
main "$@"
