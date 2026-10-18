import 'dart:async';
import 'package:flutter/material.dart';

/// Keeps the page visible while preventing actions on partially loaded data.
class IpcLoadingOverlay extends StatelessWidget {
  const IpcLoadingOverlay({super.key, required this.loading, required this.child, this.message = 'Loading IPC data…', this.progress, this.detail});
  final bool loading;
  final Widget child;
  final String message;
  final double? progress;
  final String? detail;

  @override
  Widget build(BuildContext context) => Stack(children: [
    child,
    if (loading) ...[
      const Positioned.fill(child: ModalBarrier(dismissible: false, color: Color(0x99F6F8FC))),
      Positioned.fill(child: Center(child: Semantics(
        liveRegion: true,
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26), child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: progress == 0 ? null : progress?.clamp(0, 1), color: const Color(0xFF195BFA)),
              if (progress != null) ...[
                const SizedBox(height: 12),
                Text('${(progress!.clamp(0, 1) * 100).floor()}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 18),
              Text(message, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF173565))),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(detail!, textAlign: TextAlign.center),
              ],
            ],
          )),
        ),
      ))),
    ],
  ]);
}

class IpcLoadingScope extends StatefulWidget {
  const IpcLoadingScope({super.key, required this.sources, required this.child});
  final List<Stream<Object?>> sources;
  final Widget child;
  @override
  State<IpcLoadingScope> createState() => _IpcLoadingScopeState();
}

class _IpcLoadingScopeState extends State<IpcLoadingScope> {
  final subscriptions = <StreamSubscription<Object?>>[];
  final ready = <int>{};
  final failed = <int>{};
  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.sources.length; i++) {
      final index = i;
      subscriptions.add(widget.sources[i].listen((_) {
        if (mounted) setState(() { ready.add(index); failed.remove(index); });
      }, onError: (Object _) {
        if (mounted) setState(() { ready.add(index); failed.add(index); });
      }, onDone: () {
        if (mounted && !ready.contains(index)) setState(() { ready.add(index); failed.add(index); });
      }));
    }
  }
  @override
  void dispose() {
    for (final subscription in subscriptions) { subscription.cancel(); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => IpcLoadingOverlay(
    loading: ready.length < widget.sources.length,
    child: Column(children: [
      if (failed.isNotEmpty) const Material(color: Color(0xFFFFF3E0), child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('Some IPC data could not load. Check your connection and reopen this page.'),
      )),
      Expanded(child: widget.child),
    ]),
  );
}
