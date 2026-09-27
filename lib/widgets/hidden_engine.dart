import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/app_state.dart';

/// 隐藏的本地引擎：全 App 生命周期内驻留一个不可见的 WebView，
/// 加载豆包网页以复用其 JS 完成签名，实现开箱即用的直连。
class HiddenEngine extends StatefulWidget {
  const HiddenEngine({super.key});

  @override
  State<HiddenEngine> createState() => _HiddenEngineState();
}

class _HiddenEngineState extends State<HiddenEngine> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      _controller = state.bridge.createController(
        onPageFinished: () {
          state.markEngineReady();
        },
      );
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      bottom: 0,
      width: 1,
      height: 1,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: WebViewWidget(controller: _controller!),
        ),
      ),
    );
  }
}
