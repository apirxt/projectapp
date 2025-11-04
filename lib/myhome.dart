import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'screen/parking_detail.dart';

class MyHome extends StatefulWidget {
  const MyHome({super.key});

  @override
  State<MyHome> createState() => _MyHomeState();
}

class _MyHomeState extends State<MyHome> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Position? _currentPosition;
  double? _radiusMeters; // null = no radius filter
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    // เมื่อเข้าหน้า ให้พยายามดึงตำแหน่งและตั้งค่าเริ่มต้นที่ 1 กม.
    _initDefaultRadius();
  }

  Future<void> _initDefaultRadius() async {
    try {
      setState(() => _isGettingLocation = true);
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isGettingLocation = false);
        return; // ไม่บังคับ หากปิด GPS จะไม่กรองระยะ
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() => _isGettingLocation = false);
        return; // ไม่อนุญาต ก็ไม่กรอง
      }
      final pos = await _getPrecisePosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _radiusMeters = 1000; // ค่าพื้นฐานเริ่มต้น 1 กิโลเมตร
        _isGettingLocation = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isGettingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('เลือกที่จอดรถ'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'ค้นหาที่จอดรถ',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            // ซ่อนข้อความสรุประยะทางที่กำลังกรอง ตามคำขอของผู้ใช้
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('parking_slots')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('เกิดข้อผิดพลาด'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data!.docs;
                final List<Map<String, dynamic>> items = [];
                for (final doc in allDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name']?.toString().toLowerCase() ?? '';
                  final matchesText = name.contains(_searchQuery);

                  // compute distance if possible
                  double? distance;
                  final GeoPoint? gp = data['location'] as GeoPoint?;
                  if (_currentPosition != null && gp != null) {
                    distance = Geolocator.distanceBetween(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                      gp.latitude,
                      gp.longitude,
                    );
                  }

                  // apply radius filter only when both radius and current position exist
                  bool passRadius = true;
                  if (_radiusMeters != null && _currentPosition != null) {
                    passRadius =
                        (distance != null) && (distance <= _radiusMeters!);
                  }

                  if (matchesText && passRadius) {
                    items.add({'doc': doc, 'data': data, 'distance': distance});
                  }
                }

                if (items.isEmpty) {
                  return const Center(child: Text('ยังไม่มีข้อมูลที่จอดรถ'));
                }

                // If we know user's position, fetch route distances and sort by them
                if (_currentPosition != null) {
                  return FutureBuilder<List<int?>>(
                    future: _fetchRouteDistances(items),
                    builder: (context, snapRoute) {
                      final listToRender =
                          List<Map<String, dynamic>>.from(items);
                      final routeMeters = snapRoute.data;
                      final useRoute = routeMeters != null &&
                          routeMeters.any((e) => e != null);

                      if (routeMeters != null) {
                        for (int i = 0;
                            i < listToRender.length && i < routeMeters.length;
                            i++) {
                          listToRender[i]['routeMeters'] = routeMeters[i];
                        }
                      }

                      if (useRoute) {
                        listToRender.sort((a, b) {
                          final ra = (a['routeMeters'] as int?) ?? 1 << 30;
                          final rb = (b['routeMeters'] as int?) ?? 1 << 30;
                          return ra.compareTo(rb);
                        });
                      } else {
                        // fallback: sort by straight-line distance
                        listToRender.sort((a, b) {
                          final da =
                              (a['distance'] as double?) ?? double.infinity;
                          final db =
                              (b['distance'] as double?) ?? double.infinity;
                          return da.compareTo(db);
                        });
                      }

                      final showLoading = snapRoute.connectionState ==
                              ConnectionState.waiting &&
                          !useRoute;
                      return Column(
                        children: [
                          if (showLoading)
                            const LinearProgressIndicator(minHeight: 2),
                          _buildParkingList(listToRender,
                              preferRoute: useRoute),
                        ],
                      );
                    },
                  );
                }

                // No current position: normal list sorted by name or unchanged
                return _buildParkingList(items, preferRoute: false);
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isGettingLocation ? null : _openRadiusPicker,
              child: _isGettingLocation
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('เลือกระยะทาง'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _openRadiusPicker() async {
    setState(() {
      _isGettingLocation = true;
    });

    // Ensure location permission & current position
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isGettingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('โปรดเปิดบริการระบุตำแหน่ง (GPS)')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() => _isGettingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('แอปไม่มีสิทธิ์เข้าถึงตำแหน่ง')),
          );
        }
        return;
      }

      final pos = await _getPrecisePosition();
      setState(() {
        _currentPosition = pos;
      });
    } catch (e) {
      setState(() => _isGettingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถดึงตำแหน่งปัจจุบัน: $e')),
        );
      }
      return;
    }

    setState(() => _isGettingLocation = false);

    if (!mounted) return;

    double tempRadiusMeters = _radiusMeters ?? 1000; // default 1 กม.

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('เลือกระยะรัศมีการค้นหา'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.place, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'ตำแหน่งปัจจุบัน: '
                          '${_currentPosition!.latitude.toStringAsFixed(4)}, '
                          '${_currentPosition!.longitude.toStringAsFixed(4)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    min: 1000, // 1 กม.
                    max: 10000, // 10 กม.
                    divisions: 90, // ขั้นละ 100 เมตร
                    value: tempRadiusMeters.clamp(1000, 10000),
                    label: tempRadiusMeters >= 1000
                        ? '${(tempRadiusMeters / 1000).toStringAsFixed(1)} กม.'
                        : '${tempRadiusMeters.toStringAsFixed(0)} ม.',
                    onChanged: (v) {
                      setStateDialog(() {
                        tempRadiusMeters = v;
                      });
                    },
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      tempRadiusMeters >= 1000
                          ? '≈ ${(tempRadiusMeters / 1000).toStringAsFixed(1)} กิโลเมตร'
                          : '≈ ${tempRadiusMeters.toStringAsFixed(0)} เมตร',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _radiusMeters = tempRadiusMeters;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('ยืนยัน'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDistance(double d) {
    if (d >= 1000) {
      return '${(d / 1000).toStringAsFixed(1)} กม.';
    }
    return '${d.toStringAsFixed(0)} ม.';
  }

  Widget _buildParkingList(List<Map<String, dynamic>> items,
      {required bool preferRoute}) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final entry = items[index];
        final doc = entry['doc'] as QueryDocumentSnapshot;
        final data = entry['data'] as Map<String, dynamic>;
        final double? straight = entry['distance'] as double?;
        final int? routeMeters = entry['routeMeters'] as int?;
        final bool showRoute = preferRoute && routeMeters != null;
        return ListTile(
          leading: const Icon(Icons.local_parking),
          title: Text(data['name'] ?? 'ไม่มีชื่อ'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ที่จอดรถยนต์: ${data['car_count'] ?? 0} คัน\nที่จอดมอเตอร์ไซค์: ${data['bike_count'] ?? 0} คัน',
              ),
              if (showRoute)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      'ระยะทางโดยประมาณ: ${_formatDistance(routeMeters.toDouble())}'),
                )
              else if (straight != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('ระยะทางโดยประมาณ: ${_formatDistance(straight)}'),
                ),
              const SizedBox(height: 4),
              // Rating summary (avg and count)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('parking_slots')
                    .doc(doc.id)
                    .collection('reviews')
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final rdocs = snap.data!.docs;
                  if (rdocs.isEmpty) {
                    return const Text('ยังไม่มีการให้คะแนน');
                  }
                  final ratings =
                      rdocs.map((d) => (d['rating'] ?? 0).toDouble()).toList();
                  final avg = ratings.reduce((a, b) => a + b) / ratings.length;
                  final stars = avg.round().clamp(0, 5);
                  return Row(
                    children: [
                      ...List.generate(
                          5,
                          (i) => Icon(
                                i < stars ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: 16,
                              )),
                      const SizedBox(width: 6),
                      Text('${avg.toStringAsFixed(1)} (${rdocs.length})'),
                    ],
                  );
                },
              ),
            ],
          ),
          trailing: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ParkingDetail(parkingData: data, docId: doc.id),
                ),
              );
            },
            child: const Text('เลือก'),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ParkingDetail(parkingData: data, docId: doc.id),
              ),
            );
          },
        );
      },
    );
  }

  Future<Position> _getPrecisePosition() async {
    Position? seed = await Geolocator.getLastKnownPosition();
    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 10),
        ),
      );
      // เลือกตำแหน่งที่มี accuracy ต่ำกว่า (ดีกว่า)
      if (seed == null || fresh.accuracy <= seed.accuracy) return fresh;
      return seed;
    } catch (_) {
      if (seed != null) return seed;
      // fallback
      return await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
    }
  }

  Future<List<int?>> _fetchRouteDistances(
      List<Map<String, dynamic>> items) async {
    if (_currentPosition == null) return List<int?>.filled(items.length, null);
    try {
      final List<Map<String, double>> dests = [];
      final List<int> mapIndex = [];
      for (int i = 0; i < items.length; i++) {
        final data = items[i]['data'] as Map<String, dynamic>;
        final GeoPoint? gp = data['location'] as GeoPoint?;
        if (gp != null) {
          dests.add({'lat': gp.latitude, 'lng': gp.longitude});
          mapIndex.add(i);
        }
      }
      if (dests.isEmpty) return List<int?>.filled(items.length, null);

      final results = List<int?>.filled(items.length, null);
      final callable = FirebaseFunctions.instance.httpsCallable('routeMatrix');

      // chunk into batches of 25 destinations to respect API caps
      const int chunk = 25;
      for (int i = 0; i < dests.length; i += chunk) {
        final batch = dests.sublist(
            i, i + chunk > dests.length ? dests.length : i + chunk);
        final idxs = mapIndex.sublist(
            i, i + chunk > dests.length ? dests.length : i + chunk);
        final resp = await callable.call({
          'origin': {
            'lat': _currentPosition!.latitude,
            'lng': _currentPosition!.longitude
          },
          'destinations': batch,
          'mode': 'driving',
        });
        final List distances = (resp.data['distances'] as List?) ?? [];
        for (int j = 0; j < distances.length && j < idxs.length; j++) {
          final d = distances[j];
          if (d is Map && d['meters'] != null) {
            results[idxs[j]] = (d['meters'] as num).toInt();
          }
        }
      }
      return results;
    } catch (_) {
      return List<int?>.filled(items.length, null);
    }
  }
}
