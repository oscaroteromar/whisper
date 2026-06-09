# Whisper push-to-talk for Claude Code — setup guide

Local voice input for the Claude Code VS Code extension (or any app): hold a
hotkey mindset, speak, get the text pasted automatically. No cloud, no
subscription, no Docker daemon. Runs `whisper.cpp` natively on macOS.

## Pipeline

```
Ctrl+Alt+Space
    → toggle.sh starts ffmpeg recording (● REC in menubar)
Ctrl+Alt+Space (again)
    → toggle.sh stops ffmpeg, whisper-cli transcribes → pbcopy
    → Hammerspoon sends Cmd+V (and Return, if auto-send hotkey)
```

## Files in this project

- `toggle.sh` — the state machine. First call starts recording, second call
  stops, transcribes, and copies to clipboard. Prints `RECORDING`, `PASTE`,
  or `EMPTY` so Hammerspoon knows what to do next.
- `hammerspoon-snippet.lua` — the two hotkey bindings. Paste into
  `~/.hammerspoon/init.lua`.
- `models/` — where the GGML model file lives (you download it below).

---

## Step 1 — Install dependencies

```sh
brew install whisper-cpp ffmpeg
brew install --cask hammerspoon
```

Verify:

```sh
whisper-cli --help | head -n 3
ffmpeg -version | head -n 1
```

If `whisper-cli` isn't found, your brew version may still ship the binary as
`whisper-cpp` — the script handles both, so you don't have to do anything.

## Step 2 — Download a model

```sh
mkdir -p ~/whisper/models
curl -L -o ~/whisper/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

Model choices (English-only variants are faster and usually more accurate for
English than the multilingual ones):

| Model            | Size   | Notes                              |
|------------------|--------|------------------------------------|
| `ggml-tiny.en`   | ~75 MB | Fastest, noticeable accuracy loss  |
| `ggml-base.en`   | ~140 MB| **Recommended** balanced default   |
| `ggml-small.en`  | ~460 MB| More accurate, still snappy        |
| `ggml-medium.en` | ~1.5 GB| Very accurate, latency climbs      |

Drop any of them in `models/` and point at them with the `WHISPER_MODEL`
env var if you want to swap without editing the script:

```sh
WHISPER_MODEL=~/whisper/models/ggml-small.en.bin ./toggle.sh
```

## Step 3 — Wire up Hammerspoon

1. Launch Hammerspoon (first run asks for permissions — grant **Accessibility**).
2. Click the menubar icon → **Open Config**. This opens `~/.hammerspoon/init.lua`.
3. Paste the contents of `hammerspoon-snippet.lua` into that file.
4. Menubar icon → **Reload Config**.

You should now have two hotkeys:

| Hotkey                    | Behavior                            |
|---------------------------|-------------------------------------|
| `Ctrl+Alt+Space`          | Toggle recording → paste + Return   |
| `Ctrl+Alt+Shift+Space`    | Toggle recording → paste only       |

They share state, so you can start with one and stop with the other — the
*stopping* key decides whether Return is sent. Useful when you change your
mind mid-sentence.

## Step 4 — Grant permissions

macOS will prompt the first time the hotkey fires. You need:

- **Microphone** → Hammerspoon
  (ffmpeg runs as a child of Hammerspoon and inherits this.)
- **Accessibility** → Hammerspoon
  (needed to synthesize `Cmd+V` and `Return` via `hs.eventtap`.)

System Settings → Privacy & Security → Microphone / Accessibility.

## Step 5 — Smoke test without the hotkey

Before you trust the hotkey flow, make sure the script itself works:

```sh
cd ~/whisper
./toggle.sh            # prints: RECORDING
# speak for 2-3 seconds
./toggle.sh            # prints: PASTE  (or EMPTY if silence)
pbpaste                # should show your transcribed text
```

If this works, the hotkey will work.

---

## Troubleshooting

**"model not found"** — you skipped Step 2, or the path doesn't match.
`ls ~/whisper/models/ggml-base.en.bin` should succeed.

**"whisper.cpp not found"** — `brew install whisper-cpp` didn't land on PATH.
Check `which whisper-cli` and make sure your shell picks up `/opt/homebrew/bin`.

**Hotkey does nothing** — Hammerspoon console (menubar → Console) will show
Lua errors. Common cause: init.lua wasn't reloaded after editing.

**Paste fires but text is empty / old** — Accessibility permission not yet
granted to Hammerspoon. Revoke and re-add it to force re-prompt.

**Wrong microphone picked up** — list devices and override:

```sh
ffmpeg -f avfoundation -list_devices true -i ""
# note the audio device index, e.g. [2] External Mic
export WHISPER_AUDIO_DEVICE=":2"
./toggle.sh
```

Put the `export` in your shell rc if you want it permanent, or hardcode it at
the top of `toggle.sh`.

**Latency feels high** — try `ggml-tiny.en` first to confirm it's the model
and not ffmpeg startup. `base.en` on Apple Silicon should come in well under
1.5s from stop-press to paste for typical 5–15s clips.

**Recording seems to keep running after stop** — stale PID file. Clean it:

```sh
rm -f "${TMPDIR:-/tmp}/whisper-ptt/ffmpeg.pid"
pkill -f "ffmpeg.*whisper-ptt" || true
```

## Possible upgrades (not implemented)

- **Hold-to-talk instead of toggle.** Bind `keyDown` → start, `keyUp` → stop
  in Hammerspoon using `hs.eventtap`. Feels more like Discord PTT. Toggle is
  friendlier when your hands leave the keyboard mid-thought.
- **Language auto-detect.** Drop `ggml-base.en.bin` for `ggml-base.bin` and
  remove the `.en` assumption if you want Spanish/Catalan/etc.
- **Beep feedback.** Add `hs.sound.getByName("Tink"):play()` on start/stop if
  the menubar indicator isn't enough.
- **VAD trimming.** Run the wav through `ffmpeg -af silenceremove` before
  whisper to drop leading/trailing silence — shaves a bit more latency.
- **Local LLM post-processing.** Pipe the transcript through a small local
  model to fix punctuation/capitalization before pasting.
