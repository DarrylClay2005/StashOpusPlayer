package com.stash.opusplayer.wearos.ui.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.wearos.data.WearSong
import com.stash.opusplayer.wearos.databinding.ItemTrackBinding
import java.util.concurrent.TimeUnit

class TrackListAdapter(
    private val onTrackClick: (WearSong) -> Unit
) : ListAdapter<WearSong, TrackListAdapter.TrackViewHolder>(DiffCallback()) {

    private var currentSong: WearSong? = null

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): TrackViewHolder {
        val binding = ItemTrackBinding.inflate(
            LayoutInflater.from(parent.context), 
            parent, 
            false
        )
        return TrackViewHolder(binding)
    }

    override fun onBindViewHolder(holder: TrackViewHolder, position: Int) {
        val track = getItem(position)
        holder.bind(track, track.id == currentSong?.id)
    }

    fun updateTracks(tracks: List<WearSong>) {
        submitList(tracks)
    }

    fun updateCurrentSong(song: WearSong?) {
        val oldCurrentSong = currentSong
        currentSong = song
        
        // Refresh items to update playing indicators
        currentList.forEachIndexed { index, track ->
            if (track.id == oldCurrentSong?.id || track.id == song?.id) {
                notifyItemChanged(index)
            }
        }
    }

    inner class TrackViewHolder(
        private val binding: ItemTrackBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(track: WearSong, isCurrentlyPlaying: Boolean) {
            binding.trackTitle.text = track.title
            binding.trackArtist.text = track.artist
            binding.trackDuration.text = formatDuration(track.duration)

            // Show playing indicator if this is the current track
            binding.playingIndicator.visibility = if (isCurrentlyPlaying) {
                View.VISIBLE
            } else {
                View.GONE
            }

            binding.root.setOnClickListener {
                onTrackClick(track)
            }
        }

        private fun formatDuration(milliseconds: Long): String {
            val totalSeconds = TimeUnit.MILLISECONDS.toSeconds(milliseconds)
            val minutes = totalSeconds / 60
            val seconds = totalSeconds % 60
            return String.format("%d:%02d", minutes, seconds)
        }
    }

    private class DiffCallback : DiffUtil.ItemCallback<WearSong>() {
        override fun areItemsTheSame(oldItem: WearSong, newItem: WearSong): Boolean {
            return oldItem.id == newItem.id
        }

        override fun areContentsTheSame(oldItem: WearSong, newItem: WearSong): Boolean {
            return oldItem == newItem
        }
    }
}
