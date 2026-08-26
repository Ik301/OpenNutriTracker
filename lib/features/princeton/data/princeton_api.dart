import 'dart:convert';

import 'package:http/http.dart' as http;

/// Client for the user's existing [princeton-eats] backend.
///
/// When the Flutter Web PWA is served on the tailnet this is same-origin
/// (`/api/...`); from a local dev server it is cross-origin, which the
/// backend already allows (CORSMiddleware with `allow_origins=["*"]`).
const String princetonApiBase = 'https://karina.tailb3c3f0.ts.net';

const String princetonApiBasePath = '/api';

class PrincetonLocation {
  final String num;
  final String name;

  const PrincetonLocation({required this.num, required this.name});

  factory PrincetonLocation.fromJson(Map<String, dynamic> json) =>
      PrincetonLocation(
        num: json['num'] as String,
        name: json['name'] as String,
      );

  @override
  String toString() => '$name (#$num)';
}

/// A single food item on a Princeton menu, with its per-serving nutrition
/// label -> value map (e.g. {"Calories": "320", "Protein": "12 g", ...}).
class PrincetonItem {
  final String title;
  final String recipeId;
  final Map<String, String> nutrition;

  const PrincetonItem({
    required this.title,
    required this.recipeId,
    required this.nutrition,
  });

  factory PrincetonItem.fromJson(Map<String, dynamic> json) {
    final rawNutrition = (json['nutrition'] as Map?) ?? const {};
    return PrincetonItem(
      title: json['title'] as String,
      recipeId: json['recipe_id'] as String,
      nutrition: rawNutrition.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      ),
    );
  }

  double? _num(String label) {
    final raw = nutrition[label];
    if (raw == null || raw.isEmpty) return null;
    // Values look like "320", "12 g", "1,5 g", "0.0 g" — take the leading
    // number, treating a comma as the decimal separator.
    final match =
        RegExp(r'\d+(?:[.,]\d+)?').firstMatch(raw.replaceAll(',', '.'));
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }

  double? get calories => _num('Calories');
  double? get protein => _num('Protein');
  double? get carbs =>
      _num('Total Carbohydrate') ?? _num('Total Carbohydrates');
  double? get fat => _num('Total Fat');
  String? get servingSize => nutrition['Serving Size'];
}

class PrincetonStation {
  final String station;
  final List<PrincetonItem> items;

  const PrincetonStation({required this.station, required this.items});

  factory PrincetonStation.fromJson(Map<String, dynamic> json) =>
      PrincetonStation(
        station: json['station'] as String,
        items: ((json['items'] as List?) ?? const [])
            .map((e) => PrincetonItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PrincetonMeal {
  final String meal;
  final List<PrincetonStation> stations;

  const PrincetonMeal({required this.meal, required this.stations});

  factory PrincetonMeal.fromJson(Map<String, dynamic> json) => PrincetonMeal(
        meal: json['meal'] as String,
        stations: ((json['stations'] as List?) ?? const [])
            .map((e) => PrincetonStation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PrincetonMenu {
  final String date;
  final String location;
  final List<PrincetonMeal> meals;

  const PrincetonMenu({
    required this.date,
    required this.location,
    required this.meals,
  });

  factory PrincetonMenu.fromJson(Map<String, dynamic> json) => PrincetonMenu(
        date: json['date'] as String,
        location: json['location'] as String,
        meals: ((json['meals'] as List?) ?? const [])
            .map((e) => PrincetonMeal.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PrincetonApiException implements Exception {
  final String message;
  const PrincetonApiException(this.message);
  @override
  String toString() => message;
}

class PrincetonApi {
  static Future<List<PrincetonLocation>> fetchLocations() async {
    final data = await _getJson('$princetonApiBase$princetonApiBasePath/locations');
    final list = (data['locations'] as List?) ?? const [];
    return list
        .map((e) => PrincetonLocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<PrincetonMenu> fetchMenu(String location, {required String date}) async {
    final data = await _getJson(
      '$princetonApiBase$princetonApiBasePath/menu',
      query: {'location': location, 'date': date},
    );
    return PrincetonMenu.fromJson(data);
  }

  static Future<Map<String, dynamic>> _getJson(
    String url, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(url).replace(queryParameters: query);
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw PrincetonApiException('Could not reach the Princeton menu service.');
    }
    if (response.statusCode != 200) {
      throw PrincetonApiException(
        'Princeton menu service returned ${response.statusCode}.',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
