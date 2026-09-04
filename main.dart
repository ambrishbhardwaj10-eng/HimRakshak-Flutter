import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(const HimRakshakApp());

class HimRakshakApp extends StatelessWidget {
  const HimRakshakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HimRakshak AI',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal, brightness: Brightness.light),
      home: const DashboardPage(),
    );
  }
}

class MonitoredPlace {
  final String name;
  final String district;
  final double lat;
  final double lon;
  const MonitoredPlace(this.name, this.district, this.lat, this.lon);
}

class RiskSnapshot {
  final MonitoredPlace place;
  final double rain24;
  final double rain72;
  final double forecast12;
  final double soilMoisture;
  final double wind;
  final double temperature;
  final int landslide;
  final int flood;
  final int overall;
  final DateTime fetchedAt;

  RiskSnapshot({required this.place, required this.rain24, required this.rain72, required this.forecast12, required this.soilMoisture, required this.wind, required this.temperature, required this.landslide, required this.flood, required this.overall, required this.fetchedAt});

  String get level => overall >= 80 ? 'CRITICAL' : overall >= 60 ? 'HIGH' : overall >= 35 ? 'MODERATE' : 'LOW';
}

class LiveDataService {
  static Future<RiskSnapshot> fetch(MonitoredPlace p) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${p.lat}&longitude=${p.lon}'
      '&hourly=precipitation,soil_moisture_0_to_1cm,wind_speed_10m,temperature_2m'
      '&past_days=3&forecast_days=2&timezone=Asia%2FKolkata',
    );
    final r = await http.get(uri).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('Weather service returned ${r.statusCode}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final hourly = j['hourly'] as Map<String, dynamic>;
    final times = (hourly['time'] as List).map((e) => DateTime.parse(e.toString())).toList();
    final rain = (hourly['precipitation'] as List).map((e) => (e as num?)?.toDouble() ?? 0).toList();
    final soil = (hourly['soil_moisture_0_to_1cm'] as List).map((e) => (e as num?)?.toDouble() ?? 0).toList();
    final wind = (hourly['wind_speed_10m'] as List).map((e) => (e as num?)?.toDouble() ?? 0).toList();
    final temp = (hourly['temperature_2m'] as List).map((e) => (e as num?)?.toDouble() ?? 0).toList();
    final now = DateTime.now();
    double sumBetween(Duration startAgo, Duration endAhead) {
      double s = 0;
      for (var i = 0; i < times.length; i++) {
        final t = times[i];
        if (t.isAfter(now.subtract(startAgo)) && t.isBefore(now.add(endAhead))) s += rain[i];
      }
      return s;
    }
    final rain24 = sumBetween(const Duration(hours: 24), Duration.zero);
    final rain72 = sumBetween(const Duration(hours: 72), Duration.zero);
    final forecast12 = sumBetween(Duration.zero, const Duration(hours: 12));
    int nearest = 0;
    var best = const Duration(days: 3650);
    for (var i = 0; i < times.length; i++) {
      final d = times[i].difference(now).abs();
      if (d < best) { best = d; nearest = i; }
    }
    final soilNow = soil[nearest];
    final windNow = wind[nearest];
    final tempNow = temp[nearest];

    // Transparent MVP heuristic. Must be replaced/validated before official emergency use.
    final terrainPrior = switch (p.district) {
      'Chamoli' => 18.0,
      'Rudraprayag' => 20.0,
      'Uttarkashi' => 19.0,
      'Pithoragarh' => 17.0,
      'Bageshwar' => 15.0,
      _ => 12.0,
    };
    final rainScore = math.min(45.0, rain24 * 0.32 + rain72 * 0.08 + forecast12 * 0.18);
    final soilScore = math.min(25.0, soilNow * 100 * 0.25);
    final windScore = math.min(8.0, windNow * 0.12);
    final landslide = (terrainPrior + rainScore + soilScore + windScore).clamp(0, 100).round();
    final flood = (rain24 * 0.42 + rain72 * 0.10 + forecast12 * 0.30 + soilNow * 20).clamp(0, 100).round();
    final overall = math.max(landslide, flood);
    return RiskSnapshot(place: p, rain24: rain24, rain72: rain72, forecast12: forecast12, soilMoisture: soilNow, wind: windNow, temperature: tempNow, landslide: landslide, flood: flood, overall: overall, fetchedAt: DateTime.now());
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const places = [
    MonitoredPlace('Joshimath', 'Chamoli', 30.555, 79.565),
    MonitoredPlace('Rudraprayag', 'Rudraprayag', 30.285, 78.981),
    MonitoredPlace('Uttarkashi', 'Uttarkashi', 30.7268, 78.4354),
    MonitoredPlace('Pithoragarh', 'Pithoragarh', 29.5829, 80.2182),
    MonitoredPlace('Bageshwar', 'Bageshwar', 29.8374, 79.7716),
  ];
  final Map<String, RiskSnapshot> data = {};
  bool loading = true;
  String? error;
  Timer? timer;
  MonitoredPlace selected = places.first;

  @override void initState() { super.initState(); _refresh(); timer = Timer.periodic(const Duration(minutes: 15), (_) => _refresh()); }
  @override void dispose() { timer?.cancel(); super.dispose(); }

  Future<void> _refresh() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final res = await Future.wait(places.map(LiveDataService.fetch));
      if (!mounted) return;
      setState(() { data..clear()..addEntries(res.map((e) => MapEntry(e.place.name, e))); loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e.toString(); loading = false; });
    }
  }

  Color riskColor(int score) => score >= 80 ? Colors.red.shade700 : score >= 60 ? Colors.deepOrange : score >= 35 ? Colors.amber.shade800 : Colors.green.shade700;

  @override Widget build(BuildContext context) {
    final snap = data[selected.name];
    return Scaffold(
      appBar: AppBar(title: const Text('HimRakshak AI'), actions: [IconButton(onPressed: loading ? null : _refresh, icon: const Icon(Icons.refresh))]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Live Mountain Hazard Intelligence', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Near-live environmental inputs • Decision-support only', style: TextStyle(color: Colors.grey.shade700)),
            if (loading) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
          ])),
          SizedBox(height: 310, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: FlutterMap(
            options: MapOptions(initialCenter: const LatLng(30.2, 79.3), initialZoom: 7.1),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'in.himrakshak.live'),
              MarkerLayer(markers: places.map((p) {
                final s = data[p.name];
                return Marker(point: LatLng(p.lat, p.lon), width: 48, height: 48, child: GestureDetector(onTap: () => setState(() => selected = p), child: Icon(Icons.location_on, size: 42, color: riskColor(s?.overall ?? 0))));
              }).toList()),
              RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
            ],
          ))),
          const SizedBox(height: 10),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: places.map((p) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(p.name), selected: selected.name == p.name, onSelected: (_) => setState(() => selected = p)))).toList())),
          const SizedBox(height: 10),
          if (snap != null) ...[
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text('${snap.place.name}, ${snap.place.district}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), Chip(label: Text(snap.level), backgroundColor: riskColor(snap.overall).withAlpha(35), side: BorderSide(color: riskColor(snap.overall)))]),
              Text('Overall risk ${snap.overall}/100', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: riskColor(snap.overall))),
              const SizedBox(height: 8), LinearProgressIndicator(value: snap.overall / 100, minHeight: 9, borderRadius: BorderRadius.circular(20)),
              const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: [
                _metric('Landslide', '${snap.landslide}%'), _metric('Flash flood', '${snap.flood}%'), _metric('Rain 24h', '${snap.rain24.toStringAsFixed(1)} mm'), _metric('Rain 72h', '${snap.rain72.toStringAsFixed(1)} mm'), _metric('Next 12h', '${snap.forecast12.toStringAsFixed(1)} mm'), _metric('Soil moisture', snap.soilMoisture.toStringAsFixed(2)), _metric('Temp', '${snap.temperature.toStringAsFixed(1)} °C'), _metric('Wind', '${snap.wind.toStringAsFixed(1)} km/h'),
              ]),
              const SizedBox(height: 12), Text('Updated ${DateFormat('dd MMM yyyy, hh:mm a').format(snap.fetchedAt)}'),
            ]))),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Why this risk?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('• 24-hour rainfall: ${snap.rain24.toStringAsFixed(1)} mm\n• 72-hour accumulated rainfall: ${snap.rain72.toStringAsFixed(1)} mm\n• Next 12-hour forecast: ${snap.forecast12.toStringAsFixed(1)} mm\n• Near-surface soil moisture: ${snap.soilMoisture.toStringAsFixed(2)}\n• District terrain susceptibility prior included in MVP model.'),
            ]))),
          ],
          Card(color: Colors.amber.shade50, child: const Padding(padding: EdgeInsets.all(14), child: Text('Safety notice: HimRakshak AI is an experimental decision-support app. Do not use it as the sole source for evacuation or emergency decisions. Follow official government and disaster-management advisories.'))),
        ]),
      ),
    );
  }

  Widget _metric(String label, String value) => Container(width: 150, padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.grey.shade700)), const SizedBox(height: 4), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))]));
}
