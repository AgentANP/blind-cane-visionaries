// Emergency Contact Model
class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
    };
  }

  // Create from JSON
  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}
