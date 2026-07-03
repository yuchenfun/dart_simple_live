# AI Codebase Guide

这份文档给后续 AI 或新维护者快速接手用。它不是完整产品说明，而是“先看哪里、怎么改、改完怎么验”的代码地图。

## 项目概览

Simple Live 是一个 Dart / Flutter 多包仓库，用 `simple_live_core` 聚合直播平台能力，再由主 App 和 TV App 复用核心能力并各自实现 UI、播放、同步和平台交互。

主要包：

- `simple_live_core/`：纯 Dart 核心库，负责各直播平台的分类、搜索、房间详情、播放地址、弹幕协议、通用模型。
- `simple_live_app/`：主 Flutter App，覆盖 Android / iOS / Windows / macOS / Linux。
- `simple_live_tv_app/`：TV Flutter App，面向 Android TV，也包含 Windows TV 多开相关能力。
- `simple_live_console/`：基于 core 的命令行实验/测试入口。
- `third_party/canvas_danmaku/`：本仓维护的弹幕渲染依赖，通过 dependency override 接入 App 和 TV。
- `assets/`：仓库级图片、版本 JSON、说明资源。
- `.github/workflows/`：手动/标签触发的 Android、TV、Windows、Linux、macOS、iOS 构建流程。

当前支持站点在 `simple_live_core` 和两个 App 的 `Sites` 注册表中共同体现：哔哩哔哩、斗鱼、虎牙、抖音、快手。

## 开发环境

README 当前记录：

- Windows / Android / Android TV 本地 Flutter：`3.41.9`
- Linux WSL Flutter：`3.38.10`
- GitHub Actions 使用 Flutter `3.41.x`

每个子包独立执行依赖安装和命令：

```bash
cd simple_live_core && dart pub get
cd simple_live_app && flutter pub get
cd simple_live_tv_app && flutter pub get
cd simple_live_console && dart pub get
```

常用验证：

```bash
cd simple_live_core && dart test
cd simple_live_app && flutter analyze
cd simple_live_app && flutter test
cd simple_live_tv_app && flutter analyze
cd simple_live_tv_app && flutter test
```

如果只改 core 的弹幕摘要或平台解析，优先跑相关单测，例如：

```bash
cd simple_live_core && dart test test/live_repeated_danmu_summary_test.dart
cd simple_live_core && dart test test/kuaishou_site_test.dart test/kuaishou_danmaku_test.dart
```

## 核心库结构

入口导出文件：

- `simple_live_core/lib/simple_live_core.dart`

核心接口：

- `simple_live_core/lib/src/interface/live_site.dart`
  - `LiveSite` 定义站点能力：分类、推荐、搜索、房间详情、清晰度、播放链接、直播状态、SC、贡献榜。
- `simple_live_core/lib/src/interface/live_danmaku.dart`
  - `LiveDanmaku` 定义弹幕生命周期：`start`、`stop`、`heartbeat`，通过 `onMessage` / `onClose` / `onReady` 回调上报。

平台实现：

- `bilibili_site.dart` / `bilibili_danmaku.dart`
- `douyu_site.dart` / `douyu_danmaku.dart`
- `huya_site.dart` / `huya_danmaku.dart`
- `douyin_site.dart` / `douyin_danmaku.dart`
- `kuaishou_site.dart` / `kuaishou_danmaku.dart`

通用模型在 `simple_live_core/lib/src/model/`。App 和 TV 尽量依赖这些模型，而不是各自重复平台返回结构。

通用工具在 `simple_live_core/lib/src/common/`，其中网络、日志、错误、Cookie、抖音刷新限流等逻辑放这里。

## 主 App 结构

主入口：

- `simple_live_app/lib/main.dart`

初始化顺序大致是：

1. `WidgetsFlutterBinding.ensureInitialized()`
2. 解析桌面多实例启动参数：`DesktopStartupArgs.initialize(args)`
3. 桌面 Hive 数据迁移和窗口初始化
4. `MediaKit.ensureInitialized()`
5. `Hive.initFlutter(...)`
6. `initServices()`
7. `runApp(const MyApp())`
8. 桌面窗口生命周期监听

