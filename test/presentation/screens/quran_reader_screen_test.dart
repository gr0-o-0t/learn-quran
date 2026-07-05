import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/presentation/screens/quran_reader_screen.dart';

void main() {
  group('needsKbSetupPrompt', () {
    test('true when the KB has no content and the prompt was never dismissed', () {
      expect(needsKbSetupPrompt(hasContent: false, dismissedFlag: null), isTrue);
    });

    test('false once the KB has content, even if never dismissed', () {
      expect(needsKbSetupPrompt(hasContent: true, dismissedFlag: null), isFalse);
    });

    test('false once the user has dismissed the prompt, even with no content', () {
      expect(needsKbSetupPrompt(hasContent: false, dismissedFlag: 'true'), isFalse);
    });

    test('false when the KB has content and the prompt was dismissed', () {
      expect(
        needsKbSetupPrompt(hasContent: true, dismissedFlag: 'true'),
        isFalse,
      );
    });
  });
}
