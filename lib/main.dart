import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    as mbx;
import 'package:xml/xml.dart';

const String mapboxAccessToken =
    String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
);

const String imdAuthHeaderName =
    String.fromEnvironment(
  'IMD_AUTH_HEADER_NAME',
);

const String imdAuthHeaderValue =
    String.fromEnvironment(
  'IMD_AUTH_HEADER_VALUE',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.instance.initialize();

  if (mapboxAccessToken.trim().isNotEmpty) {
    mbx.MapboxOptions.setAccessToken(
      mapboxAccessToken,
    );
  }

  runApp(
    const HimRakshakApp(),
  );
}

class HimRakshakApp extends StatelessWidget {
  const HimRakshakApp({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
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

class NotificationService {
  NotificationService._();

  static final NotificationService instance =
      NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel
      _criticalChannel =
      AndroidNotificationChannel(
    'himrakshak_critical',
    'Critical HimRakshak Alerts',
    description:
        'Critical experimental hazard indicators',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  Future<void> initialize() async {
    const settings =
        InitializationSettings(
      android:
          AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      ),
    );

    await _plugin.initialize(
      settings,
    );

    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await android?.createNotificationChannel(
      _criticalChannel,
    );
  }

  Future<void> requestPermission() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await android
        ?.requestNotificationsPermission();
  }

  Future<void> showCriticalAlert({
    required String place,
    required int risk,
  }) async {
    const androidDetails =
        AndroidNotificationDetails(
      'himrakshak_critical',
      'Critical HimRakshak Alerts',
      channelDescription:
          'Critical experimental hazard indicators',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const details =
        NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      DateTime.now()
          .millisecondsSinceEpoch
          .remainder(
            100000,
          ),
      'Critical HimRakshak Alert',
      'High experimental hazard indicator near '
          '$place. Risk: $risk/100.',
      details,
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
      if (district.trim().isNotEmpty)
        district.trim(),
      if (state.trim().isNotEmpty)
        state.trim(),
    ];

    return parts.join(
      ', ',
    );
  }
}

class RiskSnapshot {
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

class OfficialObservation {
  final String source;
  final String station;
  final DateTime? observedAt;

  final double? temperature;
  final double? humidity;
  final double? windSpeed;
  final double? rainfall24h;

  const OfficialObservation({
    required this.source,
    required this.station,
    required this.observedAt,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.rainfall24h,
  });
}

class OfficialAlert {
  final String source;
  final String title;
  final String description;
  final String severity;
  final DateTime? issuedAt;
  final String link;

  const OfficialAlert({
    required this.source,
    required this.title,
    required this.description,
    required this.severity,
    required this.issuedAt,
    required this.link,
  });
}

class OfficialDataBundle {
  final OfficialObservation? observation;

  final List<OfficialAlert> alerts;

  final String observationStatus;

  final DateTime fetchedAt;

  const OfficialDataBundle({
    required this.observation,
    required this.alerts,
    required this.observationStatus,
    required this.fetchedAt,
  });
}

class OfficialDataService {
  static const String _imdCurrentWeatherUrl =
      'https://api.imd.gov.in/api/v1/current_wx';

  static const String _ndmaRssUrl =
      'https://sachet.ndma.gov.in/'
      'cap_public_website/rss/rss_india.xml';

  static Future<OfficialDataBundle> fetch(
    PlaceInfo place,
  ) async {
    OfficialObservation? observation;

    String observationStatus =
        'IMD official observation is not '
        'configured yet. '
        'Add your IMD API authentication '
        'header in GitHub Actions secrets.';

    try {
      final result =
          await _fetchImdObservation(
        place,
      );

      observation = result.$1;
      observationStatus = result.$2;
    } catch (error) {
      observationStatus =
          'IMD observation unavailable: $error';
    }

    List<OfficialAlert> alerts =
        const [];

    try {
      alerts =
          await _fetchNdmaAlerts(
        place,
      );
    } catch (_) {
      alerts = const [];
    }

    return OfficialDataBundle(
      observation: observation,
      alerts: alerts,
      observationStatus:
          observationStatus,
      fetchedAt: DateTime.now(),
    );
  }

  static Future<
          (
            OfficialObservation?,
            String
          )>
      _fetchImdObservation(
    PlaceInfo place,
  ) async {
    if (imdAuthHeaderName
            .trim()
            .isEmpty ||
        imdAuthHeaderValue
            .trim()
            .isEmpty) {
      return (
        null,
        'IMD official observation requires '
            'API authentication. '
            'The app will never fabricate '
            'an IMD reading.'
      );
    }

    final response =
        await http
            .get(
              Uri.parse(
                _imdCurrentWeatherUrl,
              ),
              headers: {
                imdAuthHeaderName:
                    imdAuthHeaderValue,
                'Accept':
                    'application/json',
              },
            )
            .timeout(
              const Duration(
                seconds: 15,
              ),
            );

    if (response.statusCode != 200) {
      return (
        null,
        'IMD API returned HTTP '
            '${response.statusCode}.'
      );
    }

    final decoded =
        jsonDecode(
      response.body,
    );

    final rows =
        <Map<String, dynamic>>[];

    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map) {
          rows.add(
            item.map(
              (
                key,
                value,
              ) =>
                  MapEntry(
                key.toString(),
                value,
              ),
            ),
          );
        }
      }
    } else if (decoded is Map) {
      final dynamic possibleData =
          decoded['data'] ??
              decoded['result'] ??
              decoded['records'];

      if (possibleData is List) {
        for (final item
            in possibleData) {
          if (item is Map) {
            rows.add(
              item.map(
                (
                  key,
                  value,
                ) =>
                    MapEntry(
                  key.toString(),
                  value,
                ),
              ),
            );
          }
        }
      } else {
        rows.add(
          decoded.map(
            (
              key,
              value,
            ) =>
                MapEntry(
              key.toString(),
              value,
            ),
          ),
        );
      }
    }

    if (rows.isEmpty) {
      return (
        null,
        'IMD returned no '
            'current-weather records.'
      );
    }

    Map<String, dynamic>?
        selected;

    final placeTokens =
        <String>[
      place.name,
      place.district,
    ]
            .where(
              (value) =>
                  value
                      .trim()
                      .isNotEmpty,
            )
            .map(
              (value) =>
                  value.toLowerCase(),
            )
            .toList();

    int bestScore = -1;

    for (final row in rows) {
      final station =
          _stringValue(
        row,
        const [
          'Station',
          'station',
          'Station_Name',
          'station_name',
        ],
      ).toLowerCase();

      var score = 0;

      for (final token
          in placeTokens) {
        if (station.contains(
              token,
            ) ||
            token.contains(
              station,
            )) {
          score += 5;
        } else {
          for (final part
              in token.split(
            RegExp(
              r'\s+',
            ),
          )) {
            if (part.length >= 4 &&
                station.contains(
                  part,
                )) {
              score += 1;
            }
          }
        }
      }

      if (score > bestScore) {
        bestScore = score;
        selected = row;
      }
    }

    selected ??= rows.first;

    final station =
        _stringValue(
      selected,
      const [
        'Station',
        'station',
        'Station_Name',
        'station_name',
      ],
    );

    final dateText =
        _stringValue(
      selected,
      const [
        'Date of Observation',
        'date_of_observation',
        'Date',
        'date',
      ],
    );

    final timeText =
        _stringValue(
      selected,
      const [
        'Time of Observation',
        'time_of_observation',
        'Time',
        'time',
      ],
    );

    DateTime? observedAt;

    if (dateText.isNotEmpty) {
      final candidate =
          '${dateText.trim()} '
                  '${timeText.trim()}'
              .trim();

      observedAt =
          DateTime.tryParse(
                candidate,
              ) ??
              DateTime.tryParse(
                dateText.trim(),
              );
    }

    final observation =
        OfficialObservation(
      source:
          'India Meteorological Department (IMD)',
      station:
          station.isEmpty
              ? 'IMD reporting station'
              : station,
      observedAt: observedAt,
      temperature:
          _numberValue(
        selected,
        const [
          'Temperature',
          'temperature',
          'Temp',
          'temp',
        ],
      ),
      humidity:
          _numberValue(
        selected,
        const [
          'Humidity',
          'humidity',
          'RH',
        ],
      ),
      windSpeed:
          _numberValue(
        selected,
        const [
          'Wind Speed',
          'wind_speed',
          'WindSpeed',
        ],
      ),
      rainfall24h:
          _numberValue(
        selected,
        const [
          'Last 24 hrs Rainfall',
          'last_24_hrs_rainfall',
          'Past_24_hrs_Rainfall',
          'rainfall_24h',
        ],
      ),
    );

    return (
      observation,
      'Official IMD observation loaded.'
    );
  }

