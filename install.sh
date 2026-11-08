#!/bin/sh
# Installs or updates Arara:
#   curl -fsSL https://github.com/eduwxyz/tucano/releases/latest/download/install.sh | sh
#
# On a Mac: the app (signed and notarized by Apple) goes into Applications; the
# "from the internet" mark is cleared all the same. Before its public release
# Arara was called agent-desk: an old agent-desk.app is closed and replaced, and
# its data comes along the first time Arara opens.
# On Linux: the .deb with apt (Ubuntu, Debian and their family), else the AppImage
# in ~/.local/bin with an entry in the applications menu.
#
# On Windows: install.ps1, in PowerShell (this says so).
#
# For testing a build before it is released (then the app doesn't open):
# ARARA_ZIP (Mac), ARARA_DEB or ARARA_APPIMAGE (Linux; a URL or a local file)
# and ARARA_DEST, another folder. ARARA_APPIMAGE=1 picks the AppImage over the .deb.
set -e
REPO=eduwxyz/tucano
LATEST="https://github.com/$REPO/releases/latest/download"

# Messages in Portuguese on a system set to Portuguese, in English otherwise.
case "${LANG:-}" in pt*) PT=1 ;; *) PT= ;; esac
say() { if [ -n "$PT" ]; then echo "$1"; else echo "$2"; fi; }
fail() { say "$1" "$2" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fetch() { # fetch <url or file> <to>
  case "$1" in
    http*) curl -fL --progress-bar -o "$2" "$1" ;;
    *) cp "$1" "$2" ;;
  esac
}

