import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

/// Google Maps links (they open the Google Maps app on the phone when it's installed).
class MapsLinks {
  MapsLinks(this.name, this.location);

  final String name;
  final PartyLocation? location;

  String? get _address => location?.address;
  String? get _placeId => location?.placeId;

  /// What to search for: the address (most precise), else the business name.
  String get _query {
    final a = _address;
    if (a != null && a.isNotEmpty) {
      return a.toLowerCase().contains(name.toLowerCase()) ? a : '$name, $a';
    }
    return name;
  }

  bool get hasLocation => (_address?.isNotEmpty ?? false) || location?.mapsUrl != null || _placeId != null;

  /// Turn-by-turn directions from where the phone is.
  Uri directions() => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': _query,
        if (_placeId != null) 'destination_place_id': _placeId!,
      });

  /// The place on the map.
  Uri pin() => Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': _query,
        if (_placeId != null) 'query_place_id': _placeId!,
      });

  /// The Google Business profile (reviews, photos, hours). Uses the saved Google link when the
  /// lead came from Google, otherwise searches Google Maps for the business by name.
  Uri business() {
    final saved = location?.mapsUrl;
    if (saved != null && saved.startsWith('http')) return Uri.parse(saved);
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': _address == null ? name : '$name, $_address',
      if (_placeId != null) 'query_place_id': _placeId!,
    });
  }

  static Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
