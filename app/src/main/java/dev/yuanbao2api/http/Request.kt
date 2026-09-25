package dev.yuanbao2api.http

data class Request(
    val method: String,
    val path: String,
    val headers: Map<String, String>,
    val body: String
) {
    fun header(name: String): String? = headers[name.lowercase()]

    fun bearerToken(): String? {
        val auth = header("authorization") ?: return null
        return if (auth.startsWith("Bearer ")) auth.substring(7).trim() else auth.trim()
    }
}
