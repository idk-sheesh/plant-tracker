import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/utils/app_utils.dart';

void main() {
  test('timeAgo reste relatif au-dela de trente jours', () {
    final date = DateTime.now().subtract(const Duration(days: 45));

    expect(AppUtils.timeAgo(date), 'il y a 45j');
  });
}
