import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ViajesAereosPage extends StatefulWidget {
  const ViajesAereosPage({super.key});

  @override
  State<ViajesAereosPage> createState() => _ViajesAereosPageState();
}

class _ViajesAereosPageState extends State<ViajesAereosPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _viajes = [];

  static const List<String> kTiposVuelo = ['Ida y regreso', 'Un trayecto'];
  static const String kUnidadFija = 'Viaje';

  @override
  void initState() {
    super.initState();
    _cargarViajes();
  }

  Future<void> _cargarViajes() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('viajes_aereos')
          .select(
            'id, viaje, tipo_vuelo, unidad, pasajeros, distancia_km, '
            'emisiones_tco2e, incertidumbre_dato, incertidumbre_fuente, '
            'periodo(ano, mes)',
          )
          .order('id');

      final rows = List<Map<String, dynamic>>.from(data as List);
      setState(() {
        _viajes = rows;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando viajes: $e");
      setState(() {
        _viajes = [];
        _loading = false;
      });
    }
  }

  // ---------- Cálculo ----------
  double? _calcTco2e({
    required double distanciaKm,
    required int pasajeros,
    required double? factorKgCo2ePorPaxKm,
  }) {
    if (distanciaKm <= 0 ||
        pasajeros <= 0 ||
        (factorKgCo2ePorPaxKm ?? 0) <= 0) {
      return null;
    }
    final paxKm = distanciaKm * pasajeros;
    return (paxKm * factorKgCo2ePorPaxKm!) / 1000.0; // a toneladas
  }

  /// Busca factor (kg CO2e/pax-km) por tipo de vuelo
  Future<double?> _buscarFactorPaxKm(String tipoVuelo) async {
    try {
      // 1) exacto: "Viajes aéreos - {tipo}"
      final data1 = await supabase
          .from('factor_emision')
          .select(
            'valor, vigente_desde, unidad_medida(codigo), fuente_emision(subtipo)',
          )
          .eq('unidad_medida.codigo', 'pax-km')
          .eq('fuente_emision.subtipo', 'Viajes aéreos - $tipoVuelo')
          .order('vigente_desde', ascending: false)
          .limit(1);

      final rows1 = List<Map<String, dynamic>>.from(data1 as List);
      if (rows1.isNotEmpty) {
        final r = rows1.first;
        return (r['valor'] as num?)?.toDouble();
      }

      // 2) laxo: que contenga ambos fragmentos
      final data2 = await supabase
          .from('factor_emision')
          .select(
            'valor, vigente_desde, unidad_medida(codigo), fuente_emision(subtipo)',
          )
          .eq('unidad_medida.codigo', 'pax-km')
          .ilike('fuente_emision.subtipo', '%Viajes aéreos%$tipoVuelo%')
          .order('vigente_desde', ascending: false)
          .limit(1);

      final rows2 = List<Map<String, dynamic>>.from(data2 as List);
      if (rows2.isNotEmpty) {
        final r = rows2.first;
        return (r['valor'] as num?)?.toDouble();
      }
    } catch (e) {
      debugPrint('❌ Error buscando factor pax-km: $e');
    }
    return null;
  }

  Future<void> _agregarViaje() async {
    final viajeCtrl = TextEditingController();
    final pasajerosCtrl = TextEditingController(text: '1');
    final distanciaCtrl = TextEditingController();
    final incDatoCtrl = TextEditingController(text: '0.50');
    final incFuenteCtrl = TextEditingController(text: '5.025');

    int? periodoId;
    String tipoVuelo = kTiposVuelo.first;
    double? factorPaxKm;
    double? tco2ePreview;

    final dataPeriodos = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano');

    final periodos = List<Map<String, dynamic>>.from(dataPeriodos as List);

    // Evita usar context si el widget fue desmontado tras el await de arriba
    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setStateDialog) {
              Future<void> buscarFactor() async {
                final f = await _buscarFactorPaxKm(tipoVuelo);
                setStateDialog(() {
                  factorPaxKm = f;
                  final d = double.tryParse(distanciaCtrl.text.trim()) ?? 0;
                  final p = int.tryParse(pasajerosCtrl.text.trim()) ?? 0;
                  tco2ePreview = _calcTco2e(
                    distanciaKm: d,
                    pasajeros: p,
                    factorKgCo2ePorPaxKm: factorPaxKm,
                  );
                });
              }

              // Traer factor al abrir
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (factorPaxKm == null) buscarFactor();
              });

              // Recalcular helper
              void recalcular() {
                final d = double.tryParse(distanciaCtrl.text.trim()) ?? 0;
                final p = int.tryParse(pasajerosCtrl.text.trim()) ?? 0;
                setStateDialog(() {
                  tco2ePreview = _calcTco2e(
                    distanciaKm: d,
                    pasajeros: p,
                    factorKgCo2ePorPaxKm: factorPaxKm,
                  );
                });
              }

              final guardarDeshabilitado =
                  periodoId == null ||
                  viajeCtrl.text.trim().isEmpty ||
                  distanciaCtrl.text.trim().isEmpty ||
                  pasajerosCtrl.text.trim().isEmpty ||
                  factorPaxKm == null ||
                  tco2ePreview == null;

              return AlertDialog(
                title: const Text('Registrar viaje aéreo'),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                    maxWidth: MediaQuery.of(context).size.width * 0.95,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Periodo
                        DropdownButtonFormField<int>(
                          value: periodoId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Periodo *',
                          ),
                          items:
                              periodos
                                  .map(
                                    (p) => DropdownMenuItem<int>(
                                      value: p['id'] as int,
                                      child: Text('${p['ano']}-${p['mes']}'),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setStateDialog(() => periodoId = v),
                        ),
                        const SizedBox(height: 12),

                        // Viaje
                        TextField(
                          controller: viajeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Viaje *',
                            hintText: 'Ej.: Bogotá - Río de Janeiro',
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tipo de vuelo (cambia factor)
                        DropdownButtonFormField<String>(
                          value: tipoVuelo,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de vuelo *',
                          ),
                          items:
                              kTiposVuelo
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            setStateDialog(
                              () => tipoVuelo = v ?? kTiposVuelo.first,
                            );
                            buscarFactor();
                          },
                        ),
                        const SizedBox(height: 12),

                        // Unidad (fija) + Pasajeros
                        Row(
                          children: [
                            const Expanded(
                              flex: 2,
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Unidad',
                                ),
                                child: Text(kUnidadFija),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: pasajerosCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: false,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'No. de pasajeros *',
                                ),
                                onChanged: (_) => recalcular(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Distancia (km)
                        TextField(
                          controller: distanciaCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Distancia (km) *',
                          ),
                          onChanged: (_) => recalcular(),
                        ),
                        const SizedBox(height: 12),

                        // Factor y resultado
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                factorPaxKm == null
                                    ? 'Factor: no encontrado'
                                    : 'Factor: ${factorPaxKm!.toStringAsFixed(6)} kg CO₂e/pax-km',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      factorPaxKm == null
                                          ? Colors.red
                                          : Colors.green[700],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Buscar factor en BD',
                              onPressed: buscarFactor,
                              icon: const Icon(Icons.search),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            tco2ePreview == null
                                ? 'Emisiones totales: —'
                                : 'Emisiones totales: ${tco2ePreview!.toStringAsFixed(6)} t CO₂e',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  tco2ePreview == null
                                      ? Colors.red
                                      : Colors.green[700],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Incertidumbres
                        TextField(
                          controller: incDatoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText:
                                'Incertidumbre por datos de actividad (%)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: incFuenteCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Incertidumbre de la fuente (%)',
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
                    onPressed:
                        guardarDeshabilitado
                            ? null
                            : () async {
                              final pasajeros =
                                  int.tryParse(pasajerosCtrl.text.trim()) ?? 0;
                              final distancia =
                                  double.tryParse(distanciaCtrl.text.trim()) ??
                                  0.0;
                              final incDato =
                                  double.tryParse(incDatoCtrl.text.trim()) ??
                                  0.0;
                              final incFuente =
                                  double.tryParse(incFuenteCtrl.text.trim()) ??
                                  0.0;

                              try {
                                await supabase.from('viajes_aereos').insert({
                                  'periodo_id': periodoId,
                                  'viaje': viajeCtrl.text.trim(),
                                  'tipo_vuelo': tipoVuelo,
                                  'unidad': kUnidadFija,
                                  'pasajeros': pasajeros,
                                  'distancia_km': distancia,
                                  'emisiones_tco2e': tco2ePreview, // calculada
                                  'incertidumbre_dato': incDato,
                                  'incertidumbre_fuente': incFuente,
                                });

                                if (mounted) Navigator.pop(context);
                                await _cargarViajes();
                              } catch (e) {
                                debugPrint('❌ Error insertando viaje: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(SnackBar(content: Text('$e')));
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

  // ---------- UI listado ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Viajes Aéreos')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _viajes.isEmpty
              ? const Center(child: Text('No hay viajes registrados'))
              : ListView.builder(
                itemCount: _viajes.length,
                itemBuilder: (context, index) {
                  final v = _viajes[index];
                  final periodo =
                      "${v['periodo']?['ano'] ?? ''}-${v['periodo']?['mes'] ?? ''}";
                  final em = (v['emisiones_tco2e'] as num?)?.toDouble();

                  return Card(
                    margin: const EdgeInsets.all(8),
                    child: ListTile(
                      title: Text(
                        v['viaje'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "Tipo de vuelo: ${v['tipo_vuelo'] ?? '-'}\n"
                        "Unidad: ${v['unidad'] ?? 'Viaje'}\n"
                        "No. de pasajeros: ${v['pasajeros'] ?? 0}\n"
                        "Emisiones totales: ${em?.toStringAsFixed(6) ?? '-'} t CO₂e\n"
                        "Incertidumbre (dato): ${v['incertidumbre_dato'] ?? 0}%\n"
                        "Incertidumbre (fuente): ${v['incertidumbre_fuente'] ?? 0}%\n"
                        "Periodo: $periodo",
                      ),
                      // trailing: Text("${v['distancia_km'] ?? 0} km"),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarViaje,
        child: const Icon(Icons.add),
      ),
    );
  }
}
