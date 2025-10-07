package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.databinding.ItemGenreBinding
import com.stash.opusplayer.ui.fragments.GenreInfo
import com.bumptech.glide.Glide
import com.stash.opusplayer.artwork.ArtistGenreArtworkFetcher
import androidx.lifecycle.*
import kotlinx.coroutines.launch

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

            val context = binding.root.context
            val fetcher = ArtistGenreArtworkFetcher(context)
            val cached = ArtistGenreArtworkFetcher.genreFile(context, item.name)
            if (cached.exists()) {
                Glide.with(context).load(cached).centerCrop().into(binding.genreIcon)
            } else {
                Glide.with(context).load(com.stash.opusplayer.R.drawable.ic_category).into(binding.genreIcon)
                val owner = context as? LifecycleOwner
                owner?.lifecycleScope?.launch {
                    val f = fetcher.getOrFetchGenre(item.name)
                    if (f != null) {
                        Glide.with(context).load(f).centerCrop().into(binding.genreIcon)
                    }
                }
            }

            binding.root.setOnClickListener { onClick(item) }
        }
    }

    private class GenreDiffCallback : DiffUtil.ItemCallback<GenreInfo>() {
        override fun areItemsTheSame(oldItem: GenreInfo, newItem: GenreInfo): Boolean = oldItem.name == newItem.name
        override fun areContentsTheSame(oldItem: GenreInfo, newItem: GenreInfo): Boolean = oldItem == newItem
    }
}
