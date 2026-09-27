// API 客户端 - 复刻 doubao2api 全部端点
// 两种模式：
//   1. 本地引擎(默认, 开箱即用) - 通过 WebView 桥接，用豆包自身 JS 签名直连
//   2. 代理模式 - 连接自部署的 doubao2api 后端 (OpenAI 兼容 /v1/*)
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/models.dart';
import 'webview_bridge.dart';

class ApiClient {
  String backendUrl;
  String backendKey;
  bool useBackend;
  WebViewBridge? bridge;

  static const String DOUBAO_BASE = 'https://www.doubao.com';
  static const String DEFAULT_BOT_ID = '7338286299411103781';

  late Dio _dio;

  ApiClient({
    this.backendUrl = 'http://127.0.0.1:9090',
    this.backendKey = '',
    this.useBackend = false,
    this.bridge,
  }) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 6),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      },
    ));
  }

  Map<String, dynamic> get _authHeaders =>
      backendKey.isEmpty ? {} : {'Authorization': 'Bearer $backendKey'};

  Future<bool> healthCheck() async {
    if (!useBackend) {
      return bridge?.isReady ?? false;
    }
    try {
      final r = await _dio.get('$backendUrl/health');
      return r.data is Map && r.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Stream<Map<String, dynamic>> chatStream({
    required List<ChatMessage> messages,
    int needDeepThink = 0,
    String? conversationId,
  }) async* {
    if (useBackend) {
      yield* _chatStreamProxy(messages, needDeepThink, conversationId);
    } else {
      yield* _chatStreamLocal(messages, needDeepThink, conversationId);
    }
  }

  Stream<Map<String, dynamic>> _chatStreamLocal(
    List<ChatMessage> messages,
    int needDeepThink,
    String? conversationId,
  ) async* {
    if (bridge == null || !bridge!.isReady) {
      yield {'error': '本地引擎未就绪，请稍候或切换到代理模式'};
      return;
    }
    final lastMsg = messages.isNotEmpty ? messages.last.content : '';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = '${ts}_${_uuid()}';
    final body = {
      'messages': [
        {
          'content': jsonEncode({'text': lastMsg}),
          'content_type': 2001,
          'attachments': [],
          'references': [],
        }
      ],
      'completion_option': {
        'is_regen': false,
        'with_suggest': true,
        'need_create_conversation': conversationId == null,
        'launch_stage': 1,
        'is_replace': false,
        'is_delete': false,
        'is_ai_playground': false,
        'memory_type': 2,
        'message_from': 0,
        'use_deep_think': needDeepThink > 0,
        'use_auto_cot': needDeepThink == 3,
        'resend_for_regen': false,
        'enable_commerce_credit': false,
      },
      'evaluate_option': {'web_ab_params': ''},
      'local_conversation_id': conversationId ?? rand,
      'local_message_id': rand,
    };
    final stream = bridge!.chatStream(body);
    await for (final delta in stream) {
      yield delta;
    }
  }

  Stream<Map<String, dynamic>> _chatStreamProxy(
    List<ChatMessage> messages,
    int needDeepThink,
    String? conversationId,
  ) async* {
    final model = needDeepThink == 0
        ? 'doubao'
        : (needDeepThink == 1 ? 'doubao-think' : 'doubao-expert');
    final body = {
      'model': model,
      'messages':
          messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
      'stream': true,
      if (conversationId != null) 'conversation_id': conversationId,
    };
    try {
      final resp = await _dio.post(
        '$backendUrl/v1/chat/completions',
        data: jsonEncode(body),
        options: Options(
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          responseType: ResponseType.stream,
        ),
      );
      final stream = resp.data.stream as Stream<List<int>>;
      String buffer = '';
      await for (final chunk in stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          final t = line.trim();
          if (!t.startsWith('data:')) continue;
          final data = t.substring(5).trim();
          if (data == '[DONE]') return;
          try {
            final j = jsonDecode(data) as Map<String, dynamic>;
            if (j['conversation_id'] != null) {
              yield {'conversation_id': j['conversation_id']};
            }
            final choices = j['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map?;
              if (delta != null) {
                if (delta['reasoning_content'] != null) {
                  yield {'thinking': delta['reasoning_content']};
                }
                if (delta['content'] != null) {
                  yield {'text': delta['content']};
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      yield {'error': e.toString()};
    }
  }

  Future<String?> uploadImage(String filePath, String filename) async {
    if (!useBackend) return null;
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });
      final r = await _dio.post('$backendUrl/v1/images/upload',
          data: form, options: Options(headers: _authHeaders));
      if (r.data is Map) return r.data['url']?.toString();
    } catch (_) {}
    return null;
  }

  Future<UploadedFile?> uploadFile(String filePath, String filename) async {
    if (!useBackend) return null;
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });
      final r = await _dio.post('$backendUrl/v1/files',
          data: form, options: Options(headers: _authHeaders));
      if (r.data is Map) return UploadedFile.fromJson(Map.from(r.data));
    } catch (_) {}
    return null;
  }

  Future<String?> getFileDownloadUrl(String uri) async {
    if (!useBackend) return null;
    try {
      final r = await _dio.get('$backendUrl/v1/files/download',
          queryParameters: {'uri': uri},
          options: Options(headers: _authHeaders));
      if (r.data is Map) return r.data['url']?.toString();
    } catch (_) {}
    return null;
  }

  Future<List<GeneratedImage>> generateImage(String prompt,
      {String ratio = '1:1', String? refImageKey}) async {
    if (!useBackend) return [];
    try {
      final r = await _dio.post('$backendUrl/v1/images/generations',
          data: jsonEncode({
            'model': 'doubao-image',
            'prompt': prompt,
            'ratio': ratio,
            if (refImageKey != null) 'ref_image_key': refImageKey,
          }),
          options: Options(
              headers: {..._authHeaders, 'Content-Type': 'application/json'}));
      final list = <GeneratedImage>[];
      if (r.data is Map && r.data['data'] is List) {
        for (final it in r.data['data']) {
          list.add(GeneratedImage(
            url: it['url']?.toString() ?? '',
            revisedPrompt: it['revised_prompt']?.toString() ?? '',
          ));
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<GeneratedVideo>> generateVideo(String prompt,
      {String ratio = '16:9'}) async {
    if (!useBackend) return [];
    try {
      final r = await _dio.post('$backendUrl/v1/video/generations',
          data: jsonEncode({
            'model': 'doubao-video',
            'prompt': prompt,
            'ratio': ratio,
          }),
          options: Options(
              headers: {..._authHeaders, 'Content-Type': 'application/json'}));
      final list = <GeneratedVideo>[];
      if (r.data is Map && r.data['data'] is List) {
        for (final it in r.data['data']) {
          list.add(GeneratedVideo(
            videoUrl: it['video_url']?.toString() ?? '',
            coverUrl: it['cover_url']?.toString() ?? '',
            duration: (it['duration'] is num) ? it['duration'].toDouble() : 0,
            width: (it['width'] is num) ? it['width'].toInt() : 0,
            height: (it['height'] is num) ? it['height'].toInt() : 0,
          ));
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<GeneratedMusic>> generateMusic(String prompt,
      {String genre = 'Pop', String lyric = ''}) async {
    if (!useBackend) return [];
    try {
      final r = await _dio.post('$backendUrl/v1/audio/generations',
          data: jsonEncode({
            'model': 'doubao-music',
            'prompt': prompt,
            'genre': genre,
            if (lyric.isNotEmpty) 'lyric': lyric,
          }),
          options: Options(
              headers: {..._authHeaders, 'Content-Type': 'application/json'}));
      final list = <GeneratedMusic>[];
      if (r.data is Map && r.data['data'] is List) {
        for (final it in r.data['data']) {
          list.add(GeneratedMusic(
            audioUrl: it['audio_url']?.toString() ?? '',
            title: it['title']?.toString() ?? '',
            duration: (it['duration'] is num) ? it['duration'].toDouble() : 0,
            lyrics: it['lyrics']?.toString() ?? '',
            coverUrl: it['cover_url']?.toString() ?? '',
          ));
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  String _uuid() => DateTime.now().microsecondsSinceEpoch.toRadixString(16);
}
