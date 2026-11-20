#!/bin/bash
# 모델 검증: 앱의 월드·펫·스킨 코드를 검사 실행 파일과 함께 컴파일해 시나리오를 돌림
# (Command Line Tools만 있으면 XCTest를 쓸 수 없어 별도 실행 파일로 대신함)
set -e

cd "$(dirname "$0")/.."
OUT_DIR=".build/checks"
mkdir -p "$OUT_DIR"

# 맥은 앱 스킨 로더(SpriteKit)와 SpriteForge까지, 그 밖(윈도우·리눅스)은 공통 코드와 검사만
case "$(uname -s)" in
    Darwin) PLATFORM=mac; EXE="" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM=windows; EXE=".exe" ;;
    *) PLATFORM=other; EXE="" ;;
esac

# 공통 코드(Core)는 맥 껍데기 없이 홀로 컴파일되고 맥 전용 모듈을 쓰지 않아야 함 (윈도우 이식 경계)
CORE_FILES=$(find Sources/DeskPet/Core -name '*.swift' | sort)
if grep -nE '^import (AppKit|SpriteKit|CoreGraphics|EventKit|CoreAudio|ImageIO|Cocoa|Quartz|AVFoundation)' $CORE_FILES; then
    echo "  ✗ Core에 맥 전용 import가 있음. Sources/DeskPet/Mac 쪽으로 옮길 것"
    exit 1
fi
swiftc -parse-as-library -typecheck $CORE_FILES
echo "  ✓ Core: 맥 껍데기 없이 홀로 컴파일"

# 검사는 공통 코드로 실행. 맥은 앱의 스킨 로더(SpriteKit)도 함께 컴파일해 실제 로드 경로를 확인함
PLATFORM_FILES=""
[ "$PLATFORM" = mac ] && PLATFORM_FILES="Sources/DeskPet/Mac/Skin/MacSprites.swift"
swiftc -parse-as-library \
    $CORE_FILES \
    $PLATFORM_FILES \
    scripts/checks/*.swift \
    -o "$OUT_DIR/deskpet-checks$EXE"

"$OUT_DIR/deskpet-checks$EXE" "${1:-Assets/Skins}"

# SpriteForge(캐릭터 제작 도구)는 맥 전용 (AppKit·ImageIO)
if [ "$PLATFORM" != mac ]; then
    echo "  · $PLATFORM: SpriteForge 일치 검사는 맥에서만"
    exit 0
fi

# SpriteForge로 만든 스킨이 리그와 일치하는지 (스킨 폴더를 손으로 고치지 않았는지) 확인
swift build --product SpriteForge > /dev/null 2>&1 || swift build --product SpriteForge
FORGE=".build/debug/SpriteForge"
for rig in Assets/Rigs/*.rig.json; do
    [ -e "$rig" ] || continue
    name="$(basename "$rig" .rig.json)"
    rm -rf "$OUT_DIR/forge/$name"
    "$FORGE" build "$rig" --out "$OUT_DIR/forge/$name" > /dev/null
    if diff -r "$OUT_DIR/forge/$name" "Assets/Skins/$name" > /dev/null; then
        echo "  ✓ $name: 스킨이 리그와 일치"
    else
        echo "  ✗ $name: 스킨이 리그와 다름. swift run SpriteForge build $rig 로 다시 만들 것"
        exit 1
    fi
done

# 원본 스킨의 매달리기 프레임이 설정(.hang.json)과 일치하는지 확인
for recipe in Assets/Rigs/*.hang.json; do
    [ -e "$recipe" ] || continue
    name="$(basename "$recipe" .hang.json)"
    # 공개 저장소에 없는 캐릭터(scripts/private-skins.txt)는 건너뜀
    [ -d "Assets/Skins/$name" ] || { echo "  · $name: 스킨 없음, 건너뜀"; continue; }
    rm -rf "$OUT_DIR/hang/$name"
    "$FORGE" hang "$recipe" --out "$OUT_DIR/hang/$name" > /dev/null
    hang_dir="$(cd "$OUT_DIR/hang/$name" && find . -type d -name Hang | head -1)"
    if [ -n "$hang_dir" ] && diff -r "$OUT_DIR/hang/$name/$hang_dir" "Assets/Skins/$name/$hang_dir" > /dev/null; then
        echo "  ✓ $name: 매달리기 프레임이 설정과 일치"
    else
        echo "  ✗ $name: 매달리기 프레임이 설정과 다름. swift run SpriteForge hang $recipe 로 다시 만들 것"
        exit 1
    fi
done

# 남의 시트로 만든 스킨이 가져오기 설정(.import.json)과 일치하는지 확인
for recipe in Assets/Rigs/*.import.json; do
    [ -e "$recipe" ] || continue
    name="$(basename "$recipe" .import.json)"
    rm -rf "$OUT_DIR/import/$name"
    "$FORGE" import "$recipe" --out "$OUT_DIR/import/$name" > /dev/null
    if diff -r "$OUT_DIR/import/$name" "Assets/Skins/$name" > /dev/null; then
        echo "  ✓ $name: 스킨이 가져오기 설정과 일치"
    else
        echo "  ✗ $name: 스킨이 설정과 다름. swift run SpriteForge import $recipe 로 다시 만들 것"
        exit 1
    fi
done
