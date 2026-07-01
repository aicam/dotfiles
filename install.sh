#!/bin/bash
# Install the dotfiles: detect the package manager, install dependencies, symlink
# configs and bin commands, and build the vendored Go tools.
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up dotfiles from $DIR..."

# Create necessary directories
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.bashrc.d"
mkdir -p "$HOME/.local/bin"

# Create a symlink, backing up any existing non-symlink target to .bak.
create_symlink() {
    local source=$1
    local target=$2

    if [ -L "$target" ]; then
        if [ "$(readlink "$target")" = "$source" ]; then
            echo "Symlink for $(basename "$target") already exists."
        else
            echo "Symlink for $(basename "$target") points to a different location. Updating..."
            ln -sfn "$source" "$target"
        fi
    elif [ -e "$target" ]; then
        echo "Backing up existing $(basename "$target") to ${target}.bak..."
        mv "$target" "${target}.bak"
        ln -s "$source" "$target"
    else
        echo "Linking $source to $target..."
        ln -s "$source" "$target"
    fi
}

# ---------------------------------------------------------------------------
# Cross-distro package management
# ---------------------------------------------------------------------------
# Detect the package manager: dnf, apt-get, pacman, zypper, or apk.
PM=""
for m in dnf apt-get pacman zypper apk; do
    if command -v "$m" > /dev/null 2>&1; then
        PM="$m"
        break
    fi
done
# Short key used in the package map below.
case "$PM" in
    apt-get) PMKEY="apt" ;;
    *)       PMKEY="$PM" ;;
esac

# generic-name -> "mgr:package" per manager (no entry = install manually).
declare -A PKGMAP=(
    [neovim]="dnf:neovim apt:neovim pacman:neovim zypper:neovim apk:neovim"
    [imagemagick]="dnf:ImageMagick apt:imagemagick pacman:imagemagick zypper:ImageMagick apk:imagemagick"
    [ffmpeg]="dnf:ffmpeg-free apt:ffmpeg pacman:ffmpeg zypper:ffmpeg apk:ffmpeg"
    [ripgrep]="dnf:ripgrep apt:ripgrep pacman:ripgrep zypper:ripgrep apk:ripgrep"
    [nodejs]="dnf:nodejs apt:nodejs pacman:nodejs zypper:nodejs apk:nodejs"
    [npm]="dnf:nodejs-npm apt:npm pacman:npm zypper:npm apk:npm"
    [git]="dnf:git-core apt:git pacman:git zypper:git apk:git"
    [go]="dnf:golang apt:golang-go pacman:go zypper:go apk:go"
    [gh]="dnf:gh apt:gh pacman:github-cli zypper:gh apk:github-cli"
    [jq]="dnf:jq apt:jq pacman:jq zypper:jq apk:jq"
    [lazygit]="dnf:lazygit pacman:lazygit zypper:lazygit apk:lazygit"
    [gcc]="dnf:gcc apt:gcc pacman:gcc zypper:gcc apk:gcc"
    [gpp]="dnf:gcc-c++ apt:g++ pacman:gcc zypper:gcc-c++ apk:g++"
    [make]="dnf:make apt:make pacman:make zypper:make apk:make"
    [jdk]="dnf:java-21-openjdk-devel apt:default-jdk pacman:jdk-openjdk zypper:java-21-openjdk-devel apk:openjdk21"
    [jetbrains-mono]="dnf:jetbrains-mono-fonts apt:fonts-jetbrains-mono pacman:ttf-jetbrains-mono zypper:jetbrains-mono-fonts apk:font-jetbrains-mono-nerd"
)

# pkg_name <generic> -> distro package name for the current manager (or empty).
pkg_name() {
    local entry tok
    entry="${PKGMAP[$1]:-}"
    for tok in $entry; do
        if [ "${tok%%:*}" = "$PMKEY" ]; then
            echo "${tok#*:}"
            return 0
        fi
    done
    return 0
}

# pkg_install <package...> -> install via the detected manager.
pkg_install() {
    [ "$#" -eq 0 ] && return 0
    case "$PM" in
        dnf)     sudo dnf install -y "$@" ;;
        apt-get) sudo apt-get update -y && sudo apt-get install -y "$@" ;;
        pacman)  sudo pacman -S --needed --noconfirm "$@" ;;
        zypper)  sudo zypper install -y "$@" ;;
        apk)     sudo apk add "$@" ;;
        *)       return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Neovim: guarantee a modern version (our config needs >= 0.9)
