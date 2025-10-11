import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestConnectionPage extends StatefulWidget {
  const TestConnectionPage({super.key});

  @override
  State<TestConnectionPage> createState() => _TestConnectionPageState();
}

class _TestConnectionPageState extends State<TestConnectionPage> {
  final supabase = Supabase.instance.client;
  String _resultado = "Presiona el botón para probar la conexión";

  Future<void> _probarConexion() async {
    try {
      // Probar leyendo la tabla periodo
      final data = await supabase.from('periodo').select().limit(1);
      setState(() {
        _resultado = "✅ Conectado! Ejemplo: $data";
      });
    } catch (e) {
      setState(() {
        _resultado = "❌ Error de conexión: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Probar Conexión")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _resultado,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _probarConexion,
              icon: const Icon(Icons.wifi),
              label: const Text("Probar conexión"),
            ),
          ],
        ),
      ),
    );
  }
}
