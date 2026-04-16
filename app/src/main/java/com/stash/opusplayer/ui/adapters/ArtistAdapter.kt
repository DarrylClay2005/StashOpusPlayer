package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.databinding.ItemArtistBinding
import com.stash.opusplayer.ui.fragments.ArtistInfo
import com.bumptech.glide.Glide
import com.stash.opusplayer.artwork.ArtistGenreArtworkFetcher
import com.stash.opusplayer.ui.appearance.ThemeManager
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
            applyAdaptiveSizing()
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

        private fun applyAdaptiveSizing() {
            val context = binding.root.context
            val density = context.resources.displayMetrics.density
            val scale = ThemeManager.getAdaptiveUiScale(context)

            fun px(baseDp: Int): Int = (baseDp * density * scale).toInt().coerceAtLeast(1)

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

            binding.root.radius = px(10).toFloat()
            binding.root.cardElevation = px(2).toFloat()
            binding.root.minimumHeight = px(78)
            (binding.root.getChildAt(0) as? ViewGroup)?.setPadding(px(12), px(10), px(12), px(10))

            binding.artistArtwork.layoutParams = binding.artistArtwork.layoutParams.apply {
                width = px(56)
                height = px(56)
            }
            val infoLayoutParams = (binding.artistName.parent as? View)?.layoutParams as? ViewGroup.MarginLayoutParams
            infoLayoutParams?.marginStart = px(12)
            if (infoLayoutParams != null) {
                (binding.artistName.parent as View).layoutParams = infoLayoutParams
            }
            val arrowLayoutParams = binding.arrowForward.layoutParams as? ViewGroup.MarginLayoutParams
            arrowLayoutParams?.marginStart = px(6)
            if (arrowLayoutParams != null) {
                binding.arrowForward.layoutParams = arrowLayoutParams
            }

            binding.arrowForward.layoutParams = binding.arrowForward.layoutParams.apply {
                width = px(20)
                height = px(20)
            }
            binding.artistName.textSize = ThemeManager.scaleSp(context, 16f)
            binding.songCount.textSize = ThemeManager.scaleSp(context, 12f)
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
