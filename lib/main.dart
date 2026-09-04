import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const HimRakshakApp());
}

class HimRakshakApp extends StatelessWidget {
  const HimRakshakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HimRakshak AI',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const DashboardPage(),
    );
  }
}

class PlaceInfo {
  final String name;
  final String district;
  final String state;
  final double latitude;
  final double longitude;

  const PlaceInfo({
    required this.name,
    required this.district,
    required this.state,
    required this.latitude,
    required this.longitude,
  });
}

class RiskSnapshot {
  final PlaceInfo place;
  final double rainfall24;
  final double rainfall72;
  final double rainfallNext12;
  final double soilMoisture;
  final double windSpeed;
  final double temperature;
  final double elevation;

  final int landslideRisk;
  final int floodRisk;
  final int overallRisk;

  final DateTime updatedAt;

  const RiskSnapshot({
    required this.place,
    required this.rainfall24,
    required this.rainfall72,
    required this.rainfallNext12,
    required this.soilMoisture,
    required this.windSpeed,
    required this.temperature,
    required this.elevation,
    required this.landslideRisk,
    required this.floodRisk,
    required this.overallRisk,
    required this.updatedAt,
  });

  String get level {
    if (overallRisk >= 80) return 'CRITICAL';
    if (overallRisk >= 60) return 'HIGH';
    if (overallRisk >= 35) return 'MODERATE';
    return 'LOW';
  }
}

