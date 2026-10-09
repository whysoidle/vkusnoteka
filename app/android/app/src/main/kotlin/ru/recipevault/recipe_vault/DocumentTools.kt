package ru.recipevault.recipe_vault

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class DocumentTools(private val context: Context, private val channel: MethodChannel) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "ocr") { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path") ?: ""
            executor.execute {
                var bitmap: android.graphics.Bitmap? = null
                var tess: TessBaseAPI? = null
                try {
                    val source = File(path)
                    require(source.canonicalPath.startsWith(context.cacheDir.canonicalPath + File.separator) && source.isFile && source.length() <= 50L * 1024 * 1024)
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(path, bounds)
                    require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 6_000_000)
                    bitmap = BitmapFactory.decodeFile(path) ?: error("Unsupported image")
                    val root = File(context.filesDir, "OCR")
                    val data = File(root, "tessdata").apply { mkdirs() }
                    for (name in listOf("rus.traineddata", "eng.traineddata")) {
                        val model = File(data, name)
                        if (!model.exists()) context.assets.open("flutter_assets/assets/tessdata/$name").use { input -> model.outputStream().use { input.copyTo(it) } }
                    }
                    tess = TessBaseAPI()
                    require(tess.init(root.path + File.separator, "rus+eng", TessBaseAPI.OEM_LSTM_ONLY))
                    tess.pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO
                    tess.setImage(bitmap)
                    val text = tess.utF8Text ?: ""
                    main.post { if (!closed.get()) result.success(text) }
                } catch (_: Throwable) {
                    main.post { if (!closed.get()) result.error("ocr", "Не удалось распознать изображение. Выберите более чёткий снимок или заполните рецепт вручную.", null) }
                } finally { tess?.recycle(); bitmap?.recycle() }
            }
        }
    }
    fun close() {
        if (!closed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        main.removeCallbacksAndMessages(null)
        executor.shutdownNow()
    }
}
