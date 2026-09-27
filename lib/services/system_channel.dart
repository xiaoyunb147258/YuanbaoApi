// 系统能力通道：悬浮窗、电池优化白名单、前台服务保活
import 'package:flutter/services.dart';

class SystemChannel {
  static const MethodChannel _ch = MethodChannel('yuanbao/system');

  /// 请求悬浮窗权限（返回是否已授予）
  static Future<bool> requestOverlayPermission() async {
    try {
      final r = await _ch.invokeMethod<bool>('requestOverlay');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 开启/关闭悬浮球
  static Future<bool> toggleFloatingBall(bool on) async {
    try {
      final r = await _ch.invokeMethod<bool>('toggleFloatingBall', {'on': on});
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 请求忽略电池优化（保活）
  static Future<bool> requestIgnoreBattery() async {
    try {
      final r = await _ch.invokeMethod<bool>('requestIgnoreBattery');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 启动/停止前台服务
  static Future<bool> toggleForegroundService(bool on) async {
    try {
      final r = await _ch.invokeMethod<bool>('toggleForegroundService', {'on': on});
      return r ?? false;
    } catch (_) {
      return false;
    }
  }
}
