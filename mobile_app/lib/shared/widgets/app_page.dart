import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.header,
    required this.children,
    this.bottomClearance = 0,
    this.onRefresh,
  });

  final Widget header;
  final List<Widget> children;
  final double bottomClearance;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
      physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageGutter,
            AppSpacing.pageTop,
            AppSpacing.pageGutter,
            AppSpacing.pageBottom + bottomClearance,
          ),
          sliver: SliverList.separated(
            itemCount: children.length,
            itemBuilder: (context, index) => children[index],
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.sectionGap),
          ),
        ),
      ],
    );
    final refresh = onRefresh;
    if (refresh == null) return scrollView;
    return RefreshIndicator(
      color: AppColors.tealDark,
      onRefresh: refresh,
      child: scrollView,
    );
  }
}
