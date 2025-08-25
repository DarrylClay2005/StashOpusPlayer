package com.stash.opusplayer.ui

import android.Manifest
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.ActionBarDrawerToggle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.GravityCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.preference.PreferenceManager
import androidx.appcompat.app.AlertDialog
import kotlinx.coroutines.launch
import com.bumptech.glide.Glide
import com.stash.opusplayer.BuildConfig
import com.google.android.material.navigation.NavigationView
import com.karumi.dexter.Dexter
import com.karumi.dexter.MultiplePermissionsReport
import com.karumi.dexter.PermissionToken
import com.karumi.dexter.listener.PermissionRequest
import com.karumi.dexter.listener.multi.MultiplePermissionsListener
import com.stash.opusplayer.R
import com.stash.opusplayer.databinding.ActivityMainBinding
import com.stash.opusplayer.ui.fragments.MusicLibraryFragment
import com.stash.opusplayer.ui.fragments.EqualizerFragment
import com.stash.opusplayer.ui.fragments.SettingsFragment
import com.stash.opusplayer.ui.fragments.PlaylistsFragment
import com.stash.opusplayer.utils.PermissionUtils
import com.stash.opusplayer.updates.UpdateManager
import com.stash.opusplayer.player.MusicPlayerManager
import com.stash.opusplayer.data.Song

class MainActivity : AppCompatActivity(), NavigationView.OnNavigationItemSelectedListener {
    
    private lateinit var binding: ActivityMainBinding
    private lateinit var toggle: ActionBarDrawerToggle
    private lateinit var sharedPreferences: SharedPreferences
    private lateinit var updateManager: UpdateManager
    private lateinit var musicPlayerManager: MusicPlayerManager
    private lateinit var miniPlayerView: MiniPlayerView
    
    private val imagePickerLauncher = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri ->
        uri?.let { setBackgroundImage(it) }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        
        sharedPreferences = PreferenceManager.getDefaultSharedPreferences(this)
        updateManager = UpdateManager(this)
        
        setupMusicPlayer()
        setupMiniPlayer()
        setupToolbar()
        setupNavigationDrawer()
        setupBackgroundImage()
        
        setupBottomNavigation()
        checkPermissionsAndSetup()
        
        // Check for updates on app start (AI will decide if/when to show)
        updateManager.checkForUpdates(this)
        
        // Defer loading content until permissions are granted
        if (savedInstanceState != null) {
            // If recreating, assume content already loaded
        }
        
