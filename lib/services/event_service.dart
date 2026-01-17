import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EventService {
  static String get apiKey => dotenv.env['TICKETMASTER_API_KEY'] ?? '';
  static const String baseUrl = "https://app.ticketmaster.com/discovery/v2/events.json";

  static Future<List<dynamic>> fetchEvents(double lat, double lon, double radius) async {
  final Uri url = Uri.parse(
    "$baseUrl?apikey=$apiKey&latlong=$lat,$lon&radius=${radius.toInt()}"
  );

  print("Fetching events with radius: $radius km from $lat, $lon");

  final response = await http.get(url);

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['_embedded']?['events'] ?? [];
  } else {
    print("Failed to load events: ${response.statusCode}");
    return [];
  }
}

static Future<List<dynamic>> fetchSuggestedEvents() async {
  final url = "$baseUrl?apikey=$apiKey&size=3&sort=relevance,desc";

  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['_embedded']?['events'] ?? [];
    } else {
      throw Exception("Failed to load suggested events");
    }
  } catch (e) {
    throw e;
  }
}

static Future<List<dynamic>> fetchEventsByCategory(String category) async {
    final url = Uri.parse(
      '$baseUrl?classificationName=${Uri.encodeComponent(category)}&apikey=$apiKey'
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['_embedded'] != null && data['_embedded']['events'] != null) {
        return data['_embedded']['events'];
      } else {
        return [];
      }
    } else {
      throw Exception('Failed to load events for category $category');
    }
  }

}
