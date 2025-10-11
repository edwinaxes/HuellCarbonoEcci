import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransportePersonasPage extends StatefulWidget {
  const TransportePersonasPage({super.key});

  @override
  State<TransportePersonasPage> createState() => _TransportePersonasPageState();
}

class _TransportePersonasPageState extends State<TransportePersonasPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  List<dynamic> _registros = [];
  List<dynamic> _periodos = [];

  double? _factorKgPorKm; // factor vigente (kgCO2e/km)
  String? _factorFuente; // info de versión/fuente

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _cargarFactorVigenteBus(),
      _cargarPeriodos(),
      _cargarRegistros(),
    ]);
    setState(() => _loading = false);
  }

  /// Factor vigente (kgCO2e/km) para "Transporte personas - Bus larga distancia"
  Future<void> _cargarFactorVigenteBus() async {
    try {
      final feRows = await supabase
          .from('fuente_emision')
          .select('id, subtipo')
          .eq('subtipo', 'Transporte personas - Bus larga distancia')
          .limit(1);

      if (feRows.isEmpty) {
        _factorKgPorKm = null;
        _factorFuente =
            'No existe fuente "Transporte personas - Bus larga distancia"';
        return;
      }
      final int fuenteId = feRows.first['id'] as int;

      final umRows = await supabase
          .from('unidad_medida')
          .select('id, codigo')
          .eq('codigo', 'km')
          .limit(1);
      if (umRows.isEmpty) {
        _factorKgPorKm = null;
        _factorFuente = 'No existe unidad de medida "km"';
        return;
      }
      final int unidadId = umRows.first['id'] as int;

      final facRows = await supabase
          .from('factor_emision')
          .select('valor, fuente_dato, version, vigente_desde')
          .eq('fuente_id', fuenteId)
          .eq('unidad_id', unidadId)
          .order('vigente_desde', ascending: false)
          .limit(1);

      if (facRows.isEmpty) {
        _factorKgPorKm = null;
        _factorFuente = 'No hay factor vigente para Bus larga distancia (km)';
      } else {
        final row = facRows.first;
        _factorKgPorKm = (row['valor'] as num).toDouble(); // kgCO2e/km
        _factorFuente =
            'v${row['version'] ?? ''} • ${row['fuente_dato'] ?? ''}'.trim();
      }
    } catch (e) {
      _factorKgPorKm = null;
      _factorFuente = 'Error cargando factor: $e';
    }
  }

  Future<void> _cargarPeriodos() async {
    try {
      final rows = await supabase
          .from('periodo')
          .select('id, ano, mes')
          .order('ano')
          .order('mes');
      _periodos = rows;
    } catch (e) {
      _periodos = [];
    }
  }

  Future<void> _cargarRegistros() async {
    try {
      final data = await supabase
          .from('transporte_personas')
          .select(
            'id, descripcion_fuente, medio_transporte, distancia_km, '
            'emisiones_tco2e, periodo(ano, mes)',
          )
          .order('id');
      _registros = data;
      setState(() {});
    } catch (e) {
      _registros = [];
    }
  }

  /// tCO2e = km * (kgCO2e/km) / 1000
  double _calcTco2e(double km) {
    if (_factorKgPorKm == null) return 0;
    return km * _factorKgPorKm! / 1000.0;
  }

  Future<void> _agregarRegistro() async {
    final descCtrl = TextEditingController();
    final kmCtrl = TextEditingController();

    int? periodoId;
    double km = 0;
    double tco2e = 0;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSt) {
              void recalc() {
                km = double.tryParse(kmCtrl.text.replaceAll(',', '.')) ?? 0;
                tco2e = _calcTco2e(km);
                setSt(() {});
              }

              return AlertDialog(
                title: const Text(
                  'Registrar transporte de personas (larga distancia)',
                ),
                content: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_factorKgPorKm == null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: Text(
                              _factorFuente ??
                                  'No hay factor vigente para Bus larga distancia.',
                              style: const TextStyle(color: Colors.red),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Text(
                              'Factor vigente: ${_factorKgPorKm!.toStringAsFixed(3)} kg CO₂e/km\n$_factorFuente',
                              style: const TextStyle(color: Colors.green),
                            ),
                          ),
                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Descripción de la fuente *',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: kmCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Distancia recorrida (km) *',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => recalc(),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int>(
                          value: periodoId,
                          hint: const Text('Selecciona un periodo *'),
                          items: [
                            for (final p in _periodos)
                              DropdownMenuItem(
                                value: p['id'] as int,
                                child: Text('${p['ano']}-${p['mes']}'),
                              ),
                          ],
                          onChanged: (v) {
                            periodoId = v;
                            setSt(() {});
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.cloud, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Emisiones: ${tco2e.toStringAsFixed(4)} t CO₂e',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Medio de transporte: Bus (larga distancia)',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (descCtrl.text.trim().isEmpty ||
                          (double.tryParse(kmCtrl.text.replaceAll(',', '.')) ??
                                  0) <=
                              0 ||
                          periodoId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Completa los campos obligatorios (*)',
                            ),
                          ),
                        );
                        return;
                      }
                      if (_factorKgPorKm == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No hay factor vigente para Bus larga distancia.',
                            ),
                          ),
                        );
                        return;
                      }

                      try {
                        final distanciaKm =
                            double.tryParse(kmCtrl.text.replaceAll(',', '.')) ??
                            0;
                        final emisT = _calcTco2e(distanciaKm);

                        await supabase.from('transporte_personas').insert({
                          'descripcion_fuente': descCtrl.text.trim(),
                          'medio_transporte': 'Bus larga distancia',
                          'distancia_km': distanciaKm,
                          'periodo_id': periodoId,
                          'unidad':
                              'km', // tu tabla la trae por defecto, pero no estorba
                          // 👇 ahora sí se guarda para que Reportes lo sume
                          'emisiones_tco2e': emisT,
                          // las incertidumbres NO influyen en cálculos (si quieres guardarlas, añade aquí)
                          // 'incertidumbre_dato': 0,
                          // 'incertidumbre_fuente': 0,
                        });

                        if (context.mounted) Navigator.pop(context);
                        await _cargarRegistros();
                        setState(() {});
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error guardando: $e')),
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
    final factorOk = _factorKgPorKm != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transporte de Personas (Larga distancia)'),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _registros.isEmpty
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.directions_bus,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      const Text('No hay registros'),
                      const SizedBox(height: 12),
                      if (!factorOk)
                        Text(
                          _factorFuente ??
                              'No hay factor vigente para Bus larga distancia.',
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              )
              : ListView.builder(
                itemCount: _registros.length,
                itemBuilder: (context, index) {
                  final r = _registros[index];
                  final km = (r['distancia_km'] as num?)?.toDouble() ?? 0.0;
                  final tco2eGuardado =
                      (r['emisiones_tco2e'] as num?)?.toDouble() ?? 0.0;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.directions_bus),
                      title: Text(r['descripcion_fuente'] ?? ''),
                      subtitle: Text(
                        'Medio: ${r['medio_transporte'] ?? 'Bus'}\n'
                        'Distancia: ${km.toStringAsFixed(2)} km\n'
                        'Periodo: ${r['periodo']?['ano'] ?? ''}-${r['periodo']?['mes'] ?? ''}\n'
                        'Emisiones: ${tco2eGuardado.toStringAsFixed(4)} t CO₂e',
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
