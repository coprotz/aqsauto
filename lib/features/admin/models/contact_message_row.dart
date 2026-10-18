class ContactMessageRow {
  const ContactMessageRow({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.subject,
    required this.message,
    required this.source,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String subject;
  final String message;
  final String source;
  final String status;
  final DateTime? createdAt;

  String get nameLabel => name.trim().isEmpty ? 'Anonymous' : name.trim();

  String get emailLabel => email.trim().isEmpty ? 'No email' : email.trim();

  String get phoneLabel => phone.trim().isEmpty ? 'No phone' : phone.trim();
}
