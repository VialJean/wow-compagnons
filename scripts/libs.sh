#!/usr/bin/env bash
# Récupère les bibliothèques déclarées dans .pkgmeta dans ./Libs, pour le développement local.
# Utilise le packager officiel sans upload ni zip. Nécessite git, subversion et curl.
set -euo pipefail
cd "$(dirname "$0")/.."

curl -fsSL https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh -o .release-packager.sh
bash .release-packager.sh -d -z
rm -f .release-packager.sh

rm -rf Libs
cp -r .release/Compagnons/Libs ./Libs
echo "Bibliothèques copiées dans ./Libs"