  static Future<
          List<OfficialAlert>>
      _fetchNdmaAlerts(
    PlaceInfo place,
  ) async {
    final response =
        await http
            .get(
              Uri.parse(
                _ndmaRssUrl,
              ),
              headers:
                  const {
                'Accept':
                    'application/rss+xml, '
                    'application/xml, '
                    'text/xml',
                'User-Agent':
                    'HimRakshakAI/1.2',
              },
            )
            .timeout(
              const Duration(
                seconds: 15,
              ),
            );

    if (response.statusCode !=
        200) {
      return const [];
    }

    final document =
        XmlDocument.parse(
      response.body,
    );

    final searchTokens =
        <String>[
      place.name,
      place.district,
      place.state,
      'Uttarakhand',
    ]
            .where(
              (value) =>
                  value
                      .trim()
                      .isNotEmpty,
            )
            .map(
              (value) =>
                  value.toLowerCase(),
            )
            .toSet();

    final alerts =
        <OfficialAlert>[];

    for (final item
        in document
            .findAllElements(
          'item',
        )) {
      final title =
          item
                  .getElement(
                    'title',
                  )
                  ?.innerText
                  .trim() ??
              '';

      final description =
          item
                  .getElement(
                    'description',
                  )
                  ?.innerText
                  .trim() ??
              '';

      final link =
          item
                  .getElement(
                    'link',
                  )
                  ?.innerText
                  .trim() ??
              '';

      final pubDate =
          item
                  .getElement(
                    'pubDate',
                  )
                  ?.innerText
                  .trim() ??
              '';

      final combined =
          '$title $description'
              .toLowerCase();

      final matches =
          searchTokens.any(
        combined.contains,
      );

      if (!matches) {
        continue;
      }

      final severity =
          _inferSeverity(
        '$title $description',
      );

      alerts.add(
        OfficialAlert(
          source:
              'NDMA SACHET / issuing authority',
          title:
              title.isEmpty
                  ? 'Official alert'
                  : title,
          description:
              description,
          severity:
              severity,
          issuedAt:
              DateTime.tryParse(
            pubDate,
          ),
          link: link,
        ),
      );
    }

    return alerts
        .take(
          8,
        )
        .toList();
  }

  static String _inferSeverity(
    String text,
  ) {
    final value =
        text.toLowerCase();

    if (value.contains(
          'red',
        ) ||
        value.contains(
          'extreme',
        ) ||
        value.contains(
          'severe',
        )) {
      return 'Severe';
    }

    if (value.contains(
      'orange',
    )) {
      return 'Orange';
    }

    if (value.contains(
      'yellow',
    )) {
      return 'Yellow';
    }

    return 'Official';
  }

  static String _stringValue(
    Map<String, dynamic> row,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = row[key];

      if (value != null &&
          value
              .toString()
              .trim()
              .isNotEmpty) {
        return value
            .toString()
            .trim();
      }
    }

