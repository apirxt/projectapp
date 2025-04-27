import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:projectapp/screen/home.dart';
import 'package:projectapp/screen/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Initialize Firebase
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      theme: ThemeData.dark(),
      // Check if the user is logged in. If not, show HomeScreen, otherwise show WelcomeScreen.
      home: FirebaseAuth.instance.currentUser == null ? HomeScreen() : MainScreen(),

    );
  }
}