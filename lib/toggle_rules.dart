import 'dart:io';
import 'package:flutter/material.dart';

/// A utility script to toggle between development and production Firestore rules
/// for seeding data in the Vote Smart app.
void main() async {
  // Initialize Flutter bindings (required for print statements)
  WidgetsFlutterBinding.ensureInitialized();
  
  final rulesPath = 'firestore.rules';
  final devRulesPath = 'firestore.rules.dev';
  final bakRulesPath = 'firestore.rules.bak';
  
  try {
    // Check if files exist
    final rulesFile = File(rulesPath);
    final devRulesFile = File(devRulesPath);
    final bakRulesFile = File(bakRulesPath);
    
    if (!rulesFile.existsSync()) {
      print('Error: firestore.rules file not found!');
      exit(1);
    }
    
    if (!devRulesFile.existsSync()) {
      print('Error: firestore.rules.dev file not found!');
      exit(1);
    }
    
    if (!bakRulesFile.existsSync()) {
      print('Error: firestore.rules.bak file not found!');
      exit(1);
    }
    
    // Read current rules content
    final currentRules = await rulesFile.readAsString();
    
    // Determine if we're currently in dev mode by checking for the dev mode signature
    // (looking for the "allow read, write: if true;" line which is unique to dev rules)
    final bool isCurrentlyDevMode = currentRules.contains('allow read, write: if true;');
    
    if (isCurrentlyDevMode) {
      // Switch to production rules
      print('Switching to production rules...');
      await rulesFile.writeAsString(await bakRulesFile.readAsString());
      print('Successfully switched to production rules.');
    } else {
      // Switch to development rules
      print('Switching to development rules...');
      await rulesFile.writeAsString(await devRulesFile.readAsString());
      print('Successfully switched to development rules.');
    }
    
    print('\nNOTE: You may need to deploy the updated rules to Firebase for them to take effect.');
    print('Run: firebase deploy --only firestore:rules');
    
  } catch (e) {
    print('Error toggling rules: $e');
    exit(1);
  }
  
  exit(0);
}
