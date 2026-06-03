import AppKit
import CLINotifyShared
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var licenseController: LicenseController
    private let registry: SessionRegistry
    @State private var licenseKey = ""
    @State private var statusMessage = ""

    init(settings: SettingsStore, registry: SessionRegistry, licenseController: LicenseController) {
        self.settings = settings
        self.registry = registry
        self.licenseController = licenseController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("CLINotify")
                .font(.title.bold())

            GroupBox("License") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(licenseController.statusText)
                            .font(.headline)
                        if let tail = licenseController.record.licenseKeyTail {
                            Text("Key ...\(tail)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        SecureField("License key", text: $licenseKey)
                        Button("Activate") {
                            activateLicense()
                        }
                        Button("Free") {
                            resetLicense()
                        }
                    }
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("Alerts") {
                VStack(alignment: .leading) {
                    Toggle("Enable alerts", isOn: $settings.globalEnabled)
                    Toggle("Enable animation", isOn: $settings.animationEnabled)
                    Toggle("Enable sound", isOn: $settings.soundEnabled)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Display") {
                Picker("Target display", selection: $settings.selectedScreenID) {
                    ForEach(settings.availableScreens(), id: \.id) { screen in
                        Text(screen.title).tag(screen.id)
                    }
                }
                .disabled(!licenseController.capabilities.displaySelection)
                if !licenseController.capabilities.displaySelection {
                    Text("Display selection is a paid feature.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Sounds") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Done built-in")
                        TextField("Sound name", text: $settings.doneSoundName)
                    }
                    GridRow {
                        Text("Attention built-in")
                        TextField("Sound name", text: $settings.attentionSoundName)
                    }
                    GridRow {
                        Text("Done custom")
                        soundPathView(path: settings.doneCustomSoundPath, type: .done)
                    }
                    GridRow {
                        Text("Attention custom")
                        soundPathView(path: settings.attentionCustomSoundPath, type: .attention)
                    }
                }
                if !licenseController.capabilities.customSounds {
                    Text("Custom sounds are a paid feature; free mode uses built-in sounds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Registered sessions") {
                let sessions = registry.allSessions()
                if sessions.isEmpty {
                    Text("No named terminal sessions.")
                        .foregroundStyle(.secondary)
                } else {
                    Table(sessions) {
                        TableColumn("Name", value: \.name)
                        TableColumn("TTY", value: \.tty)
                        TableColumn("CWD") { session in
                            Text(session.cwd ?? "")
                        }
                    }
                    .frame(minHeight: 140)
                }
            }

            Text("Run `clinotify name \"work\"` in a terminal to enable alerts for that session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(22)
    }

    private func soundPathView(path: String, type: EventType) -> some View {
        HStack {
            Text(path.isEmpty ? "None" : path)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
            Button("Choose") {
                chooseSound(type: type)
            }
            .disabled(!licenseController.capabilities.customSounds)
            Button("Clear") {
                settings.setCustomSound(url: nil, for: type)
            }
            .disabled(path.isEmpty)
        }
    }

    private func chooseSound(type: EventType) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SoundFileValidator.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await SoundFileValidator.validate(url: url)
                await MainActor.run {
                    settings.setCustomSound(url: url, for: type)
                    statusMessage = "Sound imported."
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Invalid sound: \(error.localizedDescription)"
                }
            }
        }
    }

    private func activateLicense() {
        let key = licenseKey
        statusMessage = "Activating..."
        Task {
            do {
                try await licenseController.activateOnline(key: key)
                await MainActor.run {
                    licenseKey = ""
                    statusMessage = "License activated and cached for offline use."
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Activation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func resetLicense() {
        do {
            try licenseController.resetToFree()
            statusMessage = "Free mode enabled."
        } catch {
            statusMessage = "Reset failed: \(error.localizedDescription)"
        }
    }
}
