class AppRoutes {
  // Existing
  static const projects = '/projects';
  static const landing = '/';
  static const about = '/about';
  static const contact = '/contact';
  static const imageTakeoff = '/imageTakeoff';
  static const projectDetail = '/project-detail';
  static const takeoff = '/takeoff';
  static const buildingDetail = '/building-detail';

  static const dashboard = '/dashboard';
  static const admin = '/admin';
  static const tutorialVideos = '/tutorial-videos';
  static const adminTutorialVideos = '/admin/tutorial-videos';
  static const inviteAccept = '/invite/:token';
  static const projectBuildings = '/projects/:projectId/buildings';
  static const projectBuildingWorkspace =
      '/projects/:projectId/buildings/:buildingId/workspace';
  static const drawingMeasurement =
      '/projects/:projectId/buildings/:buildingId/drawings/:drawingId/measure';

  static String projectBuildingsPath(String projectId, String projectName) {
    return '/projects/${Uri.encodeComponent(projectId)}/buildings'
        '?projectName=${_encodeQueryValue(projectName)}';
  }

  static String projectBuildingWorkspacePath({
    required String projectId,
    required String buildingId,
    required String projectName,
    required String buildingName,
    required String buildingCode,
    int? tab,
  }) {
    return '/projects/${Uri.encodeComponent(projectId)}'
        '/buildings/${Uri.encodeComponent(buildingId)}/workspace'
        '?projectName=${_encodeQueryValue(projectName)}'
        '&buildingName=${_encodeQueryValue(buildingName)}'
        '&buildingCode=${_encodeQueryValue(buildingCode)}'
        '${tab == null ? '' : '&tab=$tab'}';
  }

  static String drawingMeasurementPath({
    required String projectId,
    required String buildingId,
    required String drawingId,
    required String drawingTitle,
    required String imageUrl,
  }) {
    return '/projects/${Uri.encodeComponent(projectId)}'
        '/buildings/${Uri.encodeComponent(buildingId)}'
        '/drawings/${Uri.encodeComponent(drawingId)}/measure'
        '?drawingTitle=${_encodeQueryValue(drawingTitle)}'
        '&imageUrl=${_encodeQueryValue(imageUrl)}';
  }

  static String _encodeQueryValue(String value) =>
      Uri.encodeQueryComponent(value).replaceAll('+', '%20');

  // BOQ templates
  static const boqTemplates = '/boq/templates';
  static const boqTemplateItems = '/boq/templates/items';

  // BOQ Excel import into project
  static const boqImportExcel = '/boq/import-excel';

  // BOQ add-from-template flow
  static const boqTemplatePickDialog =
      '/boq/template-pick-dialog'; // optional if you want as page
  static const boqTemplatePickItems = '/boq/template-pick-items';

  // templates management (optional separate module)
  static const boqTemplatesManage = '/boq/templates-manage';
  static const boqTemplateItemsManage = '/boq/template-items-manage';

  static const register = '/register';
  static const login = '/login';
  static const createProject = '/create-project';
  static const buildUpRates = '/build-up-rates';
  static const labourRates = '/labour-rates';
  static const buildUpRateNew = '/build-up-rates/new';
  static const buildUpRateResources = '/build-up-rates/resources';
  static const buildUpRateDetails = '/build-up-rates/:rateId';
  static const buildUpRateEdit = '/build-up-rates/:rateId/edit';
  static String buildUpRateDetailsPath(String rateId) =>
      '/build-up-rates/${Uri.encodeComponent(rateId)}';
  static String buildUpRateEditPath(String rateId) =>
      '/build-up-rates/${Uri.encodeComponent(rateId)}/edit';
  static const pricing = '/pricing';
  static const materialPrices = '/material-prices';
  static const adminMaterialPrices = '/admin/material-prices';
  static const adminMessages = '/admin/messages';
  // static const boqTemplateItemsManage = '/boq/template-items-manage';
  // static const boqTemplatePickItems = '/boq/template-pick-items';
}
