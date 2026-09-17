import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.header,
    required this.children,
    this.bottomClearance = 0,
  });

  final Widget header;
  final List<Widget> children;
  final double bottomClearance;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
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
  }
}
