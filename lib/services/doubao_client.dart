// 豆包协议层 - 严格复刻 doubao2api browser_client.py 的 payload 与解析
import 'dart:convert';

class DoubaoClient {
  static const String BOT_ID = '7338286299411103781';

  // 由 bridge 提供的设备参数
  String deviceId;
  String webId;
  String fp;
  DoubaoClient({this.deviceId = '', this.webId = '', this.fp = ''});

  /// 复刻 _build_query_params
  String buildQueryString() {
    final p = <String, String>{
      'aid': '497858',
      'device_id': deviceId,
      'device_platform': 'web',
      'fp': fp,
      'language': 'zh',
      'pc_version': '3.19.4',
      'pkg_type': 'release_version',
      'real_aid': '497858',
      'region': '',
      'samantha_web': '1',
      'sys_region': '',
      'tea_uuid': webId,
      'use-olympus-account': '1',
      'version_code': '20800',
      'web_id': webId,
      'web_tab_id': uuid(),
    };
    final keys = p.keys.toList()..sort();
    return keys.map((k) => '$k=${p[k]}').join('&');
  }

  /// 复刻 chat_completion 的 payload
  Map<String, dynamic> buildChatPayload(
      String text, int needDeepThink, String? conversationId,
      [String? localConvId]) {
    final needCreate =
        conversationId == null || conversationId.isEmpty || conversationId == '0';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nowSec = nowMs ~/ 1000;
    final localId = localConvId ?? 'local_${nowMs}';
    return {
      'client_meta': {
        'local_conversation_id': localId,
        'conversation_id': needCreate ? '' : (conversationId ?? ''),
        'bot_id': BOT_ID,
        'last_section_id': '',
        'last_message_index': null,
      },
      'messages': [
        {
          'local_message_id': uuid(),
          'content_block': [
            {
              'block_type': 10000,
              'content': {
                'text_block': {
                  'text': text,
                  'icon_url': '',
                  'icon_url_dark': '',
                  'summary': ''
                },
                'pc_event_block': '',
              },
              'block_id': uuid(),
              'parent_id': '',
              'meta_info': [],
              'append_fields': [],
            }
          ],
          'message_status': 0,
        }
      ],
      'option': {
        'send_message_scene': '',
        'create_time_ms': nowMs,
        'collect_id': '',
        'is_audio': false,
        'answer_with_suggest': false,
        'tts_switch': false,
        'need_deep_think': needDeepThink,
        'click_clear_context': false,
        'from_suggest': false,
        'is_regen': false,
        'is_replace': false,
        'disable_sse_cache': false,
        'select_text_action': '',
        'resend_for_regen': false,
        'scene_type': 0,
        'unique_key': uuid(),
        'start_seq': 0,
        'need_create_conversation': needCreate,
        'regen_query_id': <dynamic>[],
        'edit_query_id': <dynamic>[],
        'regen_instruction': '',
        'no_replace_for_regen': false,
        'message_from': 0,
        'shared_app_name': '',
        'shared_app_id': '',
        'sse_recv_event_options': {'support_chunk_delta': true},
        'is_ai_playground': false,
        'recovery_option': {
          'is_recovery': false,
          'req_create_time_sec': nowSec,
          'append_sse_event_scene': 0,
        },
        'message_storage_type': 0,
      },
      'ext': {
        'use_deep_think': '$needDeepThink',
        'fp': fp,
        'collection_id': '',
        'commerce_credit_config_enable': '0',
        'sub_conv_firstmet_type': needCreate ? '1' : '0',
      },
    };
  }

