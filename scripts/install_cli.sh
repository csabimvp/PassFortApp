#!/usr/bin/env bash
# Build passfort-cli in release and install it, with shell completion, on macOS or Linux / WSL2.
#
#   scripts/install_cli.sh            # -> ~/.local/bin/passfort-cli
#   scripts/install_cli.sh ~/bin      # -> a folder of your choice
#
# Completion scripts go where zsh and bash look for per-user ones, under $XDG_DATA_HOME
# (~/.local/share): they complete subcommands, options, and the vault names `--vault` takes.
# Nothing else is touched: the vault, ~/.config/passfort/ and the SwiftPM cache stay as they are.
set -euo pipefail

cd "$(dirname "$0")/../Packages/PassFortKit"

dest="${1:-$HOME/.local/bin}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
zsh_dir="$data/zsh/site-functions"
bash_dir="$data/bash-completion/completions"

echo "==> Building passfort-cli (release)"
swift build -c release --product passfort-cli
bin="$(swift build -c release --show-bin-path)/passfort-cli"
[[ -x "$bin" ]] || { echo "error: no binary at $bin" >&2; exit 1; }

echo "==> Installing to $dest"
mkdir -p "$dest"
install -m 0755 "$bin" "$dest/passfort-cli"

echo "==> Installing completion"
mkdir -p "$zsh_dir" "$bash_dir"
"$dest/passfort-cli" --generate-completion-script zsh >"$zsh_dir/_passfort-cli"
"$dest/passfort-cli" --generate-completion-script bash >"$bash_dir/passfort-cli"

echo "==> Installed $dest/passfort-cli"
case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "    $dest is not on your PATH -- add it in your shell profile" ;;
esac
if [[ "${SHELL:-}" == */zsh ]] && ! grep -qs "zsh/site-functions" "$HOME/.zshrc"; then
  echo "    zsh: add this to ~/.zshrc, before compinit runs, for completion:"
  echo "        fpath=(\"$zsh_dir\" \$fpath)"
fi
echo "    Next: passfort-cli vault add <name> <path to your vault>   (or passfort-cli init)"
