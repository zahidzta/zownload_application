// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipInputStream

internal class BundledEnginePackage(private val context: Context) : AndroidEnginePackage {
    private lateinit var runtimeRoot: File
    private lateinit var pythonLibrary: File
    private lateinit var quickJs: File
    private lateinit var ffmpeg: File
    private lateinit var ffprobe: File
    private lateinit var runner: File
    private lateinit var versions: JSONObject
    private var ytDlpOverlay = ""

    private val activeOperations = ConcurrentHashMap<String, File>()
    private val updateLock = Any()
    private var updateInProgress = false

    @Synchronized
    override fun initialize() {
        if (!::runtimeRoot.isInitialized) {
            runtimeRoot = File(context.noBackupFilesDir, "zownload-engine/python-runtime")
            extractRuntime(runtimeRoot)
            runner = copyRunner(runtimeRoot)

            val nativeDirectory = File(context.applicationInfo.nativeLibraryDir)
            pythonLibrary = findNativeLibrary(nativeDirectory) { it.name == "libpython3.so" }
            quickJs = findNativeLibrary(nativeDirectory) { it.name == "libqjs.so" }
            ffmpeg = findNativeLibrary(nativeDirectory) { it.name == "libffmpeg.so" }
            ffprobe = findNativeLibrary(nativeDirectory) { it.name == "libffprobe.so" }
            validateStagedPackage()

            val activeOverlay = AndroidEngineUpdater.activeArchive(context)
            ytDlpOverlay = activeOverlay?.absolutePath ?: ""
            versions = try {
                loadVersions()
            } catch (error: Exception) {
                // An update is provisional until imports work in the embedded runtime.
                if (activeOverlay == null) throw error
                AndroidEngineUpdater.rollback(context)
                ytDlpOverlay = ""
                loadVersions()
            }
        }
    }

    override fun analyze(url: String): JSONObject {
        if (url.isBlank()) throw EngineBridgeException("invalid_url", "URL is empty")
        ensureReady()
        val operationId = UUID.randomUUID().toString()
        val cancelFile = registerOperation(operationId)
        try {
            return runRequest(
                JSONObject().put("operation", "analyze").put("url", url),
                operationId,
            )
        } finally {
            activeOperations.remove(operationId, cancelFile)
            File(context.cacheDir, "zownload-engine/$operationId").deleteRecursively()
        }
    }

    override fun downloadOne(
        request: JSONObject,
        operationId: String,
        outputTemplate: String,
        onProgress: (JSONObject) -> Unit,
    ): JSONObject {
        ensureReady()
        validateOperationId(operationId)
        val expectedDirectory = File(context.cacheDir, "zownload-engine/$operationId").canonicalFile
        if (File(outputTemplate).parentFile?.canonicalFile != expectedDirectory) {
            throw EngineBridgeException("permission_denied", "Invalid Android output template")
        }
        val cancelFile = registerOperation(operationId)

        val requestCopy = JSONObject(request.toString())
            .put("operation", "download")
            .put("outputTemplate", outputTemplate)
        try {
            return runRequest(requestCopy, operationId, onProgress)
        } finally {
            activeOperations.remove(operationId, cancelFile)
        }
    }

    override fun cancel(operationId: String): Boolean {
        val marker = activeOperations[operationId] ?: return false
        return try {
            marker.parentFile?.mkdirs()
            marker.createNewFile() || marker.exists()
        } catch (_: IOException) {
            false
        }
    }

    override fun cancelAllActive(): Int {
        var count = 0
        for (marker in activeOperations.values) {
            try {
                marker.parentFile?.mkdirs()
                if (marker.createNewFile() || marker.exists()) {
                    count += 1
                }
            } catch (_: IOException) {
            }
        }
        return count
    }

    override fun hasActiveOperations(): Boolean = activeOperations.isNotEmpty()

    override fun checkUpdate(): JSONObject {
        ensureReady()
        return AndroidEngineUpdater.checkInfo(versions.getString("ytDlp"))
    }

    override fun update(): JSONObject {
        ensureReady()
        synchronized(updateLock) {
            if (updateInProgress || activeOperations.isNotEmpty()) {
                throw EngineBridgeException("unknown", "The Android engine is busy")
            }
            updateInProgress = true
        }
        return try {
            AndroidEngineUpdater.update(context, versions.getString("ytDlp"))
        } finally {
            synchronized(updateLock) { updateInProgress = false }
        }
    }

