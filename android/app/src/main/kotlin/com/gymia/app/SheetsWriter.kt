package com.gymia.app

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

class SheetsWriteFailure(val code: String, override val message: String) : Exception(message)

/** Only fixed API operations; model output is never an endpoint or a Google request. */
class SheetsWriter(private val rpc: (String, Map<String, String>, JSONObject?) -> JSONObject) {
    private val base = "https://sheets.googleapis.com/v4/spreadsheets"
    private fun fail(message: String): Nothing = throw SheetsWriteFailure("GOOGLE_SYNC", message)
    private fun id(args: JSONObject) = args.getString("id").also {
        if (!it.matches(Regex("[A-Za-z0-9_-]{1,200}"))) fail("La hoja no es válida.")
    }
    private fun operation(args: JSONObject): String {
        val source = args.getString("sourceKey")
        if (!source.matches(Regex("[A-Za-z0-9_:/.-]{1,300}"))) fail("El entrenamiento no es válido.")
        return MessageDigest.getInstance("SHA-256").digest(source.toByteArray()).joinToString("") { "%02x".format(it) }
    }
    private fun version(args: JSONObject): String {
        val source = args.getString("sourceVersion")
        if (source.isBlank() || source.length > 1000000) fail("El entrenamiento es demasiado grande o no contiene datos.")
        return MessageDigest.getInstance("SHA-256").digest(source.toByteArray()).joinToString("") { "%02x".format(it) }
    }
    private fun metadataId(key: String) = (key.take(8).toLong(16) and 0x7fffffff).toInt().coerceAtLeast(1)
    private fun marker(id: String, key: String): JSONObject? {
        val response = rpc("$base/$id/developerMetadata:search", emptyMap(), JSONObject().put("dataFilters", JSONArray().put(
            JSONObject().put("developerMetadataLookup", JSONObject().put("metadataId", metadataId(key)))
        )))
        val found = response.optJSONArray("matchedDeveloperMetadata") ?: return null
        if (found.length() == 0) return null
        val result = found.getJSONObject(0).getJSONObject("developerMetadata")
        if (result.optString("metadataKey") != "gymia.workout.v1" || !result.optString("metadataValue").startsWith("$key:")) fail("Hay un conflicto con el identificador del recibo. No se ha enviado nada.")
        return result
    }
    private fun snapshot(args: JSONObject): JSONObject {
        val title = args.getString("title")
        if (title.isBlank() || title.length > 100) fail("Elige una pestaña válida.")
        val range = "'" + title.replace("'", "''") + "'"
        val response = rpc("$base/${id(args)}", mapOf(
            "ranges" to range, "includeGridData" to "true",
            "fields" to "sheets(properties(sheetId,title,gridProperties),merges,data(startRow,startColumn,rowData(values(userEnteredValue,formattedValue))))"
        ), null)
        val sheet = response.getJSONArray("sheets").getJSONObject(0)
        val rows = mutableListOf<MutableList<String>>()
        val occupied = JSONArray()
        val entered = JSONObject()
        var lastUsedRow = -1
        val blocks = sheet.optJSONArray("data") ?: JSONArray()
        for (b in 0 until blocks.length()) {
            val block = blocks.getJSONObject(b)
            val data = block.optJSONArray("rowData") ?: JSONArray()
            for (r in 0 until data.length()) {
                val row = block.optInt("startRow") + r
                while (rows.size <= row) rows.add(mutableListOf())
                val values = data.getJSONObject(r).optJSONArray("values") ?: JSONArray()
                for (c in 0 until values.length()) {
                    val col = block.optInt("startColumn") + c
                    while (rows[row].size <= col) rows[row].add("")
                    val cell = values.getJSONObject(c)
                    rows[row][col] = cell.optString("formattedValue", "")
                    if (rows[row][col].isNotEmpty()) lastUsedRow = maxOf(lastUsedRow, row)
                    if (cell.has("userEnteredValue") && cell.getJSONObject("userEnteredValue").length() > 0) {
                        occupied.put("$row:$col")
                        entered.put("$row:$col", cell.getJSONObject("userEnteredValue"))
                        lastUsedRow = maxOf(lastUsedRow, row)
                    }
                }
            }
        }
        while (rows.size > lastUsedRow + 1) rows.removeAt(rows.lastIndex)
        rows.forEach { row -> while (row.isNotEmpty() && row.last().isEmpty()) row.removeAt(row.lastIndex) }
        return JSONObject().put("rows", JSONArray(rows.map { JSONArray(it) }))
            .put("occupied", occupied).put("entered", entered).put("merges", sheet.optJSONArray("merges") ?: JSONArray())
            .put("properties", sheet.getJSONObject("properties"))
    }
    fun handle(method: String, args: JSONObject): Any = when (method) {
        "syncSnapshot" -> snapshot(args).toMap()
        "syncStatus" -> {
            val key = operation(args)
            val receipt = marker(id(args), key)
            if (receipt != null && receipt.getString("metadataValue") != "$key:${version(args)}") fail("Esta sesión ya se envió y sus datos locales han cambiado. Revisa la hoja antes de corregir ese envío; no se duplicará automáticamente.")
            mapOf("synced" to (receipt != null))
        }
        "createSpreadsheet" -> {
            val requestId = args.getString("requestId")
            if (!requestId.matches(Regex("[a-f0-9-]{36}"))) fail("La solicitud de creación no es válida.")
            val name = args.getString("name").trim()
            if (name.isEmpty() || name.length > 80) fail("Escribe un nombre para la hoja (máximo 80 caracteres).")
            // Stable, unique title lets a lost creation response be recovered without creating again.
            val title = "$name · ${requestId.take(8)}"
            val escaped = title.replace("\\", "\\\\").replace("'", "\\'")
            val files = rpc("https://www.googleapis.com/drive/v3/files", mapOf(
                "q" to "mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false and name = '$escaped'",
                "fields" to "files(id,name)", "pageSize" to "100"
            ), null).optJSONArray("files") ?: JSONArray()
            if (files.length() > 1) fail("Hay más de una hoja con ese identificador. Elige la hoja desde el selector.")
            if (files.length() == 1) {
                mapOf("id" to files.getJSONObject(0).getString("id"), "name" to title, "title" to "Entrenamientos")
            } else {
                if (args.optBoolean("recoverOnly")) fail("No se ha podido localizar la hoja creada. Comprueba Google Sheets y vuelve a buscar; no se creará otra automáticamente.")
                val headers = listOf("Fecha", "Actividad", "Serie / tramo", "Métricas", "Duración (s)", "Notas", "Sesión GymIA")
                val created = rpc(base, emptyMap(), JSONObject().put("properties", JSONObject().put("title", title))
                    .put("sheets", JSONArray().put(JSONObject().put("properties", JSONObject().put("title", "Entrenamientos"))
                        .put("data", JSONArray().put(JSONObject().put("rowData", JSONArray().put(JSONObject().put("values", JSONArray(headers.map {
                            JSONObject().put("userEnteredValue", JSONObject().put("stringValue", it))
                        })))))))))
                mapOf("id" to created.getString("spreadsheetId"), "name" to title, "title" to "Entrenamientos")
            }
        }
        "writeWorkout" -> {
            val spreadsheet = id(args)
            val key = operation(args)
            val receipt = marker(spreadsheet, key)
            val valueVersion = version(args)
            if (receipt != null) {
                if (receipt.getString("metadataValue") != "$key:$valueVersion") fail("Esta sesión ya se envió y sus datos locales han cambiado. Revisa la hoja antes de corregir ese envío; no se duplicará automáticamente.")
                mapOf("synced" to true, "alreadySynced" to true)
            } else {
                val fresh = snapshot(args)
                val properties = fresh.getJSONObject("properties")
                if (properties.getInt("sheetId") != args.getInt("sheetId")) fail("La pestaña cambió. Prepara de nuevo el envío.")
                val occupied = fresh.getJSONArray("occupied").let { list -> (0 until list.length()).map { list.getString(it) }.toSet() }
                val merges = fresh.getJSONArray("merges")
                val grid = properties.getJSONObject("gridProperties")
                val writes = args.getJSONArray("writes")
                if (writes.length() !in 1..250) fail("El envío debe contener entre 1 y 250 celdas.")
                val seen = mutableSetOf<String>()
                val requests = JSONArray()
                for (i in 0 until writes.length()) {
                    val cell = writes.getJSONObject(i)
                    val row = cell.getInt("row")
                    val col = cell.getInt("column")
                    if (row !in 0 until grid.getInt("rowCount") || col !in 0 until grid.getInt("columnCount") || !seen.add("$row:$col")) fail("Una celda está repetida o fuera de la pestaña.")
                    val actual = fresh.getJSONObject("entered").optJSONObject("$row:$col") ?: JSONObject()
                    val expected = cell.optJSONObject("expected") ?: JSONObject()
                    if (actual.has("formulaValue") || expected.has("formulaValue")) fail("No se permite modificar fórmulas.")
                    if (actual.toString() != expected.toString()) fail("La celda cambió desde la revisión. No se sobrescribió nada; prepara de nuevo el envío.")
                    if ("$row:$col" in occupied && !args.optBoolean("allowOverwrite")) fail("La celda ya contiene datos. Activa la actualización de celdas y revisa el cambio antes de enviar.")
                    for (m in 0 until merges.length()) {
                        val merged = merges.getJSONObject(m)
                        if (row >= merged.optInt("startRowIndex") && row < merged.getInt("endRowIndex") && col >= merged.optInt("startColumnIndex") && col < merged.getInt("endColumnIndex")) fail("No se escriben celdas combinadas. Elige otra zona de la hoja.")
                    }
                    val value = cell.get("value")
                    val entry = JSONObject()
                    when (value) {
                        is Boolean -> entry.put("boolValue", value)
                        is Number -> { if (!value.toDouble().isFinite()) fail("Una cifra no es válida."); entry.put("numberValue", value) }
                        is String -> { if (value.isEmpty() || value.length > 4000) fail("Una celda está vacía o supera 4000 caracteres."); entry.put("stringValue", value) }
                        else -> fail("El valor de una celda no es válido.")
                    }
                    requests.put(JSONObject().put("updateCells", JSONObject()
                        .put("start", JSONObject().put("sheetId", properties.getInt("sheetId")).put("rowIndex", row).put("columnIndex", col))
                        .put("rows", JSONArray().put(JSONObject().put("values", JSONArray().put(JSONObject().put("userEnteredValue", entry)))))
                        .put("fields", "userEnteredValue")))
                }
                // Deterministic metadataId makes two competing sends of the same workout atomic:
                // only one batch can create it; the other's entire batch is rejected by Google.
                val metadataId = metadataId(key)
                requests.put(JSONObject().put("createDeveloperMetadata", JSONObject().put("developerMetadata", JSONObject()
                    .put("metadataId", metadataId).put("metadataKey", "gymia.workout.v1").put("metadataValue", "$key:$valueVersion")
                    .put("visibility", "DOCUMENT").put("location", JSONObject().put("spreadsheet", true)))))
                try {
                    rpc("$base/$spreadsheet:batchUpdate", emptyMap(), JSONObject().put("requests", requests))
                } catch (error: Exception) {
                    // A response can be lost after the atomic commit. Never blindly append again.
                    if (marker(spreadsheet, key)?.optString("metadataValue") != "$key:$valueVersion") throw error
                }
                if (marker(spreadsheet, key)?.optString("metadataValue") != "$key:$valueVersion") fail("Google no devolvió el recibo. El envío está sin confirmar; reintenta para comprobarlo.")
                mapOf("synced" to true, "alreadySynced" to false)
            }
        }
        else -> fail("Operación de sincronización desconocida.")
    }
}

private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { key -> jsonValue(get(key)) }
private fun jsonValue(value: Any?): Any? = when (value) {
    is JSONObject -> value.toMap()
    is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
    JSONObject.NULL -> null
    else -> value
}
