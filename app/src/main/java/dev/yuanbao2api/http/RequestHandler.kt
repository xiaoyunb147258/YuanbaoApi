package dev.yuanbao2api.http

import dev.yuanbao2api.store.SettingsStore
import dev.yuanbao2api.util.Logger
import dev.yuanbao2api.yuanbao.ModelCatalog
import dev.yuanbao2api.yuanbao.YuanbaoClient
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStream
import java.util.UUID

class RequestHandler(
    private val settings: SettingsStore,
    private val client: YuanbaoClient
) {

    fun handle(req: Request, out: OutputStream) {
        val writer = ResponseWriter(out)
        val path = req.path.substringBefore("?")

        when {
            req.method == "OPTIONS" -> { writer.writeJson(200, "{}"); return }
            path == "/v1/models" && req.method == "GET" -> {
                if (!auth(req, writer)) return
                writer.writeJson(200, modelsJson())
                return
            }
            path == "/v1/chat/completions" && req.method == "POST" -> {
                if (!auth(req, writer)) return
                handleChat(req, writer)
                return
            }
            path == "/health" -> { writer.writeJson(200, "{\"status\":\"ok\"}"); return }
            else -> { writer.writeJson(404, errorJson("Not found: $path")); return }
        }
    }

    private fun auth(req: Request, writer: ResponseWriter): Boolean {
        val key = settings.apiKey
        if (key.isEmpty()) return true
        if (req.bearerToken() != key) {
            writer.writeJson(401, errorJson("Invalid API key"))
            return false
        }
        return true
    }

    private fun handleChat(req: Request, writer: ResponseWriter) {
        val body = try { JSONObject(req.body) } catch (e: Exception) {
            writer.writeJson(400, errorJson("Invalid JSON body")); return
        }
        val prompt = buildPrompt(body)
        if (prompt.isEmpty()) {
            writer.writeJson(400, errorJson("No user message")); return
        }
        val stream = body.optBoolean("stream", false)
        val modelId = body.optString("model", "hunyuan")
        val model = ModelCatalog.byId(modelId) ?: ModelCatalog.default()
        val id = "chatcmpl-" + UUID.randomUUID().toString().replace("-", "").take(24)
        val created = System.currentTimeMillis() / 1000

        if (!stream) {
            try {
                val reply = client.chat(prompt, model)
                writer.writeJson(200, completionJson(id, created, modelId, reply))
            } catch (e: Exception) {
                Logger.log("请求失败：" + e.message)
                writer.writeJson(500, errorJson(e.message ?: "upstream error"))
            }
            return
        }

        writer.beginChunked()
        try {
            writer.writeChunk(sseChunk(id, created, modelId, mapOf("role" to "assistant")))
            val reply = client.chat(prompt, model) { delta ->
                if (delta.isNotEmpty()) {
                    writer.writeChunk(sseChunk(id, created, modelId, mapOf("content" to delta)))
                }
            }
            if (reply.isEmpty()) {
                writer.writeChunk(sseChunk(id, created, modelId, mapOf("content" to "")))
            }
            writer.writeChunk(sseChunk(id, created, modelId, emptyMap(), "stop"))
            writer.writeChunk("data: [DONE]\n\n")
        } catch (e: Exception) {
            Logger.log("流式请求失败：" + e.message)
            writer.writeChunk("data: " + JSONObject().put("error", JSONObject().put("message", e.message ?: "error")).toString() + "\n\n")
        }
        writer.endChunked()
    }

    private fun buildPrompt(body: JSONObject): String {
        val messages = body.optJSONArray("messages") ?: return ""
        val sb = StringBuilder()
        for (i in 0 until messages.length()) {
            val m = messages.optJSONObject(i) ?: continue
            val role = m.optString("role", "user")
            val content = m.optString("content")
            if (content.isEmpty()) continue
            when (role) {
                "system" -> sb.append("[system] ").append(content).append("\n")
                "assistant" -> sb.append("[assistant] ").append(content).append("\n")
                else -> sb.append(content).append("\n")
            }
        }
        return sb.toString().trim()
    }

    private fun sseChunk(id: String, created: Long, model: String, delta: Map<String, String>, finish: String? = null): String {
        val deltaObj = JSONObject()
        for ((k, v) in delta) deltaObj.put(k, v)
        val choice = JSONObject().put("index", 0).put("delta", deltaObj)
            .put("finish_reason", finish ?: JSONObject.NULL)
        val obj = JSONObject().put("id", id).put("object", "chat.completion.chunk")
            .put("created", created).put("model", model)
            .put("choices", JSONArray().put(choice))
        return "data: $obj\n\n"
    }

    private fun completionJson(id: String, created: Long, model: String, content: String): String {
        val message = JSONObject().put("role", "assistant").put("content", content)
        val choice = JSONObject().put("index", 0).put("message", message).put("finish_reason", "stop")
        val usage = JSONObject().put("prompt_tokens", 0).put("completion_tokens", 0).put("total_tokens", 0)
        return JSONObject().put("id", id).put("object", "chat.completion")
            .put("created", created).put("model", model)
            .put("choices", JSONArray().put(choice)).put("usage", usage).toString()
    }

    private fun modelsJson(): String {
        val now = System.currentTimeMillis() / 1000
        val list = JSONArray()
        ModelCatalog.MODELS.forEach { m ->
            list.put(JSONObject().put("id", m.id).put("object", "model")
                .put("created", now).put("owned_by", "yuanbao"))
        }
        return JSONObject().put("object", "list").put("data", list).toString()
    }

    private fun errorJson(msg: String): String =
        JSONObject().put("error", JSONObject().put("message", msg).put("type", "api_error")).toString()
}
