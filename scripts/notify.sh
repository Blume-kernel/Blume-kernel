#!/usr/bin/env bash

MODE="${1:?usage: notify.sh <success|failure|check|variant-failure>}"
set -e

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${TELEGRAM_TOKEN:-${BOT_TOKEN:-}}}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-${CHAT_ID:-}}"
TELEGRAM_BOT_TOKEN="$(printf '%s' "$TELEGRAM_BOT_TOKEN" | tr -d '[:space:]')"
TELEGRAM_CHAT_ID="$(printf '%s' "$TELEGRAM_CHAT_ID" | tr -d '[:space:]')"
TELEGRAM_TOPIC_ID="$(printf '%s' "${TELEGRAM_TOPIC_ID:-}" | tr -d '[:space:]')"

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo "[WARN] Telegram secrets not configured (BOT_TOKEN=${TELEGRAM_BOT_TOKEN:+set}${TELEGRAM_BOT_TOKEN:-empty}, CHAT_ID=${TELEGRAM_CHAT_ID:+set}${TELEGRAM_CHAT_ID:-empty}); skipping notification ($MODE)"
  exit 0
fi

# Strip accidental "-100-100..." duplication or add "-100" for bare 10+ digit supergroup IDs
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID/#-100-100/-100}"
[[ "$TELEGRAM_CHAT_ID" =~ ^[0-9]{10,}$ ]] && TELEGRAM_CHAT_ID="-100${TELEGRAM_CHAT_ID}"
echo "::add-mask::${TELEGRAM_BOT_TOKEN}"
echo "::add-mask::${TELEGRAM_CHAT_ID}"

_tg_check() {
  local LABEL="$1" RESP="$2"
  if printf '%s' "$RESP" | grep -q '"ok":true'; then
    echo "[OK] Telegram ${LABEL} sent"
  else
    echo "[ERROR] Telegram ${LABEL} failed: ${RESP}" >&2
    return 1
  fi
}

_tg_msg() {
  local RESP
  RESP=$(curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    ${TELEGRAM_TOPIC_ID:+--data-urlencode "message_thread_id=${TELEGRAM_TOPIC_ID}"} \
    --data-urlencode "text=$1" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview=true)
  _tg_check "message" "$RESP"
}

_tg_doc() {
  local FILE="$1" CAPTION="$2" RESP
  [ -f "$FILE" ] || return 0
  RESP=$(curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    ${TELEGRAM_TOPIC_ID:+-F "message_thread_id=${TELEGRAM_TOPIC_ID}"} \
    -F "document=@${FILE}" \
    -F "caption=${CAPTION}")
  _tg_check "document ($(basename "$FILE"))" "$RESP"
}

