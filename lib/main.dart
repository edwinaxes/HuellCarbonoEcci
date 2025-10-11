import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://oypebkvjahuqdbgzdipa.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im95cGVia3ZqYWh1cWRiZ3pkaXBhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc0NTA1NDQsImV4cCI6MjA3MzAyNjU0NH0.mShk78b08TlrmTwmVm6m7l0GAOSfuChmwdrr55B_ugQ',
    );
    runApp(const MyApp());
  } catch (e) {
    print('❌ Error inicializando Supabase: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Huella de Carbono',
      theme: _buildAppTheme(), // 🎨 Tema visual
      home: const HomePage(),
    );
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      useMaterial3: true, // usa Material Design 3
      primarySwatch: Colors.green,
      scaffoldBackgroundColor: const Color(0xFFF9FAFB), // fondo gris claro
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
        margin: const EdgeInsets.all(4),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Colors.black87, fontSize: 14),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color.fromARGB(255, 107, 210, 110),
        foregroundColor: Colors.white,
      ),
    );
  }
}
