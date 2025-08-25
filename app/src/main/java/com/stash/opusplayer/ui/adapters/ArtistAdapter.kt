package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.databinding.ItemArtistBinding
import com.stash.opusplayer.ui.fragments.ArtistInfo
import com.bumptech.glide.Glide
import com.stash.opusplayer.artwork.ArtistGenreArtworkFetcher
import androidx.lifecycle.*
import kotlinx.coroutines.launch

class ArtistAdapter(
    private val onArtistClick: (ArtistInfo) -> Unit
) : ListAdapter<ArtistInfo, ArtistAdapter.ArtistViewHolder>(ArtistDiffCallback()) {
    
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ArtistViewHolder {
        val binding = ItemArtistBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return ArtistViewHolder(binding, onArtistClick)
    }
    
    override fun onBindViewHolder(holder: ArtistViewHolder, position: Int) {
        holder.bind(getItem(position))
    }
    
    class ArtistViewHolder(
        private val binding: ItemArtistBinding,
        private val onArtistClick: (ArtistInfo) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {
        
        fun bind(artist: ArtistInfo) {
            binding.artistName.text = artist.name
            binding.songCount.text = "${artist.songCount} song${if (artist.songCount != 1) "s" else ""}"

            val context = binding.root.context
            val fetcher = ArtistGenreArtworkFetcher(context)
            val cached = ArtistGenreArtworkFetcher.artistFile(context, artist.name)
            if (cached.exists()) {
                Glide.with(context).load(cached).centerCrop().into(binding.artistArtwork)
            } else {
                Glide.with(context).load(com.stash.opusplayer.R.drawable.ic_person).into(binding.artistArtwork)
                val owner = context as? LifecycleOwner
                owner?.lifecycleScope?.launch {
                    val f = fetcher.getOrFetchArtist(artist.name)
                    if (f != null) {
                        Glide.with(context).load(f).centerCrop().into(binding.artistArtwork)
                    }
                }
            }
            
            binding.root.setOnClickListener {
                onArtistClick(artist)
            }
        }
    }
    
    private class ArtistDiffCallback : DiffUtil.ItemCallback<ArtistInfo>() {
        override fun areItemsTheSame(oldItem: ArtistInfo, newItem: ArtistInfo): Boolean {
            return oldItem.name == newItem.name
        }
        
        override fun areContentsTheSame(oldItem: ArtistInfo, newItem: ArtistInfo): Boolean {
            return oldItem == newItem
        }
    }
}