if [ "$MODE" = "success" ]; then
  : "${RUN_URL:?}" "${RUN_NUMBER:?}" "${START_TIME:?}"
  : "${RELEASE_URL:-}" "${BUILD_TYPE:-stable}"

  SHORT_SHA="${SHA:0:9}"
  DURATION=$(( $(date +%s) - START_TIME ))
  DATE_STR=$(date -u +'%Y-%m-%d')
  DISPLAY_TAG="${RELEASE_TAG}"
  DISPLAY_SUSFS="${SUSFS_VERSION}"
  UNAME_STR="${KERNEL_UNAME:-${KERNEL_VERSION:-unknown}}"

  [ "$BUILD_TYPE" = "testing" ] && { ICON="🧪"; LABEL="Testing build"; } || { ICON="✅"; LABEL="Build success"; }

  MSG="<b>${ICON} ${LABEL}</b>"$'\n\n'
  MSG="${MSG}<b>🔄</b> Blume-kernel · rtwo · run #${RUN_NUMBER}"$'\n'
  MSG="${MSG}<b>🏷️</b> <code>${DISPLAY_TAG}</code>"$'\n'
  MSG="${MSG}<b>🐧</b> <code>${UNAME_STR}</code>"$'\n'
  MSG="${MSG}<b>⏱️</b> $((DURATION/60))m $((DURATION%60))s"$'\n'
  MSG="${MSG}<b>🔨</b> <a href='https://github.com/${GITHUB_REPOSITORY}/commit/${SHA}'>${SHORT_SHA}</a>"$'\n\n'
  MSG="${MSG}<b>📦 Variants</b>"$'\n'
  MSG="${MSG}• KSU-Next + SUSFS"$'\n'
  MSG="${MSG}• Vanilla"$'\n'
  MSG="${MSG}<b>📦 SUSFS</b> <code>${DISPLAY_SUSFS}</code>"$'\n\n'
  MSG="${MSG}<b>📋</b> ${DATE_STR} · ${BUILD_TYPE}"$'\n'
  MSG="${MSG}<b>🔗</b> <a href='${RELEASE_URL}'>Release</a> · <a href='${RUN_URL}'>Logs</a>"
  _tg_msg "$MSG"

  for ZIP in ./release_zips/*.zip; do
    [ -f "$ZIP" ] || continue
    SIZE_MB=$(echo "scale=2; $(stat -c%s "$ZIP") / 1024 / 1024" | bc | sed 's/^\./0./')
    _tg_doc "$ZIP" "📦 $(basename "$ZIP") — ${SIZE_MB} MB"
  done

  if [ -n "${LOG_AUDIT_ZIP:-}" ] && [ -f "$LOG_AUDIT_ZIP" ]; then
    if (( $(echo "${LOG_AUDIT_SIZE_MB:-0} < 45" | bc -l) )); then
      _tg_doc "$LOG_AUDIT_ZIP" "📋 $(basename "$LOG_AUDIT_ZIP") — ${LOG_AUDIT_SIZE_MB} MB"
    else
      _tg_msg "📋 Log too large (${LOG_AUDIT_SIZE_MB} MB) — grab it from <a href='${RELEASE_URL}'>the release</a>."
    fi
  fi
elif [ "$MODE" = "failure" ]; then
  : "${RUN_URL:?}" "${RUN_NUMBER:?}"
  STATUS="${BUILD_STATUS:-failed}"
  [ "$STATUS" = "cancelled" ] && { ICON="⚠️"; LABEL="Cancelled"; } || { ICON="❌"; LABEL="Build failed"; }
  MSG="<b>${ICON} ${LABEL}</b>"$'\n\n'
  MSG="${MSG}<b>🔄</b> Blume-kernel · run #${RUN_NUMBER}"$'\n'
  MSG="${MSG}<b>🕐</b> $(date -u +'%Y-%m-%d %H:%M UTC')"$'\n'
  MSG="${MSG}<b>🔗</b> <a href='${RUN_URL}'>Logs</a>"
  _tg_msg "$MSG"
elif [ "$MODE" = "check" ]; then
  : "${RUN_URL:?}"
  DISPLAY_SUSFS_TAG="${CHECK_SUSFS_TAG:-?}"
  [ "${HAS_UPDATE:-false}" = "true" ] && STATUS_LINE="<b>🆕 Updates available</b>" || STATUS_LINE="<b>✅ All sources up to date</b>"
  MSG="<b>🔍 Source update check</b>"$'\n\n'
  MSG="${MSG}${STATUS_LINE}"$'\n\n'
  MSG="${MSG}<b>Moto 5.15:</b> <code>${CHECK_MOTO_SUB:-?}</code>"$'\n'
  MSG="${MSG}<b>KSU-Next:</b> <code>${CHECK_KSUN_TAG:-?}</code>"$'\n'
  MSG="${MSG}<b>WildKernels:</b> <code>${CHECK_WILDKERNELS_COMMIT:0:9}</code>"$'\n'
  MSG="${MSG}<b>SUSFS:</b> <code>${DISPLAY_SUSFS_TAG}</code>"$'\n'
  if [ "${HAS_UPDATE:-false}" = "true" ] && [ -n "${UPDATE_DETAIL:-}" ]; then
    MSG="${MSG}"$'\n'"<b>Changes:</b>"$'\n'
    while IFS= read -r LINE; do
      [ -z "$LINE" ] || MSG="${MSG}▸ ${LINE}"$'\n'
    done <<< "$UPDATE_DETAIL"
  fi
  MSG="${MSG}"$'\n\n'"<b>🔗</b> <a href='${RUN_URL}'>Run details</a>"
  _tg_msg "$MSG"
elif [ "$MODE" = "variant-failure" ]; then
  : "${RUN_URL:?}" "${RUN_NUMBER:?}" "${VARIANT:?}"
  LOG_FILE="/tmp/build_${SOURCE_TYPE:-gki}.log"
  ERRORS=""
  if [ -f "$LOG_FILE" ]; then
    ERRORS=$(grep -E " error:" "$LOG_FILE" | sed 's|.*/kernel_src/||; s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | awk '!seen[$0]++' | tail -20 | head -c 1800)
  fi
  [ "$BUILD_TYPE" = "testing" ] && TYPE_ICON="🧪" || TYPE_ICON="🔨"
  MSG="<b>❌ Build failed — ${VARIANT}</b>"$'\n\n'
  MSG="${MSG}<b>${TYPE_ICON}</b> ${BUILD_TYPE:-stable} · run #${RUN_NUMBER}"$'\n'
  MSG="${MSG}<b>🕐</b> $(date -u +'%H:%M UTC')"$'\n'
  MSG="${MSG}<b>🔗</b> <a href='${RUN_URL}'>Logs</a>"
  [ -z "$ERRORS" ] || MSG="${MSG}"$'\n\n'"<b>Errors:</b>"$'\n'"<pre>${ERRORS}</pre>"
  _tg_msg "$MSG"
else
  echo "[ERROR] Unknown mode: $MODE"
  exit 1
fi
