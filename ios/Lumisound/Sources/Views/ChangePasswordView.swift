import SwiftUI

// MARK: - ChangePasswordView
//
// Lets the user change their account password (POST /auth/change-password).
// On success, the server signs out every other device's session.

struct ChangePasswordView: View {
    @EnvironmentObject private var account: AccountService
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var localError: String?
    @State private var didSucceed = false

    private var canSubmit: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= 8
            && newPassword == confirmPassword
            && !isSubmitting
    }

    var body: some View {
        List {
            Section {
                SecureField("Current Password", text: $currentPassword)
                    .textContentType(.password)
            } header: {
                Text("Current Password")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                SecureField("New Password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm New Password", text: $confirmPassword)
                    .textContentType(.newPassword)
            } header: {
                Text("New Password")
            } footer: {
                Text("Password must be at least 8 characters. Other devices signed into your account will be signed out.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            if let localError {
                Section {
                    Text(localError)
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.error)
                }
                .listRowBackground(AppTheme.surface)
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                                .tint(AppTheme.textPrimary)
                        } else {
                            Text("Change Password")
                                .font(AppTheme.bodyFont(size: 15).weight(.semibold))
                        }
                        Spacer()
                    }
                    .foregroundStyle(AppTheme.dynamicAccent)
                }
                .disabled(!canSubmit)
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Password Updated", isPresented: $didSucceed) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your password has been changed. Other signed-in devices have been signed out.")
        }
    }

    private func submit() {
        guard canSubmit else { return }
        localError = nil
        isSubmitting = true
        Task {
            let success = await account.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            isSubmitting = false
            if success {
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
                didSucceed = true
            } else {
                localError = account.errorMessage ?? "Could not change password. Please try again."
            }
        }
    }
}
