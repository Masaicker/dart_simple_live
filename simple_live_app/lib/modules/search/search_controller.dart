import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';

class AppSearchController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late TabController tabController;
  int index = 0;

  var searchMode = 0.obs;

  AppSearchController() {
    final initialIndex = _resolveInitialIndex();
    index = initialIndex;
    tabController = TabController(
      length: Sites.supportSites.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    AppSettingsController.instance.setLastSearchSiteId(Sites.supportSites[index].id);
    tabController.animation?.addListener(() {
      var currentIndex = (tabController.animation?.value ?? 0).round();
      if (index == currentIndex) {
        return;
      }

      index = currentIndex;
      AppSettingsController.instance.setLastSearchSiteId(Sites.supportSites[index].id);
      // if (Sites.supportSites[index].id == Constant.kDouyin) {
      //   return;
      // }

      var controller =
          Get.find<SearchListController>(tag: Sites.supportSites[index].id);

      if (controller.list.isEmpty &&
          !controller.pageEmpty.value &&
          controller.keyword.isNotEmpty) {
        controller.refreshData();
      }
    });
  }

  StreamSubscription<dynamic>? streamSubscription;

  TextEditingController searchController = TextEditingController();

  int _resolveInitialIndex() {
    String? siteId;
    final args = Get.arguments;
    if (args is Map) {
      siteId = args["siteId"]?.toString();
    } else if (args is String) {
      siteId = args;
    }
    siteId ??= AppSettingsController.instance.lastSearchSiteId.value;
    final resolvedIndex =
        Sites.supportSites.indexWhere((site) => site.id == siteId);
    return resolvedIndex < 0 ? 0 : resolvedIndex;
  }

  @override
  void onInit() {
    searchController.addListener(_logImeEditingState);
    for (var site in Sites.supportSites) {
      // if (site.id == Constant.kDouyin) {
      //   Get.put(DouyinSearchController(site));
      // } else {
      Get.put(
        SearchListController(site),
        tag: site.id,
      );
      //}
    }

    super.onInit();
  }

  void _logImeEditingState() {
    if (!Platform.isWindows ||
        !AppSettingsController.instance.logEnable.value) {
      return;
    }
    final value = searchController.value;
    Log.writeLog(
      "[IME诊断] ${DateTime.now().toIso8601String()} "
      "Search text length=${value.text.length} "
      "composing=${value.composing.start}:${value.composing.end} "
      "selection=${value.selection.start}:${value.selection.end}",
      Level.debug,
    );
  }

  void doSearch() {
    if (searchController.text.isEmpty) {
      return;
    }
    for (var site in Sites.supportSites) {
      // if (site.id == Constant.kDouyin) {
      //   var controller = Get.find<DouyinSearchController>();
      //   controller.keyword = searchController.text;
      //   controller.searchMode.value = searchMode.value;
      //   controller.reloadWebView();
      // } else {
      var controller = Get.find<SearchListController>(tag: site.id);
      controller.clear();
      controller.keyword = searchController.text;
      controller.searchMode.value = searchMode.value;
      //}
    }
    // if (Sites.supportSites[index].id != Constant.kDouyin) {
    var controller =
        Get.find<SearchListController>(tag: Sites.supportSites[index].id);
    controller.refreshData();
    //}
  }

  @override
  void onClose() {
    searchController.removeListener(_logImeEditingState);
    streamSubscription?.cancel();
    super.onClose();
  }
}
