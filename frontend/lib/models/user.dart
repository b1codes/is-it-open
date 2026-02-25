class User {
  final int id;
  final String username;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? homeAddress;
  final double? homeLat;
  final double? homeLng;
  final String? workAddress;
  final double? workLat;
  final double? workLng;
  final bool useCurrentLocation;
  final String? token;

  User({
    required this.id,
    required this.username,
    this.email,
    this.firstName,
    this.lastName,
    this.homeAddress,
    this.homeLat,
    this.homeLng,
    this.workAddress,
    this.workLat,
    this.workLng,
    this.useCurrentLocation = false,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      homeAddress: json['home_address'],
      homeLat: json['home_lat']?.toDouble(),
      homeLng: json['home_lng']?.toDouble(),
      workAddress: json['work_address'],
      workLat: json['work_lat']?.toDouble(),
      workLng: json['work_lng']?.toDouble(),
      useCurrentLocation: json['use_current_location'] ?? false,
      token: json['token'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'home_address': homeAddress,
      'home_lat': homeLat,
      'home_lng': homeLng,
      'work_address': workAddress,
      'work_lat': workLat,
      'work_lng': workLng,
      'use_current_location': useCurrentLocation,
      'token': token,
    };
  }
}
