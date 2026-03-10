import SwiftUI
import ShotCoachCore

/// First-launch screen: collects API keys and preferred provider.
///
/// Keys are stored via `SCKeychainService` (kSecClassGenericPassword) and are
/// never written to UserDefaults, never logged, and never embedded in request URLs.
struct APIKeySetupView: View {

    var onComplete: () -> Void

    @AppStorage("preferred_provider") private var preferredProvider = "anthropic"

    @State private var openAIInput    = ""
    @State private var anthropicInput = ""
    @State private var showOpenAIError    = false
    @State private var showAnthropicError = false
    @FocusState private var focusedField: Field?

    private enum Field { case openAI, anthropic }

    // Pre-fill from Keychain so existing keys are visible on re-open.
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _openAIInput    = State(initialValue: SCKeychainService.load(key: "openai_api_key")    ?? "")
        _anthropicInput = State(initialValue: SCKeychainService.load(key: "anthropic_api_key") ?? "")
    }

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

                Text("Add an API key to unlock AI scoring.\nThe app works without one — live on-device checks always run.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: 36)

            // ── Provider picker ──────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Preferred Provider")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Provider", selection: $preferredProvider) {
                    Text("Claude (Anthropic)").tag("anthropic")
                    Text("GPT-4o (OpenAI)").tag("openai")
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            // ── Anthropic key ────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Anthropic API Key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField("sk-ant-…", text: $anthropicInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .anthropic)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .onChange(of: anthropicInput, perform: { _ in showAnthropicError = false })

                if showAnthropicError {
                    Label("Key must start with \"sk-ant-\"", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 16)

            // ── OpenAI key ───────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField("sk-…", text: $openAIInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .openAI)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                    .onChange(of: openAIInput, perform: { _ in showOpenAIError = false })

                if showOpenAIError {
                    Label("Key must start with \"sk-\"", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            // ── CTA ──────────────────────────────────────────────────────────────
            let hasAnyKey = !openAIInput.isEmpty || !anthropicInput.isEmpty
            Button(action: save) {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(hasAnyKey ? Color.green : Color.gray.opacity(0.3))
                    .foregroundStyle(hasAnyKey ? Color.black : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .animation(.easeInOut(duration: 0.2), value: hasAnyKey)
            }
            .disabled(!hasAnyKey)
            .padding(.horizontal, 32)

            Spacer().frame(height: 20)

            Text("Keys stored in the system Keychain. Never logged or sent anywhere except the chosen provider.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)

            Spacer().frame(height: 16)

            Button("Skip — use local analysis only") { onComplete() }
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear { focusedField = anthropicInput.isEmpty ? .anthropic : .openAI }
    }

    // MARK: - Private

    private func save() {
        var valid = true

        let trimmedOpenAI = openAIInput.trimmingCharacters(in: .whitespaces)
        if !trimmedOpenAI.isEmpty {
            if trimmedOpenAI.hasPrefix("sk-") {
                SCKeychainService.save(key: "openai_api_key", value: trimmedOpenAI)
                showOpenAIError = false
            } else {
                showOpenAIError = true
                valid = false
            }
        }

        let trimmedAnthropic = anthropicInput.trimmingCharacters(in: .whitespaces)
        if !trimmedAnthropic.isEmpty {
            if trimmedAnthropic.hasPrefix("sk-ant-") {
                SCKeychainService.save(key: "anthropic_api_key", value: trimmedAnthropic)
                showAnthropicError = false
            } else {
                showAnthropicError = true
                valid = false
            }
        }

        if valid { onComplete() }
    }
}
