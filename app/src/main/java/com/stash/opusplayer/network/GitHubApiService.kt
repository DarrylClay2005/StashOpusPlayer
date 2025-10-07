package com.stash.opusplayer.network

import com.stash.opusplayer.data.GitHubRelease
import retrofit2.Response
import retrofit2.http.GET
import retrofit2.http.Path

interface GitHubApiService {
    
    @GET("repos/{owner}/{repo}/releases")
    suspend fun getAllReleases(
        @Path("owner") owner: String,
        @Path("repo") repo: String
    ): Response<List<GitHubRelease>>
    
    @GET("repos/{owner}/{repo}/releases/latest")
    suspend fun getLatestRelease(
        @Path("owner") owner: String,
        @Path("repo") repo: String
    ): Response<GitHubRelease>
    
    @GET("repos/{owner}/{repo}/releases/tags/{tag}")
    suspend fun getReleaseByTag(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Path("tag") tag: String
    ): Response<GitHubRelease>
    
    companion object {
        const val BASE_URL = "https://api.github.com/"
        const val REPO_OWNER = "DarrylClay2005"
        const val REPO_NAME = "StashOpusPlayer"
    }
}
