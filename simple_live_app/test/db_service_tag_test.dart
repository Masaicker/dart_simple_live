import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/db_service.dart';

void main() {
  test('repair prefers UUID records over stale numeric records', () {
    final oldTag = FollowUserTag(
      id: 'tag-a',
      tag: '旧名称',
      userId: ['room-1'],
    );
    final otherTag = FollowUserTag(
      id: 'tag-b',
      tag: '其他',
      userId: ['room-2'],
    );
    final updatedTag = oldTag.copyWith(
      tag: '新名称',
      userId: ['room-2'],
    );

    final storageMap = DBService.buildRepairedFollowTagStorageMap([
      MapEntry(0, oldTag),
      MapEntry(updatedTag.id, updatedTag),
      MapEntry(1, otherTag),
    ]);

    expect(storageMap.keys, orderedEquals(['tag-a', 'tag-b']));
    expect(storageMap['tag-a']?.tag, '新名称');
    expect(storageMap['tag-a']?.userId, orderedEquals(['room-2']));
    expect(storageMap['tag-b'], same(otherTag));
  });

  test('repair does not revive stale numeric record data', () {
    final currentTag = FollowUserTag(
      id: 'tag-a',
      tag: '新名称',
      userId: ['room-2'],
    );
    final staleTag = FollowUserTag(
      id: 'tag-a',
      tag: '旧名称',
      userId: ['room-1'],
    );

    final storageMap = DBService.buildRepairedFollowTagStorageMap([
      MapEntry(currentTag.id, currentTag),
      MapEntry(0, staleTag),
    ]);

    expect(storageMap['tag-a']?.tag, '新名称');
    expect(
      storageMap['tag-a']?.userId,
      orderedEquals(['room-2']),
    );
  });

  test('follow tags use explicit order instead of UUID key order', () {
    final first = FollowUserTag(
      id: 'tag-a',
      tag: 'A',
      userId: [],
      sortIndex: 1,
    );
    final second = FollowUserTag(
      id: 'tag-z',
      tag: 'Z',
      userId: [],
      sortIndex: 0,
    );

    final sorted = DBService.sortFollowTags([first, second]);

    expect(sorted.map((tag) => tag.id), orderedEquals(['tag-z', 'tag-a']));
  });

  test('reordered follow tags receive contiguous sort indexes', () {
    final first = FollowUserTag(id: 'tag-a', tag: 'A', userId: []);
    final second = FollowUserTag(id: 'tag-b', tag: 'B', userId: []);

    final reordered = DBService.reindexFollowTags([second, first]);

    expect(reordered.map((tag) => tag.id), orderedEquals(['tag-b', 'tag-a']));
    expect(reordered.map((tag) => tag.sortIndex), orderedEquals([0, 1]));
  });

  test('duplicate tag names are merged in their displayed order', () {
    final laterDuplicate = FollowUserTag(
      id: 'tag-b',
      tag: ' 常看 ',
      userId: ['room-2', 'room-1'],
      sortIndex: 3,
    );
    final first = FollowUserTag(
      id: 'tag-a',
      tag: '常看',
      userId: ['room-1'],
      sortIndex: 1,
    );
    final other = FollowUserTag(
      id: 'tag-c',
      tag: '团播',
      userId: ['room-3'],
      sortIndex: 2,
    );

    final merged = DBService.mergeDuplicateFollowTagNames(
      DBService.sortFollowTags([laterDuplicate, other, first]),
    );

    expect(merged.map((tag) => tag.id), orderedEquals(['tag-a', 'tag-c']));
    expect(merged.first.tag, '常看');
    expect(merged.first.userId, orderedEquals(['room-1', 'room-2']));
  });

  test('legacy tags without sort indexes keep their existing order', () {
    final first = FollowUserTag(id: 'tag-z', tag: 'Z', userId: []);
    final second = FollowUserTag(id: 'tag-a', tag: 'A', userId: []);

    final sorted = DBService.sortFollowTags([first, second]);

    expect(sorted.map((tag) => tag.id), orderedEquals(['tag-z', 'tag-a']));
  });

  test('legacy follow tag JSON is migrated to an unassigned order', () {
    final tag = FollowUserTag.fromJson({
      'id': 'tag-a',
      'tag': 'A',
      'userId': <String>[],
    });

    expect(tag.sortIndex, -1);
    expect(tag.toJson()['sortIndex'], -1);
  });

  group('Hive follow tag order', () {
    late Directory tempDirectory;
    late DBService dbService;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('follow_tag_test_');
      Hive.init(tempDirectory.path);
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(FollowUserTagAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(FollowUserAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(HistoryAdapter());
      }
      dbService = DBService();
      dbService.tagBox = await Hive.openBox<FollowUserTag>('FollowUserTag');
    });

    tearDown(() async {
      await Hive.close();
      await tempDirectory.delete(recursive: true);
    });

    test('reordered tags keep their order after reopening Hive', () async {
      final first = FollowUserTag(
        id: 'tag-a',
        tag: 'A',
        userId: [],
        sortIndex: 0,
      );
      final second = FollowUserTag(
        id: 'tag-z',
        tag: 'Z',
        userId: [],
        sortIndex: 1,
      );
      await dbService.tagBox.putAll({first.id: first, second.id: second});

      await dbService.updateFollowTagOrder([second, first]);
      await dbService.tagBox.close();
      dbService.tagBox =
          await Hive.openBox<FollowUserTag>('FollowUserTag');

      expect(
        dbService.getFollowTagList().map((tag) => tag.id),
        orderedEquals(['tag-z', 'tag-a']),
      );
      expect(
        dbService.getFollowTagList().map((tag) => tag.sortIndex),
        orderedEquals([0, 1]),
      );
    });

    test('startup repairs legacy keys and duplicate records', () async {
      final staleTag = FollowUserTag(
        id: 'tag-a',
        tag: '旧名称',
        userId: ['room-1'],
      );
      final currentTag = FollowUserTag(
        id: 'tag-a',
        tag: '新名称',
        userId: ['room-2'],
      );
      final otherTag = FollowUserTag(
        id: 'tag-b',
        tag: '其他',
        userId: [],
      );
      await dbService.tagBox.put(0, staleTag);
      await dbService.tagBox.put(currentTag.id, currentTag);
      await dbService.tagBox.put(1, otherTag);

      await dbService.init();

      expect(dbService.tagBox.keys, unorderedEquals(['tag-a', 'tag-b']));
      expect(dbService.getFollowTag('新名称')?.id, 'tag-a');
      expect(
        dbService.getFollowTag('新名称')?.userId,
        orderedEquals(['room-2']),
      );
      expect(
        dbService.getFollowTagList().map((tag) => tag.sortIndex),
        orderedEquals([0, 1]),
      );
    });

    test('startup merges different UUIDs with the same tag name', () async {
      final first = FollowUserTag(
        id: 'tag-a',
        tag: '常看',
        userId: ['room-1'],
        sortIndex: 0,
      );
      final duplicate = FollowUserTag(
        id: 'tag-b',
        tag: ' 常看 ',
        userId: ['room-1', 'room-2'],
        sortIndex: 2,
      );
      final other = FollowUserTag(
        id: 'tag-c',
        tag: '团播',
        userId: ['room-3'],
        sortIndex: 1,
      );
      await dbService.tagBox.putAll({
        first.id: first,
        duplicate.id: duplicate,
        other.id: other,
      });

      await dbService.init();

      expect(dbService.tagBox.keys, unorderedEquals(['tag-a', 'tag-c']));
      expect(
        dbService.getFollowTagList().map((tag) => tag.id),
        orderedEquals(['tag-a', 'tag-c']),
      );
      expect(
        dbService.getFollowTag('常看')?.userId,
        orderedEquals(['room-1', 'room-2']),
      );
      expect(
        dbService.getFollowTagList().map((tag) => tag.sortIndex),
        orderedEquals([0, 1]),
      );
    });
  });
}
