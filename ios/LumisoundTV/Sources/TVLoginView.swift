import SwiftUI

// MARK: - TVLoginView

struct TVLoginView: View {
    @ObservedObject var account: TVAccount

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 26) {
            Image(systemName: "music.note.tv.fill")
                .font(.system(size: 90))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Sign in to Lumisound").font(.title)
                Text("Stream your personal cloud library on your TV.")
                    .font(.title3).foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .frame(width: 620)

            if let err = account.errorText {
                Text(err).font(.callout).foregroundStyle(.red)
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
        }
        .padding(80)
    }
}
