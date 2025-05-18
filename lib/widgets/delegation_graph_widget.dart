import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';

import '../services/delegation_service.dart';
import '../services/database_service.dart';
import '../models/data_models.dart';

class DelegationGraphWidget extends StatefulWidget {
  final String rootUserId;

  const DelegationGraphWidget({required this.rootUserId, super.key});

  @override
  State<DelegationGraphWidget> createState() => _DelegationGraphWidgetState();
}

class _DelegationGraphWidgetState extends State<DelegationGraphWidget> {
  late final DelegationService delegationService;
  late final DatabaseService databaseService;
  Future<Map<String, DelegationNode>>? _delegationGraphFuture;
  final Logger _logger = Logger();
  
  // Filter settings
  bool _showExpiredDelegations = true;
  bool _showTopicDelegations = true;
  bool _showGeneralDelegations = true;

  final Graph graph = Graph();
  late BuchheimWalkerConfiguration builder;

  @override
  void initState() {
    super.initState();
    delegationService = Provider.of<DelegationService>(context, listen: false);
    databaseService = Provider.of<DatabaseService>(context, listen: false);
    _fetchDelegationGraph();

    builder = BuchheimWalkerConfiguration()
      ..siblingSeparation = (50)
      ..levelSeparation = (50)
      ..subtreeSeparation = (50)
      ..orientation = (BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM);
  }