重要服务注册在 `initServices()`：

- `LocalStorageService`
- `DBService`
- `CurrentRoomService`
- `AppSettingsController`
- `BiliBiliAccountService`
- `DouyinAccountService`
- `KuaishouAccountService`
- `FollowService`
- `LiveSubtitleService`
- `ProfileBackupService`
- `SyncService`，桌面 secondary player instance 会跳过

目录约定：

- `app/`：全局配置、样式、工具、设置控制器、平台工具、站点注册。
- `models/`：Hive/业务模型。
- `modules/`：页面模块，通常按 `xxx_controller.dart` + `xxx_page.dart` 组织。
- `routes/`：GetX 路由、路径常量、导航辅助。
- `services/`：跨页面业务服务，例如关注、同步、账号、备份、桌面多窗口。
- `widgets/`：跨模块复用 UI。

路由注册：

- `simple_live_app/lib/routes/route_path.dart`
- `simple_live_app/lib/routes/app_pages.dart`
- `simple_live_app/lib/routes/app_navigation.dart`

站点注册：

- `simple_live_app/lib/app/constant.dart`
- `simple_live_app/lib/app/sites.dart`

## TV App 结构

主入口：

- `simple_live_tv_app/lib/main.dart`

TV App 与主 App 相似，但有几个重要差异：

- 使用 `flutter_screenutil`，设计尺寸 `1920x1080`。
- 非桌面平台强制横屏和全屏。
- 首页路由根据 `AppSettingsController.instance.firstRun` 进入协议页或主页。
- 桌面 secondary instance 同样跳过 `SyncService`，用于多窗口播放器。
- TV 的 UI 更强调焦点、遥控器/键盘导航。

重要服务：

- `LocalStorageService`
- `DBService`
- `CurrentRoomService`
- `AppSettingsController`
- `BiliBiliAccountService`
- `DouyinAccountService`
- `ProfileBackupService`
- `SyncService`
- `FollowUserService`

目录约定：

- `modules/home`、`modules/hot_live`、`modules/category`、`modules/follow_user`、`modules/live_room` 是主要观看路径。
- `modules/sync` 包含局域网/远程/WebDAV 同步相关 UI。
- `widgets/button`、`widgets/card`、`app/app_focus_node.dart` 等文件承载 TV 焦点体验。

路由注册：

- `simple_live_tv_app/lib/routes/route_path.dart`
- `simple_live_tv_app/lib/routes/app_pages.dart`
- `simple_live_tv_app/lib/routes/app_navigation.dart`

站点注册：

- `simple_live_tv_app/lib/app/constant.dart`
- `simple_live_tv_app/lib/app/sites.dart`

## 关键数据流

### 打开直播间

典型流向：

1. 页面或服务拿到 `Site` 和 `roomId`。
2. 通过 GetX 路由进入直播页。
3. `LiveRoomController` 调用 `site.liveSite.getRoomDetail()`。
4. 读取清晰度：`getPlayQualites()`。
5. 读取播放地址：`getPlayUrls()`。
6. `PlayerController` / `media_kit` 播放。
7. `site.liveSite.getDanmaku()` 创建弹幕客户端并开始接收消息。

主 App 相关文件：

- `simple_live_app/lib/modules/live_room/live_room_controller.dart`
- `simple_live_app/lib/modules/live_room/player/player_controller.dart`
- `simple_live_app/lib/modules/live_room/live_room_page.dart`

TV App 相关文件：

- `simple_live_tv_app/lib/modules/live_room/live_room_controller.dart`
- `simple_live_tv_app/lib/modules/live_room/player/player_controller.dart`
- `simple_live_tv_app/lib/modules/live_room/live_room_page.dart`

### 关注列表

关注数据本地存储在 Hive，主 App 和 TV App 有各自服务：

