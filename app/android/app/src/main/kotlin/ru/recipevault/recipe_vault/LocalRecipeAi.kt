package ru.recipevault.recipe_vault

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.ai.edge.litertlm.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** One inference at a time, off the UI thread, with explicit native resource ownership. */
class LocalRecipeAi(private val context: Context, private val channel: MethodChannel) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val lock = Any()
    private var conversation: Conversation? = null
    @Volatile private var activeId: Int? = null

    init { channel.setMethodCallHandler(::handle) }

    private fun checkCancelled() {
        if (cancelled.get() || closed.get()) throw InterruptedException("Cancelled")
    }

    private fun progress(id: Int, text: String) {
        main.post { if (!closed.get()) channel.invokeMethod("progress", mapOf("id" to id, "text" to text)) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed.get()) { result.error("closed", "Обработка уже закрыта.", null); return }
        if (call.method == "supported") {
            result.success(Build.VERSION.SDK_INT >= 26 && Build.SUPPORTED_ABIS.contains("arm64-v8a"))
            return
        }
        if (call.method == "cancel") {
            if (call.argument<Int>("id") == activeId) cancel()
            result.success(null)
            return
        }
        if (call.method != "extract") { result.notImplemented(); return }
        if (Build.VERSION.SDK_INT < 26 || !Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
            result.error("unsupported", "Локальный ИИ требует Android 8+ и 64-битный ARM-процессор.", null)
            return
        }
        if (!busy.compareAndSet(false, true)) {
            result.error("busy", "Локальная модель уже занята.", null); return
        }
        val id = call.argument<Int>("id") ?: 0
        val modelPath = call.argument<String>("modelPath") ?: ""
        val fragments = call.argument<List<String>>("fragments") ?: emptyList()
        val instruction = call.argument<String>("instruction") ?: ""
        val chatTemplate = call.argument<String>("chatTemplate") ?: ""
        val schema = call.argument<String>("schema") ?: ""
        val fragmentSchemas = call.argument<List<String>>("fragmentSchemas") ?: emptyList()
        val model = File(modelPath)
        // Native code only opens the app's private, verified model, never a source URL.
        if (model.canonicalPath != File(context.filesDir, "LocalAI/qwen-recipe.litertlm").canonicalPath ||
            !model.isFile || fragments.isEmpty() || fragments.size > 64 ||
            fragments.any { it.length > 2400 } || instruction.length > 6000 ||
            chatTemplate.length > 6000 || schema.length > 10000 ||
            (fragmentSchemas.isNotEmpty() && fragmentSchemas.size != fragments.size) ||
            fragmentSchemas.any { it.length > 10000 }) {
            busy.set(false)
            result.error("invalid", "Некорректная модель или текст.", null); return
        }
        cancelled.set(false)
        activeId = id
        executor.execute {
            var engine: Engine? = null
            var backend = "GPU"
            var outputs: List<String>? = null
            var failure: Throwable? = null
            var wasCancelled = false
            val cache = File(context.cacheDir, "litertlm")
            try {
                cache.mkdirs()
                // Retry CPU if either GPU initialization or generation fails.
                for (chosenBackend in listOf(Backend.GPU(), Backend.CPU(threadCount = 4))) {
                    checkCancelled()
                    backend = chosenBackend.name
                    progress(id, if (backend == "GPU") "Загружаю модель на видеопроцессор…"
                        else "Перехожу к обработке на процессоре…")
                    try {
                        engine = Engine(EngineConfig(modelPath, chosenBackend,
                            maxNumTokens = 4096, cacheDir = cache.path))
                        engine.initialize()
                        checkCancelled()
                        val responses = mutableListOf<String>()
                        fragments.forEachIndexed { index, fragment ->
                            checkCancelled()
                            progress(id, "Разбираю фрагмент ${index + 1} из ${fragments.size} ($backend)…")
                            val current = engine!!.createConversation(ConversationConfig(
                                systemInstruction = Contents.of(instruction),
                                samplerConfig = SamplerConfig(topK = 40, topP = 1.0, temperature = 0.0),
                                maxOutputToken = 1536, enableResponseFormat = true,
                                chatTemplate = chatTemplate,
                            ))
                            synchronized(lock) { conversation = current }
                            try {
                                checkCancelled()
                                responses.add(current.sendMessage("Источник рецепта:\n$fragment",
                                    responseFormat = ResponseFormat.json(fragmentSchemas.getOrNull(index) ?: schema)).toString())
                            } finally {
                                synchronized(lock) { conversation = null; current.close() }
                            }
                            checkCancelled()
                        }
                        outputs = responses
                        break
                    } catch (e: Exception) {
                        checkCancelled()
                        if (backend == "CPU") throw e
                    } finally {
                        try { engine?.close() } catch (_: Exception) { }
                        engine = null
                    }
                }
            } catch (e: Throwable) {
                failure = e
            } finally {
                try { engine?.close() } catch (_: Exception) { }
                // Do not retain GPU compilation files between imports.
                try { cache.deleteRecursively() } catch (_: Exception) { }
                activeId = null
                wasCancelled = cancelled.get() || closed.get()
                busy.set(false)
            }
            main.post {
                if (closed.get()) return@post
                if (wasCancelled || failure is InterruptedException) {
                    result.error("cancelled", "Обработка отменена.", null)
                } else if (failure != null) {
                    result.error("inference", "Локальная модель не смогла разобрать текст. Закройте лишние приложения и повторите; исходник сохранён.", null)
                } else {
                    result.success(mapOf("outputs" to outputs, "backend" to backend))
                }
            }
        }
    }

    private fun cancel() {
        cancelled.set(true)
        synchronized(lock) { try { conversation?.cancelProcess() } catch (_: Exception) { } }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        cancel()
        channel.setMethodCallHandler(null)
        main.removeCallbacksAndMessages(null)
        executor.shutdownNow()
    }
}
