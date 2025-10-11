import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResiduosAprovechablesPage extends StatefulWidget {
  const ResiduosAprovechablesPage({super.key});

  @override
  State<ResiduosAprovechablesPage> createState() =>
      _ResiduosAprovechablesPageState();
}

class _ResiduosAprovechablesPageState extends State<ResiduosAprovechablesPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<dynamic> _residuos = [];

  @override
  void initState() {
    super.initState();
    _cargarResiduos();
  }

  Future<void> _cargarResiduos() async {
    try {
      final data = await supabase
          .from('remocion_reciclaje')
          .select('id, kg, factor_kgco2e, tco2e_ev, periodo(ano, mes)')
          .order('id');

      setState(() {
        _residuos = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando residuos: $e");
      setState(() {
        _loading = false;
        _residuos = [];
      });
    }
  }

  Future<void> _agregarResiduo() async {
    final kgCtrl = TextEditingController();
    final incertidumbreDatoCtrl = TextEditingController();
    final incertidumbreFuenteCtrl = TextEditingController();
    int? periodoId;

    final periodos = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano');

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text("Registrar residuos aprovechables"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: kgCtrl,
                        decoration: const InputDecoration(
                          labelText: "Cantidad (kg residuos)",
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      TextField(
                        controller: incertidumbreDatoCtrl,
                        decoration: const InputDecoration(
                          labelText: "Incertidumbre datos de actividad (%)",
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      TextField(
                        controller: incertidumbreFuenteCtrl,
                        decoration: const InputDecoration(
                          labelText: "Incertidumbre fuente (%)",
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: periodoId,
                        hint: const Text("Selecciona un periodo"),
                        items: [
                          for (var p in periodos)
                            DropdownMenuItem(
                              value: p['id'],
                              child: Text("${p['ano']}-${p['mes']}"),
                            ),
                        ],
                        onChanged: (v) => setState(() => periodoId = v),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancelar"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        final kg = double.tryParse(kgCtrl.text) ?? 0;

                        // 🔹 Factor fijo oficial (kg CO2e por kg de residuo aprovechable)
                        const factor = 0.001296;
                        final tco2e = kg * factor;

                        await supabase.from('remocion_reciclaje').insert({
                          'material': 'residuos_aprovechables',
                          'kg': kg,
                          'factor_kgco2e': factor,
                          'tco2e_ev': tco2e,
                          'periodo_id': periodoId,
                          'incertidumbre_dato':
                              double.tryParse(incertidumbreDatoCtrl.text) ?? 0,
                          'incertidumbre_fuente':
                              double.tryParse(incertidumbreFuenteCtrl.text) ??
                              0,
                        });

                        Navigator.pop(context);
                        _cargarResiduos();
                      } catch (e) {
                        debugPrint("❌ Error insertando residuo: $e");
                      }
                    },
                    child: const Text("Guardar"),
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
      appBar: AppBar(title: const Text("Residuos Aprovechables")),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _residuos.isEmpty
              ? const Center(child: Text("No hay residuos registrados"))
              : ListView.builder(
                itemCount: _residuos.length,
                itemBuilder: (context, index) {
                  final r = _residuos[index];
                  return Card(
                    margin: const EdgeInsets.all(8),
                    child: ListTile(
                      title: Text("Residuos aprovechables - ${r['kg']} kg"),
                      subtitle: Text(
                        "Periodo: ${r['periodo']?['ano'] ?? ''}-${r['periodo']?['mes'] ?? ''}\n"
                        "Factor: ${r['factor_kgco2e']} kgCO₂e\n"
                        "Total evitado: ${r['tco2e_ev']} tCO₂e\n"
                        "Incert. dato: ${r['incertidumbre_dato']}%\n"
                        "Incert. fuente: ${r['incertidumbre_fuente']}%",
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarResiduo,
        child: const Icon(Icons.add),
      ),
    );
  }
}
