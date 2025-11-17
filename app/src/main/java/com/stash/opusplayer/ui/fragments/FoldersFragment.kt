package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.databinding.FragmentFoldersBinding
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.folder.ui.adapters.FolderItem
import com.stash.opusplayer.folder.ui.adapters.RevolutionaryFolderAdapter
import kotlinx.coroutines.*

class FoldersFragment : Fragment() {
    private var _binding: FragmentFoldersBinding? = null
    private val binding get() = _binding!!
    private lateinit var repo: MusicRepository

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentFoldersBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        repo = MusicRepository(requireContext())
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())

        // Load folders from songs
        viewLifecycleOwner.lifecycleScope.launch {
            val songs = withContext(Dispatchers.IO) { repo.getAllSongsFromAllSourcesFast() }
            val folderMap = mutableMapOf<String, MutableList<com.stash.opusplayer.data.Song>>()
            songs.forEach { song ->
                try {
                    val file = java.io.File(song.path)
                    val parent = file.parentFile?.absolutePath ?: return@forEach
                    folderMap.getOrPut(parent) { mutableListOf() }.add(song)
                } catch (_: Exception) {}
            }

            val items = folderMap.map { (path, list) ->
                // Try to find artwork from first song in folder via metadata
                val art = list.firstOrNull()?.let { s ->
                    try {
                        val identifier = s.path.ifBlank { s.title }
                        // Prefer file-based artwork to reduce memory overhead
                        com.stash.opusplayer.utils.MetadataStorageManager.getArtworkFilePath(requireContext(), identifier)
                            ?: run {
                                val meta = com.stash.opusplayer.utils.MetadataExtractor(requireContext()).extractMetadata(s)
                                val id = s.path.ifBlank { s.title }
                                com.stash.opusplayer.utils.MetadataStorageManager.getArtworkFilePath(requireContext(), id)
                            }
                    } catch (_: Exception) { null }
                }
                FolderItem(path = path, displayName = java.io.File(path).name, songCount = list.size, artworkPath = art)
            }.sortedByDescending { it.songCount }

            binding.recyclerView.adapter = RevolutionaryFolderAdapter(items)
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
