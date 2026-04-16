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
import com.stash.opusplayer.ui.appearance.ThemeManager
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
        applyAdaptiveChrome()
        loadGenres()
    }

    private fun setupRecyclerView() {
        adapter = GenreAdapter { genre ->
            // Navigate to show songs in this genre
            val fragment = com.stash.opusplayer.ui.fragments.FolderDetailFragment.newInstance(
                title = "Genre: ${genre.name}", 
                songs = ArrayList(genre.songs)
            )
            parentFragmentManager.beginTransaction()
                .replace(com.stash.opusplayer.R.id.main_content, fragment)
                .addToBackStack(null)
                .commit()
        }
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = this@GenresFragment.adapter
            clipToPadding = false
            setPadding(0, ThemeManager.scaleDp(requireContext(), 4), 0, ThemeManager.scaleDp(requireContext(), 28))
        }
    }

    private fun applyAdaptiveChrome() {
        val context = requireContext()
        val outerPadding = ThemeManager.scaleDp(context, 10)

        binding.root.setPadding(outerPadding, outerPadding, outerPadding, outerPadding)
        binding.titleText.textSize = ThemeManager.scaleSp(context, 16f)
        binding.genresHeaderIcon.layoutParams = binding.genresHeaderIcon.layoutParams.apply {
            width = ThemeManager.scaleDp(context, 24)
            height = ThemeManager.scaleDp(context, 24)
        }
        binding.genresHeader.layoutParams = (binding.genresHeader.layoutParams as? ViewGroup.MarginLayoutParams)?.apply {
            bottomMargin = ThemeManager.scaleDp(context, 10)
        } ?: binding.genresHeader.layoutParams
        binding.emptyStateText.textSize = ThemeManager.scaleSp(context, 14f)
        binding.emptyStateText.setPadding(
            ThemeManager.scaleDp(context, 16),
            ThemeManager.scaleDp(context, 16),
            ThemeManager.scaleDp(context, 16),
            ThemeManager.scaleDp(context, 16)
        )
    }

    private fun loadGenres() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val genresSmart = repository.getSongsByGenreSmart()
                val genres = genresSmart
                    .map { (name, songs) -> GenreInfo(name, songs.size, songs) }
                    .sortedBy { it.name.lowercase() }
                val b = _binding ?: return@launch
                if (genres.isNotEmpty()) {
                    adapter.submitList(genres)
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

data class GenreInfo(
    val name: String,
    val songCount: Int,
    val songs: List<com.stash.opusplayer.data.Song>
)