# ---------------------------------------------------------------------------
# Distro packages are often far too old - notably Ubuntu LTS ships Neovim 0.6,
# which lacks nvim_create_autocmd (0.7+) and can't run lazy.nvim (0.8+), so
# `nvim .` crashes on our config. When the available nvim is missing or stale we
# install the official prebuilt release into ~/.local (no sudo, takes PATH
# precedence over any system nvim via the ~/.local/bin loader added below).
NVIM_MIN_VERSION="0.9.0"

# version_ge <have> <want> -> true if have >= want (dotted numeric compare).
version_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# nvim_ok -> true if an nvim on PATH satisfies NVIM_MIN_VERSION.
nvim_ok() {
    command -v nvim > /dev/null 2>&1 || return 1
    local v
    v="$(nvim --version 2>/dev/null | sed -n '1s/^NVIM v//p')"
    [ -n "$v" ] || return 1
    version_ge "${v%%-*}" "$NVIM_MIN_VERSION"
}

# install_neovim_release -> download the official stable tarball into ~/.local.
install_neovim_release() {
    local arch asset assets url tmp dl
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) assets="nvim-linux-x86_64.tar.gz nvim-linux64.tar.gz" ;;
        aarch64|arm64) assets="nvim-linux-arm64.tar.gz" ;;
        *) echo "  no Neovim release build for arch '$arch' - install it manually."; return 1 ;;
    esac

    if command -v curl > /dev/null 2>&1; then
        dl() { curl -fsSL "$1" -o "$2"; }
    elif command -v wget > /dev/null 2>&1; then
        dl() { wget -qO "$2" "$1"; }
    else
        echo "  need curl or wget to download Neovim - install one, then re-run."
        return 1
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    for asset in $assets; do
        url="https://github.com/neovim/neovim/releases/download/stable/$asset"
        echo "  downloading $url ..."
        if dl "$url" "$tmp/nvim.tar.gz"; then
            if tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"; then
                local extracted
                extracted="$(find "$tmp" -maxdepth 1 -type d -name 'nvim-*' | head -n1)"
                if [ -n "$extracted" ] && [ -x "$extracted/bin/nvim" ]; then
                    rm -rf "$HOME/.local/nvim"
                    mv "$extracted" "$HOME/.local/nvim"
                    create_symlink "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"
                    echo "  installed Neovim to ~/.local/nvim (linked into ~/.local/bin)."
                    return 0
                fi
            fi
        fi
    done
    echo "  failed to download/extract a Neovim release."
    return 1
}

# ensure_neovim -> make sure a modern nvim is available, best-effort.
ensure_neovim() {
    if nvim_ok; then
        echo "Neovim $(nvim --version | sed -n '1s/^NVIM v//p') already installed."
        return 0
    fi
    if command -v nvim > /dev/null 2>&1; then
        echo "Neovim $(nvim --version | sed -n '1s/^NVIM v//p') is too old (need >= $NVIM_MIN_VERSION) - installing an official release..."
    else
        echo "Neovim not found - installing an official release..."
    fi
    install_neovim_release || {
        echo "  (release install failed) trying the $PMKEY package as a fallback..."
        p="$(pkg_name neovim)"
        [ -n "$p" ] && pkg_install "$p" || true
    }
    nvim_ok || echo "  WARNING: Neovim is still older than $NVIM_MIN_VERSION - the config may not load. See https://github.com/neovim/neovim/releases"
}

echo "--- Installing packages (manager: ${PM:-none}) ---"
# Runtime deps as "command:generic-package" pairs; installed only if the command
# is missing. Failures are reported, never fatal.
TOOLS=(
    "magick:imagemagick"
    "ffmpeg:ffmpeg"
    "rg:ripgrep"
    "node:nodejs"
    "npm:npm"
    "git:git"
    "go:go"
    "gh:gh"
    "jq:jq"
    "lazygit:lazygit"
    "cc:gcc"
    "g++:gpp"
    "make:make"
    "javac:jdk"
)
if [ -n "$PM" ]; then
    missing=()
    for pair in "${TOOLS[@]}"; do
        cmd="${pair%%:*}"
        gen="${pair##*:}"
        if ! command -v "$cmd" > /dev/null 2>&1; then
            p="$(pkg_name "$gen")"
            if [ -n "$p" ]; then
                missing+=("$p")
            else
                echo "  no $PMKEY package mapping for '$gen' - install it manually"
            fi
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Installing missing packages: ${missing[*]}"
        pkg_install "${missing[@]}" || echo "  (some packages failed/skipped - install manually: ${missing[*]})"
    else
        echo "All required packages already installed."
    fi
