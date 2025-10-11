import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProcesosIndustrialesPage extends StatefulWidget {
  const ProcesosIndustrialesPage({super.key});

  @override
  State<ProcesosIndustrialesPage> createState() =>
      _ProcesosIndustrialesPageState();
}

class _ProcesosIndustrialesPageState extends State<ProcesosIndustrialesPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _procesos = [];

  // Unidades permitidas en UI. Los factores están en kg gas / ton
  static const List<String> kUnidades = ['ton', 'kg'];

  // GWP (AR5) para convertir a CO2e
  static const Map<String, double> GWP_MAP = {
    'CO2': 1.0,
    'CH4': 28.0,
    'N2O': 265.0,
  };

  @override
  void initState() {
    super.initState();
    _cargarProcesos();
  }

  Future<void> _cargarProcesos() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('procesos_industriales')
          .select(
            'id, descripcion_fuente, cantidad, unidad, emisiones_co2e, '
            'incertidumbre_dato, incertidumbre_fuente, '
            'periodo(ano, mes), tipo_produccion_ref(nombre)',
          )
          .order('id', ascending: true);

      setState(() {
        _procesos = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando procesos: $e");
      setState(() {
        _procesos = [];
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error cargando procesos: $e")));
      }
    }
  }

  /// Obtiene el factor más vigente (kg gas / ton) y el gas asociado para el tipo
  Future<Map<String, dynamic>?> _buscarFactor({
    required int tipoProduccionId,
  }) async {
    try {
      // 1) Nombre de tipo para matchear con fuente_emision.subtipo
      final tp =
          await supabase
              .from('tipo_produccion_ref')
              .select('nombre')
              .eq('id', tipoProduccionId)
              .single();
      final String tipoNombre = (tp['nombre'] as String).trim();

      // 2) Por subtipo (ILIKE '%...%') + unidad 'ton'
      final dataBySubtipo = await supabase
          .from('factor_emision')
          .select(
            'valor, gas, version, vigente_desde, '
            'fuente_emision(subtipo), unidad_medida(codigo)',
          )
          .eq('unidad_medida.codigo', 'ton')
          .ilike('fuente_emision.subtipo', '%$tipoNombre%')
          .order('vigente_desde', ascending: false)
          .limit(1);

      final bySubtipo = List<Map<String, dynamic>>.from(dataBySubtipo as List);
      if (bySubtipo.isNotEmpty) return bySubtipo.first;

      // 3) Fallback: último vigente con unidad 'ton'
      final dataFallback = await supabase
          .from('factor_emision')
          .select(
            'valor, gas, version, vigente_desde, '
            'fuente_emision(subtipo), unidad_medida(codigo)',
          )
          .eq('unidad_medida.codigo', 'ton')
          .order('vigente_desde', ascending: false)
          .limit(1);

      final fallback = List<Map<String, dynamic>>.from(dataFallback as List);
      if (fallback.isNotEmpty) return fallback.first;

      return null;
    } catch (e) {
      debugPrint("❌ Error buscando factor: $e");
      return null;
    }
  }

  /// Diálogo: agregar proceso industrial
  Future<void> _agregarProceso() async {
    final descCtrl = TextEditingController();
    final cantidadCtrl = TextEditingController();
    final incDatoCtrl = TextEditingController();
    final incFuenteCtrl = TextEditingController();

    int? periodoId;
    int? tipoProduccionId;
    String unidadSel = 'ton'; // por defecto
    double? emisionesCalculadasT;
    String? notaFactor; // para mostrar versión/gas
    Map<String, dynamic>? factorUsado;

    // Cargar catálogos
    final periodosData = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano', ascending: true);
    final periodos = List<Map<String, dynamic>>.from(periodosData as List);

    final tiposProdData = await supabase
        .from('tipo_produccion_ref')
        .select('id, nombre')
        .order('nombre', ascending: true);
    final tiposProd = List<Map<String, dynamic>>.from(tiposProdData as List);

    // Evita usar context si fue desmontado tras los awaits previos
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> recalcular() async {
              final cantidad = double.tryParse(cantidadCtrl.text) ?? 0.0;
              if (tipoProduccionId == null || cantidad <= 0) {
                setStateDialog(() {
                  emisionesCalculadasT = null;
                  notaFactor = null;
                });
                return;
              }

              // Traer factor (kg gas / ton) + gas
              factorUsado = await _buscarFactor(
                tipoProduccionId: tipoProduccionId!,
              );
              if (factorUsado == null) {
                setStateDialog(() {
                  emisionesCalculadasT = null;
                  notaFactor =
                      '⚠️ No se encontró factor vigente para este tipo y unidad base.';
                });
                return;
              }

              final double factorKgPorTon =
                  (factorUsado!['valor'] as num).toDouble();
              final String gas = (factorUsado!['gas'] as String).toUpperCase();
              final double gwp = GWP_MAP[gas] ?? 1.0;

              // Convertir cantidad a toneladas si el usuario eligió kg
              final double cantidadTon =
                  (unidadSel == 'kg') ? (cantidad / 1000.0) : cantidad;

              // Emisiones tCO2e = cantidad_ton * (factor_kg_gas_por_ton / 1000) * GWP
              final double tCO2e =
                  cantidadTon * (factorKgPorTon / 1000.0) * gwp;

              setStateDialog(() {
                emisionesCalculadasT = tCO2e;
                notaFactor =
                    "Factor: ${factorKgPorTon.toStringAsFixed(2)} kg $gas/ton · "
                    "GWP=${gwp.toStringAsFixed(0)} · ${factorUsado!['version'] ?? ''}";
              });
            }

            return AlertDialog(
              title: const Text("Registrar Proceso Industrial"),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: "Descripción de la fuente *",
                          hintText: "p.ej., Reporte mensual de horno",
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Tipo de producción
                      DropdownButtonFormField<int>(
                        value: tipoProduccionId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Tipo de producción *",
                        ),
                        items:
                            tiposProd
                                .map(
                                  (tp) => DropdownMenuItem<int>(
                                    value: tp['id'] as int,
                                    child: Text(tp['nombre'] as String),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) async {
                          setStateDialog(() {
                            tipoProduccionId = v;
                          });
                          await recalcular();
                        },
                      ),
                      const SizedBox(height: 12),

                      // Periodo
                      DropdownButtonFormField<int>(
                        value: periodoId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Periodo *",
                        ),
                        items:
                            periodos
                                .map(
                                  (p) => DropdownMenuItem<int>(
                                    value: p['id'] as int,
                                    child: Text("${p['ano']}-${p['mes']}"),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          setStateDialog(() => periodoId = v);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Unidad
                      DropdownButtonFormField<String>(
                        value: unidadSel,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Unidad *",
                        ),
                        items:
                            kUnidades
                                .map(
                                  (u) => DropdownMenuItem<String>(
                                    value: u,
                                    child: Text(u),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) async {
                          setStateDialog(() => unidadSel = v ?? 'ton');
                          await recalcular();
                        },
                      ),
                      const SizedBox(height: 12),

                      // Cantidad
                      TextField(
                        controller: cantidadCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: "Cantidad (${unidadSel}) *",
                          hintText:
                              unidadSel == 'kg' ? "p.ej., 5000" : "p.ej., 10",
                        ),
                        onChanged: (_) => recalcular(),
                      ),
                      const SizedBox(height: 12),

                      // Incertidumbres
                      TextField(
                        controller: incDatoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "Incertidumbre (dato actividad, %) ",
                          hintText: "p.ej., 5",
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: incFuenteCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "Incertidumbre (fuente, %) ",
                          hintText: "p.ej., 10",
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Vista previa
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              emisionesCalculadasT == null
                                  ? "Emisiones tCO₂e: —"
                                  : "Emisiones tCO₂e: ${emisionesCalculadasT!.toStringAsFixed(4)}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    emisionesCalculadasT == null
                                        ? Colors.red
                                        : Colors.green[700],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              notaFactor ??
                                  "Selecciona tipo, unidad y cantidad",
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Validar
                    if (descCtrl.text.trim().isEmpty ||
                        periodoId == null ||
                        tipoProduccionId == null ||
                        cantidadCtrl.text.trim().isEmpty ||
                        emisionesCalculadasT == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Completa los campos obligatorios y asegúrate de que el cálculo sea válido.",
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    final cantidad =
                        double.tryParse(cantidadCtrl.text.trim()) ?? 0.0;
                    final incDato =
                        double.tryParse(incDatoCtrl.text.trim()) ?? 0.0;
                    final incFuente =
                        double.tryParse(incFuenteCtrl.text.trim()) ?? 0.0;

                    try {
                      await supabase.from('procesos_industriales').insert({
                        'descripcion_fuente': descCtrl.text.trim(),
                        'periodo_id': periodoId,
                        'tipo_produccion_id': tipoProduccionId,
                        'cantidad': cantidad,
                        'unidad': unidadSel,
                        'emisiones_co2e': emisionesCalculadasT,
                        'incertidumbre_dato': incDato,
                        'incertidumbre_fuente': incFuente,
                      });

                      if (mounted) Navigator.pop(context);
                      await _cargarProcesos();
                    } catch (e) {
                      debugPrint("❌ Error insertando proceso: $e");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error al guardar: $e")),
                        );
                      }
                    }
                  },
                  child: const Text("Guardar"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Eliminar registro
  Future<void> _eliminar(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Eliminar registro"),
            content: const Text("¿Seguro que deseas eliminar este proceso?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancelar"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Eliminar",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (ok != true) return;

    try {
      await supabase.from('procesos_industriales').delete().eq('id', id);
      await _cargarProcesos();
    } catch (e) {
      debugPrint("❌ Error eliminando proceso: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error al eliminar: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Procesos Industriales"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarProcesos,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _procesos.isEmpty
              ? const Center(child: Text("No hay procesos registrados"))
              : ListView.builder(
                itemCount: _procesos.length,
                itemBuilder: (context, index) {
                  final p = _procesos[index];
                  final nombreTipo = p['tipo_produccion_ref']?['nombre'] ?? '-';
                  final periodo =
                      "${p['periodo']?['ano'] ?? ''}-${p['periodo']?['mes'] ?? ''}";
                  final em = (p['emisiones_co2e'] as num?)?.toDouble();

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      title: Text(
                        "$nombreTipo — ${p['cantidad']} ${p['unidad'] ?? ''}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "Fuente: ${p['descripcion_fuente'] ?? '-'}\n"
                        "Periodo: $periodo\n"
                        "Emisiones: ${em?.toStringAsFixed(4) ?? '-'} tCO₂e\n"
                        "Incert. dato: ${p['incertidumbre_dato'] ?? 0}% · "
                        "Incert. fuente: ${p['incertidumbre_fuente'] ?? 0}%",
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminar(p['id'] as int),
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarProceso,
        child: const Icon(Icons.add),
      ),
    );
  }
}
