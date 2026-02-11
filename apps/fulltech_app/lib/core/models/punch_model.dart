class PunchModel {
  final String id;
  final String type; // in, out, lunch_start, lunch_end
  final DateTime timestamp;

  PunchModel({required this.id, required this.type, required this.timestamp});

  factory PunchModel.fromJson(Map<String, dynamic> json) {
    return PunchModel(
      id: json['id'] ?? '',
      type: json['type'] ?? 'unknown',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}
