import SwiftUI

/// Set and track a weekly listening-time goal — see
/// `ListeningGoalService`'s doc comment for how this differs from
/// Achievements' retrospective streaks/badges.
struct ListeningGoalView: View {
    @EnvironmentObject private var account: AccountService
    @ObservedObject private var goal = ListeningGoalService.shared

    @State private var draftMinutes: Int = 300 // 5 hours, a reasonable default suggestion

    var body: some View {
        List {
            if let target = goal.targetMinutes {
                Section {
                    progressCard(target: target)
                } header: {
                    Text("This Week")
                }
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)

                Section {
                    Stepper("Goal: \(formatted(target))", value: Binding(
                        get: { target },
                        set: { goal.targetMinutes = $0 }
                    ), in: 30...4200, step: 30)
                    Button(role: .destructive) {
                        goal.targetMinutes = nil
                    } label: {
                        Text("Remove Goal")
                    }
                }
                .listRowBackground(AppTheme.surface)
            } else {
                Section {
                    Stepper("Target: \(formatted(draftMinutes))", value: $draftMinutes, in: 30...4200, step: 30)
                    Button {
                        goal.targetMinutes = draftMinutes
                    } label: {
                        Label("Set Weekly Goal", systemImage: "target")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.dynamicAccent)
                } header: {
                    Text("New Goal")
                } footer: {
                    Text("Pick a weekly listening-time target. Progress is measured from your real listening over the last 7 days.")
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("Listening Goal")
        .navigationBarTitleDisplayMode(.inline)
        .task { await goal.refresh(account: account) }
        .refreshable { await goal.refresh(account: account) }
    }

    private func progressCard(target: Int) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(AppTheme.elevatedSurface, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: goal.progressFraction)
                    .stroke(
                        goal.isGoalMet ? Color.green : AppTheme.dynamicAccent,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: goal.progressFraction)
                VStack(spacing: 2) {
                    Text(formatted(goal.progressMinutes))
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("of \(formatted(target))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(width: 140, height: 140)
            .padding(.top, 8)

            if goal.isGoalMet {
                Label("Goal reached this week", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else if !goal.hasLoaded {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func formatted(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }
}
