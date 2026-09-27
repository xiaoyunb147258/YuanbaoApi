import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final logs = state.server.logs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('请求日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => state.clearLogs(),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text('暂无请求', style: TextStyle(color: Colors.grey)))
          : ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final l = logs[i];
                final status = int.tryParse(l['status'] ?? '0') ?? 0;
                final color = status >= 400
                    ? Colors.red
                    : (status >= 300 ? Colors.orange : Colors.green);
                return ListTile(
                  dense: true,
                  leading: Text(l['time'] ?? '',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  title: Text('${l['method']} ${l['path']}',
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(l['status'] ?? '',
                        style: TextStyle(
                            fontSize: 12, color: color, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
    );
  }
}