class LocationApi {
  static Future<PlaceInfo> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?format=jsonv2'
      '&lat=$latitude'
      '&lon=$longitude'
      '&zoom=15'
      '&addressdetails=1',
    );

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'HimRakshakAI/1.0',
        'Accept': 'application/json',
      },
    ).timeout(
      const Duration(seconds: 20),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Location service unavailable',
      );
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final address =
        (data['address'] as Map<String, dynamic>?) ?? {};

    String getValue(List<String> keys) {
      for (final key in keys) {
        final value = address[key];

        if (value != null &&
            value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }

      return '';
    }

    var name = getValue([
      'village',
      'town',
      'city',
      'hamlet',
      'municipality',
      'suburb',
    ]);

    final district = getValue([
      'state_district',
      'district',
      'county',
    ]);

    final state = getValue([
      'state',
    ]);

    if (name.isEmpty) {
      final display =
          data['display_name']?.toString() ?? '';

      if (display.isNotEmpty) {
        name = display.split(',').first.trim();
      } else {
        name = 'Selected location';
      }
    }

    return PlaceInfo(
      name: name,
      district:
          district.isEmpty ? 'Unknown district' : district,
      state: state.isEmpty ? 'Unknown state' : state,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class WeatherRiskService {
  static Future<RiskSnapshot> fetch(
    PlaceInfo place,
  ) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=${place.latitude}'
      '&longitude=${place.longitude}'
      '&hourly=precipitation,soil_moisture_0_to_1cm,wind_speed_10m,temperature_2m'
      '&past_days=3'
      '&forecast_days=2'
      '&timezone=Asia%2FKolkata',
    );

    final response = await http.get(uri).timeout(
      const Duration(seconds: 20),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Live environmental data unavailable',
      );
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final hourly =
        data['hourly'] as Map<String, dynamic>;

    final times = (hourly['time'] as List)
        .map(
          (value) =>
              DateTime.parse(value.toString()),
        )
        .toList();

    final rainfall =
        (hourly['precipitation'] as List)
            .map(
              (value) =>
                  (value as num?)?.toDouble() ?? 0,
            )
            .toList();

    final soil =
        (hourly['soil_moisture_0_to_1cm'] as List)
            .map(
              (value) =>
                  (value as num?)?.toDouble() ?? 0,
            )
            .toList();

    final wind =
        (hourly['wind_speed_10m'] as List)
            .map(
              (value) =>
                  (value as num?)?.toDouble() ?? 0,
            )
            .toList();

    final temperature =
        (hourly['temperature_2m'] as List)
            .map(
              (value) =>
                  (value as num?)?.toDouble() ?? 0,
            )
            .toList();

    final now = DateTime.now();

    double rainfallBetween(
      Duration past,
      Duration future,
    ) {
      double total = 0;

      final start = now.subtract(past);
      final end = now.add(future);

      for (var i = 0; i < times.length; i++) {
        if (!times[i].isBefore(start) &&
            !times[i].isAfter(end)) {
          total += rainfall[i];
        }
      }

      return total;
    }

    final rain24 = rainfallBetween(
      const Duration(hours: 24),
      Duration.zero,
    );

    final rain72 = rainfallBetween(
      const Duration(hours: 72),
      Duration.zero,
    );

    final rainNext12 = rainfallBetween(
      Duration.zero,
      const Duration(hours: 12),
    );

    var nearest = 0;
    var bestDifference =
        const Duration(days: 9999);

    for (var i = 0; i < times.length; i++) {
      final difference =
          times[i].difference(now).abs();

      if (difference < bestDifference) {
        bestDifference = difference;
        nearest = i;
      }
    }

    final soilNow = soil[nearest];
    final windNow = wind[nearest];
    final temperatureNow =
        temperature[nearest];

    final elevation =
        (data['elevation'] as num?)?.toDouble() ?? 0;

    final elevationScore =
        elevation >= 3000
            ? 26.0
            : elevation >= 2200
                ? 22.0
                : elevation >= 1400
                    ? 18.0
                    : elevation >= 700
                        ? 12.0
                        : 8.0;

    final rainfallScore = math.min(
      42.0,
      rain24 * 0.35 +
          rain72 * 0.09 +
          rainNext12 * 0.28,
    );

    final soilScore = math.min(
      24.0,
      soilNow * 100 * 0.25,
    );

    final windScore = math.min(
      8.0,
      windNow * 0.10,
    );

    final landslide = (
      elevationScore +
      rainfallScore +
      soilScore +
      windScore
    ).clamp(0.0, 100.0).round();

    final flood = (
      rain24 * 0.48 +
      rain72 * 0.10 +
      rainNext12 * 0.35 +
      soilNow * 25 +
      (elevation < 1500 ? 8 : 2)
    ).clamp(0.0, 100.0).round();

    final overall =
        math.max(landslide, flood);

    return RiskSnapshot(
      place: place,
      rainfall24: rain24,
      rainfall72: rain72,
      rainfallNext12: rainNext12,
      soilMoisture: soilNow,
      windSpeed: windNow,
      temperature: temperatureNow,
      elevation: elevation,
      landslideRisk: landslide,
      floodRisk: flood,
      overallRisk: overall,
      updatedAt: DateTime.now(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() =>
      _DashboardPageState();
}

class _DashboardPageState
    extends State<DashboardPage> {
  static const LatLng uttarakhandCenter =
      LatLng(30.0668, 79.0193);

  final MapController _mapController =
      MapController();

  LatLng? _userPosition;
  LatLng? _selectedPosition;

  PlaceInfo? _selectedPlace;
  RiskSnapshot? _snapshot;

  bool _loading = true;
  String? _error;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadCurrentLocation(),
    );

    _refreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) {
        if (_selectedPlace != null) {
          _loadRisk(_selectedPlace!);
        }
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        setState(() {
          _loading = false;
          _error =
              'Please turn on GPS/location services.';
        });

        _showUttarakhand();
        return;
      }

      var permission =
          await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission ==
              LocationPermission.denied ||
          permission ==
              LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _error =
              'Location permission is required to show your current position.';
        });

        _showUttarakhand();
        return;
      }

      final position =
          await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.high,
      );

      final point = LatLng(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      setState(() {
        _userPosition = point;
        _selectedPosition = point;
      });

      _mapController.move(
        point,
        14,
      );

      await _analysePoint(
        point,
        fromCurrentLocation: true,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error =
            'Unable to get current location: $e';
      });

      _showUttarakhand();
    }
  }

  Future<void> _analysePoint(
    LatLng point, {
    bool fromCurrentLocation = false,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedPosition = point;
      _snapshot = null;
    });

    try {
      final place =
          await LocationApi.reverseGeocode(
        point.latitude,
        point.longitude,
      );

      if (!mounted) return;

      setState(() {
        _selectedPlace = place;
      });

      final result =
          await WeatherRiskService.fetch(
        place,
      );

      if (!mounted) return;

      setState(() {
        _snapshot = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadRisk(
    PlaceInfo place,
  ) async {
    try {
      final result =
          await WeatherRiskService.fetch(place);

      if (!mounted) return;

      setState(() {
        _snapshot = result;
      });
    } catch (_) {}
  }

  void _showUttarakhand() {
    _mapController.move(
      uttarakhandCenter,
      7.3,
    );
  }

  Color _riskColor(int score) {
    if (score >= 80) {
      return Colors.red.shade700;
    }

    if (score >= 60) {
      return Colors.deepOrange;
    }

    if (score >= 35) {
      return Colors.amber.shade800;
    }

    return Colors.green.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HimRakshak AI',
        ),
        actions: [
          IconButton(
            tooltip: 'My location',
            onPressed:
                _loadCurrentLocation,
            icon: const Icon(
              Icons.my_location,
            ),
          ),
          IconButton(
            tooltip:
                'View Uttarakhand',
            onPressed:
                _showUttarakhand,
            icon: const Icon(
              Icons.map,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _selectedPlace == null
                    ? null
                    : () => _loadRisk(
                          _selectedPlace!,
                        ),
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                14,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live Mountain Hazard Intelligence',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  const Text(
                    'Your current location is shown first. Pan, zoom or tap anywhere on the map to analyse another location.',
                  ),
                  if (_loading)
                    const Padding(
                      padding:
                          EdgeInsets.only(
                        top: 12,
                      ),
                      child:
                          LinearProgressIndicator(),
                    ),
                  if (_error != null)
                    Padding(
                      padding:
                          const EdgeInsets.only(
                        top: 10,
                      ),
                      child: Text(
                        _error!,
                        style:
                            const TextStyle(
                          color: Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 480,
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              child: FlutterMap(
                mapController:
                    _mapController,
                options: MapOptions(
                  initialCenter:
                      uttarakhandCenter,
                  initialZoom: 7.3,
                  minZoom: 5,
                  maxZoom: 18,
                  onTap:
                      (
                        tapPosition,
                        point,
                      ) {
                    _analysePoint(point);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:
                        'in.himrakshak.live',
                  ),

                  MarkerLayer(
                    markers: [
                      if (_userPosition !=
                          null)
                        Marker(
                          point:
                              _userPosition!,
                          width: 52,
                          height: 52,
                          child:
                              const Icon(
                            Icons
                                .person_pin_circle,
                            size: 48,
                            color:
                                Colors.blue,
                          ),
                        ),

                      if (_selectedPosition !=
                              null &&
                          _selectedPosition !=
                              _userPosition)
                        Marker(
                          point:
                              _selectedPosition!,
                          width: 52,
                          height: 52,
                          child: Icon(
                            Icons
                                .location_on,
                            size: 48,
                            color:
                                _snapshot ==
                                        null
                                    ? Colors
                                        .orange
                                    : _riskColor(
                                        _snapshot!
                                            .overallRisk,
                                      ),
                          ),
                        ),
                    ],
                  ),

                  RichAttributionWidget(
                    attributions:
                        const [
                      TextSourceAttribution(
                        'OpenStreetMap contributors',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child:
                    FilledButton.icon(
                  onPressed:
                      _loadCurrentLocation,
                  icon: const Icon(
                    Icons.my_location,
                  ),
                  label: const Text(
                    'My Location',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _showUttarakhand,
                  icon: const Icon(
                    Icons.map,
                  ),
                  label: const Text(
                    'Uttarakhand',
                  ),
                ),
              ),
            ],
          ),

          if (_selectedPlace != null)
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selected location',
                      style: TextStyle(
                        color:
                            Colors.grey,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      _selectedPlace!.name,
                      style:
                          const TextStyle(
                        fontSize: 22,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_selectedPlace!.district}, ${_selectedPlace!.state}',
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      'Latitude: ${_selectedPlace!.latitude.toStringAsFixed(5)}',
                    ),
                    Text(
                      'Longitude: ${_selectedPlace!.longitude.toStringAsFixed(5)}',
                    ),
                  ],
                ),
              ),
            ),

          if (_snapshot != null)
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _snapshot!
                                .place
                                .name,
                            style:
                                const TextStyle(
                              fontSize: 21,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            _snapshot!
                                .level,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Text(
                      'Overall risk ${_snapshot!.overallRisk}/100',
                      style: TextStyle(
                        fontSize: 29,
                        fontWeight:
                            FontWeight.bold,
                        color:
                            _riskColor(
                          _snapshot!
                              .overallRisk,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    LinearProgressIndicator(
                      value:
                          _snapshot!
                                  .overallRisk /
                              100,
                      minHeight: 10,
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                    ),

                    const SizedBox(
                      height: 18,
                    ),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metric(
                          'Landslide',
                          '${_snapshot!.landslideRisk}%',
                        ),
                        _metric(
                          'Flash flood',
                          '${_snapshot!.floodRisk}%',
                        ),
                        _metric(
                          'Rain 24h',
                          '${_snapshot!.rainfall24.toStringAsFixed(1)} mm',
                        ),
                        _metric(
                          'Rain 72h',
                          '${_snapshot!.rainfall72.toStringAsFixed(1)} mm',
                        ),
                        _metric(
                          'Next 12h',
                          '${_snapshot!.rainfallNext12.toStringAsFixed(1)} mm',
                        ),
                        _metric(
                          'Soil moisture',
                          _snapshot!
                              .soilMoisture
                              .toStringAsFixed(
                                2,
                              ),
                        ),
                        _metric(
                          'Temperature',
                          '${_snapshot!.temperature.toStringAsFixed(1)} °C',
                        ),
                        _metric(
                          'Wind',
                          '${_snapshot!.windSpeed.toStringAsFixed(1)} km/h',
                        ),
                        _metric(
                          'Elevation',
                          '${_snapshot!.elevation.toStringAsFixed(0)} m',
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      'Updated: ${DateFormat('dd MMM yyyy, hh:mm a').format(_snapshot!.updatedAt)}',
                    ),
                  ],
                ),
              ),
            ),

          if (_snapshot != null)
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Why this risk?',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      '24-hour rainfall: ${_snapshot!.rainfall24.toStringAsFixed(1)} mm\n'
                      '72-hour rainfall: ${_snapshot!.rainfall72.toStringAsFixed(1)} mm\n'
                      'Next 12-hour rainfall: ${_snapshot!.rainfallNext12.toStringAsFixed(1)} mm\n'
                      'Soil moisture: ${_snapshot!.soilMoisture.toStringAsFixed(2)}\n'
                      'Elevation: ${_snapshot!.elevation.toStringAsFixed(0)} m\n'
                      'Wind: ${_snapshot!.windSpeed.toStringAsFixed(1)} km/h',
                    ),
                  ],
                ),
              ),
            ),

          Card(
            color:
                Colors.amber.shade50,
            child: const Padding(
              padding:
                  EdgeInsets.all(14),
              child: Text(
                'Safety notice: Risk scores are experimental decision-support indicators, not official emergency warnings. Follow DMMC, IMD, CWC, NDMA and local administration advisories for emergency decisions.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
  ) {
    return Container(
      width: 155,
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.black12,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color:
                  Colors.grey.shade700,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight:
                  FontWeight.bold,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}
