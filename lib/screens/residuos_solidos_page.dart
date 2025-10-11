import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResiduosSolidosPage extends StatefulWidget {
  const ResiduosSolidosPage({super.key});

  @override
  State<ResiduosSolidosPage> createState() => _ResiduosSolidosPageState();
}

class _ResiduosSolidosPageState extends State<ResiduosSolidosPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _residuos = [];

  @override
  void initState() {
    super.initState();
    _cargarResiduos();
  }

  Future<void> _cargarResiduos() async {
    try {
      final data = await supabase
          .from('residuos_solidos')
          .select(
            'id, descripcion_fuente, cantidad_kg, unidad, emisiones_tco2e, '
            'incertidumbre_dato, incertidumbre_fuente, '
            'categoria_id, subcategoria_id, '
            'periodo(ano, mes), subcategorias_residuos_ref(nombre)',
          )
          .order('id');

      final rows = List<Map<String, dynamic>>.from(data as List);
      setState(() {
        _residuos = rows;
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

  double _toDouble(String? s) {
    if (s == null) return 0.0;
    return double.tryParse(s.replaceAll(',', '.')) ?? 0.0;
  }

  Future<void> _agregarResiduos() async {
    final fuenteCtrl = TextEditingController();
    final cantidadCtrl = TextEditingController();
    final incertidumbreDatoCtrl = TextEditingController();
    final incertidumbreFuenteCtrl = TextEditingController();

    int? periodoId;
    int? categoriaId;
    int? subcategoriaId;

    double? factorKgCO2e; // kgCO2e/kg vigente para la subcategoría
    double emisionesCalculadasT = 0.0;

    // periodos
    final periodosData = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano')
        .order('mes');
    final periodos = List<Map<String, dynamic>>.from(periodosData as List);

    // categorías
    final categoriasData = await supabase
        .from('categorias_residuos_ref')
        .select('id, nombre')
        .order('nombre');
    final categorias = List<Map<String, dynamic>>.from(categoriasData as List);

    List<Map<String, dynamic>> subcategorias = [];

    Future<void> cargarSubcategorias(int catId) async {
      final subsData = await supabase
          .from('subcategorias_residuos_ref')
          .select('id, nombre')
          .eq('categoria_id', catId)
          .order('nombre');
      subcategorias = List<Map<String, dynamic>>.from(subsData as List);
      subcategoriaId = null;
      factorKgCO2e = null;
      emisionesCalculadasT = 0.0;
    }

    Future<void> cargarFactorVigente(int subcatId) async {
      final resp = await supabase
          .from('factor_emision_residuos')
          .select('factor_kgco2e, vigente_desde')
          .eq('subcategoria_id', subcatId)
          .order('vigente_desde', ascending: false)
          .limit(1);

      final rows = List<Map<String, dynamic>>.from(resp as List);
      if (rows.isNotEmpty) {
        factorKgCO2e = (rows.first['factor_kgco2e'] as num?)?.toDouble();
      } else {
        factorKgCO2e = null;
      }
    }

    // ⚠️ Tras los awaits anteriores, verifica que el widget siga montado
    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setStateDialog) {
              double calcTco2e(double kg, double? factorKg) {
                if (factorKg == null) return 0.0;
                // factor es kgCO2e/kg → pasar a toneladas
                return (kg * factorKg) / 1000.0;
              }

              void recalcular() {
                final kg = _toDouble(cantidadCtrl.text);
                emisionesCalculadasT = calcTco2e(kg, factorKgCO2e);
                setStateDialog(() {});
              }

              Future<void> onSelectSubcategoria(int? v) async {
                subcategoriaId = v;
                factorKgCO2e = null;
                emisionesCalculadasT = 0.0;
                setStateDialog(() {});
                if (v != null) {
                  await cargarFactorVigente(v);
                  recalcular();
                  if (factorKgCO2e == null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '⚠️ No se encontró factor vigente para esta subcategoría',
                        ),
                      ),
                    );
                  }
                }
              }

              final guardarDeshabilitado =
                  fuenteCtrl.text.trim().isEmpty ||
                  categoriaId == null ||
                  subcategoriaId == null ||
                  periodoId == null ||
                  _toDouble(cantidadCtrl.text) <= 0 ||
                  factorKgCO2e == null;

              return AlertDialog(
                title: const Text("Registrar residuos"),
                content: SingleChildScrollView(
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.88,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Fuente
                        TextField(
                          controller: fuenteCtrl,
                          decoration: const InputDecoration(
                            labelText: "Descripción de la fuente *",
                          ),
                          onChanged: (_) => setStateDialog(() {}),
                        ),
                        const SizedBox(height: 12),

                        // Categoría
                        DropdownButtonFormField<int>(
                          value: categoriaId,
                          isExpanded: true,
                          hint: const Text("Categoría *"),
                          items: [
                            for (var c in categorias)
                              DropdownMenuItem(
                                value: c['id'] as int,
                                child: Text(c['nombre'] as String),
                              ),
                          ],
                          onChanged: (v) async {
                            categoriaId = v;
                            setStateDialog(() {});
                            if (v != null) {
                              await cargarSubcategorias(v);
                              setStateDialog(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // Subcategoría
                        DropdownButtonFormField<int>(
                          value: subcategoriaId,
                          isExpanded: true,
                          hint: const Text("Subcategoría *"),
                          items: [
                            for (var s in subcategorias)
                              DropdownMenuItem(
                                value: s['id'] as int,
                                child: Text(s['nombre'] as String),
                              ),
                          ],
                          onChanged: onSelectSubcategoria,
                        ),
                        const SizedBox(height: 12),

                        // Cantidad (kg)
                        TextField(
                          controller: cantidadCtrl,
                          decoration: const InputDecoration(
                            labelText: "Cantidad (kg) *",
                            hintText: "Ej: 1234.56",
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => recalcular(),
                        ),
                        const SizedBox(height: 6),

                        // Factor vigente (solo display)
                        Row(
                          children: [
                            const Text(
                              "Factor vigente: ",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Expanded(
                              child: Text(
                                factorKgCO2e == null
                                    ? "—"
                                    : "${factorKgCO2e!.toStringAsFixed(6)} kgCO₂e/kg",
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Emisiones calculadas
                        Text(
                          "Emisiones: ${emisionesCalculadasT.toStringAsFixed(6)} tCO₂e",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Incertidumbres (se guardan tal cual)
                        TextField(
                          controller: incertidumbreDatoCtrl,
                          decoration: const InputDecoration(
                            labelText: "Incertidumbre (dato actividad, %)",
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        TextField(
                          controller: incertidumbreFuenteCtrl,
                          decoration: const InputDecoration(
                            labelText: "Incertidumbre (fuente, %)",
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Periodo
                        DropdownButtonFormField<int>(
                          value: periodoId,
                          isExpanded: true,
                          hint: const Text("Selecciona un periodo *"),
                          items: [
                            for (var p in periodos)
                              DropdownMenuItem(
                                value: p['id'] as int,
                                child: Text("${p['ano']}-${p['mes']}"),
                              ),
                          ],
                          onChanged: (v) => setStateDialog(() => periodoId = v),
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
                    onPressed:
                        guardarDeshabilitado
                            ? null
                            : () async {
                              try {
                                // Recalcula con el valor definitivo antes de insertar
                                final cantidad = _toDouble(cantidadCtrl.text);
                                final emisT =
                                    (factorKgCO2e == null)
                                        ? 0.0
                                        : (cantidad * factorKgCO2e!) / 1000.0;

                                await supabase.from('residuos_solidos').insert({
                                  'descripcion_fuente': fuenteCtrl.text.trim(),
                                  'categoria_id': categoriaId,
                                  'subcategoria_id': subcategoriaId,
                                  'unidad': 'kg',
                                  'cantidad_kg': cantidad,
                                  'emisiones_tco2e': emisT,
                                  'incertidumbre_dato': _toDouble(
                                    incertidumbreDatoCtrl.text,
                                  ),
                                  'incertidumbre_fuente': _toDouble(
                                    incertidumbreFuenteCtrl.text,
                                  ),
                                  'periodo_id': periodoId,
                                });

                                if (mounted) Navigator.pop(context);
                                _cargarResiduos();
                              } catch (e) {
                                debugPrint("❌ Error insertando residuos: $e");
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Error al guardar: $e"),
                                    ),
                                  );
                                }
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
      appBar: AppBar(title: const Text("Residuos Sólidos")),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _residuos.isEmpty
              ? const Center(child: Text("No hay registros de residuos"))
              : ListView.builder(
                itemCount: _residuos.length,
                itemBuilder: (context, index) {
                  final r = _residuos[index];
                  final subcatNombre =
                      r['subcategorias_residuos_ref']?['nombre'] ?? '-';
                  final emis =
                      (r['emisiones_tco2e'] as num?)?.toDouble() ?? 0.0;
                  return Card(
                    margin: const EdgeInsets.all(8),
                    child: ListTile(
                      title: Text(
                        "$subcatNombre • ${r['cantidad_kg']} ${r['unidad']}",
                      ),
                      subtitle: Text(
                        "Fuente: ${r['descripcion_fuente']}\n"
                        "Emisiones: ${emis.toStringAsFixed(6)} tCO₂e\n"
                        "Incertidumbre dato: ${r['incertidumbre_dato']}%\n"
                        "Incertidumbre fuente: ${r['incertidumbre_fuente']}%\n"
                        "Periodo: ${r['periodo']?['ano'] ?? ''}-${r['periodo']?['mes'] ?? ''}",
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarResiduos,
        child: const Icon(Icons.add),
      ),
    );
  }
}
