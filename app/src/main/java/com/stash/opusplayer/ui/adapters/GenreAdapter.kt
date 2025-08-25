package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.databinding.ItemGenreBinding
import com.stash.opusplayer.ui.fragments.GenreInfo

class GenreAdapter(
    private val onClick: (GenreInfo) -> Unit
) : ListAdapter<GenreInfo, GenreAdapter.GenreViewHolder>(GenreDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): GenreViewHolder {
        val binding = ItemGenreBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return GenreViewHolder(binding)
    }

    override fun onBindViewHolder(holder: GenreViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class GenreViewHolder(
        private val binding: ItemGenreBinding
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: GenreInfo) {
            binding.genreName.text = item.name
            binding.genreCount.text = "${item.songCount} song${if (item.songCount == 1) "" else "s"}"
            binding.root.setOnClickListener { onClick(item) }
        }
    }

    private class GenreDiffCallback : DiffUtil.ItemCallback<GenreInfo>() {
        override fun areItemsTheSame(oldItem: GenreInfo, newItem: GenreInfo): Boolean = oldItem.name == newItem.name
        override fun areContentsTheSame(oldItem: GenreInfo, newItem: GenreInfo): Boolean = oldItem == newItem
    }
}
