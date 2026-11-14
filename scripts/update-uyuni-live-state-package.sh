#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UYUNI_REPOSITORY="${UYUNI_REPOSITORY:-$HOME/github/uyuni}"
UYUNI_COMMIT="${1:-HEAD}"
PACKAGE_PATH="packages/uyuni_live_state_swift"
DESTINATION="$ROOT_DIR/Packages/UyuniLiveState"

usage() {
  cat <<USAGE
Usage: scripts/update-uyuni-live-state-package.sh [UYUNI_COMMIT]

Replaces Packages/UyuniLiveState with $PACKAGE_PATH from the Uyuni repository at
UYUNI_COMMIT (default HEAD) and records the repository and commit in
Packages/UyuniLiveState/provenance.yaml. The previous copy is moved to the Trash.

Environment overrides:
  UYUNI_REPOSITORY   default: \$HOME/github/uyuni
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

RESOLVED_COMMIT="$(git -C "$UYUNI_REPOSITORY" rev-parse --verify "$UYUNI_COMMIT^{commit}")"
if [[ -z "$(git -C "$UYUNI_REPOSITORY" ls-tree -d "$RESOLVED_COMMIT" "$PACKAGE_PATH")" ]]; then
  echo "error: $PACKAGE_PATH does not exist at $RESOLVED_COMMIT" >&2
  exit 1
fi

if [[ -e "$DESTINATION" ]]; then
  trash "$DESTINATION"
fi
mkdir -p "$DESTINATION"
git -C "$UYUNI_REPOSITORY" archive --format=tar "$RESOLVED_COMMIT" "$PACKAGE_PATH" | tar -x --strip-components=2 -C "$DESTINATION"
cat > "$DESTINATION/provenance.yaml" <<PROVENANCE
source_repository: chriswinsatlife/uyuni
source_path: $PACKAGE_PATH
source_commit: $RESOLVED_COMMIT
copied_by: scripts/update-uyuni-live-state-package.sh
PROVENANCE
echo "Copied $PACKAGE_PATH at $RESOLVED_COMMIT to Packages/UyuniLiveState"
