//ส่วนนำเข้าแพ็กเกจ
import 'package:flutter/material.dart';
import 'package:projectapp/screen/login.dart';
import 'package:projectapp/screen/register.dart';

//ส่วนหน้าแรก (ปุ่มไปลงทะเบียน/เข้าสู่ระบบ)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Register/Login"),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(10, 50, 10, 0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset("assets/images/logo.png"),
              //ส่วนปุ่มไปหน้าลงทะเบียน
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text("สร้างบัญชีผู้ใช้",
                      style: TextStyle(fontSize: 20)),
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (context) => const RegisterScreen()),
                      (Route<dynamic> route) => false,
                    );
                  },
                ),
              ),
              //ส่วนปุ่มไปหน้าเข้าสู่ระบบ
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label:
                      const Text("เข้าสู่ระบบ", style: TextStyle(fontSize: 20)),
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                      (Route<dynamic> route) => false,
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
