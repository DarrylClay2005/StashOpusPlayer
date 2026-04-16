package com.stash.opusplayer.ui.fragments.settings

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.stash.opusplayer.R
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.utils.PrefsKeys
import com.stash.opusplayer.work.ArtworkExtractionWorker
import com.stash.opusplayer.work.LibraryRescanWorker
import java.util.concurrent.TimeUnit

class LibrarySettingsFragment : NavigableSettingsFragment() {

    override val screenTitle: String = "Library Settings"

    private var folderSummaryView: TextView? = null

    private val folderPickerLauncher = registerForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        if (uri == null) {
            return@registerForActivityResult
        }

        runCatching {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            requireContext().contentResolver.takePersistableUriPermission(uri, flags)
            MusicRepository(requireContext()).addCustomMusicFolderTreeUri(uri.toString())
            updateFolderSummary()
            Toast.makeText(
                requireContext(),
                "Folder added. Pull to refresh the library after a rescan.",
                Toast.LENGTH_SHORT
            ).show()
        }.onFailure {
            Toast.makeText(requireContext(), "Unable to add that folder.", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val (scrollView, content) = createSettingsPage(
            title = "Library",
            subtitle = "Clean up source folders, view defaults, scans, and artwork repair in one place."
        )

        buildLayoutDefaults(content)
        buildFolderSection(content)
        buildScanningSection(content)

        return scrollView
    }

    override fun onResume() {
        super.onResume()
        updateFolderSummary()
    }

    private fun buildLayoutDefaults(parent: LinearLayout) {
        val settings = settingsPrefs()
        val section = addSettingsSection(
            parent,
            "Layout Defaults",
            "These choices become the starting layout for the library, folders screen, and folder detail view."
        )

        val entries = listOf(
            getString(R.string.layout_list),
            getString(R.string.layout_two_columns),
            getString(R.string.layout_three_columns)
        )

        fun positionForColumns(columns: Int): Int = when (columns.coerceIn(1, 3)) {
            1 -> 0
            2 -> 1
            else -> 2
        }

        fun columnsForPosition(position: Int): Int = when (position) {
            0 -> 1
            1 -> 2
            else -> 3
        }

        val songsSpinner = addSpinnerControl(
            section,
            title = "Songs view",
            summary = "Default layout when you open the full library.",
            entries = entries
        )
        var songsHydrated = false
        songsSpinner.setSelection(positionForColumns(settings.getInt(PrefsKeys.DEFAULT_SONGS_VIEW_COLUMNS, 1)))
        songsSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!songsHydrated) {
                    songsHydrated = true
                    return
                }
                settings.edit().putInt(PrefsKeys.DEFAULT_SONGS_VIEW_COLUMNS, columnsForPosition(position)).apply()
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        val foldersSpinner = addSpinnerControl(
            section,
            title = "Folders view",
            summary = "Default layout in the top-level folders browser.",
            entries = entries
        )
        var foldersHydrated = false
        foldersSpinner.setSelection(positionForColumns(settings.getInt(PrefsKeys.DEFAULT_FOLDERS_VIEW_COLUMNS, 1)))
        foldersSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!foldersHydrated) {
                    foldersHydrated = true
                    return
                }
                settings.edit().putInt(PrefsKeys.DEFAULT_FOLDERS_VIEW_COLUMNS, columnsForPosition(position)).apply()
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        val folderDetailSpinner = addSpinnerControl(
            section,
            title = "Folder detail view",
            summary = "Default layout after opening a specific folder.",
            entries = entries
        )
        var detailHydrated = false
        folderDetailSpinner.setSelection(positionForColumns(settings.getInt(PrefsKeys.DEFAULT_FOLDER_DETAIL_VIEW_COLUMNS, 1)))
        folderDetailSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!detailHydrated) {
                    detailHydrated = true
                    return
                }
                settings.edit().putInt(PrefsKeys.DEFAULT_FOLDER_DETAIL_VIEW_COLUMNS, columnsForPosition(position)).apply()
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }
    }

    private fun buildFolderSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Music Sources",
            "Manage the SAF folders that feed the library scan without dropping into the old dialog maze."
        )

        folderSummaryView = TextView(requireContext()).apply {
            textSize = 12f
            setTextColor(androidx.core.content.ContextCompat.getColor(requireContext(), R.color.text_secondary))
        }
        section.addView(folderSummaryView)
        updateFolderSummary()

        addActionButton(section, "Add music folder") {
            folderPickerLauncher.launch(null)
        }

        addActionButton(section, "Manage added folders", outlined = true) {
            showManageFoldersDialog()
        }
    }

    private fun buildScanningSection(parent: LinearLayout) {
        val settings = settingsPrefs()
        val section = addSettingsSection(
            parent,
            "Scanning & Artwork",
            "Repair the library when files move, artwork goes stale, or background work needs tuning."
        )

        addSwitchControl(
            section,
            title = "Fetch artwork online",
            summary = "Look online when embedded or cached art is missing.",
            checked = settings.getBoolean("fetch_artwork_online", true)
        ) { enabled ->
            settings.edit().putBoolean("fetch_artwork_online", enabled).apply()
        }

        addSwitchControl(
            section,
            title = "Background rescans",
            summary = "Allow library refresh work to keep metadata current in the background.",
            checked = settings.getBoolean("enable_background_rescans", true)
        ) { enabled ->
            settings.edit().putBoolean("enable_background_rescans", enabled).apply()
            Toast.makeText(
                requireContext(),
                if (enabled) "Background rescans enabled." else "Background rescans disabled.",
                Toast.LENGTH_SHORT
            ).show()
        }

        addSwitchControl(
            section,
            title = "Daily automatic rescan",
            summary = "Schedule a periodic library sweep every 24 hours.",
            checked = settings.getBoolean("enable_periodic_rescan", false)
        ) { enabled ->
            settings.edit().putBoolean("enable_periodic_rescan", enabled).apply()
            val workManager = WorkManager.getInstance(requireContext())
            val tag = "library_rescan_periodic"
            if (enabled) {
                val request = PeriodicWorkRequestBuilder<LibraryRescanWorker>(24, TimeUnit.HOURS)
                    .addTag(tag)
                    .build()
                workManager.enqueueUniquePeriodicWork(tag, ExistingPeriodicWorkPolicy.UPDATE, request)
            } else {
                workManager.cancelAllWorkByTag(tag)
            }
        }

        addActionButton(section, "Rescan library now") {
            runCatching {
                WorkManager.getInstance(requireContext())
                    .enqueue(OneTimeWorkRequestBuilder<LibraryRescanWorker>().build())
                Toast.makeText(
                    requireContext(),
                    "Library rescan started.",
                    Toast.LENGTH_SHORT
                ).show()
            }.onFailure {
                Toast.makeText(requireContext(), "Unable to start a library rescan.", Toast.LENGTH_SHORT).show()
            }
        }

        addActionButton(section, "Re-extract artwork", outlined = true) {
            runCatching {
                WorkManager.getInstance(requireContext())
                    .enqueue(OneTimeWorkRequestBuilder<ArtworkExtractionWorker>().build())
                Toast.makeText(
                    requireContext(),
                    "Artwork extraction started.",
                    Toast.LENGTH_SHORT
                ).show()
            }.onFailure {
                Toast.makeText(requireContext(), "Unable to start artwork extraction.", Toast.LENGTH_SHORT).show()
            }
        }

        addActionButton(section, "Clear artwork cache", outlined = true) {
            clearArtworkCache()
        }
    }

    private fun updateFolderSummary() {
        val repo = MusicRepository(requireContext())
        val folders = repo.getCustomMusicFolderTreeUris()
            .sortedBy { uri ->
                runCatching { android.net.Uri.parse(uri).lastPathSegment ?: uri }.getOrDefault(uri)
            }
        folderSummaryView?.text = if (folders.isEmpty()) {
            "No additional SAF folders added yet."
        } else {
            buildString {
                append("Added folders: ")
                append(folders.size)
                append("\n")
                append(
                    folders.joinToString("\n") { uri ->
                        runCatching { android.net.Uri.parse(uri).lastPathSegment ?: uri }.getOrDefault(uri)
                    }
                )
            }
        }
    }

    private fun showManageFoldersDialog() {
        val repo = MusicRepository(requireContext())
        val folders = repo.getCustomMusicFolderTreeUris().toList()
        if (folders.isEmpty()) {
            Toast.makeText(requireContext(), "No folders to manage.", Toast.LENGTH_SHORT).show()
            return
        }

        val labels = folders.map { uri ->
            runCatching { android.net.Uri.parse(uri).lastPathSegment ?: uri }.getOrDefault(uri)
        }.toTypedArray()

        AlertDialog.Builder(requireContext())
            .setTitle("Remove folder")
            .setItems(labels) { _, which ->
                val target = folders[which]
                repo.removeCustomMusicFolderTreeUri(target)
                runCatching {
                    requireContext().contentResolver.releasePersistableUriPermission(
                        android.net.Uri.parse(target),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                }
                updateFolderSummary()
                Toast.makeText(requireContext(), "Folder removed.", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("Close", null)
            .show()
    }

    private fun clearArtworkCache() {
        AlertDialog.Builder(requireContext())
            .setTitle("Clear artwork cache")
            .setMessage("Cached artwork will be removed and rebuilt as songs are scanned again.")
            .setPositiveButton("Clear") { _, _ ->
                val removedCount = runCatching {
                    var deleted = 0
                    listOf(
                        java.io.File(requireContext().cacheDir, "artwork"),
                        java.io.File(requireContext().cacheDir, "artwork_cache")
                    ).forEach { directory ->
                        directory.listFiles()?.forEach { file ->
                            if (file.delete()) {
                                deleted += 1
                            }
                        }
                    }
                    deleted
                }.getOrElse { -1 }

                if (removedCount >= 0) {
                    Toast.makeText(
                        requireContext(),
                        "Artwork cache cleared ($removedCount files).",
                        Toast.LENGTH_LONG
                    ).show()
                } else {
                    Toast.makeText(requireContext(), "Could not clear the full artwork cache.", Toast.LENGTH_LONG).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
}
