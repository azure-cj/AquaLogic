import 'package:flutter/material.dart';

class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.header, required this.children});

  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
          sliver: SliverList.separated(
            itemCount: children.length,
            itemBuilder: (context, index) => children[index],
            separatorBuilder: (context, index) => const SizedBox(height: 12),
          ),
        ),
      ],
    );
  }
}
