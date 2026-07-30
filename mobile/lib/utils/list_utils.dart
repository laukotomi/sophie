import 'package:sophie/models/base_entity.dart';

class ListUtils {
  static bool syncLists<T extends BaseEntity>(
    List<T> localList,
    List<T> backendList,
  ) {
    bool changed = false;

    for (final backendItem in backendList) {
      final localIndex = localList.indexWhere((n) => n.id == backendItem.id);
      if (localIndex == -1) {
        localList.add(backendItem);
        changed = true;
      }

      final localItem = localList[localIndex];
      if (localItem.updatedAt != backendItem.updatedAt) {
        localList[localIndex] = backendItem;
        changed = true;
      }
    }

    for (final localItem in localList) {
      final localIndex = backendList.indexWhere((n) => n.id == localItem.id);
      if (localIndex == -1) {
        localList.removeWhere((n) => n.id == localItem.id);
        changed = true;
      }
    }

    return changed;
  }
}
