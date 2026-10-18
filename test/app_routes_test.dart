import 'package:aqs/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoutes', () {
    test('keeps the expected entry routes stable', () {
      expect(AppRoutes.landing, '/');
      expect(AppRoutes.dashboard, '/dashboard');
      expect(AppRoutes.projects, '/projects');
      expect(AppRoutes.projectBuildings, '/projects/:projectId/buildings');
      expect(
        AppRoutes.projectBuildingWorkspace,
        '/projects/:projectId/buildings/:buildingId/workspace',
      );
      expect(
        AppRoutes.drawingMeasurement,
        '/projects/:projectId/buildings/:buildingId/drawings/:drawingId/measure',
      );
    });

    test('keeps core workflow routes stable', () {
      expect(AppRoutes.projectDetail, '/project-detail');
      expect(AppRoutes.buildingDetail, '/building-detail');
      expect(AppRoutes.imageTakeoff, '/imageTakeoff');
      expect(AppRoutes.takeoff, '/takeoff');
    });

    test('builds clear project and building workspace URLs', () {
      expect(
        AppRoutes.projectBuildingsPath('project-1', 'Tactic Tabora'),
        '/projects/project-1/buildings?projectName=Tactic%20Tabora',
      );
      expect(
        AppRoutes.projectBuildingWorkspacePath(
          projectId: 'project-1',
          buildingId: 'building-1',
          projectName: 'Tactic Tabora',
          buildingName: 'Terminal Building',
          buildingCode: 'Part B1',
        ),
        '/projects/project-1/buildings/building-1/workspace'
        '?projectName=Tactic%20Tabora'
        '&buildingName=Terminal%20Building'
        '&buildingCode=Part%20B1',
      );
      expect(
        AppRoutes.drawingMeasurementPath(
          projectId: 'project-1',
          buildingId: 'building-1',
          drawingId: 'drawing-1',
          drawingTitle: 'Ground Floor',
          imageUrl: 'https://example.com/drawing.png',
        ),
        '/projects/project-1/buildings/building-1/drawings/drawing-1/measure'
        '?drawingTitle=Ground%20Floor'
        '&imageUrl=https%3A%2F%2Fexample.com%2Fdrawing.png',
      );
    });

    test('keeps BOQ workflow routes stable', () {
      expect(AppRoutes.boqTemplates, '/boq/templates');
      expect(AppRoutes.boqImportExcel, '/boq/import-excel');
      expect(AppRoutes.boqTemplatePickItems, '/boq/template-pick-items');
      expect(AppRoutes.boqTemplatesManage, '/boq/templates-manage');
    });
  });
}
