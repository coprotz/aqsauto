import 'package:cloud_firestore/cloud_firestore.dart';

abstract class LinksContext {
  String get projectId;
  String get buildingId;
  String get drawingId;
  CollectionReference<Map<String, dynamic>> get measurementsRef;
}
