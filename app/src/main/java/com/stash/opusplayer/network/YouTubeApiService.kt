package com.stash.stashwave.network

import android.util.Log
import com.stash.stashwave.data.YouTubeVideo
import com.stash.stashwave.data.YouTubeSearchResult
import com.stash.stashwave.data.AudioFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder

class YouTubeApiService {
    
    companion object {
        private const val API_KEY = "AIzaSyBqWTC-S3vopTEMNTgpCalyqc_GJkUgsAg"
        private const val BASE_URL = "https://www.googleapis.com/youtube/v3"
        private const val TAG = "YouTubeApiService"
    }
    
    private val client = OkHttpClient.Builder()
        .build()
    
    suspend fun searchVideos(
        query: String,
        maxResults: Int = 25,
        pageToken: String? = null
    ): Result<YouTubeSearchResult> = withContext(Dispatchers.IO) {
        try {
            val encodedQuery = URLEncoder.encode(query, "UTF-8")
            val url = buildString {
                append("$BASE_URL/search")
                append("?part=snippet")
                append("&q=$encodedQuery")
                append("&type=video")
                append("&maxResults=$maxResults")
                append("&key=$API_KEY")
                pageToken?.let { append("&pageToken=$it") }
            }
            
            Log.d(TAG, "Searching YouTube for: $query")
            
            val request = Request.Builder()
                .url(url)
                .addHeader("Accept", "application/json")
                .build()
            
            val response = client.newCall(request).execute()
            
            if (!response.isSuccessful) {
                Log.e(TAG, "YouTube API error: ${response.code} - ${response.message}")
                return@withContext Result.failure(
                    IOException("YouTube API error: ${response.code} - ${response.message}")
                )
            }
            
            val responseBody = response.body?.string()
            if (responseBody == null) {
                Log.e(TAG, "Empty response from YouTube API")
                return@withContext Result.failure(IOException("Empty response from YouTube API"))
            }
            
            val result = parseSearchResponse(responseBody)
            Log.d(TAG, "Found ${result.videos.size} videos")
            Result.success(result)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error searching YouTube", e)
            Result.failure(e)
        }
    }
    
    suspend fun getVideoDetails(videoId: String): Result<YouTubeVideo?> = withContext(Dispatchers.IO) {
        try {
            val url = "$BASE_URL/videos?part=snippet,contentDetails,statistics&id=$videoId&key=$API_KEY"
            
            val request = Request.Builder()
                .url(url)
                .addHeader("Accept", "application/json")
                .build()
            
            val response = client.newCall(request).execute()
            
            if (!response.isSuccessful) {
                return@withContext Result.failure(
                    IOException("YouTube API error: ${response.code} - ${response.message}")
                )
            }
            
            val responseBody = response.body?.string() ?: ""
            val video = parseVideoDetailsResponse(responseBody)
            Result.success(video)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error getting video details", e)
            Result.failure(e)
        }
    }
    
    private fun parseSearchResponse(jsonResponse: String): YouTubeSearchResult {
        val json = JSONObject(jsonResponse)
        val items = json.optJSONArray("items") ?: return YouTubeSearchResult(emptyList(), null, 0)
        
        val videos = mutableListOf<YouTubeVideo>()
        
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            val snippet = item.getJSONObject("snippet")
            val videoId = item.getJSONObject("id").getString("videoId")
            
            val thumbnails = snippet.getJSONObject("thumbnails")
            val defaultThumbnail = thumbnails.optJSONObject("medium") 
                ?: thumbnails.optJSONObject("default")
            val highResThumbnail = thumbnails.optJSONObject("high")
                ?: thumbnails.optJSONObject("maxres")
            
            val video = YouTubeVideo(
                id = videoId,
                title = snippet.getString("title"),
                description = snippet.optString("description", ""),
                channelTitle = snippet.getString("channelTitle"),
                channelId = snippet.getString("channelId"),
                thumbnailUrl = defaultThumbnail?.getString("url") ?: "",
                highResThumbnailUrl = highResThumbnail?.getString("url"),
                duration = null, // Will be filled by video details if needed
                viewCount = null, // Will be filled by video details if needed
                publishedAt = snippet.getString("publishedAt"),
                url = "https://www.youtube.com/watch?v=$videoId"
            )
            
            videos.add(video)
        }
        
        val pageInfo = json.optJSONObject("pageInfo")
        val totalResults = pageInfo?.optInt("totalResults", 0) ?: 0
        val nextPageToken = json.optString("nextPageToken", null)
        
