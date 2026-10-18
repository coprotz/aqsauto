import 'package:aqs/features/utils/enum.dart';

class WallingFinishInput {
  WallType wallType;
  String plasterBoqCode; // plastering (internal / inside face)
  String plasterDecoBoqCode; // decoration for plastering (internal)
  String renderBoqCode; // rendering (external face)
  String renderDecoBoqCode; // decoration for rendering (external)

  WallingFinishInput({
    this.wallType = WallType.internal,
    this.plasterBoqCode = '',
    this.plasterDecoBoqCode = '',
    this.renderBoqCode = '',
    this.renderDecoBoqCode = '',
  });

  WallingFinishInput copy() => WallingFinishInput(
    wallType: wallType,
    plasterBoqCode: plasterBoqCode,
    plasterDecoBoqCode: plasterDecoBoqCode,
    renderBoqCode: renderBoqCode,
    renderDecoBoqCode: renderDecoBoqCode,
  );
}
