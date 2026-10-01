import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_page.dart';
import 'package:simple_live_app/services/current_room_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';

// Keep the widget tests independent of storage, network requests and timers.
class _FakeAppSettingsController extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeFollowService extends FollowService {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeFollowUserController extends FollowUserController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() async {
    await Get.reset();
  });

  for (final style in ['default', 'compact', 'card']) {
    for (final showLiveCover in [false, true]) {
      testWidgets(
        '$style (cover: $showLiveCover) updates multi-room selection without filtering',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1400, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final settings = _FakeAppSettingsController();
          settings.followDisplayStyle.value = style;
          settings.followShowLiveCover.value = showLiveCover;
          Get.put<AppSettingsController>(settings);
          Get.put<FollowService>(_FakeFollowService());
          Get.put(CurrentRoomService());

          final controller = _FakeFollowUserController();
          controller.list.assignAll([
            for (var i = 1; i <= 2; i++)
              FollowUser(
                id: 'bilibili_$i',
                roomId: '$i',
                siteId: 'bilibili',
                userName: '测试主播$i',
                face: '',
                addTime: DateTime(2026, 1, 1),
                roomTitle: '测试直播$i',
              )..liveStatus.value = 2,
          ]);
          Get.put<FollowUserController>(controller);

          await tester.pumpWidget(
            const GetMaterialApp(home: FollowUserPage()),
          );
          await tester.pumpAndSettle();

          final items = find.byType(FollowUserItem);
          expect(items, findsNWidgets(2));
          expect(find.byIcon(Icons.circle_outlined), findsNothing);

          await tester.tap(find.text('多开同屏'));
          await tester.pumpAndSettle();
          expect(find.text('开始同屏(0)'), findsOneWidget);
          expect(find.byIcon(Icons.circle_outlined), findsNWidgets(2));

          await tester.tap(items.first);
          await tester.pumpAndSettle();
          expect(find.text('开始同屏(1)'), findsOneWidget);
          expect(find.byIcon(Icons.check_circle), findsOneWidget);
          expect(
            tester.widget<FollowUserItem>(items.first).selectedForMultiRoom,
            isTrue,
          );
          expect(
            tester.widget<FollowUserItem>(items.last).selectedForMultiRoom,
            isFalse,
          );

          await tester.tap(items.first);
          await tester.pumpAndSettle();
          expect(find.text('开始同屏(0)'), findsOneWidget);
          expect(find.byIcon(Icons.check_circle), findsNothing);
          expect(find.byIcon(Icons.circle_outlined), findsNWidgets(2));

          await tester.tap(items.first);
          await tester.pumpAndSettle();
          await tester.tap(items.last);
          await tester.pumpAndSettle();
          expect(find.text('开始同屏(2)'), findsOneWidget);
          expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

          await tester.tap(find.byTooltip('取消多选'));
          await tester.pumpAndSettle();
          expect(controller.selectedMultiRoomKeys, isEmpty);
          expect(find.text('多开同屏'), findsOneWidget);
          expect(find.byIcon(Icons.check_circle), findsNothing);
          expect(find.byIcon(Icons.circle_outlined), findsNothing);
          for (final item in tester.widgetList<FollowUserItem>(items)) {
            expect(item.multiSelectMode, isFalse);
            expect(item.selectedForMultiRoom, isFalse);
          }

          await tester.tap(find.text('多开同屏'));
          await tester.pumpAndSettle();
          expect(find.text('开始同屏(0)'), findsOneWidget);
          expect(find.byIcon(Icons.circle_outlined), findsNWidgets(2));
          expect(find.byIcon(Icons.check_circle), findsNothing);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
        },
        skip: !PlatformUtils.supportsInlineMultiRoom,
      );
    }
  }
}
