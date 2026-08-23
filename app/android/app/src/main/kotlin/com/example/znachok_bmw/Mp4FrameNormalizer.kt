package com.example.znachok_bmw

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
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
            val framesJson = JSONArray()
            var outputWidth = 0
            var outputHeight = 0
            extraction.timestampsUs.forEachIndexed { index, timestampUs ->
                if (Thread.currentThread().isInterrupted) {
                    throw InterruptedException("Импорт MP4 отменён")
                }
                val raw = retriever.getFrameAtTime(
                    timestampUs,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                ) ?: throw Mp4NormalizeException(
                    "MP4_CODEC",
                    "Android не смог декодировать кадр ${index + 1}; кодек MP4 не поддерживается",
                )
                val bitmap = scaleForBadge(raw)
                if (bitmap !== raw) raw.recycle()
                outputWidth = bitmap.width
                outputHeight = bitmap.height
                val fileName = "frame-${index.toString().padStart(5, '0')}.jpg"
                val frameFile = File(staging, fileName)
                FileOutputStream(frameFile).use { stream ->
                    if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 95, stream)) {
                        throw Mp4NormalizeException(
                            "MP4_STORAGE",
                            "Не удалось сохранить кадр ${index + 1}",
                        )
                    }
                }
                bitmap.recycle()
                val nextTimestampUs = extraction.timestampsUs.getOrNull(index + 1)
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
            val sorted = rawTimestamps.distinct().sorted()
            if (sorted.isEmpty()) {
                throw Mp4NormalizeException(
                    "MP4_NO_FRAMES",
                    "В выбранном MP4 не найдено кадров",
                )
            }
            val timestamps = mutableListOf<Long>()
            for (timestampUs in sorted) {
                if (timestamps.isEmpty() || timestampUs - timestamps.last() >= MIN_FRAME_STEP_US) {
                    timestamps.add(timestampUs)
                }
            }
            if (timestamps.size > MAX_FRAMES) {
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
                timestamps.last() + fallbackDuration(timestamps),
            )
            return Timeline(timestamps, durationUs)
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
        val timestampsUs: List<Long>,
        val durationUs: Long,
    )
}
