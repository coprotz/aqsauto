import 'dart:math';
import 'package:flutter/material.dart';

double distPx(Offset a, Offset b) {
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return sqrt(dx * dx + dy * dy);
}

/// Convert pixel distance to meters using scale.
/// Example: if you already have "metersPerPixel" => lengthM = px * metersPerPixel
double pxToMeters(double px, double metersPerPixel) => px * metersPerPixel;

/// Concrete volume = b * h * L
double calcConcreteM3({
  required double bM,
  required double hM,
  required double lengthM,
}) => bM * hM * lengthM;

/// Formwork typical for beam:
/// - sides only: 2*h*L
/// - sides + soffit: (2*h + b)*L
double calcFormworkM2({
  required double bM,
  required double hM,
  required double lengthM,
  required bool includeSoffit,
}) {
  final perM = includeSoffit ? (2 * hM + bM) : (2 * hM);
  return perM * lengthM;
}
