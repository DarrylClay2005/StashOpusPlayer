package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.databinding.FragmentGenresBinding
import com.stash.opusplayer.ui.adapters.GenreAdapter
import kotlinx.coroutines.launch

class GenresFragment : Fragment() {

    private var _binding: FragmentGenresBinding? = null
    private val binding get() = _binding!!

    private lateinit var adapter: GenreAdapter
    private lateinit var repository: MusicRepository

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentGenresBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        repository = MusicRepository(requireContext())
        setupRecyclerView()
        loadGenres()
    }

    private fun setupRecyclerView() {
        adapter = GenreAdapter { _ ->
            // TODO: navigate to a genre detail list if needed
        }
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = this@GenresFragment.adapter
        }
    }

    private fun loadGenres() {
        lifecycleScope.launch {
            try {
                val allSongs = repository.getAllSongsWithMetadata()
                val genres = allSongs
                    .groupBy { it.genre.ifBlank { "Unknown" } }
                    .map { (name, songs) -> GenreInfo(name, songs.size, songs) }
                    .sortedBy { it.name.lowercase() }
                if (genres.isNotEmpty()) {
                    adapter.submitList(genres)
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

data class GenreInfo(
    val name: String,
    val songCount: Int,
    val songs: List<com.stash.opusplayer.data.Song>
)
