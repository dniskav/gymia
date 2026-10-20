package com.gymia.app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var importChannel: MethodChannel? = null
    private var pendingImport: Intent? = null
    private var pickerResult: MethodChannel.Result? = null
    private val pickSheetRequest = 7401
    private lateinit var googleSheets: GoogleSheetsBridge
    private var notificationPermissionResult: MethodChannel.Result? = null

    private fun readSheet(uri: Uri): Map<String, Any> {
        val mime = contentResolver.getType(uri)
        var virtual = mime == "application/vnd.google-apps.spreadsheet"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && DocumentsContract.isDocumentUri(this, uri)) {
            contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    virtual = virtual || (cursor.getInt(0) and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT != 0)
                }
            }
        }
        val output = ByteArrayOutputStream()
        fun read(input: java.io.InputStream) {
            input.use {
                val buffer = ByteArray(8192)
                var count: Int
                while (it.read(buffer).also { count = it } != -1) {
                    if (output.size() + count > 20 * 1024 * 1024) {
                        throw IllegalArgumentException("La hoja supera 20 MB.")
                    }
                    output.write(buffer, 0, count)
                }
            }
        }
        if (virtual) {
            val available = contentResolver.getStreamTypes(uri, "*/*")?.toList().orEmpty()
            // Prefer XLSX to retain every tab. Drive performs the conversion.
            val format = listOf(
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "text/csv", "application/csv", "text/comma-separated-values"
            ).firstOrNull { it in available }
                ?: throw IllegalArgumentException("Para leer esta hoja nativa, usa «Importar desde Google Sheets» en Tus datos y autoriza tu cuenta.")
            val descriptor = contentResolver.openTypedAssetFileDescriptor(uri, format, null)
                ?: throw IllegalArgumentException("Drive no pudo descargar la hoja. Comprueba tu conexión y vuelve a intentarlo.")
            descriptor.use { read(it.createInputStream()) }
        } else {
            read(contentResolver.openInputStream(uri)
                ?: throw IllegalArgumentException("No se pudo abrir la hoja seleccionada."))
        }
        var name = "hoja"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
        }
        return mapOf("name" to name, "bytes" to output.toByteArray())
    }

    private fun deliverSheet(uri: Uri, result: MethodChannel.Result) {
        // Cloud providers can download on demand; keep this off the UI thread.
        Thread {
            try {
                val sheet = readSheet(uri)
                runOnUiThread { result.success(sheet) }
            } catch (e: Exception) {
                runOnUiThread { result.error("IMPORT_FAILED", e.message ?: "No se pudo leer la hoja. Comprueba tu conexión y vuelve a intentarlo.", null) }
            }
        }.start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.gymia.app/chatgpt")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "openBrowser" -> {
                            val uri = Uri.parse(call.argument<String>("url") ?: "")
                            val allowed = uri.scheme == "https" && uri.userInfo == null &&
                                ((uri.host == "auth.openai.com" && uri.path == "/api/accounts/authorize") ||
                                 (uri.host == "chatgpt.com" && uri.path == "/settings/usage"))
                            require(allowed)
                            // The browser owns authentication. Never use an embedded WebView.
                            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(null)
                        }
                        "resumeApp" -> {
                            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    // Authorization URLs may contain an ID-token hint: never log them.
                    result.error("CHATGPT_BROWSER", "No se pudo abrir el navegador.", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.gymia.app/rest-notifications")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(mapOf("enabled" to RestNotifications.preferences(this).getBoolean("enabled", false), "granted" to RestNotifications.permitted(this), "exact" to RestNotifications.exact(this), "lastDeliveredId" to RestNotifications.preferences(this).getString("lastDeliveredId", null), "lastDeliveredEnd" to RestNotifications.preferences(this).getLong("lastDeliveredEnd", 0)))
                        "enable" -> {
                            val enabled = call.argument<Boolean>("enabled") == true
                            if (enabled && Build.VERSION.SDK_INT >= 33 && !RestNotifications.permitted(this)) {
                                if (notificationPermissionResult != null) { result.error("BUSY", "Ya hay una solicitud de permiso en curso.", null) }
                                else {
                                    notificationPermissionResult = result
                                    requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 8402)
                                }
                            } else {
                                RestNotifications.preferences(this).edit().putBoolean("enabled", enabled && RestNotifications.permitted(this)).apply()
                                if (!enabled) RestNotifications.cancel(this)
                                result.success(enabled && RestNotifications.permitted(this))
                            }
                        }
                        "schedule" -> {
                            RestNotifications.schedule(this, call.argument<String>("id")!!, call.argument<Number>("end")!!.toLong(), call.argument<String>("name") ?: "Entrenamiento")
                            result.success(null)
                        }
                        "cancel" -> { RestNotifications.cancel(this); result.success(null) }
                        "exactSettings" -> {
                            if (Build.VERSION.SDK_INT >= 31) startActivity(Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("REST_NOTIFICATION", "No se pudo configurar el aviso de descanso.", null) }
            }
        googleSheets = GoogleSheetsBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.gymia.app/google-sheets")
            .setMethodCallHandler { call, result -> googleSheets.handle(call, result) }
        if (intent?.action == Intent.ACTION_SEND) pendingImport = intent
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.gymia.app/import")
        importChannel!!.setMethodCallHandler { call, result ->
            if (call.method == "pickSheet") {
                if (pickerResult != null) {
                    result.error("IMPORT_BUSY", "Ya hay una selección de hoja en curso.", null)
                    return@setMethodCallHandler
                }
                pickerResult = result
                try {
                    // CATEGORY_OPENABLE excludes native Google Sheets (virtual documents).
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        type = "*/*"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }, pickSheetRequest)
                } catch (e: Exception) {
                    pickerResult = null
                    result.error("IMPORT_FAILED", "No se pudo abrir el selector de hojas.", null)
                }
                return@setMethodCallHandler
            }
            if (call.method != "takePendingImport") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val shared = pendingImport
            pendingImport = null
            if (shared == null) {
                result.success(null)
                return@setMethodCallHandler
            }
            try {
                val uri = shared.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    ?: shared.clipData?.getItemAt(0)?.uri
                    ?: throw IllegalArgumentException("En Google Sheets elige «Enviar una copia», no «Copiar enlace».")
                deliverSheet(uri, result)
            } catch (e: Exception) {
                result.error("IMPORT_FAILED", e.message ?: "No se pudo leer la hoja compartida.", null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (::googleSheets.isInitialized && googleSheets.onActivityResult(requestCode, resultCode, data)) return
        if (requestCode != pickSheetRequest) return
        val result = pickerResult ?: return
        pickerResult = null
        if (resultCode != android.app.Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.error("IMPORT_FAILED", "No se recibió la hoja seleccionada.", null)
            return
        }
        deliverSheet(uri, result)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 8402) return
        val granted = RestNotifications.permitted(this)
        RestNotifications.preferences(this).edit().putBoolean("enabled", granted).apply()
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_SEND) {
            pendingImport = intent
            importChannel?.invokeMethod("importReady", null)
        }
    }
}
