import 'package:flutter/material.dart';

import '../widgets/delegation_graph_widget.dart';

class DelegationGraphScreen extends StatelessWidget {
  final String rootUserId;

  const DelegationGraphScreen({required this.rootUserId, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delegation Graph'),
      ),
      body: DelegationGraphWidget(rootUserId: rootUserId),
    );
  }
}
