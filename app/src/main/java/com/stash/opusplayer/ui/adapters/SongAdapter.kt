package com.stash.stashwave.ui.adapters

import android.util.Base64
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.PopupMenu
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.stash.stashwave.R
import com.stash.stashwave.data.Song
import com.stash.stashwave.databinding.ItemSongBinding
import com.stash.stashwave.utils.MetadataExtractor

class SongAdapter(
    private val onSongClick: (Song) -> Unit,
    private val onFavoriteToggle: (Song) -> Unit = {},
    private val onAddToPlaylist: (Song) -> Unit = {},
    private val metadataExtractor: MetadataExtractor? = null
) : ListAdapter<Song, SongAdapter.SongViewHolder>(SongDiffCallback()) {
    
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SongViewHolder {
        val binding = ItemSongBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return SongViewHolder(binding, onSongClick)
    }
    
    override fun onBindViewHolder(holder: SongViewHolder, position: Int) {
        holder.bind(getItem(position))
    }
    
    inner class SongViewHolder(
        private val binding: ItemSongBinding,
        private val onSongClick: (Song) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {
        
        fun bind(song: Song) {
            binding.songTitle.text = song.displayName
            binding.songArtist.text = "${song.artistName} • ${song.albumName}"
            binding.songDuration.text = song.durationText
            
            // Load album artwork
            loadAlbumArt(song)
            
            // Favorite indicator could be shown here if added to layout
            
            binding.root.setOnClickListener { view ->
                // Add visual feedback - brief scale animation
                view.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(100)
                    .withEndAction {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(100)
                            .start()
                    }
                    .start()
                    
                onSongClick(song)
            }
            
            binding.menuButton.setOnClickListener {
                showContextMenu(song, it)
            }
        }
        
        private fun loadAlbumArt(song: Song) {
            // Try cached artwork first (fast path)
            val cached = try {
                metadataExtractor?.loadCachedArtwork(binding.root.context, song, 256)
            } catch (_: Exception) { null }
            if (cached != null) {
                android.util.Log.d("SongAdapter", "Loading cached artwork for ${song.displayName}")
                Glide.with(binding.root.context)
                    .load(cached)
                    .centerCrop()
                    .into(binding.songArtwork)
                return
            }

            // Fallback to embedded bytes
            android.util.Log.d("SongAdapter", "Checking embedded artwork for ${song.displayName} - albumArt length: ${song.albumArt?.length ?: 0}")
            if (!song.albumArt.isNullOrEmpty()) {
                val artBytes = try {
                    Base64.decode(song.albumArt, Base64.DEFAULT)
                } catch (_: IllegalArgumentException) { null }
                if (artBytes != null && artBytes.isNotEmpty()) {
                    android.util.Log.d("SongAdapter", "Loading embedded artwork for ${song.displayName} - decoded bytes: ${artBytes.size}")
                    Glide.with(binding.root.context)
                        .load(artBytes)
                        .placeholder(R.drawable.ic_music_note)
                        .error(R.drawable.ic_music_note)
                        .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                        .override(256, 256)
                        .centerCrop()
                        .into(binding.songArtwork)
                    return
                } else {
                    android.util.Log.d("SongAdapter", "Failed to decode embedded artwork for ${song.displayName}")
                }
            }

            // Default artwork
            setDefaultArtwork()
        }
        
        private fun setDefaultArtwork() {
            Glide.with(binding.root.context)
                .load(R.drawable.ic_music_note)
                .into(binding.songArtwork)
        }
        
        private fun showContextMenu(song: Song, anchor: View) {
            // Provide haptic feedback
            try {
                anchor.performHapticFeedback(android.view.HapticFeedbackConstants.CONTEXT_CLICK)
            } catch (_: Exception) {}
            
            val popup = PopupMenu(binding.root.context, anchor)
            popup.menuInflater.inflate(R.menu.song_context_menu, popup.menu)
            
            // Update favorite menu item text
            val favoriteItem = popup.menu.findItem(R.id.action_favorite)
            favoriteItem?.title = if (song.isFavorite) "Remove from Favorites" else "Add to Favorites"
            
            popup.setOnMenuItemClickListener { menuItem ->
                when (menuItem.itemId) {
                    R.id.action_favorite -> {
                        // Visual feedback for favorite action
                        anchor.animate()
                            .scaleX(1.1f)
                            .scaleY(1.1f)
                            .setDuration(150)
                            .withEndAction {
                                anchor.animate()
                                    .scaleX(1f)
                                    .scaleY(1f)
                                    .setDuration(150)
                                    .start()
                            }
                            .start()
                        onFavoriteToggle(song)
                        true
                    }
                    R.id.action_add_to_playlist -> {
                        // Show confirmation toast
                        android.widget.Toast.makeText(binding.root.context, "Opening playlists...", android.widget.Toast.LENGTH_SHORT).show()
                        onAddToPlaylist(song)
                        true
                    }
                    R.id.action_play_next -> {
                        // Placeholder feedback for future feature
                        android.widget.Toast.makeText(binding.root.context, "Play next feature coming soon!", android.widget.Toast.LENGTH_SHORT).show()
                        true
                    }
                    else -> false
                }
            }
            popup.show()
        }
    }
    
    private class SongDiffCallback : DiffUtil.ItemCallback<Song>() {
        override fun areItemsTheSame(oldItem: Song, newItem: Song): Boolean {
            return oldItem.id == newItem.id
        }
        
        override fun areContentsTheSame(oldItem: Song, newItem: Song): Boolean {
            return oldItem == newItem
        }
    }
}
