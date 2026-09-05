import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
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

  String get subtitle {
    final parts = <String>[
      if (district.isNotEmpty) district,
      if (state.isNotEmpty) state,
    ];

    return parts.join(', ');
  }
}

class RiskSnapshot {
  final DateTime fetchedAt;
  final double temperature;
  final double windSpeed;
  final double rainLast24h;
  final double rainNext12h;
  final double soilMoisture;
  final double elevation;
  final int landslideRisk;
  final int floodRisk;
  final int overallRisk;

  const RiskSnapshot({
    required this.fetchedAt,
    required this.temperature,
    required this.windSpeed,
    required this.rainLast24h,
    required this.rainNext12h,
    required this.soilMoisture,
    required this.elevation,
    required this.landslideRisk,
    required this.floodRisk,
    required this.overallRisk,
  });
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

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'HimRakshakAI/1.0',
          'Accept': 'application/json',
          'Accept-Language': 'en',
        },
      ).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        return PlaceInfo(
          name: 'Selected location',
          district: '',
          state: '',
          latitude: latitude,
          longitude: longitude,
        );
      }

      final data =
          jsonDecode(response.body) as Map<String, dynamic>;

      final address =
          (data['address'] as Map?)
                  ?.cast<String, dynamic>() ??
              <String, dynamic>{};

      String getValue(List<String> keys) {
        for (final key in keys) {
          final value = address[key];

          if (value != null &&
              value.toString().trim().isNotEmpty) {
            return value.toString().trim();
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

      if (name.isEmpty) {
        final display =
            data['display_name']?.toString().trim() ?? '';

        name = display.isNotEmpty
            ? display.split(',').first.trim()
            : 'Selected location';
      }

      final district = getValue([
        'state_district',
        'district',
        'county',
      ]);

      final state = getValue([
        'state',
      ]);

      return PlaceInfo(
        name: name,
        district: district,
        state: state,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {
      return PlaceInfo(
        name: 'Selected location',
        district: '',
        state: '',
        latitude: latitude,
        longitude: longitude,
      );
    }
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
      '&hourly=temperature_2m,precipitation,soil_moisture_0_to_1cm,wind_speed_10m'
      '&past_days=2'
      '&forecast_days=2'
      '&timezone=Asia%2FKolkata',
    );

    final response = await http.get(
      uri,
    ).timeout(
      const Duration(seconds: 20),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Weather service unavailable',
      );
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final hourly =
        data['hourly'] as Map<String, dynamic>?;

    if (hourly == null) {
      throw Exception(
        'Weather data unavailable',
      );
    }

    final times =
        (hourly['time'] as List? ?? const [])
            .map(
              (e) => DateTime.tryParse(
                e.toString(),
              ),
            )
            .toList();

    final temperatures = _toDoubleList(
      hourly['temperature_2m'] as List?,
    );

    final precipitation = _toDoubleList(
      hourly['precipitation'] as List?,
    );

    final soil = _toDoubleList(
      hourly['soil_moisture_0_to_1cm']
          as List?,
    );

    final wind = _toDoubleList(
      hourly['wind_speed_10m'] as List?,
    );

    if (times.isEmpty ||
        temperatures.isEmpty) {
      throw Exception(
        'Incomplete weather data',
      );
    }

    final now = DateTime.now();

    var nearestIndex = 0;

    var bestDiff =
        const Duration(days: 9999);

    for (var i = 0;
        i < times.length;
        i++) {
      final t = times[i];

      if (t == null) continue;

      final diff =
          t.difference(now).abs();

      if (diff < bestDiff) {
        bestDiff = diff;
        nearestIndex = i;
      }
    }

    double sumBetween(
      DateTime start,
      DateTime end,
    ) {
      var sum = 0.0;

      for (var i = 0;
          i < times.length &&
              i < precipitation.length;
          i++) {
        final t = times[i];

        if (t == null) continue;

        if (!t.isBefore(start) &&
            !t.isAfter(end)) {
          sum += precipitation[i];
        }
      }

      return sum;
    }

    final rainLast24h = sumBetween(
      now.subtract(
        const Duration(hours: 24),
      ),
      now,
    );

    final rainNext12h = sumBetween(
      now,
      now.add(
        const Duration(hours: 12),
      ),
    );

    final temperature =
        _at(
      temperatures,
      nearestIndex,
    );

    final windSpeed =
        _at(
      wind,
      nearestIndex,
    );

    final soilMoisture =
        _at(
      soil,
      nearestIndex,
    );

    final elevation =
        _asDouble(
      data['elevation'],
    );

    final rainSignal =
        ((rainLast24h +
                    rainNext12h) /
                80.0)
            .clamp(
      0.0,
      1.0,
    );

    final soilSignal =
        ((soilMoisture - 0.15) /
                0.35)
            .clamp(
      0.0,
      1.0,
    );

    final windSignal =
        (windSpeed / 70.0).clamp(
      0.0,
      1.0,
    );

    final elevationSignal =
        (elevation / 3000.0).clamp(
      0.0,
      1.0,
    );

    final landslideRisk = (
      rainSignal * 45 +
      soilSignal * 30 +
      elevationSignal * 20 +
      windSignal * 5
    )
        .round()
        .clamp(
          0,
          100,
        );

    final floodRisk = (
      rainSignal * 70 +
      soilSignal * 20 +
      math.min(
            1.0,
            rainNext12h / 40.0,
          ) *
          10
    )
        .round()
        .clamp(
          0,
          100,
        );

    final overallRisk = math
        .max(
          landslideRisk,
          floodRisk,
        )
        .clamp(
          0,
          100,
        );

    return RiskSnapshot(
      fetchedAt: DateTime.now(),
      temperature: temperature,
      windSpeed: windSpeed,
      rainLast24h: rainLast24h,
      rainNext12h: rainNext12h,
      soilMoisture: soilMoisture,
      elevation: elevation,
      landslideRisk: landslideRisk,
      floodRisk: floodRisk,
      overallRisk: overallRisk,
    );
  }

  static List<double> _toDoubleList(
    List? raw,
  ) {
    if (raw == null) {
      return const [];
    }

    return raw
        .map(
          _asDouble,
        )
        .toList();
  }

  static double _asDouble(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  static double _at(
    List<double> values,
    int index,
  ) {
    if (values.isEmpty) {
      return 0;
    }

    if (index < 0) {
      return values.first;
    }

    if (index >= values.length) {
      return values.last;
    }

    return values[index];
  }
}

class DashboardPage
    extends StatefulWidget {
  const DashboardPage({
    super.key,
  });

  @override
  State<DashboardPage> createState() =>
      _DashboardPageState();
}

class _DashboardPageState
    extends State<DashboardPage> {
  static const LatLng uttarakhandCenter =
      LatLng(
    30.0668,
    79.0193,
  );

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

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) => _loadCurrentLocation(),
    );

    _refreshTimer =
        Timer.periodic(
      const Duration(
        minutes: 15,
      ),
      (_) {
        final place =
            _selectedPlace;

        if (place != null) {
          _loadRisk(
            place,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();

    super.dispose();
  }

  Future<void>
      _loadCurrentLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final serviceEnabled =
          await Geolocator
              .isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _error =
              'Please turn on GPS/location services.';
        });

        _showUttarakhand();

        return;
      }

      var permission =
          await Geolocator
              .checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator
                .requestPermission();
      }

      if (permission ==
          LocationPermission.denied) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _error =
              'Location permission denied.';
        });

        _showUttarakhand();

        return;
      }

      if (permission ==
          LocationPermission
              .deniedForever) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _error =
              'Location permission is permanently denied. Enable it from app settings.';
        });

        _showUttarakhand();

        return;
      }

      final position =
          await Geolocator
              .getCurrentPosition(
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
    bool fromCurrentLocation =
        false,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedPosition = point;
      _snapshot = null;
    });

    try {
      final place =
          await LocationApi
              .reverseGeocode(
        point.latitude,
        point.longitude,
      );

      if (!mounted) return;

      setState(() {
        _selectedPlace = place;
      });

      final result =
          await WeatherRiskService
              .fetch(
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
          await WeatherRiskService
              .fetch(
        place,
      );

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

  Future<void>
      _openLocationSettings() async {
    await Geolocator
        .openLocationSettings();
  }

  Future<void>
      _openAppSettings() async {
    await Geolocator
        .openAppSettings();
  }

  Color _riskColor(
    int risk,
  ) {
    if (risk >= 70) {
      return Colors.red;
    }

    if (risk >= 40) {
      return Colors.orange;
    }

    return Colors.green;
  }

  String _riskLabel(
    int risk,
  ) {
    if (risk >= 70) {
      return 'High';
    }

    if (risk >= 40) {
      return 'Moderate';
    }

    return 'Low';
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final snapshot =
        _snapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HimRakshak AI',
        ),
        actions: [
          IconButton(
            tooltip:
                'View Uttarakhand',
            onPressed:
                _showUttarakhand,
            icon: const Icon(
              Icons.map_outlined,
            ),
          ),
          IconButton(
            tooltip:
                'My location',
            onPressed:
                _loadCurrentLocation,
            icon: const Icon(
              Icons.my_location,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController:
                        _mapController,
                    options:
                        MapOptions(
                      initialCenter:
                          uttarakhandCenter,
                      initialZoom:
                          7.3,
                      minZoom: 5,
                      maxZoom: 18,
                      onTap: (
                        tapPosition,
                        point,
                      ) {
                        _analysePoint(
                          point,
                        );
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
                              child:
                                  Icon(
                                Icons
                                    .location_on,
                                size: 48,
                                color: snapshot ==
                                        null
                                    ? Colors
                                        .orange
                                    : _riskColor(
                                        snapshot
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
                  if (_loading)
                    const Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child:
                          LinearProgressIndicator(),
                    ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Column(
                      children: [
                        FloatingActionButton
                            .small(
                          heroTag:
                              'myLocation',
                          tooltip:
                              'My location',
                          onPressed:
                              _loadCurrentLocation,
                          child:
                              const Icon(
                            Icons.my_location,
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        FloatingActionButton
                            .small(
                          heroTag:
                              'uttarakhand',
                          tooltip:
                              'View Uttarakhand',
                          onPressed:
                              _showUttarakhand,
                          child:
                              const Icon(
                            Icons.map,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child:
                  SingleChildScrollView(
                padding:
                    const EdgeInsets.all(
                  14,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                  children: [
                    if (_error != null)
                      Card(
                        child: Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            12,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                _error!,
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.red,
                                ),
                              ),
                              const SizedBox(
                                height: 8,
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed:
                                        _openLocationSettings,
                                    child:
                                        const Text(
                                      'Location settings',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _openAppSettings,
                                    child:
                                        const Text(
                                      'App settings',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    Text(
                      _selectedPlace
                              ?.name ??
                          'Tap anywhere on the map',
                      style:
                          Theme.of(
                        context,
                      ).textTheme
                              .titleLarge,
                    ),
                    if ((_selectedPlace
                                ?.subtitle ??
                            '')
                        .isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets
                                .only(
                          top: 2,
                        ),
                        child: Text(
                          _selectedPlace!
                              .subtitle,
                        ),
                      ),
                    if (_selectedPosition !=
                        null)
                      Padding(
                        padding:
                            const EdgeInsets
                                .only(
                          top: 4,
                        ),
                        child: Text(
                          '${_selectedPosition!.latitude.toStringAsFixed(5)}, '
                          '${_selectedPosition!.longitude.toStringAsFixed(5)}',
                          style:
                              Theme.of(
                            context,
                          ).textTheme
                                  .bodySmall,
                        ),
                      ),
                    const SizedBox(
                      height: 12,
                    ),
                    if (snapshot !=
                        null) ...[
                      Card(
                        child: Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            14,
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${snapshot.overallRisk}/100',
                                style:
                                    TextStyle(
                                  fontSize:
                                      34,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                  color:
                                      _riskColor(
                                    snapshot
                                        .overallRisk,
                                  ),
                                ),
                              ),
                              Text(
                                '${_riskLabel(snapshot.overallRisk)} experimental risk indicator',
                              ),
                              const SizedBox(
                                height: 10,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child:
                                        _metric(
                                      'Landslide',
                                      '${snapshot.landslideRisk}/100',
                                    ),
                                  ),
                                  Expanded(
                                    child:
                                        _metric(
                                      'Flood',
                                      '${snapshot.floodRisk}/100',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Card(
                        child: Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            14,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child:
                                        _metric(
                                      'Temperature',
                                      '${snapshot.temperature.toStringAsFixed(1)} °C',
                                    ),
                                  ),
                                  Expanded(
                                    child:
                                        _metric(
                                      'Wind',
                                      '${snapshot.windSpeed.toStringAsFixed(1)} km/h',
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  Expanded(
                                    child:
                                        _metric(
                                      'Rain 24h',
                                      '${snapshot.rainLast24h.toStringAsFixed(1)} mm',
                                    ),
                                  ),
                                  Expanded(
                                    child:
                                        _metric(
                                      'Next 12h',
                                      '${snapshot.rainNext12h.toStringAsFixed(1)} mm',
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  Expanded(
                                    child:
                                        _metric(
                                      'Soil moisture',
                                      snapshot
                                          .soilMoisture
                                          .toStringAsFixed(
                                        3,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child:
                                        _metric(
                                      'Elevation',
                                      '${snapshot.elevation.toStringAsFixed(0)} m',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      const Text(
                        'Experimental decision-support only. This is not an official emergency warning system. Always follow alerts and instructions from authorized agencies.',
                        style:
                            TextStyle(
                          fontSize: 12,
                          fontStyle:
                              FontStyle
                                  .italic,
                        ),
                      ),
                    ] else if (!_loading)
                      const Card(
                        child: Padding(
                          padding:
                              EdgeInsets.all(
                            16,
                          ),
                          child: Text(
                            'Tap a location on the map to load live weather and the experimental hazard indicator.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 6,
      ),
      child: Column(
        children: [
          Text(
            value,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
              fontSize: 16,
            ),
            textAlign:
                TextAlign.center,
          ),
          const SizedBox(
            height: 2,
          ),
          Text(
            label,
            style:
                const TextStyle(
              fontSize: 12,
            ),
            textAlign:
                TextAlign.center,
          ),
        ],
      ),
    );
  }
}
