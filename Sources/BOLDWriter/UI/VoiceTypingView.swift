import AppKit
import AVFoundation
import Foundation
import Speech
import SwiftUI

enum VoiceTypingText {
    static func cleanedTranscript(
        _ value: String
    ) -> String {
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    static func insertionText(
        transcript: String,
        documentText: String,
        replacementRange: NSRange
    ) -> String {
        let cleaned =
            cleanedTranscript(
                transcript
            )

        guard !cleaned.isEmpty else {
            return ""
        }

        let source =
            documentText as NSString

        guard
            replacementRange.location != NSNotFound,
            replacementRange.location <= source.length,
            replacementRange.length <= source.length - replacementRange.location
        else {
            return cleaned
        }

        var result =
            cleaned

        let start =
            replacementRange.location

        let end =
            NSMaxRange(
                replacementRange
            )

        if start > 0 {
            let previous =
                source.substring(
                    with:
                        NSRange(
                            location:
                                start - 1,
                            length:
                                1
                        )
                )

            if needsLeadingSpace(
                after:
                    previous
            ) {
                result =
                    " " + result
            }
        }

        if end < source.length {
            let next =
                source.substring(
                    with:
                        NSRange(
                            location:
                                end,
                            length:
                                1
                        )
                )

            if needsTrailingSpace(
                before:
                    next
            ) {
                result +=
                    " "
            }
        }

        return result
    }

    static func attributedReplacement(
        transcript: String,
        documentText: String,
        replacementRange: NSRange,
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        NSAttributedString(
            string:
                insertionText(
                    transcript:
                        transcript,
                    documentText:
                        documentText,
                    replacementRange:
                        replacementRange
                ),
            attributes:
                typingAttributes
        )
    }

    private static func needsLeadingSpace(
        after value: String
    ) -> Bool {
        guard
            let scalar =
                value.unicodeScalars.first
        else {
            return false
        }

        if CharacterSet
            .whitespacesAndNewlines
            .contains(
                scalar
            ) {
            return false
        }

        return !"([{\"'“‘—–/"
            .unicodeScalars
            .contains(
                scalar
            )
    }

    private static func needsTrailingSpace(
        before value: String
    ) -> Bool {
        guard
            let scalar =
                value.unicodeScalars.first
        else {
            return false
        }

        if CharacterSet
            .whitespacesAndNewlines
            .contains(
                scalar
            ) {
            return false
        }

        return !".,;:!?)]}\"'”’—–/"
            .unicodeScalars
            .contains(
                scalar
            )
    }
}

@MainActor
final class VoiceTypingSession: NSObject, ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var statusText = "Ready"
    @Published private(set) var errorMessage: String?

    private let audioEngine =
        AVAudioEngine()

    private var recognitionRequest:
        SFSpeechAudioBufferRecognitionRequest?

    private var recognitionTask:
        SFSpeechRecognitionTask?

    private var tapInstalled =
        false