  /// 复刻 samantha payload
  Map<String, dynamic> buildSamanthaPayload({
    required String text,
    required int contentType,
    required int skillType,
    String? ratio,
    String? lyric,
    String? genre,
  }) {
    final cd = <String, dynamic>{'text': text};
    if (ratio != null) cd['ratio'] = ratio;
    if (lyric != null) cd['lyric'] = lyric;
    if (genre != null) cd['genre'] = genre;
    return {
      'messages': [
        {
          'content': jsonEncode(cd),
          'content_type': contentType,
          'attachments': <dynamic>[],
          'references': <dynamic>[],
          'skill': {
            'skill_type': skillType,
            'skill_type_no_default': skillType,
            'skill_id': '$skillType',
            'skill_id_no_default': '$skillType',
          },
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
        'use_deep_think': false,
        'use_auto_cot': false,
        'resend_for_regen': false,
        'enable_commerce_credit': false,
        'action_bar_skill_id': skillType,
      },
      'evaluate_option': {'web_ab_params': ''},
      'local_conversation_id': uuid(),
      'local_message_id': uuid(),
    };
  }

  // ---- 解析 ----

  List<Map<String, dynamic>> parseSamanthaSse(String raw) {
    final out = <Map<String, dynamic>>[];
    for (final block in raw.split('\n\n')) {
      if (block.trim().isEmpty) continue;
      String ds = '';
      for (final line in block.trim().split('\n')) {
        if (line.startsWith('data:')) ds = line.substring(5).trim();
      }
      if (ds.isEmpty) continue;
      try {
        final e = jsonDecode(ds);
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      } catch (_) {}
    }
    return out;
  }

  Map<String, dynamic> asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      try {
        final p = jsonDecode(v);
        if (p is Map) return Map<String, dynamic>.from(p);
      } catch (_) {}
    }
    return {};
  }

  /// 从 samantha 响应提取图片 URL（content_type=2010）
  List<Map<String, dynamic>> parseImages(String raw) {
    final images = <Map<String, dynamic>>[];
    for (final data in parseSamanthaSse(raw)) {
      if (data['event_type'] != 2001) continue;
      final ed = asMap(data['event_data']);
      final msg = asMap(ed['message']);
      if (msg['content_type'] != 2010) continue;
      final content = asMap(msg['content']);
      final list = content['data'] is List ? content['data'] as List : <dynamic>[];
      for (final item in list) {
        if (item is! Map) continue;
        final ori = asMap(item['image_ori']);
        final rawImg = asMap(item['image_raw']);
        final thumb = asMap(item['image_thumb']);
        images.add({
          'key': item['key'] ?? '',
          'url': ori['url'] ?? rawImg['url'] ?? thumb['url'] ?? '',
          'width': ori['width'] ?? thumb['width'] ?? 0,
          'height': ori['height'] ?? thumb['height'] ?? 0,
        });
      }
    }
    return images;
  }

  /// 提取视频 task_id（fin_reason.async_task.id）
  String? extractVideoTaskId(String raw) {
    for (final data in parseSamanthaSse(raw)) {
      if (data['event_type'] != 2001) continue;
      final ed = asMap(data['event_data']);
      final fr = asMap(ed['fin_reason']);
      if (fr['reason'] == 1) {
        final at = asMap(fr['async_task']);
        final id = at['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  /// 解析视频结果（content_type=2021）
  List<Map<String, dynamic>> parseVideos(String raw) {
    final videos = <Map<String, dynamic>>[];
    for (final data in parseSamanthaSse(raw)) {
      if (data['event_type'] != 2001) continue;
      final ed = asMap(data['event_data']);
      final msg = asMap(ed['message']);
      if (msg['content_type'] != 2021) continue;
      final content = asMap(msg['content']);
      final list =
          content['data'] is List ? content['data'] as List : <dynamic>[content];
      for (final item in list) {
        if (item is! Map) continue;
        var url = item['video_url']?.toString() ?? item['url']?.toString() ?? '';
        if (url.isEmpty) {
          final vmStr = item['video_model'];
          if (vmStr != null) {
            final vm = vmStr is String ? asMap(vmStr) : asMap(vmStr);
            final vlist = vm['video_list'];
            if (vlist is Map) {
              for (final vinfo in vlist.values) {
                final b64 = vinfo is Map ? vinfo['main_url']?.toString() : null;
                if (b64 != null && b64.isNotEmpty) {
                  try {
                    url = utf8.decode(base64Decode(b64), allowMalformed: true);
                  } catch (_) {}
                  break;
                }
              }
            }
          }
        }
        final cover = asMap(item['cover']);
        if (url.isNotEmpty) {
          videos.add({
            'video_url': url,
            'cover_url': item['cover_url'] ?? cover['url'] ?? '',
            'width': item['width'] ?? 0,
            'height': item['height'] ?? 0,
            'duration': item['duration'] ?? 0,
          });
        }
      }
    }
    return videos;
  }

  /// 解析音乐（content_type=2006/2004 的 tasks）
  List<Map<String, dynamic>> parseMusic(String raw) {
    Map<String, dynamic>? finalContent;
    for (final data in parseSamanthaSse(raw)) {
      if (data['event_type'] != 2001) continue;
      final ed = asMap(data['event_data']);
      final msg = asMap(ed['message']);
      final ct = msg['content_type'];
      if (ct != 2006 && ct != 2004) continue;
      finalContent = asMap(msg['content']);
    }
    if (finalContent == null) return [];
    final tasks = finalContent['tasks'];
    final list = tasks is Map ? tasks.values.toList() : (tasks as List? ?? []);
    final tracks = <Map<String, dynamic>>[];
    for (final task in list) {
      if (task is! Map) continue;
      var audio = '';
      double dur = 0;
      final vmStr = task['video_model'];
      if (vmStr != null) {
        final vm = vmStr is String ? asMap(vmStr) : asMap(vmStr);
        dur = (vm['video_duration'] is num) ? vm['video_duration'].toDouble() : 0;
        final vlist = vm['video_list'];
        if (vlist is Map) {
          for (final vinfo in vlist.values) {
            final b64 = vinfo is Map ? vinfo['main_url']?.toString() : null;
            if (b64 != null && b64.isNotEmpty) {
              try {
                audio = utf8.decode(base64Decode(b64), allowMalformed: true);
              } catch (_) {}
              break;
            }
          }
        }
      }
      final cover = asMap(task['cover']);
      final coverOri = asMap(cover['image_ori']);
      if (audio.isNotEmpty || task['title'] != null) {
        tracks.add({
          'audio_url': audio,
          'title': task['title'] ?? '',
          'lyrics': task['lyric'] ?? '',
          'duration': dur,
          'cover_url': coverOri['url'] ?? '',
        });
      }
    }
    return tracks;
  }

  String uuid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
      '-' +
      (DateTime.now().microsecond % 65536).toRadixString(16);
}
