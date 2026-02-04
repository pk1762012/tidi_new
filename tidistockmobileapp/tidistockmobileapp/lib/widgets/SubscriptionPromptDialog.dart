import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../components/home/profile/SubscriptionPlanScreen.dart';

class SubscriptionPromptDialog extends StatelessWidget {
  final BuildContext parentContext;

  const SubscriptionPromptDialog({super.key, required this.parentContext});

  static void show(BuildContext parentContext) {
    showDialog(
      context: parentContext,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return SubscriptionPromptDialog(parentContext: parentContext);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 2 / 1, // width : height
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SvgPicture.asset(
                  'assets/images/tidi_join.svg',
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            /*Text(
              'Subscription Required',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),*/
            Text(
              'Access to this feature is limited to TIDI Wealth members. Please join to continue.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                showSubscriptionBottomCurtain(parentContext);

              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Join Now',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
