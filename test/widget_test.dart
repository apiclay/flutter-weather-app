import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weather_app/main.dart';

Map<String, dynamic> sample(String city) => {
      'location': city,
      'country': city == 'London' ? 'United Kingdom' : 'Japan',
      'localTime': '2026-11-09 23:15',
      'temperature': 7.1,
      'humidity': 87,
      'cloud': 10,
      'wind': '5.1|ENE',
      'uv': 0,
      'airQuality': 2,
    };

Future<void> tapSearch(WidgetTester tester) async {
  final button = find.byKey(const Key('searchButton'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Starts empty without requesting weather', (tester) async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(SkycastApp(client: client));

    expect(find.text('Live weather · Source: ApiClay'), findsOneWidget);
    expect(find.text('Search for a city'), findsOneWidget);
    expect(find.byKey(const Key('temperatureValue')), findsNothing);
    expect(requests, 0);
  });

  testWidgets('Search displays live response and supports Tokyo',
      (tester) async {
    final cities = <String>[];

    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/weather');

      final city = request.url.queryParameters['q']!;
      cities.add(city);

      return http.Response(
        jsonEncode(sample(city)),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(SkycastApp(client: client));

    final field = find.byKey(const Key('citySearchField'));

    await tester.enterText(field, 'London');
    await tapSearch(tester);

    expect(
      find.byKey(const Key('cityHeading')),
      findsOneWidget,
    );
    expect(
      find.text('London', findRichText: true),
      findsWidgets,
    );
    expect(find.text('United Kingdom'), findsOneWidget);
    expect(find.text('7.1'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);

    await tester.enterText(field, 'Tokyo');
    await tapSearch(tester);

    final heading = tester.widget<Text>(
      find.byKey(const Key('cityHeading')),
    );

    expect(heading.data, 'Tokyo');
    expect(find.text('Japan'), findsOneWidget);
    expect(cities, ['London', 'Tokyo']);
  });

  testWidgets('Empty input prevents HTTP request', (tester) async {
    var requests = 0;

    final client = MockClient((request) async {
      requests++;
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(SkycastApp(client: client));

    await tester.enterText(
      find.byKey(const Key('citySearchField')),
      '   ',
    );

    await tapSearch(tester);

    expect(
      find.text('Enter a city name (1–100 characters).'),
      findsOneWidget,
    );
    expect(requests, 0);

    final heading = tester.widget<Text>(
      find.byKey(const Key('cityHeading')),
    );
    expect(heading.data, 'Search for a city');
  });

  testWidgets('Upstream failure shows error and retry works',
      (tester) async {
    var requests = 0;

    final client = MockClient((request) async {
      requests++;
      if (requests == 1) {
        return http.Response(
          jsonEncode({'error': 'Weather unavailable. Please retry.'}),
          502,
        );
      }
      return http.Response(
        jsonEncode(sample('London')),
        200,
      );
    });

    await tester.pumpWidget(SkycastApp(client: client));

    await tester.enterText(
      find.byKey(const Key('citySearchField')),
      'London',
    );
    await tapSearch(tester);

    expect(find.byKey(const Key('errorMessage')), findsOneWidget);
    expect(find.byKey(const Key('temperatureValue')), findsNothing);

    final retry = find.byKey(const Key('retryButton'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    final heading = tester.widget<Text>(
      find.byKey(const Key('cityHeading')),
    );

    expect(heading.data, 'London');
    expect(find.byKey(const Key('errorMessage')), findsNothing);
    expect(requests, 2);
  });
}
