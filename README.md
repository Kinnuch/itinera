# 行迹 Itinera

跨平台（Android / iOS）旅行行程规划应用。Flutter 单代码库。

四项核心能力：

1. **选择旅行日期** —— 建行程时选一个日期区间，自动展开成 D1…DN 的日程骨架；出发日整体前后平移时，所有安排跟着挪。
2. **逐日安排** —— 住宿 / 餐饮 / 景点 / 交通 / 购物 / 其他，六类共用一个编辑器，每项都可填**金额（多币种）、图片（相册多选或拍照）、时间段、位置、人数、订单号、备注**。
3. **自动汇总与合理性体检** —— 每日 / 分类 / 全程开销自动合计并按汇率折算到统一币种；11 条规则检查行程是否排得通。
4. **路线图** —— 按天着色的路径图，站点顺序编号，可按天筛选、导出 PNG 分享。

---

## 运行

```bash
cd itinera
flutter --version          # 需要 Flutter 3.32 或更新（用到 Color.withValues / CardThemeData）
flutter create .           # 生成 android/ ios/ 平台目录（本仓库只提交了 Dart 源码）
flutter pub get
flutter analyze
flutter test               # 纯 Dart 逻辑测试，不需要设备
flutter run                # 接上设备或模拟器
```

> **本仓库未包含 `android/` 与 `ios/` 目录**：它们是 `flutter create` 的生成物，包含机器相关的路径与签名配置。执行上面的 `flutter create .` 会按 `pubspec.yaml` 里的 `name` 生成，然后按下一节补两处权限声明。

### 平台权限

