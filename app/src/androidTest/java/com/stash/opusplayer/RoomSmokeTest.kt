package com.stash.opusplayer

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.stash.opusplayer.music.data.database.RevolutionaryMusicDatabase
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomSmokeTest {
    @Test
    fun openDatabase() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        val db = Room.inMemoryDatabaseBuilder(ctx, RevolutionaryMusicDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        db.close()
    }
}