- 主 App：`simple_live_app/lib/services/follow_service.dart`
- TV App：`simple_live_tv_app/lib/services/follow_user_service.dart`

大量关注场景下要注意：

- 刷新任务互斥、冷却和后台并发控制。
- 导入/同步应分批写入，避免 UI 卡顿或 TV 闪退。
- 关注状态未知时通常按未开播处理。

### 同步与备份

同步相关能力分散在：

- `sync_service.dart`
- `profile_backup_service.dart`
- `bulk_data_import_service.dart`
- `sync_progress_dialog.dart`
- WebDAV / local sync / remote room sync 对应模块

主 App 路径：

- `simple_live_app/lib/modules/sync/`
- `simple_live_app/lib/services/sync_service.dart`
- `simple_live_app/lib/services/profile_backup_service.dart`
- `simple_live_app/lib/services/bulk_data_import_service.dart`

TV App 路径：

- `simple_live_tv_app/lib/modules/sync/`
- `simple_live_tv_app/lib/services/sync_service.dart`
- `simple_live_tv_app/lib/services/profile_backup_service.dart`
- `simple_live_tv_app/lib/services/bulk_data_import_service.dart`

敏感信息原则：Cookie、WebDAV 密码等默认不应写入普通配置包。

### 多开 / 多窗口

主 App 和 TV App 都有多开模块：

- `modules/multi_room/`
- `services/desktop_multi_window_service.dart`
- `app/desktop_startup_args.dart`

桌面 secondary instance 会使用独立 Hive 快照，并跳过同步服务，避免多个播放器实例同时改主数据或抢同步连接。

## 常见修改清单

### 新增直播平台

通常需要改：

1. `simple_live_core/lib/src/<site>_site.dart`
2. `simple_live_core/lib/src/danmaku/<site>_danmaku.dart`
3. `simple_live_core/lib/simple_live_core.dart` 导出新实现。
4. `simple_live_app/lib/app/constant.dart`
5. `simple_live_app/lib/app/sites.dart`
6. `simple_live_tv_app/lib/app/constant.dart`
7. `simple_live_tv_app/lib/app/sites.dart`
8. 两个 App 的站点图标资源和 `pubspec.yaml` assets 覆盖范围。
9. 搜索、账号、Cookie 或特殊设置页面，如该平台需要登录态。
10. core 单测，至少覆盖房间解析、播放地址解析、弹幕消息解析中风险最高的部分。

注意：站点 `id` 是持久化和同步关键字段，改名会影响已有用户数据。

### 新增页面

主 App：

1. 在 `simple_live_app/lib/modules/<feature>/` 新建 page/controller。
2. 在 `simple_live_app/lib/routes/route_path.dart` 加路径。
3. 在 `simple_live_app/lib/routes/app_pages.dart` 注册 `GetPage` 和 bindings。
4. 如需统一跳转，在 `app_navigation.dart` 增加封装。

TV App：

1. 同样修改 `modules/`、`route_path.dart`、`app_pages.dart`。
2. 额外检查焦点初始位置、遥控器返回、横屏布局、文字是否溢出。

### 新增设置项

通常涉及：

1. `LocalStorageService` 增加 key。
2. `AppSettingsController` 增加响应式字段、默认值、读写方法。
3. 对应 settings page 增加 UI。
4. 如果要导入/导出，更新 `profile_backup_service.dart` 和 `bulk_data_import_service.dart`。
5. 如果影响 TV，也要在 TV App 重复增加或确认不支持。

### 修改同步/导入

先看这几个文件：

- `services/sync_service.dart`
- `services/profile_backup_service.dart`
- `services/bulk_data_import_service.dart`
- `models/db/`
- `widgets/sync_progress_dialog.dart`

改动原则：

- 大数据量分批处理。
- 进度通过 `SyncProgress` 或 UI 进度弹窗反馈。
- 导入旧格式要尽量兼容，失败提示要能定位问题。
- 不把敏感字段默认导出。

### 修改播放器或弹幕

