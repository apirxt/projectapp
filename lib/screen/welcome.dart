//ส่วนนำเข้าแพ็กเกจ
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'home.dart';

//ส่วนหน้ายินดีต้อนรับหลังเข้าสู่ระบบ
class WelcomeScreen extends StatelessWidget {
  WelcomeScreen({super.key});

  final auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ยินดีต้อนรับ"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Center(
          child: Column(
            children: [
              //ส่วนแสดงอีเมลผู้ใช้ปัจจุบัน
              Text(
                auth.currentUser?.email ?? "ไม่มีข้อมูลผู้ใช้",
                style: const TextStyle(fontSize: 25),
              ),
              //ส่วนปุ่มออกจากระบบ
              ElevatedButton(
                child: const Text("ออกจากระบบ"),
                onPressed: () async {
                  await auth.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                    (Route<dynamic> route) => false,
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}
