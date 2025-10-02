# YouTube Data API v3 Setup Guide

This guide will walk you through obtaining your own YouTube Data API v3 key from Google Developer Console and configuring it in StashWave Player for enhanced YouTube functionality.

## 🎯 Why You Need Your Own API Key

StashWave Player offers two approaches for YouTube integration:

1. **🔒 Secure (Recommended)**: Use your own API key for full YouTube Data API features
2. **📱 Simple**: Use Seal integration for downloads without API setup

With your own API key, you get:
- ✅ **YouTube search** within the app
- ✅ **Video metadata** (titles, descriptions, thumbnails)
- ✅ **Channel information** and view counts
- ✅ **Related videos** and suggestions
- ✅ **Comment loading** (if enabled)
- ✅ **Playlist information**

## 📋 Prerequisites

- Google account
- Internet connection
- 10-15 minutes for setup

## 🚀 Step 1: Create Google Cloud Project

### 1.1 Access Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Sign in with your Google account
3. Accept terms of service if prompted

### 1.2 Create New Project

1. Click the project dropdown (top-left, next to "Google Cloud")
2. Click **"New Project"**
3. Fill in project details:
   - **Project name**: `StashWave-YouTube-API` (or your preferred name)
   - **Organization**: Leave default (usually "No organization")
   - **Location**: Leave default
4. Click **"Create"**
5. Wait for project creation (30-60 seconds)

### 1.3 Select Your Project

1. Click the project dropdown again
2. Select your newly created project (`StashWave-YouTube-API`)

## 🎵 Step 2: Enable YouTube Data API v3

### 2.1 Navigate to API Library

1. In the left sidebar, click **"APIs & Services"**
2. Click **"Library"**

### 2.2 Find and Enable YouTube Data API

1. In the search bar, type: `YouTube Data API v3`
2. Click on **"YouTube Data API v3"** from results
3. Click **"Enable"** button
4. Wait for API to be enabled (10-30 seconds)

## 🔑 Step 3: Create API Key

### 3.1 Navigate to Credentials

1. In the left sidebar, click **"APIs & Services"** → **"Credentials"**
2. Click **"+ Create Credentials"** at the top
3. Select **"API key"** from dropdown

### 3.2 Copy Your API Key

1. A dialog will appear with your API key
2. **Important**: Copy and save this key immediately!
   ```
   Example: AIzaSyBqWTC-S3vopTEMNTgpCalyqc_GJkUgsAg
   ```
3. Click **"Restrict Key"** (recommended for security)

### 3.3 Configure API Key Restrictions (Recommended)

#### Application Restrictions:
1. Select **"Android apps"**
2. Click **"+ Add"**
3. Add these package names:
   - `com.stash.stashwave` (main app)
   - `com.stash.opusplayer` (legacy compatibility)
4. For **SHA-1 certificate fingerprint**:
   ```bash
   # Debug fingerprint (for development)
   SHA1: A0:A1:A2:A3:A4:A5:A6:A7:A8:A9:B0:B1:B2:B3:B4:B5:B6:B7:B8:B9
   
   # Get your debug fingerprint:
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```

#### API Restrictions:
1. Select **"Restrict key"**
2. Choose **"YouTube Data API v3"**
3. Click **"Save"**

## 📱 Step 4: Configure API Key in StashWave Player

### Method 1: Local Properties File (Recommended)

1. Navigate to your StashWave Player project directory:
   ```bash
   cd StashOpusPlayer
   ```

2. Create or edit `local.properties` file:
   ```bash
   nano local.properties
   ```

3. Add your API key:
   ```properties
   sdk.dir=/path/to/your/Android/Sdk
   YOUTUBE_API_KEY=YOUR_API_KEY_HERE
   ```
   Replace `YOUR_API_KEY_HERE` with your actual API key.

4. Save the file (Ctrl+X, then Y, then Enter in nano)

### Method 2: Environment Variable

1. Add to your shell profile (~/.bashrc, ~/.zshrc, etc.):
   ```bash
   echo 'export YOUTUBE_API_KEY="YOUR_API_KEY_HERE"' >> ~/.bashrc
   source ~/.bashrc
   ```

2. The app will automatically pick up the environment variable during build.

### Method 3: Build Configuration

1. Edit `app/build.gradle`:
   ```gradle
   android {
       buildTypes {
           debug {
               buildConfigField "String", "YOUTUBE_API_KEY", "\"YOUR_API_KEY_HERE\""
           }
           release {
               buildConfigField "String", "YOUTUBE_API_KEY", "\"YOUR_API_KEY_HERE\""
           }
       }
   }
   ```

