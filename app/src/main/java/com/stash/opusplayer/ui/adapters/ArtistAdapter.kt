package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.databinding.ItemArtistBinding
import com.stash.opusplayer.ui.fragments.ArtistInfo

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
