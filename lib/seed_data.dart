import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/data_seeder.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set Firestore settings to allow localhost
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    sslEnabled: false,
  );

  runApp(const SeedDataApp());
}

class SeedDataApp extends StatelessWidget {
  const SeedDataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Data Seeder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const SeedDataScreen(),
    );
  }
}

class SeedDataScreen extends StatefulWidget {
  const SeedDataScreen({super.key});

  @override
  State<SeedDataScreen> createState() => _SeedDataScreenState();
}

class _SeedDataScreenState extends State<SeedDataScreen> {
  final DataSeeder _dataSeeder = DataSeeder();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSeeding = false;
  bool _isClearing = false;
  bool _isAuthenticated = false;
  bool _isSigningIn = false;
  String _statusMessage = 'Not authenticated. Please sign in first.';
  List<String> _logMessages = [];

  // Text controllers for login form
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Check if user is already signed in
    if (_auth.currentUser != null) {
      setState(() {
        _isAuthenticated = true;
        _statusMessage = 'Ready to seed data';
      });
      _addLogMessage('Already signed in as ${_auth.currentUser!.email}');
    }
  }

  @override
  void dispose() {
    // Clean up controllers when the widget is disposed
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInAsAdmin() async {
    if (_isAuthenticated) return;

    // Show login dialog
    final credentials = await _showLoginDialog();
    if (credentials == null) return; // User cancelled

    setState(() {
      _isSigningIn = true;
      _statusMessage = 'Signing in as admin...';
      _logMessages = [];
    });

    try {
      _addLogMessage('Attempting to sign in as admin...');
      await _auth.signInWithEmailAndPassword(
        email: credentials['email']!,
        password: credentials['password']!,
      );
      _addLogMessage('Successfully signed in as admin');
      setState(() {
        _isAuthenticated = true;
        _statusMessage = 'Ready to seed data';
      });
    } catch (e) {
      _addLogMessage('Error signing in: $e');
      setState(() {
        _statusMessage = 'Error signing in: $e';
      });
    } finally {
      setState(() {
        _isSigningIn = false;
      });
    }
  }

  Future<Map<String, String>?> _showLoginDialog() async {
    _emailController.text = 'admin@votesmart.com'; // Default suggestion
    _passwordController.text = ''; // Clear password

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Admin Login'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter admin email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter admin password',
                  ),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (_emailController.text.isNotEmpty &&
                    _passwordController.text.isNotEmpty) {
                  Navigator.of(context).pop({
                    'email': _emailController.text,
                    'password': _passwordController.text,
                  });
                }
              },
              child: const Text('Login'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _seedData() async {
    if (_isSeeding || _isClearing || !_isAuthenticated) return;

    setState(() {
      _isSeeding = true;
      _statusMessage = 'Seeding data...';
      _logMessages = [];
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
    if (_isSeeding || _isClearing || !_isAuthenticated) return;

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
      _logMessages = [];
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
        title: const Text('Vote Smart Data Seeder'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _statusMessage,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (!_isAuthenticated) ...[
              // Only show sign-in button if not authenticated
              ElevatedButton.icon(
                onPressed: (_isSeeding || _isClearing || _isSigningIn)
                    ? null
                    : _signInAsAdmin,
                icon: const Icon(Icons.login),
                label:
                    Text(_isSigningIn ? 'Signing in...' : 'Sign In as Admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_isAuthenticated) ...[
              // Only show these buttons if authenticated
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isSeeding || _isClearing) ? null : _seedData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isSeeding ? 'Seeding...' : 'Seed Database'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          (_isSeeding || _isClearing) ? null : _clearSeededData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                          _isClearing ? 'Removing...' : 'Remove Seeded Data'),
                    ),
                  ),
                ],
              ),
            ],
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
