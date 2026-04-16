package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.stash.opusplayer.R
import com.stash.opusplayer.databinding.ItemFolderBinding
import com.stash.opusplayer.databinding.ItemFolderGridBinding
import com.stash.opusplayer.ui.fragments.FolderInfo
import com.stash.opusplayer.utils.MetadataExtractor

class FolderAdapter(
    private val onClick: (FolderInfo) -> Unit
) : ListAdapter<FolderInfo, RecyclerView.ViewHolder>(FolderDiffCallback()) {

    companion object {
        private const val VIEW_TYPE_LIST = 0
        private const val VIEW_TYPE_GRID = 1
    }

    private var columns: Int = 1
    private var metadataExtractor: MetadataExtractor? = null

    fun setColumns(cols: Int) {
        if (columns != cols) {
            columns = cols
            notifyDataSetChanged()
        }
    }

    override fun getItemViewType(position: Int): Int = if (columns == 1) VIEW_TYPE_LIST else VIEW_TYPE_GRID

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        if (metadataExtractor == null) {
            metadataExtractor = MetadataExtractor(parent.context.applicationContext)
        }
        val inflater = LayoutInflater.from(parent.context)
        return if (viewType == VIEW_TYPE_LIST) {
            val binding = ItemFolderBinding.inflate(inflater, parent, false)
            ListViewHolder(binding)
        } else {
            val binding = ItemFolderGridBinding.inflate(inflater, parent, false)
            GridViewHolder(binding)
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
        private val binding: ItemFolderBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: FolderInfo) {
            binding.folderName.text = item.displayName
            binding.folderPath.text = item.parentLabel
            binding.folderPreview.text = "Starts with ${item.previewSongTitle}"
            binding.folderCount.text = item.countLabel
            loadFolderArtwork(binding.folderArtwork, item)
            binding.root.setOnClickListener { onClick(item) }
        }
    }

    inner class GridViewHolder(
        private val binding: ItemFolderGridBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: FolderInfo) {
            binding.folderName.text = item.displayName
            binding.folderPath.text = item.parentLabel
            binding.folderPreview.text = "Starts with ${item.previewSongTitle}"
            binding.folderCount.text = item.countLabel
            loadFolderArtwork(binding.folderArtwork, item)
            binding.root.setOnClickListener { onClick(item) }
        }
    }

    private fun loadFolderArtwork(imageView: android.widget.ImageView, item: FolderInfo) {
        val song = item.thumbnailSong
        if (song == null) {
            Glide.with(imageView.context)
                .load(R.drawable.ic_music_note)
                .centerCrop()
                .into(imageView)
            return
        }

        val cached = runCatching { metadataExtractor?.loadCachedArtwork(imageView.context, song, 384) }.getOrNull()
        val embedded = if (cached == null) {
            runCatching { metadataExtractor?.decodeAlbumArt(song.albumArt) }.getOrNull()
        } else {
            null
        }
        val artModel: Any = cached ?: embedded ?: R.drawable.ic_music_note

        Glide.with(imageView.context)
            .load(artModel)
            .placeholder(R.drawable.ic_music_note)
            .error(R.drawable.ic_music_note)
            .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
            .centerCrop()
            .into(imageView)
    }

    private class FolderDiffCallback : DiffUtil.ItemCallback<FolderInfo>() {
        override fun areItemsTheSame(oldItem: FolderInfo, newItem: FolderInfo): Boolean = oldItem.path == newItem.path
        override fun areContentsTheSame(oldItem: FolderInfo, newItem: FolderInfo): Boolean = oldItem == newItem
    }
}