        // Handle back button press
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (binding.drawerLayout.isDrawerOpen(GravityCompat.START)) {
                    binding.drawerLayout.closeDrawer(GravityCompat.START)
                } else {
                    finish()
                }
            }
        })
    }
    
    private fun setupToolbar() {
        setSupportActionBar(binding.toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = getString(R.string.app_name)
    }
    
    private fun setupBottomNavigation() {
        binding.bottomNav.setOnItemSelectedListener { item ->
            when (item.itemId) {
                R.id.nav_songs -> {
                    loadFragment(MusicLibraryFragment())
                    supportActionBar?.title = getString(R.string.menu_music_library)
                    true
                }
                R.id.nav_artists -> {
                    loadFragment(com.stash.opusplayer.ui.fragments.ArtistsFragment())
                    supportActionBar?.title = getString(R.string.menu_artists)
                    true
                }
                R.id.nav_genres -> {
                    loadFragment(com.stash.opusplayer.ui.fragments.GenresFragment())
                    supportActionBar?.title = getString(R.string.menu_genres)
                    true
                }
                R.id.nav_folders -> {
                    loadFragment(com.stash.opusplayer.ui.fragments.FoldersFragment())
                    supportActionBar?.title = getString(R.string.menu_folders)
                    true
                }
                R.id.nav_settings -> {
                    loadFragment(SettingsFragment())
                    supportActionBar?.title = getString(R.string.menu_settings)
                    true
                }
                else -> false
            }
        }
    }
    
    private fun setupNavigationDrawer() {
        toggle = ActionBarDrawerToggle(
            this, binding.drawerLayout, binding.toolbar,
            R.string.nav_open, R.string.nav_close
        )
        binding.drawerLayout.addDrawerListener(toggle)
        toggle.syncState()
        
        binding.navView.setNavigationItemSelectedListener(this)
    }
    
    private fun setupBackgroundImage() {
        val backgroundUri = sharedPreferences.getString("background_image_uri", null)
        backgroundUri?.let { uri ->
            binding.backgroundImage.visibility = android.view.View.VISIBLE
            Glide.with(this)
                .load(Uri.parse(uri))
                .into(binding.backgroundImage)
        }
    }
    
    private fun setBackgroundImage(uri: Uri) {
        try {
            // Take persistent permission
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            
            // Save URI to preferences
            sharedPreferences.edit()
                .putString("background_image_uri", uri.toString())
                .apply()
            
            // Display image
            binding.backgroundImage.visibility = android.view.View.VISIBLE
            Glide.with(this)
                .load(uri)
                .into(binding.backgroundImage)
                
        } catch (e: Exception) {
            Toast.makeText(this, "Failed to set background image", Toast.LENGTH_SHORT).show()
        }
    }
    
    fun pickBackgroundImage() {
        imagePickerLauncher.launch("image/*")
    }
    
    private fun checkPermissionsAndSetup() {
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            listOf(Manifest.permission.READ_MEDIA_AUDIO)
        } else {
            listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        
        Dexter.withContext(this)
            .withPermissions(permissions)
            .withListener(object : MultiplePermissionsListener {
                override fun onPermissionsChecked(report: MultiplePermissionsReport) {
                    if (report.areAllPermissionsGranted()) {
                        // Permissions granted, proceed to load default content
                        loadDefaultContentIfNeeded()
                    } else {
                        Toast.makeText(
                            this@MainActivity,
                            "Audio permission is required to show your music library.",
                            Toast.LENGTH_LONG
                        ).show()
                        // Load a safe screen (Settings) so app doesn't crash
                        loadFragment(SettingsFragment())
                        supportActionBar?.title = getString(R.string.menu_settings)
                        binding.bottomNav.selectedItemId = R.id.nav_settings
                    }
                }
                
                override fun onPermissionRationaleShouldBeShown(
                    permissions: List<PermissionRequest>,
                    token: PermissionToken
                ) {
                    token.continuePermissionRequest()
                }
            })
            .check()
    }

    private fun loadDefaultContentIfNeeded() {
        // Only load if nothing is displayed yet
        if (supportFragmentManager.findFragmentById(R.id.main_content) == null) {
            loadFragment(MusicLibraryFragment())
            supportActionBar?.title = getString(R.string.menu_music_library)
            binding.bottomNav.selectedItemId = R.id.nav_songs
            binding.navView.setCheckedItem(R.id.nav_music_library)
        }
    }
    
    override fun onNavigationItemSelected(item: android.view.MenuItem): Boolean {
        when (item.itemId) {
            R.id.nav_music_library -> {
                loadFragment(MusicLibraryFragment())
                supportActionBar?.title = getString(R.string.menu_music_library)
            }
            R.id.nav_playlists -> {
                loadFragment(PlaylistsFragment())
                supportActionBar?.title = getString(R.string.menu_playlists)
            }
            R.id.nav_equalizer -> {
                loadFragment(EqualizerFragment())
                supportActionBar?.title = getString(R.string.menu_equalizer)
            }
            R.id.nav_settings -> {
                loadFragment(SettingsFragment())
                supportActionBar?.title = getString(R.string.menu_settings)
            }
            R.id.nav_about -> {
                showAboutDialog()
            }
        }
        
        binding.drawerLayout.closeDrawer(GravityCompat.START)
        return true
    }
    
    private fun loadFragment(fragment: Fragment) {
        supportFragmentManager.beginTransaction()
            .replace(R.id.main_content, fragment)
            .commit()
    }
    
    private fun showAboutDialog() {
        AlertDialog.Builder(this)
            .setTitle("About Stash Opus Player")
            .setMessage("""Stash Opus Player v${BuildConfig.VERSION_NAME}
                
A modern music player with AI-powered features.
                
Features:
• Multi-format audio support
• Custom background images
• AI-powered update notifications
• Material Design 3 UI
• Intelligent user experience
                
© 2025 Stash Opus Player
                
Check for updates anytime from Settings.""")
            .setPositiveButton("Check for Updates") { _, _ ->
                updateManager.checkForUpdates(this, forceCheck = true)
            }
            .setNegativeButton("Close", null)
            .show()
    }
    
    fun getUpdateManager() = updateManager
    
    private fun setupMusicPlayer() {
        musicPlayerManager = MusicPlayerManager(this).apply {
            initialize()
        }
    }
    
    private fun setupMiniPlayer() {
        miniPlayerView = binding.miniPlayer
        miniPlayerView.initialize(this, musicPlayerManager)
    }
    
    // Music player functionality
    fun playMusic(song: Song) {
        lifecycleScope.launch {
            try {
                musicPlayerManager.playSong(song)
                // Open Now Playing activity
                val intent = Intent(this@MainActivity, NowPlayingActivity::class.java).apply {
                    putExtra("song", song)
                }
                startActivity(intent)
            } catch (e: Exception) {
                Toast.makeText(this@MainActivity, "Error playing song: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }
    
    fun addToPlaylist(song: com.stash.opusplayer.data.Song) {
        // TODO: Implement playlist functionality
        Toast.makeText(this, "Added to playlist: ${song.displayName}", Toast.LENGTH_SHORT).show()
    }
    
    fun toggleFavorite(song: com.stash.opusplayer.data.Song) {
        // TODO: Implement favorite toggle
        lifecycleScope.launch {
            val repository = com.stash.opusplayer.data.MusicRepository(this@MainActivity)
            if (song.isFavorite) {
                repository.removeFromFavorites(song.id)
                Toast.makeText(this@MainActivity, "Removed from favorites", Toast.LENGTH_SHORT).show()
            } else {
                repository.addToFavorites(song)
                Toast.makeText(this@MainActivity, "Added to favorites", Toast.LENGTH_SHORT).show()
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        if (::miniPlayerView.isInitialized) {
            miniPlayerView.release()
        }
        if (::musicPlayerManager.isInitialized) {
            musicPlayerManager.release()
        }
    }
    
}
