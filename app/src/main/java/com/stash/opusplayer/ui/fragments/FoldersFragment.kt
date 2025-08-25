package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.databinding.FragmentFoldersBinding
import com.stash.opusplayer.ui.adapters.FolderAdapter
import kotlinx.coroutines.launch
import java.io.File
import android.net.Uri

class FoldersFragment : Fragment() {

    private var _binding: FragmentFoldersBinding? = null
    private val binding get() = _binding!!

    private lateinit var adapter: FolderAdapter
    private lateinit var repository: MusicRepository

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentFoldersBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        repository = MusicRepository(requireContext())
        setupRecyclerView()
        loadFolders()
    }

    private fun setupRecyclerView() {
        adapter = FolderAdapter { info ->
            val fragment = FolderDetailFragment.newInstance(info.path, ArrayList(info.songs))
            parentFragmentManager.beginTransaction()
                .replace(com.stash.opusplayer.R.id.main_content, fragment)
                .addToBackStack(null)
                .commit()
        }
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = this@FoldersFragment.adapter
        }
    }

    private fun loadFolders() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val songs = repository.getAllSongsFromAllSources()
                val folders = songs
                    .groupBy { song ->
                        if (song.path.startsWith("content://")) {
                            // Use relativePath set during SAF scan; fallback to content URI host
                            val rp = song.relativePath.ifBlank { "Content/${Uri.parse(song.path).host ?: "Music"}/" }
                            // Normalize leading/trailing slashes
                            rp.trimStart('/').trimEnd('/')
                        } else {
                            File(song.path).parent ?: "/"
                        }
                    }
                    .map { (path, group) -> FolderInfo(path, group.size, group) }
                    .sortedBy { it.path.lowercase() }
                val b = _binding ?: return@launch
                if (folders.isNotEmpty()) {
                    adapter.submitList(folders)
                    b.recyclerView.visibility = View.VISIBLE
                    b.emptyStateText.visibility = View.GONE
                } else {
                    b.recyclerView.visibility = View.GONE
                    b.emptyStateText.visibility = View.VISIBLE
                }
            } catch (_: Exception) {
                val b = _binding ?: return@launch
                b.recyclerView.visibility = View.GONE
                b.emptyStateText.visibility = View.VISIBLE
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

data class FolderInfo(
    val path: String,
    val songCount: Int,
    val songs: List<com.stash.opusplayer.data.Song>
)
