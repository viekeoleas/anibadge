package com.example.znachok_bmw

import android.annotation.TargetApi
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

class Mp4NormalizeException(
    val code: String,
    override val message: String,
) : Exception(message)

class Mp4FrameNormalizer(private val context: Context) {
    companion object {
        private const val MAX_FRAMES = 20_000
        private const val MAX_DIMENSION = 1_200
        private const val MIN_FRAME_STEP_US = 15_000L
        private const val FALLBACK_FRAME_US = 33_333L
        private const val MAX_BATCH_FRAMES = 16
        private const val BATCH_BITMAP_BUDGET_BYTES = 48L * 1024L * 1024L
    }

    fun normalize(sourcePath: String, outputDirectory: String): String {
        val source = File(sourcePath).canonicalFile
        val output = File(outputDirectory).canonicalFile
        validatePrivatePath(source, output)
        if (!source.isFile || source.length() == 0L) {
            throw Mp4NormalizeException("MP4_MISSING", "Выбранный MP4 не удалось прочитать")
        }

        val extraction = extractTimeline(source)
        val staging = File(output.parentFile, "${output.name}.tmp-${System.nanoTime()}")
        if (!staging.mkdirs()) {
            throw Mp4NormalizeException("MP4_STORAGE", "Не удалось создать папку для кадров MP4")
        }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(source.path)
            var framesJson = JSONArray()
            var outputWidth = 0
            var outputHeight = 0
            val writeFrame = { index: Int, timestampUs: Long, raw: Bitmap ->
                if (Thread.currentThread().isInterrupted) {
                    throw InterruptedException("Импорт MP4 отменён")
                }
                val bitmap = scaleForBadge(raw)
                if (bitmap !== raw) raw.recycle()
                outputWidth = bitmap.width
                outputHeight = bitmap.height
                val fileName = "frame-${index.toString().padStart(5, '0')}.jpg"
                val frameFile = File(staging, fileName)
                try {
                    FileOutputStream(frameFile).use { stream ->
                        if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 95, stream)) {
                            throw Mp4NormalizeException(
                                "MP4_STORAGE",
                                "Не удалось сохранить кадр ${index + 1}",
                            )
                        }
                    }
                } finally {
                    bitmap.recycle()
                }
                val nextTimestampUs = extraction.frames.getOrNull(index + 1)?.timestampUs
                val durationUs = if (nextTimestampUs != null) {
                    nextTimestampUs - timestampUs
                } else {
                    max(FALLBACK_FRAME_US, extraction.durationUs - timestampUs)
                }.coerceIn(1_000L, 10_000_000L)
                framesJson.put(
                    JSONObject()
                        .put("file", fileName)
                        .put("durationUs", durationUs),
                )
                Unit
            }
            val batchSize = decodeBatchSize(extraction.width, extraction.height)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && batchSize > 1) {
                try {
                    decodeFrameBatches(retriever, extraction.frames, batchSize, writeFrame)
                } catch (_: BatchDecodeException) {
                    staging.listFiles()
                        ?.filter { it.name.startsWith("frame-") && it.extension == "jpg" }
                        ?.forEach { it.delete() }
                    framesJson = JSONArray()
                    outputWidth = 0
                    outputHeight = 0
                    decodeFramesAtTimestamps(retriever, extraction, writeFrame)
                }
            } else {
                decodeFramesAtTimestamps(retriever, extraction, writeFrame)
            }
            val manifest = JSONObject()
                .put("version", 1)
                .put("source", source.name)
                .put("width", outputWidth)
                .put("height", outputHeight)
                .put("durationUs", extraction.durationUs)
                .put("frames", framesJson)
            File(staging, "manifest.json").writeText(manifest.toString())

            if (output.exists() && !output.deleteRecursively()) {
                throw Mp4NormalizeException(
                    "MP4_STORAGE",
                    "Не удалось заменить старые кадры MP4",
                )
            }
            if (!staging.renameTo(output)) {
                throw Mp4NormalizeException(
                    "MP4_STORAGE",
                    "Не удалось завершить импорт MP4",
                )
            }
            return File(output, "manifest.json").path
        } catch (error: Mp4NormalizeException) {
            staging.deleteRecursively()
            throw error
        } catch (error: Exception) {
            staging.deleteRecursively()
            throw Mp4NormalizeException(
                "MP4_DECODE",
                error.message ?: "MP4 повреждён или использует неподдерживаемый кодек",
            )
        } finally {
            retriever.release()
        }
    }

    private fun validatePrivatePath(source: File, output: File) {
        val privateRoot = File(context.applicationInfo.dataDir).canonicalPath + File.separator
        if (!source.path.startsWith(privateRoot) || !output.path.startsWith(privateRoot)) {
            throw Mp4NormalizeException(
                "MP4_PATH",
                "MP4 должен находиться во внутренней памяти приложения",
            )
        }
    }

    private fun extractTimeline(source: File): Timeline {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(source.path)
            var videoTrack = -1
            var format: MediaFormat? = null
            for (track in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(track)
                val mime = candidate.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/")) {
                    videoTrack = track
                    format = candidate
                    break
                }
            }
            if (videoTrack < 0 || format == null) {
                throw Mp4NormalizeException(
                    "MP4_NO_VIDEO",
                    "В выбранном MP4 нет видеодорожки",
                )
            }
            extractor.selectTrack(videoTrack)
            val rawTimestamps = mutableListOf<Long>()
            while (true) {
                val timestampUs = extractor.sampleTime
                if (timestampUs < 0) break
                rawTimestamps.add(timestampUs)
                if (rawTimestamps.size > MAX_FRAMES * 2) {
                    throw Mp4NormalizeException(
                        "MP4_TOO_LONG",
                        "В MP4 слишком много кадров для внутренней памяти значка",
                    )
                }
                if (!extractor.advance()) break
            }
            val sorted = rawTimestamps.sorted()
            if (sorted.isEmpty()) {
                throw Mp4NormalizeException(
                    "MP4_NO_FRAMES",
                    "В выбранном MP4 не найдено кадров",
                )
            }
            val frames = mutableListOf<FrameRequest>()
            for ((frameIndex, timestampUs) in sorted.withIndex()) {
                if (frames.isEmpty() || timestampUs - frames.last().timestampUs >= MIN_FRAME_STEP_US) {
                    frames.add(FrameRequest(frameIndex, timestampUs))
                }
            }
            if (frames.size > MAX_FRAMES) {
                throw Mp4NormalizeException(
                    "MP4_TOO_LONG",
                    "В MP4 слишком много кадров для внутренней памяти значка",
                )
            }
            val declaredDurationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION)
            } else {
                0L
            }
            val durationUs = max(
                declaredDurationUs,
                frames.last().timestampUs + fallbackDuration(frames.map { it.timestampUs }),
            )
            val width = if (format.containsKey(MediaFormat.KEY_WIDTH)) {
                format.getInteger(MediaFormat.KEY_WIDTH)
            } else {
                0
            }
            val height = if (format.containsKey(MediaFormat.KEY_HEIGHT)) {
                format.getInteger(MediaFormat.KEY_HEIGHT)
            } else {
                0
            }
            return Timeline(frames, durationUs, width, height)
        } finally {
            extractor.release()
        }
    }

    private fun fallbackDuration(timestamps: List<Long>): Long =
        if (timestamps.size > 1) {
            max(1_000L, timestamps.last() - timestamps[timestamps.lastIndex - 1])
        } else {
            FALLBACK_FRAME_US
        }

    @TargetApi(Build.VERSION_CODES.P)
    private fun decodeFrameBatches(
        retriever: MediaMetadataRetriever,
        requests: List<FrameRequest>,
        batchSize: Int,
        consume: (Int, Long, Bitmap) -> Unit,
    ) {
        var requestCursor = 0
        while (requestCursor < requests.size) {
            val firstFrameIndex = requests[requestCursor].frameIndex
            var lastRequest = requestCursor
            while (lastRequest + 1 < requests.size &&
                requests[lastRequest + 1].frameIndex - firstFrameIndex < batchSize
            ) {
                lastRequest++
            }
            val decodedCount = requests[lastRequest].frameIndex - firstFrameIndex + 1
            val decoded = try {
                retriever.getFramesAtIndex(firstFrameIndex, decodedCount)
            } catch (error: Exception) {
                throw BatchDecodeException(error)
            }
            if (decoded.size < decodedCount) {
                decoded.forEach { it.recycle() }
                throw BatchDecodeException(
                    IllegalStateException("Android returned an incomplete MP4 frame batch"),
                )
            }
            try {
                for (requestIndex in requestCursor..lastRequest) {
                    val request = requests[requestIndex]
                    consume(
                        requestIndex,
                        request.timestampUs,
                        decoded[request.frameIndex - firstFrameIndex],
                    )
                }
            } finally {
                decoded.filterNot { it.isRecycled }.forEach { it.recycle() }
            }
            requestCursor = lastRequest + 1
        }
    }

    private fun decodeFramesAtTimestamps(
        retriever: MediaMetadataRetriever,
        timeline: Timeline,
        consume: (Int, Long, Bitmap) -> Unit,
    ) {
        val scaledSize = scaledSize(timeline.width, timeline.height)
        timeline.frames.forEachIndexed { index, request ->
            val raw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 && scaledSize != null) {
                retriever.getScaledFrameAtTime(
                    request.timestampUs,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                    scaledSize.first,
                    scaledSize.second,
                )
            } else {
                retriever.getFrameAtTime(
                    request.timestampUs,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                )
            } ?: throw Mp4NormalizeException(
                "MP4_CODEC",
                "Android не смог декодировать кадр ${index + 1}; кодек MP4 не поддерживается",
            )
            consume(index, request.timestampUs, raw)
        }
    }

    private fun decodeBatchSize(width: Int, height: Int): Int {
        if (width <= 0 || height <= 0) return 4
        val bitmapBytes = width.toLong() * height.toLong() * 4L
        return (BATCH_BITMAP_BUDGET_BYTES / bitmapBytes)
            .coerceIn(1L, MAX_BATCH_FRAMES.toLong())
            .toInt()
    }

    private fun scaledSize(width: Int, height: Int): Pair<Int, Int>? {
        val largest = max(width, height)
        if (largest <= MAX_DIMENSION || width <= 0 || height <= 0) return null
        val factor = MAX_DIMENSION.toDouble() / largest
        return Pair(
            max(1, (width * factor).roundToInt()),
            max(1, (height * factor).roundToInt()),
        )
    }

    private fun scaleForBadge(bitmap: Bitmap): Bitmap {
        val largest = max(bitmap.width, bitmap.height)
        if (largest <= MAX_DIMENSION) return bitmap
        val factor = MAX_DIMENSION.toDouble() / largest
        return Bitmap.createScaledBitmap(
            bitmap,
            max(1, (bitmap.width * factor).roundToInt()),
            max(1, (bitmap.height * factor).roundToInt()),
            true,
        )
    }

    private data class Timeline(
        val frames: List<FrameRequest>,
        val durationUs: Long,
        val width: Int,
        val height: Int,
    )

    private data class FrameRequest(
        val frameIndex: Int,
        val timestampUs: Long,
    )

    private class BatchDecodeException(cause: Exception) : Exception(cause)
}
