import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
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
  double? _radiusMeters; // null = ไม่กรองตามระยะทาง
  bool _isGettingLocation = false;
  int _limit = 20; // จำนวนรายการแรกสุดที่ดึงมา และเพิ่มได้ด้วยปุ่ม "โหลดเพิ่ม"

  // โหมดค้นหาจากสถานที่
  bool _isSearchByPlace = false; // true เมื่อใช้พิกัดจากข้อความค้นหา
  double? _searchLat;
  double? _searchLng;
  String? _searchPlaceLabel; // label แสดงชื่อสถานที่ที่ค้นหา

  // debounce สำหรับ geocoding
  final Duration _debounceDuration = const Duration(milliseconds: 500);
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // ตั้งค่ารัศมีเริ่มต้นเป็น 1 กม. เสมอ เพื่อไม่ให้เห็นประกาศเกิน 1 กม. ตั้งแต่แรก
    _radiusMeters = 1000;
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
                  // โหมดค้นหาจากสถานที่ด้วย debounce
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(_debounceDuration, () async {
                    final q = value.trim();
                    if (q.isEmpty) {
                      if (!mounted) return;
                      setState(() {
                        _isSearchByPlace = false;
                        _searchLat = null;
                        _searchLng = null;
                        _searchPlaceLabel = null;
                        _searchQuery = '';
                      });
                      return;
                    }
                    try {
                      final results = await geocoding.locationFromAddress(q);
                      if (results.isEmpty) {
                        if (!mounted) return;
                        setState(() {
                          _isSearchByPlace = false;
                          _searchLat = null;
                          _searchLng = null;
                          _searchPlaceLabel = null;
                          _searchQuery = q.toLowerCase();
                        });
                        return;
                      }
                      final loc = results.first;
                      if (!mounted) return;
                      setState(() {
                        _isSearchByPlace = true;
                        _searchLat = loc.latitude;
                        _searchLng = loc.longitude;
                        _searchPlaceLabel = q;
                        _radiusMeters =
                            1000; // โหมดสถานที่: ตั้งค่าเริ่มต้น 1 กม.
                        _searchQuery = q.toLowerCase();
                      });
                    } catch (_) {
                      if (!mounted) return;
                      setState(() {
                        _isSearchByPlace = false;
                        _searchLat = null;
                        _searchLng = null;
                        _searchPlaceLabel = null;
                        _searchQuery = q.toLowerCase();
                      });
                    }
                  });
                },
                decoration: InputDecoration(
                  hintText: 'ค้นหาที่จอดรถ',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'ล้าง',
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            if (_isSearchByPlace && _searchLat != null && _searchLng != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Chip(
                        avatar: const Icon(Icons.place, size: 18),
                        label: Text('ค้นหาจาก: ${_searchPlaceLabel ?? ''}'),
                      ),
                    ],
                  ),
                ),
              ),
            // ซ่อนข้อความสรุประยะทางที่กำลังกรอง ตามคำขอของผู้ใช้
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('parking_slots')
                  .orderBy('timestamp', descending: false)
                  .limit(_limit)
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
                  // ถ้าเป็นโหมดค้นหาจากสถานที่ จะไม่กรองตามชื่อประกาศ
                  final name = data['name']?.toString().toLowerCase() ?? '';
                  final matchesText =
                      _isSearchByPlace ? true : name.contains(_searchQuery);

                  // คำนวณระยะทางเส้นตรงถ้าทำได้
                  double? distance;
                  final GeoPoint? gp = data['location'] as GeoPoint?;
                  if (gp != null) {
                    if (_isSearchByPlace &&
                        _searchLat != null &&
                        _searchLng != null) {
                      distance = Geolocator.distanceBetween(
                        _searchLat!,
                        _searchLng!,
                        gp.latitude,
                        gp.longitude,
                      );
                    } else if (_currentPosition != null) {
                      distance = Geolocator.distanceBetween(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                        gp.latitude,
                        gp.longitude,
                      );
                    }
                  }

                  // ตัวกรองรัศมีเบื้องต้น
                  // - โหมดค้นหาสถานที่: ยังไม่กรอง (ไปกรองด้วยเส้นทางจริงภายหลัง)
                  // - โหมดตำแหน่งปัจจุบัน: ยังไม่กรองตรงนี้ ปล่อยไปกรองด้วยระยะเส้นทางจริงภายหลัง
                  bool passRadius = true;
                  if (_isSearchByPlace) {
                    passRadius = true; // รอกรองด้วย routeMeters ภายหลัง
                  } else if (_currentPosition != null) {
                    passRadius = true; // รอกรองด้วย routeMeters ภายหลัง
                  }

                  if (matchesText && passRadius) {
                    items.add({'doc': doc, 'data': data, 'distance': distance});
                  }
                }

                if (items.isEmpty) {
                  return const Center(child: Text('ยังไม่มีข้อมูลที่จอดรถ'));
                }

                // ถ้ามีตำแหน่งผู้ใช้ ให้ดึงระยะทางตามเส้นทางจริงและเรียงตามค่านั้น
                if (!_isSearchByPlace && _currentPosition != null) {
                  return FutureBuilder<List<int?>>(
                    future: _fetchRouteDistances(items),
                    builder: (context, snapRoute) {
                      List<Map<String, dynamic>> listToRender =
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

                      // เมื่อมีค่าเส้นทางจริง ให้กรองตามรัศมี (เริ่มต้น 1 กม.) ด้วย routeMeters
                      if (useRoute) {
                        final int limitMeters = (_radiusMeters ?? 1000).toInt();
                        listToRender = listToRender
                            .where((e) =>
                                (e['routeMeters'] as int?) != null &&
                                (e['routeMeters'] as int) <= limitMeters)
                            .toList();
                      }

                      if (useRoute) {
                        listToRender.sort((a, b) {
                          final ra = (a['routeMeters'] as int?) ?? 1 << 30;
                          final rb = (b['routeMeters'] as int?) ?? 1 << 30;
                          return ra.compareTo(rb);
                        });
                      } else {
                        // ถ้ายังไม่คำนวณเส้นทางจริง แสดงตัวโหลดและรอผล เพื่อกันแสดงรายการเกินรัศมี
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final showLoading = snapRoute.connectionState ==
                              ConnectionState.waiting &&
                          !useRoute;
                      final listWidget = _buildParkingList(listToRender,
                          preferRoute: useRoute);
                      final canLoadMore = snapshot.data!.docs.length >= _limit;
                      return Column(children: [
                        if (showLoading)
                          const LinearProgressIndicator(minHeight: 2),
                        listWidget,
                        const SizedBox(height: 8),
                        if (canLoadMore)
                          TextButton(
                            onPressed: () => setState(() => _limit += 20),
                            child: const Text('โหลดเพิ่ม'),
                          ),
                      ]);
                    },
                  );
                }

                // โหมดค้นหาจากสถานที่: ใช้ระยะเส้นทางจริงตามรัศมีที่เลือก
                if (_isSearchByPlace &&
                    _searchLat != null &&
                    _searchLng != null) {
                  return FutureBuilder<List<int?>>(
                    future: _fetchRouteDistancesFromOrigin(
                        _searchLat!, _searchLng!, items),
                    builder: (context, snapRoute) {
                      List<Map<String, dynamic>> listToRender =
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

                      if (!useRoute) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      // กรองภายในรัศมีที่เลือก (ค่าเริ่มต้น 1 กม.)
                      final int limitMeters = (_radiusMeters ?? 1000).toInt();
                      listToRender = listToRender
                          .where((e) =>
                              (e['routeMeters'] as int?) != null &&
                              (e['routeMeters'] as int) <= limitMeters)
                          .toList();

                      listToRender.sort((a, b) {
                        final ra = (a['routeMeters'] as int?) ?? 1 << 30;
                        final rb = (b['routeMeters'] as int?) ?? 1 << 30;
                        return ra.compareTo(rb);
                      });

                      final listWidget =
                          _buildParkingList(listToRender, preferRoute: true);
                      final canLoadMore = snapshot.data!.docs.length >= _limit;
                      return Column(children: [
                        listWidget,
                        const SizedBox(height: 8),
                        if (canLoadMore)
                          TextButton(
                            onPressed: () => setState(() => _limit += 20),
                            child: const Text('โหลดเพิ่ม'),
                          ),
                      ]);
                    },
                  );
                }

                // กรณีอื่น ๆ (เช่น ไม่มีตำแหน่งและไม่ได้ค้นหาจากสถานที่): เรียงตามเส้นตรงเป็น fallback
                items.sort((a, b) {
                  final da = (a['distance'] as double?) ?? double.infinity;
                  final db = (b['distance'] as double?) ?? double.infinity;
                  return da.compareTo(db);
                });
                final listWidget = _buildParkingList(items, preferRoute: false);
                final canLoadMore = snapshot.data!.docs.length >= _limit;
                return Column(children: [
                  listWidget,
                  const SizedBox(height: 8),
                  if (canLoadMore)
                    TextButton(
                      onPressed: () => setState(() => _limit += 20),
                      child: const Text('โหลดเพิ่ม'),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                if (_isSearchByPlace) {
                  await _openRadiusPickerForPlace();
                } else {
                  if (_isGettingLocation) return;
                  await _openRadiusPicker();
                }
              },
              child: _isGettingLocation && !_isSearchByPlace
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

  void _clearSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _searchController.clear();
      _isSearchByPlace = false;
      _searchLat = null;
      _searchLng = null;
      _searchPlaceLabel = null;
      _searchQuery = '';
    });
  }

  Future<void> _openRadiusPicker() async {
    setState(() {
      _isGettingLocation = true;
    });

    // ตรวจสอบสิทธิ์และดึงตำแหน่งปัจจุบัน
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

  Future<void> _openRadiusPickerForPlace() async {
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
                  if (_searchLat != null && _searchLng != null)
                    Row(
                      children: [
                        const Icon(Icons.place, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'สถานที่ค้นหา: ${_searchPlaceLabel ?? ''}\n(${_searchLat!.toStringAsFixed(4)}, ${_searchLng!.toStringAsFixed(4)})',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Slider(
                    min: 1000, // 1 กม.
                    max: 10000, // 10 กม.
                    divisions: 90,
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
        final thumb =
            (data['image_thumb_url'] ?? data['image_url'] ?? '').toString();
        return ListTile(
          leading: thumb.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    thumb,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                )
              : const Icon(Icons.local_parking),
          title: Text(data['name'] ?? 'ไม่มีชื่อ'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(builder: (_) {
                final t = (data['type'] ?? '').toString();
                final List<String> lines = [];
                if (t.contains('รถยนต์')) {
                  lines.add('ที่จอดรถยนต์: ${data['car_count'] ?? 0} คัน');
                }
                if (t.contains('มอเตอร์ไซค์')) {
                  lines
                      .add('ที่จอดมอเตอร์ไซค์: ${data['bike_count'] ?? 0} คัน');
                }
                return Text(lines.join('\n'));
              }),
              if (showRoute)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'ระยะทางโดยประมาณ: ${_formatDistance(routeMeters.toDouble())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                )
              else if (straight != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'ระยะทางโดยประมาณ: ${_formatDistance(straight)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              const SizedBox(height: 4),
              // แสดงคะแนนรีวิวใต้ระยะทาง: ใช้ค่า aggregate ถ้ามี
              // ถ้าไม่มี aggregate ให้ fallback ไปคำนวณจาก subcollection reviews แบบสด
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('parking_slots')
                    .doc(doc.id)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final v = snap.data!.data() as Map<String, dynamic>?;
                  final double aggAvg =
                      (v?['rating_avg'] as num?)?.toDouble() ?? 0.0;
                  final int aggCount =
                      (v?['rating_count'] as num?)?.toInt() ?? 0;

                  if (aggCount > 0) {
                    return Row(
                      children: [
                        ...List.generate(
                          5,
                          (i) => Icon(
                            i < aggAvg.round().clamp(0, 5)
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('${aggAvg.toStringAsFixed(1)} ($aggCount)'),
                      ],
                    );
                  }

                  // Fallback: อ่านรีวิวรายการนี้โดยตรงเพื่อคำนวณเฉลี่ยแบบเรียลไทม์
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('parking_slots')
                        .doc(doc.id)
                        .collection('reviews')
                        .snapshots(),
                    builder: (context, rs) {
                      if (!rs.hasData) return const SizedBox.shrink();
                      final docs = rs.data!.docs;
                      if (docs.isEmpty) return const SizedBox.shrink();
                      double sum = 0;
                      for (final d in docs) {
                        final r = d['rating'];
                        if (r is num) sum += r.toDouble();
                      }
                      final avg = sum / docs.length;
                      return Row(
                        children: [
                          ...List.generate(
                            5,
                            (i) => Icon(
                              i < avg.round().clamp(0, 5)
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('${avg.toStringAsFixed(1)} (${docs.length})'),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                _showBookingDialog(data, doc.id);
              },
              child: const Text(
                'จองที่จอดรถ',
                style: TextStyle(fontSize: 12),
              ),
            ),
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
      // ทางเลือกสำรองหากเรียกตำแหน่งแบบละเอียดไม่สำเร็จ
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

      // แบ่งปลายทางเป็นชุดละไม่เกิน 25 จุด ตามข้อจำกัดของ API
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

  Future<List<int?>> _fetchRouteDistancesFromOrigin(double originLat,
      double originLng, List<Map<String, dynamic>> items) async {
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

      const int chunk = 25;
      for (int i = 0; i < dests.length; i += chunk) {
        final batch = dests.sublist(
            i, i + chunk > dests.length ? dests.length : i + chunk);
        final idxs = mapIndex.sublist(
            i, i + chunk > dests.length ? dests.length : i + chunk);
        final resp = await callable.call({
          'origin': {'lat': originLat, 'lng': originLng},
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

  // Dialog จองที่จอดรถ
  Future<void> _showBookingDialog(
      Map<String, dynamic> slotData, String slotId) async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController();
    String? imageUrl; // URL หลังอัปโหลด
    DateTime? bookingDate; // วันที่ต้องการจอง
    bool busy = false;
    // เลือกประเภทรถ: เลือกได้อย่างใดอย่างหนึ่งเท่านั้น
    bool carChecked = false;
    bool bikeChecked = false;
    String? vehicleType; // 'car' หรือ 'bike'
    final String bankAccount =
        ((slotData['bankAccount'] ?? slotData['accountNumber'] ?? '')
                .toString())
            .trim();
    final String bankName = (slotData['bankName'] ?? '').toString().trim();
    final String accountName =
        (slotData['accountName'] ?? '').toString().trim();

    bool isValid() {
      final name = nameCtl.text.trim();
      final phone = phoneCtl.text.trim();
      final isDigits = RegExp(r'^\d{10}$').hasMatch(phone);
      return name.isNotEmpty &&
          isDigits &&
          imageUrl != null &&
          bookingDate != null &&
          vehicleType != null &&
          !busy;
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          Future<void> pickAndUpload() async {
            try {
              setD(() => busy = true);
              final ImagePicker picker = ImagePicker();
              final XFile? img =
                  await picker.pickImage(source: ImageSource.gallery);
              if (img == null) {
                setD(() => busy = false);
                return;
              }
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) throw Exception('กรุณาเข้าสู่ระบบ');
              final path =
                  'booking_images/$uid/${DateTime.now().millisecondsSinceEpoch}_${img.name}';
              final ref = FirebaseStorage.instance.ref(path);
              // ตรวจ metadata ก่อนส่ง
              final metadata = SettableMetadata(customMetadata: {
                'ownerUid': uid,
              });
              final task = await ref.putFile(
                File(img.path),
                metadata,
              );
              final url = await task.ref.getDownloadURL();
              setD(() {
                imageUrl = url;
                busy = false;
              });
            } on FirebaseException catch (e) {
              setD(() => busy = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: ${e.code}')));
              }
            } catch (e) {
              setD(() => busy = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
              }
            }
          }

          Future<void> submit() async {
            try {
              setD(() => busy = true);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) throw Exception('กรุณาเข้าสู่ระบบ');
              final name = nameCtl.text.trim();
              final phone = phoneCtl.text.trim();
              await FirebaseFirestore.instance.collection('user_bookings').add({
                'userId': uid,
                'slotId': slotId,
                'slotName': slotData['name'] ?? '-',
                'ownerId': slotData['ownerId'],
                'vehicleType': vehicleType,
                'name': name,
                'phone': phone,
                'imageUrl': imageUrl,
                'bookingDate': bookingDate != null
                    ? Timestamp.fromDate(DateTime(bookingDate!.year,
                        bookingDate!.month, bookingDate!.day))
                    : null,
                'status': 'pending',
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(const SnackBar(content: Text('จองสำเร็จ')));
              }
            } on FirebaseException catch (e) {
              setD(() => busy = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('การจองล้มเหลว: ${e.code}')),
                );
              }
            } catch (e) {
              setD(() => busy = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text('การจองล้มเหลว: $e')));
              }
            }
          }

          return AlertDialog(
            title: const Text('จองที่จอดรถ'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'คำเตือน : การจองนี้จะเป็นการจองแบบเต็มวันเท่านั้น.',
                      style: TextStyle(color: Colors.orangeAccent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ที่จอด: ${slotData['name'] ?? '-'}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ตัวเลือกประเภทรถ (อยู่เหนือช่องชื่อ)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('ประเภทรถ',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Wrap(
                    spacing: 20,
                    runSpacing: 0,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: carChecked,
                            onChanged: (v) {
                              setD(() {
                                carChecked = v == true;
                                if (carChecked) {
                                  bikeChecked = false;
                                  vehicleType = 'car';
                                } else if (!bikeChecked) {
                                  vehicleType = null;
                                }
                              });
                            },
                          ),
                          const Text('รถยนต์'),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: bikeChecked,
                            onChanged: (v) {
                              setD(() {
                                bikeChecked = v == true;
                                if (bikeChecked) {
                                  carChecked = false;
                                  vehicleType = 'bike';
                                } else if (!carChecked) {
                                  vehicleType = null;
                                }
                              });
                            },
                          ),
                          const Text('รถมอเตอร์ไซค์'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อ',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'เบอร์โทร (9–10 หลัก)',
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bookingDate == null
                              ? 'ยังไม่เลือกวันที่'
                              : "วันที่จอง: ${bookingDate!.day.toString().padLeft(2, '0')}/${bookingDate!.month.toString().padLeft(2, '0')}/${bookingDate!.year}",
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          DateTime now = DateTime.now();
                          // Parse service_date range: "dd/MM/yyyy - dd/MM/yyyy"
                          DateTime? rangeStart;
                          DateTime? rangeEnd;
                          try {
                            final raw =
                                (slotData['service_date'] ?? '').toString();
                            if (raw.contains('-')) {
                              final parts = raw.split('-');
                              DateTime? parseDate(String s) {
                                final t = s.trim();
                                final seg = t.split('/');
                                if (seg.length != 3) {
                                  return null;
                                }
                                final d = int.tryParse(seg[0]);
                                final m = int.tryParse(seg[1]);
                                final y = int.tryParse(seg[2]);
                                if (d == null || m == null || y == null) {
                                  return null;
                                }
                                return DateTime(y, m, d);
                              }

                              rangeStart = parseDate(parts[0]);
                              rangeEnd = parseDate(parts[1]);
                              if (rangeStart != null && rangeEnd != null) {
                                // Normalize to today-or-start for initial date
                                final today =
                                    DateTime(now.year, now.month, now.day);
                                if (today.isBefore(rangeStart)) {
                                  now = rangeStart;
                                } else if (today.isAfter(rangeEnd)) {
                                  now = rangeEnd;
                                } else {
                                  now = today;
                                }
                              }
                            }
                          } catch (_) {}

                          final picked = await showDatePicker(
                            context: context,
                            initialDate: now,
                            firstDate: (rangeStart ??
                                DateTime(now.year, now.month, now.day)),
                            lastDate: (rangeEnd ??
                                now.add(const Duration(days: 365))),
                          );
                          if (picked != null) {
                            setD(() => bookingDate = picked);
                          }
                        },
                        icon: const Icon(Icons.event),
                        label: const Text('เลือกวันที่จอง'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (bankAccount.isNotEmpty ||
                      bankName.isNotEmpty ||
                      accountName.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (bankName.isNotEmpty)
                                  Text('ธนาคาร : $bankName'),
                                if (accountName.isNotEmpty)
                                  Text('ชื่อบัญชี : $accountName'),
                                if (bankAccount.isNotEmpty)
                                  Text(
                                    'เลขบัญชี : $bankAccount',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (bankAccount.isNotEmpty)
                            TextButton.icon(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                          ClipboardData(text: bankAccount));
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content:
                                                  Text('คัดลอกเลขบัญชีแล้ว')),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('คัดลอก'),
                            ),
                        ],
                      ),
                    ),
                  // แสดงส่วนเลขบัญชีให้อยู่เหนือปุ่มแนบรูปสลิปตามที่ร้องขอ
                  const SizedBox(height: 4),
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(imageUrl!,
                          height: 120, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    onPressed: busy ? null : pickAndUpload,
                    icon: const Icon(Icons.image),
                    label: Text(
                        imageUrl == null ? 'แนบรูปสลิป' : 'เปลี่ยนรูปสลิป'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        // ถ้ามีรูปอัปโหลดไว้แต่ยกเลิก อาจลบไฟล์เพื่อความสะอาด (ไม่บังคับ)
                        Navigator.pop(ctx);
                      },
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: isValid() ? submit : null,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ยืนยันการจอง'),
              ),
            ],
          );
        });
      },
    );
  }
}