    private fun runRequest(
        request: JSONObject,
        operationId: String,
        onProgress: ((JSONObject) -> Unit)? = null,
    ): JSONObject {
        validateOperationId(operationId)
        val workDirectory = File(context.cacheDir, "zownload-engine/$operationId")
        if (!workDirectory.isDirectory && !workDirectory.mkdirs()) {
            throw EngineBridgeException("disk_full", "Cannot create the private engine work directory")
        }
        val requestFile = File(workDirectory, "request.json")
        val resultFile = File(workDirectory, "result.json")
        val progressFile = File(workDirectory, "progress.jsonl")
        val cancelFile = File(workDirectory, "cancel")
        requestFile.writeText(
            request.put("pythonHome", runtimeRoot.absolutePath)
                .put("ffmpegPath", ffmpeg.absolutePath)
                .put("ffprobePath", ffprobe.absolutePath)
                .put("quickJsPath", quickJs.absolutePath)
                .put("ytDlpOverlay", ytDlpOverlay)
                .toString(),
            Charsets.UTF_8,
        )
        resultFile.delete()
        progressFile.writeText("", Charsets.UTF_8)

        val finished = AtomicBoolean(false)
        val watcher = if (onProgress != null) Thread({
            watchProgress(progressFile, finished, onProgress)
        }, "zownload-engine-progress-$operationId").apply { start() } else null

        val argv = JSONArray()
            .put(runner.absolutePath)
            .put(requestFile.absolutePath)
            .put(resultFile.absolutePath)
            .put(progressFile.absolutePath)
            .put(cancelFile.absolutePath)
            .toString()
        val encodedArgs = Base64.encodeToString(argv.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val resultPathLiteral = "'${resultFile.absolutePath.replace("\\", "\\\\").replace("'", "\\'")}'"
        val source = """
            try:
                import base64, json, runpy, sys
                sys.argv = json.loads(base64.b64decode('$encodedArgs').decode('utf-8'))
                runpy.run_path(sys.argv[0], run_name='__main__')
            except BaseException as error:
                try:
                    import traceback
                    detail = traceback.format_exc()
                except BaseException:
                    detail = type(error).__name__ + ': ' + str(error)
                try:
                    with open($resultPathLiteral, 'w', encoding='utf-8') as output:
                        output.write(detail)
                except BaseException:
                    pass
                raise
        """.trimIndent()

        val runStatus = try {
            NativePythonBridge.run(pythonLibrary.absolutePath, runtimeRoot.absolutePath, source)
        } finally {
            finished.set(true)
            watcher?.join(5_000)
        }
        if (runStatus != 0) {
            val detail = if (resultFile.isFile) resultFile.readText(Charsets.UTF_8).take(4_000) else "no Python traceback was written"
            throw EngineBridgeException("engine_missing", "Embedded Python failed with status $runStatus: $detail")
        }
        if (!resultFile.isFile) {
            throw EngineBridgeException("engine_missing", "Embedded Python did not return an engine result")
        }

        val response = JSONObject(resultFile.readText(Charsets.UTF_8))
        if (!response.optBoolean("ok")) {
            val error = response.optJSONObject("error") ?: JSONObject()
            throw EngineBridgeException(
                error.optString("code", "unknown"),
                error.optString("detail", "Android engine operation failed"),
            )
        }
        return response.optJSONObject("value")
            ?: throw EngineBridgeException("engine_missing", "Android engine returned an invalid result")
    }

    private fun watchProgress(file: File, finished: AtomicBoolean, callback: (JSONObject) -> Unit) {
        var offset = 0L
        while (!finished.get() || offset < file.length()) {
            try {
                RandomAccessFile(file, "r").use { input ->
                    if (input.length() > offset) {
                        input.seek(offset)
                        val line = input.readLine()
                        if (line != null) {
                            offset = input.filePointer
                            val decoded = String(line.toByteArray(Charsets.ISO_8859_1), Charsets.UTF_8)
                            callback(JSONObject(decoded))
                        }
                    }
                }
                if (offset >= file.length()) Thread.sleep(80)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            } catch (_: Exception) {
                try {
                    Thread.sleep(80)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return
                }
            }
        }
    }

    private fun extractRuntime(root: File) {
        val marker = File(root, ".ready")
        if (marker.isFile) return
        val archiveName = context.assets.list("")
            ?.singleOrNull { it.startsWith("python-runtime") && it.endsWith(".zip") }
            ?: throw EngineBridgeException("engine_missing", "The manifest-verified Python runtime asset is missing")

        val parent = root.parentFile ?: throw EngineBridgeException("engine_missing", "Invalid engine runtime directory")
        if (!parent.isDirectory && !parent.mkdirs()) {
            throw EngineBridgeException("disk_full", "Cannot create the Android engine directory")
        }
        val staging = File(parent, "python-runtime.extracting")
        staging.deleteRecursively()
        if (!staging.mkdirs()) throw EngineBridgeException("disk_full", "Cannot stage the Python runtime")
        val canonicalRoot = staging.canonicalPath + File.separator

        try {
            ZipInputStream(context.assets.open(archiveName).buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val target = File(staging, entry.name).canonicalFile
                    if (!target.path.startsWith(canonicalRoot)) {
                        throw EngineBridgeException("engine_missing", "Python runtime archive contains an unsafe path")
                    }
                    if (entry.isDirectory) {
                        if (!target.isDirectory && !target.mkdirs()) throw IOException("Cannot create runtime directory")
                    } else {
                        target.parentFile?.let { if (!it.isDirectory && !it.mkdirs()) throw IOException("Cannot create runtime directory") }
                        FileOutputStream(target).use { output -> zip.copyTo(output) }
                    }
                    zip.closeEntry()
                }
            }
            File(staging, ".ready").writeText("manifest-verified", Charsets.UTF_8)
            if (root.exists()) root.deleteRecursively()
            if (!staging.renameTo(root)) throw IOException("Cannot publish the extracted Python runtime")
        } catch (error: Exception) {
            staging.deleteRecursively()
            if (error is EngineBridgeException) throw error
            throw EngineBridgeException("engine_missing", error.message ?: "Could not extract the Python runtime")
        }
    }

