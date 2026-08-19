#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================

BASE="/home/wojtek/myarch"
PROFILE="$BASE/archlive"
WORK="$BASE/archiso"

AUR_LIST="$BASE/aur.txt"
AUR_DIR="$BASE/aur"
REPO_DIR="$BASE/aur-repo"

REPO_NAME="myaur"

# Domyślnie usuwamy katalog work po zakończeniu.
KEEP_WORK=false

if [[ "${1:-}" == "--keep-work" ]]; then
    KEEP_WORK=true
fi


# ============================================================
# CLEANUP
# ============================================================

cleanup() {
    local exit_code=$?

    echo
    echo "==> Cleanup..."

    if [[ "$KEEP_WORK" == true ]]; then
        echo "==> --keep-work: pozostawiam $WORK"
        return
    fi

    if [[ -d "$WORK" ]]; then

        echo "==> Sprawdzanie mountów..."

        # Odmontowanie całego airootfs, jeśli jest zamontowany.
        if mountpoint -q "$WORK/x86_64/airootfs" 2>/dev/null; then
            echo "==> Odmontowywanie airootfs..."

            sudo umount -R "$WORK/x86_64/airootfs" 2>/dev/null || true
        fi

        # Na wszelki wypadek spróbuj znaleźć pozostałe mounty
        # znajdujące się pod katalogiem WORK.
        if command -v findmnt >/dev/null 2>&1; then
            while read -r mountpoint_path; do
                [[ -z "$mountpoint_path" ]] && continue

                echo "==> Odmontowywanie: $mountpoint_path"

                sudo umount "$mountpoint_path" 2>/dev/null || true
            done < <(
                findmnt -R -n -o TARGET "$WORK" 2>/dev/null |
                sort -r
            )
        fi

        echo "==> Usuwanie $WORK..."

        sudo rm -rf "$WORK"
    fi

    if [[ $exit_code -eq 0 ]]; then
        echo "==> Cleanup zakończony."
    else
        echo "==> Build zakończył się błędem (kod $exit_code)."
        echo "==> Work directory został usunięty."
    fi
}

trap cleanup EXIT


# ============================================================
# CHECKS
# ============================================================

echo "==> Sprawdzanie zależności..."

for command in git makepkg repo-add mkarchiso; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: Brakuje programu: $command"
        exit 1
    fi
done

if [[ ! -f "$AUR_LIST" ]]; then
    echo "ERROR: Nie znaleziono:"
    echo "       $AUR_LIST"
    exit 1
fi

if [[ ! -d "$PROFILE" ]]; then
    echo "ERROR: Nie znaleziono profilu archiso:"
    echo "       $PROFILE"
    exit 1
fi


# ============================================================
# PREPARE DIRECTORIES
# ============================================================

echo
echo "==> Tworzenie katalogów..."
mkdir -p "$AUR_DIR"
mkdir -p "$REPO_DIR"


# ============================================================
# BUILD AUR PACKAGES
# ============================================================

echo
echo "============================================================"
echo "==> PAKIETY AUR"
echo "============================================================"

while IFS= read -r package || [[ -n "$package" ]]; do

    # Pomijanie pustych linii i komentarzy
    [[ -z "$package" ]] && continue
    [[ "$package" =~ ^[[:space:]]*# ]] && continue

    # Usunięcie ewentualnych spacji
    package="$(echo "$package" | xargs)"

    [[ -z "$package" ]] && continue

    echo
    echo "------------------------------------------------------------"
    echo "==> Pakiet: $package"
    echo "------------------------------------------------------------"

    PKG_BUILD_DIR="$AUR_DIR/$package"


    # --------------------------------------------------------
    # CLONE / UPDATE AUR
    # --------------------------------------------------------

    if [[ ! -d "$PKG_BUILD_DIR/.git" ]]; then

        echo "==> Klonowanie z AUR..."

        git clone \
            "https://aur.archlinux.org/$package.git" \
            "$PKG_BUILD_DIR"

    else

        echo "==> Aktualizacja repozytorium AUR..."

        git -C "$PKG_BUILD_DIR" pull --ff-only

    fi


    cd "$PKG_BUILD_DIR"


    # --------------------------------------------------------
    # GET PACKAGE INFO
    # --------------------------------------------------------

    PKGINFO="$(makepkg --printsrcinfo)"

    PKGNAME="$(
        echo "$PKGINFO" |
        awk '$1 == "pkgname" {print $3; exit}'
    )"

    PKGVER="$(
        echo "$PKGINFO" |
        awk '$1 == "pkgver" {print $3; exit}'
    )"

    PKGREL="$(
        echo "$PKGINFO" |
        awk '$1 == "pkgrel" {print $3; exit}'
    )"

    VERSION="${PKGVER}-${PKGREL}"

    echo "==> Wersja: $PKGNAME-$VERSION"


    # --------------------------------------------------------
    # CHECK CACHE
    # --------------------------------------------------------

    if compgen -G \
        "$REPO_DIR/$PKGNAME-$VERSION-*.pkg.tar.zst" \
        > /dev/null
    then

        echo "==> Pakiet tej wersji już istnieje w lokalnym repo."
        echo "==> Pomijam budowanie."

        continue
    fi


    # --------------------------------------------------------
    # BUILD
    # --------------------------------------------------------

    echo "==> Brak pakietu w cache."
    echo "==> Budowanie $PKGNAME..."

    # Usuwamy stare artefakty z katalogu AUR.
    rm -f ./*.pkg.tar.zst


    makepkg \
        -sf \
        --noconfirm


    # --------------------------------------------------------
    # COPY PACKAGE TO LOCAL REPOSITORY
    # --------------------------------------------------------

    echo "==> Kopiowanie pakietu do lokalnego repo..."

    shopt -s nullglob

    packages=( ./*.pkg.tar.zst )

    if [[ ${#packages[@]} -eq 0 ]]; then
        echo "ERROR: makepkg nie wygenerował pakietu!"
        exit 1
    fi

    cp "${packages[@]}" "$REPO_DIR/"

    shopt -u nullglob

done < "$AUR_LIST"


# ============================================================
# UPDATE LOCAL REPOSITORY
# ============================================================

echo
echo "============================================================"
echo "==> LOKALNE REPOZYTORIUM"
echo "============================================================"

cd "$REPO_DIR"

shopt -s nullglob

packages=( ./*.pkg.tar.zst )

if [[ ${#packages[@]} -eq 0 ]]; then
    echo "ERROR: Lokalne repo nie zawiera żadnych pakietów."
    exit 1
fi

shopt -u nullglob


echo "==> Aktualizacja bazy repozytorium..."

repo-add \
    "$REPO_NAME.db.tar.gz" \
    "${packages[@]}"


# ============================================================
# BUILD ARCHISO
# ============================================================

echo
echo "============================================================"
echo "==> ARCHISO"
echo "============================================================"

cd "$BASE"

echo "==> Profil:"
echo "    $PROFILE"

echo "==> Work:"
echo "    $WORK"

echo
echo "==> Uruchamiam mkarchiso..."

mkarchiso \
    -v \
    -w "$WORK" \
    "$PROFILE"


# ============================================================
# DONE
# ============================================================

echo
echo "============================================================"
echo "==> GOTOWE"
echo "============================================================"

echo
echo "ISO powinno znajdować się w:"
echo "    $BASE/out"

echo

if [[ "$KEEP_WORK" == true ]]; then
    echo "Work directory pozostawiony:"
    echo "    $WORK"
else
    echo "Work directory zostanie usunięty przez cleanup."
fi