        return YouTubeSearchResult(videos, nextPageToken, totalResults)
    }
    
    private fun parseVideoDetailsResponse(jsonResponse: String): YouTubeVideo? {
        val json = JSONObject(jsonResponse)
        val items = json.optJSONArray("items") ?: return null
        
        if (items.length() == 0) return null
        
        val item = items.getJSONObject(0)
        val snippet = item.getJSONObject("snippet")
        val statistics = item.optJSONObject("statistics")
        val contentDetails = item.optJSONObject("contentDetails")
        val videoId = item.getString("id")
        
        val thumbnails = snippet.getJSONObject("thumbnails")
        val defaultThumbnail = thumbnails.optJSONObject("medium") 
            ?: thumbnails.optJSONObject("default")
        val highResThumbnail = thumbnails.optJSONObject("high")
            ?: thumbnails.optJSONObject("maxres")
        
        return YouTubeVideo(
            id = videoId,
            title = snippet.getString("title"),
            description = snippet.optString("description", ""),
            channelTitle = snippet.getString("channelTitle"),
            channelId = snippet.getString("channelId"),
            thumbnailUrl = defaultThumbnail?.getString("url") ?: "",
            highResThumbnailUrl = highResThumbnail?.getString("url"),
            duration = contentDetails?.optString("duration"),
            viewCount = statistics?.optString("viewCount"),
            publishedAt = snippet.getString("publishedAt"),
            url = "https://www.youtube.com/watch?v=$videoId"
        )
    }
    
    suspend fun getAudioFormats(videoId: String): Result<List<AudioFormat>> = withContext(Dispatchers.IO) {
        try {
            // Use yt-dlp style format extraction
            // This simulates what yt-dlp would return for audio formats
            val formats = extractAudioFormatsFromVideo(videoId)
            Result.success(formats)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting audio formats", e)
            Result.failure(e)
        }
    }
    
    private suspend fun extractAudioFormatsFromVideo(videoId: String): List<AudioFormat> {
        // Simulate yt-dlp style format extraction with realistic YouTube audio formats
        // These formats match actual YouTube audio stream IDs and qualities
        return listOf(
            // OPUS formats (WebM container) - Best quality
            AudioFormat(
                formatId = "251",
                extension = "webm",
                quality = "Best",
                bitrate = "160",
                codec = "opus",
                fileSize = null
            ),
            AudioFormat(
                formatId = "250",
                extension = "webm",
                quality = "Good",
                bitrate = "70",
                codec = "opus",
                fileSize = null
            ),
            AudioFormat(
                formatId = "249",
                extension = "webm",
                quality = "Medium",
                bitrate = "50",
                codec = "opus",
                fileSize = null
            ),
            // AAC formats (M4A container)
            AudioFormat(
                formatId = "140",
                extension = "m4a",
                quality = "Good",
                bitrate = "128",
                codec = "aac",
                fileSize = null
            ),
            AudioFormat(
                formatId = "139",
                extension = "m4a",
                quality = "Medium",
                bitrate = "48",
                codec = "aac",
                fileSize = null
            ),
            // High-quality MP3 (converted)
            AudioFormat(
                formatId = "mp3-320",
                extension = "mp3",
                quality = "Best",
                bitrate = "320",
                codec = "mp3",
                fileSize = null
            ),
            AudioFormat(
                formatId = "mp3-192",
                extension = "mp3",
                quality = "Good",
                bitrate = "192",
                codec = "mp3",
                fileSize = null
            ),
            AudioFormat(
                formatId = "mp3-128",
                extension = "mp3",
                quality = "Medium",
                bitrate = "128",
                codec = "mp3",
                fileSize = null
            )
        ).sortedByDescending { 
            // Sort by quality: Best > Good > Medium, then by bitrate
            when (it.quality) {
                "Best" -> 3000 + (it.bitrate?.toIntOrNull() ?: 0)
                "Good" -> 2000 + (it.bitrate?.toIntOrNull() ?: 0)
                "Medium" -> 1000 + (it.bitrate?.toIntOrNull() ?: 0)
                else -> 0
            }
        }
    }
    
    suspend fun getDirectAudioUrl(videoId: String, formatId: String): Result<String?> = withContext(Dispatchers.IO) {
        try {
            // This would typically use yt-dlp or youtube-dl to extract the direct URL
            // For demo purposes, we'll simulate this
            val url = "https://youtube.com/watch?v=$videoId&format=$formatId"
            Log.d(TAG, "Generated audio URL for format $formatId: $url")
            Result.success(url)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting direct audio URL", e)
            Result.failure(e)
        }
    }
    
    suspend fun getComments(
        videoId: String,
        maxResults: Int = 20,
        pageToken: String? = null,
        order: String = "relevance"
): Result<com.stash.stashwave.data.YouTubeCommentsResult> = withContext(Dispatchers.IO) {
        try {
            val base = "$BASE_URL/commentThreads"
            val url = buildString {
                append(base)
                append("?part=snippet")
                append("&videoId=$videoId")
                append("&maxResults=$maxResults")
                append("&order=$order")
                append("&textFormat=html")
                append("&key=$API_KEY")
                pageToken?.let { append("&pageToken=$it") }
            }

            val request = Request.Builder()
                .url(url)
                .addHeader("Accept", "application/json")
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                return@withContext Result.failure(IOException("YouTube API error: ${response.code} - ${response.message}"))
            }

            val body = response.body?.string() ?: ""
            val result = parseCommentsResponse(body)
            Result.success(result)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting comments", e)
            Result.failure(e)
        }
    }

