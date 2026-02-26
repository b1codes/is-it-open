import 'place.dart';

class SavedPlace {
  final int id;
  final Place place;
  final String? customName;

  SavedPlace({required this.id, required this.place, this.customName});

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    return SavedPlace(
      id: json['id'],
      place: Place.fromJson(json['place']),
      customName: json['custom_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'place': place.toJson(), 'custom_name': customName};
  }
}
