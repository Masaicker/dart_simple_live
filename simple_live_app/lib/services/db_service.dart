import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

class DBService extends GetxService {
  static DBService get instance => Get.find<DBService>();
  late Box<History> historyBox;
  late Box<FollowUser> followBox;
  late Box<FollowUserTag> tagBox;
  final Uuid uuid = const Uuid();

  Future init() async {
    historyBox = await Hive.openBox("History");
    followBox = await Hive.openBox("FollowUser");
    tagBox = await Hive.openBox("FollowUserTag");
    await _repairFollowTags();
  }

  static Map<String, FollowUserTag> buildFollowTagStorageMap(
    Iterable<FollowUserTag> tags,
  ) {
    final result = <String, FollowUserTag>{};
    for (final tag in tags) {
      result[tag.id] = tag;
    }
    return result;
  }

  static Map<String, FollowUserTag> buildRepairedFollowTagStorageMap(
    Iterable<MapEntry<dynamic, FollowUserTag>> entries,
  ) {
    final result = <String, FollowUserTag>{};
    final canonicalIds = <String>{};
    for (final entry in entries) {
      final tag = entry.value;
      final isCanonical = entry.key == tag.id;
      final existing = result[tag.id];
      if (existing == null) {
        result[tag.id] = tag;
        if (isCanonical) {
          canonicalIds.add(tag.id);
        }
        continue;
      }

      final existingIsCanonical = canonicalIds.contains(tag.id);
      final preferred = isCanonical || !existingIsCanonical ? tag : existing;
      result[tag.id] = preferred;
      if (isCanonical) {
        canonicalIds.add(tag.id);
      }
    }
    return result;
  }

  static List<FollowUserTag> sortFollowTags(
    Iterable<FollowUserTag> tags,
  ) {
    final indexedTags = tags.toList(growable: false).asMap().entries.toList();
    indexedTags.sort((left, right) {
      final leftIndex =
          left.value.sortIndex < 0 ? 0x7fffffff : left.value.sortIndex;
      final rightIndex =
          right.value.sortIndex < 0 ? 0x7fffffff : right.value.sortIndex;
      final order = leftIndex.compareTo(rightIndex);
      return order != 0 ? order : left.key.compareTo(right.key);
    });
    return indexedTags.map((entry) => entry.value).toList(growable: false);
  }

  static List<FollowUserTag> reindexFollowTags(
    Iterable<FollowUserTag> tags,
  ) {
    final list = tags.toList(growable: false);
    return [
      for (var index = 0; index < list.length; index++)
        list[index].copyWith(sortIndex: index),
    ];
  }

  Future<void> _repairFollowTags() async {
    final entries = tagBox.toMap().entries.toList(growable: false);
    final tagsById = buildRepairedFollowTagStorageMap(entries);
    final repaired = buildFollowTagStorageMap(
      reindexFollowTags(sortFollowTags(tagsById.values)),
    );
    final needsRepair = entries.length != repaired.length ||
        entries.any((entry) => entry.key != entry.value.id) ||
        repaired.entries.any(
          (entry) => tagBox.get(entry.key)?.sortIndex != entry.value.sortIndex,
        );
    if (!needsRepair) {
      return;
    }

    // Write repaired values before removing legacy numeric keys so a failed
    // migration cannot erase the only copy of a tag.
    await tagBox.putAll(repaired);
    final staleKeys = entries
        .map((entry) => entry.key)
        .where((key) => !repaired.containsKey(key))
        .toList(growable: false);
    if (staleKeys.isNotEmpty) {
      await tagBox.deleteAll(staleKeys);
    }
  }

  // follow_user_tag 相关逻辑
  bool getFollowTagExist(String id) {
    return tagBox.containsKey(id);
  }

  // 删除标签
  Future deleteFollowTag(String id) async {
    await tagBox.delete(id);
  }

  FollowUserTag? getFollowTag(String tag) {
    return tagBox.values.firstWhereOrNull((item) => item.tag == tag);
  }

  // 判断标签名称是否重复
  bool getFollowTagExistByTag(String tag) {
    return tagBox.values.any((item) => item.tag == tag);
  }

  // 获取标签列表
  List<FollowUserTag> getFollowTagList() {
    return sortFollowTags(tagBox.values);
  }

  int getNextFollowTagSortIndex() {
    var maxSortIndex = -1;
    for (final tag in tagBox.values) {
      if (tag.sortIndex > maxSortIndex) {
        maxSortIndex = tag.sortIndex;
      }
    }
    return maxSortIndex + 1;
  }

  // 修改标签
  Future updateFollowTag(FollowUserTag followTag) async {
    await tagBox.put(followTag.id, followTag);
  }

  // 添加标签
  // 限制标签唯一且长度不超过8个字符，非法输入返回 null
  Future<FollowUserTag?> addFollowTag(String tag) async {
    final String name = tag.trim();
    if (name.isEmpty) {
      return null;
    }
    if (getFollowTagExistByTag(name)) {
      return getFollowTag(name);
    }
    if (name.length > 8) {
      return null;
    }
    final String uniqueId = uuid.v4();
    final followUserTag = FollowUserTag(
      id: uniqueId,
      tag: name,
      userId: [],
      sortIndex: getNextFollowTagSortIndex(),
    );
    await tagBox.put(uniqueId, followUserTag);
    return followUserTag;
  }

  // 调整标签顺序
  Future updateFollowTagOrder(List<FollowUserTag> userTagList) async {
    final updatedMap = buildFollowTagStorageMap(
      reindexFollowTags(userTagList),
    );
    await tagBox.putAll(updatedMap);
  }

  bool getFollowExist(String id) {
    return followBox.containsKey(id);
  }

  List<FollowUser> getFollowList() {
    return followBox.values.toList();
  }

  Future addFollow(FollowUser follow) async {
    await followBox.put(follow.id, follow);
  }

  Future addFollows(Iterable<FollowUser> follows) async {
    await followBox.putAll({
      for (final follow in follows) follow.id: follow,
    });
  }

  Future deleteFollow(String id) async {
    await followBox.delete(id);
  }

  History? getHistory(String id) {
    if (historyBox.containsKey(id)) {
      return historyBox.get(id);
    }
    return null;
  }

  Future addOrUpdateHistory(History history) async {
    await historyBox.put(history.id, history);
  }

  List<History> getHistores() {
    var his = historyBox.values.toList();
    his.sort((a, b) => b.updateTime.compareTo(a.updateTime));
    return his;
  }
}
