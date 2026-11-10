import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

void main() => runApp(const SkycastApp());

class SkycastApp extends StatefulWidget {
  const SkycastApp({super.key, this.client});
  final http.Client? client;

  @override
  State<SkycastApp> createState() => _SkycastAppState();
}

class _SkycastAppState extends State<SkycastApp> {
  late final http.Client client;
  late final bool ownsClient;

  @override
  void initState() {
    super.initState();
    ownsClient = widget.client == null;
    client = widget.client ?? http.Client();
  }

  @override
  void dispose() {
    if (ownsClient) client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Skycast',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1683DD),
          ),
          scaffoldBackgroundColor: const Color(0xFFF3F8FE),
        ),
        home: WeatherHome(client: client),
      );
}

class WeatherHome extends StatefulWidget {
  const WeatherHome({super.key, required this.client});
  final http.Client client;

  @override
  State<WeatherHome> createState() => _WeatherHomeState();
}

class _WeatherHomeState extends State<WeatherHome> {
  final controller = TextEditingController();
  Map<String, dynamic>? weather;
  String? error;
  String? lastCity;
  bool loading = false;
  int requestId = 0;

  Future<void> search([String? retryCity]) async {
    final city = (retryCity ?? controller.text).trim();
    if (city.isEmpty || city.length > 100) {
      setState(() {
        error = 'Enter a city name (1–100 characters).';
      });
      return;
    }

    final id = ++requestId;
    setState(() {
      loading = true;
      error = null;
      weather = null;
      lastCity = city;
    });
    FocusManager.instance.primaryFocus?.unfocus();

    try {
      final uri = Uri.parse('$apiBaseUrl/weather').replace(
        queryParameters: {'q': city},
      );
      final response = await widget.client
          .get(uri)
          .timeout(const Duration(seconds: 35));

      if (response.statusCode != 200) {
        String message = 'Weather unavailable. Please retry.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['error'] is String) {
            message = body['error'] as String;
          }
        } catch (_) {
          // Keep the generic error for invalid server responses.
        }
        throw Exception(message);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['location'] is! String ||
          decoded['country'] is! String ||
          decoded['localTime'] is! String ||
          decoded['temperature'] is! num ||
          decoded['humidity'] is! num ||
          decoded['cloud'] is! num ||
          decoded['wind'] is! String ||
          decoded['uv'] is! num ||
          decoded['airQuality'] is! num) {
        throw const FormatException('Invalid weather response.');
      }
      if (mounted && id == requestId) {
        setState(() => weather = decoded);
      }
    } catch (e) {
      if (mounted && id == requestId) {
        setState(() {
          error = e is TimeoutException
              ? 'Request timed out. Please retry.'
              : e is FormatException
                  ? 'Invalid weather response. Please retry.'
                  : e is http.ClientException
                      ? 'Connection failed. Check the backend.'
                      : e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted && id == requestId) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    requestId++;
    controller.dispose();
    super.dispose();
  }

  String value(Object? v) => v?.toString() ?? 'Unavailable';

  String aqiCategory(num index) {
    switch (index.toInt()) {
      case 1:
        return 'Good';
      case 2:
        return 'Moderate';
      case 3:
        return 'Unhealthy for sensitive groups';
      case 4:
        return 'Unhealthy';
      case 5:
        return 'Very unhealthy';
      case 6:
        return 'Hazardous';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1683DD);
    final w = weather;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.wb_sunny_rounded,
                            color: blue, size: 30),
                        SizedBox(width: 10),
                        Text('Skycast',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Live weather · Source: ApiClay',
                        style: TextStyle(
                            color: Color(0xFF365B7C),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF69C7FF),
                            blue,
                            Color(0xFF1256A6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.wb_cloudy_rounded,
                              size: 90, color: Color(0xFFFFE08A)),
                          const SizedBox(height: 12),
                          Text(
                            w == null ? 'Search for a city' : value(w['location']),
                            key: const Key('cityHeading'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold),
                          ),
                          if (w != null) ...[
                            const SizedBox(height: 8),
                            Text(value(w['country']),
                                style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 16),
                            Text(value(w['temperature']),
                                key: const Key('temperatureValue'),
                                style: const TextStyle(
                                    fontSize: 62,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w300)),
                            const Text('Temperature · API value',
                                style: TextStyle(color: Colors.white)),
                            const SizedBox(height: 10),
                            Text('Local time: ${value(w['localTime'])}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white)),
                          ] else
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Enter a city to load current weather.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      key: const Key('citySearchField'),
                      controller: controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) {
                        if (!loading) search();
                      },
                      decoration: InputDecoration(
                        labelText: 'City',
                        hintText: 'London or Tokyo',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const Key('searchButton'),
                      onPressed: loading ? null : search,
                      icon: const Icon(Icons.search),
                      label: const Text('Search'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(height: 20),
                      const Center(child: CircularProgressIndicator()),
                      const Center(child: Text('Loading weather...')),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 18),
                      Text(error!,
                          key: const Key('errorMessage'),
                          style: const TextStyle(color: Color(0xFFB42318))),
                      if (lastCity != null)
                        OutlinedButton.icon(
                          key: const Key('retryButton'),
                          onPressed: loading ? null : () => search(lastCity),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                    ],
                    if (w != null) ...[
                      const SizedBox(height: 24),
                      const Text('Weather details',
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio:
                            constraints.maxWidth < 360 ? 1.1 : 1.4,
                        children: [
                          detail(Icons.water_drop_outlined, 'Humidity',
                              '${value(w['humidity'])}%'),
                          detail(Icons.cloud_outlined, 'Cloud cover',
                              '${value(w['cloud'])}%'),
                          detail(Icons.air, 'Wind · API value',
                              value(w['wind'])),
                          detail(Icons.eco_outlined, 'EPA air quality',
                              '${value(w['airQuality'])} · ${aqiCategory(w['airQuality'] as num)}'),
                          detail(Icons.wb_sunny_outlined, 'UV · API value',
                              value(w['uv'])),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget detail(IconData icon, String label, String data) => Card(
        color: Colors.white,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF1683DD)),
              const SizedBox(height: 7),
              Text(label, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 5),
              Text(data, textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      );
}