    private fun copyRunner(root: File): File {
        val target = File(root, "engine_runner.py")
        // This small script ships with the app, so refresh it on app update
        // even when the larger extracted Python runtime is already present.
        context.assets.open("engine_runner.py").use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output)
                output.fd.sync()
            }
        }
        return target
    }

    private fun findNativeLibrary(directory: File, matches: (File) -> Boolean): File {
        return directory.listFiles()?.singleOrNull(matches)
            ?: throw EngineBridgeException("engine_missing", "A required manifest-verified Android engine library is missing")
    }

    private fun validateStagedPackage() {
        val expected = listOf(pythonLibrary, quickJs, ffmpeg, ffprobe)
        if (expected.any { !it.isFile || !it.canRead() }) {
            throw EngineBridgeException("engine_missing", "The staged Android engine package is incomplete")
        }
    }

    private fun ensureReady() {
        if (!::versions.isInitialized) initialize()
    }

    private fun loadVersions(): JSONObject {
        val operationId = UUID.randomUUID().toString()
        return try {
            runRequest(
                JSONObject().put("operation", "versions"),
                operationId,
            )
        } finally {
            File(context.cacheDir, "zownload-engine/$operationId").deleteRecursively()
        }
    }

    private fun registerOperation(operationId: String): File {
        validateOperationId(operationId)
        synchronized(updateLock) {
            if (updateInProgress) throw EngineBridgeException("unknown", "The Android engine is updating")
            val workDirectory = File(context.cacheDir, "zownload-engine/$operationId")
            if (!workDirectory.isDirectory && !workDirectory.mkdirs()) {
                throw EngineBridgeException("disk_full", "Cannot create the private engine work directory")
            }
            val cancelFile = File(workDirectory, "cancel")
            cancelFile.delete()
            if (activeOperations.putIfAbsent(operationId, cancelFile) != null) {
                throw EngineBridgeException("unknown", "An engine operation already uses this ID")
            }
            return cancelFile
        }
    }

    private fun validateOperationId(value: String) {
        if (!Regex("^[A-Za-z0-9_-]{1,64}$").matches(value)) {
            throw EngineBridgeException("permission_denied", "Invalid Android engine operation ID")
        }
    }
}
