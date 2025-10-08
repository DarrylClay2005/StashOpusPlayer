# 🎵 Enhanced Artist & Genre Features

## Overview
The StashOpus Player now features significantly improved artist and genre organization that reads metadata directly from your music files and intelligently organizes your music library.

## 🎤 Artist Features

### **How It Works**
- **Metadata Extraction**: Reads artist information directly from audio file tags (ID3, Vorbis, etc.)
- **Smart Normalization**: Groups similar artist names together (e.g., "Artist Name" and "Artist Name " are grouped)
- **Folder Organization**: Each artist becomes a folder containing all their songs
- **Intelligent Sorting**: Songs within each artist are sorted by album → track number → title

### **Artist Organization**
```
📁 Hip-Hop Artists
   📁 Drake
      📁 Scorpion (Album)
         🎵 Track 1: Song Name
         🎵 Track 2: Another Song
      📁 Views (Album)
         🎵 Track 1: Song Name
   📁 Kendrick Lamar
      📁 DAMN. (Album)
      📁 good kid, m.A.A.d city (Album)
```

### **Enhanced Features**
- **Metadata Priority**: Prioritizes embedded metadata over folder/filename guessing
- **Artist Normalization**: Handles variations like "Artist & Other" → "Artist and Other"
- **Unknown Artist Handling**: Gracefully handles files without artist tags
- **Album Organization**: Within each artist, songs are organized by album

## 🎭 Genre Features  

### **How It Works**
- **Metadata First**: Reads genre tags directly from audio files
- **Smart Inference**: If no genre tag exists, intelligently infers from song/artist/album names
- **Genre Normalization**: Maps variations to standard genre names
- **Caching System**: Remembers inferred genres to improve performance

### **Genre Detection Methods**
1. **Embedded Tags**: Reads GENRE field from audio metadata
2. **Smart Text Analysis**: Analyzes song, artist, and album names for genre clues
3. **Pattern Recognition**: Identifies genre patterns in file/folder names
4. **Caching**: Stores inferred genres for future use

### **Genre Mapping Examples**
```
Input Variations          → Standardized Genre
"hip hop", "hip-hop", "rap" → "Hip-Hop" 
"r&b", "rnb"               → "R&B"
"electronic", "edm"        → "Electronic"
"rock and roll"            → "Rock"
"lo-fi", "lofi"           → "Lo-Fi"
"afrobeat", "afrobeats"   → "Afrobeats"
```

### **Genre Organization**
```
📁 Genres
   📁 Hip-Hop
      🎵 Drake - God's Plan
      🎵 Kendrick Lamar - HUMBLE.
   📁 Rock
      🎵 Queen - Bohemian Rhapsody  
      🎵 The Beatles - Hey Jude
   📁 Electronic
      🎵 Daft Punk - One More Time
      🎵 Calvin Harris - Feel So Close
```

## 🔧 Technical Implementation

### **Metadata Extraction Process**
```kotlin
// 1. Check for existing metadata
if (song.genre.isBlank()) {
    // 2. Extract from file tags
    val extractedSong = metadataExtractor.extractMetadata(song)
    
    // 3. If still no genre, use smart inference
    if (extractedSong.genre.isBlank()) {
        val inferredGenre = inferGenreFromMetadata(song)
        song.copy(genre = inferredGenre)
    }
}
```

### **Smart Genre Inference**
```kotlin
val searchText = "${song.title} ${song.artist} ${song.album}".lowercase()
val inferredGenre = when {
    searchText.containsAny(listOf("hip hop", "rap", "trap")) → "Hip-Hop"
    searchText.containsAny(listOf("rock", "metal", "punk")) → "Rock"  
    searchText.containsAny(listOf("electronic", "edm", "house")) → "Electronic"
    // ... more patterns
}
```

## 📊 Performance Optimizations

### **Caching System**
- **Genre Cache**: Stores inferred genres using SharedPreferences
- **Metadata Cache**: Caches extracted metadata to avoid re-processing
- **Stable Keys**: Uses consistent song identification for reliable caching

### **Smart Processing**
- **Background Processing**: Metadata extraction happens in background threads
- **Progressive Loading**: Shows basic info first, enhances with metadata progressively
- **Memory Efficient**: Processes songs in batches to avoid memory issues

## 🎯 User Benefits

### **For Artists Tab**
- ✅ **Accurate Organization**: Songs grouped by actual artist metadata, not folder names
- ✅ **Complete Discography**: All songs by an artist in one place, regardless of location
- ✅ **Album Structure**: Maintains album organization within each artist
- ✅ **Smart Matching**: Groups variations of artist names together

### **For Genres Tab** 
- ✅ **Automatic Classification**: No manual genre tagging required
- ✅ **Consistent Naming**: Standardized genre names across your library
- ✅ **Discovery**: Find music by mood/style even if not explicitly tagged
- ✅ **Smart Inference**: Works even with files that have no genre tags

## 🚀 Getting Started

1. **Open Artists Tab**: Navigate to Artists from the bottom navigation
2. **Browse by Artist**: Tap any artist to see all their songs organized by album
3. **Explore Genres**: Switch to Genres tab to browse music by style
4. **Automatic Organization**: The app automatically reads metadata and organizes your music

## 🔄 Background Processing

The enhanced system works seamlessly in the background:
- **Library Scan**: Automatically processes metadata when scanning your library
- **Progressive Enhancement**: Starts with basic info, adds metadata as it's processed
- **Smart Caching**: Remembers processed information for faster future access
- **Performance Focused**: Designed to not impact app responsiveness

---

**Your music library is now intelligently organized by actual metadata, giving you a professional music management experience! 🎵✨**