package com.stash.opusplayer.ui.adapters

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.stash.opusplayer.R
import com.stash.opusplayer.data.DownloadProgress
import com.stash.opusplayer.data.DownloadStatus
import com.stash.opusplayer.data.YouTubeVideo
import com.stash.opusplayer.databinding.ItemYoutubeVideoBinding
import java.text.NumberFormat
import java.util.*

class YouTubeVideoAdapter(
    private val onVideoClick: (YouTubeVideo) -> Unit = {},
    private val onDownloadClick: (YouTubeVideo) -> Unit = {},
    private val onPreviewClick: (YouTubeVideo) -> Unit = {}
) : ListAdapter<YouTubeVideo, YouTubeVideoAdapter.VideoViewHolder>(DiffCallback) {

    private val downloadProgress = mutableMapOf<String, DownloadProgress>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VideoViewHolder {
        val binding = ItemYoutubeVideoBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return VideoViewHolder(binding)
    }

    override fun onBindViewHolder(holder: VideoViewHolder, position: Int) {
        val video = getItem(position)
        holder.bind(video)
    }

    fun updateDownloadProgress(videoId: String, progress: DownloadProgress) {
        downloadProgress[videoId] = progress
        // Find the position of this video and notify
        val position = currentList.indexOfFirst { it.id == videoId }
        if (position >= 0) {
            notifyItemChanged(position)
        }
    }

    inner class VideoViewHolder(private val binding: ItemYoutubeVideoBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(video: YouTubeVideo) {
            binding.apply {
                // Set video info
                titleTextView.text = video.title
                channelTextView.text = video.channelTitle
                
                // Format duration
                durationTextView.text = video.duration?.let { formatDuration(it) } ?: ""
                durationTextView.visibility = if (video.duration != null) View.VISIBLE else View.GONE
                
                // Format view count
                viewsTextView.text = video.viewCount?.let { formatViewCount(it) } ?: ""
                viewsTextView.visibility = if (video.viewCount != null) View.VISIBLE else View.GONE

                // Load thumbnail
                Glide.with(thumbnailImageView.context)
                    .load(video.highResThumbnailUrl ?: video.thumbnailUrl)
                    .placeholder(R.drawable.ic_music_note)
                    .error(R.drawable.ic_music_note)
                    .into(thumbnailImageView)

                // Handle download progress
                val progress = downloadProgress[video.id]
                if (progress != null) {
                    downloadProgressContainer.visibility = View.VISIBLE
                    when (progress.status) {
                        DownloadStatus.DOWNLOADING -> {
                            downloadProgress.isIndeterminate = false
                            downloadProgress.setProgressCompat(progress.progress, true)
                            downloadStatusText.text = "${progress.progress}%"
                            downloadButton.text = "Cancel"
                            downloadButton.isEnabled = true
                        }
                        DownloadStatus.COMPLETED -> {
                            downloadProgress.setProgressCompat(100, true)
                            downloadStatusText.text = "Complete"
                            downloadButton.text = "Downloaded"
                            downloadButton.isEnabled = false
                        }
                        DownloadStatus.FAILED -> {
                            downloadProgressContainer.visibility = View.GONE
                            downloadButton.text = "Retry"
                            downloadButton.isEnabled = true
                        }
                        DownloadStatus.PENDING -> {
                            downloadProgress.isIndeterminate = true
                            downloadStatusText.text = "Pending..."
                            downloadButton.text = "Cancel"
                            downloadButton.isEnabled = true
                        }
                        DownloadStatus.CANCELLED -> {
                            downloadProgressContainer.visibility = View.GONE
                            downloadButton.text = "Download HQ"
                            downloadButton.isEnabled = true
                        }
                    }
                } else {
                    downloadProgressContainer.visibility = View.GONE
                    downloadButton.text = "Download HQ"
                    downloadButton.isEnabled = true
                }

                // Set click listeners
                root.setOnClickListener { onVideoClick(video) }
                downloadButton.setOnClickListener { onDownloadClick(video) }
                previewButton.setOnClickListener { onPreviewClick(video) }
            }
        }

        private fun formatDuration(isoDuration: String): String {
            // Parse ISO 8601 duration format (PT4M13S -> 4:13)
            val regex = Regex("PT(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?")
            val match = regex.find(isoDuration) ?: return isoDuration

            val hours = match.groupValues[1].toIntOrNull() ?: 0
            val minutes = match.groupValues[2].toIntOrNull() ?: 0
            val seconds = match.groupValues[3].toIntOrNull() ?: 0

            return when {
                hours > 0 -> String.format("%d:%02d:%02d", hours, minutes, seconds)
                else -> String.format("%d:%02d", minutes, seconds)
            }
        }

        private fun formatViewCount(viewCount: String): String {
            return try {
                val count = viewCount.toLong()
                when {
                    count >= 1_000_000_000 -> "${(count / 1_000_000_000.0).let { "%.1f".format(it) }}B views"
                    count >= 1_000_000 -> "${(count / 1_000_000.0).let { "%.1f".format(it) }}M views"
                    count >= 1_000 -> "${(count / 1_000.0).let { "%.1f".format(it) }}K views"
                    else -> "${NumberFormat.getInstance().format(count)} views"
                }
            } catch (e: NumberFormatException) {
                "$viewCount views"
            }
        }
    }

    companion object {
        private val DiffCallback = object : DiffUtil.ItemCallback<YouTubeVideo>() {
            override fun areItemsTheSame(oldItem: YouTubeVideo, newItem: YouTubeVideo): Boolean {
                return oldItem.id == newItem.id
            }

            override fun areContentsTheSame(oldItem: YouTubeVideo, newItem: YouTubeVideo): Boolean {
                return oldItem == newItem
            }
        }
    }
}
