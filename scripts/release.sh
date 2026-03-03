#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Helpers ────────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }
confirm() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Pre-flight checks ──────────────────────────────────────────────────────────

command -v gh >/dev/null 2>&1 || die "gh CLI not found"
command -v git >/dev/null 2>&1 || die "git not found"

cd "$PROJECT_DIR"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    die "must be on main branch (currently on '$CURRENT_BRANCH')"
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    die "working tree is dirty -- commit or stash changes first"
fi

PRESETS_ZIP="$HOME/Documents/foobar2000/projectMacOS.zip"
if [ ! -f "$PRESETS_ZIP" ]; then
    die "presets zip not found at $PRESETS_ZIP"
fi

# ── Ask for version ────────────────────────────────────────────────────────────

CURRENT_VERSION=$(grep 'DECLARE_COMPONENT_VERSION' mac/ProjectMRegistration.mm \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

echo "Current version: $CURRENT_VERSION"
read -r -p "New version: " NEW_VERSION

[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "invalid version format (expected X.Y.Z)"

TAG="v$NEW_VERSION"

echo ""
echo "  Version : $CURRENT_VERSION → $NEW_VERSION"
echo "  Tag     : $TAG"
echo "  Presets : $PRESETS_ZIP"
echo ""
confirm "Proceed?" || { echo "Aborted."; exit 0; }

# ── Pull latest main ───────────────────────────────────────────────────────────

echo ""
echo "==> Pulling latest main..."
git pull origin main

# ── Bump version ───────────────────────────────────────────────────────────────

echo "==> Bumping version to $NEW_VERSION..."

sed -i '' "s/DECLARE_COMPONENT_VERSION(\"projectMacOS visualizer\", \"$CURRENT_VERSION\"/DECLARE_COMPONENT_VERSION(\"projectMacOS visualizer\", \"$NEW_VERSION\"/" \
    mac/ProjectMRegistration.mm

sed -i '' "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*;/MARKETING_VERSION = $NEW_VERSION;/g" \
    mac/projectMacOS.xcodeproj/project.pbxproj

sed -i '' "s/Version: $CURRENT_VERSION /Version: $NEW_VERSION /" \
    AGENTS.md

# ── Build & deploy ─────────────────────────────────────────────────────────────

echo "==> Building..."
SKIP_DEPS_BUILD=1 bash "$SCRIPT_DIR/deploy-component.sh" --build

ARTIFACT="$PROJECT_DIR/mac/build/Release/foo_vis_projectMacOS.fb2k-component"
[ -f "$ARTIFACT" ] || die "build artifact not found: $ARTIFACT"

# ── Commit & push ──────────────────────────────────────────────────────────────

echo "==> Committing version bump..."
git add mac/ProjectMRegistration.mm mac/projectMacOS.xcodeproj/project.pbxproj AGENTS.md
git commit -m "chore: bump version to $NEW_VERSION"
git push origin main

# ── Tag ────────────────────────────────────────────────────────────────────────

echo "==> Creating tag $TAG..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "    Tag $TAG already exists locally -- deleting..."
    git tag -d "$TAG"
fi
if git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
    echo "    Tag $TAG exists on remote -- deleting..."
    git push origin --delete "$TAG"
fi
git tag "$TAG"
git push origin "$TAG"

# ── Release ────────────────────────────────────────────────────────────────────

echo "==> Creating GitHub release $TAG..."
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "    Release $TAG already exists -- deleting..."
    gh release delete "$TAG" --yes
fi

gh release create "$TAG" \
    --title "$TAG" \
    --generate-notes \
    "$ARTIFACT" \
    "$PRESETS_ZIP"

echo ""
echo "Done. https://github.com/gabitoesmiapodo/projectMacOS/releases/tag/$TAG"
