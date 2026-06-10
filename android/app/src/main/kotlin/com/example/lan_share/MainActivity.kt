package com.example.lan_share

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    private val channelName = "lan_share/files"
    private val requestPickFiles = 8201
    private val requestPickFolder = 8202
    private var pendingResult: MethodChannel.Result? = null
    private val streamHandles = ConcurrentHashMap<Int, BufferedInputStream>()
    private val nextHandle = AtomicInteger(1)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFiles" -> pickFiles(result)
                    "pickFolder" -> pickFolder(result)
                    "listFolderFiles" -> listFolderFiles(call, result)
                    "calculateSha256" -> calculateSha256(call, result)
                    "openRead" -> openRead(call, result)
                    "readChunk" -> readChunk(call, result)
                    "closeRead" -> closeRead(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickFiles(result: MethodChannel.Result) {
        if (!setPendingResult(result)) return

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }

        startActivityForResult(intent, requestPickFiles)
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (!setPendingResult(result)) return

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }

        startActivityForResult(intent, requestPickFolder)
    }

    private fun setPendingResult(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error("busy", "Another picker request is already active.", null)
            return false
        }

        pendingResult = result
        return true
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val result = pendingResult ?: return
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return
        }

        when (requestCode) {
            requestPickFiles -> result.success(handlePickedFiles(data))
            requestPickFolder -> result.success(handlePickedFolder(data))
            else -> result.success(null)
        }
    }

    private fun handlePickedFiles(data: Intent): List<Map<String, Any?>> {
        val uris = mutableListOf<Uri>()
        val clipData = data.clipData

        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                uris.add(clipData.getItemAt(index).uri)
            }
        } else {
            data.data?.let { uris.add(it) }
        }

        return uris.mapNotNull { uri ->
            persistReadPermission(uri)
            describeFileUri(uri)
        }
    }

    private fun handlePickedFolder(data: Intent): Map<String, Any?>? {
        val treeUri = data.data ?: return null
        persistReadPermission(treeUri)

        val name = queryDocumentName(treeUri)
            ?: DocumentsContract.getTreeDocumentId(treeUri).substringAfterLast(':')
            .ifEmpty { "Selected folder" }

        return mapOf(
            "uri" to treeUri.toString(),
            "name" to name,
            "relativePath" to name,
            "size" to 0,
            "path" to "",
            "isFolder" to true,
        )
    }

    private fun listFolderFiles(call: MethodCall, result: MethodChannel.Result) {
        val uriValue = call.argument<String>("uri")
        val folderName = call.argument<String>("folderName") ?: "folder"

        if (uriValue.isNullOrEmpty()) {
            result.error("missing_uri", "Folder URI is required.", null)
            return
        }

        Thread {
            try {
                val treeUri = Uri.parse(uriValue)
                val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
                val files = mutableListOf<Map<String, Any?>>()

                collectTreeFiles(
                    treeUri = treeUri,
                    documentId = rootDocumentId,
                    relativePrefix = folderName,
                    output = files,
                )

                runOnUiThread { result.success(files) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("folder_scan_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun collectTreeFiles(
        treeUri: Uri,
        documentId: String,
        relativePrefix: String,
        output: MutableList<Map<String, Any?>>,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            documentId,
        )

        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)

            if (idIndex < 0 || nameIndex < 0 || mimeIndex < 0) {
                return@use
            }

            while (cursor.moveToNext()) {
                val childId = cursor.getString(idIndex) ?: continue
                val name = cursor.getString(nameIndex) ?: "file"
                val mime = cursor.getString(mimeIndex) ?: ""
                val childRelativePath = "$relativePrefix/$name"

                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    collectTreeFiles(treeUri, childId, childRelativePath, output)
                } else {
                    val fileUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                    val size = getLong(cursor, sizeIndex).takeIf { it > 0 }
                        ?: queryAssetLength(fileUri)

                    output.add(
                        mapOf(
                            "uri" to fileUri.toString(),
                            "name" to name,
                            "relativePath" to childRelativePath,
                            "size" to size,
                            "path" to "",
                            "isFolder" to false,
                        )
                    )
                }
            }
        }
    }

    private fun calculateSha256(call: MethodCall, result: MethodChannel.Result) {
        val uriValue = call.argument<String>("uri")

        if (uriValue.isNullOrEmpty()) {
            result.error("missing_uri", "File URI is required.", null)
            return
        }

        Thread {
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                contentResolver.openInputStream(Uri.parse(uriValue)).use { input ->
                    if (input == null) {
                        throw IllegalStateException("Unable to open URI stream.")
                    }

                    val buffer = ByteArray(1024 * 1024)
                    var read = input.read(buffer)

                    while (read >= 0) {
                        if (read > 0) {
                            digest.update(buffer, 0, read)
                        }

                        read = input.read(buffer)
                    }
                }

                val hash = digest.digest().joinToString("") { "%02x".format(it) }
                runOnUiThread { result.success(hash) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("hash_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun openRead(call: MethodCall, result: MethodChannel.Result) {
        val uriValue = call.argument<String>("uri")

        if (uriValue.isNullOrEmpty()) {
            result.error("missing_uri", "File URI is required.", null)
            return
        }

        try {
            val input = contentResolver.openInputStream(Uri.parse(uriValue))

            if (input == null) {
                result.error("open_failed", "Unable to open URI stream.", null)
                return
            }

            val handle = nextHandle.getAndIncrement()
            streamHandles[handle] = BufferedInputStream(input)
            result.success(handle)
        } catch (error: Throwable) {
            result.error("open_failed", error.message, null)
        }
    }

    private fun readChunk(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Int>("handle")
        val chunkSize = call.argument<Int>("chunkSize") ?: (1024 * 1024)

        if (handle == null) {
            result.error("missing_handle", "Read handle is required.", null)
            return
        }

        val input = streamHandles[handle]

        if (input == null) {
            result.error("missing_stream", "Read stream is not open.", null)
            return
        }

        Thread {
            try {
                val buffer = ByteArray(chunkSize)
                val read = input.read(buffer)
                val bytes = if (read <= 0) {
                    ByteArray(0)
                } else if (read == buffer.size) {
                    buffer
                } else {
                    buffer.copyOf(read)
                }

                runOnUiThread { result.success(bytes) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("read_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun closeRead(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<Int>("handle")

        if (handle != null) {
            streamHandles.remove(handle)?.close()
        }

        result.success(null)
    }

    private fun describeFileUri(uri: Uri): Map<String, Any?>? {
        val name = queryOpenableColumn(uri, OpenableColumns.DISPLAY_NAME) as? String
            ?: uri.lastPathSegment
            ?: "file"
        val size = (queryOpenableColumn(uri, OpenableColumns.SIZE) as? Long)
            ?.takeIf { it > 0 }
            ?: queryAssetLength(uri)

        return mapOf(
            "uri" to uri.toString(),
            "name" to name,
            "relativePath" to name,
            "size" to size,
            "path" to "",
            "isFolder" to false,
        )
    }

    private fun queryDocumentName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(0)
                } else {
                    null
                }
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun queryOpenableColumn(uri: Uri, columnName: String): Any? {
        var cursor: Cursor? = null

        return try {
            cursor = contentResolver.query(uri, arrayOf(columnName), null, null, null)

            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(columnName)

                if (index < 0 || cursor.isNull(index)) {
                    null
                } else if (columnName == OpenableColumns.SIZE) {
                    cursor.getLong(index)
                } else {
                    cursor.getString(index)
                }
            } else {
                null
            }
        } catch (_: Throwable) {
            null
        } finally {
            cursor?.close()
        }
    }

    private fun getLong(cursor: Cursor, index: Int): Long {
        return if (index >= 0 && !cursor.isNull(index)) {
            cursor.getLong(index)
        } else {
            0L
        }
    }

    private fun queryAssetLength(uri: Uri): Long {
        return try {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
                descriptor.length.takeIf { it >= 0 } ?: 0L
            } ?: 0L
        } catch (_: Throwable) {
            0L
        }
    }

    private fun persistReadPermission(uri: Uri) {
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // Some providers grant temporary access only. The current transfer can still proceed.
        }
    }
}
