import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/shared/maps/maps_links.dart';
import 'package:hipersign_mobile_app/shared/models/models.dart';

void main() {
  test('directions use the address and the Google place', () {
    final m = MapsLinks('AdzProHub', PartyLocation(address: 'Kalmandapam, Palakkad', placeId: 'ChIJ1'));
    final u = m.directions();
    expect(u.host, 'www.google.com');
    expect(u.queryParameters['destination'], 'AdzProHub, Kalmandapam, Palakkad');
    expect(u.queryParameters['destination_place_id'], 'ChIJ1');
  });

  test('business opens the saved Google link, else searches by name', () {
    final saved = MapsLinks('X', PartyLocation(mapsUrl: 'https://maps.google.com/?cid=42'));
    expect(saved.business().toString(), 'https://maps.google.com/?cid=42');
    final none = MapsLinks('Junior Construction', null);
    expect(none.hasLocation, isFalse);
    expect(none.business().queryParameters['query'], 'Junior Construction');
    expect(none.directions().queryParameters['destination'], 'Junior Construction');
  });

  test('address that already has the name is not repeated', () {
    final m = MapsLinks('Amal Traders', PartyLocation(address: 'Amal Traders, MG Road'));
    expect(m.pin().queryParameters['query'], 'Amal Traders, MG Road');
  });
}
