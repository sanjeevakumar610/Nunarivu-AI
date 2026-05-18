package com.example.nunarivu_ai

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicReference

private const val TAG = "NunarivuInference"
private const val CHANNEL = "com.nunarivu/inference"
private const val STREAM_CHANNEL = "com.nunarivu/stream"

/**
 * InferencePlugin — LiteRT-LM backend (replaces llama.cpp JNI bridge).
 *
 * Runs Gemma 4 E2B on the Adreno 710 GPU (OpenCL) via Google AI Edge's
 * LiteRT-LM Engine, with automatic CPU fallback.
 *
 * Flutter-facing API:
 *   MethodChannel "com.nunarivu/inference":
 *     loadModel(modelPath)      → true on success
 *     infer(prompt, imagePath?) → response String  (non-streaming, kept for fallback)
 *
 *   EventChannel "com.nunarivu/stream":
 *     subscribe with {prompt, imagePath} as arguments → Stream<String> of token chunks
 *
 * Model format : .litertlm (NOT .gguf — single file includes vision encoder)
 */
class InferencePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var appContext: Context? = null

    // LiteRT-LM engine — null until loadModel() succeeds
    private var engine: Engine? = null

    // Coroutine scope cancelled in onDetachedFromEngine
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Active streaming job — cancelled when Dart unsubscribes
    private var streamJob: Job? = null

    // Tracks the currently-open Conversation so it can be closed before a new
    // one is created.  LiteRT-LM only supports ONE conversation at a time
    // globally; failing to close the previous one causes:
    //   FAILED_PRECONDITION: A session already exists.
    private val activeConversation = AtomicReference<Conversation?>(null)

    // ── FlutterPlugin lifecycle ──────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        // Method channel (load + non-streaming infer)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)

        // Event channel (streaming tokens)
        EventChannel(binding.binaryMessenger, STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    @Suppress("UNCHECKED_CAST")
                    val args = arguments as? Map<String, Any?> ?: run {
                        events.error("ARG", "Missing arguments map", null)
                        return
                    }
                    val prompt = args["prompt"] as? String ?: run {
                        events.error("ARG", "prompt required", null)
                        return
                    }
                    val imagePath = args["imagePath"] as? String ?: ""
                    val eng = engine ?: run {
                        events.error("NOT_LOADED", "Model is not loaded", null)
                        return
                    }

                    streamJob?.cancel()
                    // Close any lingering conversation BEFORE the new job starts,
                    // so the native session slot is free when createConversation() runs.
                    activeConversation.getAndSet(null)
                        ?.let { try { it.close() } catch (_: Exception) {} }

                    streamJob = scope.launch {
                        var conversation: Conversation? = null
                        try {
                            Log.i(TAG, "Stream inference start (hasImage=${imagePath.isNotEmpty()})")
                            conversation = eng.createConversation()
                            activeConversation.set(conversation)

                            val flow = if (imagePath.isNotEmpty()) {
                                conversation.sendMessageAsync(
                                    Contents.of(
                                        Content.ImageFile(imagePath),
                                        Content.Text(prompt),
                                    )
                                )
                            } else {
                                conversation.sendMessageAsync(prompt)
                            }

                            flow.collect { chunk ->
                                withContext(Dispatchers.Main) { events.success(chunk.toString()) }
                            }
                            withContext(Dispatchers.Main) { events.endOfStream() }
                            Log.i(TAG, "Stream inference done")
                        } catch (ex: CancellationException) {
                            // Dart cancelled the stream — nothing to report
                            Log.i(TAG, "Stream inference cancelled")
                        } catch (ex: Exception) {
                            Log.e(TAG, "Stream inference failed", ex)
                            withContext(Dispatchers.Main) {
                                events.error("INFER_FAIL", ex.message, null)
                            }
                        } finally {
                            // Remove from tracking first, then close
                            activeConversation.compareAndSet(conversation, null)
                            try { conversation?.close() } catch (_: Exception) {}
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    Log.i(TAG, "Stream cancelled by Dart")
                    streamJob?.cancel()
                    streamJob = null
                }
            })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        streamJob?.cancel()
        closeEngine()
        scope.cancel()
        appContext = null
    }

    // ── MethodCall dispatch ──────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> handleLoadModel(call, result)
            "infer"     -> handleInfer(call, result)
            else        -> result.notImplemented()
        }
    }

    // ── loadModel ────────────────────────────────────────────────────────────

    private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
        val modelPath = call.argument<String>("modelPath")
            ?: return result.error("ARG", "modelPath required", null)

        closeEngine()

        val cacheDir = appContext?.cacheDir?.path

        scope.launch {
            val loaded = tryLoadEngine(modelPath, cacheDir, gpu = true)
                ?: tryLoadEngine(modelPath, cacheDir, gpu = false)

            withContext(Dispatchers.Main) {
                if (loaded != null) {
                    engine = loaded
                    result.success(true)
                } else {
                    result.error("LOAD_FAIL", "Engine failed to initialise (CPU)", null)
                }
            }
        }
    }

    private fun tryLoadEngine(modelPath: String, cacheDir: String?, gpu: Boolean): Engine? {
        val label = if (gpu) "GPU" else "CPU"
        return try {
            Log.i(TAG, "Loading LiteRT-LM ($label): $modelPath")
            val config = EngineConfig(
                modelPath = modelPath,
                backend   = if (gpu) Backend.GPU() else Backend.CPU(),
                cacheDir  = cacheDir,
            )
            val e = Engine(config)
            e.initialize()
            Log.i(TAG, "LiteRT-LM engine ready ($label)")
            e
        } catch (ex: Exception) {
            Log.w(TAG, "$label init failed: ${ex.message}")
            null
        }
    }

    // ── infer (non-streaming fallback) ────────────────────────────────────────

    private fun handleInfer(call: MethodCall, result: MethodChannel.Result) {
        val prompt    = call.argument<String>("prompt")    ?: return result.error("ARG", "prompt required", null)
        val imagePath = call.argument<String>("imagePath") ?: ""

        val currentEngine = engine
            ?: return result.error("NOT_LOADED", "Model is not loaded", null)

        // Cancel any active streaming job and close its conversation before
        // attempting a new synchronous inference.
        streamJob?.cancel()
        activeConversation.getAndSet(null)
            ?.let { try { it.close() } catch (_: Exception) {} }

        scope.launch {
            var conversation: Conversation? = null
            try {
                Log.i(TAG, "Infer (non-stream) start (hasImage=${imagePath.isNotEmpty()})")
                conversation = currentEngine.createConversation()
                activeConversation.set(conversation)

                val sb = StringBuilder()
                if (imagePath.isNotEmpty()) {
                    conversation.sendMessageAsync(
                        Contents.of(
                            Content.ImageFile(imagePath),
                            Content.Text(prompt),
                        )
                    ).collect { chunk -> sb.append(chunk) }
                } else {
                    conversation.sendMessageAsync(prompt)
                        .collect { chunk -> sb.append(chunk) }
                }

                val responseText = sb.toString()
                Log.i(TAG, "Infer done (${responseText.length} chars)")
                withContext(Dispatchers.Main) { result.success(responseText) }
            } catch (ex: Exception) {
                Log.e(TAG, "Infer failed", ex)
                withContext(Dispatchers.Main) {
                    result.error("INFER_FAIL", ex.message, null)
                }
            } finally {
                activeConversation.compareAndSet(conversation, null)
                try { conversation?.close() } catch (_: Exception) {}
            }
        }
    }

    // ── Cleanup ──────────────────────────────────────────────────────────────

    private fun closeEngine() {
        streamJob?.cancel()
        streamJob = null
        activeConversation.getAndSet(null)
            ?.let { try { it.close() } catch (_: Exception) {} }
        try { engine?.close() } catch (_: Exception) {}
        engine = null
    }
}