    return '';
  }

  static double? _numberValue(
    Map<String, dynamic> row,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = row[key];

      if (value is num) {
        return value.toDouble();
      }

      final parsed =
          double.tryParse(
        value
                ?.toString()
                .replaceAll(
                  ',',
                  '',
                )
                .trim() ??
            '',
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }
}

enum HimRakshakMapMode {
  satellite,
  hybrid,
  terrain,
}
class LocationApi {
  static const headers = {
    'User-Agent':
        'HimRakshakAI/1.1',
    'Accept':
        'application/json',
    'Accept-Language':
        'en',
  };

  static Future<PlaceInfo>
      reverseGeocode(
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
      final response =
          await http
              .get(
                uri,
                headers: headers,
              )
              .timeout(
                const Duration(
                  seconds: 15,
                ),
              );

      if (response.statusCode !=
          200) {
        return _fallback(
          latitude,
          longitude,
        );
      }

      final data =
          jsonDecode(
        response.body,
      ) as Map<String, dynamic>;

      return _fromData(
        data,
        latitude,
        longitude,
      );
    } catch (_) {
      return _fallback(
        latitude,
        longitude,
      );
    }
  }

  static Future<List<PlaceInfo>>
      search(
    String query,
  ) async {
    final cleaned =
        query.trim();

    if (cleaned.isEmpty) {
      return const [];
    }

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'format': 'jsonv2',
        'q': cleaned,
        'limit': '8',
        'addressdetails': '1',
        'countrycodes': 'in',
      },
    );

    final response =
        await http
            .get(
              uri,
              headers: headers,
            )
            .timeout(
              const Duration(
                seconds: 15,
              ),
            );

    if (response.statusCode !=
        200) {
      throw Exception(
        'Place search unavailable',
      );
    }

    final raw =
        jsonDecode(
      response.body,
    ) as List<dynamic>;

    final results =
        <PlaceInfo>[];

    for (final item in raw) {
      if (item is! Map) {
        continue;
      }

      final data =
          item.cast<
              String,
              dynamic>();

      final latitude =
          double.tryParse(
        data['lat']
                ?.toString() ??
            '',
      );

      final longitude =
          double.tryParse(
        data['lon']
                ?.toString() ??
            '',
      );

      if (latitude == null ||
          longitude == null) {
        continue;
      }

      results.add(
        _fromData(
          data,
          latitude,
          longitude,
        ),
      );
    }

    results.sort(
      (a, b) {
        final first =
            a.state
                    .toLowerCase()
                    .contains(
                      'uttarakhand',
                    )
                ? 0
                : 1;

        final second =
            b.state
                    .toLowerCase()
                    .contains(
                      'uttarakhand',
                    )
                ? 0
                : 1;

        return first.compareTo(
          second,
        );
      },
    );

    return results;
  }

  static PlaceInfo _fromData(
    Map<String, dynamic> data,
    double latitude,
    double longitude,
  ) {
    final address =
        (data['address'] as Map?)
                ?.cast<
                    String,
                    dynamic>() ??
            {};

    String read(
      List<String> keys,
    ) {
      for (final key in keys) {
        final value =
            address[key];

        if (value != null &&
            value
                .toString()
                .trim()
                .isNotEmpty) {
          return value
              .toString()
              .trim();
        }
      }

      return '';
    }

    var name = read(
      [
        'village',
        'town',
        'city',
        'hamlet',
        'municipality',
        'suburb',
        'locality',
      ],
    );

    if (name.isEmpty) {
      name =
          data['name']
                  ?.toString()
                  .trim() ??
              '';
    }

    if (name.isEmpty) {
      final display =
          data['display_name']
                  ?.toString()
                  .trim() ??
              '';

      if (display.isNotEmpty) {
        name = display
            .split(',')
            .first
            .trim();
      }
    }

    if (name.isEmpty) {
      name =
          'Selected location';
    }

    return PlaceInfo(
      name: name,
      district: read(
        [
          'state_district',
          'district',
          'county',
        ],
      ),
      state: read(
        [
          'state',
        ],
      ),
      latitude: latitude,
      longitude: longitude,
    );
  }

  static PlaceInfo _fallback(
    double latitude,
    double longitude,
  ) {
    return PlaceInfo(
      name:
          'Selected location',
      district: '',
      state: '',
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class WeatherRiskService {
  static Future<RiskSnapshot>
      fetch(
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

    final response =
        await http
            .get(
              uri,
            )
            .timeout(
              const Duration(
                seconds: 20,
              ),
            );

    if (response.statusCode !=
        200) {
      throw Exception(
        'Weather service unavailable',
      );
    }

    final data =
        jsonDecode(
      response.body,
    ) as Map<String, dynamic>;

    final hourly =
        data['hourly']
            as Map<
                String,
                dynamic>?;

    if (hourly == null) {
      throw Exception(
        'Weather data unavailable',
      );
    }

    final times =
        (hourly['time']
                    as List? ??
                const [])
            .map(
              (value) =>
                  DateTime.tryParse(
                value.toString(),
              ),
            )
            .toList();

    final temperatures =
        _list(
      hourly[
              'temperature_2m']
          as List?,
    );

    final rain =
        _list(
      hourly['precipitation']
          as List?,
    );

    final soil =
        _list(
      hourly[
              'soil_moisture_0_to_1cm']
          as List?,
    );

    final wind =
        _list(
      hourly[
              'wind_speed_10m']
          as List?,
    );

    if (times.isEmpty ||
        temperatures.isEmpty) {
      throw Exception(
        'Incomplete weather data',
      );
    }

    final now =
        DateTime.now();

    var nearestIndex = 0;

    var nearestDifference =
        const Duration(
      days: 9999,
    );

    for (var index = 0;
        index < times.length;
        index++) {
      final time =
          times[index];

      if (time == null) {
        continue;
      }

      final difference =
          time
              .difference(
                now,
              )
              .abs();

      if (difference <
          nearestDifference) {
        nearestDifference =
            difference;

        nearestIndex =
            index;
      }
    }

    double sumRain(
      DateTime start,
      DateTime end,
    ) {
      var total = 0.0;

      for (var index = 0;
          index < times.length &&
              index < rain.length;
          index++) {
        final time =
            times[index];

        if (time == null) {
          continue;
        }

        if (!time.isBefore(
              start,
            ) &&
            !time.isAfter(
              end,
            )) {
          total +=
              rain[index];
        }
      }

      return total;
    }

    final rainLast24h =
        sumRain(
      now.subtract(
        const Duration(
          hours: 24,
        ),
      ),
      now,
    );

    final rainNext12h =
        sumRain(
      now,
      now.add(
        const Duration(
          hours: 12,
        ),
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
        _double(
      data['elevation'],
    );

    final rainSignal =
        ((rainLast24h +
                    rainNext12h) /
                80)
            .clamp(
      0.0,
      1.0,
    );

    final soilSignal =
        ((soilMoisture -
                    0.15) /
                0.35)
            .clamp(
      0.0,
      1.0,
    );

    final windSignal =
        (windSpeed / 70)
            .clamp(
      0.0,
      1.0,
    );

    final elevationSignal =
        (elevation / 3000)
            .clamp(
      0.0,
      1.0,
    );

    final landslideRisk =
        (rainSignal * 45 +
                soilSignal * 30 +
                elevationSignal *
                    20 +
                windSignal * 5)
            .round()
            .clamp(
              0,
              100,
            );

    final floodRisk =
        (rainSignal * 70 +
                soilSignal * 20 +
                math.min(
                      1.0,
                      rainNext12h /
                          40,
                    ) *
                    10)
            .round()
            .clamp(
              0,
              100,
            );

    final overallRisk =
        math
            .max(
              landslideRisk,
              floodRisk,
            )
            .clamp(
              0,
              100,
            );

    return RiskSnapshot(
      temperature:
          temperature,
      windSpeed:
          windSpeed,
      rainLast24h:
          rainLast24h,
      rainNext12h:
          rainNext12h,
      soilMoisture:
          soilMoisture,
      elevation:
          elevation,
      landslideRisk:
          landslideRisk,
      floodRisk:
          floodRisk,
      overallRisk:
          overallRisk,
    );
  }

  static List<double> _list(
    List? values,
  ) {
    if (values == null) {
      return const [];
    }

    return values
        .map(
          _double,
        )
        .toList();
  }

  static double _double(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ??
              '',
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

    if (index >=
        values.length) {
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
  State<DashboardPage>
      createState() =>
          _DashboardPageState();
}

class _DashboardPageState
    extends State<DashboardPage> {
  static const LatLng
      uttarakhandCenter =
      LatLng(
    30.0668,
    79.0193,
  );
    static const int
      criticalRisk = 70;

  final MapController
      _mapController =
      MapController();

  mbx.MapboxMap? _mapboxMap;

  mbx.CircleAnnotationManager?
      _circleAnnotationManager;

  HimRakshakMapMode _mapMode =
      HimRakshakMapMode.hybrid;

  OfficialDataBundle? _officialData;

  final TextEditingController
      _searchController =
      TextEditingController();

  LatLng? _userPosition;

  LatLng? _selectedPosition;

  PlaceInfo? _selectedPlace;

  RiskSnapshot? _snapshot;

  bool _loading = true;

  bool _searching = false;

  String? _error;

  Timer? _timer;

  String? _lastAlertKey;

  DateTime? _lastAlertTime;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) async {
        await NotificationService
            .instance
            .requestPermission();

        await _loadCurrentLocation();
      },
    );

    _timer =
        Timer.periodic(
      const Duration(
        minutes: 15,
      ),
      (_) {
        final place =
            _selectedPlace;

        if (place != null) {
          _refreshRisk(
            place,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();

    _searchController
        .dispose();

    _mapController
        .dispose();

    super.dispose();
  }

  Future<void>
      _loadCurrentLocation() async {
    setState(
      () {
        _loading = true;
        _error = null;
      },
    );

    try {
      final enabled =
          await Geolocator
              .isLocationServiceEnabled();

      if (!enabled) {
        if (!mounted) {
          return;
        }

        setState(
          () {
            _loading = false;
            _error =
                'Please turn on GPS/location services.';
          },
        );

        _showUttarakhand();

        return;
      }

      var permission =
          await Geolocator
              .checkPermission();

      if (permission ==
          LocationPermission
              .denied) {
        permission =
            await Geolocator
                .requestPermission();
      }

      if (permission ==
          LocationPermission
              .denied) {
        if (!mounted) {
          return;
        }

        setState(
          () {
            _loading = false;
            _error =
                'Location permission denied.';
          },
        );

        return;
      }

      if (permission ==
          LocationPermission
              .deniedForever) {
        if (!mounted) {
          return;
        }

        setState(
          () {
            _loading = false;
            _error =
                'Location permission permanently denied.';
          },
        );

        return;
      }

      final position =
          await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final point =
          LatLng(
        position.latitude,
        position.longitude,
      );

      if (!mounted) {
        return;
      }

      setState(
        () {
          _userPosition =
              point;

          _selectedPosition =
              point;
        },
      );

      await _moveMap(
        point,
        14,
      );

      await _analysePoint(
        point,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(
        () {
          _loading = false;

          _error =
              'Unable to get current location: $error';
        },
      );
    }
  }

  Future<void> _analysePoint(
    LatLng point,
  ) async {
    setState(
      () {
        _loading = true;
        _error = null;
        _selectedPosition =
            point;
        _snapshot = null;
        _officialData = null;
      },
    );

    try {
      final place =
          await LocationApi
              .reverseGeocode(
        point.latitude,
        point.longitude,
      );

      if (!mounted) {
        return;
      }

      setState(
        () {
          _selectedPlace =
              place;
        },
      );

      final results =
          await Future.wait<dynamic>(
        [
          WeatherRiskService.fetch(
            place,
          ),
          OfficialDataService.fetch(
            place,
          ),
        ],
      );

      final snapshot =
          results[0] as RiskSnapshot;

      final official =
          results[1]
              as OfficialDataBundle;

      if (!mounted) {
        return;
      }

      setState(
        () {
          _snapshot = snapshot;
          _officialData = official;
          _loading = false;
        },
      );

      await _syncMapboxMarkers();

      await _criticalCheck(
        place,
        snapshot,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(
        () {
          _loading = false;

          _error =
              error.toString();
        },
      );
    }
  }

  Future<void> _refreshRisk(
    PlaceInfo place,
  ) async {
    try {
      final results =
          await Future.wait<dynamic>(
        [
          WeatherRiskService.fetch(
            place,
          ),
          OfficialDataService.fetch(
            place,
          ),
        ],
      );

      final snapshot =
          results[0] as RiskSnapshot;

      final official =
          results[1]
              as OfficialDataBundle;

      if (!mounted) {
        return;
      }

      setState(
        () {
          _snapshot = snapshot;
          _officialData = official;
        },
      );

      await _syncMapboxMarkers();

      await _criticalCheck(
        place,
        snapshot,
      );
    } catch (_) {}
  }

  Future<void> _criticalCheck(
    PlaceInfo place,
    RiskSnapshot snapshot,
  ) async {
    if (snapshot.overallRisk <
        criticalRisk) {
      return;
    }

    final now =
        DateTime.now();

    final key =
        '${place.latitude.toStringAsFixed(3)}:'
        '${place.longitude.toStringAsFixed(3)}';

    final duplicate =
        _lastAlertKey == key &&
            _lastAlertTime !=
                null &&
            now.difference(
                  _lastAlertTime!,
                ) <
                const Duration(
                  minutes: 30,
                );

    if (duplicate) {
      return;
    }

    _lastAlertKey = key;

    _lastAlertTime = now;

    await SystemSound.play(
      SystemSoundType.alert,
    );

    await HapticFeedback
        .heavyImpact();

    await NotificationService
        .instance
        .showCriticalAlert(
      place: place.name,
      risk:
          snapshot.overallRisk,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        duration:
            const Duration(
          seconds: 8,
        ),
        backgroundColor:
            Colors.red.shade800,
        content: Text(
          'CRITICAL: ${place.name} '
          'experimental risk '
          '${snapshot.overallRisk}/100. '
          'Follow official authority warnings.',
        ),
      ),
    );
  }

  Future<void>
      _searchPlace() async {
    final query =
        _searchController.text
            .trim();

    if (query.isEmpty ||
        _searching) {
      return;
    }

    FocusScope.of(
      context,
    ).unfocus();

    setState(
      () {
        _searching = true;
        _error = null;
      },
    );

    try {
      final results =
          await LocationApi
              .search(
        query,
      );

      if (!mounted) {
        return;
      }

      setState(
        () {
          _searching = false;
        },
      );

      if (results.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'No place found.',
            ),
          ),
        );

        return;
      }

      await _showResults(
        results,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(
        () {
          _searching = false;

          _error =
              'Search failed: $error';
        },
      );
    }
  }

  Future<void> _showResults(
    List<PlaceInfo> results,
  ) async {
    final selected =
        await showModalBottomSheet<
            PlaceInfo>(
      context: context,
      showDragHandle: true,
      builder: (
        context,
      ) {
        return SafeArea(
          child:
              ListView.separated(
            shrinkWrap: true,
            itemCount:
                results.length,
            separatorBuilder:
                (
              _,
              __,
            ) =>
                    const Divider(
              height: 1,
            ),
            itemBuilder:
                (
              context,
              index,
            ) {
              final place =
                  results[index];

              return ListTile(
                leading:
                    const Icon(
                  Icons.location_on,
                ),
                title:
                    Text(
                  place.name,
                ),
                subtitle:
                    Text(
                  place.subtitle
                          .isEmpty
                      ? '${place.latitude.toStringAsFixed(4)}, '
                          '${place.longitude.toStringAsFixed(4)}'
                      : place.subtitle,
                ),
                onTap:
                    () {
                  Navigator.pop(
                    context,
                    place,
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    _searchController.text =
        selected.name;

    final point =
        LatLng(
      selected.latitude,
      selected.longitude,
    );

    await _moveMap(
      point,
      13,
    );

    setState(
      () {
        _selectedPlace =
            selected;

        _selectedPosition =
            point;

        _loading = true;

        _snapshot = null;
        _officialData = null;
      },
    );

    try {
      final results =
          await Future.wait<dynamic>(
        [
          WeatherRiskService.fetch(
            selected,
          ),
          OfficialDataService.fetch(
            selected,
          ),
        ],
      );

      final snapshot =
          results[0] as RiskSnapshot;

      final official =
          results[1]
              as OfficialDataBundle;

      if (!mounted) {
        return;
      }

      setState(
        () {
          _snapshot = snapshot;
          _officialData = official;
          _loading = false;
        },
      );

      await _syncMapboxMarkers();

      await _criticalCheck(
        selected,
        snapshot,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(
        () {
          _loading = false;
          _error =
              error.toString();
        },
      );
    }
  }

  Future<void>
      _showUttarakhand() async {
    await _moveMap(
      uttarakhandCenter,
      7.3,
    );
  }

  Future<void> _moveMap(
    LatLng point,
    double zoom,
  ) async {
    if (mapboxAccessToken
            .trim()
            .isNotEmpty &&
        _mapboxMap != null) {
      await _mapboxMap!.setCamera(
        mbx.CameraOptions(
          center: mbx.Point(
            coordinates:
                mbx.Position(
              point.longitude,
              point.latitude,
            ),
          ),
          zoom: zoom,
          pitch:
              _mapMode ==
                      HimRakshakMapMode
                          .terrain
                  ? 55
                  : 0,
        ),
      );
    } else {
      _mapController.move(
        point,
        zoom,
      );
    }

    await _syncMapboxMarkers();
  }

  Future<void> _onMapboxCreated(
    mbx.MapboxMap map,
  ) async {
    _mapboxMap = map;

    _circleAnnotationManager =
        await map.annotations
            .createCircleAnnotationManager();

    await _syncMapboxMarkers();
  }

  Future<void>
      _syncMapboxMarkers() async {
    final manager =
        _circleAnnotationManager;

    if (manager == null) {
      return;
    }

    await manager.deleteAll();

    if (_userPosition != null) {
      await manager.create(
        mbx.CircleAnnotationOptions(
          geometry:
              mbx.Point(
            coordinates:
                mbx.Position(
              _userPosition!
                  .longitude,
              _userPosition!
                  .latitude,
            ),
          ),
          circleRadius: 9,
          circleColor:
              0xFF1976D2,
          circleStrokeColor:
              0xFFFFFFFF,
          circleStrokeWidth: 3,
        ),
      );
    }

    if (_selectedPosition !=
            null &&
        _selectedPosition !=
            _userPosition) {
      final risk =
          _snapshot?.overallRisk;

      final color =
          risk == null
              ? 0xFFFF9800
              : risk >=
                      criticalRisk
                  ? 0xFFD32F2F
                  : risk >= 40
                      ? 0xFFF57C00
                      : 0xFF2E7D32;

      await manager.create(
        mbx.CircleAnnotationOptions(
          geometry:
              mbx.Point(
            coordinates:
                mbx.Position(
              _selectedPosition!
                  .longitude,
              _selectedPosition!
                  .latitude,
            ),
          ),
          circleRadius: 9,
          circleColor: color,
          circleStrokeColor:
              0xFFFFFFFF,
          circleStrokeWidth: 3,
        ),
      );
    }
  }

  String _mapboxStyle() {
    switch (_mapMode) {
      case HimRakshakMapMode
          .satellite:
        return mbx
            .MapboxStyles
            .SATELLITE;

      case HimRakshakMapMode
          .hybrid:
        return mbx
            .MapboxStyles
            .STANDARD_SATELLITE;

      case HimRakshakMapMode
          .terrain:
        return mbx
            .MapboxStyles
            .STANDARD;
    }
  }

  Future<void> _changeMapMode(
    HimRakshakMapMode mode,
  ) async {
    setState(
      () {
        _mapMode = mode;
      },
    );

    final map =
        _mapboxMap;

    if (map != null) {
      await map.loadStyleURI(
        _mapboxStyle(),
      );

      final selected =
          _selectedPosition ??
              _userPosition ??
              uttarakhandCenter;

      await _moveMap(
        selected,
        mode ==
                HimRakshakMapMode
                    .terrain
            ? 11
            : 13,
      );
    }
  }

  Color _riskColor(
    int risk,
  ) {
    if (risk >=
        criticalRisk) {
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
    if (risk >=
        criticalRisk) {
      return 'Critical';
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
        title:
            const Text(
          'HimRakshak AI',
        ),
        actions: [
          IconButton(
            onPressed:
                _showUttarakhand,
            icon:
                const Icon(
              Icons.map_outlined,
            ),
          ),
          IconButton(
            onPressed:
                _loadCurrentLocation,
            icon:
                const Icon(
              Icons.my_location,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets
                      .all(
                10,
              ),
              child: TextField(
                controller:
                    _searchController,
                textInputAction:
                    TextInputAction
                        .search,
                onSubmitted:
                    (_) =>
                        _searchPlace(),
                decoration:
                    InputDecoration(
                  hintText:
                      'Search Kedarnath, Joshimath...',
                  prefixIcon:
                      const Icon(
                    Icons.search,
                  ),
                  suffixIcon:
                      _searching
                          ? const Padding(
                              padding:
                                  EdgeInsets.all(
                                12,
                              ),
                              child:
                                  SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed:
                                  _searchPlace,
                              icon:
                                  const Icon(
                                Icons
                                    .arrow_forward,
                              ),
                            ),
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius
                            .circular(
                      14,
                    ),
                  ),
                ),
              ),
            ),

            // =========================
            // MAP SECTION
            // =========================
            Expanded(
              flex: 6,
              child: Stack(
                children: [
                  if (mapboxAccessToken
                      .trim()
                      .isNotEmpty)
                    mbx.MapWidget(
                      key:
                          const ValueKey(
                        'himrakshak-mapbox',
                      ),
                      styleUri:
                          _mapboxStyle(),
                      cameraOptions:
                          mbx.CameraOptions(
                        center:
                            mbx.Point(
                          coordinates:
                              mbx.Position(
                            uttarakhandCenter
                                .longitude,
                            uttarakhandCenter
                                .latitude,
                          ),
                        ),
                        zoom: 7.3,
                        pitch:
                            _mapMode ==
                                    HimRakshakMapMode
                                        .terrain
                                ? 55
                                : 0,
                      ),
                      onMapCreated:
                          _onMapboxCreated,
                      onTapListener:
                          (gesture) {
                        final coordinates =
                            gesture
                                .point
                                .coordinates;

                        _analysePoint(
                          LatLng(
                            coordinates.lat
                                .toDouble(),
                            coordinates.lng
                                .toDouble(),
                          ),
                        );
                      },
                    )
                  else
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
                        onTap:
                            (
                          _,
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
                                  color:
                                      snapshot ==
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

                  // =========================
                  // MAP TYPE SELECTOR
                  // =========================
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Card(
                      child: Padding(
                        padding:
                            const EdgeInsets
                                .all(
                          6,
                        ),
                        child:
                            mapboxAccessToken
                                    .trim()
                                    .isNotEmpty
                                ? PopupMenuButton<
                                    HimRakshakMapMode>(
                                    tooltip:
                                        'Map style',
                                    initialValue:
                                        _mapMode,
                                    onSelected:
                                        _changeMapMode,
                                    itemBuilder:
                                        (context) =>
                                            const [
                                      PopupMenuItem(
                                        value:
                                            HimRakshakMapMode
                                                .satellite,
                                        child:
                                            Text(
                                          'Satellite',
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value:
                                            HimRakshakMapMode
                                                .hybrid,
                                        child:
                                            Text(
                                          'Hybrid',
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value:
                                            HimRakshakMapMode
                                                .terrain,
                                        child:
                                            Text(
                                          'Terrain / 3D',
                                        ),
                                      ),
                                    ],
                                    child:
                                        const Row(
                                      mainAxisSize:
                                          MainAxisSize
                                              .min,
                                      children: [
                                        Icon(
                                          Icons
                                              .layers_outlined,
                                        ),
                                        SizedBox(
                                          width: 6,
                                        ),
                                        Text(
                                          'Map',
                                        ),
                                      ],
                                    ),
                                  )
                                : const Padding(
                                    padding:
                                        EdgeInsets
                                            .symmetric(
                                      horizontal:
                                          6,
                                      vertical:
                                          4,
                                    ),
                                    child:
                                        Text(
                                      'OSM fallback',
                                      style:
                                          TextStyle(
                                        fontSize:
                                            11,
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                  ),

                  if (_loading)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child:
                          LinearProgressIndicator(),
                    ),
                ],
              ),
            ),

            // =========================
            // INFORMATION SECTION
            // =========================
            Expanded(
              flex: 5,
              child:
                  SingleChildScrollView(
                padding:
                    const EdgeInsets
                        .all(
                  14,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                  children: [
                    if (_error !=
                        null)
                      Card(
                        child:
                            Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            12,
                          ),
                          child:
                              Text(
                            _error!,
                            style:
                                const TextStyle(
                              color:
                                  Colors.red,
                            ),
                          ),
                        ),
                      ),

                    // =========================
                    // CRITICAL WARNING
                    // =========================
                    if (snapshot !=
                            null &&
                        snapshot
                                .overallRisk >=
                            criticalRisk)
                      Card(
                        color:
                            Colors.red
                                .shade50,
                        child:
                            Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            12,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons
                                    .warning_amber_rounded,
                                color:
                                    Colors.red,
                                size: 32,
                              ),
                              const SizedBox(
                                width: 10,
                              ),
                              Expanded(
                                child:
                                    Text(
                                  'CRITICAL EXPERIMENTAL INDICATOR: '
                                  '${snapshot.overallRisk}/100',
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.red,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    Text(
                      _selectedPlace
                              ?.name ??
                          'Tap or search a location',
                      style:
                          Theme.of(
                        context,
                      )
                              .textTheme
                              .titleLarge,
                    ),

                    if ((_selectedPlace
                                ?.subtitle ??
                            '')
                        .isNotEmpty)
                      Text(
                        _selectedPlace!
                            .subtitle,
                      ),

                    const SizedBox(
                      height: 12,
                    ),

                    // =========================
                    // OFFICIAL OBSERVATION
                    // =========================
                    if (_officialData !=
                        null) ...[
                      Card(
                        child:
                            Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            14,
                          ),
                          child:
                              Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons
                                        .verified_outlined,
                                  ),
                                  SizedBox(
                                    width: 8,
                                  ),
                                  Text(
                                    'Official / Observed Data',
                                    style:
                                        TextStyle(
                                      fontWeight:
                                          FontWeight
                                              .bold,
                                      fontSize:
                                          16,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(
                                height: 10,
                              ),

                              if (_officialData!
                                      .observation !=
                                  null) ...[
                                Text(
                                  _officialData!
                                      .observation!
                                      .source,
                                  style:
                                      const TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),

                                const SizedBox(
                                  height: 4,
                                ),

                                Text(
                                  'Station: '
                                  '${_officialData!.observation!.station}',
                                ),

                                if (_officialData!
                                        .observation!
                                        .observedAt !=
                                    null)
                                  Text(
                                    'Observed: '
                                    '${_formatTime(_officialData!.observation!.observedAt!)}',
                                  ),

                                const SizedBox(
                                  height: 10,
                                ),

                                Row(
                                  children: [
                                    Expanded(
                                      child:
                                          _metric(
                                        'Temperature',
                                        _formatMetric(
                                          _officialData!
                                              .observation!
                                              .temperature,
                                          '°C',
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child:
                                          _metric(
                                        'Humidity',
                                        _formatMetric(
                                          _officialData!
                                              .observation!
                                              .humidity,
                                          '%',
                                        ),
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
                                        'Wind',
                                        _formatMetric(
                                          _officialData!
                                              .observation!
                                              .windSpeed,
                                          'km/h',
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child:
                                          _metric(
                                        'Rain 24h',
                                        _formatMetric(
                                          _officialData!
                                              .observation!
                                              .rainfall24h,
                                          'mm',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else
                                Text(
                                  _officialData!
                                      .observationStatus,
                                  style:
                                      const TextStyle(
                                    fontSize:
                                        12,
                                  ),
                                ),

                              const SizedBox(
                                height: 8,
                              ),

                              Text(
                                'Fetched: '
                                '${_formatTime(_officialData!.fetchedAt)}',
                                style:
                                    const TextStyle(
                                  fontSize:
                                      11,
                                  color:
                                      Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // =========================
                      // NDMA SACHET ALERTS
                      // =========================
                      Card(
                        child:
                            Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            14,
                          ),
                          child:
                              Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons
                                        .warning_amber_rounded,
                                  ),
                                  SizedBox(
                                    width: 8,
                                  ),
                                  Expanded(
                                    child:
                                        Text(
                                      'Official Alerts — NDMA SACHET',
                                      style:
                                          TextStyle(
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                        fontSize:
                                            16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(
                                height: 8,
                              ),

                              if (_officialData!
                                  .alerts
                                  .isEmpty)
                                const Text(
                                  'No matching live SACHET alert was found '
                                  'for this place/district in the current feed.',
                                  style:
                                      TextStyle(
                                    fontSize:
                                        12,
                                  ),
                                )
                              else
                                ..._officialData!
                                    .alerts
                                    .map(
                                  (
                                    alert,
                                  ) =>
                                      Padding(
                                    padding:
                                        const EdgeInsets
                                            .only(
                                      bottom:
                                          10,
                                    ),
                                    child:
                                        Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [
                                        Text(
                                          '${alert.severity}: '
                                          '${alert.title}',
                                          style:
                                              const TextStyle(
                                            fontWeight:
                                                FontWeight
                                                    .bold,
                                          ),
                                        ),

                                        if (alert
                                            .description
                                            .isNotEmpty)
                                          Text(
                                            alert
                                                .description,
                                            maxLines:
                                                4,
                                            overflow:
                                                TextOverflow
                                                    .ellipsis,
                                          ),

                                        if (alert
                                                .issuedAt !=
                                            null)
                                          Text(
                                            'Issued: '
                                            '${_formatTime(alert.issuedAt!)}',
                                            style:
                                                const TextStyle(
                                              fontSize:
                                                  11,
                                              color:
                                                  Colors
                                                      .grey,
                                            ),
                                          ),

                                        Text(
                                          'Source: '
                                          '${alert.source}',
                                          style:
                                              const TextStyle(
                                            fontSize:
                                                11,
                                            color:
                                                Colors
                                                    .grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                                          if (snapshot !=
                        null) ...[
                      Card(
                        child:
                            Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            14,
                          ),
                          child:
                              Column(
                            children: [
                              Text(
                                '${snapshot.overallRisk}/100',
                                style:
                                    TextStyle(
                                  fontSize:
                                      34,
                                  fontWeight:
                                      FontWeight.bold,
                                  color:
                                      _riskColor(
                                    snapshot
                                        .overallRisk,
                                  ),
                                ),
                              ),
                              Text(
                                '${_riskLabel(snapshot.overallRisk)} '
                                'experimental risk indicator',
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

                      // =========================
                      // ENVIRONMENTAL INPUTS
                      // =========================
                      Card(
                        child:
                            Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            14,
                          ),
                          child:
                              Column(
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

                      // =========================
                      // EXPLAINABLE RISK
                      // =========================
                      Card(
                        child:
                            Padding(
                          padding:
                              const EdgeInsets
                                  .all(
                            14,
                          ),
                          child:
                              Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              const Text(
                                'Why is this score high?',
                                style:
                                    TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                  fontSize:
                                      16,
                                ),
                              ),

                              const SizedBox(
                                height: 6,
                              ),

                              Text(
                                _riskReason(
                                  snapshot,
                                ),
                              ),

                              const SizedBox(
                                height: 8,
                              ),

                              const Text(
                                'Experimental inputs: Open-Meteo '
                                'weather/model data + elevation. '
                                'Weights: landslide = rain 45%, '
                                'soil moisture 30%, elevation 20%, '
                                'wind 5%; flood = rain 70%, '
                                'soil moisture 20%, next-12h rain 10%.',
                                style:
                                    TextStyle(
                                  fontSize:
                                      12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 6,
                      ),

                      // =========================
                      // SAFETY DISCLAIMER
                      // =========================
                      const Text(
                        'Experimental decision-support only. '
                        'The 0–100 HimRakshak score is not an '
                        'official probability. '
                        'Official observations and alerts are '
                        'displayed separately above. '
                        'Always follow authorized agency alerts.',
                        style:
                            TextStyle(
                          fontSize: 12,
                          fontStyle:
                              FontStyle
                                  .italic,
                        ),
                      ),

                      const SizedBox(
                        height: 16,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(
    DateTime value,
  ) {
    final local =
        value.toLocal();

    String two(
      int number,
    ) =>
        number
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '${two(local.day)}/'
        '${two(local.month)}/'
        '${local.year} '
        '${two(local.hour)}:'
        '${two(local.minute)}';
  }

  String _formatMetric(
    double? value,
    String unit,
  ) {
    if (value == null) {
      return 'N/A';
    }

    return '${value.toStringAsFixed(1)} $unit';
  }

  String _riskReason(
    RiskSnapshot snapshot,
  ) {
    final reasons =
        <String>[];

    if (snapshot.rainLast24h +
            snapshot.rainNext12h >=
        40) {
      reasons.add(
        'high recent/forecast rainfall',
      );
    }

    if (snapshot.soilMoisture >=
        0.30) {
      reasons.add(
        'wet near-surface soil',
      );
    }

    if (snapshot.elevation >=
        1800) {
      reasons.add(
        'mountain/elevation exposure',
      );
    }

    if (snapshot.windSpeed >=
        40) {
      reasons.add(
        'strong wind',
      );
    }

    if (reasons.isEmpty) {
      return 'No single strong driver is dominating; '
          'the score comes from the weighted '
          'combination of current inputs.';
    }

    return 'Main drivers: '
        '${reasons.join(', ')}.';
  }

  Widget _metric(
    String label,
    String value,
  ) {
    return Column(
      children: [
        Text(
          value,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style:
              const TextStyle(
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
