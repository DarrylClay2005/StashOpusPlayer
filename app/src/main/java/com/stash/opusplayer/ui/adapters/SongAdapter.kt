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
import com.stash.stashwave.databinding.ItemSongGridBinding
import com.stash.stashwave.utils.MetadataExtractor

class SongAdapter(
    private val onSongClick: (Song) -> Unit,
    private val onFavoriteToggle: (Song) -> Unit = {},
    private val onAddToPlaylist: (Song) -> Unit = {},
    private val onPlayNext: (Song) -> Unit = {},
    private val onAddToQueue: (Song) -> Unit = {},
    private val metadataExtractor: MetadataExtractor? = null
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
                view.animate().scaleX(0.95f).scaleY(0.95f).setDuration(100).withEndAction {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                }.start()
                onSongClick(song)
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
                view.animate().scaleX(0.98f).scaleY(0.98f).setDuration(80).withEndAction {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(80).start()
                }.start()
                onSongClick(song)
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
        // Try cached artwork first (fast path)
        val cached = try { metadataExtractor?.loadCachedArtwork(rootView.context, song, 256) } catch (_: Exception) { null }
        if (cached != null) {
            Glide.with(rootView.context).load(cached).centerCrop().into(artworkView)
            return
        }
        // Fallback to embedded bytes
        if (!song.albumArt.isNullOrEmpty()) {
            val artBytes = try { Base64.decode(song.albumArt, Base64.DEFAULT) } catch (_: IllegalArgumentException) { null }
            if (artBytes != null && artBytes.isNotEmpty()) {
                Glide.with(rootView.context)
                    .load(artBytes)
                    .placeholder(R.drawable.ic_music_note)
                    .error(R.drawable.ic_music_note)
                    .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                    .centerCrop()
                    .into(artworkView)
                return
            }
        }
        // Default artwork
        Glide.with(rootView.context).load(R.drawable.ic_music_note).into(artworkView)
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
                    anchor.animate().scaleX(1.1f).scaleY(1.1f).setDuration(150).withEndAction {
                        anchor.animate().scaleX(1f).scaleY(1f).setDuration(150).start()
                    }.start()
                    onFavoriteToggle(song)
                    true
                }
                R.id.action_add_to_playlist -> {
                    android.widget.Toast.makeText(root.context, "Opening playlists...", android.widget.Toast.LENGTH_SHORT).show()
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
