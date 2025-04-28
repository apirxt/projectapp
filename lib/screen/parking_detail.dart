import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ParkingDetail extends StatelessWidget {
  final Map<String, dynamic> parkingData;

  const ParkingDetail({Key? key, required this.parkingData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final location = parkingData['location'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(parkingData['name'] ?? 'รายละเอียดที่จอดรถ'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parkingData['image_url'] != null && parkingData['image_url'].isNotEmpty)
                Center(
                  child: Image.network(
                    parkingData['image_url'],
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'ที่จอดรถ: ${parkingData['name'] ?? 'ไม่มีข้อมูล'}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text('ประเภท: ${parkingData['type'] ?? 'ไม่มีข้อมูล'}\n'),
              const SizedBox(height: 5),
              Text('จำนวนรถยนต์: ${parkingData['car_count'] ?? 0}'),
              const SizedBox(height: 5),
              Text('ราคาที่จอดรถยนต์: ${parkingData['car_price'] ?? 0} บาท/ชั่วโมง\n'),
              const SizedBox(height: 5),
              Text('จำนวนมอเตอร์ไซค์: ${parkingData['bike_count'] ?? 0}'),
              const SizedBox(height: 5),
              Text('ราคาที่จอดมอเตอร์ไซค์: ${parkingData['bike_price'] ?? 0} บาท/ชั่วโมง\n'),
              const SizedBox(height: 5),
              Text('วันที่เปิดให้บริการ: ${parkingData['service_date'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 5),
              Text('เวลาที่เปิดให้บริการ: ${parkingData['service_time'] ?? 'ไม่มีข้อมูล'}'),
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
                        infoWindow: InfoWindow(title: parkingData['name'] ?? 'ที่จอดรถ'),
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
              const Text(
                'รายละเอียดเพิ่มเติม:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(parkingData['details'] ?? 'ไม่มีข้อมูลเพิ่มเติม'),
            ],
          ),
        ),
      ),
    );
  }
}