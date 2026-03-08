#!/bin/sh
# x-ray 설치/삭제 스크립트
#
# 설치:
#   curl -sSfL https://raw.githubusercontent.com/cclss/x-ray-releases/main/install.sh | sh
#
# 삭제:
#   curl -sSfL https://raw.githubusercontent.com/cclss/x-ray-releases/main/install.sh | sh -s -- --uninstall
#
# 환경변수:
#   INSTALL_DIR  — 설치 경로 (기본: /usr/local/bin)
#   VERSION      — 특정 버전 설치 (기본: 최신)

set -e

REPO="cclss/x-ray-releases"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# OS/Arch 감지
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$OS" in
        linux)  OS="linux" ;;
        darwin) OS="darwin" ;;
        *)
            echo "지원하지 않는 OS: $OS" >&2
            exit 1
            ;;
    esac

    case "$ARCH" in
        x86_64|amd64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)
            echo "지원하지 않는 아키텍처: $ARCH" >&2
            exit 1
            ;;
    esac
}

# 최신 버전 조회
get_latest_version() {
    if [ -n "$VERSION" ]; then
        echo "$VERSION"
        return
    fi

    curl -sSf "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name"' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

# 설치
install() {
    detect_platform

    VERSION_TAG=$(get_latest_version)
    if [ -z "$VERSION_TAG" ]; then
        echo "버전 정보를 가져올 수 없습니다." >&2
        exit 1
    fi

    # v 접두사 제거 (파일명용)
    VERSION_NUM="${VERSION_TAG#v}"

    ARCHIVE="x-ray_${VERSION_NUM}_${OS}_${ARCH}.tar.gz"
    URL="https://github.com/${REPO}/releases/download/${VERSION_TAG}/${ARCHIVE}"
    CHECKSUM_URL="https://github.com/${REPO}/releases/download/${VERSION_TAG}/checksums.txt"

    echo "x-ray ${VERSION_TAG} 설치 중 (${OS}/${ARCH})..."

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    # 아카이브 다운로드
    curl -sSfL -o "${TMP_DIR}/${ARCHIVE}" "$URL"

    # 체크섬 검증
    curl -sSfL -o "${TMP_DIR}/checksums.txt" "$CHECKSUM_URL"
    cd "$TMP_DIR"

    if command -v sha256sum > /dev/null 2>&1; then
        grep "$ARCHIVE" checksums.txt | sha256sum -c --quiet
    elif command -v shasum > /dev/null 2>&1; then
        grep "$ARCHIVE" checksums.txt | shasum -a 256 -c --quiet
    else
        echo "경고: sha256 검증 도구를 찾을 수 없습니다. 체크섬 검증을 건너뜁니다." >&2
    fi

    # 압축 해제 & 설치
    tar xzf "$ARCHIVE"

    if [ ! -w "$INSTALL_DIR" ]; then
        echo "sudo 권한으로 ${INSTALL_DIR}에 설치합니다..."
        sudo install -m 755 x-ray "$INSTALL_DIR/x-ray"
    else
        install -m 755 x-ray "$INSTALL_DIR/x-ray"
    fi

    echo ""
    echo "설치 완료: ${INSTALL_DIR}/x-ray"
    "${INSTALL_DIR}/x-ray" version
}

# 삭제
uninstall() {
    BINARY_PATH="${INSTALL_DIR}/x-ray"

    if [ ! -f "$BINARY_PATH" ]; then
        echo "x-ray가 ${INSTALL_DIR}에 설치되어 있지 않습니다." >&2
        exit 1
    fi

    echo "삭제 대상:"
    echo "  바이너리: ${BINARY_PATH}"

    # Docker 이미지 확인
    DOCKER_IMAGES=""
    if command -v docker > /dev/null 2>&1; then
        DOCKER_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep 'x-ray-' || true)
    fi

    if [ -n "$DOCKER_IMAGES" ]; then
        echo "  Docker 이미지:"
        echo "$DOCKER_IMAGES" | while read -r img; do
            echo "    $img"
        done
    fi

    echo ""
    printf "삭제하시겠습니까? [y/N] "
    read -r CONFIRM
    case "$CONFIRM" in
        [yY]|[yY][eE][sS]) ;;
        *)
            echo "취소됨."
            exit 0
            ;;
    esac

    # 바이너리 삭제
    if [ ! -w "$INSTALL_DIR" ]; then
        sudo rm -f "$BINARY_PATH"
    else
        rm -f "$BINARY_PATH"
    fi
    echo "바이너리 삭제 완료."

    # Docker 이미지 삭제
    if [ -n "$DOCKER_IMAGES" ]; then
        echo "$DOCKER_IMAGES" | while read -r img; do
            docker rmi "$img" 2>/dev/null || true
        done
        echo "Docker 이미지 삭제 완료."
    fi

    echo ""
    echo "x-ray 삭제 완료."
}

# 인자 파싱
case "${1:-}" in
    --uninstall|uninstall)
        uninstall
        ;;
    *)
        install
        ;;
esac
