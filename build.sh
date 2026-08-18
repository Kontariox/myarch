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
        echo "==> Sprawdzanie zmian w AUR..."
        git -C "$PKG_BUILD_DIR" pull --ff-only
    fi

    cd "$PKG_BUILD_DIR"

    # Pobierz informacje o wersji pakietu z PKGBUILD
    PKGNAME=$(makepkg --printsrcinfo | awk '$1 == "pkgname" {print $3; exit}')
    PKGVER=$(makepkg --printsrcinfo | awk '$1 == "pkgver" {print $3; exit}')
    PKGREL=$(makepkg --printsrcinfo | awk '$1 == "pkgrel" {print $3; exit}')


    VERSION="${PKGVER}-${PKGREL}"

    echo "==> Wersja AUR: $PKGNAME-$VERSION"

    # Sprawdź, czy dokładnie taka wersja już istnieje
    if compgen -G "$REPO_DIR/$PKGNAME-$VERSION-*.pkg.tar.zst" > /dev/null; then
        echo "==> $PKGNAME-$VERSION już jest w repo."
        echo "==> Pomijam budowanie."
        continue
    fi

    echo "==> Brak tej wersji w repo."
    echo "==> Budowanie $PKGNAME..."

    # Usuń stare artefakty z katalogu budowania
    rm -f ./*.pkg.tar.zst

    makepkg -sf --noconfirm

    echo "==> Kopiowanie pakietu do lokalnego repo..."

    cp ./*.pkg.tar.zst "$REPO_DIR/"

done < "$AUR_LIST"

echo
echo "==> Aktualizacja lokalnego repozytorium..."

cd "$REPO_DIR"

# Usuń stare bazy repo
rm -f "$REPO_NAME.db" "$REPO_NAME.files"
rm -f "$REPO_NAME.db.tar.gz" "$REPO_NAME.files.tar.gz"

repo-add "$REPO_NAME.db.tar.gz" ./*.pkg.tar.zst

echo
echo "==> Budowanie archiso..."
cd "$BASE"

mkarchiso -v \
    -w "$WORK" \
    "$PROFILE"

echo
echo "========================================"
echo "==> GOTOWE"
echo "========================================"