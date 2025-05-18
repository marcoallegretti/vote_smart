import 'firebase_options.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/audit_service.dart';
import 'services/database_initializer.dart';
import 'services/proposal_lifecycle_service.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Initialize the database with sample data
  // This should ideally run only once, or be idempotent
  final databaseInitializer = DatabaseInitializer();
  await databaseInitializer.initializeDatabase();

  // AuthService will be created and provided by MultiProvider below.
  // ProposalLifecycleService will also be provided there and will use AuthService.
  // The explicit initialization of ProposalLifecycleService and its monitoring
  // is removed from here as the service now self-manages based on auth state.
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthService()), // AuthService provided first
        Provider<DatabaseService>(create: (_) => DatabaseService()),
        Provider<AuditService>(create: (_) => AuditService()),
        // ProposalLifecycleService depends on AuthService
        ProxyProvider<AuthService, ProposalLifecycleService>(
          update: (context, authService, previousProposalLifecycleService) => 
              ProposalLifecycleService(authService: authService),
          // dispose is not strictly necessary here for ProposalLifecycleService if it cleans up its own streams,
          // but if it had resources tied to the Provider lifecycle, it would be.
          // The service itself has a dispose method for its internal streams.
        ),
      ],
      child: MaterialApp(
        title: 'Participatory Democracy',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const AppEntryPoint(),
      ),
    );
  }
}

class AppEntryPoint extends StatelessWidget {
  const AppEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    // Ensure ProposalLifecycleService is initialized/listened to by accessing it.
    // This is important if its constructor or auth listener setup has side effects
    // that need to occur early. ProxyProvider handles its creation.
    Provider.of<ProposalLifecycleService>(context, listen: false);
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final auditService = Provider.of<AuditService>(context, listen: false);

    return Consumer<AuthService>(
      builder: (context, authService, _) {
        return StreamBuilder(
          stream: authService.authStateChanges,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.active) {
              final user = snapshot.data;
              // final userModel = authService.currentUser; // currentUser from AuthService is UserModel?

              if (user == null) { // Using firebase user from authStateChanges for routing
                return const AuthScreen();
              } else {
                // Wait for UserModel to be loaded if necessary, or show loading indicator
                if (authService.currentUser == null) {
                  // Still waiting for _fetchUserModel to complete after sign-in event
                  return const Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text('Loading user data...'),
                        ],
                      ),
                    ),
                  );
                }
                return MainNavigation(databaseService: databaseService, auditService: auditService);
              }
            }
            
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          },
        );
      },
    );
  }
}