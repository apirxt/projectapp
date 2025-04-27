import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class mymember extends StatefulWidget {
  const mymember({super.key});

  @override
  State<mymember> createState() => _mymemberState();
}

class _mymemberState extends State<mymember> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController carCountController = TextEditingController();
  final TextEditingController bikeCountController = TextEditingController();
  final TextEditingController carPriceController = TextEditingController();
  final TextEditingController bikePriceController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController timeController = TextEditingController();
  final TextEditingController detailsController = TextEditingController(); // Add a new TextEditingController for additional details
  String vehicleType = '';
  bool _isImagePickerActive = false; // Add a flag to track ImagePicker state
  String? nameError; // Add a variable to store the error message

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

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
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
                          color: const Color.fromARGB(255, 175, 175, 175), // เปลี่ยนสีของตัวอักษร
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ParkingDetailScreen(data: data),
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

  Widget _buildAddDialog(BuildContext context) {
    // Local variables to manage state within the dialog
    String localVehicleType = vehicleType;

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
                        localVehicleType = localVehicleType.replaceAll('รถยนต์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('รถยนต์')) ...[
                  TextField(
                    controller: carCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'จำนวนที่จอดรถยนต์'),
                  ),
                  TextField(
                    controller: carPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ราคาที่จอดรถยนต์(บาท/ชั่วโมง)'),
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
                        localVehicleType = localVehicleType.replaceAll('มอเตอร์ไซค์ ', '');
                      }
                    });
                  },
                ),
                if (localVehicleType.contains('มอเตอร์ไซค์')) ...[
                  TextField(
                    controller: bikeCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'จำนวนที่จอดมอเตอร์ไซค์'),
                  ),
                  TextField(
                    controller: bikePriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ราคาที่จอดมอเตอร์ไซค์(บาท/ชั่วโมง)'),
                  ),
                ],
                const Divider(height: 0),
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(labelText: 'วันที่เปิดให้บริการ(เช่น 27/04/2025)'),
                  keyboardType: TextInputType.datetime,
                ),
                TextField(
                  controller: timeController,
                  decoration: const InputDecoration(labelText: 'เวลาที่เปิดให้บริการ(เช่น 08:00-20:00)'),
                ),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดเพิ่มเติม',
                    hintText: 'กรอกรายละเอียดเพิ่มเติมเกี่ยวกับที่จอดรถ',
                  ),
                  maxLines: null, // Allow multi-line input
                ),
                ElevatedButton(
                  onPressed: _isImagePickerActive
                      ? null // Disable button if ImagePicker is active
                      : () async {
                          setState(() {
                            _isImagePickerActive = true;
                          });

                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(source: ImageSource.gallery);

                          if (image != null) {
                            try {
                              // Upload image to Firebase Storage
                              final storageRef = FirebaseStorage.instance
                                  .ref()
                                  .child('parking_images/${image.name}');
                              final uploadTask = await storageRef.putFile(File(image.path));

                              // Get the download URL
                              final imageUrl = await uploadTask.ref.getDownloadURL();

                              // Save the image URL to Firestore
                              await FirebaseFirestore.instance.collection('parking_slots').add({
                                'name': nameController.text,
                                'type': vehicleType,
                                'car_count': int.tryParse(carCountController.text) ?? 0,
                                'bike_count': int.tryParse(bikeCountController.text) ?? 0,
                                'car_price': int.tryParse(carPriceController.text) ?? 0,
                                'bike_price': int.tryParse(bikePriceController.text) ?? 0,
                                'service_date': dateController.text,
                                'service_time': timeController.text,
                                'details': detailsController.text, // Save additional details
                                'image_url': imageUrl, // Save the image URL
                                'timestamp': FieldValue.serverTimestamp(),
                              });

                              // Clear the input fields and close the dialog
                              Navigator.pop(context);
                              nameController.clear();
                              carCountController.clear();
                              bikeCountController.clear();
                              carPriceController.clear();
                              bikePriceController.clear();
                              dateController.clear();
                              timeController.clear();
                              detailsController.clear(); // Clear the additional details controller
                              vehicleType = '';
                            } catch (e) {
                              // Show an error message if something goes wrong
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                              );
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
                  onPressed: () {
                    // TODO: ปักหมุดสถานที่
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
                    await FirebaseFirestore.instance.collection('parking_slots').add({
                      'name': nameController.text,
                      'type': vehicleType,
                      'car_count': int.tryParse(carCountController.text) ?? 0,
                      'bike_count': int.tryParse(bikeCountController.text) ?? 0,
                      'car_price': int.tryParse(carPriceController.text) ?? 0,
                      'bike_price': int.tryParse(bikePriceController.text) ?? 0,
                      'service_date': dateController.text,
                      'service_time': timeController.text,
                      'details': detailsController.text, // Save additional details
                      'timestamp': FieldValue.serverTimestamp(),
                    });

                    // Clear the input fields and close the dialog
                    Navigator.pop(context);
                    nameController.clear();
                    carCountController.clear();
                    bikeCountController.clear();
                    carPriceController.clear();
                    bikePriceController.clear();
                    dateController.clear();
                    timeController.clear();
                    detailsController.clear(); // Clear the additional details controller
                    vehicleType = '';
                  } catch (e) {
                    // Show an error message if something goes wrong
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                    );
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
}

class ParkingDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const ParkingDetailScreen({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(data['name'] ?? 'รายละเอียดที่จอดรถ'),
      ),
      body: Padding(
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
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
            Text('ราคาที่จอดมอเตอร์ไซค์: ${data['bike_price'] ?? 0} บาท/ชั่วโมง\n'),
            const SizedBox(height: 5),
            Text('วันที่เปิดให้บริการ: ${data['service_date'] ?? 'ไม่มีข้อมูล'}'),
            const SizedBox(height: 5),
            Text('เวลาที่เปิดให้บริการ: ${data['service_time'] ?? 'ไม่มีข้อมูล'}'),
            const SizedBox(height: 20),
            Text(
              'รายละเอียดเพิ่มเติม:',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text('${data['details'] ?? 'ไม่มีข้อมูล'}'),
          ],
        ),
      ),
    );
  }
}
