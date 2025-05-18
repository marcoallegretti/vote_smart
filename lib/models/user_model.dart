class UserModel {
  final String id;
  final String name;
  final String email;
  // Add other relevant user properties like profileImageUrl, roles, etc.

  UserModel({
    required this.id,
    required this.name,
    required this.email,
  });

  // Optional: Factory constructor for Firebase or other data sources
  // factory UserModel.fromMap(Map<String, dynamic> data, String documentId) {
  //   return UserModel(
  //     id: documentId,
  //     name: data['name'] ?? '',
  //     email: data['email'] ?? '',
  //   );
  // }

  // // Optional: Method to convert UserModel to Map for Firebase
  // Map<String, dynamic> toMap() {
  //   return {
  //     'name': name,
  //     'email': email,
  //   };
  // }
}
