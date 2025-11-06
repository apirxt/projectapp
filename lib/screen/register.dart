//ส่วนนำเข้าแพ็กเกจ
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:form_field_validator/form_field_validator.dart';
import 'package:projectapp/model/profile.dart';

import 'home.dart';

//ส่วนหน้าสร้างบัญชีผู้ใช้
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  //ส่วนสถานะฟอร์มและข้อมูลผู้สมัคร
  final formKey = GlobalKey<FormState>();
  Profile profile = Profile();
  final Future<FirebaseApp> firebase = Firebase.initializeApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: firebase,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(
                title: Text("Error"),
              ),
              body: Center(
                child: Text("${snapshot.error}"),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.done) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (Route<dynamic> route) => false,
                );
              },
              child: Scaffold(
                appBar: AppBar(
                  title: const Text("สร้างบัญชีผู้ใช้"),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (context) => const HomeScreen()),
                        (Route<dynamic> route) => false,
                      );
                    },
                  ),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          //ส่วนช่องกรอกชื่อผู้ใช้
                          const Text("ชื่อผู้ใช้",
                              style: TextStyle(fontSize: 20)),
                          TextFormField(
                            validator: RequiredValidator(
                                    errorText: "กรุณาป้อนชื่อผู้ใช้ด้วยครับ")
                                .call,
                            textInputAction: TextInputAction.next,
                            onSaved: (String? name) {
                              profile.displayName = name?.trim();
                            },
                          ),
                          const SizedBox(height: 15),
                          //ส่วนช่องกรอกอีเมล
                          const Text("อีเมล", style: TextStyle(fontSize: 20)),
                          TextFormField(
                            validator: MultiValidator([
                              RequiredValidator(
                                  errorText: "กรุณาป้อนอีเมลด้วยครับ"),
                              EmailValidator(errorText: "รูปแบบอีเมลไม่ถูกต้อง")
                            ]).call,
                            keyboardType: TextInputType.emailAddress,
                            onSaved: (String? email) {
                              profile.email = email!;
                            },
                          ),
                          const SizedBox(
                            height: 15,
                          ),
                          //ส่วนช่องกรอกรหัสผ่าน
                          const Text("รหัสผ่าน",
                              style: TextStyle(fontSize: 20)),
                          TextFormField(
                            validator: RequiredValidator(
                                    errorText: "กรุณาป้อนรหัสผ่านด้วยครับ")
                                .call,
                            obscureText: true,
                            onSaved: (String? password) {
                              profile.password = password!;
                            },
                          ),
                          const SizedBox(height: 50),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              child: const Text("ลงทะเบียน",
                                  style: TextStyle(fontSize: 20)),
                              onPressed: () async {
                                //ส่วนกระบวนการลงทะเบียน
                                if (formKey.currentState!.validate()) {
                                  formKey.currentState!.save();
                                  try {
                                    final cred = await FirebaseAuth.instance
                                        .createUserWithEmailAndPassword(
                                            email: profile.email!,
                                            password: profile.password!);
                                    // ตั้งชื่อผู้ใช้ไปที่โปรไฟล์ Auth
                                    if (profile.displayName != null &&
                                        profile.displayName!.isNotEmpty) {
                                      await cred.user?.updateDisplayName(
                                          profile.displayName!.trim());
                                      await cred.user?.reload();
                                    }
                                    if (!context.mounted) return;
                                    formKey.currentState!.reset();
                                    Fluttertoast.showToast(
                                        msg: "สร้างบัญชีผู้ใช้เรียบร้อยแล้ว",
                                        gravity: ToastGravity.TOP);
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const HomeScreen()),
                                    );
                                  } on FirebaseAuthException catch (e) {
                                    setState(() {
                                      String message;
                                      if (e.code == 'email-already-in-use') {
                                        message =
                                            "มีอีเมลนี้ในระบบแล้วครับ โปรดใช้อีเมลอื่นแทน";
                                      } else if (e.code == 'weak-password') {
                                        message =
                                            "รหัสผ่านต้องมีความยาว 6 ตัวอักษรขึ้นไป";
                                      } else {
                                        message = e.message ?? "เกิดข้อผิดพลาด";
                                      }
                                      Fluttertoast.showToast(
                                          msg: message,
                                          gravity: ToastGravity.CENTER,
                                          backgroundColor: Colors.red,
                                          textColor: Colors.white,
                                          fontSize: 16.0);
                                    });
                                  }
                                }
                              },
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return Scaffold(
            body: Center(
              child: const CircularProgressIndicator(),
            ),
          );
        });
  }
}
