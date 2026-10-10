#!/bin/sh
# Lance une release de CorpUI : met la version dans le .toc (et le badge du
# README), commite, pose le tag vX.Y.Z et pousse. GitHub construit ensuite
# CorpUI-X.Y.Z.zip et la release (.github/workflows/release.yml).
# Usage (Git Bash, depuis le dossier CorpUI) : .github/scripts/release.sh 1.2.0
set -e
VER="$1"
case "$VER" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "Usage : $0 X.Y.Z   (ex. 1.2.0)" >&2; exit 1 ;;
esac
cd "$(git rev-parse --show-toplevel)"
if [ -n "$(git status --porcelain)" ]; then
  echo "Des changements ne sont pas commites : commite-les d abord." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$VER" >/dev/null; then
  echo "La version v$VER existe deja." >&2
  exit 1
fi
sed -i "s/^## Version: .*/## Version: $VER/" CorpUI.toc
sed -i "s#badge/Version-[0-9.]*-#badge/Version-$VER-#" README.md
git add CorpUI.toc README.md
git commit -m "Version $VER"
git tag -a "v$VER" -m "CorpUI $VER"
git push origin HEAD "v$VER"
echo "Version $VER envoyee. Suivi : https://github.com/Cerynna/CorpUI/actions"
echo "Release : https://github.com/Cerynna/CorpUI/releases/tag/v$VER"
