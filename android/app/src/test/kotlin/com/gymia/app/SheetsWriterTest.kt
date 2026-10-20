package com.gymia.app

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SheetsWriterTest {
    private class GoogleFake {
        val markers = mutableListOf<JSONObject>()
        val batches = mutableListOf<JSONObject>()
        var occupied = false
        var formula = false
        var merged = false
        var lostResponse = false
        var created = false
        var createCount = 0
        var createdTitle = ""
        val writer = SheetsWriter { endpoint, _, body ->
            when {
                endpoint.endsWith("developerMetadata:search") -> {
                    JSONObject().put("matchedDeveloperMetadata", JSONArray(markers.map { JSONObject().put("developerMetadata", it) }))
                }
                endpoint.endsWith(":batchUpdate") -> {
                    val requests = body!!.getJSONArray("requests")
                    val metadata = requests.getJSONObject(requests.length() - 1).getJSONObject("createDeveloperMetadata").getJSONObject("developerMetadata")
                    check(markers.none { it.getInt("metadataId") == metadata.getInt("metadataId") })
                    markers.add(metadata)
                    batches.add(body)
                    if (lostResponse) throw java.io.IOException("Response lost after commit")
                    JSONObject()
                }
                endpoint.contains("drive/v3/files") -> JSONObject().put("files", if (created) JSONArray().put(JSONObject().put("id", "new-file").put("name", createdTitle)) else JSONArray())
                endpoint.endsWith("/spreadsheets") -> {
                    created = true; createCount++; createdTitle = body!!.getJSONObject("properties").getString("title")
                    assertEquals("Entrenamientos", body.getJSONArray("sheets").getJSONObject(0).getJSONObject("properties").getString("title"))
                    JSONObject().put("spreadsheetId", "new-file")
                }
                else -> {
                    val cell = JSONObject().put("formattedValue", if (occupied) "existing" else "")
                    if (occupied) cell.put("userEnteredValue", JSONObject().put("stringValue", "existing"))
                    if (formula) cell.put("userEnteredValue", JSONObject().put("formulaValue", "=IF(TRUE,\"\",0)"))
                    val sheet = JSONObject().put("properties", JSONObject().put("sheetId", 7).put("title", "Resumen 2026").put("gridProperties", JSONObject().put("rowCount", 1000).put("columnCount", 26)))
                        .put("data", JSONArray().put(JSONObject().put("rowData", JSONArray().put(JSONObject().put("values", JSONArray().put(cell))).put(JSONObject().put("values", JSONArray().put(JSONObject()))))))
                    if (merged) sheet.put("merges", JSONArray().put(JSONObject().put("startRowIndex", 0).put("endRowIndex", 2).put("startColumnIndex", 0).put("endColumnIndex", 2)))
                    JSONObject().put("sheets", JSONArray().put(sheet))
                }
            }
        }
    }
    private fun args() = JSONObject().put("id", "file-1").put("title", "Resumen 2026").put("sourceKey", "local:workout-1").put("sourceVersion", "original workout").put("sheetId", 7)
        .put("writes", JSONArray().put(JSONObject().put("row", 0).put("column", 0).put("value", "=literal note")))
    @Test fun writesLiteralCellsAndReceiptAtomically() {
        val fake = GoogleFake()
        val result = fake.writer.handle("writeWorkout", args()) as Map<*, *>
        assertEquals(true, result["synced"])
        val requests = fake.batches.single().getJSONArray("requests")
        assertEquals(2, requests.length())
        val update = requests.getJSONObject(0).getJSONObject("updateCells")
        assertEquals("userEnteredValue", update.getString("fields"))
        assertEquals("=literal note", update.getJSONArray("rows").getJSONObject(0).getJSONArray("values").getJSONObject(0).getJSONObject("userEnteredValue").getString("stringValue"))
        assertEquals("gymia.workout.v1", requests.getJSONObject(1).getJSONObject("createDeveloperMetadata").getJSONObject("developerMetadata").getString("metadataKey"))
    }
    @Test fun secondSendDoesNotWriteAgain() {
        val fake = GoogleFake()
        fake.writer.handle("writeWorkout", args())
        fake.occupied = true
        val result = fake.writer.handle("writeWorkout", args()) as Map<*, *>
        assertEquals(true, result["alreadySynced"])
        assertEquals(1, fake.batches.size)
    }
    @Test fun lostResponseUsesReceiptWithoutDuplicating() {
        val fake = GoogleFake(); fake.lostResponse = true
        assertEquals(true, (fake.writer.handle("writeWorkout", args()) as Map<*, *>)["synced"])
        fake.writer.handle("writeWorkout", args())
        assertEquals(1, fake.batches.size)
    }
    @Test fun occupiedAndBlankFormulaCellsAreRejected() {
        for (formula in listOf(false, true)) {
            val fake = GoogleFake(); fake.occupied = !formula; fake.formula = formula
            try { fake.writer.handle("writeWorkout", args()); fail("Must reject") } catch (_: SheetsWriteFailure) { }
            assertTrue(fake.batches.isEmpty())
        }
    }
    @Test fun rejectsMergedOutOfBoundsRepeatedAndWrongTab() {
        for (change in 0..3) {
            val fake = GoogleFake(); val request = args()
            when (change) {
                0 -> fake.merged = true
                1 -> request.getJSONArray("writes").getJSONObject(0).put("row", 1000)
                2 -> request.getJSONArray("writes").put(request.getJSONArray("writes").getJSONObject(0))
                3 -> request.put("sheetId", 8)
            }
            try { fake.writer.handle("writeWorkout", request); fail("Must reject") } catch (_: SheetsWriteFailure) { }
            assertTrue(fake.batches.isEmpty())
        }
    }
    @Test fun snapshotKeepsBlankFormulasAndTrimsUnusedGrid() {
        val fake = GoogleFake(); fake.formula = true
        val snapshot = fake.writer.handle("syncSnapshot", args()) as Map<*, *>
        assertEquals(listOf("0:0"), snapshot["occupied"])
        assertEquals(1, (snapshot["rows"] as List<*>).size)
    }

    @Test fun reviewedExistingValueCanBeChangedButConflictingValueCannot() {
        val fake = GoogleFake(); fake.occupied = true
        val request = args().put("allowOverwrite", true)
        request.getJSONArray("writes").getJSONObject(0).put("expected", JSONObject().put("stringValue", "existing"))
        assertEquals(true, (fake.writer.handle("writeWorkout", request) as Map<*, *>)["synced"])
        val conflict = GoogleFake(); conflict.occupied = true
        val stale = args().put("allowOverwrite", true)
        stale.getJSONArray("writes").getJSONObject(0).put("expected", JSONObject().put("stringValue", "old value"))
        try { conflict.writer.handle("writeWorkout", stale); fail("Must reject stale value") } catch (_: SheetsWriteFailure) { }
        assertTrue(conflict.batches.isEmpty())
    }
    @Test fun changedSourceDoesNotPretendToHaveBeenSynced() {
        val fake = GoogleFake()
        fake.writer.handle("writeWorkout", args())
        val changed = args().put("sourceVersion", "changed workout")
        try { fake.writer.handle("syncStatus", changed); fail("Must report changed source") } catch (_: SheetsWriteFailure) { }
        try { fake.writer.handle("writeWorkout", changed); fail("Must not duplicate changed source") } catch (_: SheetsWriteFailure) { }
        assertEquals(1, fake.batches.size)
    }
    @Test fun creationRecoveryFindsSameFileAndNeverCreatesBlindly() {
        val fake = GoogleFake()
        val create = JSONObject().put("name", "Mis entrenos").put("requestId", "12345678-1234-1234-1234-123456789abc")
        fake.writer.handle("createSpreadsheet", create)
        create.put("recoverOnly", true)
        assertEquals("new-file", (fake.writer.handle("createSpreadsheet", create) as Map<*, *>)["id"])
        assertEquals(1, fake.createCount)
        fake.created = false
        try { fake.writer.handle("createSpreadsheet", create); fail("Must not create") } catch (_: SheetsWriteFailure) { }
        assertEquals(1, fake.createCount)
    }
}
