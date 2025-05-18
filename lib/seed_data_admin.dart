import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/data_seeder.dart';

// A command-line version of the data seeder that uses Firebase Admin SDK
void main() async {
  // Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Run the app
  runApp(const SeedDataAdminApp());
}

class SeedDataAdminApp extends StatelessWidget {
  const SeedDataAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vote Smart Admin Seeder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SeedDataAdminScreen(),
    );
  }
}

class SeedDataAdminScreen extends StatefulWidget {
  const SeedDataAdminScreen({super.key});

  @override
  State<SeedDataAdminScreen> createState() => _SeedDataAdminScreenState();
}

class _SeedDataAdminScreenState extends State<SeedDataAdminScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DataSeeder _dataSeeder = DataSeeder();
  bool _isSeeding = false;
  bool _isClearing = false;
  final List<String> _logMessages = [];
  String _statusMessage = 'Ready to manage data';

  @override
  void initState() {
    super.initState();
    _checkRules();
  }

  Future<void> _checkRules() async {
    try {
      // Try to read a document to test permissions
      await FirebaseFirestore.instance.collection('users').limit(1).get();
      _addLogMessage('Firestore rules allow read access');
    } catch (e) {
      _addLogMessage('Warning: Firestore rules may be restrictive: $e');
      _statusMessage = 'Warning: Security rules may prevent seeding';
      setState(() {});
    }
  }

  Future<void> _seedData() async {
    if (_isSeeding || _isClearing) return;

    setState(() {
      _isSeeding = true;
      _statusMessage = 'Seeding data...';
    });

    try {
      _addLogMessage('Starting data seeding process...');
      await _dataSeeder.seedDatabase();
      _addLogMessage('Data seeding completed successfully!');
      setState(() {
        _statusMessage = 'Data seeded successfully!';
      });
    } catch (e) {
      _addLogMessage('Error during data seeding: $e');
      setState(() {
        _statusMessage = 'Error seeding data: $e';
      });
    } finally {
      setState(() {
        _isSeeding = false;
      });
    }
  }

  Future<void> _clearSeededData() async {
    if (_isSeeding || _isClearing) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Data Removal'),
            content: const Text(
                'This will remove all seeded data including topics, proposals, votes, and comments. '
                'The default users (admin, moderator, proposer, user) will be preserved. '
                'Are you sure you want to continue?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove Data'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _isClearing = true;
      _statusMessage = 'Clearing seeded data...';
    });

    try {
      _addLogMessage('Starting data removal process...');
      await _dataSeeder.clearSeededData();
      _addLogMessage('Seeded data removed successfully!');
      setState(() {
        _statusMessage = 'Data removed successfully!';
      });
    } catch (e) {
      _addLogMessage('Error removing seeded data: $e');
      setState(() {
        _statusMessage = 'Error removing data: $e';
      });
    } finally {
      setState(() {
        _isClearing = false;
      });
    }
  }

  Future<void> _toggleRules() async {
    try {
      final rulesDoc = await FirebaseFirestore.instance
          .collection('_settings')
          .doc('rules')
          .get();
      final bool devMode =
          rulesDoc.exists ? (rulesDoc.data()?['devMode'] ?? false) : false;

      await FirebaseFirestore.instance
          .collection('_settings')
          .doc('rules')
          .set({
        'devMode': !devMode,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _addLogMessage(
          'Security rules mode toggled to: ${!devMode ? 'Development' : 'Production'}');
      _statusMessage =
          'Rules updated to ${!devMode ? 'Development' : 'Production'} mode';
      setState(() {});
    } catch (e) {
      _addLogMessage('Error toggling rules: $e');
    }
  }

  void _addLogMessage(String message) {
    setState(() {
      _logMessages
          .add('${DateTime.now().toString().substring(11, 19)}: $message');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Vote Smart Admin Data Manager'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusMessage,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Current user: ${_auth.currentUser?.email ?? 'Not signed in'}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSeeding || _isClearing ? null : _seedData,
                    icon: const Icon(Icons.add_circle),
                    label: Text(_isSeeding ? 'Seeding...' : 'Seed Database'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _isSeeding || _isClearing ? null : _clearSeededData,
                    icon: const Icon(Icons.delete),
                    label: Text(
                        _isClearing ? 'Removing...' : 'Remove Seeded Data'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isSeeding || _isClearing ? null : _toggleRules,
              icon: const Icon(Icons.security),
              label: const Text('Toggle Security Rules Mode'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Log:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  itemCount: _logMessages.length,
                  itemBuilder: (context, index) {
                    return Text(_logMessages[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