    func start() {
        guard !isRecording else {
            return
        }

        transcript =
            ""

        errorMessage =
            nil

        statusText =
            "Requesting permission…"

        SFSpeechRecognizer.requestAuthorization {
            [weak self]
            speechStatus in

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                guard speechStatus == .authorized else {
                    self.statusText =
                        "Permission required"

                    self.errorMessage =
                        Self.speechPermissionMessage(
                            speechStatus
                        )

                    return
                }

                self.requestMicrophonePermission()
            }
        }
    }

    func stop() {
        stopAudio(
            cancel:
                false
        )

        isRecording =
            false

        statusText =
            transcript.isEmpty
                ? "Stopped"
                : "Transcript ready"
    }

    func cancel() {
        stopAudio(
            cancel:
                true
        )

        isRecording =
            false
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(
            for:
                .audio
        ) {
        case .authorized:
            beginRecognition()

        case .notDetermined:
            AVCaptureDevice.requestAccess(
                for:
                    .audio
            ) {
                [weak self]
                granted in

                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    if granted {
                        self.beginRecognition()
                    } else {
                        self.statusText =
                            "Permission required"

                        self.errorMessage =
                            "Microphone permission was not granted."
                    }
                }
            }

        case .denied:
            statusText =
                "Permission required"

            errorMessage =
                "Microphone permission is denied. Enable it for BOLD Writer in System Settings → Privacy & Security → Microphone."

        case .restricted:
            statusText =
                "Unavailable"

            errorMessage =
                "Microphone access is restricted on this Mac."

        @unknown default:
            statusText =
                "Unavailable"

            errorMessage =
                "Microphone permission is unavailable."
        }
    }

    private func beginRecognition() {
        stopAudio(
            cancel:
                true
        )

        guard
            let recognizer =
                SFSpeechRecognizer(
                    locale:
                        Locale.current
                )
        else {
            statusText =
                "Unavailable"

            errorMessage =
                "Speech recognition is unavailable for the current language."

            return
        }

        guard recognizer.isAvailable else {
            statusText =
                "Unavailable"

            errorMessage =
                "Speech recognition is temporarily unavailable."

            return
        }

        let request =
            SFSpeechAudioBufferRecognitionRequest()

        request.shouldReportPartialResults =
            true

        recognitionRequest =
            request

        recognitionTask =
            recognizer.recognitionTask(
                with:
                    request
            ) {
                [weak self]
                result,
                error in

                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    if let result {
                        self.transcript =
                            VoiceTypingText.cleanedTranscript(
                                result
                                    .bestTranscription
                                    .formattedString
                            )

                        self.statusText =
                            result.isFinal
                                ? "Transcript ready"
                                : "Listening…"

                        if result.isFinal {
                            self.stopAudio(
                                cancel:
                                    false
                            )

                            self.isRecording =
                                false
                        }
                    }

                    if let error {
                        if self.transcript.isEmpty {
                            self.errorMessage =
                                error.localizedDescription
                        }

                        self.stopAudio(
                            cancel:
                                true
                        )

                        self.isRecording =
                            false

                        self.statusText =
                            self.transcript.isEmpty
                                ? "Stopped"
                                : "Transcript ready"
                    }
                }
            }

        let input =
            audioEngine.inputNode

        let format =
            input.outputFormat(
                forBus:
                    0
            )

        guard
            format.sampleRate > 0,
            format.channelCount > 0
        else {
            stopAudio(
                cancel:
                    true
            )

            statusText =
                "Unavailable"

            errorMessage =
                "No usable microphone input is available."

            return
        }

        input.installTap(
            onBus:
                0,
            bufferSize:
                1024,
            format:
                format
        ) {
            [weak request]
            buffer,
            _ in

            request?
                .append(
                    buffer
                )
        }

        tapInstalled =
            true

        do {
            audioEngine.prepare()

            try audioEngine.start()

            isRecording =
                true

            statusText =
                "Listening…"
        } catch {
            stopAudio(
                cancel:
                    true
            )

            statusText =
                "Could not start"

            errorMessage =
                error.localizedDescription
        }
    }

    private func stopAudio(
        cancel: Bool
    ) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if tapInstalled {
            audioEngine
                .inputNode
                .removeTap(
                    onBus:
                        0
                )

            tapInstalled =
                false
        }

        if cancel {
            recognitionTask?
                .cancel()

            recognitionTask =
                nil
        } else {
            recognitionRequest?
                .endAudio()
        }

        recognitionRequest =
            nil
    }

    private static func speechPermissionMessage(
        _ status:
            SFSpeechRecognizerAuthorizationStatus
    ) -> String {
        switch status {
        case .denied:
            return "Speech Recognition permission is denied. Enable it for BOLD Writer in System Settings → Privacy & Security → Speech Recognition."
        case .restricted:
            return "Speech Recognition is restricted on this Mac."
        case .notDetermined:
            return "Speech Recognition permission has not been granted."
        case .authorized:
            return ""
        @unknown default:
            return "Speech Recognition permission is unavailable."
        }
    }
}

struct VoiceTypingView: View {
    let onInsert:
        (String) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @StateObject
    private var session =
        VoiceTypingSession()

    var body: some View {
        VStack(
            alignment:
                .leading,
            spacing:
                16
        ) {
            HStack {
                Image(
                    systemName:
                        session.isRecording
                            ? "mic.fill"
                            : "mic"
                )
                .font(
                    .system(
                        size:
                            30
                    )
                )

                VStack(
                    alignment:
                        .leading,
                    spacing:
                        3
                ) {
                    Text(
                        "Voice Typing"
                    )
                    .font(
                        .title2.bold()
                    )

                    Text(
                        session.statusText
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()
            }

            Text(
                "Speak naturally. The live transcript appears below. Your document changes only when you choose Insert."
            )
            .font(
                .caption
            )
            .foregroundStyle(
                .secondary
            )

            ScrollView {
                Text(
                    session.transcript.isEmpty
                        ? "Your transcript will appear here."
                        : session.transcript
                )
                .foregroundStyle(
                    session.transcript.isEmpty
                        ? .secondary
                        : .primary
                )
                .textSelection(
                    .enabled
                )
                .frame(
                    maxWidth:
                        .infinity,
                    minHeight:
                        180,
                    alignment:
                        .topLeading
                )
                .padding(
                    12
                )
            }
            .background(
                Color(
                    nsColor:
                        .textBackgroundColor
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius:
                        7
                )
            )

            if let errorMessage =
                session.errorMessage {

                Text(
                    errorMessage
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .red
                )
                .textSelection(
                    .enabled
                )
            }

            HStack {
                Button(
                    "Cancel"
                ) {
                    session.cancel()
                    dismiss()
                }
                .keyboardShortcut(
                    .cancelAction
                )

                Spacer()

                if session.isRecording {
                    Button(
                        "Stop"
                    ) {
                        session.stop()
                    }
                } else {
                    Button(
                        "Start Listening"
                    ) {
                        session.start()
                    }
                }

                Button(
                    "Insert"
                ) {
                    let value =
                        VoiceTypingText.cleanedTranscript(
                            session.transcript
                        )

                    guard !value.isEmpty else {
                        return
                    }

                    session.stop()
                    onInsert(value)
                    dismiss()
                }
                .buttonStyle(
                    .borderedProminent
                )
                .disabled(
                    VoiceTypingText
                        .cleanedTranscript(
                            session.transcript
                        )
                        .isEmpty
                )
                .keyboardShortcut(
                    .defaultAction
                )
            }
        }
        .padding(
            20
        )
        .frame(
            width:
                560
        )
        .onDisappear {
            session.cancel()
        }
    }
}
