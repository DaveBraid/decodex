#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.local/bin"
TARGET_BIN="${TARGET_DIR}/decodex"

mkdir -p "${TARGET_DIR}"
ln -sf "${REPO_DIR}/bin/decodex" "${TARGET_BIN}"
chmod +x "${REPO_DIR}/bin/decodex"

echo "Installed decodex -> ${TARGET_BIN}"

case ":${PATH}:" in
  *":${TARGET_DIR}:"*) ;;
  *)
    echo "Note: ${TARGET_DIR} is not currently in your PATH."
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

echo ""
echo "Next steps:"
echo "  1. Verify daemon & schema:  decodex doctor --fix"
echo "  2. List existing projects:  decodex projects"
echo "  3. Optional Agent Skill:    install ${REPO_DIR}/skills/decodex into your agent's skills directory"
