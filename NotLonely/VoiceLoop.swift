import Foundation
import AVFoundation
import Porcupine
import Starscream
import SwiftWhisper
import AudioKit
import WatchConnectivity

// **User Action Required:**
// 1. Ensure you have Xcode installed to resolve Swift Package Manager dependencies automatically.
//    Alternatively, you can run `swift package resolve` in the terminal.
// 2. You will need to manually add the Porcupine library to your project.
//    Download the Porcupine iOS SDK and add it to your project.
// 3. In your project's `Info.plist`, add the key `NSMicrophoneUsageDescription`
//    with a string explaining why the app needs microphone access.
// 4. Obtain your AccessKey from Picovoice Console (https://console.picovoice.ai/)
//    and replace the placeholder below.
// 5. Create a "hey_not_lonely.ppn" wake word file from the Picovoice Console and
//    add it to your project's main bundle.
// 6. Download a whisper.cpp model (e.g., ggml-base.en.bin) from
//    https://huggingface.co/ggerganov/whisper.cpp/tree/main
//    and add it to your project's main bundle.

class VoiceLoop: NSObject, ObservableObject, NetworkingDelegate, WCSessionDelegate {
    @Published var messages: [ChatMessage] = []
    @Published var isPrivateModeEnabled = false
    @Published var isListening: Bool = false {
        didSet {
            if isListening {
                start()
            } else {
                stop()
            }
        }
    }

    @Published var backendURLString: String = "ws://localhost:8080/chat" {
        didSet {
            setupNetworking()
        }
    }

    @Published var personalityPrompt: String = ""
    
    private var porcupine: Porcupine?
    private let audioSession = AVAudioSession.sharedInstance()
    private let audioQueue = DispatchQueue(label: "audio-queue", qos: .userInitiated)
    private let audioEngine = AVAudioEngine()
    private var networking: Networking?
    private let ttsSynthesizer = AVSpeechSynthesizer()
    private var whisper: Whisper?
    
    private var audioRecorder: AVAudioRecorder?
    private var silenceTimer: Timer?
    private var isRecordingForSTT = false

    private var isStreaming = false

    private let ACCESS_KEY = "YOUR_ACCESS_KEY_HERE"
    // Removed hard-coded backend URL. Now configurable via `backendURLString`.

