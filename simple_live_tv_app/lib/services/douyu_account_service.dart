import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';

class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  String cookie = "";
  final hasCookie = false.obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyuCookie, "");
    hasCookie.value = cookie.trim().isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    final site = Sites.allSites[Constant.kDouyu]?.liveSite;
    if (site is DouyuSite) {
      site.cookie = cookie;
    }
  }

  void setCookie(String value) {
    cookie = value.trim();
    hasCookie.value = cookie.isNotEmpty;
    setSite();
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuCookie, cookie);
  }

  void clearCookie() => setCookie("");
}
