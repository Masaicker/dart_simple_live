import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';

void main() {
  test('follow tags are stored by UUID and duplicate records are repaired', () {
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
    final updatedTag = oldTag.copyWith(tag: '新名称');

    final storageMap = DBService.buildFollowTagStorageMap([
      oldTag,
      otherTag,
      updatedTag,
    ]);

    expect(storageMap.keys, orderedEquals(['tag-a', 'tag-b']));
    expect(storageMap['tag-a']?.tag, '新名称');
    expect(storageMap['tag-b'], same(otherTag));
  });

  test('follow tag order is preserved while using UUID keys', () {
    final first = FollowUserTag(id: 'tag-a', tag: 'A', userId: []);
    final second = FollowUserTag(id: 'tag-b', tag: 'B', userId: []);

    final storageMap = DBService.buildFollowTagStorageMap([second, first]);

    expect(storageMap.keys, orderedEquals(['tag-b', 'tag-a']));
  });
}
