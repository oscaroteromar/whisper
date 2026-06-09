#!/bin/bash
# Whisper push-to-talk toggle script.
#
# First invocation  -> starts ffmpeg recording in the background, prints RECORDING
# Second invocation -> stops ffmpeg, runs whisper.cpp, copies text to clipboard,
#                      prints PASTE (or EMPTY if nothing was transcribed)
#
# Hammerspoon reads the printed keyword to decide whether to send Cmd+V + Return.

set -euo pipefail

# Hammerspoon (and other GUI launchers) spawn children with a bare PATH that
# doesn't include Homebrew, so whisper-cli / ffmpeg come back "not found" even
# when they're installed. Prepend both brew prefixes so this works whether the
# script is invoked from an interactive shell or from Hammerspoon.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi
STATE_DIR="${TMPDIR:-/tmp}/whisper-ptt"
mkdir -p "$STATE_DIR"
PID_FILE="$STATE_DIR/ffmpeg.pid"
LANG_FILE="$STATE_DIR/language"
WAV_FILE="$STATE_DIR/recording.wav"
OUT_PREFIX="$STATE_DIR/out"

MODEL="${WHISPER_MODEL:-$SCRIPT_DIR/models/ggml-small.bin}"
# avfoundation device spec. `:0` = no video, default audio input.
# List devices with: ffmpeg -f avfoundation -list_devices true -i ""
AUDIO_DEVICE="${WHISPER_AUDIO_DEVICE:-:0}"
LANGUAGE=""

while getopts "l:" opt; do
  case "$opt" in
    l) LANGUAGE="$OPTARG" ;;
    *) ;;
  esac
done

# brew's whisper-cpp formula installs the CLI as `whisper-cli` in recent
# versions; fall back to `whisper-cpp` for older installs.
if command -v whisper-cli >/dev/null 2>&1; then
  WHISPER_BIN=whisper-cli
elif command -v whisper-cpp >/dev/null 2>&1; then
  WHISPER_BIN=whisper-cpp
else
  echo "ERROR: whisper.cpp not found. Run: brew install whisper-cpp" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ERROR: ffmpeg not found. Run: brew install ffmpeg" >&2
  exit 1
fi

if [[ ! -f "$MODEL" ]]; then
  echo "ERROR: model not found at $MODEL" >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  # ---------- STOP ----------
  PID=$(cat "$PID_FILE")
  # SIGINT lets ffmpeg flush the WAV trailer; SIGKILL would corrupt the file.
  kill -INT "$PID" 2>/dev/null || true
  for _ in $(seq 1 40); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.05
  done
  rm -f "$PID_FILE"

  # Recover the language saved when recording started.
  if [[ -z "$LANGUAGE" && -f "$LANG_FILE" ]]; then
    LANGUAGE="$(cat "$LANG_FILE")"
  fi
  rm -f "$LANG_FILE"

  EXTRA_FLAGS=()
  if [[ -n "$LANGUAGE" ]]; then
    EXTRA_FLAGS+=(-l "$LANGUAGE")
  else
    EXTRA_FLAGS+=(-tr)
  fi

  "$WHISPER_BIN" \
    -m "$MODEL" \
    -f "$WAV_FILE" \
    ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} \
    -nt \
    -otxt \
    -of "$OUT_PREFIX" \
    >/dev/null 2>&1

  TEXT=$(cat "${OUT_PREFIX}.txt" 2>/dev/null || true)
  # Trim leading/trailing whitespace.
  TEXT="${TEXT#"${TEXT%%[![:space:]]*}"}"
  TEXT="${TEXT%"${TEXT##*[![:space:]]}"}"

  if [[ -z "$TEXT" ]]; then
    echo "EMPTY"
    exit 0
  fi

  printf '%s' "$TEXT" | pbcopy
  echo "PASTE"
else
  # ---------- START ----------
  rm -f "$WAV_FILE"
  # Persist language so the stop invocation can use it.
  if [[ -n "$LANGUAGE" ]]; then
    printf '%s' "$LANGUAGE" > "$LANG_FILE"
  else
    rm -f "$LANG_FILE"
  fi
  # 16 kHz mono is what whisper.cpp expects internally — giving it that
  # directly avoids an internal resample and trims a bit of latency.
  nohup ffmpeg -y \
    -f avfoundation -i "$AUDIO_DEVICE" \
    -ac 1 -ar 16000 \
    "$WAV_FILE" \
    </dev/null >/dev/null 2>&1 &
  echo $! > "$PID_FILE"
  disown || true
  echo "RECORDING"
fi
