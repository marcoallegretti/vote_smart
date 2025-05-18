class ProposalModel {
  final String id;
  final String title;
  final String description;
  final String proposerId; // User ID of the proposer
  final DateTime createdAt;
  final DateTime? votingEndsAt;
  // Add other relevant proposal properties like status, category, etc.

  ProposalModel({
    required this.id,
    required this.title,
    required this.description,
    required this.proposerId,
    required this.createdAt,
    this.votingEndsAt,
  });

  // Optional: Factory constructor for data sources
  // factory ProposalModel.fromMap(Map<String, dynamic> data, String documentId) {
  //   return ProposalModel(
  //     id: documentId,
  //     title: data['title'] ?? '',
  //     description: data['description'] ?? '',
  //     proposerId: data['proposerId'] ?? '',
  //     createdAt: (data['createdAt'] as Timestamp).toDate(), // Example for Firebase Timestamp
  //     votingEndsAt: (data['votingEndsAt'] as Timestamp?)?.toDate(),
  //   );
  // }

  // // Optional: Method to convert ProposalModel to Map
  // Map<String, dynamic> toMap() {
  //   return {
  //     'title': title,
  //     'description': description,
  //     'proposerId': proposerId,
  //     'createdAt': createdAt,
  //     'votingEndsAt': votingEndsAt,
  //   };
  // }
}
