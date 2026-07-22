#!/usr/bin/env bash
# Bygg + publicera frontend till GitHub Pages (wlanhage.github.io/HouseMates).
# Kräver: .env.pages med PUBLIC_*-värdena (skapas av deploy-flödet, gitignorad).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env.pages ] || { echo "Saknar .env.pages – se deploy/SUPABASE.md"; exit 1; }
set -a; source .env.pages; set +a

BASE_PATH=/HouseMates npm run build
cp build/index.html build/404.html

cd build
git init -q && git checkout -qb gh-pages
git add -A && git commit -qm "Deploy: $(git -C .. log -1 --format=%h) $(date '+%Y-%m-%d %H:%M')"
git push -qf https://github.com/wlanhage/HouseMates.git gh-pages
rm -rf .git
echo "Publicerad: https://wlanhage.github.io/HouseMates/"
