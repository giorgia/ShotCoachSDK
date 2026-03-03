import SwiftUI
import ShotCoachCore

/// First-launch screen: collects the OpenAI API key and persists it in the Keychain.
///
/// The key is stored via `SCKeychainService` (kSecClassGenericPassword) and is
/// never written to UserDefaults, never logged, and never embedded in request URLs.
struct APIKeySetupView: View {

    /// Called once the key is saved; the parent should transition to the main UI.
    var onComplete: () -> Void

    @State private var keyInput = ""
    @State private var showError = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Header ──────────────────────────────────────────────────────────
            VStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("ShotCoach")
                    .font(.system(size: 36, weight: .bold))

                Text("Add an OpenAI API key to unlock cloud analysis.\nThe app works without one — live on-device checks always run.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: 48)

            // ── Key field ────────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField("sk-…", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)

                if showError {
                    Label("Key must start with \"sk-\"", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            // ── CTA ──────────────────────────────────────────────────────────────
            Button(action: save) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(keyInput.isEmpty ? Color.gray.opacity(0.3) : Color.green)
                    .foregroundStyle(keyInput.isEmpty ? Color.secondary : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .animation(.easeInOut(duration: 0.2), value: keyInput.isEmpty)
            }
            .disabled(keyInput.isEmpty)
            .padding(.horizontal, 32)

            Spacer().frame(height: 20)

            Text("Stored in the system Keychain. Only sent to OpenAI — never anywhere else.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)

            Spacer().frame(height: 16)

            // ── Skip ─────────────────────────────────────────────────────────────
            Button("Skip — use local analysis only") {
                onComplete()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: - Private

    private func save() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("sk-") else {
            showError = true
            return
        }
        showError = false
        SCKeychainService.save(key: "openai_api_key", value: trimmed)
        onComplete()
    }
}