else
    echo "  No supported package manager found. Install manually: ${TOOLS[*]%%:*}"
fi

echo "--- Installing fonts ---"
# Install JetBrains Mono, the terminal font (ghostty/config).
if fc-list 2>/dev/null | grep -qi "jetbrains mono"; then
    echo "JetBrains Mono already installed."
elif [ -n "$PM" ]; then
    p="$(pkg_name jetbrains-mono)"
    if [ -n "$p" ]; then
        echo "Installing JetBrains Mono ($p)..."
        pkg_install "$p" || echo "  (install failed/skipped - install '$p' manually)"
    else
        echo "  no JetBrains Mono package for $PMKEY - install it manually."
    fi
else
    echo "  No package manager - install JetBrains Mono manually."
fi

echo "--- Installing Ghostty terminal ---"
# Install Ghostty: native package on Fedora/Arch, else Flatpak. Best-effort.
if command -v ghostty > /dev/null 2>&1; then
    echo "Ghostty already installed."
else
    case "$PM" in
        dnf)    sudo dnf install -y ghostty || true ;;
        pacman) sudo pacman -S --needed --noconfirm ghostty || true ;;
    esac
    if ! command -v ghostty > /dev/null 2>&1; then
        if command -v flatpak > /dev/null 2>&1; then
            echo "Installing Ghostty via Flatpak..."
            flatpak install -y flathub com.mitchellh.ghostty || echo "  (flatpak ghostty failed - see https://ghostty.org/download)"
        else
            echo "  Ghostty isn't packaged for $PMKEY. Install it from https://ghostty.org/download"
            echo "  (or 'flatpak install flathub com.mitchellh.ghostty')."
        fi
    fi
fi

echo "--- Installing bin commands ---"
# Symlink each command in dotfiles/bin into ~/.local/bin.
if [ -d "$DIR/bin" ]; then
    for script in "$DIR"/bin/*; do
        [ -f "$script" ] || continue
        name="$(basename "$script")"
        chmod +x "$script"
        create_symlink "$script" "$HOME/.local/bin/$name"
    done
fi

echo "--- Installing Claude Code skills ---"
# Symlink each skill in dotfiles/claude/skills into ~/.claude/skills, leaving any
# machine-local skills already there untouched.
if [ -d "$DIR/claude/skills" ]; then
    mkdir -p "$HOME/.claude/skills"
    for skill in "$DIR"/claude/skills/*/; do
        [ -d "$skill" ] || continue
        name="$(basename "$skill")"
        create_symlink "${skill%/}" "$HOME/.claude/skills/$name"
    done
fi

echo "--- Installing Neovim ---"
ensure_neovim

echo "--- Configuring Neovim ---"
create_symlink "$DIR/nvim" "$HOME/.config/nvim"

echo "--- Configuring Ghostty ---"
create_symlink "$DIR/ghostty" "$HOME/.config/ghostty"

echo "--- Configuring ghme (gh-dash) ---"
create_symlink "$DIR/gh-dash" "$HOME/.config/gh-dash"

echo "--- Configuring msgme ---"
# msgme reads ~/.config/msgme/config.yml; set the Slack token via $SLACK_TOKEN.
create_symlink "$DIR/msgme-config" "$HOME/.config/msgme"

echo "--- Configuring shell (Ghostty git-branch title) ---"
# Auto-sourced from ~/.bashrc.d/ by the loader below.
create_symlink "$DIR/bashrc.d/ghostty-title.sh" "$HOME/.bashrc.d/ghostty-title.sh"

