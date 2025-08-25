package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.databinding.FragmentPlaylistsBinding
import com.stash.opusplayer.data.MusicRepository
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class PlaylistsFragment : Fragment() {
    
    private var _binding: FragmentPlaylistsBinding? = null
    private val binding get() = _binding!!

    private lateinit var repository: MusicRepository
    private lateinit var adapter: PlaylistsAdapter

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentPlaylistsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        repository = MusicRepository(requireContext())
        setupRecycler()
        binding.createButton.setOnClickListener { promptCreate() }
        observePlaylists()
    }

    private fun setupRecycler() {
        adapter = PlaylistsAdapter { playlistId ->
            parentFragmentManager.beginTransaction()
                .replace(com.stash.opusplayer.R.id.main_content, PlaylistDetailFragment.newInstance(playlistId))
                .addToBackStack(null)
                .commit()
        }
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter
    }

    private fun observePlaylists() {
        viewLifecycleOwner.lifecycleScope.launch {
            repository.getPlaylists().collectLatest { list ->
                val b = _binding ?: return@collectLatest
                if (list.isNotEmpty()) {
                    adapter.submitList(list)
                    b.recyclerView.visibility = View.VISIBLE
                    b.emptyStateText.visibility = View.GONE
                } else {
                    b.recyclerView.visibility = View.GONE
                    b.emptyStateText.visibility = View.VISIBLE
                }
            }
        }
    }

    private fun promptCreate() {
        val edit = android.widget.EditText(requireContext())
        edit.hint = "Playlist name"
        android.app.AlertDialog.Builder(requireContext())
            .setTitle("Create playlist")
            .setView(edit)
            .setPositiveButton("Create") { _, _ ->
                val name = edit.text.toString().trim()
                if (name.isNotEmpty()) {
                    viewLifecycleOwner.lifecycleScope.launch {
                        repository.createPlaylist(name)
                    }
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

// Adapter for playlists list
private class PlaylistsAdapter(
    val onClick: (Long) -> Unit
) : androidx.recyclerview.widget.ListAdapter<com.stash.opusplayer.data.database.PlaylistWithCount, PlaylistsViewHolder>(
    object : androidx.recyclerview.widget.DiffUtil.ItemCallback<com.stash.opusplayer.data.database.PlaylistWithCount>() {
        override fun areItemsTheSame(
            oldItem: com.stash.opusplayer.data.database.PlaylistWithCount,
            newItem: com.stash.opusplayer.data.database.PlaylistWithCount
        ): Boolean = oldItem.id == newItem.id
        override fun areContentsTheSame(
            oldItem: com.stash.opusplayer.data.database.PlaylistWithCount,
            newItem: com.stash.opusplayer.data.database.PlaylistWithCount
        ): Boolean = oldItem == newItem
    }
) {
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PlaylistsViewHolder {
        val row = com.stash.opusplayer.databinding.ItemPlaylistBinding.inflate(
            LayoutInflater.from(parent.context), parent, false
        )
        return PlaylistsViewHolder(row, onClick)
    }
    override fun onBindViewHolder(holder: PlaylistsViewHolder, position: Int) {
        holder.bind(getItem(position))
    }
}

private class PlaylistsViewHolder(
    private val binding: com.stash.opusplayer.databinding.ItemPlaylistBinding,
    private val onClick: (Long) -> Unit
) : androidx.recyclerview.widget.RecyclerView.ViewHolder(binding.root) {
    fun bind(item: com.stash.opusplayer.data.database.PlaylistWithCount) {
        binding.playlistName.text = item.name
        binding.playlistCount.text = "${item.songCount} song${if (item.songCount == 1) "" else "s"}"
        binding.root.setOnClickListener { onClick(item.id) }
    }
}
