package com.example.timer_main

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

class ReminderSoundProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String {
        val name = uri.lastPathSegment.orEmpty().lowercase()
        return when {
            name.endsWith(".mp3") => "audio/mpeg"
            name.endsWith(".m4a") || name.endsWith(".mp4") => "audio/mp4"
            name.endsWith(".wav") => "audio/wav"
            name.endsWith(".ogg") || name.endsWith(".oga") => "audio/ogg"
            name.endsWith(".aac") => "audio/aac"
            name.endsWith(".flac") => "audio/flac"
            else -> "application/octet-stream"
        }
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Read-only sound provider")
        val segments = uri.pathSegments
        if (segments.size != 2 || segments[0] != "sounds") throw FileNotFoundException("Invalid sound URI")
        val name = segments[1]
        if (!Regex("^[A-Za-z0-9_.-]{1,180}$").matches(name)) throw FileNotFoundException("Invalid sound filename")
        val root = File(requireNotNull(context).filesDir, "reminder_sounds").canonicalFile
        val file = File(root, name).canonicalFile
        if (file.parentFile != root || !file.isFile) throw FileNotFoundException("Reminder sound not found")
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }
}
