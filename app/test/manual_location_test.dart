import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/event_service.dart';
import 'package:zaihandazi/location_service.dart';

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

  test('administrative region never mixes another language as fallback', () {
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

    expect(region.displayName('ko'), '서울특별시');
    expect(region.displayName('en'), 'Seoul');
    expect(region.displayName('zh'), '首尔特别市');
    expect(fallback.displayName('en'), 'KR-00');
  });
}
