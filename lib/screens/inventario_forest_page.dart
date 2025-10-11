import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventarioForestPage extends StatefulWidget {
  const InventarioForestPage({super.key});

  @override
  State<InventarioForestPage> createState() => _InventarioForestPageState();
}

class _InventarioForestPageState extends State<InventarioForestPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _periodos = [];
  List<Map<String, dynamic>> _especies = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // ❌ quitamos la variable sin uso
      await Future.wait([
        _cargarRegistros(),
        _cargarPeriodos(),
        _cargarEspecies(),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargarRegistros() async {
    try {
      final data = await supabase
          .from('remocion_forestal')
          .select(
            'id, arboles, biomasa_t, tco2e_ev, periodo(ano, mes), '
            'especie_id, especies_arboles_ref(nombre)',
          )
          .order('id');
      _registros = List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      _registros = [];
      debugPrint('❌ Error cargando inventario forestal: $e');
    }
  }

  Future<void> _cargarPeriodos() async {
    try {
      final data = await supabase
          .from('periodo')
          .select('id, ano, mes')
          .order('ano')
          .order('mes');
      _periodos = List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      _periodos = [];
    }
  }

  Future<void> _cargarEspecies() async {
    try {
      final data = await supabase
          .from('especies_arboles_ref')
          .select('id, nombre')
          .order('nombre');
      _especies = List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      _especies = [];
    }
  }

  Future<void> _agregarRegistro() async {
    final arbolesCtrl = TextEditingController();
    final biomasaCtrl = TextEditingController();

    int? periodoId;
    int? especieId;
    double tco2Calc = 0.0;

    double _p(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0.0;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSt) {
              void recalcular() {
                final biomasa = _p(biomasaCtrl.text);
                tco2Calc = biomasa * 3.67; // Biomasa (t) * 3.67 = tCO2
                setSt(() {});
              }

              return AlertDialog(
                title: const Text('Registrar inventario forestal'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Especie
                      DropdownButtonFormField<int>(
                        value: especieId,
                        hint: const Text('Selecciona especie'),
                        items: [
                          for (final e in _especies)
                            DropdownMenuItem(
                              value: e['id'] as int,
                              child: Text(e['nombre'] as String),
                            ),
                        ],
                        onChanged: (v) => setSt(() => especieId = v),
                      ),
                      const SizedBox(height: 12),

                      // Número de individuos
                      TextField(
                        controller: arbolesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Número de individuos',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Biomasa
                      TextField(
                        controller: biomasaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Biomasa (t)',
                          helperText:
                              'Se usa tCO₂e = biomasa × 3.67 (si no tienes biomasa, deja 0)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => recalcular(),
                      ),
                      const SizedBox(height: 12),

                      // Emisiones (captura) calculadas
                      Row(
                        children: [
                          const Icon(Icons.eco, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Captura total: ${tco2Calc.toStringAsFixed(3)} t CO₂e',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Periodo
                      DropdownButtonFormField<int>(
                        value: periodoId,
                        hint: const Text('Periodo'),
                        items: [
                          for (final p in _periodos)
                            DropdownMenuItem(
                              value: p['id'] as int,
                              child: Text('${p['ano']}-${p['mes']}'),
                            ),
                        ],
                        onChanged: (v) => setSt(() => periodoId = v),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final arboles = int.tryParse(arbolesCtrl.text) ?? 0;
                      final biomasa = _p(biomasaCtrl.text);

                      if (especieId == null || periodoId == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Selecciona especie y periodo antes de guardar.',
                              ),
                            ),
                          );
                        }
                        return;
                      }

                      try {
                        await supabase.from('remocion_forestal').insert({
                          'arboles': arboles,
                          'especie_id': especieId,
                          'biomasa_t': biomasa,
                          'tco2e_ev': biomasa * 3.67,
                          'periodo_id': periodoId,
                        });

                        if (context.mounted) Navigator.pop(context);
                        await _cargarRegistros();
                        if (mounted) setState(() {});
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al guardar: $e')),
                          );
                        }
                      }
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              );
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventario forestal')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _registros.isEmpty
              ? const Center(child: Text('No hay registros'))
              : ListView.builder(
                itemCount: _registros.length,
                itemBuilder: (context, index) {
                  final r = _registros[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      title: Text(
                        r['especies_arboles_ref']?['nombre'] ?? 'Especie',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Individuos: ${r['arboles'] ?? 0}\n'
                        'Biomasa: ${r['biomasa_t'] ?? 0} t\n'
                        'Captura total: ${r['tco2e_ev'] ?? 0} t CO₂e\n'
                        'Periodo: ${r['periodo']?['ano'] ?? ''}-${r['periodo']?['mes'] ?? ''}',
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarRegistro,
        child: const Icon(Icons.add),
      ),
    );
  }
}
