import 'package:flutter/material.dart';
import 'package:projectapp/screen/login.dart';
import 'package:projectapp/screen/register.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Register/Login"),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(10, 50, 10, 0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset("assets/images/logo.png"),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.add),
                  label:
                      Text("สร้างบัญชีผู้ใช้", style: TextStyle(fontSize: 20)),
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => RegisterScreen()),
                      (Route<dynamic> route) => false,
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.login),
                  label: Text("เข้าสู่ระบบ", style: TextStyle(fontSize: 20)),
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => LoginScreen()),
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
