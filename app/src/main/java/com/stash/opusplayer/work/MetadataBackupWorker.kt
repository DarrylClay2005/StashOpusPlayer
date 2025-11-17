package com.stash.opusplayer.work

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * Worker for nightly metadata backups
 */
class MetadataBackupWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    override fun doWork(): Result {
        val outputPath = inputData.getString(KEY_OUTPUT_PATH) ?: return Result.failure()
        
        return try {
            // TODO: Implement actual backup logic
            Result.success()
        } catch (e: Exception) {
            Result.failure()
        }
    }

    companion object {
        private const val KEY_OUTPUT_PATH = "output_path"
        private const val WORK_NAME = "metadata_backup"

        fun scheduleNightlyBackup(context: Context, outputPath: String) {
            val constraints = Constraints.Builder()
                .setRequiresBatteryNotLow(true)
                .build()

            val inputData = Data.Builder()
                .putString(KEY_OUTPUT_PATH, outputPath)
                .build()

            val backupRequest = PeriodicWorkRequestBuilder<MetadataBackupWorker>(
                24, TimeUnit.HOURS
            )
                .setConstraints(constraints)
                .setInputData(inputData)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                backupRequest
            )
        }
    }
}
