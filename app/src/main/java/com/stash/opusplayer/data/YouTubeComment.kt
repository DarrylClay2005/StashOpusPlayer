package com.stash.opusplayer.data

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class YouTubeComment(
    val authorName: String,
    val authorProfileImageUrl: String?,
    val textHtml: String,
    val likeCount: Int,
    val publishedAt: String,
    val replyCount: Int = 0,
    val commentId: String? = null,
    val parentId: String? = null
) : Parcelable

@Parcelize
data class YouTubeCommentsResult(
    val comments: List<YouTubeComment>,
    val nextPageToken: String?
) : Parcelable