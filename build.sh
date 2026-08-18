#!/bin/bash
set -e

BASE="/home/wojtek/myarch"
PROFILE="$BASE/archlive"
WORK="$BASE/archiso"

AUR_LIST="$BASE/aur.txt"
AUR_DIR="$BASE/aur"
REPO_DIR="$BASE/aur-repo"

REPO_NAME="myaur"

echo "==> Tworzenie katalogów..."
mkdir -p "$AUR_DIR"
mkdir -p "$REPO_DIR"

echo "==> Budowanie pakietów AUR..."

while IFS= read -r package || [[ -n "$package" ]]; do

    # Pomijanie pustych linii i komentarzy
    [[ -z "$package" ]] && continue
    [[ "$package" =~ ^[[:space:]]*# ]] && continue

    echo
    echo "========================================"
    echo "==> Pakiet: $package"
    echo "========================================"

    PKG_BUILD_DIR="$AUR_DIR/$package"

    # Pobranie PKGBUILD z AUR
    if [[ ! -d "$PKG_BUILD_DIR/.git" ]]; then
        echo "==> Klonowanie $package z AUR..."
        git clone "https://aur.archlinux.org/$package.git" "$PKG_BUILD_DIR"
    else
        echo "==> Aktualizacja $package..."
        git -C "$PKG_BUILD_DIR" pull --ff-only
    fi

    cd "$PKG_BUILD_DIR"

    echo "==> Budowanie $package..."

    # Budujemy jako zwykły użytkownik.
    # makepkg nie powinien być uruchamiany jako root.
    makepkg -sf --noconfirm

    echo "==> Kopiowanie pakietu do lokalnego repo..."

    cp ./*.pkg.tar.zst "$REPO_DIR/"

done < "$AUR_LIST"

echo
echo "==> Aktualizacja lokalnego repozytorium..."

cd "$REPO_DIR"

repo-add "$REPO_NAME.db.tar.gz" ./*.pkg.tar.zst

echo
echo "==> Budowanie archiso..."

mkarchiso -v \
    -w "$WORK" \
    "$PROFILE"

echo
echo "========================================"
echo "==> GOTOWE"
echo "========================================"