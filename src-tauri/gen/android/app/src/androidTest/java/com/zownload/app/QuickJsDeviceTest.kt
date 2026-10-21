// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File
import java.security.MessageDigest
import android.util.Log
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class QuickJsDeviceTest {
    @Test
    fun pinnedRuntimeAndPairExecuteOnDevice() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val oldZipapp = File(context.noBackupFilesDir, "${YoutubeDL.baseName}/${YoutubeDL.ytdlpDirName}/${YoutubeDL.ytdlpBin}")
        assertTrue(oldZipapp.parentFile!!.mkdirs() || oldZipapp.parentFile!!.isDirectory)
        oldZipapp.writeText("previous bundled yt-dlp probe")
        val selected = BundledEnginePackage()
        selected.initialize(context)
        val runtime = File(selected.paths.quickJsExecutable!!)
        val zipapp = File(selected.paths.ytDlpArchive!!)
        assertEquals("4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185", sha256(runtime))
        assertEquals("1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6", sha256(zipapp))

        // QuickJS reads a script from the same writable cache used by yt-dlp.
        val script = File(context.cacheDir, "quickjs-device-probe.js")
        script.writeText("print('ZOWNLOAD_QUICKJS_EXEC_OK')")
        val process = ProcessBuilder(runtime.absolutePath, script.absolutePath)
            .redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().readText()
        assertEquals("QuickJS execution failed: $output", 0, process.waitFor())
        assertTrue(output.contains("ZOWNLOAD_QUICKJS_EXEC_OK"))
        Log.i("Zownload0C05", "QuickJS script=${script.absolutePath} output=${output.trim()}")

        val cache = File(context.cacheDir, "yt-dlp-device-probe")
        assertTrue(cache.mkdirs() || cache.isDirectory)
        val cacheProbe = File(cache, "write-probe")
        cacheProbe.writeText("writable")
        assertEquals("writable", cacheProbe.readText())
        val request = YoutubeDLRequest("https://example.com/")
        request.addOption("--verbose")
        request.addOption("--simulate")
        request.addOption("--socket-timeout", 5)
        request.addOption("--retries", 0)
        request.addOption("--cache-dir", cache.absolutePath)
        // A generic page may contain no video. Its verbose startup report still
        // proves the selected Python zipapp sees the pinned EJS and QuickJS.
        val report = try {
            val response = YoutubeDL.getInstance().execute(request)
            response.err + response.out
        } catch (error: Exception) {
            error.message.orEmpty()
        }
        report.lineSequence().filter {
            it.contains("yt-dlp version") || it.contains("Optional libraries:") || it.contains("JS runtimes:")
        }.forEach { Log.i("Zownload0C05", it) }
        assertTrue(report.contains("yt-dlp version stable@2026.08.19"))
        assertTrue(report.contains("yt_dlp_ejs-0.8.0"))
        assertTrue(report.contains("JS runtimes: quickjs-2026-06-04"))
        assertTrue(cache.isDirectory && cache.canWrite())
        Log.i("Zownload0C05", "writable cache=${cache.absolutePath}")
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val chunk = ByteArray(8192)
            while (true) {
                val count = input.read(chunk)
                if (count < 0) break
                digest.update(chunk, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
