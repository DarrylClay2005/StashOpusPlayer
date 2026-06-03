import SwiftUI

struct LoginView: View {

    @EnvironmentObject var account: AccountService
    @Environment(\.dismiss) var dismiss

    @State private var isRegistering = false
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var email = ""
    @State private var displayName = ""
    @State private var isLoading = false

    // Local validation error (e.g. passwords don't match)
    @State private var localError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {

                        // MARK: Logo / Header
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(AppTheme.accent)
                                .shadow(color: AppTheme.accent.opacity(0.4), radius: 12, x: 0, y: 6)

                            Text("Stash Opus Player")
                                .font(.title2.bold())
                                .foregroundStyle(AppTheme.textPrimary)

                            Text("Sync your music across devices")
                                .font(AppTheme.bodyFont(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.top, 20)

                        // MARK: Mode Picker
                        Picker("Mode", selection: $isRegistering) {
                            Text("Log In").tag(false)
                            Text("Create Account").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .onChange(of: isRegistering) { _ in
                            localError = nil
                            account.errorMessage = nil
                        }

                        // MARK: Form Fields
                        VStack(spacing: 14) {

                            // Username
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Username")
                                    .font(AppTheme.bodyFont(size: 12))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.leading, 4)
                                TextField("", text: $username)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .padding(12)
                                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            // Password
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Password")
                                    .font(AppTheme.bodyFont(size: 12))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.leading, 4)
                                SecureField("", text: $password)
                                    .textContentType(isRegistering ? .newPassword : .password)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .padding(12)
                                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            // Registration-only fields
                            if isRegistering {

                                // Confirm password
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Confirm Password")
                                        .font(AppTheme.bodyFont(size: 12))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .padding(.leading, 4)
                                    SecureField("", text: $confirmPassword)
                                        .textContentType(.newPassword)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .padding(12)
                                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                                        )
                                }

                                // Display name
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Display Name (optional)")
                                        .font(AppTheme.bodyFont(size: 12))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .padding(.leading, 4)
                                    TextField("", text: $displayName)
                                        .textContentType(.name)
                                        .autocorrectionDisabled()
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .padding(12)
                                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                                        )
                                }

                                // Email
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Email (optional)")
                                        .font(AppTheme.bodyFont(size: 12))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .padding(.leading, 4)
                                    TextField("", text: $email)
                                        .textContentType(.emailAddress)
                                        .keyboardType(.emailAddress)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .padding(12)
                                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)

                        // MARK: Error message
                        let errorText = localError ?? account.errorMessage
                        if let err = errorText {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                Text(err)
                                    .font(AppTheme.bodyFont(size: 13))
                                    .multilineTextAlignment(.leading)
                            }
                            .foregroundStyle(AppTheme.error)
                            .padding(.horizontal)
                        }

                        // MARK: Submit Button
                        Button {
                            submitTapped()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppTheme.accent)
                                    .frame(height: 50)
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(isRegistering ? "Create Account" : "Log In")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .disabled(isLoading || username.isEmpty || password.isEmpty)
                        .padding(.horizontal)
                        .opacity((isLoading || username.isEmpty || password.isEmpty) ? 0.6 : 1.0)

                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .onChange(of: account.isLoggedIn) { loggedIn in
                if loggedIn { dismiss() }
            }
        }
    }

    // MARK: - Actions

    private func submitTapped() {
        localError = nil
        account.errorMessage = nil

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty else {
            localError = "Username is required."
            return
        }
        guard !password.isEmpty else {
            localError = "Password is required."
            return
        }

        if isRegistering {
            guard password == confirmPassword else {
                localError = "Passwords do not match."
                return
            }
            guard password.count >= 6 else {
                localError = "Password must be at least 6 characters."
                return
            }
        }

        isLoading = true
        Task {
            defer { isLoading = false }
            if isRegistering {
                await account.register(
                    username: trimmedUsername,
                    password: password,
                    email: email.isEmpty ? nil : email,
                    displayName: displayName.isEmpty ? nil : displayName
                )
            } else {
                await account.login(username: trimmedUsername, password: password)
            }
        }
    }
}
