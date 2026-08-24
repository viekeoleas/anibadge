package com.example.znachok_bmw

import android.content.Context
import android.graphics.Bitmap
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "znachok/wifi"
    private val mediaChannelName = "znachok/media"
    private var connectivity: ConnectivityManager? = null
    private var wifiCallback: ConnectivityManager.NetworkCallback? = null
    private var boundNetwork: Network? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val encoderPool: ExecutorService = Executors.newFixedThreadPool(
        Runtime.getRuntime().availableProcessors().coerceIn(2, 4),
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> connectToBoard(
                        call.argument<String>("ssid") ?: "Znachok-BMW",
                        call.argument<String>("password") ?: "bmw-display",
                        result,
                    )
                    "disconnect" -> {
                        releaseBoardNetwork()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        val mediaMessenger = flutterEngine.dartExecutor.binaryMessenger
        val mediaTaskQueue = mediaMessenger.makeBackgroundTaskQueue()
        MethodChannel(
            mediaMessenger,
            mediaChannelName,
            StandardMethodCodec.INSTANCE,
            mediaTaskQueue,
        )
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "normalizeMp4" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val outputDirectory = call.argument<String>("outputDirectory")
                        if (sourcePath.isNullOrBlank() || outputDirectory.isNullOrBlank()) {
                            result.error("BAD_ARGUMENT", "Не передан путь к MP4", null)
                        } else {
                            normalizeMp4(sourcePath, outputDirectory, result)
                        }
                    }
                    "encodeJpeg" -> {
                        val rgba = call.argument<ByteArray>("rgba")
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        val maxBytes = call.argument<Int>("maxBytes") ?: Int.MAX_VALUE
                        val qualities = call.argument<List<Int>>("qualities")
                        if (rgba == null || width <= 0 || height <= 0 ||
                            qualities.isNullOrEmpty() || rgba.size < width * height * 4
                        ) {
                            result.error("BAD_ARGUMENT", "Некорректный RGBA-кадр", null)
                        } else {
                            encodeJpeg(rgba, width, height, maxBytes, qualities, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun encodeJpeg(
        rgba: ByteArray,
        width: Int,
        height: Int,
        maxBytes: Int,
        qualities: List<Int>,
        result: MethodChannel.Result,
    ) {
        encoderPool.execute {
            try {
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
                var encoded: ByteArray? = null
                for (quality in qualities) {
                    val stream = ByteArrayOutputStream(256 * 1024)
                    if (!bitmap.compress(
                            Bitmap.CompressFormat.JPEG,
                            quality.coerceIn(1, 100),
                            stream,
                        )
                    ) {
                        continue
                    }
                    val bytes = stream.toByteArray()
                    if (bytes.size <= maxBytes) {
                        encoded = bytes
                        break
                    }
                }
                bitmap.recycle()
                mainHandler.post {
                    if (encoded != null) {
                        result.success(encoded)
                    } else {
                        result.error("TOO_COMPLEX", "Кадр не уложился в лимит", null)
                    }
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("ENCODE_FAILED", error.message, null)
                }
            }
        }
    }

    private fun normalizeMp4(
        sourcePath: String,
        outputDirectory: String,
        result: MethodChannel.Result,
    ) {
        try {
            val manifest = Mp4FrameNormalizer(this).normalize(
                sourcePath,
                outputDirectory,
            )
            result.success(manifest)
        } catch (error: Mp4NormalizeException) {
            result.error(error.code, error.message, null)
        } catch (error: Exception) {
            result.error(
                "MP4_DECODE",
                error.message ?: "MP4 повреждён или использует неподдерживаемый кодек",
                null,
            )
        }
    }

    private fun connectToBoard(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("OLD_ANDROID", "Подключи Wi-Fi $ssid вручную", null)
            return
        }
        releaseBoardNetwork()
        val manager = connectivity ?: run {
            result.error("NO_NETWORK", "Сетевой сервис Android недоступен", null)
            return
        }
        var replied = false
        fun finish(block: () -> Unit) {
            if (replied) return
            replied = true
            runOnUiThread(block)
        }
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(password)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (wifiCallback !== this) return
                if (manager.bindProcessToNetwork(network)) {
                    boundNetwork = network
                    finish { result.success(true) }
                } else {
                    finish { result.error("BIND_FAILED", "Не удалось направить трафик в сеть платы", null) }
                }
            }

            override fun onUnavailable() {
                finish { result.error("WIFI_UNAVAILABLE", "Не удалось подключиться к $ssid", null) }
            }

            override fun onLost(network: Network) {
                if (wifiCallback === this && boundNetwork == network) {
                    boundNetwork = null
                    manager.bindProcessToNetwork(null)
                }
            }
        }
        wifiCallback = callback
        try {
            manager.requestNetwork(request, callback, 45_000)
        } catch (e: Exception) {
            wifiCallback = null
            finish { result.error("WIFI_ERROR", e.message ?: "Ошибка Wi-Fi", null) }
        }
    }

    private fun releaseBoardNetwork() {
        val manager = connectivity ?: return
        val callback = wifiCallback
        wifiCallback = null
        boundNetwork = null
        callback?.let {
            try {
                manager.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        manager.bindProcessToNetwork(null)
    }

    override fun onDestroy() {
        releaseBoardNetwork()
        encoderPool.shutdown()
        super.onDestroy()
    }
}
