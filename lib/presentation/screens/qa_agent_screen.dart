import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/services/llm_service.dart';
import '../../data/repositories/rag_repository.dart';
import '../../data/local/db/app_database.dart';
import 'settings_screen.dart';

/// Engagement-value key: once the user dismisses the AI setup prompt (or
/// finishes it with a model downloaded), this screen stops re-showing it.
const aiSetupPromptDismissedKey = 'ai_setup_prompt_dismissed';

/// True if the AI setup prompt should be shown instead of the chat UI:
/// no model is downloaded yet ([modelPath] null) and the user hasn't
/// already dismissed the prompt ([dismissedFlag] isn't `'true'`).
bool needsAiSetupPrompt({required String? modelPath, required String? dismissedFlag}) {
  return modelPath == null && dismissedFlag != 'true';
}

class QaAgentScreen extends ConsumerStatefulWidget {
  const QaAgentScreen({super.key});

  @override
  ConsumerState<QaAgentScreen> createState() => _QaAgentScreenState();
}

class _QaAgentScreenState extends ConsumerState<QaAgentScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _currentConversationId;
  bool _isGenerating = false;
  List<Map<String, dynamic>> _messages = [];
  bool _checkingAiSetup = true;
  bool _needsAiSetup = false;

  static const List<String> _suggestedPrompts = [
    'What does the Quran say about kindness to parents?',
    'How did the Prophet deal with sadness?',
    'Explain Surah Al-Fatiha',
    'What is the importance of Salat?',
    'What does Islam say about forgiveness?',
    'How to find peace in difficult times?',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _checkAiSetup());
    Future.microtask(() => _initChat());
  }

  Future<void> _checkAiSetup() async {
    final llmService = ref.read(llmServiceProvider);
    final userRepo = ref.read(userRepositoryProvider);
    final modelPath = await llmService.getSelectedModelPath();
    final dismissed = await userRepo.getEngagementValue(aiSetupPromptDismissedKey);
    if (mounted) {
      setState(() {
        _needsAiSetup = needsAiSetupPrompt(modelPath: modelPath, dismissedFlag: dismissed);
        _checkingAiSetup = false;
      });
    }
  }

  Future<void> _openAiSetup() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Set Up AI Model')),
        body: const SettingsScreen(),
      ),
    ));
    await _checkAiSetup();
  }

  Future<void> _skipAiSetup() async {
    final userRepo = ref.read(userRepositoryProvider);
    await userRepo.setEngagementValue(aiSetupPromptDismissedKey, 'true');
    if (mounted) setState(() => _needsAiSetup = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    final convoRepo = ref.read(conversationRepositoryProvider);
    final convos = await convoRepo.getAllConversations();
    
    if (convos.isEmpty) {
      final newConvo = await convoRepo.createConversation('General Q&A');
      _currentConversationId = newConvo.id;
    } else {
      _currentConversationId = convos.first.id;
    }

    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (_currentConversationId == null) return;
    
    final convoRepo = ref.read(conversationRepositoryProvider);
    final msgs = await convoRepo.getMessages(_currentConversationId!);
    
    if (mounted) {
      setState(() {
        _messages = msgs.map((m) {
          String citationStr = '';
          try {
            if (m.citationsJson.isNotEmpty) {
              final List<dynamic> citList = jsonDecode(m.citationsJson);
              citationStr = citList.map((e) => e['title'] as String).join(' • ');
            }
          } catch (_) {}

          return {
            'sender': m.sender,
            'text': m.textContent,
            'citations': citationStr,
          };
        }).toList();
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _createNewConversation() async {
    final convoRepo = ref.read(conversationRepositoryProvider);
    final newConvo = await convoRepo.createConversation('New Chat');
    setState(() {
      _currentConversationId = newConvo.id;
    });
    await _loadMessages();
  }

  Future<void> _deleteConversation(String convoId, StateSetter setSheetState) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat?'),
        content: const Text('Are you sure you want to delete this conversation? All messages will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final convoRepo = ref.read(conversationRepositoryProvider);
      await convoRepo.deleteConversation(convoId);

      if (_currentConversationId == convoId) {
        final convos = await convoRepo.getAllConversations();
        if (convos.isEmpty) {
          final newConvo = await convoRepo.createConversation('General Q&A');
          _currentConversationId = newConvo.id;
        } else {
          _currentConversationId = convos.first.id;
        }
        await _loadMessages();
      }

      setSheetState(() {});
      setState(() {});
    }
  }

  void _showHistoryBottomSheet() {
    final convoRepo = ref.read(conversationRepositoryProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.softIvory,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.textMuted.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Chat History',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.forestGreen,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final newConvo = await convoRepo.createConversation('New Chat');
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  setState(() {
                                    _currentConversationId = newConvo.id;
                                  });
                                  await _loadMessages();
                                }
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('New Chat'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.emeraldGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: FutureBuilder<List<Conversation>>(
                          future: convoRepo.getAllConversations(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(color: AppTheme.emeraldGreen),
                              );
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            final convos = snapshot.data ?? [];
                            if (convos.isEmpty) {
                              return const Center(child: Text('No conversations yet.'));
                            }

                            return ListView.builder(
                              controller: scrollController,
                              itemCount: convos.length,
                              itemBuilder: (context, index) {
                                final convo = convos[index];
                                final isCurrent = convo.id == _currentConversationId;
                                final timeStr = _formatRelativeTime(convo.lastActive);

                                return ListTile(
                                  leading: Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: isCurrent ? AppTheme.emeraldGreen : AppTheme.textMuted,
                                  ),
                                  title: Text(
                                    convo.title,
                                    style: GoogleFonts.inter(
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      color: isCurrent ? AppTheme.emeraldGreen : AppTheme.textCharcoal,
                                    ),
                                  ),
                                  subtitle: Text(
                                    timeStr,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                    onPressed: () => _deleteConversation(convo.id, setSheetState),
                                  ),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    setState(() {
                                      _currentConversationId = convo.id;
                                    });
                                    await _loadMessages();
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatRelativeTime(int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - timestamp;
    if (diff < 0) return 'Just now';
    if (diff < 60) {
      return 'Just now';
    } else if (diff < 3600) {
      final minutes = diff ~/ 60;
      return '$minutes min ago';
    } else if (diff < 86400) {
      final hours = diff ~/ 3600;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (diff < 172800) {
      return 'Yesterday';
    } else {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final month = months[dt.month - 1];
      return '$month ${dt.day}';
    }
  }

  Widget _buildHeader(ThemeData theme) {
    final convoRepo = ref.read(conversationRepositoryProvider);
    return FutureBuilder<List<Conversation>>(
      future: convoRepo.getAllConversations(),
      builder: (context, snapshot) {
        String title = 'General Q&A';
        if (snapshot.hasData && _currentConversationId != null) {
          final current = snapshot.data!.firstWhere(
            (c) => c.id == _currentConversationId,
            orElse: () => const Conversation(id: '', title: 'General Q&A', createdAt: 0, lastActive: 0),
          );
          if (current.id.isNotEmpty) {
            title = current.title;
          }
        }
        
        final displayTitle = title.length > 25 ? '${title.substring(0, 22)}...' : title;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          color: AppTheme.surfaceMint.withValues(alpha: 0.5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.forum_outlined, color: AppTheme.forestGreen, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    displayTitle,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textCharcoal,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_comment_outlined, size: 20),
                    color: AppTheme.forestGreen,
                    tooltip: 'New Chat',
                    onPressed: _createNewConversation,
                  ),
                  IconButton(
                    icon: const Icon(Icons.history_rounded, size: 20),
                    color: AppTheme.forestGreen,
                    tooltip: 'Chat History',
                    onPressed: _showHistoryBottomSheet,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isGenerating || _currentConversationId == null) return;

    _controller.clear(); // Clear input text field immediately for responsive feel!

    final convoRepo = ref.read(conversationRepositoryProvider);
    final ragRepo = ref.read(ragRepositoryProvider);
    final llmService = ref.read(llmServiceProvider);

    // 1. Save user message
    await convoRepo.addMessage(_currentConversationId!, 'user', text, '[]');
    // Log search/question event for engagement tracking
    unawaited(ref.read(engagementServiceProvider).logSearchEvent(text));
    await _loadMessages();

    setState(() {
      _isGenerating = true;
      // Add a temporary loading message for the agent with empty content
      _messages.add({
        'sender': 'agent',
        'text': '',
        'citations': '',
      });
    });
    _scrollToBottom();

    try {
      // 2. Perform RAG query
      final ragResults = await ragRepo.search(text, limit: 3);
      
      final List<Map<String, String>> citationsList = [];
      final StringBuffer contextBuffer = StringBuffer();
      
      for (final res in ragResults) {
        String title = '';
        String textContent = '';
        
        if (res.type == RagSourceType.verse && res.verse != null) {
          title = 'Surah Al-${res.verse!.surahNumber}:${res.verse!.ayahNumber}';
          textContent = res.verse!.englishText;
        } else if (res.type == RagSourceType.hadith && res.hadith != null) {
          title = '${res.hadith!.bookName} Hadith ${res.hadith!.hadithNumber}';
          textContent = res.hadith!.englishText;
        } else if (res.type == RagSourceType.tafsir && res.tafsir != null) {
          title = 'Tafsir Al-${res.tafsir!.surahNumber}:${res.tafsir!.ayahNumber}';
          textContent = res.tafsir!.contentEnglish;
        }
        
        if (title.isNotEmpty) {
          citationsList.add({'title': title});
          contextBuffer.write('$textContent ');
        }
      }

      final citationsStr = citationsList.map((e) => e['title']!).join(' • ');
      final ragContext = contextBuffer.toString();

      // 3. Call LLM Service Stream
      final responseStream = llmService.generateResponseStream(text, ragContext);
      String fullAgentResponse = '';

      await for (final chunk in responseStream) {
        if (!mounted) return;
        fullAgentResponse += chunk;
        
        setState(() {
          _messages[_messages.length - 1] = {
            'sender': 'agent',
            'text': fullAgentResponse,
            'citations': citationsStr,
          };
        });
        _scrollToBottom();
      }

      // 4. Save final complete agent response to database
      await convoRepo.addMessage(
        _currentConversationId!,
        'agent',
        fullAgentResponse,
        jsonEncode(citationsList),
      );
    } catch (_) {
      setState(() {
        _messages[_messages.length - 1] = {
          'sender': 'agent',
          'text': 'Forgive me, but I encountered an error answering your question. Please try again.',
          'citations': '',
        };
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_checkingAiSetup) {
      return const SafeArea(
        child: Center(child: CircularProgressIndicator(color: AppTheme.emeraldGreen)),
      );
    }
    if (_needsAiSetup) {
      return _AiSetupPrompt(onSetUp: _openAiSetup, onSkip: _skipAiSetup);
    }

    return SafeArea(
      child: Column(
        children: [
          _buildHeader(theme),
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              itemCount: _messages.length + 1, // +1 for suggested prompts
              itemBuilder: (context, index) {
                if (index == 0) {
                  if (_messages.isNotEmpty) return const SizedBox.shrink();
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'As-Salamu Alaykum',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.forestGreen,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'How can I help you understand the Quran today?',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _suggestedPrompts
                              .map((prompt) => ActionChip(
                                    label: Text(
                                      prompt,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: AppTheme.forestGreen,
                                      ),
                                    ),
                                    backgroundColor:
                                        AppTheme.emeraldGreen.withValues(alpha: 0.08),
                                    side: BorderSide(
                                      color:
                                          AppTheme.emeraldGreen.withValues(alpha: 0.2),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    onPressed: _isGenerating ? null : () => _sendMessage(prompt),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  );
                }

                final msg = _messages[index - 1];
                final isUser = msg['sender'] == 'user';
                final text = msg['text'] as String;
                final citations = msg['citations'] as String;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isUser
                            ? AppTheme.emeraldGreen
                            : AppTheme.surfaceMint,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isUser && text.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: _TypingIndicator(),
                            )
                          else
                            Text(
                              text,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: isUser ? Colors.white : AppTheme.textCharcoal,
                                height: 1.4,
                              ),
                            ),
                          if (citations.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: Colors.black12),
                            const SizedBox(height: 6),
                            Text(
                              'Sources: $citations',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.forestGreen,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Message input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_isGenerating,
                      decoration: InputDecoration(
                        hintText: _isGenerating ? 'Generating response...' : 'Ask about Quran, Hadith...',
                        border: InputBorder.none,
                        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded),
                    color: AppTheme.emeraldGreen,
                    onPressed: _isGenerating ? null : () => _sendMessage(_controller.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSetupPrompt extends StatelessWidget {
  const _AiSetupPrompt({required this.onSetUp, required this.onSkip});

  final VoidCallback onSetUp;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.smart_toy_rounded,
              size: 72,
              color: AppTheme.emeraldGreen,
            ),
            const SizedBox(height: 24),
            Text(
              'Set Up Your AI Companion',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.forestGreen,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Download an on-device AI model in Settings so your questions '
              'get real, private answers grounded in the Quran and Hadith. '
              'Until then, you\'ll only see limited demo responses.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSetUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emeraldGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Set Up AI Model'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onSkip,
              child: const Text(
                'Skip for now',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double delay = index * 0.2;
            double progress = (_controller.value - delay) % 1.0;
            if (progress < 0) progress += 1.0;

            double opacity = 0.3;
            if (progress < 0.4) {
              opacity = 0.3 + (progress / 0.4) * 0.7;
            } else if (progress < 0.8) {
              opacity = 1.0 - ((progress - 0.4) / 0.4) * 0.7;
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppTheme.forestGreen.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
