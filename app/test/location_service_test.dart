import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/location_service.dart';

void main() {
  test('resolves a coordinate to an API administrative region', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/regions/resolve');
      expect(request.url.queryParameters['latitude'], '37.4784000');
      expect(request.url.queryParameters['longitude'], '126.9516000');
      return http.Response(
        jsonEncode({
          'data': {
            'code': 'KR-11620',
            'name_zh_cn': '冠岳区',
            'name_ko_kr': '관악구',
            'name_en_us': 'Gwanak-gu',
            'city_name_zh_cn': '首尔特别市',
            'city_name_ko_kr': '서울특별시',
            'city_name_en_us': 'Seoul',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final location = await LocationService(client: client).resolveRegion(
      37.4784,
      126.9516,
      languageCode: 'zh',
    );

    expect(location.regionCode, 'KR-11620');
    expect(location.label, '首尔特别市 · 冠岳区');
    expect(location.latitude, 37.4784);
    expect(location.longitude, 126.9516);
  });
}