**⚠️ Warning**: Never commit API keys directly in gradle files!

## 🔧 Step 5: Build and Test

### 5.1 Clean and Rebuild

```bash
./gradlew clean
./gradlew build
```

### 5.2 Install and Test

1. Install the app on your device
2. Open StashWave Player
3. Navigate to the **YouTube** tab
4. Try searching for a song/video
5. If you see results, your API key is working! 🎉

## 📊 Step 6: Monitor API Usage

### 6.1 Check Quota Usage

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project
3. Navigate to **"APIs & Services"** → **"Quotas"**
4. Find **"YouTube Data API v3"**
5. Monitor your daily quota usage

### 6.2 Understanding Quotas

- **Free tier**: 10,000 units per day
- **Search**: ~100 units per request
- **Video details**: ~1-4 units per video
- **Daily usage**: Resets at midnight PST

### 6.3 Increase Quotas (If Needed)

1. Click **"Edit Quotas"** in the quotas section
2. Request quota increase
3. Provide justification for increased usage
4. Wait for Google approval (usually 1-3 business days)

## 🛡️ Security Best Practices

### ✅ Do's:
- **Use local.properties** for API keys (never committed)
- **Restrict your API key** to Android apps only
- **Monitor usage** regularly in Google Console
- **Rotate keys periodically** (every 6-12 months)
- **Use different keys** for debug and release builds

### ❌ Don'ts:
- **Never commit API keys** to version control
- **Don't share API keys** publicly or with others
- **Don't use unrestricted keys** in production
- **Don't hardcode keys** in source files
- **Don't ignore quota limits** (can result in suspension)

## 🔍 Troubleshooting

### Common Issues:

#### "API key not valid" Error
1. **Check restrictions**: Ensure package name and SHA-1 are correct
2. **Verify API enabled**: YouTube Data API v3 must be enabled
3. **Wait for propagation**: Changes can take 5-10 minutes

#### "Quota exceeded" Error
1. **Check usage**: Go to Google Console → Quotas
2. **Optimize requests**: Cache results when possible
3. **Request increase**: If legitimately needed

#### "Package name not allowed" Error
1. **Verify SHA-1**: Use correct debug/release fingerprint
2. **Check package name**: Must match exactly
3. **Update restrictions**: Add all needed package names

### Debug Commands:

```bash
# Check current API key in local.properties
grep YOUTUBE_API_KEY local.properties

# Get debug keystore fingerprint
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android

# Test API key directly
curl "https://www.googleapis.com/youtube/v3/search?part=snippet&q=test&key=YOUR_API_KEY"
```

## 🚀 Advanced Configuration

### Custom API Endpoint

You can modify the API endpoint in the app by editing `YouTubeApiService.kt`:

```kotlin
companion object {
    private const val BASE_URL = "https://www.googleapis.com/youtube/v3/"
    private const val API_KEY = BuildConfig.YOUTUBE_API_KEY
}
```

### Caching Strategies

StashWave Player implements intelligent caching:

- **Search results**: Cached for 30 minutes
- **Video metadata**: Cached for 24 hours  
- **Thumbnails**: Cached indefinitely
- **API responses**: Automatic retry with exponential backoff

### Rate Limiting

The app automatically handles rate limiting:

- **Request throttling**: Max 100 requests per second
- **Quota monitoring**: Automatic usage tracking
- **Graceful degradation**: Falls back to Seal integration if quota exceeded

## 📞 Support

### Need Help?

1. **Check logs**: Enable debug mode in app settings
2. **Verify setup**: Follow this guide step-by-step
3. **Test API key**: Use the curl command above
4. **GitHub Issues**: [Report bugs here](https://github.com/DarrylClay2005/StashOpusPlayer/issues)

### Useful Links:

- [YouTube Data API Documentation](https://developers.google.com/youtube/v3)
- [Google Cloud Console](https://console.cloud.google.com/)
- [API Key Best Practices](https://cloud.google.com/docs/authentication/api-keys)
- [Quota Management](https://developers.google.com/youtube/v3/getting-started#quota)

---

**🎵 Enjoy enhanced YouTube search and metadata in StashWave Player!**

*With your own API key, you'll have reliable access to YouTube's vast music library with rich metadata and search capabilities.*