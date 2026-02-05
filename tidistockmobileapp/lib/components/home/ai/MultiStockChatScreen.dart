import 'dart:convert';
import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../service/ApiService.dart';
import '../../../widgets/customScaffold.dart';

class MultiStockChatScreen extends StatefulWidget {
  final dynamic symbols;

  const MultiStockChatScreen({super.key, required this.symbols});

  @override
  State<MultiStockChatScreen> createState() => _MultiStockChatScreenState();
}

class _MultiStockChatScreenState extends State<MultiStockChatScreen> with TickerProviderStateMixin {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isThinking = false;

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        sender: Sender.user,
        controller: _createAnimationController(),
      ));
      _isThinking = true;
    });
    _controller.clear();

    _messages.last.controller.forward();
    _scrollToBottom();

    try {
      final history = _messages.map((msg) => msg.text).toList();
      ApiService apiService = ApiService();
      final List<String> updatedSymbols = widget.symbols.map<String>((s) => '${s['symbol']}.NS').toList();

      final response = await apiService.multiStockChat(
        updatedSymbols,
        history,
        text,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final botResponse = data['answer'] ?? 'Sorry, I couldn’t understand that.';

        final botMsg = _ChatMessage(
          text: botResponse,
          sender: Sender.bot,
          controller: _createAnimationController(),
        );

        setState(() {
          _messages.add(botMsg);
          _isThinking = false;
        });

        botMsg.controller.forward();
      } else {
        throw Exception('Server error ${response.statusCode}');
      }
    } catch (e) {
      final errorMsg = _ChatMessage(
        text: 'Oops! Something went wrong. Please try again.',
        sender: Sender.bot,
        controller: _createAnimationController(),
      );
      setState(() {
        _messages.add(errorMsg);
        _isThinking = false;
      });
      errorMsg.controller.forward();
    }

    _scrollToBottom();
  }

  AnimationController _createAnimationController() {
    return AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearMessages() {
    for (var msg in _messages) {
      msg.controller.dispose();
    }
    setState(() {
      _messages.clear();
      _isThinking = false;
    });
  }

  @override
  void dispose() {
    for (var msg in _messages) {
      msg.controller.dispose();
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      menu: null,
      allowBackNavigation: true,
      displayActions: false,
      imageUrl: null,
      child: Column(
        children: [
          // Top Bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Top Bar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_messages.isNotEmpty) // 👈 show only if chat has messages
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: Icon(Icons.delete_outline, color: lightColorScheme.primary),
                            tooltip: 'Clear chat',
                            onPressed: _clearMessages,
                          ),
                        ),
                    ],
                  ),
                ),

                Center(
                  child: Text(
                    'Comparing: \n' +
                        widget.symbols
                            .map<String>((s) => '${s['symbol']}')
                            .join(' * '),
                    style: TextStyle(
                      color: lightColorScheme.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 2),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Messages List
          Expanded(
            child: Stack(
              children: [

                // Background logo
                Positioned.fill(
                  child: Center(
                    child: Opacity(
                      opacity: 0.2,
                      child: Image.asset(
                        'assets/images/tidi_one_1024.png',
                        width: 400,
                        height: 400,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),

                // Chat messages container
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: lightColorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isThinking ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isThinking && index == _messages.length) {
                        return const TypingIndicator();
                      }

                      final msg = _messages[index];

                      final bgColor = msg.sender == Sender.user
                          ? lightColorScheme.primary.withOpacity(0.85)
                          : lightColorScheme.secondary.withOpacity(0.25);
                      final textColor = msg.sender == Sender.user
                          ? lightColorScheme.onPrimary
                          : lightColorScheme.primary;

                      return SizeTransition(
                        sizeFactor: CurvedAnimation(parent: msg.controller, curve: Curves.easeOut),
                        axisAlignment: 0,
                        child: FadeTransition(
                          opacity: msg.controller,
                          child: Align(
                            alignment: msg.sender == Sender.user
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(msg.sender == Sender.user ? 16 : 0),
                                  bottomRight: Radius.circular(msg.sender == Sender.user ? 0 : 16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: MarkdownBody(
                                data: msg.text,
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(color: textColor, fontSize: 15),
                                  strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                                ),
                                selectable: false,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Input Field + Send Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: lightColorScheme.primary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: lightColorScheme.primary),
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        hintStyle: TextStyle(color: lightColorScheme.primary.withOpacity(0.6)),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                AnimatedSendButton(onTap: _sendMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Send Button with animation
class AnimatedSendButton extends StatefulWidget {
  final VoidCallback onTap;
  const AnimatedSendButton({required this.onTap, super.key});

  @override
  State<AnimatedSendButton> createState() => _AnimatedSendButtonState();
}

class _AnimatedSendButtonState extends State<AnimatedSendButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onTap() async {
    await _animController.forward();
    await _animController.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [lightColorScheme.primary, lightColorScheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.send, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

// Chat message class
enum Sender { user, bot }

class _ChatMessage {
  final String text;
  final Sender sender;
  final AnimationController controller;

  _ChatMessage({required this.text, required this.sender, required this.controller});
}

// Typing Indicator
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _dots;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this)..repeat();
    _dots = StepTween(begin: 1, end: 3).animate(_controller);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, child) {
        final dots = '.' * _dots.value;
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            decoration: BoxDecoration(
              color: lightColorScheme.secondary.withOpacity(0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Text(
              dots,
              style: const TextStyle(color: Colors.black, fontStyle: FontStyle.italic, fontSize: 18),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
