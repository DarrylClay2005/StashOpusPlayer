# Enhanced YouTube Extraction Setup Guide

This guide explains how to set up and use the enhanced YouTube extraction system that combines YouTube Data API v3 with yt-dlp and FFmpeg for optimal audio downloading.

## 🌟 New Features

Your StashOpusPlayer now includes:

✅ **Custom Extraction Service**: Hybrid approach using YouTube API + yt-dlp  
✅ **Enhanced Metadata**: Rich video information from official YouTube API  
✅ **Improved Reliability**: Fallback mechanisms and error handling  
✅ **Format Selection**: Real-time format availability and quality options  
✅ **Standalone Service**: Optional Python service for advanced extraction  

## 🏗️ Architecture

The new system uses a **hybrid approach**:

1. **YouTube Data API v3** - Fast, reliable metadata and search
2. **yt-dlp** - Robust audio stream extraction and downloading  
3. **FFmpeg** - High-quality format conversion and processing
4. **Custom Service** - Combines all three for optimal results

## 📱 Android App Changes

### Modified Files:
- `YouTubeApiService.kt` - Updated API key
- `VideoDownloadManager.kt` - Integrated custom extraction service
- `CustomYouTubeExtractionService.kt` - New hybrid extraction service

### New Features:
- Enhanced format selection with real-time availability
- Improved progress tracking during downloads
- Automatic fallback to legacy methods if needed
- Better error handling and recovery
- Rich metadata extraction from YouTube API

## 🐍 Python Service Setup (Optional but Recommended)

The standalone Python service provides additional reliability and can be deployed separately.

### Prerequisites:
```bash
# Install Python 3.8+
sudo pacman -S python python-pip

# Install FFmpeg (required for audio processing)
sudo pacman -S ffmpeg

# Install system dependencies
sudo pacman -S python-virtualenv
```

### Installation:
```bash
# Navigate to the project directory
cd StashOpusPlayer

# Create Python virtual environment
python -m venv venv
source venv/bin/activate  # On Linux/Mac
# or
venv\\Scripts\\activate  # On Windows

# Install requirements
pip install -r requirements.txt

# Make the service executable
chmod +x yt_dlp_service.py
```

### Configuration:
1. Update `ExtractionServiceConfig.kt` if needed:
   ```kotlin
   const val LOCAL_SERVICE_URL = "http://YOUR_IP:8080/quick"
   const val LOCAL_SERVICE_ENABLED = true
   ```

2. Find your local IP address:
   ```bash
   ip addr show | grep inet
   ```

### Starting the Service:
```bash
# Start the Python service
python yt_dlp_service.py

# The service will be available at:
# http://0.0.0.0:8080
```

### Service Endpoints:
- `GET /health` - Check service status
- `GET /info/{video_url}` - Get video information
- `POST /download` - Download audio with custom parameters
- `GET /quick/{video_id}` - Quick download endpoint
- `POST /cleanup` - Clean up old files
- `POST /update` - Update yt-dlp to latest version

## 🎵 Usage Examples

### Basic Download:
The Android app will automatically use the enhanced extraction service. Users will experience:
- Faster search results from YouTube API
- More reliable downloads via yt-dlp
- Better format selection
- Enhanced metadata and thumbnails

### Advanced Usage with Python Service:
```bash
# Test the service
curl http://localhost:8080/health

# Get video information
curl "http://localhost:8080/info/dQw4w9WgXcQ"

# Quick download
curl "http://localhost:8080/quick/dQw4w9WgXcQ?format=mp3&quality=best" -o audio.mp3

# Download with custom parameters
curl -X POST http://localhost:8080/download \
  -H "Content-Type: application/json" \
  -d '{"url": "https://youtube.com/watch?v=dQw4w9WgXcQ", "format": "opus", "quality": "best"}'
```

## 📊 Benefits of the New System

### 🚀 Performance Improvements:
- **Faster searches**: YouTube API provides instant results
- **Reliable downloads**: yt-dlp handles complex extraction scenarios
- **Better format detection**: Real-time format availability
- **Enhanced metadata**: Rich video information including thumbnails

### 🛡️ Reliability Features:
- **Automatic fallbacks**: Falls back to legacy methods if new service fails
- **Error recovery**: Multiple retry mechanisms
- **Anti-detection**: Advanced techniques to avoid YouTube blocks
- **Progress tracking**: Real-time download progress updates

### 🎨 User Experience:
- **Rich metadata**: Channel names, descriptions, thumbnails
- **Format options**: Multiple quality and format choices
- **Progress feedback**: Detailed download status updates
- **Error messages**: Clear, actionable error information

## 🔧 Troubleshooting

### Common Issues:

#### API Key Issues:
- Ensure the API key `AIzaSyBqWTC-S3vopTEMNTgpCalyqc_GJkUgsAg` is valid
- Check API quotas in Google Cloud Console
- Verify YouTube Data API v3 is enabled

#### yt-dlp Issues:
```bash
# Update yt-dlp to latest version
pip install --upgrade yt-dlp

# Or via the service
curl -X POST http://localhost:8080/update
```

#### FFmpeg Issues:
```bash
# Verify FFmpeg installation
ffmpeg -version

# Install if missing
sudo pacman -S ffmpeg  # Arch Linux
```

#### Service Connection Issues:
```bash
# Check if service is running
curl http://localhost:8080/health

# Check firewall settings
sudo ufw allow 8080  # If using UFW

# Check service logs
python yt_dlp_service.py  # Look for error messages
```

### Debug Mode:
Enable debug logging in the Android app to see detailed extraction process:
```kotlin
Log.d(TAG, "Debug info here")
```

## 📈 Monitoring and Maintenance

### Health Checks:
The system includes built-in health checks:
```kotlin
val healthResult = videoDownloadManager.checkServiceHealth()
```

### Updates:
Keep components updated:
```bash
# Update yt-dlp
pip install --upgrade yt-dlp

# Update service dependencies  
pip install --upgrade -r requirements.txt
```

### Cleanup:
The Python service automatically cleans up temporary files, but you can trigger manual cleanup:
```bash
curl -X POST http://localhost:8080/cleanup
```

## 🚀 Deployment Options

### Development Setup:
- Run Python service on localhost
- Use for testing and development

### Production Setup:
- Deploy Python service on dedicated server
- Use reverse proxy (nginx) for security
- Set up monitoring and logging
- Configure automatic updates

### Docker Deployment (Optional):
```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
RUN apt-get update && apt-get install -y ffmpeg

COPY yt_dlp_service.py .
EXPOSE 8080

CMD ["python", "yt_dlp_service.py"]
```

## 📝 API Reference

### Android Methods:
```kotlin
// Get available formats
val formatsResult = videoDownloadManager.getAvailableFormats(videoUrl)

// Check service health  
val healthResult = videoDownloadManager.checkServiceHealth()

// Update yt-dlp
val updateResult = videoDownloadManager.updateYtDlp()
```

### Python Service API:
- Full RESTful API with JSON responses
- CORS enabled for web applications
- Error handling with HTTP status codes
- Progress tracking via webhooks (planned)

## 🤝 Contributing

To contribute to the YouTube extraction system:

1. Fork the repository
2. Make changes to the relevant files
3. Test with both Android app and Python service
4. Submit pull request with detailed description

### Testing:
- Test API key functionality
- Verify yt-dlp integration
- Check error handling and fallbacks
- Test various video formats and qualities

---

**Need Help?** Check the logs in both the Android app and Python service for detailed error information. The system is designed to be robust with multiple fallback mechanisms.
