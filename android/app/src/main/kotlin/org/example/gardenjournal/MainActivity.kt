package org.example.gardenjournal

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private var pendingBackupResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gardenjournal/platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLocalTimeZone" -> result.success(TimeZone.getDefault().id)
                "pickBackupFile" -> pickBackupFile(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pickBackupFile(result: MethodChannel.Result) {
        if (pendingBackupResult != null) {
            result.error("picker_busy", "Un sélecteur est déjà ouvert.", null)
            return
        }
        pendingBackupResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            type = "application/json"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/json", "text/plain"))
        }
        startActivityForResult(intent, BACKUP_PICKER_REQUEST)
    }

    @Deprecated("Deprecated in Android API, kept for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != BACKUP_PICKER_REQUEST) return
        val result = pendingBackupResult ?: return
        pendingBackupResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        var temporaryFile: File? = null
        try {
            val importDirectory = File(cacheDir, "backup_imports").apply { mkdirs() }
            val selectedFile = File.createTempFile("gardenjournal-import-", ".json", importDirectory)
            temporaryFile = selectedFile
            contentResolver.openInputStream(data.data!!).use { input ->
                requireNotNull(input) { "Le fichier sélectionné est illisible." }
                selectedFile.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        require(total <= MAX_BACKUP_BYTES) { "La sauvegarde dépasse 250 Mio." }
                        output.write(buffer, 0, read)
                    }
                }
            }
            result.success(selectedFile.absolutePath)
        } catch (error: Exception) {
            temporaryFile?.delete()
            result.error("backup_read_failed", error.message, null)
        }
    }

    companion object {
        private const val BACKUP_PICKER_REQUEST = 9042
        private const val MAX_BACKUP_BYTES = 250L * 1024L * 1024L
    }
}
