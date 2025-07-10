# Not Lonely – iOS App (v0.1) — Design Spec for Coding Agent

MISSION  
Ship a **native Swift/SwiftUI** iOS app that pairs with AirPods, detects a custom wake-word, captures user speech, streams it to the backend service, and plays the TTS reply—all with an opt-in *Private Mode* that runs on-device STT.  UX must feel hands-free and latency <900 ms RTT on 5 G.

––– 1. High-Level Flow –––
AirPods mic ─► Porcupine wake-word ─► AVAudioEngine ring buffer  
    └─(Private Mode) whisper.cpp → UTF-8 text ─► WebSocket/gRPC  
    └─(Cloud Mode) 16-kHz PCM frames ─► WebSocket/gRPC  
Backend returns `llm_text` → (optional on-device TTS) → `AVSpeechSynthesizer` → AirPods

––– 2. Core Framework Choices –––
* **Wake-word**  Porcupine iOS SDK (`hey_not_lonely.ppn`)  
* **Audio I/O**  `AVAudioSession` + `AVAudioEngine.installTap`  
* **On-device STT**  `whisper.cpp` via Metal (toggle)  
* **Transport**  `gRPC-Swift` (HTTP/2) or fallback `Starscream` WebSocket  
* **TTS playback**  `AVSpeechSynthesizer` (iOS-18 neural voices) or remote PCM stream  
* **UI**  SwiftUI + Combine; minimal screens: ChatLog, Settings, Onboarding

––– 3. Packet Contract (sync with backend spec) –––
```proto
message AudioFrame { oneof { bytes pcm = 1; string text = 2; } }
message AssistantFrame { oneof { string partial_text = 1; bytes tts_chunk = 2; } }
service NotLonely { rpc Chat(stream AudioFrame) returns (stream AssistantFrame); }
```

––– 4. App States –––

1. **Foreground**  Always-listening after wake-word.
2. **Background**  Push-to-Talk fallback (tap in Dynamic Island / Watch).
3. **Low Power**  Disable mic after 5 min idle, ask user to re-arm.

––– 5. Privacy & Permissions –––

* Request `Microphone`, `Bluetooth`, `SpeechRecognition` capabilities.
* Show plain-language consent & toggle for “Private Mode (no audio leaves device).”
* All outbound traffic TLS 1.3; embed backend’s certificate pin (ATS).

––– 6. Performance Targets –––

* Wake-word latency ≤150 ms.
* Private Mode: STT RTF ≤0.9 on A17-Pro.
* End-to-end voice round-trip ≤900 ms 90-th percentile over 5 G.

––– 7. Deliverables –––

* **Xcode project** `NotLonely.xcodeproj` (Swift 5.9, iOS 17+).
* `VoiceLoop.swift` (wake-word, audio tap, WebSocket stream).
* `ChatView.swift` (conversation list with partial token rendering).
* `SettingsView.swift` (Private Mode, provider picker).
* `WatchKit Extension` (tap-to-talk complication).
* Unit tests for wake-word, STT pipeline, WebSocket reconnect.
* Fastlane lane `beta` → TestFlight upload.

––– 8. CI / CD –––

* GitHub Actions: lint (SwiftFormat), build (xcodebuild + xcode-test), upload dSYMs.
* Secrets: `APP_STORE_CONNECT_API_KEY`, `PV_ACCESS_KEY`.
* Increment build number on each merge to `main`.

––– 9. Milestones –––
W1  Wake-word + local audio capture prototype.
W3  Streaming to backend, receives text replies.
W5  TTS playback + partial tokens; UI polish.
W6  Private Mode (whisper.cpp) + background Push-to-Talk.
W8  Beta TestFlight, crash-free sessions ≥98 %.
W10  App Store launch with subscription IAP stub.

Outcome: a streamlined, privacy-respecting iOS client that talks fluently with the modular backend and can be extended to Android or desktop later with the same gRPC contract.