  void _fetchDelegationGraph() {
    _delegationGraphFuture =
        delegationService.getDelegationGraph(widget.rootUserId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: FutureBuilder<Map<String, DelegationNode>>(
            future: _delegationGraphFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                _logger.e("Error fetching delegation graph", error: snapshot.error);
                return Center(
                    child: Text('Error loading delegation graph: ${snapshot.error}'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No delegation data found.'));
              } else {
                final delegationData = snapshot.data!;
                _buildGraphView(delegationData);

                return Column(
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(100),
                        minScale: 0.01,
                        maxScale: 5.6,
                        child: GraphView(
                          graph: graph,
                          algorithm:
                              BuchheimWalkerAlgorithm(builder, TreeEdgeRenderer(builder)),
                          paint: Paint()
                            ..color = Colors.blue
                            ..strokeWidth = 2.0
                            ..style = PaintingStyle.stroke,
                          builder: (Node node) {
                            // Use node data (index) to get the actual DelegationNode or User info
                            var nodeIndex =
                                node.key!.value as String; // Assuming key is user ID
                            var delegationNode = delegationData[nodeIndex];
            
                            // Pass both the userId (nodeIndex) and the nodeData
                            return _buildNodeWidget(nodeIndex, delegationNode);
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _buildLegend(),
                    ),
                  ],
                );
              }
            },
          ),
        ),
      ],
    );
  }

  // Build filter bar for delegation display options
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FilterChip(
            label: const Text('Expired'),
            selected: _showExpiredDelegations,
            onSelected: (bool selected) {
              setState(() {
                _showExpiredDelegations = selected;
                _fetchDelegationGraph(); // Refresh graph
              });
            },
          ),
          FilterChip(
            label: const Text('Topic-specific'),
            selected: _showTopicDelegations,
            onSelected: (bool selected) {
              setState(() {
                _showTopicDelegations = selected;
                _fetchDelegationGraph(); // Refresh graph
              });
            },
          ),
          FilterChip(
            label: const Text('General'),
            selected: _showGeneralDelegations,
            onSelected: (bool selected) {
              setState(() {
                _showGeneralDelegations = selected;
                _fetchDelegationGraph(); // Refresh graph
              });
            },
          ),
        ],
      ),
    );
  }

  // Build color legend
  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem('Root User', Colors.blueAccent),
        const SizedBox(width: 12),
        _legendItem('General Delegation', Colors.lightBlue[400]!),
        const SizedBox(width: 12),
        _legendItem('Topic Delegation', Colors.greenAccent[700]!),
        const SizedBox(width: 12),
        _legendItem('Expired Delegation', Colors.grey[400]!),
      ],
    );
  }

  // Helper method to create a legend item
  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
  
  void _buildGraphView(Map<String, DelegationNode> delegationData) {
    // Clear existing graph nodes/edges before rebuilding
    graph.nodes.clear();
    graph.edges.clear();

    if (!delegationData.containsKey(widget.rootUserId)) {
      _logger.w("Root user ${widget.rootUserId} not found in delegation data");
      // Add the root node anyway to show something
      graph.addNode(Node.Id(widget.rootUserId));
      return;
    }

    final Map<String, Node> graphNodes = {};

    // Create graph nodes from delegation data
    delegationData.forEach((userId, delegationNode) {
      graphNodes[userId] = Node.Id(userId);
      graph.addNode(graphNodes[userId]!);
    });

    // Create edges based on delegations
    delegationData.forEach((userId, delegationNode) {
      if (delegationNode.delegatedTo != null) {
        final delegatorNode = graphNodes[userId];
        final delegateeNode =
            graphNodes[delegationNode.delegatedTo!.delegateeId];

        if (delegatorNode != null && delegateeNode != null) {
          graph.addEdge(delegatorNode, delegateeNode);
        } else {
          _logger.w(
              "Could not find nodes for edge between $userId and ${delegationNode.delegatedTo!.delegateeId}");
        }
      }
    });

    _logger.i(
        "Graph built with ${graph.nodeCount()} nodes and ${graph.edges.length} edges.");
  }

  Widget _buildNodeWidget(String userId, DelegationNode? nodeData) {
    // Add null check for nodeData first (user info might still be missing)
    if (nodeData == null) {
      // Handle the case where nodeData is unexpectedly null
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red[100], // Indicate error or unknown state
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red, width: 1),
        ),
        child: Text('Error: Node data missing for $userId',
            style: const TextStyle(color: Colors.black87)),
      );
    }

    // Now nodeData is guaranteed non-null
    String displayText = nodeData.user.name ?? userId;
    bool isRoot = userId == widget.rootUserId;
    
    // Check if node has expired delegations only
    bool hasOnlyExpiredDelegations = nodeData.delegatedTo != null &&
        _isDelegationExpired(nodeData.delegatedTo!);
    
    // Check if node has any outgoing topic-specific delegations
    bool hasTopicDelegation = nodeData.delegatedTo != null &&
        nodeData.delegatedTo!.topicId != null;

    return Tooltip(
      message: _buildTooltipText(nodeData),
      textStyle: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _getNodeColor(isRoot, hasOnlyExpiredDelegations, hasTopicDelegation),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasOnlyExpiredDelegations ? Colors.grey : Colors.black54,
            width: 1,
            style: hasOnlyExpiredDelegations ? BorderStyle.solid : BorderStyle.solid,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayText,
              style: TextStyle(
                color: isRoot || (!hasOnlyExpiredDelegations && !isRoot) 
                    ? Colors.white 
                    : Colors.black87,
                fontWeight: isRoot ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
            if (nodeData.delegatedFrom.isNotEmpty)
              Text(
                "Delegations: ${nodeData.delegatedFrom.length}",
                style: const TextStyle(fontSize: 10),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
  
  // Helper method to get node color based on status
  Color _getNodeColor(bool isRoot, bool hasExpiredDelegations, bool hasTopicDelegation) {
    if (isRoot) return Colors.blueAccent;
    if (hasExpiredDelegations) return Colors.grey[400]!;
    if (hasTopicDelegation) return Colors.greenAccent[700]!;
    return Colors.lightBlue[400]!;
  }
  
  // Helper method to build tooltip text
  String _buildTooltipText(DelegationNode node) {
    StringBuffer buffer = StringBuffer();
    buffer.writeln("User: ${node.user.name ?? 'Unknown'}");
    buffer.writeln("Role: ${node.user.role.toString().split('.').last}");
    
    if (node.delegatedFrom.isNotEmpty) {
      buffer.writeln("Incoming delegations: ${node.delegatedFrom.length}");
    }
    
    if (node.delegatedTo != null) {
      final delegation = node.delegatedTo!;
      buffer.writeln("Delegated to: ${delegation.delegateeId}");
      buffer.writeln("Valid until: ${_formatDate(delegation.validUntil)}");
      buffer.writeln("Topic: ${delegation.topicId != null ? 'Specific' : 'General'}");
      buffer.writeln("Status: ${_isDelegationExpired(delegation) ? 'Expired' : 'Active'}");
    }
    
    return buffer.toString();
  }
  
  // Helper method to format date
  String _formatDate(DateTime date) {
    return "${date.year}/${date.month}/${date.day}";
  }
  
  // Helper method to check if delegation is expired
  bool _isDelegationExpired(DelegationModel delegation) {
    return delegation.validUntil.isBefore(DateTime.now());
  }
}
