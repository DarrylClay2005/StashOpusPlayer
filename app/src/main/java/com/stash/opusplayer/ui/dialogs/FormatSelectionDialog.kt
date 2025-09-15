package com.stash.opusplayer.ui.dialogs

import android.app.Dialog
import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import androidx.recyclerview.widget.LinearLayoutManager
import com.bumptech.glide.Glide
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.stash.opusplayer.R
import com.stash.opusplayer.data.AudioFormat
import com.stash.opusplayer.data.YouTubeVideo
import com.stash.opusplayer.databinding.DialogFormatSelectionBinding
import com.stash.opusplayer.ui.adapters.AudioFormatAdapter

class FormatSelectionDialog(
    context: Context,
    private val video: YouTubeVideo,
    private val formats: List<AudioFormat>,
    private val onFormatSelected: (AudioFormat) -> Unit
) : Dialog(context) {

    private lateinit var binding: DialogFormatSelectionBinding
    private lateinit var formatAdapter: AudioFormatAdapter
    private var selectedFormat: AudioFormat? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        binding = DialogFormatSelectionBinding.inflate(LayoutInflater.from(context))
        setContentView(binding.root)
        
        setupVideoInfo()
        setupButtons()
        setupFormatList()
    }

    private fun setupVideoInfo() {
        binding.apply {
            videoTitle.text = video.title
            videoChannel.text = video.channelTitle
            
            // Load thumbnail
            Glide.with(context)
                .load(video.highResThumbnailUrl ?: video.thumbnailUrl)
                .placeholder(R.drawable.ic_music_note)
                .error(R.drawable.ic_music_note)
                .into(videoThumbnail)
        }
    }

    private fun setupFormatList() {
        formatAdapter = AudioFormatAdapter { format ->
            selectedFormat = format
            // Automatically start download when format is selected
            onFormatSelected(format)
            dismiss()
        }
        
        binding.formatsRecyclerView.apply {
            adapter = formatAdapter
            layoutManager = LinearLayoutManager(context)
        }
        
        formatAdapter.submitList(formats)
    }

    private fun setupButtons() {
        binding.apply {
            cancelButton.setOnClickListener {
                dismiss()
            }
        }
    }

    companion object {
        fun show(
            context: Context,
            video: YouTubeVideo,
            formats: List<AudioFormat>,
            onFormatSelected: (AudioFormat) -> Unit
        ) {
            val dialog = FormatSelectionDialog(context, video, formats, onFormatSelected)
            dialog.show()
        }
    }
}
