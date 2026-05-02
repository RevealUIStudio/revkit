#!/bin/bash
# Sets up git hooks in WSL RevealUI to sync the Windows mirror
# on every commit, merge, checkout, and rewrite (rebase/amend).
#
# RevealUI uses Husky (core.hooksPath = .husky/_), so user-facing hooks
# go in .husky/, NOT .git/hooks/. The sync script itself lives in
# .git/hooks/ (untracked, won't pollute the working tree).

REPO="/home/joshua-v-dev/projects/RevealUI"
GIT_HOOKS_DIR="$REPO/.git/hooks"
HUSKY_DIR="$REPO/.husky"
EXCLUDE_FILE="$REPO/.git/info/exclude"

# 1. Create the sync script in .git/hooks/ (untracked)
cat > "$GIT_HOOKS_DIR/sync-windows-mirror" << 'EOF'
#!/bin/bash
# Sync Windows RevealUI mirror from local WSL repo
# Runs in background so it never blocks the developer

WINDOWS_MIRROR="/mnt/c/Users/joshu/projects/RevealUI"
WSL_REPO="/home/joshua-v-dev/projects/RevealUI"

# Only sync if Windows mirror exists
[ -d "$WINDOWS_MIRROR/.git" ] || exit 0

(
  branch=$(git -C "$WSL_REPO" symbolic-ref --short HEAD 2>/dev/null) || branch="main"
  git -C "$WINDOWS_MIRROR" fetch "$WSL_REPO" "$branch" 2>/dev/null
  git -C "$WINDOWS_MIRROR" reset --hard FETCH_HEAD 2>/dev/null
) &
EOF
chmod +x "$GIT_HOOKS_DIR/sync-windows-mirror"
echo "Created $GIT_HOOKS_DIR/sync-windows-mirror"

# 2. Create Husky hooks in .husky/ (where Husky's dispatcher looks)
for hook in post-commit post-merge post-checkout post-rewrite; do
  cat > "$HUSKY_DIR/$hook" << 'EOF'
#!/bin/bash
.git/hooks/sync-windows-mirror
EOF
  chmod +x "$HUSKY_DIR/$hook"
  echo "Created $HUSKY_DIR/$hook"
done

# 3. Add Husky hooks to .git/info/exclude so they don't pollute git status
mkdir -p "$(dirname "$EXCLUDE_FILE")"
for hook in post-commit post-merge post-checkout post-rewrite; do
  if ! grep -qF ".husky/$hook" "$EXCLUDE_FILE" 2>/dev/null; then
    echo ".husky/$hook" >> "$EXCLUDE_FILE"
    echo "Excluded .husky/$hook from git status"
  fi
done

# 4. Clean up old hooks from .git/hooks/ (dead code — Husky ignores them)
for hook in post-commit post-merge post-checkout; do
  if [ -f "$GIT_HOOKS_DIR/$hook" ] && grep -q "sync-windows-mirror" "$GIT_HOOKS_DIR/$hook" 2>/dev/null; then
    rm "$GIT_HOOKS_DIR/$hook"
    echo "Removed dead $GIT_HOOKS_DIR/$hook"
  fi
done

echo ""
echo "Verification:"
ls -la "$HUSKY_DIR"/{post-commit,post-merge,post-checkout,post-rewrite} 2>&1
ls -la "$GIT_HOOKS_DIR/sync-windows-mirror" 2>&1
echo ""
echo "git status check:"
cd "$REPO" && git status --short .husky/