echo "--- Ensuring ~/.bashrc loads ~/.local/bin and ~/.bashrc.d ---"
# Append a PATH + ~/.bashrc.d loader to ~/.bashrc unless it already sources it.
BRC="$HOME/.bashrc"
touch "$BRC"
if grep -q '\.bashrc\.d' "$BRC"; then
    echo "  ~/.bashrc already sources ~/.bashrc.d"
else
    cat >> "$BRC" <<'EOF'

# --- dotfiles: PATH + ~/.bashrc.d loader (added by install.sh) ---
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
if [ -d "$HOME/.bashrc.d" ]; then
    for rc in "$HOME"/.bashrc.d/*.sh; do
        [ -r "$rc" ] && . "$rc"
    done
    unset rc
fi
EOF
    echo "  added PATH + ~/.bashrc.d loader to ~/.bashrc"
fi
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "  note: ~/.local/bin isn't on PATH in THIS shell - open a new shell or 'source ~/.bashrc'." ;;
esac

echo "--- Building msgme ---"
# msgme: terminal messages dashboard, built from vendored source.
if [ -d "$DIR/msgme" ]; then
    if command -v go > /dev/null 2>&1; then
        if ( cd "$DIR/msgme" && go build -o "$HOME/.local/bin/msgme" . ); then
            echo "Installed msgme to ~/.local/bin/msgme"
        else
            echo "  (msgme build failed - run 'cd $DIR/msgme && go build' to investigate)"
        fi
    else
        echo "  Go not installed - skipping msgme. Later: cd $DIR/msgme && go build -o ~/.local/bin/msgme ."
    fi
fi

echo "--- Building ghme (patched gh-dash) ---"
# ghme-rebuild compiles the vendored gh-dash source and installs it as the `gh
# dash` extension binary. gh is only needed at runtime.
if [ -d "$DIR/ghme" ] && [ -f "$DIR/ghme/go.mod" ]; then
    if command -v go > /dev/null 2>&1; then
        echo "  building the patched gh-dash binary (ghme-rebuild)..."
        GHME_SRC="$DIR/ghme" "$HOME/.local/bin/ghme-rebuild" || echo "  (ghme-rebuild failed - run 'GHME_SRC=$DIR/ghme ghme-rebuild' to investigate)"
    else
        echo "  Go not installed - skipping ghme. Later: GHME_SRC=$DIR/ghme ghme-rebuild"
    fi
    command -v gh > /dev/null 2>&1 || echo "  note: install gh (GitHub CLI) and 'gh auth login' so ghme can authenticate."
else
    echo "  no vendored source at $DIR/ghme - skipping ghme build."
fi

echo "--- Building todome ---"
# todome: terminal todo tracker, built from vendored source; no config needed.
if [ -d "$DIR/todome" ] && [ -f "$DIR/todome/go.mod" ]; then
    if command -v go > /dev/null 2>&1; then
        if ( cd "$DIR/todome" && go build -o "$HOME/.local/bin/todome" . ); then
            echo "Installed todome to ~/.local/bin/todome"
        else
            echo "  (todome build failed - run 'cd $DIR/todome && go build' to investigate)"
        fi
    else
        echo "  Go not installed - skipping todome. Later: cd $DIR/todome && go build -o ~/.local/bin/todome ."
    fi
fi

echo "--- Setting Ghostty as the default terminal ---"
# xdg-terminal-exec (used by GNOME/file managers) reads this list.
echo "com.mitchellh.ghostty.desktop" > "$HOME/.config/xdg-terminals.list"

echo "--- Installing Custom Desktop Applications ---"
for desktop_file in "$DIR"/custom_apps/*.desktop; do
    if [ -f "$desktop_file" ]; then
        filename=$(basename "$desktop_file")
        target="$HOME/.local/share/applications/$filename"

        echo "Processing $filename..."

        # Rewrite hardcoded /home/<user>/dotfiles and /home/<user> paths to $DIR/$HOME.
        sed -e "s|/home/[^/]*/dotfiles|$DIR|g" \
            -e "s|/home/[^/]*|$HOME|g" \
            "$desktop_file" > "$target"

        # Give execution permissions just in case
        chmod +x "$target"
    fi
done

# Update desktop database so the applications appear in application launchers
if command -v update-desktop-database > /dev/null; then
    echo "Updating desktop database..."
    update-desktop-database "$HOME/.local/share/applications"
fi

echo "--- Setup Complete! ---"
