import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/app_permissions.dart';
import 'package:zaihandazi/event_service.dart';
import 'package:zaihandazi/location_service.dart';
import 'package:zaihandazi/main.dart';

class _LocationPlatform extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  int permissionRequests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return permission = LocationPermission.whileInUse;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    latitude: 37.56,
    longitude: 126.97,
    timestamp: DateTime.now(),
    accuracy: 35,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual region selection persists and clears', () async {
    final service = LocationService();
    const selection = ManualRegionSelection(
      cityCode: 'KR-11',
      districtCode: 'KR-11-680',
    );

    await service.saveManualRegion(selection);
    final restored = await service.readManualRegion();

    expect(restored?.cityCode, selection.cityCode);
    expect(restored?.districtCode, selection.districtCode);

    await service.clearManualRegion();
    expect(await service.readManualRegion(), isNull);
  });

  test('administrative region falls back to a name instead of a code', () {
    const region = AdministrativeRegion(
      code: 'KR-11',
      level: 1,
      nameZhCn: '首尔特别市',
      nameKoKr: '서울특별시',
      nameEnUs: 'Seoul',
    );
    const fallback = AdministrativeRegion(
      code: 'KR-00',
      level: 1,
      nameZhCn: '测试地区',
      nameKoKr: '',
      nameEnUs: '',
    );
    const invalidChinese = AdministrativeRegion(
      code: 'KR-99',
      level: 2,
      nameZhCn: '의정부시',
      nameKoKr: '의정부시',
      nameEnUs: 'Uijeongbu-si',
    );

    expect(region.displayName('ko'), '서울특별시');
    expect(region.displayName('en'), 'Seoul');
    expect(region.displayName('zh'), '首尔特别市');
    expect(fallback.displayName('en'), '测试地区');
    expect(invalidChinese.displayName('zh'), '의정부시');
  });

  test(
    'GPS works without external geocoding and a revoked permission blocks cached coordinates',
    () async {
      SharedPreferences.setMockInitialValues({
        AppPermissions.key(AppPermission.location): true,
      });
      final previous = GeolocatorPlatform.instance;
      final platform = _LocationPlatform();
      GeolocatorPlatform.instance = platform;
      addTearDown(() => GeolocatorPlatform.instance = previous);
      var geocodingRequests = 0;
      final service = LocationService(
        client: MockClient((_) async {
          geocodingRequests++;
          return http.Response('{}', 500);
        }),
      );

      final location = await service.locate(languageCode: 'zh');
      expect(location.latitude, 37.56);
      expect(location.label, '已获取当前位置');
      expect(geocodingRequests, 0);

      platform.permission = LocationPermission.denied;
      await expectLater(
        service.locate(languageCode: 'zh'),
        throwsA(isA<LocationFailure>()),
      );
      expect(platform.permissionRequests, 0);
      await service.locate(
        languageCode: 'zh',
        forceRefresh: true,
        allowPermissionPrompt: true,
      );
      expect(platform.permissionRequests, 1);
    },
  );

  testWidgets(
    'manual area picker expands and closes without showing a district code',
    (tester) async {
      AppLocation? selected;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            DaziApp(
              home: Scaffold(
                body: HomePage(
                  events: const [],
                  onOpen: (_) {},
                  onRetry: () {},
                  onLocationChanged: (location) => selected = location,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('附近热门'), findsNothing);
          await tester.tap(find.text('选择位置'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('手动选择地区'));
          await tester.pumpAndSettle();
          expect(find.byType(DropdownButtonFormField<String>), findsNothing);
          final district = find.text('所在区域 · 全市');
          await tester.tap(district);
          await tester.pumpAndSettle();
          expect(find.text('성동구'), findsOneWidget);
          expect(find.text('KR-11200'), findsNothing);
          await tester.tap(district);
          await tester.pumpAndSettle();
          expect(find.text('성동구'), findsNothing);
          await tester.tap(district);
          await tester.pumpAndSettle();
          await tester.tap(find.text('성동구'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('使用所选地区'));
          await tester.pumpAndSettle();
          expect(selected?.districtCode, 'KR-11200');
          expect(find.text('首尔 · 성동구'), findsOneWidget);
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [
                {
                  'code': 'KR-11',
                  'level': 1,
                  'name_zh_cn': '首尔',
                  'name_ko_kr': '서울',
                },
                {
                  'code': 'KR-11200',
                  'parent_code': 'KR-11',
                  'level': 2,
                  'name_zh_cn': '성동구',
                  'name_ko_kr': '성동구',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
    },
  );

  testWidgets('activity cover offers camera and gallery choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      DaziApp(
        home: Scaffold(
          body: CreateEventPage(onCreated: (_) {}, loadRemoteData: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('选择并裁剪图片');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('拍摄照片'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);
  });
}
