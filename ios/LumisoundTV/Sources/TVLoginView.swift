import SwiftUI

// MARK: - TVLoginView

struct TVLoginView: View {
    @ObservedObject var account: TVAccount

    @State private var username = ""
    @State private var password = ""
    @State private var glow = false

    var body: some View {
        ZStack {
            TVAmbientBackground()

            VStack(spacing: 30) {
                Image(systemName: "music.note.tv.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, Color.accentColor],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: Color.accentColor.opacity(glow ? 0.75 : 0.35), radius: glow ? 34 : 18)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: glow)
                    .onAppear { glow = true }

                VStack(spacing: 8) {
                    Text("Lumisound")
                        .font(.system(size: 44, weight: .bold))
                    Text("Sign in to stream your personal cloud library on your TV")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 18) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                .frame(width: 620)
                .padding(28)
                .tvGlassPanel(cornerRadius: 24)

                if let err = account.errorText {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await account.login(username: username, password: password) }
                } label: {
                    if account.isLoggingIn {
                        ProgressView().frame(width: 320)
                    } else {
                        Text("Sign In").frame(width: 320)
                    }
                }
                .disabled(account.isLoggingIn || username.isEmpty || password.isEmpty)
                .padding(.top, 4)
            }
            .padding(80)
        }
    }
}
