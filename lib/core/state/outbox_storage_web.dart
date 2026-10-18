import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

final _locks = <String, Future<void>>{};
Future<void> _own(String user) => _locks.putIfAbsent(user, () {
  final ready = Completer<void>();
  try {
    web.window.navigator.locks.request(
      'aqs.execution.outbox.$user',
      web.LockOptions(ifAvailable: true),
      ((web.Lock? lock) {
        if (lock == null) {
          ready.completeError(
            StateError(
              'Offline saving is open in another tab. Close that tab, then reload this one.',
            ),
          );
          return null;
        }
        ready.complete();
        // Hold the lock for this tab's lifetime: two tabs must never overwrite
        // each other's pending queue. The browser releases it on tab close.
        return Completer<JSAny?>().future.toJS;
      }).toJS,
    ).toDart.catchError((Object error) {
      if (!ready.isCompleted) ready.completeError(error);
      return null;
    });
  } catch (error) {
    ready.completeError(StateError('Safe device storage is unavailable: $error'));
  }
  return ready.future;
});

Future<String?> readOutbox(String user) async {
  await _own(user);
  return web.window.localStorage.getItem('aqs.execution.outbox.$user');
}

Future<void> writeOutbox(String user, String value) async {
  await _own(user);
  web.window.localStorage.setItem('aqs.execution.outbox.$user', value);
}
