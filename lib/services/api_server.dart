// 本地 OpenAI 兼容 API 服务器
// 复刻 doubao2api 的 unified_server：在安卓设备上暴露 /v1/* 端点，
// 让任何支持 OpenAI 协议的客户端 / Agent 都能把本机当作"豆包 API"使用。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'webview_bridge.dart';

class ApiServer {
  HttpServer? _server;
  final WebViewBridge bridge;
  String apiKey;
  int port;
  bool running = false;

  final List<Map<String, String>> logs = [];

  ApiServer({required this.bridge, this.apiKey = '', this.port = 9090});

  void _log(String method, String path, int status) {
    logs.insert(0, {
      'time': DateTime.now().toString().substring(11, 19),
      'method': method,
      'path': path,
      'status': '$status',
    });
    if (logs.length > 100) logs.removeLast();
  }

  Future<void> start() async {
    if (running) return;
    final router = Router();

    router.get('/health', (Request req) {
      _log('GET', '/health', 200);
      return _json({
        'status': 'ok',
        'logged_in': bridge.isReady,
        'consecutive_failures': 0,
        'needs_captcha': false,
        'last_error_code': 0,
      });
    });

    router.get('/v1/models', (Request req) {
      _log('GET', '/v1/models', 200);
      return _json({
        'object': 'list',
        'data': [
          {'id': 'doubao', 'object': 'model', 'owned_by': 'doubao', 'created': 0},
          {'id': 'doubao-think', 'object': 'model', 'owned_by': 'doubao', 'created': 0},
          {'id': 'doubao-expert', 'object': 'model', 'owned_by': 'doubao', 'created': 0},
          {'id': 'doubao-image', 'object': 'model', 'owned_by': 'doubao', 'created': 0},
          {'id': 'doubao-video', 'object': 'model', 'owned_by': 'doubao', 'created': 0},
          {'id': 'doubao-music', 'object': 'model', 'owned_by': 'doubao', 'created': 0},
        ],
      });
    });

    router.get('/auth/status', (Request req) {
      _log('GET', '/auth/status', 200);
      return _json({
        'logged_in': bridge.isReady,
        'is_ready_flag': bridge.isReady,
        'login_button_visible': !bridge.isReady,
        'page_url': 'https://www.doubao.com/chat/',
        'device_id': '',
        'web_id': '',
      });
    });

    router.post('/v1/chat/completions', (Request req) async {
      if (!_checkAuth(req, '/v1/chat/completions')) {
        return _error(401, 'authentication failed');
      }
      final body = await req.readAsString();
      Map<String, dynamic> j;
      try {
        j = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        _log('POST', '/v1/chat/completions', 400);
        return _error(400, 'invalid json');
      }
      final model = j['model']?.toString() ?? 'doubao';
      final wantStream = j['stream'] == true;
      final needDeepThink = model.contains('expert')
          ? 3
          : (model.contains('think') ? 1 : 0);
      final messages = (j['messages'] as List?) ?? [];
      final text = _extractText(messages);

      if (text.isEmpty) {
        _log('POST', '/v1/chat/completions', 400);
        return _error(400, 'empty messages');
      }
      if (!bridge.isReady) {
        _log('POST', '/v1/chat/completions', 503);
        return _error(503, 'not logged in');
      }

      final payload = _buildPayload(text, needDeepThink);

      if (!wantStream) {
        final buf = StringBuffer();
        final thinkBuf = StringBuffer();
        try {
          await for (final d in bridge.chatStream(payload)) {
            if (d['text'] != null) buf.write(d['text']);
            if (d['thinking'] != null) thinkBuf.write(d['thinking']);
            if (d['done'] == true) break;
          }
        } catch (e) {
          return _error(502, 'upstream error: $e');
        }
        _log('POST', '/v1/chat/completions', 200);
        return _json({
          'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
          'object': 'chat.completion',
          'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'model': model,
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': buf.toString(),
                if (thinkBuf.isNotEmpty) 'reasoning_content': thinkBuf.toString(),
              },
              'finish_reason': 'stop',
            }
          ],
          'usage': {'prompt_tokens': 0, 'completion_tokens': 0, 'total_tokens': 0},
        });
      } else {
        _log('POST', '/v1/chat/completions', 200);
        return Response.ok(
          _sseStream(bridge.chatStream(payload), model),
          headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
          },
        );
      }
    });

    router.post('/v1/images/generations', (Request req) async {
      if (!_checkAuth(req, '/v1/images/generations')) return _error(401, 'auth');
      final body = await req.readAsString();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final prompt = j['prompt']?.toString() ?? '';
      final images = await _generateMedia(prompt, 2010);
      _log('POST', '/v1/images/generations', 200);
      return _json({
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'data': images.map((u) => {'url': u, 'revised_prompt': prompt}).toList(),
      });
    });

    router.post('/v1/video/generations', (Request req) async {
      if (!_checkAuth(req, '/v1/video/generations')) return _error(401, 'auth');
      final body = await req.readAsString();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final prompt = j['prompt']?.toString() ?? '';
      final videos = await _generateMedia(prompt, 2020);
      _log('POST', '/v1/video/generations', 200);
      return _json({
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'data': videos.map((u) => {'video_url': u, 'cover_url': '', 'duration': 0}).toList(),
      });
    });

    router.post('/v1/audio/generations', (Request req) async {
      if (!_checkAuth(req, '/v1/audio/generations')) return _error(401, 'auth');
      final body = await req.readAsString();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final prompt = j['prompt']?.toString() ?? '';
      final audios = await _generateMedia(prompt, 2005);
      _log('POST', '/v1/audio/generations', 200);
      return _json({
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'data': audios
            .map((u) => {'audio_url': u, 'title': '', 'duration': 0, 'lyrics': '', 'cover_url': ''})
            .toList(),
      });
    });

    router.post('/v1/session/qr-login', (Request req) {
      _log('POST', '/v1/session/qr-login', 200);
      return _json({'status': 'pending', 'message': '请在 App 内网页完成登录'});
    });
    router.get('/v1/session/qr-login', (Request req) {
      return _json({'status': bridge.isReady ? 'success' : 'pending'});
    });

    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    running = true;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    running = false;
  }

  bool _checkAuth(Request req, String path) {
    if (apiKey.isEmpty || apiKey == 'any') return true;
    final auth = req.headers['authorization'] ?? '';
    final ok = auth == 'Bearer $apiKey';
    if (!ok) _log('POST', path, 401);
    return ok;
  }

  String _extractText(List messages) {
    for (final m in messages.reversed) {
      if (m is Map && m['role'] == 'user') {
        final c = m['content'];
        if (c is String) return c;
        if (c is List) {
          for (final part in c) {
            if (part is Map && part['type'] == 'text') {
              return part['text']?.toString() ?? '';
            }
          }
        }
      }
    }
    return '';
  }

  Map<String, dynamic> _buildPayload(String text, int needDeepThink) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = '${ts}_${ts.toRadixString(16)}';
    return {
      'messages': [
        {
          'content': jsonEncode({'text': text}),
          'content_type': 2001,
          'attachments': [],
          'references': [],
        }
      ],
      'completion_option': {
        'is_regen': false,
        'with_suggest': true,
        'need_create_conversation': true,
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
      'local_conversation_id': rand,
      'local_message_id': rand,
    };
  }

  Stream<List<int>> _sseStream(
      Stream<Map<String, dynamic>> src, String model) async* {
    final id = 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    yield utf8.encode(_chunk(id, created, model, {'role': 'assistant'}, null));
    await for (final d in src) {
      if (d['done'] == true) break;
      if (d['error'] != null) {
        yield utf8.encode(_chunk(id, created, model, {}, 'error'));
        break;
      }
      if (d['thinking'] != null) {
        yield utf8.encode(
            _chunk(id, created, model, {'reasoning_content': d['thinking']}, null));
      }
      if (d['text'] != null) {
        yield utf8.encode(_chunk(id, created, model, {'content': d['text']}, null));
      }
    }
    yield utf8.encode(_chunk(id, created, model, {}, 'stop'));
    yield utf8.encode('data: [DONE]\n\n');
  }

  String _chunk(String id, int created, String model, Map delta, String? finish) {
    return 'data: ${jsonEncode({
          'id': id,
          'object': 'chat.completion.chunk',
          'created': created,
          'model': model,
          'choices': [
            {'index': 0, 'delta': delta, 'finish_reason': finish}
          ],
        })}\n\n';
  }

  Future<List<String>> _generateMedia(String prompt, int contentType) async {
    final urls = <String>[];
    final payload = _buildPayload(prompt, 0);
    final msgs = payload['messages'] as List;
    if (msgs.isNotEmpty) {
      final first = msgs[0] as Map;
      first['content_type'] = contentType;
    }
    try {
      await for (final d in bridge.chatStream(payload)) {
        if (d['image'] != null) urls.add(d['image'].toString());
        if (d['done'] == true) break;
      }
    } catch (_) {}
    return urls;
  }

  Response _json(Map<String, dynamic> data) {
    return Response.ok(
      jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _error(int code, String msg) {
    return Response(
      code,
      body: jsonEncode({'error': {'message': msg, 'type': 'error'}}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
