import SwiftUI

struct AboutView: View {
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Version \(version)"
    }

    var body: some View {
        VStack(spacing: 10) {
            LaunchMarkLogo(height: 100)

            Text("MailMind")
                .font(.title)
                .fontWeight(.bold)

            Text(versionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Your inbox, intelligently sorted.")
                .font(.body)
                .multilineTextAlignment(.center)

            Text("""
                Categorization runs on-device through Apple Intelligence and Foundation Models, not remote LLM services, and MailMind does not collect third-party AI API keys.

                Gmail OAuth tokens are stored in your device Keychain with this-device-only protection. Gmail and OAuth use HTTPS directly with Google. MailMind does not operate servers that relay your inbox or credential material.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("About")
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
