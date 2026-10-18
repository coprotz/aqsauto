import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_resource.dart';
import 'package:aqs/features/build_up_rates/repositories/resource_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class ResourceLibraryController extends GetxController {
  ResourceLibraryController({ResourceRepository? repository})
    : _repository = repository ?? ResourceRepository();
  final ResourceRepository _repository;
  final resources = <RateResource>[].obs;
  final isLoading = false.obs;
  final searchQuery = ''.obs;
  final selectedType = RateComponentType.material.obs;
  bool _loaded = false;
  String? get uid => FirebaseAuth.instance.currentUser?.uid;
  List<RateResource> get filtered =>
      resources
          .where(
            (resource) =>
                resource.category == selectedType.value &&
                (searchQuery.value.isEmpty ||
                    resource.name.toLowerCase().contains(
                      searchQuery.value.toLowerCase(),
                    )),
          )
          .toList();

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    final id = uid;
    if (id == null) return;
    isLoading.value = true;
    try {
      resources.assignAll(await _repository.list(id));
      _loaded = true;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> save(RateResource resource) async {
    final id = uid;
    if (id == null) return;
    await _repository.save(id, resource);
    await load(force: true);
  }

  Future<void> delete(RateResource resource) async {
    final id = uid;
    if (id == null) return;
    await _repository.delete(id, resource.resourceId);
    resources.remove(resource);
  }
}