private fun parseCommentsResponse(jsonResponse: String): com.stash.stashwave.data.YouTubeCommentsResult {
        val json = JSONObject(jsonResponse)
        val items = json.optJSONArray("items")
val comments = mutableListOf<com.stash.stashwave.data.YouTubeComment>()
        if (items != null) {
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                val snippet = item.getJSONObject("snippet")
                val topLevelComment = snippet.getJSONObject("topLevelComment")
                val cSnippet = topLevelComment.getJSONObject("snippet")
                val authorName = cSnippet.optString("authorDisplayName", "")
                val authorProfileImageUrl = cSnippet.optString("authorProfileImageUrl", null)
                val textHtml = cSnippet.optString("textDisplay", "")
                val likeCount = cSnippet.optInt("likeCount", 0)
                val publishedAt = cSnippet.optString("publishedAt", "")
                val replyCount = snippet.optInt("totalReplyCount", 0)
                val commentId = topLevelComment.optString("id", null)
                comments.add(
com.stash.stashwave.data.YouTubeComment(
                        authorName = authorName,
                        authorProfileImageUrl = authorProfileImageUrl,
                        textHtml = textHtml,
                        likeCount = likeCount,
                        publishedAt = publishedAt,
                        replyCount = replyCount,
                        commentId = commentId,
                        parentId = null
                    )
                )
            }
        }
        val nextPageToken = json.optString("nextPageToken", null)
return com.stash.stashwave.data.YouTubeCommentsResult(comments, nextPageToken)
    }

    suspend fun getCommentReplies(
        parentId: String,
        maxResults: Int = 20,
        pageToken: String? = null
): Result<com.stash.stashwave.data.YouTubeCommentsResult> = withContext(Dispatchers.IO) {
        try {
            val base = "$BASE_URL/comments"
            val url = buildString {
                append(base)
                append("?part=snippet")
                append("&parentId=$parentId")
                append("&maxResults=$maxResults")
                append("&textFormat=html")
                append("&key=$API_KEY")
                pageToken?.let { append("&pageToken=$it") }
            }
            val request = Request.Builder().url(url).addHeader("Accept","application/json").build()
            val response = client.newCall(request).execute()
            if (!response.isSuccessful) return@withContext Result.failure(IOException("YouTube API error: ${response.code} - ${response.message}"))
            val body = response.body?.string() ?: ""
            val result = parseRepliesResponse(body, parentId)
            Result.success(result)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting replies", e)
            Result.failure(e)
        }
    }

private fun parseRepliesResponse(jsonResponse: String, parentId: String): com.stash.stashwave.data.YouTubeCommentsResult {
        val json = JSONObject(jsonResponse)
        val items = json.optJSONArray("items")
val comments = mutableListOf<com.stash.stashwave.data.YouTubeComment>()
        if (items != null) {
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                val snippet = item.getJSONObject("snippet")
                val authorName = snippet.optString("authorDisplayName", "")
                val authorProfileImageUrl = snippet.optString("authorProfileImageUrl", null)
                val textHtml = snippet.optString("textDisplay", "")
                val likeCount = snippet.optInt("likeCount", 0)
                val publishedAt = snippet.optString("publishedAt", "")
                val commentId = item.optString("id", null)
                comments.add(
com.stash.stashwave.data.YouTubeComment(
                        authorName = authorName,
                        authorProfileImageUrl = authorProfileImageUrl,
                        textHtml = textHtml,
                        likeCount = likeCount,
                        publishedAt = publishedAt,
                        replyCount = 0,
                        commentId = commentId,
                        parentId = parentId
                    )
                )
            }
        }
        val nextPageToken = json.optString("nextPageToken", null)
return com.stash.stashwave.data.YouTubeCommentsResult(comments, nextPageToken)
    }

    private fun formatDuration(isoDuration: String?): String? {
        if (isoDuration == null) return null
        
        // Parse ISO 8601 duration format (PT4M13S -> 4:13)
        val regex = Regex("PT(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?")
        val match = regex.find(isoDuration) ?: return null
        
        val hours = match.groupValues[1].toIntOrNull() ?: 0
        val minutes = match.groupValues[2].toIntOrNull() ?: 0
        val seconds = match.groupValues[3].toIntOrNull() ?: 0
        
        return when {
            hours > 0 -> String.format("%d:%02d:%02d", hours, minutes, seconds)
            else -> String.format("%d:%02d", minutes, seconds)
        }
    }
}
