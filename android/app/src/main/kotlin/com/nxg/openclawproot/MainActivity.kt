package com.nxg.openclawproot

import android.content.Context
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaPlayer
import android.speech.tts.TextToSpeech
import java.util.Locale
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Base64
import io.flutter.plugin.common.MethodChannel.Result
import rikka.shizuku.Shizuku
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nxg.openclawproot/native"
    private var mediaPlayer: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var pendingVoiceResult: Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val filesDir = applicationContext.filesDir.absolutePath
        val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir

        flutterChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        flutterChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getArch" -> result.success(ArchUtils.getArch())
                "getFilesDir" -> result.success(filesDir)
                "getNativeLibDir" -> result.success(nativeLibDir)
                "getExternalStoragePath" -> result.success(Environment.getExternalStorageDirectory().absolutePath)

                "requestBatteryOptimization" -> {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:${packageName}")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BATTERY_ERROR", e.message, null)
                    }
                }

                "isBatteryOptimized" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(!pm.isIgnoringBatteryOptimizations(packageName))
                }

                "requestStoragePermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            if (!Environment.isExternalStorageManager()) {
                                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                startActivity(intent)
                            }
                        } else {
                            ActivityCompat.requestPermissions(
                                this@MainActivity,
                                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE),
                                STORAGE_PERMISSION_REQUEST
                            )
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }

                "hasStoragePermission" -> {
                    val has = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Environment.isExternalStorageManager()
                    } else {
                        ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
                    }
                    result.success(has)
                }

                "bringToForeground" -> {
                    try {
                        val intent = Intent(applicationContext, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                        }
                        applicationContext.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FOREGROUND_ERROR", e.message, null)
                    }
                }

                "checkRootAccess" -> {
                    Thread {
                        try {
                            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
                            val exitCode = process.waitFor()
                            runOnUiThread { result.success(exitCode == 0) }
                        } catch (e: Exception) {
                            runOnUiThread { result.success(false) }
                        }
                    }.start()
                }

                "executeRootCommand" -> {
                    val command = call.argument<String>("command") ?: ""
                    Thread {
                        try {
                            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))
                            val output = process.inputStream.bufferedReader().readText()
                            val errorOutput = process.errorStream.bufferedReader().readText()
                            process.waitFor()
                            runOnUiThread { result.success(output + errorOutput) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ROOT_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "captureScreenshot" -> {
                    Thread {
                        try {
                            val screenshotsDir = File(filesDir, "screenshots")
                            screenshotsDir.mkdirs()
                            val path = "${screenshotsDir.absolutePath}/screen_${System.currentTimeMillis()}.png"
                            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "screencap -p $path"))
                            process.waitFor()
                            if (File(path).exists()) {
                                runOnUiThread { result.success(path) }
                            } else {
                                runOnUiThread { result.error("SCREENSHOT_ERROR", "Screenshot file not created", null) }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SCREENSHOT_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "captureScreenshotBase64" -> {
                    Thread {
                        try {
                            val pipeProcess = Runtime.getRuntime().exec(
                                arrayOf("su", "-c", "screencap -p /dev/stdout 2>/dev/null | base64 -w0")
                            )
                            val pipeOutput = pipeProcess.inputStream.bufferedReader().readText().trim()
                            val pipeExit = pipeProcess.waitFor()
                            if (pipeExit == 0 && pipeOutput.isNotEmpty() && pipeOutput.length > 100) {
                                runOnUiThread { result.success(pipeOutput) }
                            } else {
                                val screenshotsDir = File(filesDir, "screenshots")
                                screenshotsDir.mkdirs()
                                val path = "${screenshotsDir.absolutePath}/screen_b64_${System.currentTimeMillis()}.png"
                                val capProcess = Runtime.getRuntime().exec(arrayOf("su", "-c", "screencap -p $path"))
                                capProcess.waitFor()
                                val file = File(path)
                                if (file.exists()) {
                                    val bytes = file.readBytes()
                                    val b64 = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
                                    file.delete()
                                    runOnUiThread { result.success(b64) }
                                } else {
                                    runOnUiThread { result.error("SCREENSHOT_ERROR", "Screenshot failed", null) }
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SCREENSHOT_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "captureScreenshotJpeg" -> {
                    Thread {
                        try {
                            val tmpFile = File(filesDir, "screen_tmp.png")
                            val capProcess = Runtime.getRuntime().exec(arrayOf("su", "-c", "screencap -p ${tmpFile.absolutePath}"))
                            capProcess.waitFor()
                            if (!tmpFile.exists()) {
                                runOnUiThread { result.error("SCREENSHOT_ERROR", "Screenshot failed", null) }
                                return@Thread
                            }
                            val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.RGB_565 }
                            var bitmap = BitmapFactory.decodeFile(tmpFile.absolutePath, opts)
                            if (bitmap == null) {
                                tmpFile.delete()
                                runOnUiThread { result.error("SCREENSHOT_ERROR", "Decode failed", null) }
                                return@Thread
                            }
                            // scale to max 960px
                            val maxDim = 960
                            val w = bitmap.width
                            val h = bitmap.height
                            if (w > maxDim || h > maxDim) {
                                val scale = maxDim.toFloat() / maxOf(w, h).toFloat()
                                val nw = (w * scale).toInt()
                                val nh = (h * scale).toInt()
                                bitmap = Bitmap.createScaledBitmap(bitmap, nw, nh, true)
                            }
                            val baos = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 60, baos)
                            val jpeg = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
                            bitmap.recycle()
                            tmpFile.delete()
                            runOnUiThread { result.success(jpeg) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SCREENSHOT_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "initTts" -> {
                    initTts()
                    result.success(true)
                }

                "speakTts" -> {
                    val text = call.argument<String>("text") ?: ""
                    val speed = (call.argument<Double>("speed") ?: 0.5).toFloat()
                    speakTts(text, speed)
                    result.success(true)
                }

                "stopTts" -> {
                    stopTts()
                    result.success(true)
                }

                "startVoiceInput" -> {
                    startVoiceInput(result)
                }

                "stopVoiceInput" -> {
                    stopVoiceInput()
                    result.success(true)
                }

                "playAudio" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        mediaPlayer?.release()
                        mediaPlayer = MediaPlayer().apply {
                            setDataSource(path)
                            prepare()
                            setOnCompletionListener {
                                mediaPlayer?.release()
                                mediaPlayer = null
                            }
                            start()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }

                "stopAudio" -> {
                    try {
                        mediaPlayer?.release()
                        mediaPlayer = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }

                "openHtmlFile" -> {
                    val filePath = call.argument<String>("path") ?: ""
                    try {
                        val file = File(filePath)
                        if (file.exists()) {
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this@MainActivity,
                                "${packageName}.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "text/html")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("FILE_NOT_FOUND", "HTML file not found", null)
                        }
                    } catch (e: Exception) {
                        result.error("HTML_ERROR", e.message, null)
                    }
                }

                "getDeviceInfo" -> {
                    Thread {
                        try {
                            val info = mutableMapOf<String, String>()
                            info["model"] = Build.MODEL
                            info["manufacturer"] = Build.MANUFACTURER
                            info["androidVersion"] = Build.VERSION.RELEASE
                            info["sdkLevel"] = Build.VERSION.SDK_INT.toString()

                            // RAM
                            runCatching {
                                val memProcess = Runtime.getRuntime().exec(arrayOf("su", "-c", "cat /proc/meminfo"))
                                val memInfo = memProcess.inputStream.bufferedReader().readText()
                                memProcess.waitFor()
                                val totalMem = Regex("MemTotal:\\s+(\\d+)").find(memInfo)?.groupValues?.getOrNull(1) ?: "0"
                                val totalMemMB = (totalMem.toLongOrNull() ?: 0) / 1024
                                info["ramMB"] = totalMemMB.toString()
                            }.onFailure { info["ramMB"] = "未知" }

                            // Screen
                            val dm = resources.displayMetrics
                            info["screenWidth"] = dm.widthPixels.toString()
                            info["screenHeight"] = dm.heightPixels.toString()
                            info["density"] = dm.density.toString()

                            // CPU
                            runCatching {
                                val cpuProcess = Runtime.getRuntime().exec(arrayOf("su", "-c", "grep Hardware /proc/cpuinfo 2>/dev/null | head -1"))
                                val cpuLine = cpuProcess.inputStream.bufferedReader().readText().trim()
                                cpuProcess.waitFor()
                                info["cpuHardware"] = cpuLine.replace("Hardware", "").replace("\t", "").replace(":", "").trim().ifEmpty { "未知" }
                            }.onFailure { info["cpuHardware"] = "未知" }

                            // Root status — actually check
                            info["rootStatus"] = try {
                                val p = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
                                if (p.waitFor() == 0) "已获取" else "未获取"
                            } catch (_: Exception) {
                                "未获取"
                            }

                            runOnUiThread { result.success(info) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("DEVICE_ERROR", e.message, null) }
                        }
                    }.start()
                }

                "isAccessibilityEnabled" -> {
                    val enabled = PhoneControlService.isRunning ||
                        isAccessibilityServiceEnabled()
                    result.success(enabled)
                }

                "openAccessibilitySettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ACCESSIBILITY_ERROR", e.message, null)
                    }
                }

                "performAccessibilityAction" -> {
                    val action = call.argument<String>("action") ?: ""
                    val params = call.argument<Map<String, Any>>("params") ?: emptyMap()
                    val service = PhoneControlService.instance
                    if (service == null) {
                        result.error("SERVICE_NOT_RUNNING", "Accessibility service not running", null)
                    } else {
                        try {
                            when (action) {
                                "home" -> result.success(service.performHome())
                                "back" -> result.success(service.performBack())
                                "recents" -> result.success(service.performRecents())
                                "tap" -> {
                                    val x = (params["x"] as? Number)?.toFloat() ?: 0f
                                    val y = (params["y"] as? Number)?.toFloat() ?: 0f
                                    service.performTap(x, y)
                                    result.success(true)
                                }
                                "swipe" -> {
                                    val x1 = (params["x1"] as? Number)?.toFloat() ?: 0f
                                    val y1 = (params["y1"] as? Number)?.toFloat() ?: 0f
                                    val x2 = (params["x2"] as? Number)?.toFloat() ?: 0f
                                    val y2 = (params["y2"] as? Number)?.toFloat() ?: 0f
                                    val dur = (params["durationMs"] as? Number)?.toLong() ?: 300L
                                    service.performSwipe(x1, y1, x2, y2, dur)
                                    result.success(true)
                                }
                                "inputText" -> {
                                    val text = params["text"] as? String ?: ""
                                    service.inputText(text)
                                    result.success(true)
                                }
                                "clickNode" -> {
                                    val label = params["text"] as? String ?: params["resourceId"] as? String ?: ""
                                    result.success(service.performClickNode(label))
                                }
                                "longClickNode" -> {
                                    val label = params["text"] as? String ?: params["resourceId"] as? String ?: ""
                                    result.success(service.performLongClickNode(label))
                                }
                                "scrollForward" -> {
                                    result.success(service.performScrollForward())
                                }
                                "scrollBackward" -> {
                                    result.success(service.performScrollBackward())
                                }
                                "appendText" -> {
                                    val text = params["text"] as? String ?: ""
                                    result.success(service.appendText(text))
                                }
                                "setNodeText" -> {
                                    val text = params["text"] as? String ?: ""
                                    val resId = params["resourceId"] as? String ?: ""
                                    result.success(service.setNodeText(text, resId))
                                }
                                "getNodeInfo" -> {
                                    result.success(service.getNodeInfo())
                                }
                                else -> result.notImplemented()
                            }
                        } catch (e: Exception) {
                            result.error("ACTION_ERROR", e.message, null)
                        }
                    }
                }

                "showAgentOverlay" -> {
                    val status = call.argument<String>("status") ?: "..."
                    val step = call.argument<Int>("step") ?: 0
                    AgentOverlayService.show(this@MainActivity, status, step)
                    result.success(true)
                }

                "updateAgentOverlay" -> {
                    val status = call.argument<String>("status") ?: ""
                    val step = call.argument<Int>("step") ?: 0
                    val paused = call.argument<Boolean>("paused") ?: false
                    AgentOverlayService.update(status, step, paused)
                    result.success(true)
                }

                "hideAgentOverlay" -> {
                    AgentOverlayService.hide(this@MainActivity)
                    result.success(true)
                }

                "showAgentInput" -> {
                    val hint = call.argument<String>("hint") ?: "输入验证码或反馈..."
                    AgentOverlayService.showInput(hint)
                    result.success(true)
                }

                "hideAgentInput" -> {
                    AgentOverlayService.hideInput()
                    result.success(true)
                }

                "hasOverlayPermission" -> {
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            Settings.canDrawOverlays(this@MainActivity)
                        else true
                    )
                }

                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !Settings.canDrawOverlays(this@MainActivity)) {
                        // Try root auto-grant first
                        var granted = false
                        try {
                            val p = Runtime.getRuntime().exec(
                                arrayOf("su", "-c", "appops set ${packageName} SYSTEM_ALERT_WINDOW allow")
                            )
                            p.waitFor()
                            granted = p.exitValue() == 0
                        } catch (_: Exception) {}

                        if (!granted) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:${packageName}")
                                ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
                                startActivity(intent)
                            } catch (e: Exception) {
                                result.error("OVERLAY_PERMISSION_ERROR", e.message, null)
                                return@setMethodCallHandler
                            }
                        }
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }

                "listDirectory" -> {
                    val path = call.argument<String>("path") ?: "/"
                    result.success(listDirectory(path))
                }

                "readFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val maxBytes = call.argument<Int>("maxBytes") ?: 65536
                    result.success(readFile(path, maxBytes))
                }

                "searchFiles" -> {
                    val rootPath = call.argument<String>("rootPath") ?: "/"
                    val pattern = call.argument<String>("pattern") ?: "*"
                    result.success(searchFiles(rootPath, pattern))
                }

                "statFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(statFile(path))
                }

                "browserOpen" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val intent = Intent(this@MainActivity, BrowserWebViewActivity::class.java).apply {
                            putExtra("url", BrowserWebViewActivity.normalizeUrl(url))
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BROWSER_ERROR", e.message, null)
                    }
                }

                "browserGetStructure" -> {
                    if (!BrowserWebViewActivity.isActive()) {
                        result.error("BROWSER_NOT_OPEN", "浏览器未打开", null)
                    } else {
                        BrowserWebViewActivity.refreshStructure()
                        Handler(Looper.getMainLooper()).postDelayed({
                            result.success(BrowserWebViewActivity.getStructure())
                        }, 400)
                    }
                }

                "browserClick" -> {
                    if (!BrowserWebViewActivity.isActive()) {
                        result.error("BROWSER_NOT_OPEN", "浏览器未打开", null)
                    } else {
                        val index = call.argument<Int>("index") ?: 0
                        BrowserWebViewActivity.clickElement(index)
                        result.success(true)
                    }
                }

                "browserInput" -> {
                    if (!BrowserWebViewActivity.isActive()) {
                        result.error("BROWSER_NOT_OPEN", "浏览器未打开", null)
                    } else {
                        val index = call.argument<Int>("index") ?: 0
                        val text = call.argument<String>("text") ?: ""
                        BrowserWebViewActivity.inputText(index, text)
                        result.success(true)
                    }
                }

                "browserScroll" -> {
                    if (!BrowserWebViewActivity.isActive()) {
                        result.error("BROWSER_NOT_OPEN", "浏览器未打开", null)
                    } else {
                        val direction = call.argument<String>("direction") ?: "down"
                        BrowserWebViewActivity.scrollPage(direction)
                        result.success(true)
                    }
                }

                "checkShizukuAccess" -> {
                    Thread {
                        try {
                            val binderAlive = Shizuku.pingBinder()
                            val hasPermission = if (Shizuku.isPreV11() || Shizuku.getVersion() < 11) {
                                checkSelfPermission("moe.shizuku.manager.permission.API_V23") ==
                                    PackageManager.PERMISSION_GRANTED
                            } else {
                                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                            }
                            val uid = if (binderAlive && hasPermission) Shizuku.getUid() else -1
                            runOnUiThread {
                                result.success(mapOf(
                                    "available" to (binderAlive && hasPermission),
                                    "uid" to uid,
                                    "isRoot" to (uid == 0),
                                    "isAdb" to (uid == 2000),
                                ))
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.success(mapOf("available" to false, "error" to (e.message ?: "unknown")))
                            }
                        }
                    }.start()
                }

                "requestShizukuPermission" -> {
                    if (Shizuku.isPreV11() || Shizuku.getVersion() < 11) {
                        ActivityCompat.requestPermissions(
                            this@MainActivity,
                            arrayOf("moe.shizuku.manager.permission.API_V23"),
                            1001
                        )
                    } else {
                        Shizuku.requestPermission(1001)
                    }
                    result.success(true)
                }

                "executeShizukuCommand" -> {
                    val command = call.argument<String>("command") ?: ""
                    Thread {
                        try {
                            val method = Shizuku::class.java.getDeclaredMethod(
                                "newProcess",
                                Array<String>::class.java,
                                Array<String>::class.java,
                                String::class.java
                            )
                            method.isAccessible = true
                            val process = method.invoke(null,
                                arrayOf("sh", "-c", command), null, null) as java.lang.Process
                            val output = process.inputStream.bufferedReader().readText()
                            val error = process.errorStream.bufferedReader().readText()
                            process.waitFor()
                            runOnUiThread {
                                result.success(mapOf(
                                    "output" to output,
                                    "error" to error,
                                    "exitCode" to process.exitValue(),
                                ))
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("SHIZUKU_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }

                else -> result.notImplemented()
            }
        }

        requestNotificationPermission()
    }

    private fun initTts() {
        if (tts != null) return
        tts = TextToSpeech(applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.CHINESE
            }
        }
    }

    private fun speakTts(text: String, speed: Float) {
        tts?.let {
            it.setSpeechRate(speed * 2.0f) // map 0.0-1.0 slider to 0.0-2.0 TTS rate
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                it.speak(text, TextToSpeech.QUEUE_FLUSH, null, "aidroid_tts_${System.currentTimeMillis()}")
            } else {
                it.speak(text, TextToSpeech.QUEUE_FLUSH, null)
            }
        }
    }

    private fun stopTts() {
        tts?.stop()
    }

    private fun startVoiceInput(result: Result) {
        stopVoiceInput()
        pendingVoiceResult = result

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(applicationContext)
        speechRecognizer?.setRecognitionListener(object : android.speech.RecognitionListener {
            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(android.speech.SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.getOrNull(0) ?: ""
                pendingVoiceResult?.success(text)
                pendingVoiceResult = null
                speechRecognizer?.destroy()
                speechRecognizer = null
            }

            override fun onError(error: Int) {
                pendingVoiceResult?.success("")
                pendingVoiceResult = null
                speechRecognizer?.destroy()
                speechRecognizer = null
            }

            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }
        speechRecognizer?.startListening(intent)
    }

    private fun stopVoiceInput() {
        speechRecognizer?.stopListening()
        speechRecognizer?.destroy()
        speechRecognizer = null
        pendingVoiceResult?.success("")
        pendingVoiceResult = null
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val enabledServices = try {
            android.provider.Settings.Secure.getString(
                contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
        } catch (e: Exception) {
            null
        } ?: return false
        return enabledServices.contains(packageName)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST
                )
            }
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }

    // ── File System Access ──

    private fun execRoot(cmd: String): String {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", cmd))
            val output = process.inputStream.bufferedReader().readText()
            process.waitFor()
            output
        } catch (_: Exception) {
            ""
        }
    }

    private fun listDirectory(path: String): String {
        return execRoot("ls -la \"$path\" 2>&1")
    }

    private fun readFile(path: String, maxBytes: Int): String {
        val file = java.io.File(path)
        if (!file.exists()) return ""
        val bytes = minOf(file.length(), maxBytes.toLong())
        return execRoot("head -c $bytes \"$path\" 2>&1")
    }

    private fun searchFiles(rootPath: String, pattern: String): String {
        return execRoot("find \"$rootPath\" -name \"$pattern\" 2>/dev/null | head -50")
    }

    private fun statFile(path: String): String {
        return execRoot("ls -la \"$path\" 2>&1")
    }

    companion object {
        var flutterChannel: MethodChannel? = null

        fun sendOverlayAction(action: String) {
            if (action.startsWith("input:")) {
                val text = action.substring(6)
                flutterChannel?.invokeMethod("agentOverlayAction", mapOf("action" to "input", "text" to text))
            } else {
                flutterChannel?.invokeMethod("agentOverlayAction", mapOf("action" to action))
            }
        }

        const val NOTIFICATION_PERMISSION_REQUEST = 1001
        const val STORAGE_PERMISSION_REQUEST = 1003
    }
}
