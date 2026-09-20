import 'package:hive/hive.dart';

part 'follow_user_tag.g.dart';

@HiveType(typeId: 3)
class FollowUserTag {
  @HiveField(1)
  String id;

  // 用户自定义tag
  @HiveField(2)
  String tag;

  // followUserId
  @HiveField(3)
  List<String> userId;

  // 用户自定义标签的显示顺序
  @HiveField(4, defaultValue: -1)
  int sortIndex;

  FollowUserTag({
    required this.id,
    required this.tag,
    required this.userId,
    this.sortIndex = -1,
  });

  factory FollowUserTag.fromJson(Map<String, dynamic> json) {
    final rawUserIds = json['userId'];
    return FollowUserTag(
      id: json['id']?.toString().trim() ?? "",
      tag: json['tag']?.toString().trim() ?? "",
      userId: rawUserIds is List
          ? rawUserIds.map((e) => e.toString()).toList()
          : <String>[],
      sortIndex: (json['sortIndex'] as num?)?.toInt() ?? -1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tag': tag,
      'userId': userId,
      'sortIndex': sortIndex,
    };
  }

  FollowUserTag copyWith({
    String? id,
    String? tag,
    List<String>? userId,
    int? sortIndex,
  }) {
    return FollowUserTag(
      id: id ?? this.id,
      tag: tag ?? this.tag,
      userId: userId ?? this.userId,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }
}
