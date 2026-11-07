import AVFoundation
import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "System"
    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Label("General", systemImage: "gear") }
            EditingSettingsView().tabItem { Label("Editing", systemImage: "pencil") }
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
            SpeechSettingsView().tabItem { Label("Read Aloud", systemImage: "speaker.wave.2") }
            PrivacySettingsView().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }.frame(width: 620, height: 430)
            .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("defaultFont") private var font = "Helvetica"
    @AppStorage("defaultFontSize") private var size = 15.0
    @AppStorage("appearance") private var appearance = "System"
    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) { Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark") }
            TextField("Default font", text: $font)
            Stepper("Default size: \(Int(size)) pt", value: $size, in: 8...48)
            Text("BOLD Writer autosaves through macOS document architecture. Create named recovery points from File > Save Version.").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }
}

struct EditingSettingsView: View {
    @AppStorage("writingPreferences") private var preferences = "Preserve my voice and intended meaning. Use clear, direct prose."
    var body: some View {
        Form {
            Section("Writing Preferences") {
                Text("These instructions stay on this Mac and are included only when you deliberately run an AI command.").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $preferences).frame(minHeight: 180)
            }
        }.padding(24)
    }
}

struct AISettingsView: View {
    @AppStorage("openAIModel") private var model = "gpt-5.6"
    @State private var apiKey = ""
    @State private var isConfigured = false
    @State private var status = ""
    @State private var testing = false
    var body: some View {
        Form {
            Section("OpenAI") {
                Text("AI editing is optional. BOLD Writer works without it.").font(.headline)
                SecureField(isConfigured ? "Enter a replacement key" : "API key", text: $apiKey)
                TextField("Model", text: $model)
                HStack {
                    Button(isConfigured ? "Replace API Key" : "Save API Key") { save() }.disabled(apiKey.isEmpty)
                    Button("Remove API Key", role: .destructive) { remove() }.disabled(!isConfigured)
                    Button("Test Connection") { test() }.disabled(!isConfigured || testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Security") {
                Text("The key is stored in your macOS Keychain, never in the document, app bundle, logs, source code, or family copies.").font(.caption)
            }
        }.padding(24).onAppear { isConfigured = ((try? KeychainService.shared.loadAPIKey()) ?? nil) != nil }
    }
    private func save() {
        do { try KeychainService.shared.saveAPIKey(apiKey); apiKey = ""; isConfigured = true; status = "API key saved securely in Keychain." }
        catch { status = error.localizedDescription }
    }
    private func remove() {
        do { try KeychainService.shared.removeAPIKey(); isConfigured = false; status = "API key removed." }
        catch { status = error.localizedDescription }
    }
    private func test() {
        testing = true
        Task {
            defer { testing = false }
            do {
                guard let key = try KeychainService.shared.loadAPIKey() else { throw AIProviderError.notConfigured }
                try await OpenAIProvider(apiKey: key, model: model).testConnection()
                status = "Connection successful."
            } catch { status = error.localizedDescription }
        }
    }
}

struct SpeechSettingsView: View {
    @AppStorage("speechVoice") private var voice = ""
    @AppStorage("speechRate") private var rate = 0.48
    var body: some View {
        Form {
            Picker("System voice", selection: $voice) {
                Text("System Default").tag("")
                ForEach(AVSpeechSynthesisVoice.speechVoices(), id: \.identifier) { Text("\($0.name) — \($0.language)").tag($0.identifier) }
            }
            Slider(value: $rate, in: 0.1...0.65) { Text("Speed") }
            Text("Read Aloud uses voices installed on this Mac and does not send manuscript text to a cloud service.").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Privacy by design").font(.title2.bold())
            Label("Editing, saving, search, export, and Read Aloud work locally.", systemImage: "checkmark.shield")
            Label("No analytics, advertising SDK, or tracking is included.", systemImage: "checkmark.shield")
            Label("AI requests are sent only after you press Preview Changes.", systemImage: "checkmark.shield")
            Label("The displayed scope controls how much manuscript text is sent.", systemImage: "checkmark.shield")
            Spacer()
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
    }
}
