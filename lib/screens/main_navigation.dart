import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'delegation_management_screen.dart';
import '../services/database_service.dart';
import '../services/audit_service.dart';

class MainNavigation extends StatefulWidget {
  final DatabaseService databaseService;
  final AuditService auditService;

  const MainNavigation({
    required this.databaseService,
    required this.auditService,
    super.key,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(databaseService: widget.databaseService, auditService: widget.auditService),
      DelegationManagementScreen(databaseService: widget.databaseService, auditService: widget.auditService),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Delegations',
          ),
        ],
      ),
    );
  }
}
