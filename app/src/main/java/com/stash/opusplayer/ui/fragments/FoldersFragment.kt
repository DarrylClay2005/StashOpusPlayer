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
        adapter = FolderAdapter { _ ->
            // TODO: navigate to folder detail list if needed
        }
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = this@FoldersFragment.adapter
        }
    }

    private fun loadFolders() {
        lifecycleScope.launch {
            try {
                val songs = repository.getAllSongsFromAllSources()
                val folders = songs
                    .groupBy { File(it.path).parent ?: "/" }
                    .map { (path, group) -> FolderInfo(path, group.size, group) }
                    .sortedBy { it.path.lowercase() }
                if (folders.isNotEmpty()) {
                    adapter.submitList(folders)
                    binding.recyclerView.visibility = View.VISIBLE
                    binding.emptyStateText.visibility = View.GONE
                } else {
                    binding.recyclerView.visibility = View.GONE
                    binding.emptyStateText.visibility = View.VISIBLE
                }
            } catch (_: Exception) {
                binding.recyclerView.visibility = View.GONE
                binding.emptyStateText.visibility = View.VISIBLE
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
