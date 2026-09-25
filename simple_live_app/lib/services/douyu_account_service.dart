import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  var cookie = "";
  var hasCookie = false.obs;

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
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuCookie, cookie);
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void clearCookie() => setCookie("");
}
