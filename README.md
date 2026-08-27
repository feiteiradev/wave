# Wave

A private, local-first macOS dictation utility: speak naturally and the text
appears wherever your cursor is. Portuguese (Portugal) is the default language
and the primary quality target.

> Press → Speak → Release → Text appears.

Dictation makes **zero network requests**. The only thing that needs the
internet is explicitly downloading a model.

## Build

```sh
make test    # 121 unit tests
make app     # builds and signs build/Wave.app
make run     # builds, signs and launches
```

`Scripts/make-app.sh` signs with an Apple Development identity and a fixed
bundle ID. This matters: macOS keys the Microphone and Accessibility grants to
the signing identity, so an ad-hoc signature would silently revoke Accessibility
on every rebuild. Override with `SIGN_IDENTITY=…` if you need a different one.

Insertion cannot be unit-tested — it writes through the Accessibility API into
whatever app is focused — so `make app` then
`open -na build/Wave.app --args --wave-probe` runs the real fallback chain
against the focused app and writes the winning rung to
`~/Library/Logs/Wave/probe.log`.

## First run

Onboarding asks for Microphone and Accessibility, shows the hotkeys, and
downloads a speech model. It cannot finish until a model is installed and
validated — Wave cannot dictate without one.

Defaults: `⌥Space` for Clean, `⌥⇧Space` for Raw, push-to-talk.

## Layout

| Target | What lives there |
| --- | --- |
| `WaveCore` | Pure logic — dictation state machine, cleanup rules, vocabulary, chunking, insertion chain, model manager, diagnostics. Foundation only, fully unit-tested. |
| `WavePlatform` | macOS integration — audio capture, global hotkeys, Accessibility insertion, WhisperKit STT, MLX cleanup LLM, model downloads. |
| `WaveApp` | Menu bar, notch HUD, Settings, onboarding. |

Speech recognition and cleanup sit behind the `STTEngine` and `CleanupEngine`
protocols, so models and runtimes can be replaced without touching the rest.

## Privacy

Audio lives in memory only and is dropped as soon as it is transcribed. There is
no transcription history. Logs hold durations, model names and which insertion
method was used — the event type is a closed enum of metadata-only cases, so
transcribed text has no way into a log line. Logs are capped at 7 days and 10 MB.
