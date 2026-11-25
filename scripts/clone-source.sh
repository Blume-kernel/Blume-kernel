#!/usr/bin/env bash
set -e

: "${SOURCE_TYPE:?}"
: "${KERNEL_SRC:=$WORK_DIR/kernel_src}"

mkdir -p "$KERNEL_SRC"

case "$SOURCE_TYPE" in

  moto)
    MOTO_REPO="https://github.com/ctOS-rtwo/android_kernel_motorola_sm8550"
    PINS_FILE="${WORK_DIR:-$(pwd)}/sources/source-pins.json"
    MOTO_COMMIT=$(jq -r '.moto_commit // "13a9dd56c42b7d708542afab690ee7e419f0dc3a"' "$PINS_FILE" 2>/dev/null || echo "13a9dd56c42b7d708542afab690ee7e419f0dc3a")
    if [ "${MOTO_CACHE_HIT}" = "true" ] && [ -d "$KERNEL_SRC/.git" ]; then
      echo "[Moto] Cache hit — fetching commit $MOTO_COMMIT ..."
      git -C "$KERNEL_SRC" remote set-url origin "$MOTO_REPO"
      for attempt in 1 2 3; do
        git -C "$KERNEL_SRC" fetch origin --depth=1 "$MOTO_COMMIT" && \
          git -C "$KERNEL_SRC" reset --hard FETCH_HEAD && \
          git -C "$KERNEL_SRC" clean -fdx && break
        echo "⚠️ Fetch attempt $attempt failed, retrying in 30s..."
        sleep 30
      done
    else
      echo "[Moto] Cloning $MOTO_REPO @ $MOTO_COMMIT ..."
      for attempt in 1 2 3; do
        rm -rf "$KERNEL_SRC" && mkdir -p "$KERNEL_SRC"
        git -C "$KERNEL_SRC" init -q && \
          git -C "$KERNEL_SRC" remote add origin "$MOTO_REPO" && \
          git -C "$KERNEL_SRC" fetch origin --depth=1 "$MOTO_COMMIT" && \
          git -C "$KERNEL_SRC" checkout -f FETCH_HEAD && break
        echo "⚠️ Attempt $attempt failed, retrying in 30s..."
        sleep 30
      done
    fi
    ;;

  *)
    echo "[ERROR] Unknown source type: $SOURCE_TYPE"
    exit 1
    ;;
esac

echo "[OK] Source cloned → $KERNEL_SRC"
echo "KERNEL_SRC=$KERNEL_SRC" >> "${GITHUB_ENV:-/dev/null}"
