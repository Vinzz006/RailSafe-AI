import 'package:flutter_test/flutter_test.dart';
import 'package:railsafe_ai/core/constants/app_constants.dart';

void main() {
  test('App configuration constants sanity check', () {
    expect(AppConstants.appName, equals("RailSafe AI"));
    expect(AppConstants.appSubtitle, equals("Handheld Screening Assistance"));
  });
}
