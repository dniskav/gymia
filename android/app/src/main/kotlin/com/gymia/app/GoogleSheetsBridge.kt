package com.gymia.app

import android.accounts.Account
import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.AccountPicker
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/** Tokens remain on Android, in memory, and never cross the Flutter channel. */
class GoogleSheetsBridge(private val activity: Activity) {
    private val accountRequest = 7410
    private val consentRequest = 7411
    private val identityScopes = listOf(
        Scope("openid"), Scope("https://www.googleapis.com/auth/userinfo.email")
    )
    private val sheetScopes = listOf(
        Scope("https://www.googleapis.com/auth/spreadsheets.readonly"),
        Scope("https://www.googleapis.com/auth/drive.metadata.readonly")
    )
    private var authorizationResult: MethodChannel.Result? = null
    @Volatile private var accessToken: String? = null
    @Volatile private var subject: String? = null
    @Volatile private var generation = 0
    @Volatile private var writeAuthorized = false
    private var interactive = true
    private var identityOnly = false
    private var expectedSubject: String? = null
    private var requestedScopes = identityScopes

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "disconnect" -> {
                generation++
                accessToken = null
                subject = null
                authorizationResult?.error("GOOGLE_CANCELLED", "La conexión se ha cerrado.", null)
                authorizationResult = null
                result.success(null)
            }
            "clearSheetToken" -> {
                val token = accessToken
                val expected = call.argument<String>("expectedSubject")
                if (expected == null || expected != subject) {
                    result.error("GOOGLE_ACCOUNT_MISMATCH", "La cuenta no corresponde al acceso actual.", null)
                } else if (token == null) {
                    result.success(null)
                } else {
                    accessToken = null
                    Identity.getAuthorizationClient(activity).clearToken(ClearTokenRequest.builder().setToken(token).build())
                        .addOnSuccessListener { result.success(null) }
                        .addOnFailureListener { result.error("GOOGLE_AUTH_REQUIRED", "No se pudo renovar el acceso a Google.", null) }
                }
            }
            "connectIdentity", "authorize", "authorizeWrite" -> {
                if (authorizationResult != null) {
                    result.error("GOOGLE_BUSY", "La autorización ya está en curso.", null)
                    return
                }
                interactive = call.argument<Boolean>("interactive") != false
                identityOnly = call.method == "connectIdentity"
                expectedSubject = call.argument<String>("expectedSubject")
                if (!identityOnly && expectedSubject.isNullOrBlank()) {
                    result.error("GOOGLE_PROFILE_REQUIRED", "Conecta tu cuenta desde Cuenta y datos antes de cargar una hoja.", null)
                    return
                }
                writeAuthorized = false
                requestedScopes = if (identityOnly) identityScopes else identityScopes + if (call.method == "authorizeWrite") listOf(Scope("https://www.googleapis.com/auth/spreadsheets"), Scope("https://www.googleapis.com/auth/drive.metadata.readonly")) else sheetScopes
                generation++
                accessToken = null
                subject = null
                authorizationResult = result
                // Let Google's authorization UI select the account and request
                // consent in one flow. A separate picker is only needed when
                // the user explicitly asks to change the previous account.
                if (!identityOnly) {
                    val email = call.argument<String>("email")
                    if (email.isNullOrBlank()) {
                        finishError("GOOGLE_PROFILE_REQUIRED", "No se recibió la cuenta del perfil.")
                        return
                    }
                    requestAuthorization(Account(email, "com.google"))
                    return
                }
                try {
                    val options = AccountPicker.AccountChooserOptions.Builder()
                        .setAllowableAccountsTypes(listOf("com.google"))
                        .setAlwaysShowAccountPicker(true)
                        .build()
                    activity.startActivityForResult(AccountPicker.newChooseAccountIntent(options), accountRequest)
                } catch (_: Exception) {
                    finishError("GOOGLE_UNAVAILABLE", "No se pudo abrir Google. Comprueba que los servicios de Google Play estén disponibles.")
                }
            }
            "list" -> execute(call, result) { token ->
                val query = call.argument<String>("query").orEmpty().trim()
                val escaped = query.replace("\\", "\\\\").replace("'", "\\'")
                val filter = "mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false" +
                    if (escaped.isEmpty()) "" else " and name contains '$escaped'"
                val params = mutableMapOf(
                    "q" to filter, "fields" to "files(id,name),nextPageToken,incompleteSearch",
                    "pageSize" to "100", "orderBy" to "modifiedTime desc"
                )
                call.argument<String>("pageToken")?.takeIf { it.isNotEmpty() }?.let { params["pageToken"] = it }
                val json = request(token, "https://www.googleapis.com/drive/v3/files", params)
                val files = json.optJSONArray("files")
                mapOf(
                    "files" to (0 until (files?.length() ?: 0)).map { i ->
                        val file = files!!.getJSONObject(i)
                        mapOf("id" to file.getString("id"), "name" to file.getString("name"))
                    },
                    "nextPageToken" to json.optString("nextPageToken", ""),
                    "incompleteSearch" to json.optBoolean("incompleteSearch", false)
                )
            }
            "tabs" -> execute(call, result) { token ->
                val id = sheetId(call)
                val json = request(token, "https://sheets.googleapis.com/v4/spreadsheets/$id",
                    mapOf("fields" to "sheets(properties(title))"))
                val sheets = json.getJSONArray("sheets")
                (0 until sheets.length()).map { sheets.getJSONObject(it).getJSONObject("properties").getString("title") }
            }
            "read" -> execute(call, result) { token ->
                val id = sheetId(call)
                val title = call.argument<String>("title")?.takeIf { it.isNotEmpty() }
                    ?: throw GoogleFailure("GOOGLE_INPUT", "Elige una pestaña de la hoja.")
                // Quote A1 titles, including spaces, apostrophes and names resembling cell references.
                val range = Uri.encode("'" + title.replace("'", "''") + "'")
                val json = request(token, "https://sheets.googleapis.com/v4/spreadsheets/$id/values/$range",
                    mapOf("valueRenderOption" to "FORMATTED_VALUE", "majorDimension" to "ROWS"))
                val rows = json.optJSONArray("values")
                (0 until (rows?.length() ?: 0)).map { i ->
                    val row = rows!!.getJSONArray(i)
                    (0 until row.length()).map { j -> row.optString(j, "") }
                }
            }
            "syncSnapshot", "syncStatus", "writeWorkout", "createSpreadsheet", "probeWrite" -> execute(call, result) { token ->
                if (!writeAuthorized) throw GoogleFailure("GOOGLE_WRITE_REQUIRED", "Autoriza la escritura en Google antes de enviar el progreso.")
                val writer = SheetsWriter { endpoint, params, body -> request(token, endpoint, params, body) }
                writer.handle(call.method, JSONObject(call.arguments as Map<*, *>))
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != accountRequest && requestCode != consentRequest) return false
        if (authorizationResult == null) return true
        if (requestCode == accountRequest) {
            if (resultCode != Activity.RESULT_OK) {
                finishError("GOOGLE_CANCELLED", "Google no completó la selección de cuenta. Puedes volver a conectar sin salir de esta pantalla.")
                return true
            }
            val email = data?.getStringExtra("authAccount")
            if (email.isNullOrBlank()) {
                finishError("GOOGLE_ACCOUNT", "No se recibió la cuenta de Google seleccionada.")
                return true
            }
            requestAuthorization(Account(email, "com.google"))
        } else {
            // A non-OK result can carry Google's actual error. Parse it before
            // treating the flow as cancelled instead of silently hiding it.
            if (data == null) {
                finishError("GOOGLE_CANCELLED", "Google no completó la autorización. Vuelve a conectar y acepta los permisos solicitados.")
                return true
            }
            try {
                acceptAuthorization(Identity.getAuthorizationClient(activity).getAuthorizationResultFromIntent(data))
            } catch (e: Exception) { authorizationError(e) }
        }
        return true
    }

    private fun requestAuthorization(account: Account? = null) {
        try {
            val builder = AuthorizationRequest.builder().setRequestedScopes(requestedScopes)
            if (account != null) builder.setAccount(account)
            Identity.getAuthorizationClient(activity).authorize(builder.build())
                .addOnSuccessListener { acceptAuthorization(it) }
                .addOnFailureListener { authorizationError(it) }
        } catch (e: Exception) { authorizationError(e) }
    }

    private fun acceptAuthorization(result: AuthorizationResult) {
        if (authorizationResult == null) return
        if (result.hasResolution()) {
            if (!interactive) {
                finishError("GOOGLE_RECONNECT_REQUIRED", "Google necesita que vuelvas a conectar la cuenta porque el permiso no está disponible. Los datos locales se conservan.")
                return
            }
            try {
                activity.startIntentSenderForResult(result.pendingIntent!!.intentSender, consentRequest, null, 0, 0, 0)
            } catch (e: Exception) { authorizationError(e) }
            return
        }
        if (!result.grantedScopes.containsAll(requestedScopes.map { it.scopeUri }) || result.accessToken.isNullOrBlank()) {
            finishError("GOOGLE_PERMISSION", "Google no concedió los permisos solicitados. Puedes volver a intentarlo.")
            return
        }
        val token = result.accessToken!!
        val epoch = generation
        val signingIn = identityOnly
        val expected = expectedSubject
        Thread {
            try {
                // Google validates the bearer token at its HTTPS userinfo
                // endpoint. Never trust an email or an unverified decoded JWT.
                val identity = request(token, "https://openidconnect.googleapis.com/v1/userinfo", emptyMap())
                val id = identity.optString("sub")
                val email = identity.optString("email")
                if (!id.matches(Regex("[A-Za-z0-9_-]{1,128}")) ||
                    !email.contains("@") || !identity.optBoolean("email_verified")) {
                    throw GoogleFailure("GOOGLE_IDENTITY", "Google no devolvió una identidad verificada.")
                }
                if (expected != null && id != expected) {
                    throw GoogleFailure("GOOGLE_ACCOUNT_MISMATCH", "La cuenta seleccionada no corresponde a este perfil. No se cargó ninguna hoja.")
                }
                activity.runOnUiThread {
                    if (generation == epoch && authorizationResult != null) {
                        subject = id
                        accessToken = if (signingIn) null else token
                        writeAuthorized = !signingIn && result.grantedScopes.contains("https://www.googleapis.com/auth/spreadsheets")
                        authorizationResult?.success(if (signingIn) mapOf("subject" to id, "email" to email) else true)
                        authorizationResult = null
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    if (generation == epoch) {
                        if (e is GoogleFailure) finishError(e.code, e.message)
                        else finishError("GOOGLE_IDENTITY", "No se pudo verificar tu identidad con Google. Comprueba la conexión.")
                    }
                }
            }
        }.start()
    }

    private fun authorizationError(error: Exception) {
        val code = (error as? ApiException)?.statusCode
        finishError("GOOGLE_AUTH", if (code == 10) {
            "Google no reconoce la configuración de GymIA. Falta registrar esta versión de la app en el proyecto de Google."
        } else if (code == 16) {
            "Google no completó la autorización (código 16). Puedes volver a conectar y aceptar los permisos solicitados sin salir de esta pantalla."
        } else {
            "No se pudo autorizar Google${code?.let { " (código $it)" }.orEmpty()}. Comprueba tu conexión y que tu cuenta esté habilitada para las pruebas de GymIA."
        })
    }

    private fun finishError(code: String, message: String) {
        accessToken = null
        authorizationResult?.error(code, message, null)
        authorizationResult = null
    }

    private fun sheetId(call: MethodCall): String = call.argument<String>("id")
        ?.takeIf { it.matches(Regex("[A-Za-z0-9_-]+")) }
        ?: throw GoogleFailure("GOOGLE_INPUT", "La hoja seleccionada no es válida.")

    private fun execute(call: MethodCall, result: MethodChannel.Result, action: (String) -> Any) {
        val expected = call.argument<String>("expectedSubject")
        if (expected == null || expected != subject) {
            result.error("GOOGLE_ACCOUNT_MISMATCH", "La lectura no corresponde a la cuenta autorizada. Vuelve a conectar desde tu perfil.", null)
            return
        }
        val epoch = generation
        val token = accessToken
        if (token == null) {
            result.error("GOOGLE_AUTH_REQUIRED", "Vuelve a conectar tu cuenta de Google para cargar la hoja.", null)
            return
        }
        Thread {
            try {
                val value = action(token)
                activity.runOnUiThread {
                    if (epoch == generation && expected == subject) result.success(value)
                    else result.error("GOOGLE_ACCOUNT_CHANGED", "La cuenta cambió durante la lectura. No se aplicó el resultado.", null)
                }
            } catch (e: SheetsWriteFailure) {
                activity.runOnUiThread { result.error(e.code, e.message, null) }
            } catch (e: GoogleFailure) {
                activity.runOnUiThread { result.error(e.code, e.message, null) }
            } catch (_: Exception) {
                activity.runOnUiThread { result.error("GOOGLE_NETWORK", "No se pudo confirmar la operación con Google. El progreso local se conserva. Al reintentar se comprobará el recibo del envío.", null) }
            }
        }.start()
    }

    private fun request(token: String, endpoint: String, params: Map<String, String>, body: JSONObject? = null): JSONObject {
        val builder = Uri.parse(endpoint).buildUpon()
        params.forEach { (key, value) -> builder.appendQueryParameter(key, value) }
        val connection = URL(builder.build().toString()).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("Accept", "application/json")
            if (body != null) {
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            if (status !in 200..299) {
                throw when (status) {
                    401 -> GoogleFailure("GOOGLE_AUTH_REQUIRED", "La autorización de Google ha caducado. Vuelve a conectar tu cuenta.")
                    403 -> GoogleFailure("GOOGLE_FORBIDDEN", "Google no permite esta operación. Comprueba los permisos de la hoja y que las API de Drive y Sheets estén activadas para GymIA.")
                    404 -> GoogleFailure("GOOGLE_NOT_FOUND", "La hoja ya no está disponible para esta cuenta.")
                    429 -> GoogleFailure("GOOGLE_RATE_LIMIT", "Google ha recibido demasiadas solicitudes. Espera un momento y vuelve a intentarlo.")
                    else -> GoogleFailure("GOOGLE_SERVER", "Google no pudo completar la operación (código $status). Vuelve a intentarlo.")
                }
            }
            val output = ByteArrayOutputStream()
            connection.inputStream.use { input ->
                val buffer = ByteArray(8192)
                var count: Int
                while (input.read(buffer).also { count = it } != -1) {
                    if (output.size() + count > 20 * 1024 * 1024) {
                        throw GoogleFailure("GOOGLE_TOO_LARGE", "La pestaña supera 20 MB. Elige una pestaña más pequeña.")
                    }
                    output.write(buffer, 0, count)
                }
            }
            return JSONObject(output.toString("UTF-8"))
        } finally { connection.disconnect() }
    }

    private class GoogleFailure(val code: String, override val message: String) : Exception(message)
}