    override init() {
        super.init()
        
        setupNetworking()

        do {
            // Init Porcupine
            guard let keywordPath = Bundle.main.path(forResource: "I--m-not-lonely_en_ios_v3_0_0", ofType: "ppn") else {
                print("Error: Wake word file not found.")
                return
            }
            self.porcupine = try Porcupine(accessKey: ACCESS_KEY, keywordPath: keywordPath)

            // Init Whisper
            guard let modelURL = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin") else {
                print("Error: Whisper model not found.")
                return
            }
            self.whisper = Whisper(fromFileURL: modelURL)

        } catch {
            print("Error initializing: \(error)")
        }
    }

    func start() {
        audioQueue.async {
            self.startAudioEngine()
        }
    }

    func stop() {
        audioEngine.stop()
        networking?.disconnect()
        isStreaming = false
    }

    private func startAudioEngine() {
        do {
            // Configure the audio session for Bluetooth (AirPods) I/O
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat, // tuned for speech capture & playback
                options: [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .mixWithOthers
                ]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Prefer AirPods as the audio route when available
            configureAudioRouteToAirPods()

            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                   sampleRate: Double(Porcupine.sampleRate),
                                                   channels: 1,
                                                   interleaved: false) else {
                print("Failed to create required audio format")
                return
            }

            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { (buffer, _) in
                let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                 frameCapacity: AVAudioFrameCount(outputFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate))!
                
                var error: NSError? = nil
                let status = converter.convert(to: pcmBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                guard status != .error else {
                    print("Error converting audio buffer: \(error?.localizedDescription ?? "unknown error")")
                    return
                }

                let channelData = pcmBuffer.int16ChannelData![0]
                let frameLength = Int(pcmBuffer.frameLength)
                let audioFrame = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

                do {
                    if !self.isStreaming {
                        let keywordIndex = try self.porcupine?.process(pcm: audioFrame)
                        if keywordIndex == 0 {
                            // Wake word detected!
                            print("Wake word detected!")
                            if self.isPrivateModeEnabled {
                                self.startRecordingForSTT()
                            } else {
                                self.isStreaming = true
                                self.networking?.connect()
                            }
                        }
                    } else {
                        let data = Data(buffer: UnsafeBufferPointer(start: audioFrame, count: audioFrame.count))
                        self.networking?.send(data: data)
                    }
                } catch {
                    print("Error processing audio: \(error)")
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            print("Audio engine started.")

        } catch {
            print("Error setting up audio engine: \(error)")
        }
    }

    private func startRecordingForSTT() {
        print("Starting recording for STT...")
        isRecordingForSTT = true
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stt-recording.wav")
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            // Start a timer to check for silence
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.checkForSilence()
            }

        } catch {
            print("Failed to start STT recording: \(error)")
        }
    }
    
    private func stopRecordingAndTranscribe() {
        print("Stopping recording.")
        isRecordingForSTT = false
        silenceTimer?.invalidate()
        audioRecorder?.stop()
        
        guard let url = audioRecorder?.url else { return }
        
        Task {
            do {
                let pcmArray = try await self.convertAudioFileToPCMArray(fileURL: url)
                let segments = try await self.whisper!.transcribe(audioFrames: pcmArray)
                let transcribedText = segments.map(\.text).joined()
                print("Transcribed text: \(transcribedText)")
                
                // Add user message to chat
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage(text: transcribedText, sender: .user))
                }
                
                // TODO: Send text to backend in proper AudioFrame format
                self.networking?.connect()
                self.networking?.send(string: transcribedText)

            } catch {
                print("Error during transcription: \(error)")
            }
        }
    }
    
    private func checkForSilence() {
        audioRecorder?.updateMeters()
        if let power = audioRecorder?.averagePower(forChannel: 0) {
            print("Audio power: \(power)")
            // A simple silence detection logic. This needs tuning.
            if power < -40 { // This threshold is arbitrary
                print("Silence detected, stopping recording.")
                stopRecordingAndTranscribe()
            }
        }
    }
    
    // From SwiftWhisper README, using AudioKit
    private func convertAudioFileToPCMArray(fileURL: URL) async throws -> [Float] {
        var options = FormatConverter.Options()
        options.format = .wav
        options.sampleRate = 16000
        options.bitDepth = 16
        options.channels = 1
        options.isInterleaved = false

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let converter = FormatConverter(inputURL: fileURL, outputURL: tempURL, options: options)
        
        return try await withCheckedThrowingContinuation { continuation in
            converter.start { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                do {
                    let data = try Data(contentsOf: tempURL)
                    let floats = stride(from: 44, to: data.count, by: 2).map {
                        return data[$0..<$0 + 2].withUnsafeBytes {
                            let short = Int16(littleEndian: $0.load(as: Int16.self))
                            return max(-1.0, min(Float(short) / 32767.0, 1.0))
                        }
                    }
                    try? FileManager.default.removeItem(at: tempURL)
                    continuation.resume(returning: floats)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    private func setupNetworking() {
        guard let url = URL(string: backendURLString) else {
            print("Invalid backend URL: \(backendURLString)")
            return
        }

        networking?.disconnect()
        networking = Networking(url: url)
        networking?.delegate = self
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("WCSession activation complete.")
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        // We don't need to do anything here for this app
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        // We don't need to do anything here for this app
        // Reactivate the session if needed
        WCSession.default.activate()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let action = message["action"] as? String, action == "tapToTalk" {
            print("Received tapToTalk message from watch.")
            // Trigger recording on the main thread
            DispatchQueue.main.async {
                self.startRecordingForSTT()
            }
        }
    }

    // MARK: - NetworkingDelegate

    func networkingDidConnect() {
        print("Networking connected.")
        if !personalityPrompt.isEmpty {
            networking?.send(string: personalityPrompt)
        }
    }

    func networkingDidDisconnect() {
        print("Networking disconnected.")
        isStreaming = false
    }

    func networkingDidReceiveMessage(message: String) {
        print("Received message: \(message)")
        // The spec defines AssistantFrame with partial_text or tts_chunk.
        // For now, we assume we get a final string.
        // We need to parse the incoming message to see what it is.
        // Assuming a simple JSON structure for now like: {"partial_text": "..."}
        
        // A more robust implementation would decode the protobuf AssistantFrame
        let newMessage = ChatMessage(text: message, sender: .assistant)
        
        DispatchQueue.main.async {
            self.messages.append(newMessage)
            self.speak(message)
        }
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // As per spec, use iOS 18 neural voices if available, otherwise default.
        if #available(iOS 18.0, *) {
            // This is how you would select a specific neural voice if you know its identifier
            // let voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Samantha")
            // utterance.voice = voice
            // For now, we just let it pick a default one.
        } else {
            // Fallback on earlier versions
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        ttsSynthesizer.speak(utterance)
    }

    deinit {
        porcupine?.delete()
    }

    /// If the user has AirPods (or any Bluetooth headset) connected, make it the preferred input.
    private func configureAudioRouteToAirPods() {
        guard let bluetoothInput = audioSession.availableInputs?.first(where: { input in
            input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP
        }) else { return }

        do {
            try audioSession.setPreferredInput(bluetoothInput)
            print("Audio route set to Bluetooth: \(bluetoothInput.portName)")
        } catch {
            print("Failed to set preferred Bluetooth input: \(error)")
        }
    }
} 
