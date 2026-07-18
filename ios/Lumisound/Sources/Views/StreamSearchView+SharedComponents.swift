import SwiftUI

// MARK: - Shared visual components for the Cloud Services tab
//
// Small, reusable pieces used across the search-results, server-library, my-
// library, and trending bodies so every state (loading/empty/error) in
// StreamSearchView reads as one consistent, polished design language instead
// of each screen inventing its own spinner/placeholder text.

// MARK: - SkeletonTrackRow / SkeletonList

/// A placeholder row shaped like the real track rows (artwork + two text
/// lines + trailing control), overlaid with a looping shimmer sweep. Shown
/// while a search/browse is in flight so the list "breathes" instead of
/// staring at a bare spinner for a few seconds.
struct SkeletonTrackRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.elevatedSurface.opacity(0.6))
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.elevatedSurface.opacity(0.6))
                    .frame(width: 170, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.elevatedSurface.opacity(0.45))
                    .frame(width: 110, height: 10)
            }

            Spacer(minLength: 4)

            Circle()
                .fill(AppTheme.elevatedSurface.opacity(0.5))
                .frame(width: 30, height: 30)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        )
        .overlay(ShimmerOverlay().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }
}

/// A stack of `SkeletonTrackRow`s standing in for an about-to-arrive result
/// list. Rendered inside a plain `ScrollView` (not a `List`) so it can be
/// dropped into any loading branch without fighting list-row chrome.
struct SkeletonList: View {
    var rowCount: Int = 7

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(0..<rowCount, id: \.self) { _ in
                    SkeletonTrackRow()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }
}

// MARK: - CloudEmptyStateView

/// A consistent icon + title + message (+ optional action) empty/placeholder
/// state, used for every "nothing here yet" or "no results" moment across the
/// Cloud Services tab so they all share one visual language instead of each
/// screen rolling its own ad-hoc VStack.
struct CloudEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.dynamicAccent.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(AppTheme.dynamicAccent)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(AppTheme.headlineFont(size: 17))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(message)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppTheme.bodyFont(size: 14).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(AppTheme.dynamicAccentGradient, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - CloudSectionHeader

/// Small kerned all-caps section label (flame/other icon + text), matching
/// the look the trending header established, reused for other section
/// headers in the tab (e.g. "On This Device", "Previously Downloaded").
struct CloudSectionHeader: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.dynamicAccent)
            Text(text.uppercased())
                .font(AppTheme.bodyFont(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .kerning(0.8)
        }
    }
}
