<!--- This file contains the architecture planned for each stage of the project. -->
# Participatory Democracy Voting System Architecture

## Overview
This application is a comprehensive voting platform for participatory democracy with multiple voting methods, user roles, and proposal management. The architecture follows a clean separation of concerns with data layer, business logic, and presentation layer.

## Core Features
1. Multi-role user system (Admin, Moderator, User, Proposer)
2. 15 different voting methods implementation
3. Complete proposal lifecycle management
4. Delegated voting capability
5. Group management
6. Comments and discussion

## Technical Constraints
- Maximum 10-12 files total
- Firebase Authentication for user management
- Firestore for database (no Firebase Storage or Realtime Database)
- Material 3 design system
- Provider for state management

## File Structure (10 files total)

1. `lib/main.dart` - App entry point, Firebase initialization
2. `lib/theme.dart` - Theme configuration (already exists)
3. `lib/models/data_models.dart` - All data models for Firestore collections
4. `lib/services/auth_service.dart` - Authentication and user management
5. `lib/services/database_service.dart` - Firestore database operations
6. `lib/screens/auth_screen.dart` - Login/Register screens
7. `lib/screens/home_screen.dart` - Main dashboard and navigation
8. `lib/screens/proposal_screen.dart` - Proposal creation and management
9. `lib/screens/voting_screen.dart` - Voting interfaces for all methods
10. `lib/widgets/common_widgets.dart` - Reusable UI components

## Firebase Structure

### Authentication
- Email/password authentication
- Custom claims for role management

### Firestore Collections
- **users**: User profiles and role information
- **topics**: Categories for proposals
- **proposals**: Main proposal information with status tracking
- **voteSessions**: Configuration for voting methods and options
- **votes**: Individual vote records
- **delegations**: Delegation relationships between users
- **groups**: User groups for collective voting
- **comments**: Discussion on proposals

## Implementation Plan

### 1. Setup and Configuration
- Initialize Firebase in main.dart
- Configure theme and app routes
- Add required dependencies

### 2. Authentication and User Management
- Implement login/registration flows
- Add role-based authorization
- Create user profile management

### 3. Data Models and Services
- Design and implement all data models
- Create database services for CRUD operations
- Implement repository pattern for data access

### 4. Proposal Management
- Create proposal lifecycle states
- Implement proposal creation flow
- Add support phase tracking
- Design freezing and publishing mechanisms

### 5. Voting System Implementation
- Create base voting interface
- Implement all 15 voting methods with appropriate UI
- Add vote calculation and result display

### 6. Role-Based UI
- Develop admin dashboard for user management
- Create moderator tools for content review
- Design proposer tracking interface
- Implement user voting screens

### 7. User Experience Enhancements
- Add dark mode support
- Implement responsive design for web support
- Create loading indicators and error handling

### 8. Testing and Debugging
- Verify all voting methods work correctly
- Test role-based permissions
- Ensure proposal lifecycle operates as expected

## Deployment
The application will be deployed as a Flutter web app and mobile app (Android/iOS).

## Technical Considerations

1. **Role-Based Access Control**:
   - Use a combination of Firestore rules and application-level checks
   - Validate permissions for each operation

2. **Voting Method Implementations**:
   - Create a factory pattern for instantiating voting methods
   - Provide consistent interfaces for all methods
   - Implement calculations for complex methods (Schulze, Condorcet, etc.)

3. **State Management**:
   - Use Provider for application state
   - Create view models for complex screens

4. **Firestore Schema Design**:
   - Optimize for read patterns and minimize writes
   - Use denormalization where appropriate
   - Create indexes for complex queries

5. **Offline Support**:
   - Use Firestore offline capabilities
   - Cache critical data for offline viewing