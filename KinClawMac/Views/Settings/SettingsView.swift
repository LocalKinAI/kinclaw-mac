import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var licenseInput = ""
    @State private var showSaved = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section {
                    accountStatus
                } header: {
                    Text("Account")
                }

                // License key section
                Section {
                    licenseKeyInput
                } header: {
                    Text("License Key")
                } footer: {
                    Text("Purchase a Cloud Pro license at localkin.dev/pricing.\nPaste your license key here to unlock Pro features.")
                }

                // Usage section
                if !appState.isPro {
                    Section {
                        usageInfo
                    } header: {
                        Text("Daily Usage")
                    }
                }

                // About section
                Section {
                    aboutSection
                } header: {
                    Text("About")
                }

                // Links
                Section {
                    linksSection
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            licenseInput = appState.licenseKey
        }
    }

    // MARK: - Account Status

    private var accountStatus: some View {
        HStack(spacing: 16) {
            Image(systemName: appState.isPro ? "star.circle.fill"
                  : appState.isInTrial ? "gift.circle.fill" : "person.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(appState.isPro ? .orange : appState.isInTrial ? .blue : .gray)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isPro ? "Cloud Pro"
                     : appState.isInTrial ? "Free Trial" : "Free Plan")
                    .font(.headline)
                Text(appState.isPro ? "All features unlocked"
                     : appState.isInTrial ? "All features free for \(appState.trialDaysRemaining) more days"
                     : "\(max(0, appState.freeMessageLimit - appState.dailyMessageCount)) messages remaining today")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !appState.isPro {
                Button("Upgrade") {
                    if let url = URL(string: "https://localkin.dev/pricing") {
                        openExternalURL(url)
                    }
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - License Key Input

    private var licenseKeyInput: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.secondary)
                SecureField("Enter license key", text: $licenseInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            HStack(spacing: 12) {
                Button {
                    appState.setLicenseKey(licenseInput)
                    showSaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSaved = false
                    }
                } label: {
                    HStack {
                        Image(systemName: showSaved ? "checkmark" : "arrow.down.circle")
                        Text(showSaved ? "Saved!" : "Save Key")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if appState.isPro {
                    Button {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .alert("Remove License?", isPresented: $showClearConfirm) {
                        Button("Remove", role: .destructive) {
                            licenseInput = ""
                            appState.setLicenseKey("")
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("You'll lose access to Pro features.")
                    }
                }
            }
        }
    }

    // MARK: - Usage Info

    private var usageInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Messages today")
                Spacer()
                Text("\(appState.dailyMessageCount) / \(appState.freeMessageLimit)")
                    .foregroundColor(.secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.platformTertiaryBackground)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(usageColor)
                        .frame(
                            width: geo.size.width * min(1, Double(appState.dailyMessageCount) / Double(appState.freeMessageLimit)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            Text("Resets daily at midnight")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var usageColor: Color {
        let ratio = Double(appState.dailyMessageCount) / Double(appState.freeMessageLimit)
        if ratio > 0.8 { return .red }
        if ratio > 0.5 { return .orange }
        return .green
    }

    // MARK: - About

    private var aboutSection: some View {
        Group {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Engine")
                Spacer()
                Text("LocalKin Microkernel")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        Group {
            Link(destination: URL(string: "https://localkin.dev")!) {
                Label("Website", systemImage: "globe")
            }
            Link(destination: URL(string: "https://github.com/nicksun233/localkin")!) {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: URL(string: "https://localkin.dev/pricing")!) {
                Label("Pricing", systemImage: "tag.fill")
            }
        }
    }
}
