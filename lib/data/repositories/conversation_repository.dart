import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local/db/app_database.dart';

class ConversationRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  ConversationRepository(this._db);

  Future<List<Conversation>> getAllConversations() {
    return (_db.select(_db.conversations)
          ..orderBy([(t) => OrderingTerm.desc(t.lastActive)]))
        .get();
  }

  Future<Conversation> createConversation(String title) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.conversations).insert(ConversationsCompanion.insert(
          id: id,
          title: title,
          createdAt: now,
          lastActive: now,
        ));
    return (await (_db.select(_db.conversations)
              ..where((t) => t.id.equals(id)))
            .getSingle());
  }

  Future<List<Message>> getMessages(String conversationId) {
    return (_db.select(_db.messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .get();
  }

  Future<void> addMessage(String conversationId, String sender, String text,
      String citationsJson) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.messages).insert(MessagesCompanion.insert(
          id: id,
          conversationId: conversationId,
          sender: sender,
          textContent: text,
          citationsJson: citationsJson,
          timestamp: now,
        ));
    // Update last active on conversation
    await (_db.update(_db.conversations)
          ..where((t) => t.id.equals(conversationId)))
        .write(ConversationsCompanion(lastActive: Value(now)));
  }

  Future<void> deleteConversation(String conversationId) async {
    await (_db.delete(_db.conversations)
          ..where((t) => t.id.equals(conversationId)))
        .go();
  }
}
