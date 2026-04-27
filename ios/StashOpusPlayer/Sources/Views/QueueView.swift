import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        NavigationStack {
            List {
                if player.queue.isEmpty {
                    Text("Queue is empty")
                        .foregroundStyle(AppTheme.textSecondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, song in
                        Button {
                            player.setQueue(player.queue, startIndex: index, autoplay: true)
                        } label: {
                            HStack {
                                Text(index == player.currentIndex ? "Playing" : "\(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(index == player.currentIndex ? AppTheme.accent : AppTheme.textSecondary)
                                    .frame(width: 50, alignment: .leading)
                                SongRow(song: song, isCurrent: index == player.currentIndex)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Queue")
            .safeAreaInset(edge: .bottom) {
                MiniPlayerBar()
            }
        }
    }
}
