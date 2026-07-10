import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/modules/account/xiaohongshu/qr_login_controller.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

class XiaohongshuQRLoginPage extends GetView<XiaohongshuQRLoginController> {
  const XiaohongshuQRLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(
        children: [
          AppStyle.vGap32,
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.arrow_back,
                text: '返回',
                autofocus: true,
                onTap: Get.back,
              ),
              AppStyle.hGap32,
              Text(
                '登录小红书',
                style: AppStyle.titleStyleWhite.copyWith(
                  fontSize: 36.w,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppStyle.hGap24,
              const Spacer(),
            ],
          ),
          AppStyle.vGap32,
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: SizedBox(
                    width: 960.w,
                    height: 540.w,
                    child: Stack(
                      children: [
                        InAppWebView(
                          initialSettings: InAppWebViewSettings(
                            userAgent: XiaohongshuSite.userAgent,
                            javaScriptEnabled: true,
                            transparentBackground: false,
                          ),
                          onWebViewCreated: controller.attachController,
                          onLoadStop: controller.handleLoadStop,
                          onReceivedError: controller.handleLoadError,
                        ),
                        Obx(() => _buildOverlay(context)),
                      ],
                    ),
                  ),
                ),
                AppStyle.vGap24,
                Text(
                  '请使用小红书手机客户端扫码并确认登录',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32.w),
                ),
                AppStyle.vGap24,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    switch (controller.status.value) {
      case XiaohongshuQRLoginStatus.loading:
        return const ColoredBox(
          color: Colors.white,
          child: Center(child: CircularProgressIndicator()),
        );
      case XiaohongshuQRLoginStatus.failed:
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller.errorMessage.value.isEmpty
                      ? '页面加载失败'
                      : controller.errorMessage.value,
                  textAlign: TextAlign.center,
                  style: AppStyle.textStyleWhite,
                ),
                AppStyle.vGap12,
                HighlightButton(
                  focusNode: AppFocusNode(),
                  iconData: Icons.refresh,
                  text: '重新加载',
                  onTap: controller.reload,
                ),
              ],
            ),
          ),
        );
      case XiaohongshuQRLoginStatus.waiting:
      case XiaohongshuQRLoginStatus.completed:
        return const SizedBox.shrink();
    }
  }
}
