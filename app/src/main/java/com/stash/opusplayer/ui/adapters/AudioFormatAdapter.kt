package com.stash.stashwave.ui.adapters

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.stash.stashwave.R
import com.stash.stashwave.data.AudioFormat
import com.stash.stashwave.databinding.ItemAudioFormatBinding

class AudioFormatAdapter(
    private val onFormatSelected: (AudioFormat) -> Unit
) : ListAdapter<AudioFormat, AudioFormatAdapter.FormatViewHolder>(DiffCallback) {

    private var selectedPosition = -1

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): FormatViewHolder {
        val binding = ItemAudioFormatBinding.inflate(
            LayoutInflater.from(parent.context),
            parent,
            false
        )
        return FormatViewHolder(binding)
    }

    override fun onBindViewHolder(holder: FormatViewHolder, position: Int) {
        val format = getItem(position)
        holder.bind(format, position == selectedPosition)
    }

    fun selectFormat(format: AudioFormat) {
        val newPosition = currentList.indexOf(format)
        if (newPosition >= 0) {
            val oldPosition = selectedPosition
            selectedPosition = newPosition
            
            // Notify changes
            if (oldPosition >= 0) notifyItemChanged(oldPosition)
            notifyItemChanged(selectedPosition)
            
            onFormatSelected(format)
        }
    }

    fun getSelectedFormat(): AudioFormat? {
        return if (selectedPosition >= 0) getItem(selectedPosition) else null
    }

    inner class FormatViewHolder(private val binding: ItemAudioFormatBinding) :
        RecyclerView.ViewHolder(binding.root) {

        init {
            binding.root.setOnClickListener {
                val position = adapterPosition
                if (position != RecyclerView.NO_POSITION) {
                    val format = getItem(position)
                    selectFormat(format)
                }
            }
        }

        fun bind(format: AudioFormat, isSelected: Boolean) {
            binding.apply {
                // Set format name (extension + quality)
                formatName.text = "${format.extension.uppercase()} ${format.quality}"
                
                // Set quality badge
                qualityBadge.text = format.quality
                qualityBadge.setBackgroundResource(
                    when (format.quality.lowercase()) {
                        "hq" -> R.drawable.quality_badge_background
                        "medium" -> R.drawable.quality_badge_background  
                        "low" -> R.drawable.quality_badge_background
                        else -> R.drawable.quality_badge_background
                    }
                )

                // Set format details
                val details = buildString {
                    format.bitrate?.let { append("$it kbps") }
                    format.fileSize?.let { 
                        if (isNotEmpty()) append(" • ")
                        append(it)
                    }
                    if (isNotEmpty()) append(" • ")
                    append("${format.codec.uppercase()} Codec")
                }
                formatDetails.text = details

                // Set format icon based on extension
                val iconRes = when (format.extension.lowercase()) {
                    "mp3" -> R.drawable.ic_music_note
                    "opus", "webm" -> R.drawable.ic_music_note  
                    "m4a", "aac" -> R.drawable.ic_music_note
                    "flac" -> R.drawable.ic_music_note
                    else -> R.drawable.ic_music_note
                }
                formatIcon.setImageResource(iconRes)

                // Set selection state
                selectionRadio.isChecked = isSelected
                root.isSelected = isSelected
                
                // Update card appearance based on selection
                root.strokeWidth = if (isSelected) 2 else 1
                root.strokeColor = root.context.getColor(
                    if (isSelected) android.R.color.holo_blue_bright 
                    else android.R.color.darker_gray
                )
            }
        }
    }

    companion object {
        private val DiffCallback = object : DiffUtil.ItemCallback<AudioFormat>() {
            override fun areItemsTheSame(oldItem: AudioFormat, newItem: AudioFormat): Boolean {
                return oldItem.formatId == newItem.formatId
            }

            override fun areContentsTheSame(oldItem: AudioFormat, newItem: AudioFormat): Boolean {
                return oldItem == newItem
            }
        }
    }
}
