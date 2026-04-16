package com.stash.opusplayer.ui.adapters

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
import com.stash.opusplayer.R
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.ItemSongFolderCardBinding
import com.stash.opusplayer.databinding.ItemSongBinding
import com.stash.opusplayer.databinding.ItemSongGridBinding
import com.stash.opusplayer.ui.appearance.ThemeManager
import com.stash.opusplayer.utils.MetadataExtractor
import com.stash.opusplayer.utils.AnimationUtils

class SongAdapter(
    private val onSongClick: (Song) -> Unit,
    private val onFavoriteToggle: (Song) -> Unit = {},
    private val onAddToPlaylist: (Song) -> Unit = {},
    private val onPlayNext: (Song) -> Unit = {},
    private val onAddToQueue: (Song) -> Unit = {},
    private val onShowFeedback: (String) -> Unit = {},
    private val metadataExtractor: MetadataExtractor? = null
) : ListAdapter<Song, RecyclerView.ViewHolder>(SongDiffCallback()) {

    companion object {
        private const val VIEW_TYPE_LIST = 0
        private const val VIEW_TYPE_GRID = 1
        private const val VIEW_TYPE_FOLDER_CARD_LIST = 2
    }

    enum class ListStyle {
        STANDARD,
        FOLDER_CARD
    }

    private var columns: Int = 1
    private var listStyle: ListStyle = ListStyle.STANDARD

    fun setColumns(cols: Int) {
        if (columns != cols) {
            columns = cols
            notifyDataSetChanged()
        }
    }

    fun setListStyle(style: ListStyle) {
        if (listStyle != style) {
            listStyle = style
            if (columns == 1) {
                notifyDataSetChanged()
            }
        }
    }

    override fun getItemViewType(position: Int): Int = when {
        columns != 1 -> VIEW_TYPE_GRID
        listStyle == ListStyle.FOLDER_CARD -> VIEW_TYPE_FOLDER_CARD_LIST
        else -> VIEW_TYPE_LIST
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return when (viewType) {
            VIEW_TYPE_LIST -> {
                val binding = ItemSongBinding.inflate(inflater, parent, false)
                ListViewHolder(binding, onSongClick)
            }
            VIEW_TYPE_FOLDER_CARD_LIST -> {
                val binding = ItemSongFolderCardBinding.inflate(inflater, parent, false)
                FolderCardViewHolder(binding, onSongClick)
            }
            else -> {
                val binding = ItemSongGridBinding.inflate(inflater, parent, false)
                GridViewHolder(binding, onSongClick)
            }
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val item = getItem(position)
        when (holder) {
            is ListViewHolder -> holder.bind(item)
            is FolderCardViewHolder -> holder.bind(item)
            is GridViewHolder -> holder.bind(item)
        }
    }

    inner class ListViewHolder(
        private val binding: ItemSongBinding,
        private val onSongClick: (Song) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(song: Song) {
            applyAdaptiveListSizing()
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

        private fun applyAdaptiveListSizing() {
            val context = binding.root.context
            val density = context.resources.displayMetrics.density
            val scale = ThemeManager.getAdaptiveUiScale(context)

            fun px(baseDp: Int): Int = (baseDp * density * scale).toInt().coerceAtLeast(1)

            val rootLayoutParams = binding.root.layoutParams as? ViewGroup.MarginLayoutParams
            rootLayoutParams?.apply {
                marginStart = px(4)
                topMargin = px(4)
                marginEnd = px(4)
                bottomMargin = px(4)
            }
            if (rootLayoutParams != null) {
                binding.root.layoutParams = rootLayoutParams
            }

            binding.root.radius = px(9).toFloat()
            binding.root.cardElevation = px(2).toFloat()
            binding.root.minimumHeight = px(62)

            (binding.root.getChildAt(0) as? ViewGroup)?.setPadding(px(10), px(8), px(10), px(8))

            binding.songArtwork.layoutParams = binding.songArtwork.layoutParams.apply {
                width = px(44)
                height = px(44)
            }

            val infoLayoutParams = (binding.songTitle.parent as? View)?.layoutParams as? ViewGroup.MarginLayoutParams
            infoLayoutParams?.marginStart = px(10)
            if (infoLayoutParams != null) {
                (binding.songTitle.parent as View).layoutParams = infoLayoutParams
            }

            val durationLayoutParams = binding.songDuration.layoutParams as? ViewGroup.MarginLayoutParams
            durationLayoutParams?.marginStart = px(4)
            if (durationLayoutParams != null) {
                binding.songDuration.layoutParams = durationLayoutParams
            }

            val menuLayoutParams = binding.menuButton.layoutParams as? ViewGroup.MarginLayoutParams
            menuLayoutParams?.marginStart = px(4)
            if (menuLayoutParams != null) {
                binding.menuButton.layoutParams = menuLayoutParams
            }

            binding.songTitle.textSize = ThemeManager.scaleSp(context, 14f)
            binding.songArtist.textSize = ThemeManager.scaleSp(context, 11f)
            binding.songDuration.textSize = ThemeManager.scaleSp(context, 10f)
            binding.menuButton.layoutParams = binding.menuButton.layoutParams.apply {
                width = px(20)
                height = px(20)
            }
            binding.menuButton.minimumWidth = px(20)
            binding.menuButton.minimumHeight = px(20)
        }
    }

    inner class FolderCardViewHolder(
        private val binding: ItemSongFolderCardBinding,
        private val onSongClick: (Song) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(song: Song) {
            binding.songTitle.text = song.displayName
            binding.songArtist.text = song.artistName.ifBlank { "Unknown Artist" }
            binding.songAlbum.text = song.albumName.ifBlank { "Single or loose track" }
            binding.songDuration.text = song.durationText
            applyAdaptiveCardSizing()

            loadAlbumArt(binding, song)

            binding.root.setOnClickListener { view ->
                AnimationUtils.animateButtonPress(view) {
                    onSongClick(song)
                }
            }

            binding.menuButton.setOnClickListener { showContextMenu(binding.root, song, it) }
        }

        private fun applyAdaptiveCardSizing() {
            val context = binding.root.context
            val density = context.resources.displayMetrics.density
            val cardScale = ThemeManager.getAdaptiveUiScale(context)

            fun px(baseDp: Int): Int = (baseDp * density * cardScale).toInt().coerceAtLeast(1)

            val rootLayoutParams = binding.root.layoutParams as? ViewGroup.MarginLayoutParams
            rootLayoutParams?.apply {
                marginStart = px(6)
                topMargin = px(5)
                marginEnd = px(6)
                bottomMargin = px(5)
            }
            if (rootLayoutParams != null) {
                binding.root.layoutParams = rootLayoutParams
            }
            binding.root.radius = px(18).toFloat()
            binding.root.strokeWidth = px(1)
            binding.root.minimumHeight = px(84)

            binding.songArtwork.layoutParams = binding.songArtwork.layoutParams.apply {
                width = px(60)
                height = px(60)
            }

            binding.songTitle.textSize = ThemeManager.scaleSp(context, 15f)
            binding.songArtist.textSize = ThemeManager.scaleSp(context, 12f)
            binding.songAlbum.textSize = ThemeManager.scaleSp(context, 11f)
            binding.songDuration.textSize = ThemeManager.scaleSp(context, 10f)

            binding.menuButton.layoutParams = binding.menuButton.layoutParams.apply {
                width = px(22)
                height = px(22)
            }
            binding.menuButton.minimumWidth = px(22)
            binding.menuButton.minimumHeight = px(22)
        }
    }

    inner class GridViewHolder(
        private val binding: ItemSongGridBinding,
        private val onSongClick: (Song) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(song: Song) {
            applyAdaptiveGridSizing()
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

        private fun applyAdaptiveGridSizing() {
            val context = binding.root.context
            val density = context.resources.displayMetrics.density
            val scale = ThemeManager.getAdaptiveUiScale(context)

            fun px(baseDp: Int): Int = (baseDp * density * scale).toInt().coerceAtLeast(1)

            val rootLayoutParams = binding.root.layoutParams as? ViewGroup.MarginLayoutParams
            rootLayoutParams?.apply {
                marginStart = px(4)
                topMargin = px(4)
                marginEnd = px(4)
                bottomMargin = px(4)
            }
            if (rootLayoutParams != null) {
                binding.root.layoutParams = rootLayoutParams
            }

            binding.root.radius = px(9).toFloat()
            binding.root.cardElevation = px(2).toFloat()

            val container = binding.root.getChildAt(0) as? ViewGroup
            val artworkContainer = container?.getChildAt(0)
            val textContainer = container?.getChildAt(1) as? ViewGroup
            textContainer?.setPadding(px(8), px(8), px(8), px(8))

            artworkContainer?.minimumHeight = px(100)

            val menuLayoutParams = binding.menuButton.layoutParams as? ViewGroup.MarginLayoutParams
            menuLayoutParams?.setMargins(px(4), px(4), px(4), px(4))
            if (menuLayoutParams != null) {
                binding.menuButton.layoutParams = menuLayoutParams
            }

            binding.songTitle.textSize = ThemeManager.scaleSp(context, 12f)
            binding.songArtist.textSize = ThemeManager.scaleSp(context, 10f)
            binding.menuButton.layoutParams = binding.menuButton.layoutParams.apply {
                width = px(20)
                height = px(20)
            }
            binding.menuButton.minimumWidth = px(20)
            binding.menuButton.minimumHeight = px(20)
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
            is ItemSongFolderCardBinding -> { rootView = binding.root; artworkView = binding.songArtwork }
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