先定位是 core 解析问题还是 App 播放/渲染问题：

- 平台协议、播放 URL、弹幕消息字段：改 `simple_live_core`。
- 播放器状态、清晰度切换、全屏、小窗、控制栏：改 App/TV 的 `modules/live_room/player/`。
- 弹幕渲染样式、重复弹幕、富文本/表情显示：可能同时涉及 `simple_live_core`、`third_party/canvas_danmaku` 和 App/TV 设置页。

## 代码风格和架构习惯

- 状态管理和路由使用 GetX。
- 本地持久化主要使用 Hive。
- 网络请求在 core 和 App 服务内使用 Dio。
- 播放器使用 `media_kit`。
- 弹窗和 Toast 使用 `flutter_smart_dialog`。
- 不要把平台 HTTP 返回结构直接泄漏到 UI，优先转换为 core model 或 App model。
- 主 App 与 TV App 有相似逻辑但不是同一套 UI。修 bug 时要判断是否两边都要改。
- 桌面多实例路径要谨慎：secondary instance 不应启动同步服务，不应直接使用主 Hive 写入路径。

## 安全边界

README 明确禁止扩展这些能力：

- 官方账号登录、注册、找回密码、实名、绑定手机、未成年人模式。
- 官方账号维度的关注、取关、拉黑、消息已读、历史同步、收藏同步。
- 充值、钱包、余额、礼物、订单、退款、兑换码等付费相关功能。
- 送礼物、上舰、贵族、粉丝牌、付费表情、打赏等付费互动。
- 官方活动、抽奖、任务、签到、红包、福袋、竞猜、投票、积分、优惠券等写操作。

开发目标应保持在公开视频/直播信息读取、播放、弹幕展示、本地关注管理和本地/用户授权同步。

## 构建与发布线索

工作流文件：

- `.github/workflows/publish_app_release.yml`：主 App Android release。
- `.github/workflows/publish_app_release_windows.yml`：主 App Windows release。
- `.github/workflows/publish_app_release_linux.yml`：主 App Linux release。
- `.github/workflows/publish_app_release_macos_manual.yml`：主 App macOS 手动构建。
- `.github/workflows/publish_app_release_ios_manual.yml`：主 App iOS unsigned IPA。
- `.github/workflows/publish_tv_app_release.yaml`：TV Android release。
- `publish_app_dev.yaml`、`publish_tv_app_dev.yaml`：dev 标签/手动构建。

发布版本号在：

- `simple_live_app/pubspec.yaml`
- `simple_live_tv_app/pubspec.yaml`
- `assets/app_version.json`
- `assets/tv_app_version.json`

## AI 介入建议

接任务后建议按这个顺序探索：

1. 先用 `rg` 搜用户提到的中文文案、设置名、类名或站点名。
2. 判断改动归属：core、主 App、TV App、三方弹幕组件，还是多个包联动。
3. 找同类实现照着现有模式改，例如新增平台先看 `kuaishou` 或 `douyin`，新增设置先看相邻 settings page。
4. 改完至少跑受影响包的 analyze 或单测；如果网络依赖导致平台测试不稳定，要说明限制。
5. 最后检查是否遗漏另一端 App。主 App 修了的关注/同步/播放问题，TV App 经常也有对应文件。

高频入口速查：

- Core 导出：`simple_live_core/lib/simple_live_core.dart`
- Core 平台接口：`simple_live_core/lib/src/interface/live_site.dart`
- Core 弹幕接口：`simple_live_core/lib/src/interface/live_danmaku.dart`
- 主 App 入口：`simple_live_app/lib/main.dart`
- 主 App 路由：`simple_live_app/lib/routes/app_pages.dart`
- 主 App 站点：`simple_live_app/lib/app/sites.dart`
- TV App 入口：`simple_live_tv_app/lib/main.dart`
- TV App 路由：`simple_live_tv_app/lib/routes/app_pages.dart`
- TV App 站点：`simple_live_tv_app/lib/app/sites.dart`