install_mac() {
  # Apple silicon or Intel. uname says x86_64 in a Terminal running under Rosetta, so ask the chip.
  ARCH=x64
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && ARCH=arm64
  ZIP="${ARARA_ZIP:-$LATEST/arara-mac-$ARCH.zip}"
  DEST="${ARARA_DEST:-/Applications}"
  [ -w "$DEST" ] || [ -n "$ARARA_DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  APP="$DEST/Arara.app"
  OLD="$DEST/agent-desk.app"

  say "Baixando a Arara…" "Downloading Arara…"
  fetch "$ZIP" "$TMP/arara.zip"
  ditto -x -k "$TMP/arara.zip" "$TMP/app"
  [ -d "$TMP/app/Arara.app" ] || fail "O arquivo baixado não tem o Arara.app." "The download doesn't contain Arara.app."

  # Copying over a running app leaves it unable to quit normally: close it first.
  running() { pgrep -f "$APP/Contents/MacOS/Arara\$" >/dev/null || pgrep -f "$OLD/Contents/MacOS/agent-desk\$" >/dev/null; }
  if running; then
    say "Fechando o app aberto…" "Closing the running app…"
    for name in Arara agent-desk; do
      osascript -e 'with timeout of 20 seconds' -e "tell application \"$name\" to quit" -e 'end timeout' >/dev/null 2>&1 || true
    done
    for _ in $(seq 1 30); do running || break; sleep 1; done
    running && fail "O app não fechou. Feche com ⌘Q e rode de novo." "The app didn't close. Quit it with ⌘Q and run this again."
  fi

  rm -rf "$APP"
  ditto "$TMP/app/Arara.app" "$APP"
  xattr -r -d com.apple.quarantine "$APP" >/dev/null 2>&1 || true
  if [ -d "$OLD" ] && [ -z "$ARARA_DEST" ]; then
    rm -rf "$OLD"
    osascript -e 'tell application "System Events" to delete login item "agent-desk"' >/dev/null 2>&1 || true
  fi
  say "Instalado em $APP" "Installed in $APP"
  [ -n "$ARARA_DEST" ] || open "$APP"
}

install_linux() {
  # The files carry each format's name for the architecture (amd64 .deb, x86_64 AppImage).
  case "$(uname -m)" in
    x86_64 | amd64) DEB=amd64 IMG=x86_64 ;;
    aarch64 | arm64) DEB=arm64 IMG=arm64 ;;
    *) fail "A Arara roda em Linux x64 ou ARM64, não em $(uname -m)." "Arara runs on x64 or ARM64 Linux, not on $(uname -m)." ;;
  esac

  # Replacing a running app's files leaves it broken: close it first (it quits on SIGTERM).
  # Only the app itself: a command line that starts with its path.
  running() { pgrep -f '^/opt/Arara/arara( |$)' >/dev/null || pgrep -f '^[^ ]*/Arara\.AppImage( |$)' >/dev/null; }
  if running && [ -z "$ARARA_DEST" ]; then
    say "Fechando o app aberto…" "Closing the running app…"
    pkill -TERM -f '^/opt/Arara/arara( |$)' 2>/dev/null || true
    pkill -TERM -f '^[^ ]*/Arara\.AppImage( |$)' 2>/dev/null || true
    for _ in $(seq 1 30); do running || break; sleep 1; done
    running && fail "O app não fechou. Encerre a Arara (ícone na bandeja › Encerrar) e rode de novo." "The app didn't close. Quit Arara (tray icon › Quit) and run this again."
  fi

  if [ -z "${ARARA_APPIMAGE:-}" ] && command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
    say "Baixando a Arara (.deb)…" "Downloading Arara (.deb)…"
    fetch "${ARARA_DEB:-$LATEST/arara-linux-$DEB.deb}" "$TMP/arara.deb"
    chmod 644 "$TMP/arara.deb"
    chmod 755 "$TMP"
    SUDO=
    if [ "$(id -u)" != 0 ]; then
      command -v sudo >/dev/null 2>&1 || fail "Precisa de sudo pra instalar o .deb. Rode como root, ou use ARARA_APPIMAGE=1." "Installing the .deb needs sudo. Run as root, or use ARARA_APPIMAGE=1."
      SUDO=sudo
      say "Instalando (o sistema pede a sua senha)…" "Installing (the system asks for your password)…"
    fi
    $SUDO apt-get install -y "$TMP/arara.deb"
    APP=/opt/Arara/arara
  else
    DEST="${ARARA_DEST:-$HOME/.local/bin}"
    mkdir -p "$DEST"
    APP="$DEST/Arara.AppImage"
    case "${ARARA_APPIMAGE:-}" in "" | 1) SRC="$LATEST/arara-linux-$IMG.AppImage" ;; *) SRC="$ARARA_APPIMAGE" ;; esac
    say "Baixando a Arara (AppImage)…" "Downloading Arara (AppImage)…"
    fetch "$SRC" "$TMP/Arara.AppImage"
    chmod +x "$TMP/Arara.AppImage"
    mv -f "$TMP/Arara.AppImage" "$APP"
    if [ -z "$ARARA_DEST" ]; then
      # In the applications menu, with the toucan (the AppImage's own icon, by its path).
      ICON="$HOME/.local/share/icons/arara.png"
      mkdir -p "$(dirname "$ICON")" "$HOME/.local/share/applications"
      PNG=usr/share/icons/hicolor/1024x1024/apps/arara.png
      (cd "$TMP" && env -u APPIMAGE_EXTRACT_AND_RUN "$APP" --appimage-extract "$PNG" >/dev/null 2>&1 && cp "squashfs-root/$PNG" "$ICON") || ICON=arara
      cat > "$HOME/.local/share/applications/arara.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Arara
Comment=A team of AI agents on your computer
Exec="$APP" %U
Icon=$ICON
Terminal=false
Categories=Utility;
StartupWMClass=Arara
EOF
      command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi
  fi
  say "Instalado: $APP" "Installed: $APP"
  if [ -z "$ARARA_DEST" ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    nohup "$APP" >/dev/null 2>&1 &
  fi
}

case "$(uname -s)" in
  Darwin) install_mac ;;
  Linux) install_linux ;;
  MINGW* | MSYS* | CYGWIN*) fail "No Windows, instale pelo PowerShell: irm $LATEST/install.ps1 | iex" "On Windows, install from PowerShell: irm $LATEST/install.ps1 | iex" ;;
  *) fail "A Arara roda no macOS, no Linux e no Windows." "Arara runs on macOS, Linux and Windows." ;;
esac
