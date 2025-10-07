package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.databinding.ItemFolderBinding
import com.stash.opusplayer.databinding.ItemFolderGridBinding
import com.stash.opusplayer.ui.fragments.FolderInfo

class FolderAdapter(
    private val onClick: (FolderInfo) -> Unit
) : ListAdapter<FolderInfo, RecyclerView.ViewHolder>(FolderDiffCallback()) {

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
            binding.folderPath.text = item.path
            binding.folderCount.text = "${item.songCount} song${if (item.songCount == 1) "" else "s"}"
            binding.root.setOnClickListener { onClick(item) }
        }
    }

    inner class GridViewHolder(
        private val binding: ItemFolderGridBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: FolderInfo) {
            // Show only the last segment of the path for a cleaner tile title
            val name = item.path.substringAfterLast('/')
                .ifBlank { item.path }
            binding.folderName.text = name
            binding.folderCount.text = "${item.songCount}"
            binding.root.setOnClickListener { onClick(item) }
        }
    }

    private class FolderDiffCallback : DiffUtil.ItemCallback<FolderInfo>() {
        override fun areItemsTheSame(oldItem: FolderInfo, newItem: FolderInfo): Boolean = oldItem.path == newItem.path
        override fun areContentsTheSame(oldItem: FolderInfo, newItem: FolderInfo): Boolean = oldItem == newItem
    }
}
