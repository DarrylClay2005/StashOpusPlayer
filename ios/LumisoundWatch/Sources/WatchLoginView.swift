import SwiftUI

// MARK: - WatchLoginView
//
// Manual on-watch sign-in, shown inside the Watch Library tab whenever there's
// no active session. In practice most users won't see this — the phone
// pushes an automatic handoff (see WatchAccountStore.applyHandoff) as soon as
// it's paired and logged in — but this covers first-run-before-phone-login
// and explicit-logout cases.

struct WatchLoginView: View {
    @EnvironmentObject private var account: WatchAccountStore
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)

                Text("Sign In")
                    .font(.system(size: 13, weight: .semibold))

                Text("Or just open Lumisound on iPhone once — your session syncs to the watch automatically.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                SecureField("Password", text: $password)

                if let error = account.errorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        isLoggingIn = true
                        await account.login(username: username, password: password)
                        isLoggingIn = false
                    }
                } label: {
                    if isLoggingIn {
                        ProgressView()
                    } else {
                        Text("Log In")
                    }
                }
                .disabled(username.isEmpty || password.isEmpty || isLoggingIn)
            }
            .padding(.horizontal, 6)
        }
    }
}