`android/app/src/main/AndroidManifest.xml`，在 `<manifest>` 下、`<application>` 之前加：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<!-- 相机拍票据；从相册选图由 image_picker 走系统选择器，Android 13+ 无需存储权限 -->
<uses-permission android:name="android.permission.CAMERA" />
```

`ios/Runner/Info.plist`，在最外层 `<dict>` 里加：

```xml
<key>NSCameraUsageDescription</key>
<string>拍摄车票、菜单等图片附加到行程条目</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>从相册选择图片附加到行程条目</string>
```

不需要定位权限：应用不读取用户位置，地点全部来自搜索或地图选点。

### 地图密钥

打开应用 → 右上角设置 → 填入其一或两者：

| 服务商 | 申请地址 | 用途 |
| --- | --- | --- |
| 高德 Web 服务 Key | console.amap.com（类型选「Web 服务」，**不是** Android/iOS SDK） | 境内 POI 搜索、逆地理、驾车/步行/公交路径 |
| Mapbox Access Token | account.mapbox.com 的默认 public token | 境外地理编码、驾车/步行/骑行路径 |

两个都不填也能用：底图退回 OpenStreetMap 公共瓦片，可以在地图上长按选点，只是没有搜索和真实导航几何（路线用直线估算，图上画成虚线）。

---

## 架构

```
lib/
├── core/            纯工具：金额、日期、坐标系、主题
├── data/
│   ├── db/          sqflite 建表与迁移
│   ├── models/      Trip / PlanItem / GeoPlace / Attachment
│   └── repositories/ 读写入口，UI 不直接碰 SQL
├── services/
│   ├── map/         MapProvider 抽象 + 高德 / Mapbox / OSM 实现 + 路径缓存
│   ├── currency/    汇率拉取与本地缓存
│   └── media/       图片落盘
├── domain/          纯计算，无 IO，全部可单测
│   ├── budget/      开销汇总
│   ├── review/      合理性规则引擎
│   └── route/       路线编译 + 顺序优化
├── providers/       Riverpod 状态
└── ui/              页面与组件
```

几个刻意的取舍：

**不使用代码生成。** 没有 freezed / json_serializable / drift codegen / riverpod_generator。模型的 `toRow` / `fromRow` 手写。代价是多写一些样板，换来的是 `git clone` 之后不需要跑 `build_runner` 就能编译，CI 也少一个环节。

**坐标统一以 WGS-84 存储。** 高德全程 GCJ-02，进出 `AmapProvider` 时转换；渲染时由 `MapDisplayAdapter` 按当前瓦片源的坐标系搬一次。这样切换服务商不会让已存的行程集体偏移几百米。

**金额用最小货币单位的整数。** `Money(12850, 'CNY')` 表示 128.50 元，日元等零小数位币种按 `Money(1200, 'JPY')`。跨币种加法直接抛异常而不是静默按 1:1 相加。拿不到汇率的条目不计入合计，而是单独计数并在界面上说明——宁可显示「3 笔未计入」，也不能让用户以为自己花得比实际少。

**地图渲染用 `flutter_map` 而非原生 SDK。** 纯 Dart，双端行为一致，不需要在 Gradle / CocoaPods 里塞两套密钥；服务商能力（搜索、导航）走 HTTP REST。代价是没有原生 SDK 的 3D 建筑和实时路况图层——对行程规划这个场景用不上。

**地图密钥存在设备本地，不打包进二进制。** 地图 API 按调用量计费，让每个用户用自己的配额；也免去密钥随 APK 泄露。

---

## 开销汇总

`BudgetCalculator.summarize` 是纯函数：给定行程、条目、汇率表，返回

- 每日：分类小计、当日合计、条目数、因缺汇率未计入的条目
- 全程：合计、日均、人均、分类占比、预算使用率、花得最多的一天

汇率来自 `open.er-api.com`（无需密钥），入库缓存 12 小时；离线时用上次拉到的值继续算，只是标注为过期。

## 合理性体检

`ItineraryReviewer` 跑一组规则，每条产出 `Advice{severity, code, title, detail, date, itemIds, action}`。加一条新检查 = 写一个 `ReviewRule` 实现并注册。

| code | 级别 | 检查什么 |
| --- | --- | --- |
| `item_out_of_range` | 冲突 | 改期后掉到行程区间之外的条目 |
| `time_overlap` | 冲突 | 同一天两项时间重叠 |
| `travel_infeasible` | 冲突 | 两项之间的空档装不下通勤时间 |
| `missing_lodging` | 提醒 | 中间某晚没住处，也没有跨夜交通 |
| `day_overloaded` | 提醒 | 单日在外时长超上限 |
| `day_overloaded_attractions` | 提醒 | 单日景点数超上限 |
| `route_detour` | 提醒 | 当天路径明显长于优化顺序，附建议顺序 |
| `over_budget` | 提醒 | 超总预算 / 单日显著高于日均 |
| `currency_missing_rate` | 提醒 | 有开销因缺汇率未计入合计 |
| `missing_meal` | 建议 | 午/晚餐时段没安排，且当时不在长途交通上 |
| `missing_location` | 建议 | 条目缺坐标，路线图会跳过 |
| `empty_day` | 建议 | 整天空白 |
| `unbooked_big_ticket` | 建议 | 大额住宿/交通还没标记已订 |

**通勤可达性**的判据：取前一项的终点到后一项的起点的直线距离，乘 1.35 绕行系数，除以交通方式的速度，加上该方式的固定开销（飞机 150 分钟含值机安检，高铁 40 分钟），再留 10 分钟容错。没有显式交通条目时按距离推断方式（1.2km 内步行 / 25km 内公交 / 300km 内铁路 / 更远飞机）。

**绕路检测**用「最近邻构造 + 2-opt 改良」算出优化顺序，与当前顺序的直线总里程比较，超过阈值倍数（默认 1.4）才提示。跨城的火车/飞机条目排除在外，否则里程会被拉爆。规则只给建议不自动改：顺序背后可能有营业时间、预约时段这类应用不知道的约束——「按建议重排」是用户点的按钮。

阈值都在设置页可调。

## 路线图

`RouteBuilder` 把条目编译成 `TripRoute`：每天一个 `DayRoute`（配色取自 10 色循环调色板），站点按时间轴排序并编号，相邻两站之间请求一段导航几何。

- 有密钥且服务商支持该方式 → 真实路径，实线
- 拿不到（跨城铁路/航班、无密钥、离线）→ 两点直线 + 速度模型估时，**虚线**，卡片上明说「虚线为直线估算」
- 结果按「服务商-方式-起讫点(4 位小数)」缓存 14 天，重复进入不重复计费

同一位置的连续条目（酒店退房 + 在酒店吃早餐）合并成一个点，不重复打标记。

---

## 测试

```bash
flutter test
```

覆盖的是值得回归的部分：

- `budget_test.dart` —— 分日/分类汇总、多币种折算、缺汇率不静默混入、预算超支、人均拆分、跨币种加法抛错
- `review_test.dart` —— 时间重叠、跨城赶不到 / 同城来得及、中间日缺住宿（末日不误报）、单日景点过载、区间外条目、健康分随冲突下降
- `geo_route_test.dart` —— GCJ-02 往返误差 <1m、境外不偏移、折线解码、2-opt 确实缩短路径、通勤耗时模型

UI 层没写 widget 测试：这一层变动频繁，回归价值不如上面这些确定性逻辑。

---

## 已知边界

- **本地优先，无云端同步。** 数据存在设备的 sqflite 里，换机不迁移。多人协作编辑同一份行程需要另加后端。
- **没有景点营业时间数据。** 「周一闭馆」这类冲突查不出来——需要接 POI 详情接口才能补上。
- **公交换乘只在高德侧可用。** Mapbox Directions 没有 transit profile，境外的地铁段目前按直线估算。
- **iOS 上没有做 Cupertino 风格分支。** 行程表是密集信息界面，两套控件维护两份布局不划算；滚动物理和返回手势由 Flutter 自动适配平台。
