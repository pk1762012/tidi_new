import 'package:tidistockmobileapp/theme/theme.dart';
import 'package:flutter/material.dart';

class AIBotButton extends StatefulWidget {
  final VoidCallback onTap;
  final String title;

  const AIBotButton({super.key, required this.title, required this.onTap});

  @override
  State<AIBotButton> createState() => _AIBotButtonState();
}

class _AIBotButtonState extends State<AIBotButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = lightColorScheme.primary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow
                  Container(
                    width: 110 * _scaleAnimation.value,
                    height: 110 * _scaleAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.4),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),

                  // Inner pulse
                  Container(
                    width: 90 * _scaleAnimation.value,
                    height: 90 * _scaleAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          primaryColor.withOpacity(0.4),
                          Colors.transparent,
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),

                  // Main button
                  GestureDetector(
                    onTap: widget.onTap,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        /*gradient: LinearGradient(
                          colors: [
                            primaryColor,
                            lightColorScheme.surface,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),*/
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .3),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
              child: Image.asset(
              'assets/images/tidi_ai.gif',
              fit: BoxFit.cover,
              width: 72,
              height: 72,
              ),
              ),

              ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 1),
          Text(
            widget.title,
            style: TextStyle(
              color: Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  blurRadius: 10,
                  color: lightColorScheme.primary,
                  offset: Offset(0, 2),
                ),
              ],
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
