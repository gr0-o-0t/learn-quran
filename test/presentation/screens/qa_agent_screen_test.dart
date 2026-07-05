import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/presentation/screens/qa_agent_screen.dart';

void main() {
  group('needsAiSetupPrompt', () {
    test('true when no model is downloaded and the prompt was never dismissed', () {
      expect(needsAiSetupPrompt(modelPath: null, dismissedFlag: null), isTrue);
    });

    test('false once a model is downloaded, even if never dismissed', () {
      expect(needsAiSetupPrompt(modelPath: '/models/e2b.gguf', dismissedFlag: null), isFalse);
    });

    test('false once the user has dismissed the prompt, even with no model', () {
      expect(needsAiSetupPrompt(modelPath: null, dismissedFlag: 'true'), isFalse);
    });

    test('false when a model is downloaded and the prompt was dismissed', () {
      expect(
        needsAiSetupPrompt(modelPath: '/models/e2b.gguf', dismissedFlag: 'true'),
        isFalse,
      );
    });
  });
}
