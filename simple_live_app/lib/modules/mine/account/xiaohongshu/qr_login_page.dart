import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/xiaohongshu/qr_login_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

class XiaohongshuQRLoginPage extends GetView<XiaohongshuQRLoginController> {
  const XiaohongshuQRLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小红书扫码登录')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(XiaohongshuQRLoginController.loginUrl),
                  ),
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
          const SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('请使用小红书手机客户端扫码并确认登录'),
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
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: controller.reload,
                  child: const Text('重新加载'),
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
