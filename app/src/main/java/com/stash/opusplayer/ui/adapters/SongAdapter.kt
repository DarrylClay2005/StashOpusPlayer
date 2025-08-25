package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.PopupMenu
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.stash.opusplayer.R
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.ItemSongBinding
import com.stash.opusplayer.utils.MetadataExtractor

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
            
            binding.root.setOnClickListener {
                onSongClick(song)
            }
            
            binding.menuButton.setOnClickListener {
                showContextMenu(song, it)
            }
        }
        
        private fun loadAlbumArt(song: Song) {
            if (!song.albumArt.isNullOrEmpty()) {
                // Load from base64 encoded album art
                val bitmap = metadataExtractor?.decodeAlbumArt(song.albumArt)
                if (bitmap != null) {
                    Glide.with(binding.root.context)
                        .load(bitmap)
                        .placeholder(R.drawable.ic_music_note)
                        .error(R.drawable.ic_music_note)
                        .centerCrop()
                        .into(binding.songArtwork)
                } else {
                    setDefaultArtwork()
                }
            } else {
                setDefaultArtwork()
            }
        }
        
        private fun setDefaultArtwork() {
            Glide.with(binding.root.context)
                .load(R.drawable.ic_music_note)
                .into(binding.songArtwork)
        }
        
        private fun showContextMenu(song: Song, anchor: View) {
            val popup = PopupMenu(binding.root.context, anchor)
            popup.menuInflater.inflate(R.menu.song_context_menu, popup.menu)
            
            // Update favorite menu item text
            val favoriteItem = popup.menu.findItem(R.id.action_favorite)
            favoriteItem?.title = if (song.isFavorite) "Remove from Favorites" else "Add to Favorites"
            
            popup.setOnMenuItemClickListener { menuItem ->
                when (menuItem.itemId) {
                    R.id.action_favorite -> {
                        onFavoriteToggle(song)
                        true
                    }
                    R.id.action_add_to_playlist -> {
                        onAddToPlaylist(song)
                        true
                    }
                    R.id.action_play_next -> {
                        // TODO: Add to play next
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
