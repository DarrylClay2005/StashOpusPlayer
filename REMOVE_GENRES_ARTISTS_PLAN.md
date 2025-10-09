# 🗑️ Remove Genres & Artists Features - Implementation Plan

## Phase 1: Identify Files to Remove

### UI Components
```bash
# Fragments
rm app/src/main/java/com/stash/opusplayer/ui/fragments/ArtistsFragment.kt
rm app/src/main/java/com/stash/opusplayer/ui/fragments/GenresFragment.kt
rm app/src/main/java/com/stash/opusplayer/ui/fragments/ArtistSongsFragment.kt

# Adapters
rm app/src/main/java/com/stash/opusplayer/ui/adapters/ArtistAdapter.kt
rm app/src/main/java/com/stash/opusplayer/ui/adapters/GenreAdapter.kt

# Layout files
rm app/src/main/res/layout/fragment_artists.xml
rm app/src/main/res/layout/fragment_genres.xml
rm app/src/main/res/layout/fragment_artist_songs.xml
rm app/src/main/res/layout/item_artist.xml
rm app/src/main/res/layout/item_genre.xml

# Artwork fetcher
rm app/src/main/java/com/stash/opusplayer/artwork/ArtistGenreArtworkFetcher.kt
```

### Database & Data Layer
```kotlin
// Files likely to exist (need to check):
// - app/src/main/java/com/stash/opusplayer/data/entities/Artist.kt
// - app/src/main/java/com/stash/opusplayer/data/entities/Genre.kt  
// - app/src/main/java/com/stash/opusplayer/data/dao/ArtistDao.kt
// - app/src/main/java/com/stash/opusplayer/data/dao/GenreDao.kt
```

## Phase 2: Database Migration Script

```kotlin
// Create migration to remove artist and genre tables
@Entity
data class DatabaseMigration {
    companion object {
        val MIGRATION_REMOVE_ARTISTS_GENRES = object : Migration(currentVersion, currentVersion + 1) {
            override fun migrate(database: SupportSQLiteDatabase) {
                // Remove foreign key constraints first
                database.execSQL("CREATE TABLE songs_new AS SELECT id, title, duration, file_path, album_art_path, date_added, play_count, last_played FROM songs")
                database.execSQL("DROP TABLE songs")
                database.execSQL("ALTER TABLE songs_new RENAME TO songs")
                
                // Drop artist and genre related tables
                database.execSQL("DROP TABLE IF EXISTS artists")
                database.execSQL("DROP TABLE IF EXISTS genres")
                database.execSQL("DROP TABLE IF EXISTS song_artists")
                database.execSQL("DROP TABLE IF EXISTS song_genres")
                database.execSQL("DROP TABLE IF EXISTS album_artists")
            }
        }
    }
}
```

## Phase 3: Navigation Updates

### MainActivity Navigation
```kotlin
// Remove from bottom navigation or drawer menu
// Update navigation graph to remove artist/genre destinations
// Remove menu items from navigation drawer
```

### Menu Resource Updates
```xml
<!-- Remove from navigation menu -->
<!-- app/src/main/res/menu/bottom_navigation.xml -->
<!-- app/src/main/res/menu/navigation_drawer.xml -->
```

## Phase 4: Repository Updates

```kotlin
// Update MusicRepository.kt to remove:
// - artist-related methods
// - genre-related methods
// - artist/genre artwork fetching
// - artist/genre database operations
```

## Phase 5: Replacement Features Implementation

### Enhanced Song Management
```kotlin
// Add to Song entity:
data class Song(
    // ... existing fields
    val customTags: List<String> = emptyList(), // User-defined tags
    val mood: String? = null, // Mood-based classification
    val energy: Int = 0, // Energy level 0-100
    val isFavorite: Boolean = false,
    val rating: Int = 0 // 1-5 star rating
)
```

### Smart Playlists
```kotlin
class SmartPlaylistManager {
    fun createRecentlyPlayedPlaylist(): List<Song>
    fun createMostPlayedPlaylist(): List<Song>
    fun createRecentlyAddedPlaylist(): List<Song>
    fun createFavoritesPlaylist(): List<Song>
    fun createMoodBasedPlaylist(mood: String): List<Song>
    fun createEnergyBasedPlaylist(minEnergy: Int, maxEnergy: Int): List<Song>
}
```

### Advanced Search & Filtering
```kotlin
class AdvancedSongFilter {
    fun filterByTitle(query: String): List<Song>
    fun filterByDuration(minDuration: Long, maxDuration: Long): List<Song>
    fun filterByDateAdded(since: Date): List<Song>
    fun filterByPlayCount(minCount: Int): List<Song>
    fun filterByCustomTags(tags: List<String>): List<Song>
    fun filterByMood(mood: String): List<Song>
    fun filterByRating(minRating: Int): List<Song>
}
```

## Phase 6: UI Replacements

### New Song-Focused Fragments
```kotlin
// SongLibraryFragment - Enhanced song list with advanced filtering
// SmartPlaylistsFragment - Auto-generated playlists
// RecentlyPlayedFragment - Recently played songs
// FavoritesFragment - Favorite songs with ratings
// MoodPlaylistsFragment - Mood-based song organization
```

### Enhanced Song List Features
```kotlin
// Add to song list items:
// - Star rating system
// - Custom tags display
// - Mood indicators
// - Play count badges
// - Recently played indicators
// - Advanced sorting options
```

## Phase 7: Settings Integration Updates

### Remove Genre/Artist Settings
```kotlin
// Remove from SettingsFragment:
// - Artist artwork settings
// - Genre-based organization options
// - Artist/genre sync settings
```

### Add New Song-Focused Settings
```kotlin
// Add to settings:
// - Auto-tagging options
// - Mood detection settings
// - Smart playlist preferences
// - Rating system configuration
// - Recently played history length
```

## Phase 8: Testing & Validation

### Database Migration Testing
```bash
# Test migration on different database versions
# Verify no foreign key constraint violations
# Ensure song data integrity after migration
```

### UI Testing
```bash
# Verify no broken navigation links
# Test all song list functionality
# Verify search and filtering works
# Test new smart playlist features
```

### Performance Testing
```bash
# Measure app startup time improvement
# Test memory usage reduction
# Verify smooth scrolling in song lists
# Test search performance
```

## Expected Benefits

### Performance Improvements
- ⚡ **Faster app startup** (fewer fragments to initialize)
- 🧠 **Reduced memory usage** (simpler database schema)
- 📱 **Smoother UI** (fewer complex queries)
- 🔍 **Better search performance** (focused on songs only)

### User Experience Improvements  
- 🎯 **Simplified interface** (no genre/artist clutter)
- ⭐ **Better song management** (ratings, tags, favorites)
- 🎵 **Smart playlists** (auto-generated based on listening habits)
- 🔍 **Enhanced discovery** (mood-based, energy-based filtering)

### Code Quality Improvements
- 🧹 **Cleaner codebase** (removed ~15+ files)
- 📊 **Simpler database** (fewer tables and relationships)
- 🛠️ **Easier maintenance** (focused feature set)
- 🐛 **Fewer bugs** (less complexity)

## Implementation Commands

```bash
# Execute the file removal
./remove_genres_artists_files.sh

# Update database version
# Implement migration logic
# Update navigation
# Test thoroughly
# Create new release
```

This plan transforms StashOpusPlayer into a more focused, song-centric music player while removing unnecessary complexity and improving performance.