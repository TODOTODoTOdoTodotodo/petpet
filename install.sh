#!/bin/bash
# DeskPet 설치 스크립트
#   설치:   curl -fsSL https://raw.githubusercontent.com/TODOTODoTOdoTodotodo/petpet/main/install.sh | bash
#   지우기: curl -fsSL https://raw.githubusercontent.com/TODOTODoTOdoTodotodo/petpet/main/install.sh | bash -s -- --uninstall
#
# 하는 일: GitHub Releases의 최신 DeskPet.zip 내려받기 → 응용 프로그램 폴더에 풀기 → 실행
# 관리자 권한(sudo)을 쓰지 않음. /Applications에 쓸 수 없으면 ~/Applications에 설치
# 바꿀 수 있는 값: DESKPET_URL(내려받을 주소), DESKPET_DIR(설치 폴더)
set -euo pipefail

REPO="TODOTODoTOdoTodotodo/petpet"
URL="${DESKPET_URL:-https://github.com/$REPO/releases/latest/download/DeskPet.zip}"
APP="DeskPet.app"
TMP_DIR=""

say() { printf '%s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# 설치 폴더: 지정값 → /Applications(쓰기 가능할 때) → ~/Applications
target_dir() {
    if [ -n "${DESKPET_DIR:-}" ]; then
        printf '%s' "$DESKPET_DIR"
    elif [ -w /Applications ]; then
        printf '%s' /Applications
    else
        printf '%s' "$HOME/Applications"
    fi
}

# 실행 중인 DeskPet 종료
quit_app() {
    pkill -x DeskPet 2>/dev/null || true
    sleep 1
}

uninstall() {
    quit_app
    local removed=false
    # 설치 폴더를 지정했으면 그 폴더만
    local dirs=(/Applications "$HOME/Applications")
    [ -n "${DESKPET_DIR:-}" ] && dirs=("$DESKPET_DIR")
    for dir in "${dirs[@]}"; do
        [ -d "$dir/$APP" ] || continue
        rm -rf "${dir:?}/$APP"
        say "✓ 삭제: $dir/$APP"
        removed=true
    done
    [ "$removed" = true ] || say "· 설치된 DeskPet 없음"
    say "· 설정·도감까지 지우려면:"
    say "  defaults delete com.deskpet.companion; rm -rf ~/Library/Logs/DeskPet ~/Library/Application\\ Support/DeskPet"
}

install() {
    [ "$(uname -s)" = "Darwin" ] || fail "macOS 전용"
    [ "$(uname -m)" = "arm64" ] || fail "Apple Silicon Mac(M1 이후) 전용. Intel Mac 미지원"
    local major
    major="$(sw_vers -productVersion | cut -d. -f1)"
    [ "$major" -ge 13 ] || fail "macOS 13 이상 필요 (현재 $(sw_vers -productVersion))"

    local dir
    dir="$(target_dir)"
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT
    local tmp="$TMP_DIR"

    say "· 내려받기: $URL"
    curl -fL --progress-bar "$URL" -o "$tmp/DeskPet.zip" || fail "내려받기 실패"
    ditto -x -k "$tmp/DeskPet.zip" "$tmp/unpacked" || fail "압축 풀기 실패"
    [ -d "$tmp/unpacked/$APP" ] || fail "압축 파일 안에 $APP 없음"

    mkdir -p "$dir"
    quit_app
    rm -rf "${dir:?}/$APP"
    mv "$tmp/unpacked/$APP" "$dir/$APP"
    say "✓ 설치: $dir/$APP"

    if [ "${DESKPET_NO_LAUNCH:-}" != "1" ]; then
        open "$dir/$APP"
        say "✓ 실행. 메뉴바의 👾 확인"
    fi
}

case "${1:-}" in
    --uninstall) uninstall ;;
    "") install ;;
    *) fail "알 수 없는 옵션: $1 (설치는 옵션 없이, 지우기는 --uninstall)" ;;
esac
