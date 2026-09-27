// 本地 OpenAI 兼容 API 服务器
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'webview_bridge.dart';
import 'doubao_client.dart';

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

  DoubaoClient _client() => DoubaoClient(
        deviceId: bridge.deviceId,
        webId: bridge.webId,
        fp: bridge.fp,
      );

  Future<void> start() async {
    if (running) return;
    final router = Router();

    router.get('/health', (Request req) {
      _log('GET', '/health', 200);
      return _json({
        'status': 'ok',
        'logged_in': bridge.loggedIn,
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
        'logged_in': bridge.loggedIn,
        'is_ready_flag': bridge.isReady,
        'login_button_visible': !bridge.loggedIn,
        'page_url': 'https://www.doubao.com/chat/',
        'device_id': bridge.deviceId,
        'web_id': bridge.webId,
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
        return _error(400, 'invalid json');
      }
      final model = j['model']?.toString() ?? 'doubao';
      final wantStream = j['stream'] == true;
      final needDeepThink =
          model.contains('expert') ? 3 : (model.contains('think') ? 1 : 0);
      final messages = (j['messages'] as List?) ?? [];
      final text = _extractText(messages);
      final convId = j['conversation_id']?.toString();

      if (text.isEmpty) return _error(400, 'empty messages');
      if (!bridge.isReady) return _error(503, 'not logged in');

      final c = _client();
      final url = '/chat/completion?${c.buildQueryString()}';
      final payload = c.buildChatPayload(text, needDeepThink, convId);
      final payloadJson = jsonEncode(payload);

      if (!wantStream) {
        final buf = StringBuffer();
        String newConv = convId ?? '';
        try {
          await for (final d
              in bridge.chatStream(url: url, payloadJson: payloadJson)) {
            if (d['text'] != null) buf.write(d['text']);
            if (d['conversation_id'] != null &&
                (newConv.isEmpty || newConv == '0')) {
              newConv = d['conversation_id'].toString();
            }
            if (d['error'] != null) return _error(502, d['error'].toString());
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
          'conversation_id': newConv,
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': buf.toString(),
                'conversation_id': newConv,
              },
              'finish_reason': 'stop',
            }
          ],
          'usage': {'prompt_tokens': 0, 'completion_tokens': 0, 'total_tokens': 0},
        });
      } else {
        _log('POST', '/v1/chat/completions', 200);
        return Response.ok(
          _sseStream(bridge.chatStream(url: url, payloadJson: payloadJson), model),
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
      final j = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final prompt = j['prompt']?.toString() ?? '';
      final ratio = j['ratio']?.toString();
      final c = _client();
      final url = '/samantha/chat/completion?${c.buildQueryString()}';
      final payload = c.buildSamanthaPayload(
          text: prompt, contentType: 2009, skillType: 3, ratio: ratio);
      final raw = await bridge.fetchOnce(
          url: url, payloadJson: jsonEncode(payload), timeoutSeconds: 120);
      final images = raw.startsWith('__ERROR__:') ? [] : c.parseImages(raw);
      _log('POST', '/v1/images/generations', 200);
      return _json({
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'data': images
            .map((im) => {'url': im['url'], 'revised_prompt': prompt})
            .toList(),
      });
    });

    router.post('/v1/video/generations', (Request req) async {
      if (!_checkAuth(req, '/v1/video/generations')) return _error(401, 'auth');
      final j = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final prompt = j['prompt']?.toString() ?? '';
      final ratio = j['ratio']?.toString();
      final c = _client();
      final url = '/samantha/chat/completion?${c.buildQueryString()}';
      final payload = c.buildSamanthaPayload(
          text: prompt, contentType: 2020, skillType: 17, ratio: ratio);
      final raw = await bridge.fetchOnce(
          url: url, payloadJson: jsonEncode(payload), timeoutSeconds: 60);
      var videos = <Map<String, dynamic>>[];
      if (!raw.startsWith('__ERROR__:')) {
        final taskId = c.extractVideoTaskId(raw);
        if (taskId != null) {
          final poll =
              await bridge.fetchOnce(url: url, payloadJson: jsonEncode({'task_id': taskId, 'event_id': 0}), timeoutSeconds: 300);
          if (!poll.startsWith('__ERROR__:')) {
            videos = c.parseVideos(poll);
          }
        }
      }
      _log('POST', '/v1/video/generations', 200);
      return _json({
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'data': videos,
      });
    });

    router.post('/v1/audio/generations', (Request req) async {
      if (!_checkAuth(req, '/v1/audio/generations')) return _error(401, 'auth');
      final j = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final prompt = j['prompt']?.toString() ?? '';
      final lyric = j['lyric']?.toString();
      final genre = j['genre']?.toString();
      final c = _client();
      final url = '/samantha/chat/completion?${c.buildQueryString()}';
      final payload = c.buildSamanthaPayload(
          text: prompt, contentType: 2005, skillType: 9, lyric: lyric, genre: genre);
      final raw = await bridge.fetchOnce(
          url: url, payloadJson: jsonEncode(payload), timeoutSeconds: 300);
      final tracks = raw.startsWith('__ERROR__:') ? [] : c.parseMusic(raw);
      _log('POST', '/v1/audio/generations', 200);
      return _json({
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'data': tracks,
      });
    });

    router.post('/v1/files', (Request req) {
      _log('POST', '/v1/files', 501);
      return _error(501, 'file upload not implemented in this build');
    });
    router.post('/v1/images/upload', (Request req) {
      _log('POST', '/v1/images/upload', 501);
      return _error(501, 'image upload not implemented in this build');
    });

    router.post('/v1/session/qr-login', (Request req) {
      _log('POST', '/v1/session/qr-login', 200);
      return _json({'status': 'pending', 'message': '请在 App 内网页完成登录'});
    });
    router.get('/v1/session/qr-login', (Request req) {
      return _json({'status': bridge.loggedIn ? 'success' : 'pending'});
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

  Stream<List<int>> _sseStream(
      Stream<Map<String, dynamic>> src, String model) async* {
    final id = 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    yield utf8.encode(_chunk(id, created, model, {'role': 'assistant'}, null));
    await for (final d in src) {
      if (d['error'] != null) {
        yield utf8.encode(_chunk(id, created, model, {}, 'error'));
        break;
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

  Response _json(Map<String, dynamic> data) {
    return Response.ok(jsonEncode(data),
        headers: {'Content-Type': 'application/json'});
  }

  Response _error(int code, String msg) {
    return Response(code,
        body: jsonEncode({'error': {'message': msg, 'type': 'error'}}),
        headers: {'Content-Type': 'application/json'});
  }
}
