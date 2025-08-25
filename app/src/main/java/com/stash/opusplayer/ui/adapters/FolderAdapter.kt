package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.databinding.ItemFolderBinding
import com.stash.opusplayer.ui.fragments.FolderInfo

class FolderAdapter(
    private val onClick: (FolderInfo) -> Unit
) : ListAdapter<FolderInfo, FolderAdapter.FolderViewHolder>(FolderDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): FolderViewHolder {
        val binding = ItemFolderBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return FolderViewHolder(binding)
    }

    override fun onBindViewHolder(holder: FolderViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class FolderViewHolder(
        private val binding: ItemFolderBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: FolderInfo) {
            binding.folderPath.text = item.path
            binding.folderCount.text = "${item.songCount} song${if (item.songCount == 1) "" else "s"}"
            binding.root.setOnClickListener { onClick(item) }
        }
    }

    private class FolderDiffCallback : DiffUtil.ItemCallback<FolderInfo>() {
        override fun areItemsTheSame(oldItem: FolderInfo, newItem: FolderInfo): Boolean = oldItem.path == newItem.path
        override fun areContentsTheSame(oldItem: FolderInfo, newItem: FolderInfo): Boolean = oldItem == newItem
    }
}
