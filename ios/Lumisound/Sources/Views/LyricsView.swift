import SwiftUI

struct LyricsView: View {
    let lines: [LrcLine]
    let currentPosition: TimeInterval
    let isPlaying: Bool

    private var currentLineIndex: Int? {
        // Last line whose timestamp is <= currentPosition
        var result: Int? = nil
        for (index, line) in lines.enumerated() {
            if line.time <= currentPosition {
                result = index
            } else {
                break
            }
        }
        return result
    }

    var body: some View {
        if lines.isEmpty {
            emptyState
        } else {
            lyricsScroll
        }
    }

    private var emptyState: some View {
        Text("No lyrics available")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private var lyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        lyricLine(line: line, isCurrent: index == currentLineIndex)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 8)
            }
            .onChange(of: currentLineIndex) { newIndex in
                scrollToCurrentLine(proxy: proxy, index: newIndex, animated: isPlaying)
            }
            .onChange(of: isPlaying) { playing in
                // Re-anchor to the line matching the *actual* current position the
                // moment playback resumes, without animation — any scroll animation
                // left over from before the pause (or queued while paused) would
                // otherwise keep interpolating against a now-stale target and the
                // highlighted line would visibly drift from the real playtime.
                if playing {
                    scrollToCurrentLine(proxy: proxy, index: currentLineIndex, animated: false)
                }
            }
            .onAppear {
                // Land on the correct line immediately when the lyrics panel first
                // appears (e.g. opening Lyrics mid-track) instead of animating a
                // long scroll from the top.
                scrollToCurrentLine(proxy: proxy, index: currentLineIndex, animated: false)
            }
        }
    }

    private func scrollToCurrentLine(proxy: ScrollViewProxy, index: Int?, animated: Bool) {
        guard let idx = index, lines.indices.contains(idx) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(lines[idx].id, anchor: .center)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(lines[idx].id, anchor: .center)
            }
        }
    }

    private func lyricLine(line: LrcLine, isCurrent: Bool) -> some View {
        Text(line.text.isEmpty ? "·" : line.text)
            .font(isCurrent ? .body.weight(.semibold) : .body)
            .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textSecondary)
            .multilineTextAlignment(.center)
            .scaleEffect(isCurrent ? 1.06 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCurrent)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
    }
}
