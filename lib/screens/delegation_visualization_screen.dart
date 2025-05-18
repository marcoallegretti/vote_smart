import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/delegation_service.dart';
import '../services/audit_service.dart';
import '../services/database_service.dart';
import 'dart:math' as math;
import '../widgets/loading_indicator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/data_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'delegation_audit_screen.dart';

class DelegationVisualizationScreen extends StatefulWidget {
  final String? topicId;
  final String? topicTitle;
  final DatabaseService databaseService;
  final AuditService auditService;

  const DelegationVisualizationScreen({
    super.key,
    this.topicId,
    this.topicTitle,
    required this.databaseService,
    required this.auditService,
  });

  @override
  State<DelegationVisualizationScreen> createState() =>
      _DelegationVisualizationScreenState();
}

class _DelegationVisualizationScreenState
    extends State<DelegationVisualizationScreen> with SingleTickerProviderStateMixin {
  late final DelegationService _delegationService;
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _isLoading = false;
  Map<String, DelegationNode> _delegationGraph = {};
  bool _showMetrics = true;
  double _voteWeight = 1.0;
  late TabController _tabController;
  List<UserModel> _topDelegates = [];
  Map<String, double> _influenceDistribution = {};

  @override
  void initState() {
    super.initState();
    _delegationService = DelegationService.withInstance(
      firestoreInstance: FirebaseFirestore.instance,
      databaseService: widget.databaseService,
      auditService: widget.auditService,
    );
    _tabController = TabController(length: 3, vsync: this);
    _loadDelegationGraph();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDelegationGraph() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load delegation graph and vote weight
      final graph = await _delegationService.getDelegationGraph(_currentUserId);
      final weight = await _delegationService
          .calculateRepresentedVoterCount(_currentUserId, topicId: widget.topicId);
      
      // Calculate top delegates by influence
      final topDelegates = await _calculateTopDelegates(graph);
      
      // Calculate influence distribution
      final influenceDistribution = _calculateInfluenceDistribution(graph);

      setState(() {
        _delegationGraph = graph;
        _voteWeight = weight;
        _topDelegates = topDelegates;
        _influenceDistribution = influenceDistribution;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading delegation graph: $e');
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load delegation relationships');
    }
  }
  
  Future<List<UserModel>> _calculateTopDelegates(Map<String, DelegationNode> graph) async {
    // Calculate the number of delegations to each user
    final Map<String, int> delegationCounts = {};
    
    for (final node in graph.values) {
      for (final _ in node.delegatedFrom) {
        delegationCounts[node.user.id] = (delegationCounts[node.user.id] ?? 0) + 1;
      }
    }
    
    // Sort users by delegation count
    final sortedUserIds = delegationCounts.keys.toList()
      ..sort((a, b) => delegationCounts[b]!.compareTo(delegationCounts[a]!));
    
    // Get top 5 users
    final topUserIds = sortedUserIds.take(5).toList();
    final List<UserModel> topUsers = [];
    
    for (final userId in topUserIds) {
      if (graph.containsKey(userId)) {
        topUsers.add(graph[userId]!.user);
      }
    }
    
    return topUsers;
  }
  
  Map<String, double> _calculateInfluenceDistribution(Map<String, DelegationNode> graph) {
    final Map<String, double> distribution = {};
    
    // Calculate total delegations
    int totalDelegations = 0;
    for (final node in graph.values) {
      totalDelegations += node.delegatedFrom.length;
    }
    
    if (totalDelegations == 0) return {};
    
    // Calculate percentage for each user with delegations
    for (final entry in graph.entries) {
      final node = entry.value;
      if (node.delegatedFrom.isNotEmpty) {
        final percentage = node.delegatedFrom.length / totalDelegations * 100;
        distribution[node.user.name] = percentage;
      }
    }
    
    return distribution;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.topicId != null
        ? 'Delegation Network: ${widget.topicTitle}'
        : 'My Delegation Network';

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          IconButton(
            icon: Icon(_showMetrics ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                _showMetrics = !_showMetrics;
              });
            },
            tooltip: _showMetrics ? 'Hide Metrics' : 'Show Metrics',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => DelegationAuditScreen(
                    databaseService: widget.databaseService,
                    auditService: widget.auditService,
                  ),
                ),
              );
            },
            tooltip: 'View Audit Trail',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDelegationGraph,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Network'),
            Tab(text: 'Influence'),
            Tab(text: 'Top Delegates'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: LoadingIndicator())
          : Column(
              children: [
                if (_showMetrics) _buildMetricsPanel(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDelegationGraph(),
                      _buildInfluenceDistribution(),
                      _buildTopDelegatesView(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMetricsPanel() {
    final directDelegations =
        _delegationGraph[_currentUserId]?.delegatedFrom.length ?? 0;
    final transitiveWeight = _voteWeight - 1.0 - directDelegations;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Vote Weight: ${_voteWeight.toStringAsFixed(1)}x',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMetricItem(
                'Your Vote',
                '1.0',
                Icons.person,
                Colors.blue,
              ),
              _buildMetricItem(
                'Direct Delegations',
                directDelegations.toString(),
                Icons.connect_without_contact,
                Colors.green,
              ),
              _buildMetricItem(
                'Transitive Influence',
                transitiveWeight > 0
                    ? transitiveWeight.toStringAsFixed(1)
                    : '0',
                Icons.share,
                Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDelegationGraph() {
    if (_delegationGraph.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.account_tree,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No delegation network found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create delegations to visualize your network',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Delegation Network Visualization',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            boundaryMargin: const EdgeInsets.all(100),
            minScale: 0.5,
            maxScale: 2.5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CustomPaint(
                  size: const Size(300, 300),
                  painter: DelegationGraphPainter(
                    delegationGraph: _delegationGraph,
                    currentUserId: _currentUserId,
                    context: context,
                  ),
                  child: Container(),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Pinch to zoom, drag to pan',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
  
  Widget _buildInfluenceDistribution() {
    if (_influenceDistribution.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.pie_chart,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No influence data available',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create delegations to see influence distribution',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Delegation Influence Distribution',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: _getInfluencePieSections(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Influence Legend:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ..._getInfluenceLegendItems(),
            ],
          ),
        ),
      ],
    );
  }
  
  List<PieChartSectionData> _getInfluencePieSections() {
    final List<PieChartSectionData> sections = [];
    final List<Color> colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.amber,
      Colors.pink,
    ];
    
    int colorIndex = 0;
    _influenceDistribution.forEach((name, percentage) {
      sections.add(
        PieChartSectionData(
          color: colors[colorIndex % colors.length],
          value: percentage,
          title: '${percentage.toStringAsFixed(1)}%',
          radius: 100,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
      colorIndex++;
    });
    
    return sections;
  }
  
  List<Widget> _getInfluenceLegendItems() {
    final List<Widget> items = [];
    final List<Color> colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.amber,
      Colors.pink,
    ];
    
    int colorIndex = 0;
    _influenceDistribution.forEach((name, percentage) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                color: colors[colorIndex % colors.length],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$name (${percentage.toStringAsFixed(1)}%)'),
              ),
            ],
          ),
        ),
      );
      colorIndex++;
    });
    
    return items;
  }
  
  Widget _buildTopDelegatesView() {
    if (_topDelegates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.people,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No top delegates found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create delegations to see top delegates',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Top Delegates by Influence',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _topDelegates.length,
            itemBuilder: (context, index) {
              final user = _topDelegates[index];
              final delegationCount = _delegationGraph[user.id]?.delegatedFrom.length ?? 0;
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(user.name),
                  subtitle: Text(user.email),
                  trailing: Chip(
                    label: Text('$delegationCount delegations'),
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// Add this to pubspec.yaml dependencies:
// fl_chart: ^0.62.0

class DelegationGraphPainter extends CustomPainter {
  final Map<String, DelegationNode> delegationGraph;
  final String currentUserId;
  final BuildContext context;

  DelegationGraphPainter({
    required this.delegationGraph,
    required this.currentUserId,
    required this.context,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (delegationGraph.isEmpty) return;

    // Create positioning map
    final positions =
        _calculateNodePositions(delegationGraph, currentUserId, size);

    // Draw connections (delegation lines)
    _drawConnections(canvas, positions);

    // Draw nodes
    _drawNodes(canvas, positions);
  }

  Map<String, Offset> _calculateNodePositions(
    Map<String, DelegationNode> graph,
    String rootId,
    Size size,
  ) {
    final Map<String, Offset> positions = {};
    final center = Offset(size.width / 2, size.height / 2);

    // Add the root node at center
    positions[rootId] = center;

    // Calculate max depth for scaling
    int maxDepth = 0;
    for (final node in graph.values) {
      if (node.depth > maxDepth) maxDepth = node.depth;
    }

    // Organize nodes by depth
    final Map<int, List<String>> nodesByDepth = {};
    for (final entry in graph.entries) {
      final depth = entry.value.depth;
      nodesByDepth[depth] = nodesByDepth[depth] ?? [];
      nodesByDepth[depth]!.add(entry.key);
    }

    // Position nodes in concentric circles around root
    for (int depth = 1; depth <= maxDepth; depth++) {
      final nodesAtDepth = nodesByDepth[depth] ?? [];
      final radius = (depth / maxDepth) * (size.width * 0.4);

      for (int i = 0; i < nodesAtDepth.length; i++) {
        final angle = (i / nodesAtDepth.length) * 2 * math.pi;
        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);
        positions[nodesAtDepth[i]] = Offset(x, y);
      }
    }

    return positions;
  }

  void _drawConnections(Canvas canvas, Map<String, Offset> positions) {
    final arrowPaint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;


    for (final entry in delegationGraph.entries) {
      final node = entry.value;

      // Draw delegations from this node
      if (node.delegatedTo != null) {
        final from = positions[entry.key]!;
        final to = positions[node.delegatedTo!.delegateeId]!;

        // Calculate arrow direction
        final dx = to.dx - from.dx;
        final dy = to.dy - from.dy;
        final distance = math.sqrt(dx * dx + dy * dy);

        // Node radii
        const fromRadius = 20.0;
        const toRadius = 20.0;

        // Calculate start and end points, adjusting for node size
        final startX = from.dx + (dx / distance) * fromRadius;
        final startY = from.dy + (dy / distance) * fromRadius;
        final endX = to.dx - (dx / distance) * toRadius;
        final endY = to.dy - (dy / distance) * toRadius;

        final start = Offset(startX, startY);
        final end = Offset(endX, endY);

        // Draw the line
        canvas.drawLine(start, end, arrowPaint);

        // Draw arrow head
        _drawArrowHead(canvas, start, end, arrowPaint);
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset start, Offset end, Paint paint) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final angle = math.atan2(dy, dx);

    const arrowSize = 10.0;
    final arrowAngle = math.pi / 6;

    final path = Path();
    path.moveTo(end.dx, end.dy);
    path.lineTo(
      end.dx - arrowSize * math.cos(angle - arrowAngle),
      end.dy - arrowSize * math.sin(angle - arrowAngle),
    );
    path.lineTo(
      end.dx - arrowSize * math.cos(angle + arrowAngle),
      end.dy - arrowSize * math.sin(angle + arrowAngle),
    );
    path.close();

    canvas.drawPath(path, Paint()..color = Colors.grey);
  }

  void _drawNodes(Canvas canvas, Map<String, Offset> positions) {
    for (final entry in positions.entries) {
      final userId = entry.key;
      final position = entry.value;
      final node = delegationGraph[userId];

      if (node == null) continue;

      // Determine node color based on type
      Color nodeColor;
      if (userId == currentUserId) {
        nodeColor = Colors.blue;
      } else if (node.delegatedFrom.isNotEmpty) {
        nodeColor = Colors.green;
      } else {
        nodeColor = Colors.grey;
      }

      // Draw node circle
      final nodePaint = Paint()
        ..color = nodeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(position, 20, nodePaint);

      // Draw border for current user
      if (userId == currentUserId) {
        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(position, 20, borderPaint);
      }

      // Draw user initial
      final initialText =
          node.user.name.isNotEmpty ? node.user.name[0].toUpperCase() : '?';
      final textSpan = TextSpan(
        text: initialText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Center text within the node
      final textOffset = Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      );
      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
