import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kInk = Color(0xFF1A1A1A);
const kInk2 = Color(0xFF31302E);
const kMut = Color(0xFF615D59);
const kFaint = Color(0xFFA39E98);
const kCanvas = Color(0xFFF6F5F4);
const kSurf = Color(0xFFFFFFFF);
const kHair = Color(0xFFE6E6E6);
const kGreen = Color(0xFF1AAE39);
const kTeal = Color(0xFF2A9D99);
const kOrange = Color(0xFFDD5B00);
const kRed = Color(0xFFE03E3E);
const kIndigo = Color(0xFF213183);
const kAccent = Color(0xFF0075DE);

ThemeData buildRadarTheme() => ThemeData(
      scaffoldBackgroundColor: kCanvas,
      colorScheme: ColorScheme.fromSeed(seedColor: kAccent, surface: kSurf),
      useMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: Brightness.light).textTheme,
      ),
    );
