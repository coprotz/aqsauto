import 'package:cloud_firestore/cloud_firestore.dart';
import 'session_data_state.dart';

/// Screens consume shared session state. Firestore only feeds the state once
/// per query; its local write events and server confirmations update all views.
final firestoreState = SessionDataState();

extension StatefulQuery<T> on Query<T> {
  /// Read the latest shared snapshot synchronously when present.
  QuerySnapshot<T>? get stateSnapshot =>
      firestoreState.latest<QuerySnapshot<T>>(('query', this));

  Stream<QuerySnapshot<T>> stateSnapshots() =>
      firestoreState.watch(('query', this), () => snapshots(includeMetadataChanges: true));
}

extension StatefulDocument<T> on DocumentReference<T> {
  DocumentSnapshot<T>? get stateSnapshot =>
      firestoreState.latest<DocumentSnapshot<T>>(('document', this));
  Stream<DocumentSnapshot<T>> stateSnapshots() =>
      firestoreState.watch(('document', this), () => snapshots());
}
