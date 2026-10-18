import 'dart:async';

/// One retained value and one upstream subscription per key, shared by pages.
/// Retain session data until account reset by default.
class SessionDataState {
  SessionDataState({
    this.idleLifetime,
    this.maxIdleEntries,
    this.idleDisconnectDelay,
  });
  final Duration? idleLifetime;
  final int? maxIdleEntries;
  final Duration? idleDisconnectDelay;
  final Map<Object, _Feed<dynamic>> _feeds = {};

  /// Return an already-emitted snapshot without waiting for another event.
  /// Null means that this query has not yet populated the shared session.
  T? latest<T>(Object key) {
    final feed = _feeds[key];
    if (feed is _Feed<T> && !feed.closed && feed.hasValue) {
      return feed.value as T;
    }
    return null;
  }

  Stream<T> watch<T>(Object key, Stream<T> Function() source) {
    return Stream<T>.multi((listener) {
      final subscription = _shared<T>(key, source).listen(
        listener.addSync,
        onError: listener.addErrorSync,
        onDone: listener.closeSync,
      );
      listener.onCancel = subscription.cancel;
      listener.onPause = subscription.pause;
      listener.onResume = subscription.resume;
    }, isBroadcast: true);
  }

  Stream<T> _shared<T>(Object key, Stream<T> Function() source) {
    final existing = _feeds[key];
    if (existing != null) return (existing as _Feed<T>).stream;
    late final _Feed<T> feed;
    feed = _Feed<T>(source, idleLifetime, idleDisconnectDelay, () {
      if (identical(_feeds[key], feed)) _feeds.remove(key);
    });
    _feeds[key] = feed;
    final idle = _feeds.entries.where((e) => e.value.idle).toList();
    for (final entry in idle.take(
      maxIdleEntries == null ? 0 : (idle.length - maxIdleEntries!).clamp(0, idle.length),
    )) {
      _feeds.remove(entry.key)?.close();
    }
    return feed.stream;
  }

  /// Call on sign-out/account changes. Never replay another account's data.
  void clear() {
    final feeds = _feeds.values.toList();
    _feeds.clear();
    for (final feed in feeds) {
      feed.close();
    }
  }
}

class _Feed<T> {
  _Feed(this.source, this.lifetime, this.disconnectDelay, this.onExpired) {
    stream = Stream<T>.multi((listener) {
      if (closed) {
        listener.closeSync();
        return;
      }
      timer?.cancel();
      disconnectTimer?.cancel();
      listeners.add(listener);
      if (hasValue) listener.addSync(value as T);
      listener.onCancel = () {
        listeners.remove(listener);
        if (!closed && listeners.isEmpty && lifetime != null)
          timer = Timer(lifetime!, () {
            close();
            onExpired();
          });
        if (!closed && listeners.isEmpty && disconnectDelay != null) {
          disconnectTimer = Timer(disconnectDelay!, () {
            final previous = subscription;
            subscription = null;
            previous?.cancel();
          });
        }
      };
      subscription ??= source().listen(
        (next) {
          value = next;
          hasValue = true;
          for (final sink in listeners.toList()) {
            sink.addSync(next);
          }
        },
        onError: (Object error, StackTrace stack) {
          // Do not replay stale/possibly revoked data after an access failure.
          value = null;
          hasValue = false;
          for (final sink in listeners.toList()) {
            sink.addErrorSync(error, stack);
          }
          close();
          onExpired();
        },
        onDone: () {
          close();
          onExpired();
        },
      );
    }, isBroadcast: true);
  }
  final Stream<T> Function() source;
  final Duration? lifetime;
  final Duration? disconnectDelay;
  final void Function() onExpired;
  late final Stream<T> stream;
  final listeners = <MultiStreamController<T>>{};
  StreamSubscription<T>? subscription;
  Timer? timer;
  Timer? disconnectTimer;
  T? value;
  bool hasValue = false, closed = false;
  bool get idle => listeners.isEmpty;
  void close() {
    if (closed) return;
    closed = true;
    timer?.cancel();
    disconnectTimer?.cancel();
    subscription?.cancel();
    value = null;
    for (final sink in listeners.toList()) {
      sink.closeSync();
    }
    listeners.clear();
  }
}
