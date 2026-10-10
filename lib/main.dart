import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const RoadprintApp());

const bg = Color(0xFF080D16);
const panel = Color(0xFF142033);
const blue = Color(0xFF60A5FA);
const muted = Color(0xFF94A3B8);

class Trip {
  final String id, title, state, note, date;
  final double miles;
  final List<LatLng> points;
  Trip({required this.id, required this.title, required this.state,
    required this.note, required this.date, required this.miles, this.points = const []});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'state': state,
    'note': note, 'date': date, 'miles': miles,
    'points': points.map((p) => [p.latitude, p.longitude]).toList()};
  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
    id: '${j['id']}', title: '${j['title'] ?? 'Drive'}', state: '${j['state'] ?? ''}',
    note: '${j['note'] ?? ''}', date: '${j['date'] ?? ''}',
    miles: (j['miles'] as num).toDouble(),
    points: ((j['points'] as List?) ?? []).map((p) => LatLng(
      (p[0] as num).toDouble(), (p[1] as num).toDouble())).toList());
}

class RoadprintApp extends StatelessWidget {
  const RoadprintApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ROADPRINT',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: ThemeData(
      platform: TargetPlatform.iOS,
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4D93F7)),
    ),
    darkTheme: ThemeData(
      platform: TargetPlatform.iOS,
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B1424),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4D93F7), brightness: Brightness.dark),
    ),
    home: const MainScreen(),
  );
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int tab = 0; // Map first
  List<Trip> trips = [];
  bool recording = false;
  List<LatLng> livePoints = [];
  StreamSubscription<Position>? locationSub;
  String locationMessage = '';
  double liveMiles = 0;
  final distance = const Distance();

  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(prefs.getString('roadprint_trips_v1') ?? '[]') as List;
      if (mounted) setState(() => trips = saved.map((x) => Trip.fromJson(Map<String, dynamic>.from(x))).toList());
    } catch (_) { if (mounted) snack('Could not read saved trips'); }
  }
  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('roadprint_trips_v1', jsonEncode(trips.map((t) => t.toJson()).toList()));
  }
  void snack(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  double get totalMiles => trips.fold(0, (double a, t) => a + t.miles);
  int get states => trips.map((t) => t.state.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet().length;
  String get today => DateTime.now().toLocal().toIso8601String().split('T').first;

  Future<void> addTrip({double? recordedMiles, List<LatLng>? recordedPoints}) async {
    final title = TextEditingController(text: recordedMiles == null ? '' : 'Recorded drive');
    final state = TextEditingController();
    final miles = TextEditingController(text: recordedMiles?.toStringAsFixed(1) ?? '');
    final note = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface, title: const Text('Save a drive'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Trip name')),
        const SizedBox(height: 10),
        TextField(controller: state, decoration: const InputDecoration(labelText: 'State (e.g. Connecticut)')),
        const SizedBox(height: 10),
        TextField(controller: miles, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Miles')),
        const SizedBox(height: 10),
        TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Memory / notes')),
      ])), actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ));
    if (result == true) {
      final n = double.tryParse(miles.text.trim());
      if (n == null || !n.isFinite || n < 0) { snack('Enter a valid nonnegative mileage'); }
      else {
        setState(() => trips.insert(0, Trip(id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title.text.trim().isEmpty ? 'Untitled drive' : title.text.trim(),
          state: state.text.trim(), note: note.text.trim(), date: today,
          miles: n, points: recordedPoints ?? [])));
        await persist();
        snack('Drive saved');
      }
    }
    title.dispose(); state.dispose(); miles.dispose(); note.dispose();
  }
  Future<void> deleteTrip(Trip t) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete this trip?'), content: Text(t.title), actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ]));
    if (yes == true) { setState(() => trips.removeWhere((x) => x.id == t.id)); await persist(); }
  }

  Future<void> startRecording() async {
    if (recording) return;
    if (!await Geolocator.isLocationServiceEnabled()) { snack('Enable location services first'); return; }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      snack('Location permission is required'); return;
    }
    setState(() { recording = true; livePoints = []; liveMiles = 0; locationMessage = 'Waiting for GPS…'; });
    try {
      locationSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, distanceFilter: 15)).listen((pos) {
        if (!mounted || !recording || pos.accuracy > 80) return;
        final next = LatLng(pos.latitude, pos.longitude);
        setState(() {
          if (livePoints.isNotEmpty) {
            final meters = distance.as(LengthUnit.Meter, livePoints.last, next);
            if (meters < 10 || meters > 1000) return;
            liveMiles += meters / 1609.344;
          }
          livePoints.add(next);
          locationMessage = '${livePoints.length} GPS points';
        });
      }, onError: (Object e) { if (mounted) snack('GPS error: $e'); });
    } catch (e) { setState(() => recording = false); snack('Could not start GPS: $e'); }
  }
  Future<void> stopRecording() async {
    await locationSub?.cancel(); locationSub = null;
    final points = List<LatLng>.from(livePoints);
    final miles = liveMiles;
    setState(() { recording = false; locationMessage = ''; });
    if (points.isNotEmpty) await addTrip(recordedMiles: miles, recordedPoints: points);
    else snack('No GPS points captured. Nothing saved.');
  }
  @override void dispose() { locationSub?.cancel(); super.dispose(); }

  bool get dark => Theme.of(context).brightness == Brightness.dark;
  Color get background => dark ? const Color(0xFF0B1424) : const Color(0xFFF8FAFC);
  Color get surface => dark ? const Color(0xFF17283F) : Colors.white;
  Color get foreground => dark ? Colors.white : const Color(0xFF0B1424);
  Color get secondary => dark ? const Color(0xFF98989F) : const Color(0xFF6E6E73);
  Color get accent => dark ? const Color(0xFF4D93F7) : const Color(0xFF4D93F7);

  TextStyle get largeTitle => TextStyle(fontSize: 34, letterSpacing: -1.2, fontWeight: FontWeight.w700, color: foreground);
  Widget sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 30, 2, 12),
    child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: secondary)));
  Widget panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(20)}) => Container(
    width: double.infinity, padding: padding,
    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20)), child: child);
  Widget pageHeading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: largeTitle), const SizedBox(height: 6),
      Text(subtitle, style: TextStyle(color: secondary, fontSize: 14)),
    ]));
  Widget metric(String label, String value) => Expanded(child: panel(Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: foreground)),
      const SizedBox(height: 6), Text(label, style: TextStyle(fontSize: 11, color: secondary)),
    ]), padding: const EdgeInsets.all(16)));
  Widget primaryButton(String title, IconData icon, VoidCallback onPressed, {bool destructive = false}) =>
    SizedBox(width: double.infinity, child: CupertinoButton(
      color: destructive ? const Color(0xFFFF453A) : accent,
      borderRadius: BorderRadius.circular(15), padding: const EdgeInsets.symmetric(vertical: 16),
      onPressed: onPressed,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 20, color: Colors.white), const SizedBox(width: 9),
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ])));

  Widget home() => ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 32), children: [
    pageHeading('Your roads. Your story.', 'A lifetime of drives, all in one place.'),
    panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('TOTAL DISTANCE', style: TextStyle(color: secondary, fontSize: 11, letterSpacing: 1.4)),
      const SizedBox(height: 12), Text('${totalMiles.toStringAsFixed(1)} mi',
        style: TextStyle(fontSize: 43, letterSpacing: -2, color: foreground, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6), Text('${trips.length} drives saved', style: TextStyle(color: secondary)),
    ])),
    const SizedBox(height: 12),
    Row(children: [metric('STATES LOGGED', '$states'), const SizedBox(width: 12), metric('TRIPS', '${trips.length}')]),
    sectionTitle('Your next drive'),
    primaryButton('Record a drive', Icons.my_location, recording ? stopRecording : startRecording,
      destructive: recording),
    if (recording) Padding(padding: const EdgeInsets.all(12), child: Text(
      'Recording: ${liveMiles.toStringAsFixed(2)} mi · $locationMessage', style: TextStyle(color: accent))),
    const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: CupertinoButton(
      color: surface, borderRadius: BorderRadius.circular(15),
      onPressed: () => addTrip(), child: Text('Log a drive manually', style: TextStyle(color: accent)))),
    const SizedBox(height: 18),
    Text('GPS recording currently works only while the app is active. Never interact with the app while driving.',
      style: TextStyle(color: secondary, fontSize: 12, height: 1.5)),
  ]);

  Widget map() {
    final lines = trips.where((t) => t.points.length > 1).map((t) => Polyline(
      points: t.points, strokeWidth: 4, color: accent)).toList();
    if (livePoints.length > 1) lines.add(Polyline(points: livePoints, strokeWidth: 5, color: const Color(0xFFFF9F0A)));
    return Stack(children: [
      FlutterMap(options: const MapOptions(initialCenter: LatLng(41.6, -72.7), initialZoom: 8), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.roadprint.app'),
        PolylineLayer(polylines: lines),
        const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
      ]),
      Positioned(top: 16, left: 16, right: 16, child: panel(Row(children: [
        Icon(Icons.map, color: accent), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Explore', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: foreground)),
          Text('${lines.length} mapped routes', style: TextStyle(color: secondary, fontSize: 12)),
        ])),
        CupertinoButton(padding: EdgeInsets.zero, onPressed: () => addTrip(),
          child: Icon(Icons.add_circle, color: accent, size: 29)),
      ]), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8))),
      Positioned(bottom: 22, left: 16, right: 16, child: panel(Text(
        'Saved GPS routes appear in blue. Map tiles require internet.',
        style: TextStyle(color: secondary, fontSize: 12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12))),
    ]);
  }

  Widget tripList({bool memoriesOnly = false}) {
    final list = memoriesOnly ? trips.where((t) => t.note.trim().isNotEmpty).toList() : trips;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 32), children: [
      pageHeading(memoriesOnly ? 'Memories' : 'Your trips',
        memoriesOnly ? 'The roads you never forget.' : 'Every journey has a story.'),
      if (!memoriesOnly) Padding(padding: const EdgeInsets.only(bottom: 18),
        child: primaryButton('Add a trip', Icons.add, () => addTrip())),
      if (list.isEmpty) panel(Text(memoriesOnly ? 'Add a note to a trip to save a memory here.' : 'Your first drive is waiting.',
        style: TextStyle(color: secondary))),
      ...list.map((t) => Padding(padding: const EdgeInsets.only(bottom: 12), child: panel(Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(t.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: foreground))),
            CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(32, 32),
              onPressed: () => deleteTrip(t), child: const Icon(Icons.delete_outline, color: Color(0xFFFF453A), size: 19))]),
          Text('${t.date} · ${t.miles.toStringAsFixed(1)} mi${t.state.isEmpty ? '' : ' · ${t.state}'}',
            style: TextStyle(color: accent, fontSize: 13)),
          if (t.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(t.note, style: TextStyle(color: foreground))),
          if (t.points.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
            child: Text('${t.points.length} recorded GPS points', style: TextStyle(color: secondary, fontSize: 12))),
        ])))),
    ]);
  }

  Widget stats() {
    final longest = trips.isEmpty ? 0.0 : trips.map((t) => t.miles).reduce((a, b) => a > b ? a : b);
    final byState = <String, double>{};
    for (final t in trips) {
      if (t.state.trim().isNotEmpty) byState.update(t.state.trim(), (v) => v + t.miles, ifAbsent: () => t.miles);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 32), children: [
      pageHeading('By the numbers.', 'Your driving history at a glance.'),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TOTAL MILES LOGGED', style: TextStyle(color: secondary, fontSize: 11, letterSpacing: 1.2)),
        const SizedBox(height: 10), Text(totalMiles.toStringAsFixed(1),
          style: TextStyle(color: foreground, fontSize: 45, fontWeight: FontWeight.w700)),
        Text('miles', style: TextStyle(color: secondary)),
      ])),
      const SizedBox(height: 12),
      Row(children: [metric('TRIPS', '${trips.length}'), const SizedBox(width: 12), metric('STATES', '$states')]),
      const SizedBox(height: 12),
      Row(children: [metric('AVERAGE MI', (trips.isEmpty ? 0 : totalMiles / trips.length).toStringAsFixed(1)),
        const SizedBox(width: 12), metric('LONGEST MI', longest.toStringAsFixed(1))]),
      sectionTitle('Mileage by state'),
      if (byState.isEmpty) panel(Text('Log a trip with a state to see your breakdown.', style: TextStyle(color: secondary))),
      ...byState.entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 12), child: panel(Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(e.key, style: TextStyle(color: foreground)),
            Text('${e.value.toStringAsFixed(1)} mi', style: TextStyle(color: accent))]),
          const SizedBox(height: 12), ClipRRect(borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(value: totalMiles == 0 ? 0 : e.value / totalMiles,
              backgroundColor: dark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
              color: accent, minHeight: 6)),
        ])))),
      const SizedBox(height: 12), Text('Bars show the share of logged mileage, not the percentage of roads completed.',
        style: TextStyle(color: secondary, fontSize: 12)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [map(), home(), tripList(), stats(), tripList(memoriesOnly: true)];
    return Scaffold(
      backgroundColor: background,
      appBar: CupertinoNavigationBar(
        backgroundColor: surface.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: dark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6), width: 0.4)),
        middle: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ROADPRINT', style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 3)),
          Text('NAVIGATE · EXPLORE · CONNECT', style: TextStyle(color: accent, fontSize: 8, letterSpacing: 1.8)),
        ]),
      ),
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: CupertinoTabBar(
        backgroundColor: surface,
        activeColor: accent,
        inactiveColor: secondary,
        currentIndex: tab,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_car_outlined), label: 'Trips'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Stats'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_border), activeIcon: Icon(Icons.favorite), label: 'Memories'),
        ],
      ),
    );
  }
}
