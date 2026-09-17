import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/features/more/widgets/more_header.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: MoreHeader(
            title: 'About AquaLogic',
            subtitle: 'Calm, trustworthy aquarium operations',
            onBack: () => Navigator.of(context).pop(),
          ),
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.mint,
                        child: Icon(
                          LucideIcons.droplets,
                          color: AppColors.tealDark,
                        ),
                      ),
                      SizedBox(width: 11),
                      Expanded(
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'AquaLogic',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'A local-first aquarium monitoring and operations experience for JRed Aquatics.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const InfoRow(
                    label: 'Surface',
                    value: 'Android-first mobile prototype',
                    icon: LucideIcons.smartphone,
                  ),
                  const Divider(height: 1),
                  const InfoRow(
                    label: 'Data mode',
                    value: 'Local mock repositories',
                    icon: LucideIcons.database,
                  ),
                ],
              ),
            ),
            const EmptyState(
              title: 'Backend integration is deferred',
              message:
                  'This interface is prepared for future API repositories. It does not send commands or connect to production services.',
              icon: LucideIcons.info,
            ),
          ],
        ),
      ),
    );
  }
}
