import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'dart:io';

class MyMember extends StatefulWidget {
  const MyMember({super.key});

  @override
  State<MyMember> createState() => _MyMemberState();
}

class _MyMemberState extends State<MyMember> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController carCountController = TextEditingController();
  final TextEditingController bikeCountController = TextEditingController();
  final TextEditingController carPriceController = TextEditingController();
  final TextEditingController bikePriceController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController timeController = TextEditingController();
  final TextEditingController detailsController =
      TextEditingController(); // Add a new TextEditingController for additional details
  String vehicleType = '';
  bool _isImagePickerActive = false; // Add a flag to track ImagePicker state
  String? nameError; // Add a variable to store the error message
  LatLng? selectedLocation; // Add a variable to store the selected location

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('ปล่อยเช่าที่จอดรถ'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
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

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(child: Text('ยังไม่มีข้อมูลที่จอดรถ'));
                }

                final currentUid = FirebaseAuth.instance.currentUser?.uid;

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final docSnap = docs[index];
                    final data = docSnap.data() as Map<String, dynamic>;
                    final isOwner =
                        (currentUid != null && data['ownerId'] == currentUid);
                    return ListTile(
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (data['type'].contains('รถยนต์'))
                            const Icon(Icons.directions_car),
                          if (data['type'].contains('มอเตอร์ไซค์'))
                            const Icon(Icons.motorcycle),
                        ],
                      ),
                      title: Text(
                        data['name'] ?? 'ไม่มีชื่อ',
                        style: TextStyle(
                          fontSize: 20, // ขนาดตัวอักษรของชื่อที่จอดรถ
                          fontWeight: FontWeight.bold, // ทำให้ตัวหนา
                        ),
                      ),
                      subtitle: Text(
                        'จำนวนรถยนต์: ${data['car_count'] ?? 0}\nจำนวนมอเตอร์ไซค์: ${data['bike_count'] ?? 0}',
                        style: TextStyle(
                          fontSize: 16, // ขนาดตัวอักษรของจำนวนที่จอดรถ
                          color: const Color.fromARGB(
                              255, 175, 175, 175), // เปลี่ยนสีของตัวอักษร
                        ),
                      ),
                      trailing: isOwner
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  tooltip: 'แก้ไขข้อมูล',
                                  onPressed: () async {
                                    await showDialog(
                                      context: context,
                                      builder: (ctx) => _buildEditDialog(
                                          ctx, docSnap.id, data),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'ลบประกาศ',
                                  onPressed: () async {
                                    await _confirmAndDelete(
                                        context, docSnap.id, data);
                                  },
                                ),
                              ],
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ParkingDetailScreen(data: data),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => _buildAddDialog(context),
                );
              },
              child: const Text('เพิ่มที่จอดรถ'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete(
      BuildContext context, String docId, Map<String, dynamic> data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: const Text(
            'คุณต้องการลบประกาศนี้หรือไม่? การลบไม่สามารถย้อนกลับได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // พยายามลบรูปทั้งหมดที่เคยผูกกับประกาศนี้ก่อน (ลบทุกรูปของประกาศนี้เท่านั้น)
      final paths =
          ((data['image_paths'] as List?)?.map((e) => e.toString()).toSet()) ??
              <String>{};
      final imageUrl = data['image_url'] as String?;
      // ลบจาก URL ล่าสุดด้วย (เผื่อยังไม่มีใน paths)
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(imageUrl);
          await ref.delete();
        } catch (_) {}
      }
      for (final p in paths) {
        try {
          final ref = FirebaseStorage.instance.ref(p);
          await ref.delete();
        } catch (_) {}
      }

      // ลบเอกสาร Firestore หลังจากจัดการรูปแล้ว
      await FirebaseFirestore.instance
          .collection('parking_slots')
          .doc(docId)
          .delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบประกาศเรียบร้อย')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ลบประกาศล้มเหลว: $e')),
        );
      }
    }
  }

  Widget _buildAddDialog(BuildContext context) {
    // Local variables to manage state within the dialog
    String localVehicleType = vehicleType;
    String? localImageUrlInDialog; // hold uploaded image url until save
    final List<String> localImagePathsInDialog =
        <String>[]; // keep storage paths for deletion later

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        return AlertDialog(
          title: const Text('เพิ่มที่จอดรถ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'ตั้งชื่อที่จอดรถ',
                    errorText: nameError, // Display error message if any
                  ),
                ),
                CheckboxListTile(
                  title: const Text('รถยนต์'),
                  value: localVehicleType.contains('รถยนต์'),
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        if (!localVehicleType.contains('รถยนต์')) {
                          localVehicleType += 'รถยนต์ ';
                        }
                      } else {
                        localVehicleType =
                            localVehicleType.replaceAll('รถยนต์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('รถยนต์')) ...[
                  TextField(
                    controller: carCountController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'จำนวนที่จอดรถยนต์'),
                  ),
                  TextField(
                    controller: carPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'ราคาที่จอดรถยนต์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                CheckboxListTile(
                  title: const Text('มอเตอร์ไซค์'),
                  value: localVehicleType.contains('มอเตอร์ไซค์'),
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        if (!localVehicleType.contains('มอเตอร์ไซค์')) {
                          localVehicleType += 'มอเตอร์ไซค์ ';
                        }
                      } else {
                        localVehicleType =
                            localVehicleType.replaceAll('มอเตอร์ไซค์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('มอเตอร์ไซค์')) ...[
                  TextField(
                    controller: bikeCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'จำนวนที่จอดมอเตอร์ไซค์'),
                  ),
                  TextField(
                    controller: bikePriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'ราคาที่จอดมอเตอร์ไซค์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(
                      labelText: 'วันที่เปิดให้บริการ(เช่น 27/04/2025)'),
                  keyboardType: TextInputType.datetime,
                ),
                TextField(
                  controller: timeController,
                  decoration: const InputDecoration(
                      labelText: 'เวลาที่เปิดให้บริการ(เช่น 08:00-20:00)'),
                ),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดเพิ่มเติม',
                    hintText: 'กรอกรายละเอียดเพิ่มเติมเกี่ยวกับที่จอดรถ',
                  ),
                  maxLines: null, // Allow multi-line input
                ),
                if (localImageUrlInDialog != null &&
                    localImageUrlInDialog!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Image.network(localImageUrlInDialog!,
                        height: 120, fit: BoxFit.cover),
                  ),
                ElevatedButton(
                  onPressed: _isImagePickerActive
                      ? null // Disable button if ImagePicker is active
                      : () async {
                          setState(() {
                            _isImagePickerActive = true;
                          });

                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                              source: ImageSource.gallery);

                          if (image != null) {
                            try {
                              // Upload image to Firebase Storage
                              final storageRef = FirebaseStorage.instance
                                  .ref()
                                  .child(
                                      'parking_images/${DateTime.now().millisecondsSinceEpoch}_${image.name}');
                              final uploadTask =
                                  await storageRef.putFile(File(image.path));

                              // Get the download URL and keep locally until Save
                              final imageUrl =
                                  await uploadTask.ref.getDownloadURL();

                              setDialogState(() {
                                localImageUrlInDialog = imageUrl;
                                // record storage path for later deletion when post removed
                                if (!localImagePathsInDialog
                                    .contains(storageRef.fullPath)) {
                                  localImagePathsInDialog
                                      .add(storageRef.fullPath);
                                }
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('อัปโหลดรูปภาพเรียบร้อย')),
                                );
                              }
                            } catch (e) {
                              // Show an error message if something goes wrong
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('อัปโหลดรูปภาพล้มเหลว: $e')),
                                );
                              }
                            } finally {
                              setState(() {
                                _isImagePickerActive = false;
                              });
                            }
                          } else {
                            setState(() {
                              _isImagePickerActive = false;
                            });
                          }
                        },
                  child: const Text('เพิ่มรูปภาพ'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final LatLng? result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MapScreen(),
                      ),
                    );
                    if (result != null) {
                      selectedLocation = result;
                      setDialogState(() {}); // Refresh dialog state
                    }
                  },
                  child: const Text('เลือกปักหมุดสถานที่'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    (carCountController.text.isNotEmpty ||
                        bikeCountController.text.isNotEmpty)) {
                  setState(() {
                    vehicleType = localVehicleType.trim();
                  });

                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('กรุณาเข้าสู่ระบบก่อนบันทึก')),
                      );
                    }
                    return;
                  }

                  // Check if the parking name already exists
                  final existingDocs = await FirebaseFirestore.instance
                      .collection('parking_slots')
                      .where('name', isEqualTo: nameController.text)
                      .get();

                  if (existingDocs.docs.isNotEmpty) {
                    // Show a warning below the input field
                    setDialogState(() {
                      nameError = 'ชื่อที่จอดรถนี้มีอยู่แล้ว กรุณาตั้งชื่อใหม่';
                    });
                    return;
                  }

                  try {
                    await FirebaseFirestore.instance
                        .collection('parking_slots')
                        .add({
                      'name': nameController.text,
                      'type': localVehicleType.trim(),
                      'car_count': int.tryParse(carCountController.text) ?? 0,
                      'bike_count': int.tryParse(bikeCountController.text) ?? 0,
                      'car_price': int.tryParse(carPriceController.text) ?? 0,
                      'bike_price': int.tryParse(bikePriceController.text) ?? 0,
                      'service_date': dateController.text,
                      'service_time': timeController.text,
                      'details':
                          detailsController.text, // Save additional details
                      if (localImageUrlInDialog != null)
                        'image_url': localImageUrlInDialog,
                      if (localImagePathsInDialog.isNotEmpty)
                        'image_paths': localImagePathsInDialog,
                      'location': selectedLocation != null
                          ? GeoPoint(selectedLocation!.latitude,
                              selectedLocation!.longitude)
                          : null,
                      'ownerId': uid,
                      'timestamp': FieldValue.serverTimestamp(),
                    });

                    // Clear the input fields and close the dialog
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    nameController.clear();
                    carCountController.clear();
                    bikeCountController.clear();
                    carPriceController.clear();
                    bikePriceController.clear();
                    dateController.clear();
                    timeController.clear();
                    detailsController
                        .clear(); // Clear the additional details controller
                    vehicleType = '';
                    selectedLocation = null; // Clear the selected location
                  } catch (e) {
                    // Show an error message if something goes wrong
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                      );
                    }
                  }
                } else {
                  setDialogState(() {
                    nameError = 'กรุณากรอกข้อมูลให้ครบถ้วน';
                  });
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditDialog(
      BuildContext context, String docId, Map<String, dynamic> data) {
    // Local state and controllers initialized from existing data
    final nameCtl = TextEditingController(text: data['name'] ?? '');
    final carCountCtl =
        TextEditingController(text: (data['car_count']?.toString() ?? ''));
    final bikeCountCtl =
        TextEditingController(text: (data['bike_count']?.toString() ?? ''));
    final carPriceCtl =
        TextEditingController(text: (data['car_price']?.toString() ?? ''));
    final bikePriceCtl =
        TextEditingController(text: (data['bike_price']?.toString() ?? ''));
    final dateCtl = TextEditingController(text: data['service_date'] ?? '');
    final timeCtl = TextEditingController(text: data['service_time'] ?? '');
    final detailsCtl = TextEditingController(text: data['details'] ?? '');

    String localVehicleType = (data['type'] ?? '').toString();
    GeoPoint? gp = data['location'] as GeoPoint?;
    LatLng? localSelectedLocation =
        gp != null ? LatLng(gp.latitude, gp.longitude) : null;
    String? localImageUrl = data['image_url'] as String?;
    final List<String> originalImagePaths =
        (data['image_paths'] as List?)?.map((e) => e.toString()).toList() ??
            <String>[];
    final List<String> localImagePaths = List<String>.from(originalImagePaths);
    String? localNameError;
    bool busy = false;

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        return AlertDialog(
          title: const Text('แก้ไขที่จอดรถ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: InputDecoration(
                    labelText: 'ชื่อที่จอดรถ',
                    errorText: localNameError,
                  ),
                ),
                CheckboxListTile(
                  title: const Text('รถยนต์'),
                  value: localVehicleType.contains('รถยนต์'),
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        if (!localVehicleType.contains('รถยนต์')) {
                          localVehicleType += 'รถยนต์ ';
                        }
                      } else {
                        localVehicleType =
                            localVehicleType.replaceAll('รถยนต์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('รถยนต์')) ...[
                  TextField(
                    controller: carCountCtl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'จำนวนที่จอดรถยนต์'),
                  ),
                  TextField(
                    controller: carPriceCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'ราคาที่จอดรถยนต์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                CheckboxListTile(
                  title: const Text('มอเตอร์ไซค์'),
                  value: localVehicleType.contains('มอเตอร์ไซค์'),
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        if (!localVehicleType.contains('มอเตอร์ไซค์')) {
                          localVehicleType += 'มอเตอร์ไซค์ ';
                        }
                      } else {
                        localVehicleType =
                            localVehicleType.replaceAll('มอเตอร์ไซค์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('มอเตอร์ไซค์')) ...[
                  TextField(
                    controller: bikeCountCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'จำนวนที่จอดมอเตอร์ไซค์'),
                  ),
                  TextField(
                    controller: bikePriceCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'ราคาที่จอดมอเตอร์ไซค์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                TextField(
                  controller: dateCtl,
                  decoration: const InputDecoration(
                      labelText: 'วันที่เปิดให้บริการ(เช่น 27/04/2025)'),
                  keyboardType: TextInputType.datetime,
                ),
                TextField(
                  controller: timeCtl,
                  decoration: const InputDecoration(
                      labelText: 'เวลาที่เปิดให้บริการ(เช่น 08:00-20:00)'),
                ),
                TextField(
                  controller: detailsCtl,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดเพิ่มเติม',
                    hintText: 'แก้ไขรายละเอียดเกี่ยวกับที่จอดรถ',
                  ),
                  maxLines: null,
                ),
                if (localImageUrl != null && localImageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Image.network(localImageUrl!,
                        height: 120, fit: BoxFit.cover),
                  ),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setDialogState(() => busy = true);
                          try {
                            final ImagePicker picker = ImagePicker();
                            final XFile? image = await picker.pickImage(
                                source: ImageSource.gallery);
                            if (image != null) {
                              final storageRef = FirebaseStorage.instance
                                  .ref()
                                  .child(
                                      'parking_images/${DateTime.now().millisecondsSinceEpoch}_${image.name}');
                              final uploadTask =
                                  await storageRef.putFile(File(image.path));
                              final url = await uploadTask.ref.getDownloadURL();
                              setDialogState(() {
                                localImageUrl = url;
                                if (!localImagePaths
                                    .contains(storageRef.fullPath)) {
                                  localImagePaths.add(storageRef.fullPath);
                                }
                              });
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('อัปโหลดรูปภาพล้มเหลว: $e')));
                            }
                          } finally {
                            setDialogState(() => busy = false);
                          }
                        },
                  child: const Text('เปลี่ยนรูปภาพ'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final LatLng? result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => MapScreen()),
                    );
                    if (result != null) {
                      localSelectedLocation = result;
                      setDialogState(() {});
                    }
                  },
                  child: const Text('แก้ไขปักหมุดสถานที่'),
                ),
                if (localSelectedLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(
                        'ตำแหน่งใหม่: ${localSelectedLocation!.latitude.toStringAsFixed(6)}, ${localSelectedLocation!.longitude.toStringAsFixed(6)}'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      // Basic validation
                      if (nameCtl.text.trim().isEmpty ||
                          (carCountCtl.text.trim().isEmpty &&
                              bikeCountCtl.text.trim().isEmpty)) {
                        setDialogState(() {
                          localNameError =
                              'กรุณากรอกชื่อ และจำนวนที่จอดอย่างน้อย 1 ประเภท';
                        });
                        return;
                      }

                      setDialogState(() => busy = true);
                      try {
                        // If name changed, ensure uniqueness
                        if (nameCtl.text.trim() != (data['name'] ?? '')) {
                          final dup = await FirebaseFirestore.instance
                              .collection('parking_slots')
                              .where('name', isEqualTo: nameCtl.text.trim())
                              .get();
                          final existsOther =
                              dup.docs.any((d) => d.id != docId);
                          if (existsOther) {
                            setDialogState(() {
                              localNameError =
                                  'ชื่อที่จอดรถนี้มีอยู่แล้ว กรุณาตั้งชื่อใหม่';
                              busy = false;
                            });
                            return;
                          }
                        }

                        final update = <String, dynamic>{
                          'name': nameCtl.text.trim(),
                          'type': localVehicleType.trim(),
                          'car_count': int.tryParse(carCountCtl.text) ?? 0,
                          'bike_count': int.tryParse(bikeCountCtl.text) ?? 0,
                          'car_price': int.tryParse(carPriceCtl.text) ?? 0,
                          'bike_price': int.tryParse(bikePriceCtl.text) ?? 0,
                          'service_date': dateCtl.text,
                          'service_time': timeCtl.text,
                          'details': detailsCtl.text,
                        };
                        if (localImageUrl != null) {
                          update['image_url'] = localImageUrl;
                        }
                        // add new paths (if any) without duplicates
                        final List<String> newPaths = localImagePaths
                            .where((p) => !originalImagePaths.contains(p))
                            .toList();
                        if (newPaths.isNotEmpty) {
                          update['image_paths'] =
                              FieldValue.arrayUnion(newPaths);
                        }
                        if (localSelectedLocation != null) {
                          update['location'] = GeoPoint(
                              localSelectedLocation!.latitude,
                              localSelectedLocation!.longitude);
                        }

                        await FirebaseFirestore.instance
                            .collection('parking_slots')
                            .doc(docId)
                            .update(update);

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('อัปเดตข้อมูลเรียบร้อย')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('อัปเดตล้มเหลว: $e')));
                        }
                      } finally {
                        setDialogState(() => busy = false);
                      }
                    },
              child: const Text('บันทึกการแก้ไข'),
            ),
          ],
        );
      },
    );
  }
}

class ParkingDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const ParkingDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final GeoPoint? location = data['location'] as GeoPoint?;

    return Scaffold(
      appBar: AppBar(
        title: Text(data['name'] ?? 'รายละเอียดที่จอดรถ'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data['image_url'] != null && data['image_url'].isNotEmpty)
                Center(
                  child: Image.network(
                    data['image_url'],
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'ที่จอดรถ: ${data['name'] ?? 'ไม่มีชื่อ'}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text('ประเภท: ${data['type'] ?? 'ไม่มีข้อมูล'}\n'),
              const SizedBox(height: 5),
              Text('จำนวนรถยนต์: ${data['car_count'] ?? 0}'),
              const SizedBox(height: 5),
              Text('ราคาที่จอดรถยนต์: ${data['car_price'] ?? 0} บาท/ชั่วโมง\n'),
              const SizedBox(height: 5),
              Text('จำนวนมอเตอร์ไซค์: ${data['bike_count'] ?? 0}'),
              const SizedBox(height: 5),
              Text(
                  'ราคาที่จอดมอเตอร์ไซค์: ${data['bike_price'] ?? 0} บาท/ชั่วโมง\n'),
              const SizedBox(height: 5),
              Text(
                  'วันที่เปิดให้บริการ: ${data['service_date'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 5),
              Text(
                  'เวลาที่เปิดให้บริการ: ${data['service_time'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 20),
              if (location != null) ...[
                const Text(
                  'ตำแหน่งที่จอดรถ:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 200,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(location.latitude, location.longitude),
                      zoom: 15,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('parking_location'),
                        position: LatLng(location.latitude, location.longitude),
                        infoWindow:
                            InfoWindow(title: data['name'] ?? 'ที่จอดรถ'),
                      ),
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                    mapType: MapType.normal,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'รายละเอียดเพิ่มเติม:',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text('${data['details'] ?? 'ไม่มีข้อมูล'}'),
            ],
          ),
        ),
      ),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _controller;
  final TextEditingController _searchController = TextEditingController();
  final Set<Marker> _markers = {};
  LatLng? _selectedLocation;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(13.7563, 100.5018), // Bangkok coordinates
    zoom: 11,
  );

  void _addMarker(LatLng position) {
    setState(() {
      _markers.clear(); // Remove existing markers
      _selectedLocation = position;
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_location'),
          position: position,
          infoWindow: const InfoWindow(title: 'ตำแหน่งที่เลือก'),
        ),
      );
    });
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาพิมพ์สถานที่ที่ต้องการค้นหา')),
      );
      return;
    }
    try {
      final results = await geocoding.locationFromAddress(query);
      if (results.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบสถานที่ที่ค้นหา')),
        );
        return;
      }
      final first = results.first;
      final target = LatLng(first.latitude, first.longitude);
      _addMarker(target);
      await _controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 15),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ค้นหาสถานที่ล้มเหลว: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกตำแหน่งที่จอดรถ'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _searchPlace(),
              decoration: InputDecoration(
                hintText: 'ค้นหาสถานที่...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchPlace,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              onMapCreated: (GoogleMapController controller) {
                _controller = controller;
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapType: MapType.normal,
              markers: _markers,
              onTap: _addMarker,
            ),
          ),
          if (_selectedLocation != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    'ละติจูด: ${_selectedLocation!.latitude.toStringAsFixed(6)}\nลองจิจูด: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // Return the selected location to the previous screen
                      Navigator.pop(context, _selectedLocation);
                    },
                    child: const Text('ยืนยันตำแหน่ง'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
