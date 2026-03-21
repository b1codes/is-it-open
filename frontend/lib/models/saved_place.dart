import 'place.dart';

class SavedPlace {
  final int id;
  final Place place;
  final String? customName;
  final String? icon;
  final String? color;
  final bool isPinned;
  final int? averageVisitLength;

  SavedPlace({
    required this.id,
    required this.place,
    this.customName,
    this.icon,
    this.color,
    this.isPinned = false,
    this.averageVisitLength,
  });

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    return SavedPlace(
      id: json['id'],
      place: Place.fromJson(json['place']),
      customName: json['custom_name'],
      icon: json['icon'],
      color: json['color'],
      isPinned: json['is_pinned'] ?? false,
      averageVisitLength: json['average_visit_length'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'place': place.toJson(),
      'custom_name': customName,
      'icon': icon,
      'color': color,
      'is_pinned': isPinned,
      'average_visit_length': averageVisitLength,
    };
  }
}
