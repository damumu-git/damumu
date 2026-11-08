import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaihandazi/activity_text.dart';

void main() {
  test('formats estimated amounts with thousands separators', () {
    expect(formatThousands(0), '0');
    expect(formatThousands(999), '999');
    expect(formatThousands(1000), '1,000');
    expect(formatThousands(123456789), '123,456,789');
  });

  test('price input displays separators and remains parseable', () {
    const formatter = ThousandsInputFormatter();
    final value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '00123456',
        selection: TextSelection.collapsed(offset: 8),
      ),
    );

    expect(value.text, '123,456');
    expect(parseFormattedAmount(value.text), 123456);
  });
}
