import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConsumoMovilPage extends StatefulWidget {
  const ConsumoMovilPage({super.key});

  @override
  State<ConsumoMovilPage> createState() => _ConsumoMovilPageState();
}

class _ConsumoMovilPageState extends State<ConsumoMovilPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<dynamic> _consumos = [];

  // Cache de factores de combustible: [{id, nombre, categoria, factor_kgco2e}]
  List<Map<String, dynamic>> _factores = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_cargarFactores(), _cargarConsumos()]);
    setState(() => _loading = false);
  }

  Future<void> _cargarFactores() async {
    try {
      final rows = await supabase
          .from('tipos_combustible_ref')
          .select('id, nombre, categoria, factor_kgco2e')
          .order('nombre');

      _factores =
          (rows as List).map((e) {
            final num? f = e['factor_kgco2e'];
            return {
              'id': e['id'],
              'nombre': e['nombre'] as String,
              'categoria': e['categoria'],
              'factor':
                  (f ?? 0).toDouble(), // kgCO2e / gal (líquido) o por unidad
            };
          }).toList();
    } catch (e) {
      debugPrint('❌ Error cargando factores de combustible: $e');
      _factores = [];
    }
  }

  /// Cargar consumos de vehículos móviles
  Future<void> _cargarConsumos() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('consumo_combustible')
          .select(
            'id, galones, km_recorridos, tipo, emisiones_tco2e, '
            'periodo(ano, mes), vehiculo(placa, combustible, rendimiento_km_gal)',
          )
          .not('vehiculo_id', 'is', null) // solo móviles
          .order('id');

      setState(() {
        _consumos = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando consumos móviles: $e");
      setState(() {
        _consumos = [];
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _matchFactorByNombre(String? nombre) {
    if (nombre == null) return null;
    // Match estricto por nombre; si tus nombres varían (p. ej. "Diésel" vs "Diesel"),
    // puedes normalizar (lowercase, quitar acentos) para mejorar el match.
    try {
      return _factores.firstWhere(
        (f) =>
            (f['nombre'] as String).toLowerCase().trim() ==
            nombre.toLowerCase().trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Registrar consumo móvil
  Future<void> _agregarConsumo() async {
    final galonesCtrl = TextEditingController();

    int? periodoId;
    int? vehiculoId;

    // Derivados del vehículo/combustible
    String? nombreCombustibleVeh;
    double? rendimientoKmGal;

    // Factor seleccionado (si no hay match por vehículo)
    Map<String, dynamic>? factorSeleccionado;

    // Cálculos en vivo
    double galones = 0.0;
    double factorKgPorGal = 0.0; // kgCO2e por galón
    double tco2e = 0.0; // toneladas
    double? kmRecorridos;

    final periodos = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano')
        .order('mes');

    final vehiculos = await supabase
        .from('vehiculo')
        .select('id, placa, combustible, rendimiento_km_gal')
        .order('placa');

    void recalc() {
      galones = double.tryParse(galonesCtrl.text.replaceAll(',', '.')) ?? 0.0;

      // si tenemos factor por el vehículo úsalo; si no, toma el del selector
      double? f;
      final match = _matchFactorByNombre(nombreCombustibleVeh);
      if (match != null) {
        f = (match['factor'] as num?)?.toDouble();
      } else if (factorSeleccionado != null) {
        f = (factorSeleccionado!['factor'] as num?)?.toDouble();
      }

      factorKgPorGal = (f ?? 0.0);
      tco2e = galones * factorKgPorGal / 1000.0; // kg -> toneladas
      kmRecorridos =
          rendimientoKmGal == null ? null : (galones * rendimientoKmGal!);
    }

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSt) {
              return AlertDialog(
                title: const Text("Registrar consumo móvil"),
                content: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.9,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Periodo
                        DropdownButtonFormField<int>(
                          value: periodoId,
                          isExpanded: true,
                          hint: const Text("Selecciona un periodo *"),
                          items: [
                            for (var p in periodos)
                              DropdownMenuItem(
                                value: p['id'],
                                child: Text("${p['ano']}-${p['mes']}"),
                              ),
                          ],
                          onChanged: (v) {
                            periodoId = v;
                            setSt(() {});
                          },
                        ),
                        const SizedBox(height: 12),

                        // Vehículo
                        DropdownButtonFormField<int>(
                          value: vehiculoId,
                          isExpanded: true,
                          hint: const Text("Selecciona un vehículo *"),
                          items: [
                            for (var v in vehiculos)
                              DropdownMenuItem(
                                value: v['id'],
                                child: Text(
                                  "${v['placa']} (${v['combustible']})",
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            vehiculoId = v;
                            // reset factorSeleccionado cuando cambie vehículo
                            factorSeleccionado = null;

                            if (v != null) {
                              final selected = (vehiculos as List).firstWhere(
                                (x) => x['id'] == v,
                              );
                              nombreCombustibleVeh =
                                  selected['combustible'] as String?;
                              final num? r = selected['rendimiento_km_gal'];
                              rendimientoKmGal = (r ?? 0).toDouble();

                              // recalcular con el match (si existe)
                              recalc();
                            } else {
                              nombreCombustibleVeh = null;
                              rendimientoKmGal = null;
                              recalc();
                            }
                            setSt(() {});
                          },
                        ),
                        const SizedBox(height: 8),

                        // Info del vehículo / combustible + fallback de factor
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            nombreCombustibleVeh == null
                                ? "Combustible del vehículo: —"
                                : "Combustible del vehículo: $nombreCombustibleVeh",
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Si no hay factor por nombre de vehículo, deja seleccionar
                        if (_matchFactorByNombre(nombreCombustibleVeh) == null)
                          DropdownButtonFormField<Map<String, dynamic>>(
                            value: factorSeleccionado,
                            isExpanded: true,
                            hint: const Text(
                              "Selecciona tipo de combustible (factor) *",
                            ),
                            items: [
                              for (final f in _factores)
                                DropdownMenuItem(
                                  value: f,
                                  child: Text(
                                    "${f['nombre']} • factor ${(f['factor'] as num).toDouble().toStringAsFixed(3)} kgCO₂e/gal",
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              factorSeleccionado = v;
                              recalc();
                              setSt(() {});
                            },
                          )
                        else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Factor detectado: "
                              "${_matchFactorByNombre(nombreCombustibleVeh)?['factor']?.toStringAsFixed(3)} kgCO₂e/gal",
                              style: const TextStyle(color: Colors.green),
                            ),
                          ),
                        const SizedBox(height: 12),

                        // Galones
                        TextField(
                          controller: galonesCtrl,
                          decoration: const InputDecoration(
                            labelText: "Galones consumidos *",
                            hintText: "Ej: 25.5",
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) {
                            recalc();
                            setSt(() {});
                          },
                        ),
                        const SizedBox(height: 12),

                        // Preview de cálculo
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Factor usado: ${factorKgPorGal.toStringAsFixed(3)} kgCO₂e/gal",
                              ),
                              Text(
                                "Emisiones estimadas: ${tco2e.toStringAsFixed(4)} t CO₂e",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                "Km recorridos (estimado): ${kmRecorridos == null ? '—' : kmRecorridos!.toStringAsFixed(2)} km",
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
                      // Validaciones obligatorias
                      if (periodoId == null || vehiculoId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Selecciona periodo y vehículo"),
                          ),
                        );
                        return;
                      }
                      // Debe existir un factor: por match de vehículo o por selección manual
                      final match = _matchFactorByNombre(nombreCombustibleVeh);
                      final tieneFactor =
                          (match != null) ||
                          (factorSeleccionado != null &&
                              (factorSeleccionado!['factor'] as num)
                                      .toDouble() >
                                  0);
                      if (!tieneFactor) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Selecciona un factor de combustible válido",
                            ),
                          ),
                        );
                        return;
                      }

                      // Recalcular definitivo
                      recalc();

                      try {
                        // Determinar tipo (nombre) y tipo_combustible_id si aplica
                        String tipo =
                            nombreCombustibleVeh ??
                            (factorSeleccionado?['nombre'] as String? ??
                                'Combustible');
                        int? tipoCombustibleId =
                            match != null
                                ? match['id'] as int
                                : (factorSeleccionado?['id'] as int?);

                        await supabase.from('consumo_combustible').insert({
                          'periodo_id': periodoId,
                          'vehiculo_id': vehiculoId,
                          'tipo': tipo,
                          'galones': galones,
                          'km_recorridos': kmRecorridos,
                          'emisiones_tco2e': tco2e, // 👈 GUARDAMOS tCO₂e
                          'tipo_combustible_id': tipoCombustibleId,
                          'unidad': 'galones',
                          'consumo':
                              galones, // por consistencia con estacionarios
                          'factor_kgco2e_usado': factorKgPorGal,
                          'factor_categoria': 'Movil',
                        });

                        if (context.mounted) Navigator.pop(context);
                        _cargarConsumos();
                      } catch (e) {
                        debugPrint("❌ Error insertando consumo móvil: $e");
                        if (context.mounted) {
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
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Combustibles Móviles")),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _consumos.isEmpty
              ? const Center(child: Text("No hay consumos registrados"))
              : ListView.builder(
                itemCount: _consumos.length,
                itemBuilder: (context, i) {
                  final c = _consumos[i] as Map<String, dynamic>;
                  final num? g = c['galones'];
                  final num? km = c['km_recorridos'];
                  final num? t = c['emisiones_tco2e'];

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      title: Text(
                        "${(g ?? 0).toString()} gal - ${c['tipo'] ?? ''}",
                      ),
                      subtitle: Text(
                        "Vehículo: ${c['vehiculo']?['placa'] ?? '-'}\n"
                        "Periodo: ${c['periodo']?['ano']}-${c['periodo']?['mes']}\n"
                        "Km recorridos: ${km?.toStringAsFixed(2) ?? '-'}\n"
                        "Emisiones: ${t?.toStringAsFixed(4) ?? '-'} t CO₂e",
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarConsumo,
        child: const Icon(Icons.add),
      ),
    );
  }
}
