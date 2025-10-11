import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransporteEmpleadosPage extends StatefulWidget {
  const TransporteEmpleadosPage({super.key});

  @override
  State<TransporteEmpleadosPage> createState() =>
      _TransporteEmpleadosPageState();
}

class _TransporteEmpleadosPageState extends State<TransporteEmpleadosPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<dynamic> _registros = [];

  @override
  void initState() {
    super.initState();
    _cargarRegistros();
  }

  Future<void> _cargarRegistros() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('desplazamientos_empleados')
          .select(
            'id, descripcion_fuente, medio_transporte, distancia_km, frecuencia, '
            'unidad, emisiones_tco2e, incertidumbre_dato, incertidumbre_fuente, '
            'periodo(ano, mes)',
          )
          .order('id');
      setState(() {
        _registros = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando transporte empleados: $e");
      setState(() {
        _registros = [];
        _loading = false;
      });
    }
  }

  // ----- Helpers para factores -----
  // Mapea el texto del dropdown al subtipo usado en fuente_emision.subtipo
  String _subtipoPorMedio(String medio) {
    switch (medio) {
      case 'Motocicleta':
        return 'Transporte empleados - Motocicleta';
      case 'Carro/taxi':
        return 'Transporte empleados - Carro/taxi';
      case 'Bus / SITP / Intermunicipal':
        return 'Transporte empleados - Bus/SITP/intermunicipal';
      case 'TransMilenio (BRT)':
        return 'Transporte empleados - TransMilenio';
      default:
        return ''; // no debería ocurrir
    }
  }

  // Obtiene el factor (kgCO2e/pkm) para el medio seleccionado.
  // Hace 3 consultas simples para evitar joins complicados.
  Future<double?> _getFactorPKM(String medio) async {
    try {
      final subtipo = _subtipoPorMedio(medio);
      if (subtipo.isEmpty) return null;

      final fuente =
          await supabase
              .from('fuente_emision')
              .select('id')
              .eq('subtipo', subtipo)
              .limit(1)
              .maybeSingle();

      if (fuente == null || fuente['id'] == null) return null;
      final fuenteId = fuente['id'] as int;

      final um =
          await supabase
              .from('unidad_medida')
              .select('id')
              .eq('codigo', 'pkm')
              .limit(1)
              .maybeSingle();

      if (um == null || um['id'] == null) return null;
      final umId = um['id'] as int;

      final factorRow =
          await supabase
              .from('factor_emision')
              .select('valor, vigente_desde')
              .eq('fuente_id', fuenteId)
              .eq('unidad_id', umId)
              .order('vigente_desde', ascending: false)
              .limit(1)
              .maybeSingle();

      if (factorRow == null) return null;
      final v = factorRow['valor'];
      if (v == null) return null;
      return (v as num).toDouble(); // kgCO2e/pkm
    } catch (e) {
      debugPrint('❌ Error obteniendo factor pkm: $e');
      return null;
    }
  }

  Future<void> _agregarRegistro() async {
    // Controladores
    final descCtrl = TextEditingController();
    final distanciaCtrl = TextEditingController();
    final frecuenciaCtrl = TextEditingController(text: '1');
    final incDatoCtrl = TextEditingController();
    final incFuenteCtrl = TextEditingController();

    // Estado del diálogo
    int? periodoId;
    String? medio; // opciones fijas
    double? factorPKM; // kgCO2e/pkm
    double emisionesT = 0.0; // tCO2e calculado

    // Cargar periodos
    final periodos = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano')
        .order('mes');

    void recalcular(StateSetter setState) {
      final dist = double.tryParse(distanciaCtrl.text) ?? 0.0;
      final frec = (int.tryParse(frecuenciaCtrl.text) ?? 1).clamp(1, 1000000);
      if (factorPKM != null) {
        // kgCO2e -> tCO2e
        emisionesT = (dist * frec * factorPKM!) / 1000.0;
      } else {
        emisionesT = 0.0;
      }
      setState(() {});
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Registrar transporte de empleados'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Periodo
                      DropdownButtonFormField<int>(
                        value: periodoId,
                        hint: const Text('Selecciona un periodo *'),
                        items: [
                          for (var p in periodos)
                            DropdownMenuItem(
                              value: p['id'],
                              child: Text("${p['ano']}-${p['mes']}"),
                            ),
                        ],
                        onChanged: (v) => setState(() => periodoId = v),
                      ),
                      const SizedBox(height: 12),

                      // Descripción de la fuente
                      TextField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: "Descripción de la fuente *",
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Medio de transporte
                      DropdownButtonFormField<String>(
                        value: medio,
                        hint: const Text('Medio de transporte *'),
                        items: const [
                          DropdownMenuItem(
                            value: 'Motocicleta',
                            child: Text('Motocicleta'),
                          ),
                          DropdownMenuItem(
                            value: 'Carro/taxi',
                            child: Text('Carro/taxi'),
                          ),
                          DropdownMenuItem(
                            value: 'Bus / SITP / Intermunicipal',
                            child: Text('Bus / SITP / Intermunicipal'),
                          ),
                          DropdownMenuItem(
                            value: 'TransMilenio (BRT)',
                            child: Text('TransMilenio (BRT)'),
                          ),
                        ],
                        onChanged: (v) async {
                          setState(() => medio = v);
                          factorPKM = await _getFactorPKM(v!);
                          if (factorPKM == null) {
                            // Aviso en caso de no encontrar factor
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'No se encontró un factor vigente para este medio (pkm).',
                                  ),
                                ),
                              );
                            }
                          }
                          recalcular(setState);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Distancia (km)
                      TextField(
                        controller: distanciaCtrl,
                        decoration: const InputDecoration(
                          labelText: "Distancia por viaje (km) *",
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => recalcular(setState),
                      ),
                      const SizedBox(height: 12),

                      // Frecuencia (viajes en el periodo)
                      TextField(
                        controller: frecuenciaCtrl,
                        decoration: const InputDecoration(
                          labelText: "Frecuencia (viajes en el periodo) *",
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => recalcular(setState),
                      ),
                      const SizedBox(height: 12),

                      // Incertidumbres
                      TextField(
                        controller: incDatoCtrl,
                        decoration: const InputDecoration(
                          labelText:
                              "Incertidumbre (dato actividad, %) (opcional)",
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      TextField(
                        controller: incFuenteCtrl,
                        decoration: const InputDecoration(
                          labelText: "Incertidumbre (fuente, %) (opcional)",
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Resultado
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Emisiones tCO₂e:",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            emisionesT.toStringAsFixed(6),
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (factorPKM != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            "Factor aplicado: ${factorPKM!.toStringAsFixed(6)} kgCO₂e/pkm",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
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
                      // Validación mínima
                      if (periodoId == null ||
                          descCtrl.text.trim().isEmpty ||
                          medio == null ||
                          (double.tryParse(distanciaCtrl.text) ?? 0) <= 0 ||
                          (int.tryParse(frecuenciaCtrl.text) ?? 0) <= 0 ||
                          factorPKM == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Completa los campos obligatorios y asegúrate de tener un factor vigente para el medio.',
                            ),
                          ),
                        );
                        return;
                      }

                      final distancia =
                          double.tryParse(distanciaCtrl.text) ?? 0.0;
                      final frecuencia = int.tryParse(frecuenciaCtrl.text) ?? 1;
                      final incDato =
                          double.tryParse(incDatoCtrl.text.trim()).toString();
                      final incFuente =
                          double.tryParse(incFuenteCtrl.text.trim()).toString();

                      try {
                        await supabase
                            .from('desplazamientos_empleados')
                            .insert({
                              'periodo_id': periodoId,
                              'descripcion_fuente': descCtrl.text.trim(),
                              'medio_transporte': medio,
                              'distancia_km': distancia,
                              'frecuencia': frecuencia,
                              'unidad': 'km',
                              'emisiones_tco2e': emisionesT,
                              'incertidumbre_dato':
                                  incDato == 'null' ? 0 : double.parse(incDato),
                              'incertidumbre_fuente':
                                  incFuente == 'null'
                                      ? 0
                                      : double.parse(incFuente),
                            });

                        if (context.mounted) Navigator.pop(context);
                        _cargarRegistros();
                      } catch (e) {
                        debugPrint('❌ Error insertando registro: $e');
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

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Transporte de Empleados")),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _registros.isEmpty
              ? const Center(child: Text('No hay registros'))
              : ListView.builder(
                itemCount: _registros.length,
                itemBuilder: (context, i) {
                  final r = _registros[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.directions_walk),
                      title: Text(
                        "${r['medio_transporte'] ?? '-'}  •  ${r['distancia_km']} km x ${r['frecuencia']}",
                      ),
                      subtitle: Text(
                        "Fuente: ${r['descripcion_fuente'] ?? '-'}\n"
                        "Periodo: ${r['periodo']?['ano'] ?? ''}-${r['periodo']?['mes'] ?? ''}\n"
                        "Unidad: ${r['unidad'] ?? 'km'}\n"
                        "Emisiones: ${r['emisiones_tco2e']?.toStringAsFixed(6) ?? '-'} tCO₂e\n"
                        "Inc. dato: ${r['incertidumbre_dato'] ?? 0}% | Inc. fuente: ${r['incertidumbre_fuente'] ?? 0}%",
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
