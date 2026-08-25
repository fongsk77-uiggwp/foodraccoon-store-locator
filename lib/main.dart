import 'package:flutter/material.dart';

import 'screens/store_locator_screen.dart';

const foodRaccoonGreen = Color(0xFF0C4F3B);
const foodRaccoonBright = Color(0xFF129565);
const foodRaccoonSurface = Color(0xFFF5F8F6);

void main() {
  runApp(const FoodRaccoonApp());
}

class FoodRaccoonApp extends StatelessWidget {
  const FoodRaccoonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoodRaccoon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: foodRaccoonGreen,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: foodRaccoonSurface,
        appBarTheme: const AppBarTheme(
          backgroundColor: foodRaccoonSurface,
          foregroundColor: foodRaccoonGreen,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            side: BorderSide(color: Color(0xFFDCE9E2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: Color(0xFFDCE9E2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: Color(0xFFDCE9E2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: foodRaccoonBright, width: 1.5),
          ),
        ),
      ),
      home: const StoreLocatorScreen(),
    );
  }
}
