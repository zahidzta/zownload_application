// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.ByteArrayInputStream
import java.io.IOException
import java.util.zip.ZipFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class YtDlpUpdateDeviceTest {
    @Test
    fun verifiedStableUpdateRejectsUnsafeSwapsAndRollsBack() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        AndroidEngineAdapter(context)
        val archive = VerifiedYtDlpUpdate.activeArchive(context)
        if (VerifiedYtDlpUpdate.sha256(archive) == VerifiedYtDlpUpdate.candidateHash) {
            VerifiedYtDlpUpdate.rollbackAfterFailure(context, "probe reset")
        }
        assertEquals(VerifiedYtDlpUpdate.baselineHash, VerifiedYtDlpUpdate.sha256(archive))
        assertEquals(VerifiedYtDlpUpdate.baselineVersion, VerifiedYtDlpUpdate.runVersion(context, archive))
        Log.i("Zownload0C14", "BASELINE version=${VerifiedYtDlpUpdate.baselineVersion} hash=${VerifiedYtDlpUpdate.baselineHash}")

        VerifiedYtDlpUpdate.beginJob()
        try {
            try {
                VerifiedYtDlpUpdate.updateFromRelease(context)
                fail("Update must refuse an active engine job")
            } catch (expected: IOException) {
                assertTrue(expected.message.orEmpty().contains("busy"))
                Log.i("Zownload0C14", "ACTIVE_JOB_REJECTED hash=${VerifiedYtDlpUpdate.sha256(archive)}")
            }
        } finally {
            VerifiedYtDlpUpdate.endJob()
        }
        assertEquals(VerifiedYtDlpUpdate.baselineHash, VerifiedYtDlpUpdate.sha256(archive))

        try {
            VerifiedYtDlpUpdate.updateFromStream(context, ByteArrayInputStream("bad candidate".toByteArray()))
            fail("A bad checksum must be rejected")
        } catch (expected: IOException) {
            assertTrue(expected.message.orEmpty().contains("SHA-256 mismatch"))
            Log.i("Zownload0C14", "BAD_CANDIDATE_REJECTED hash=${VerifiedYtDlpUpdate.sha256(archive)}")
        }
        assertEquals(VerifiedYtDlpUpdate.baselineHash, VerifiedYtDlpUpdate.sha256(archive))

        VerifiedYtDlpUpdate.updateFromRelease(context)
        assertEquals(VerifiedYtDlpUpdate.candidateHash, VerifiedYtDlpUpdate.sha256(archive))
        assertEquals(VerifiedYtDlpUpdate.candidateVersion, VerifiedYtDlpUpdate.runVersion(context, archive))
        assertZipEjs(archive, VerifiedYtDlpUpdate.candidateEjsVersion)
        AndroidEngineAdapter(context) // another initialization must retain the accepted candidate
        assertEquals(VerifiedYtDlpUpdate.candidateHash, VerifiedYtDlpUpdate.sha256(archive))
        assertRuntimeReport(VerifiedYtDlpUpdate.candidateVersion)

        // Inject a failure after acceptance, then use the same rollback API
        // that a later health failure can call. No real media is affected.
        VerifiedYtDlpUpdate.rollbackAfterFailure(context, "injected post-acceptance failure")
        assertEquals(VerifiedYtDlpUpdate.baselineHash, VerifiedYtDlpUpdate.sha256(archive))
        assertEquals(VerifiedYtDlpUpdate.baselineVersion, VerifiedYtDlpUpdate.runVersion(context, archive))
        AndroidEngineAdapter(context)
        assertRuntimeReport(VerifiedYtDlpUpdate.baselineVersion)
        Log.i("Zownload0C14", "RECOVERY_OK version=${VerifiedYtDlpUpdate.baselineVersion} hash=${VerifiedYtDlpUpdate.sha256(archive)}")
    }

    private fun assertZipEjs(archive: java.io.File, version: String) {
        ZipFile(archive).use { zip ->
            val entry = zip.getEntry("yt_dlp_ejs/_version.py") ?: throw IOException("EJS missing")
            val text = zip.getInputStream(entry).bufferedReader().use { it.readText() }
            assertTrue(text.contains("__version__ = version = '$version'"))
        }
    }

    private fun assertRuntimeReport(version: String) {
        val request = YoutubeDLRequest("https://example.com/")
        request.addOption("--verbose")
        request.addOption("--simulate")
        request.addOption("--socket-timeout", 5)
        request.addOption("--retries", 0)
        val report = try {
            val response = YoutubeDL.getInstance().execute(request)
            response.err + response.out
        } catch (error: Exception) {
            error.message.orEmpty()
        }
        report.lineSequence().filter {
            it.contains("yt-dlp version") || it.contains("Optional libraries:")
        }.forEach { Log.i("Zownload0C14", "RUNTIME $it") }
        assertTrue(report, report.contains("yt-dlp version stable@$version"))
        assertTrue(report, report.contains("yt_dlp_ejs-0.8.0"))
    }
}
