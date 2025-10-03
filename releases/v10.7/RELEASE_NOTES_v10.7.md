# StashOpusPlayer v10.7 - YouTube UX Improvements

## ✨ What's New

### 1) Infinite Scroll for YouTube Search
- Automatically loads more YouTube results when you scroll near the end
- Uses the YouTube Data API nextPageToken for smooth pagination
- No extra taps required — keep scrolling to explore more videos

### 2) User-Provided YouTube API Key in Settings
- New YouTube section in Settings to enter your own API key
- Stored securely on-device (SharedPreferences)
- App prompts to reload so the key is applied everywhere
- Runtime override — no need to modify build files or recompile

## 🔧 Technical Details
- YouTubeSearchFragment: pagination state, scroll listener, and list append
- YouTubeApiService: supports runtime API key override via SharedPreferences; falls back to BuildConfig.YOUTUBE_API_KEY
- Updated call sites to pass Context to the API service
- SettingsFragment: API key input UI with reload prompt

## 🧪 How to Use
1. Go to Settings > YouTube, paste your API key, and tap Save
2. Choose Reload when prompted
3. Open the YouTube tab, search for videos, and scroll — more results will load automatically

Enjoy the smoother YouTube experience! 🎉