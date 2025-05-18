# Vote Smart

A Flutter-based participatory democracy application that implements various voting systems to facilitate fair and transparent decision-making processes.

## Project Status

### Completed Features
- **User Authentication**: Secure sign-in and user management
- **Proposal Lifecycle**: Automated workflow for proposal creation, discussion, voting, and implementation
- **Basic Voting Methods**:
  - First-Past-The-Post (FPTP)
  - Approval Voting
  - Two-Round System (Majority Runoff)
  - Weighted Voting
- **Liquid Democracy**:
  - Delegation management
  - Vote propagation logic
  - Delegation visualization
  - Audit trails
- **Discussion Forums**: Threaded comments and discussions for proposals
- **Basic Analytics**: Visualization of voting results and participation metrics

### Current Development Focus
- **Enhanced Analytics**: Advanced visualization of voting patterns and delegation networks
- **Educational Resources**: Tutorials and explanations of different voting methods
- **Performance Optimization**: Improving scalability for larger user bases

## Implemented Voting Systems

### Core Methods
1. **First-Past-The-Post (FPTP)**
   - Simple plurality voting
   - Each voter selects one candidate
   - Candidate with most votes wins

2. **Approval Voting**
   - Voters can approve multiple candidates
   - Each approved candidate receives one vote
   - Candidate with most approvals wins

3. **Two-Round System**
   - First round: All candidates compete
   - If no majority, top two candidates proceed to second round
   - Majority required to win

4. **Weighted Voting**
   - Voters can assign different weights to candidates
   - Supports both cumulative and non-cumulative variants

### Advanced Methods (Prototype/In Progress)
- **Schulze Method**
  - Currently simplified prototype
  - Full implementation pending

## Technical Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Authentication, Firestore, Cloud Functions)
- **State Management**: Provider
- **Testing**: Flutter Test, Mockito

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Firebase project with Firestore database
- Google Cloud account (for Firebase services)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/vote_smart.git
   cd vote_smart
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Set up Firebase:
   - Create a new Firebase project
   - Add Android/iOS/Web app to your Firebase project
   - Download configuration files:
     - `google-services.json` (Android)
     - `GoogleService-Info.plist` (iOS)
   - Place these files in their respective platform directories

4. Run the app:
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── models/           # Data models
├── screens/          # UI screens
├── services/         # Business logic and API clients
├── utils/            # Helper functions and constants
├── widgets/          # Reusable UI components
├── main.dart         # Application entry point
└── firebase_options.dart  # Firebase configuration
```

## Contributing

Contributions are welcome. Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Flutter and Firebase teams for their excellent documentation
- The open-source community for various packages and libraries
- Researchers in voting systems and social choice theory
