package dev.yuanbao2api.yuanbao

/**
 * 元宝模型：OpenAI 模型名 <-> 元宝 chatModelId 映射。
 */
data class YuanbaoModel(
    val id: String,
    val chatModelId: String,
    val name: String
)

object ModelCatalog {
    val MODELS = listOf(
        YuanbaoModel("hunyuan", "hunyuan_omnipotent_hy4", "Hunyuan"),
        YuanbaoModel("hunyuan-t1", "hunyuan_t1", "深度思考 (T1)"),
        YuanbaoModel("deepseek", "deep_seek", "DeepSeek"),
        YuanbaoModel("deepseek-v3", "deep_seek_v3", "DeepSeek V3")
    )

    fun byId(id: String): YuanbaoModel? {
        return MODELS.firstOrNull { it.id == id || it.chatModelId == id }
    }

    fun default(): YuanbaoModel = MODELS.first()
}
