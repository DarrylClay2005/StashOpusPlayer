package com.stash.opusplayer.ui.adapters

import android.util.Base64
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.PopupMenu
import androidx.lifecycle.LifecycleCoroutineScope
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.stash.opusplayer.R
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.ItemSongBinding
import com.stash.opusplayer.databinding.ItemSongGridBinding
import com.stash.opusplayer.utils.MetadataExtractor
import com.stash.opusplayer.utils.MetadataStorageManager
import com.stash.opusplayer.utils.AnimationUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class SongAdapter(
    private val onSongClick: (Song) -> Unit,
    private val onFavoriteToggle: (Song) -> Unit = {},
    private val onAddToPlaylist: (Song) -> Unit = {},
    private val onPlayNext: (Song) -> Unit = {},
    private val onAddToQueue: (Song) -> Unit = {},
    private val onShowFeedback: (String) -> Unit = {},
    private val metadataExtractor: MetadataExtractor? = null,
    private val lifecycleScope: LifecycleCoroutineScope? = null
) : ListAdapter<Song, RecyclerView.ViewHolder>(SongDiffCallback()) {

    companion object {
        private const val VIEW_TYPE_LIST = 0
        private const val VIEW_TYPE_GRID = 1
    }

    private var columns: Int = 1

    fun setColumns(cols: Int) {
        if (columns != cols) {
            columns = cols
            notifyDataSetChanged()
        }
    }

    override fun getItemViewType(position: Int): Int = if (columns == 1) VIEW_TYPE_LIST else VIEW_TYPE_GRID

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return if (viewType == VIEW_TYPE_LIST) {
            val binding = ItemSongBinding.inflate(inflater, parent, false)
            ListViewHolder(binding, onSongClick)
        } else {
            val binding = ItemSongGridBinding.inflate(inflater, parent, false)
            GridViewHolder(binding, onSongClick)
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val item = getItem(position)
        when (holder) {
            is ListViewHolder -> holder.bind(item)
            is GridViewHolder -> holder.bind(item)
        }
    }

    inner class ListViewHolder(
        private val binding: ItemSongBinding,
        private val onSongClick: (Song) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(song: Song) {
            binding.songTitle.text = song.displayName
            binding.songArtist.text = "${song.artistName} • ${song.albumName}"
            binding.songDuration.text = song.durationText

            loadAlbumArt(binding, song)

            binding.root.setOnClickListener { view ->
                AnimationUtils.animateButtonPress(view) {
                    onSongClick(song)
                }
            }

            binding.menuButton.setOnClickListener { showContextMenu(binding.root, song, it) }
        }
    }

    inner class GridViewHolder(
        private val binding: ItemSongGridBinding,
        private val onSongClick: (Song) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(song: Song) {
            binding.songTitle.text = song.displayName
            binding.songArtist.text = song.artistName

            loadAlbumArt(binding, song)

            binding.root.setOnClickListener { view ->
                AnimationUtils.animateButtonPress(view) {
                    onSongClick(song)
                }
            }

            binding.menuButton.setOnClickListener { showContextMenu(binding.root, song, it) }
        }
    }

    private fun loadAlbumArt(bindingRoot: View, imageView: android.widget.ImageView, song: Song) {
        // unused — helper placeholder if needed later
    }

    private fun loadAlbumArt(binding: Any, song: Song) {
        val rootView: View
        val artworkView: android.widget.ImageView
        when (binding) {
            is ItemSongBinding -> { rootView = binding.root; artworkView = binding.songArtwork }
            is ItemSongGridBinding -> { rootView = binding.root; artworkView = binding.songArtwork }
            else -> return
        }
        
        val identifier = song.path.ifBlank { song.title }
        android.util.Log.d("SongAdapter", "[ARTWORK] Loading for: '${song.displayName}', path: '${song.path}', hasAlbumArt: ${!song.albumArt.isNullOrEmpty()}, identifier: '$identifier'")
        
        // Priority 1: Check MetadataStorageManager first (dedicated storage)
        val hasStoredArtwork = MetadataStorageManager.hasArtwork(rootView.context, identifier)
        android.util.Log.d("SongAdapter", "[ARTWORK] Priority 1 - Stored artwork exists: $hasStoredArtwork for identifier: '$identifier'")
        if (hasStoredArtwork) {
            val storedBytes = MetadataStorageManager.loadArtwork(rootView.context, identifier)
            android.util.Log.d("SongAdapter", "[ARTWORK] Priority 1 - Loaded bytes: ${if (storedBytes != null) "${storedBytes.size} bytes" else "null"}")
            if (storedBytes != null && storedBytes.isNotEmpty()) {
                android.util.Log.d("SongAdapter", "[ARTWORK] Priority 1 - Loading ${storedBytes.size} bytes into Glide for: ${song.displayName}")
                try {
                    Glide.with(rootView.context)
                        .load(storedBytes)
                        .signature(com.bumptech.glide.signature.ObjectKey(identifier))
                        .placeholder(R.drawable.ic_music_note)
                        .error(R.drawable.ic_music_note)
                        .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                        .centerCrop()
                        .into(artworkView)
                    android.util.Log.d("SongAdapter", "[ARTWORK] Priority 1 - Glide load initiated successfully")
                } catch (e: Exception) {
                    android.util.Log.e("SongAdapter", "[ARTWORK] Priority 1 - Glide load FAILED: ${e.message}", e)
                }
                return
            } else {
                android.util.Log.w("SongAdapter", "[ARTWORK] Priority 1 - File exists but bytes are ${if (storedBytes == null) "null" else "empty"}")
            }
        }
        
        // Priority 2: Check if embedded artwork exists in Song object
        android.util.Log.d("SongAdapter", "[ARTWORK] Priority 2 - Checking embedded artwork in Song object")
        if (!song.albumArt.isNullOrEmpty()) {
            android.util.Log.d("SongAdapter", "[ARTWORK] Priority 2 - Song has albumArt field (${song.albumArt?.length ?: 0} chars)")
            val artBytes = try { Base64.decode(song.albumArt, Base64.DEFAULT) } catch (_: IllegalArgumentException) { null }
            if (artBytes != null && artBytes.isNotEmpty()) {
                android.util.Log.d("SongAdapter", "[ARTWORK] Priority 2 - Successfully decoded embedded artwork (${artBytes.size} bytes)")
                Glide.with(rootView.context)
                    .load(artBytes)
                    .signature(com.bumptech.glide.signature.ObjectKey(identifier))
                    .placeholder(R.drawable.ic_music_note)
                    .error(R.drawable.ic_music_note)
                    .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                    .centerCrop()
                    .into(artworkView)
                // Save to MetadataStorageManager for faster future loads
                lifecycleScope?.launch(Dispatchers.IO) {
                    try {
                        MetadataStorageManager.saveArtwork(rootView.context, identifier, artBytes)
                    } catch (_: Exception) {}
                }
                return
            }
        }
        
        // Priority 3: Try legacy cached artwork
        android.util.Log.d("SongAdapter", "[ARTWORK] Priority 3 - Checking legacy cached artwork")
        val cached = try { metadataExtractor?.loadCachedArtwork(rootView.context, song, 256) } catch (_: Exception) { null }
        android.util.Log.d("SongAdapter", "[ARTWORK] Priority 3 - Legacy cache result: ${if (cached != null) "found" else "not found"}")
        if (cached != null) {
            Glide.with(rootView.context)
                .load(cached)
                .signature(com.bumptech.glide.signature.ObjectKey(identifier))
                .placeholder(R.drawable.ic_music_note)
                .error(R.drawable.ic_music_note)
                .centerCrop()
                .into(artworkView)
            return
        }
        
        // Priority 4: Extract artwork on-demand in background
        android.util.Log.d("SongAdapter", "[ARTWORK] Priority 4 - Attempting on-demand extraction, lifecycleScope: ${lifecycleScope != null}, metadataExtractor: ${metadataExtractor != null}")
        if (lifecycleScope != null && metadataExtractor != null) {
            android.util.Log.d("SongAdapter", "[ARTWORK] Priority 4 - Starting background extraction for: ${song.displayName}")
            // Show placeholder while loading
            Glide.with(rootView.context)
                .load(R.drawable.ic_music_note)
                .signature(com.bumptech.glide.signature.ObjectKey(identifier))
                .into(artworkView)
                
            lifecycleScope.launch(Dispatchers.IO) {
                android.util.Log.d("SongAdapter", "[ARTWORK] Priority 4 - Background thread started for: ${song.displayName}")
                try {
                    val updatedSong = metadataExtractor.extractMetadata(song, forceArtworkExtraction = true)
                    if (updatedSong.albumArt != null) {
                        val artBytes = try { Base64.decode(updatedSong.albumArt, Base64.DEFAULT) } catch (_: Exception) { null }
                        if (artBytes != null && artBytes.isNotEmpty()) {
                            withContext(Dispatchers.Main) {
                                try {
                                    Glide.with(rootView.context)
                                        .asBitmap()
                                        .load(artBytes)
                                        .signature(com.bumptech.glide.signature.ObjectKey(identifier))
                                        .placeholder(R.drawable.ic_music_note)
                                        .error(R.drawable.ic_music_note)
                                        .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                                        .centerCrop()
                                        .into(artworkView)
                                } catch (_: Exception) {}
                            }
                        }
                    }
                } catch (_: Exception) {}
            }
        } else {
            // No lifecycle scope - just show placeholder
            Glide.with(rootView.context)
                .load(R.drawable.ic_music_note)
                .signature(com.bumptech.glide.signature.ObjectKey(identifier))
                .into(artworkView)
        }
    }

    private fun showContextMenu(root: View, song: Song, anchor: View) {
        try { anchor.performHapticFeedback(android.view.HapticFeedbackConstants.CONTEXT_CLICK) } catch (_: Exception) {}
        val popup = PopupMenu(root.context, anchor)
        popup.menuInflater.inflate(R.menu.song_context_menu, popup.menu)
        val favoriteItem = popup.menu.findItem(R.id.action_favorite)
        favoriteItem?.title = if (song.isFavorite) "Remove from Favorites" else "Add to Favorites"
        popup.setOnMenuItemClickListener { menuItem ->
            when (menuItem.itemId) {
                R.id.action_favorite -> {
                    AnimationUtils.bounceView(anchor, 1.2f, 400)
                    onFavoriteToggle(song)
                    true
                }
                R.id.action_add_to_playlist -> {
                    onShowFeedback("Opening playlists...")
                    onAddToPlaylist(song)
                    true
                }
                R.id.action_play_next -> {
                    onPlayNext(song)
                    true
                }
                R.id.action_add_to_queue -> {
                    onAddToQueue(song)
                    true
                }
                else -> false
            }
        }
        popup.show()
    }

    private class SongDiffCallback : DiffUtil.ItemCallback<Song>() {
        override fun areItemsTheSame(oldItem: Song, newItem: Song): Boolean = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: Song, newItem: Song): Boolean = oldItem == newItem
    }
}
