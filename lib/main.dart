//ส่วนนำเข้าแพ็กเกจ
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:projectapp/screen/home.dart';
import 'package:projectapp/screen/main_screen.dart';

//ส่วนเริ่มต้นแอป
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); //ส่วนเริ่มต้น Firebase
  runApp(const MyApp());
}

//ส่วนวิดเจ็ตหลักของแอป
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      theme: ThemeData.dark(),
  //ส่วนหน้าแรกตามสถานะล็อกอิน
      home: FirebaseAuth.instance.currentUser == null ? HomeScreen() : MainScreen(),

    );
  }
}