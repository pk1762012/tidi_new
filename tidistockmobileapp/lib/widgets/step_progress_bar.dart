import 'package:flutter/material.dart';

/// Step progress bar matching prod StepProgressBar.js.
/// Shows 3 steps: Rebalance Preference -> Current Holdings -> Final Rebalance.
class StepProgressBar extends StatelessWidget {
  final int currentStep; // 1-based (1, 2, or 3)
  final String? broker;

  const StepProgressBar({
    super.key,
    required this.currentStep,
    this.broker,
  });

  static const _steps = [
    _StepInfo(
      label: 'Rebalance\nPreference',
      description: 'Review and confirm the proposed rebalance changes.',
    ),
    _StepInfo(
      label: 'Current\nHoldings',
      description: 'Verify your current stock holdings. Edit if needed.',
    ),
    _StepInfo(
      label: 'Final\nRebalance',
      description: 'Confirm orders to be placed with your broker.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final stepBefore = (i ~/ 2) + 1;
            final isCompleted = stepBefore < currentStep;
            return Expanded(
              child: Container(
                height: 2,
                color: isCompleted
                    ? const Color(0xFF0D9488)
                    : const Color(0xFFE0E0E0),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final stepNumber = stepIndex + 1;
          final isCompleted = stepNumber < currentStep;
          final isActive = stepNumber == currentStep;
          return _buildStep(stepNumber, _steps[stepIndex], isCompleted, isActive);
        }),
      ),
    );
  }

  Widget _buildStep(int number, _StepInfo info, bool isCompleted, bool isActive) {
    final Color circleColor;
    final Widget circleChild;

    if (isCompleted) {
      circleColor = const Color(0xFF0D9488);
      circleChild = const Icon(Icons.check, size: 14, color: Colors.white);
    } else if (isActive) {
      circleColor = const Color(0xFF0D9488);
      circleChild = Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    } else {
      circleColor = const Color(0xFFBDBDBD);
      circleChild = Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isActive ? 30 : 26,
          height: isActive ? 30 : 26,
          decoration: BoxDecoration(
            color: circleColor,
            shape: BoxShape.circle,
            border: isActive
                ? Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.3), width: 3)
                : null,
          ),
          alignment: Alignment.center,
          child: circleChild,
        ),
        const SizedBox(height: 6),
        Text(
          info.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive
                ? const Color(0xFF0D9488)
                : isCompleted
                    ? const Color(0xFF424242)
                    : const Color(0xFF9E9E9E),
          ),
        ),
      ],
    );
  }
}

class _StepInfo {
  final String label;
  final String description;
  const _StepInfo({required this.label, required this.description});
}
