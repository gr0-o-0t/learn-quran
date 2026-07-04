import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/repositories/conversation_repository.dart';

void main() {
  late AppDatabase db;
  late ConversationRepository repository;

  setUp(() async {
    // Enable foreign keys for CASCADE delete to work in SQLite memory DB
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: (rawDb) {
      rawDb.execute('PRAGMA foreign_keys = ON;');
    }));
    repository = ConversationRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ConversationRepository Tests', () {
    test('createConversation and getAllConversations works', () async {
      var list = await repository.getAllConversations();
      expect(list, isEmpty);

      final convo1 = await repository.createConversation('Patience in Islam');
      expect(convo1.title, 'Patience in Islam');
      expect(convo1.id, isNotEmpty);

      // Delay to ensure next conversation has a distinct lastActive timestamp
      await Future.delayed(const Duration(milliseconds: 1100));

      final convo2 = await repository.createConversation('Daily Prayers');
      expect(convo2.title, 'Daily Prayers');

      list = await repository.getAllConversations();
      expect(list.length, 2);
      expect(list[0].title, 'Daily Prayers'); // last active first
      expect(list[1].title, 'Patience in Islam');
    });

    test('addMessage and getMessages works', () async {
      final convo = await repository.createConversation('Hadith Q&A');
      
      var messages = await repository.getMessages(convo.id);
      expect(messages, isEmpty);

      await repository.addMessage(convo.id, 'user', 'What is the Hadith about intentions?', '[]');
      await repository.addMessage(convo.id, 'agent', 'It is: Actions are but by intention...', '[{"title":"Bukhari 1"}]');

      messages = await repository.getMessages(convo.id);
      expect(messages.length, 2);
      expect(messages[0].sender, 'user');
      expect(messages[0].textContent, 'What is the Hadith about intentions?');
      expect(messages[1].sender, 'agent');
      expect(messages[1].citationsJson, '[{"title":"Bukhari 1"}]');
    });

    test('deleteConversation deletes convo and cascading messages', () async {
      final convo = await repository.createConversation('Delete Me');
      await repository.addMessage(convo.id, 'user', 'Hello', '[]');

      var convos = await repository.getAllConversations();
      var messages = await repository.getMessages(convo.id);
      expect(convos.length, 1);
      expect(messages.length, 1);

      await repository.deleteConversation(convo.id);

      convos = await repository.getAllConversations();
      expect(convos, isEmpty);
      
      // Messages should be deleted due to CASCADE
      final allMessages = await db.select(db.messages).get();
      expect(allMessages, isEmpty);
    });
  });
}
