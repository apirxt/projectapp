import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:projectapp/model/profile.dart';
import 'package:projectapp/screen/main_screen.dart';

import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  Profile profile = Profile();
  final Future<FirebaseApp> firebase = Firebase.initializeApp();
  String? emailError;
  String? passwordError;

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
                  title: const Text("เข้าสู่ระบบ"),
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
                          const Text("อีเมล", style: TextStyle(fontSize: 20)),
                          TextFormField(
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "กรุณาป้อนอีเมลด้วยครับ";
                              }
                              return null;
                            },
                            keyboardType: TextInputType.emailAddress,
                            onSaved: (String? email) {
                              profile.email = email!;
                            },
                            decoration: InputDecoration(
                              errorText: emailError,
                            ),
                          ),
                          const SizedBox(
                            height: 15,
                          ),
                          const Text("รหัสผ่าน",
                              style: TextStyle(fontSize: 20)),
                          TextFormField(
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "กรุณาป้อนรหัสผ่านด้วยครับ";
                              }
                              return null;
                            },
                            obscureText: true,
                            onSaved: (String? password) {
                              profile.password = password!;
                            },
                            decoration: InputDecoration(
                              errorText: passwordError,
                            ),
                          ),
                          const SizedBox(height: 50),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              child: const Text("เข้าสู่ระบบ",
                                  style: TextStyle(fontSize: 20)),
                              onPressed: () async {
                                if (formKey.currentState!.validate()) {
                                  formKey.currentState!.save();
                                  try {
                                    await FirebaseAuth.instance
                                        .signInWithEmailAndPassword(
                                            email: profile.email!,
                                            password: profile.password!);
                                    // refresh token to get latest custom claims for rules/UI
                                    await FirebaseAuth.instance.currentUser
                                        ?.getIdToken(true);
                                    if (!context.mounted) return;
                                    formKey.currentState!.reset();
                                    Fluttertoast.showToast(
                                        msg: "เข้าสู่ระบบสำเร็จ",
                                        gravity: ToastGravity.CENTER);
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const MainScreen()),
                                    );
                                  } on FirebaseAuthException catch (e) {
                                    setState(() {
                                      emailError = null;
                                      passwordError = null;
                                      if (e.code == 'user-not-found' ||
                                          e.code == 'invalid-email') {
                                        emailError = e.code == 'user-not-found'
                                            ? "ไม่พบบัญชีผู้ใช้นี้"
                                            : "รูปแบบอีเมลไม่ถูกต้อง";
                                      } else if (e.code == 'wrong-password') {
                                        passwordError = "รหัสผ่านไม่ถูกต้อง";
                                      } else {
                                        emailError = null;
                                        passwordError =
                                            "เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง";
                                      }
                                    });
                                    Fluttertoast.showToast(
                                        msg: emailError ??
                                            passwordError ??
                                            "เกิดข้อผิดพลาด",
                                        gravity: ToastGravity.CENTER);
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
