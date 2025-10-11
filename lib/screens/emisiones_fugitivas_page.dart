import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmisionesFugitivasPage extends StatefulWidget {
  const EmisionesFugitivasPage({super.key});

  @override
  State<EmisionesFugitivasPage> createState() => _EmisionesFugitivasPageState();
}

class _EmisionesFugitivasPageState extends State<EmisionesFugitivasPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _emisiones = [];

  static const List<String> kUnidades = ['kg', 'g'];

  @override
  void initState() {
    super.initState();
    _cargarEmisiones();
  }

  Future<void> _cargarEmisiones() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('emisiones_fugitivas')
          .select(
            'id, descripcion_fuente, tipo_refrigerante, cantidad_kg, equipo, '
            'emisiones_tco2e, incertidumbre_dato, incertidumbre_fuente, '
            'periodo(ano, mes)',
          )
          .order('id', ascending: true);

      setState(() {
        _emisiones = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _emisiones = [];
        _loading = false;
      });
      debugPrint("❌ Error cargando emisiones fugitivas: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error cargando emisiones: $e")));
      }
    }
  }

  Future<void> _agregarEmision() async {
    final fuenteCtrl = TextEditingController();
    final cantidadCtrl = TextEditingController();
    final equipoCtrl = TextEditingController();
    final incertidumbreDatoCtrl = TextEditingController();
    final incertidumbreFuenteCtrl = TextEditingController();

    int? periodoId;
    String? refrigeranteSel;
    String unidadSel = 'kg';
    double? emisionesTco2eVista;

    final periodos = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano', ascending: true)
        .order('mes', ascending: true);

    final refrigerantes = await supabase
        .from('refrigerantes_ref')
        .select('id, nombre, factor_kgco2e')
        .order('nombre', ascending: true);

    final List<Map<String, dynamic>> refriList =
        List<Map<String, dynamic>>.from(refrigerantes as List);

    double _toKg(String unidad, double cantidad) {
      return unidad == 'g' ? cantidad / 1000.0 : cantidad;
    }

    void _recalcular(void Function(void Function()) setStateDialog) {
      final raw = cantidadCtrl.text.trim().replaceAll(',', '.');
      final double cantidadUi = double.tryParse(raw) ?? 0.0;
      if (cantidadUi <= 0 || refrigeranteSel == null) {
        setStateDialog(() => emisionesTco2eVista = null);
        return;
      }

      final ref = refriList.firstWhere(
        (e) => (e['nombre'] as String) == refrigeranteSel,
        orElse: () => {},
      );
      if (ref.isEmpty) {
        setStateDialog(() => emisionesTco2eVista = null);
        return;
      }

      final double factorKgCo2e =
          (ref['factor_kgco2e'] as num?)?.toDouble() ?? 0.0;
      if (factorKgCo2e <= 0) {
        setStateDialog(() => emisionesTco2eVista = null);
        return;
      }

      final double cantidadKg = _toKg(unidadSel, cantidadUi);
      final double tco2e = (cantidadKg * factorKgCo2e) / 1000.0; // kg→t
      setStateDialog(() => emisionesTco2eVista = tco2e);
    }

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text("Registrar emisión fugitiva"),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.75,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<int>(
                          value: periodoId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Periodo *",
                          ),
                          items:
                              (periodos as List)
                                  .map((e) => Map<String, dynamic>.from(e))
                                  .map(
                                    (p) => DropdownMenuItem<int>(
                                      value: p['id'] as int,
                                      child: Text("${p['ano']}-${p['mes']}"),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setStateDialog(() => periodoId = v),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: fuenteCtrl,
                          decoration: const InputDecoration(
                            labelText: "Descripción de la fuente *",
                            hintText: "p.ej., OS, bitácora de mantenimiento",
                          ),
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: refrigeranteSel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Agente (refrigerante) *",
                          ),
                          items:
                              refriList
                                  .map(
                                    (r) => DropdownMenuItem<String>(
                                      value: r['nombre'] as String,
                                      child: Text(
                                        "${r['nombre']} (factor: ${(r['factor_kgco2e'] as num?)?.toDouble() ?? 0} kgCO₂e/kg)",
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            refrigeranteSel = v;
                            _recalcular(setStateDialog);
                          },
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: unidadSel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Unidad del consumo *",
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
                          onChanged: (v) {
                            unidadSel = v ?? 'kg';
                            _recalcular(setStateDialog);
                          },
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: cantidadCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: "Cantidad ($unidadSel) *",
                            hintText:
                                unidadSel == 'kg'
                                    ? "p.ej., 12.5"
                                    : "p.ej., 500",
                          ),
                          onChanged: (_) => _recalcular(setStateDialog),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: equipoCtrl,
                          decoration: const InputDecoration(
                            labelText: "Equipo (opcional)",
                            hintText: "p.ej., Chiller-03",
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: incertidumbreDatoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: "Incertidumbre (dato actividad, %)",
                            hintText: "p.ej., 5",
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: incertidumbreFuenteCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: "Incertidumbre (fuente, %)",
                            hintText: "p.ej., 10",
                          ),
                        ),
                        const SizedBox(height: 16),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                emisionesTco2eVista == null
                                    ? "Emisiones totales: —"
                                    : "Emisiones totales: ${emisionesTco2eVista!.toStringAsFixed(6)} t CO₂e",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      emisionesTco2eVista == null
                                          ? Colors.red
                                          : Colors.green[700],
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Fórmula: tCO₂e = (kg × factor_kgCO₂e/kg) / 1000. Si eliges gramos, convierto g→kg.",
                                style: TextStyle(fontSize: 12),
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
                      // Validación final
                      final raw = cantidadCtrl.text.trim().replaceAll(',', '.');
                      final double cantUi = double.tryParse(raw) ?? 0.0;
                      if (periodoId == null ||
                          fuenteCtrl.text.trim().isEmpty ||
                          refrigeranteSel == null ||
                          cantUi <= 0 ||
                          emisionesTco2eVista == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Completa periodo, fuente, agente, consumo y verifica el cálculo.",
                            ),
                          ),
                        );
                        return;
                      }

                      final cantidadKg = _toKg(unidadSel, cantUi);
                      final incDato =
                          double.tryParse(
                            incertidumbreDatoCtrl.text.trim().replaceAll(
                              ',',
                              '.',
                            ),
                          ) ??
                          0.0;
                      final incFuente =
                          double.tryParse(
                            incertidumbreFuenteCtrl.text.trim().replaceAll(
                              ',',
                              '.',
                            ),
                          ) ??
                          0.0;

                      try {
                        await supabase.from('emisiones_fugitivas').insert({
                          'periodo_id': periodoId,
                          'descripcion_fuente': fuenteCtrl.text.trim(),
                          'tipo_refrigerante': refrigeranteSel,
                          'cantidad_kg': cantidadKg,
                          'equipo':
                              equipoCtrl.text.trim().isEmpty
                                  ? null
                                  : equipoCtrl.text.trim(),
                          'emisiones_tco2e': emisionesTco2eVista, // toneladas
                          'incertidumbre_dato': incDato,
                          'incertidumbre_fuente': incFuente,
                        });

                        if (mounted) Navigator.pop(context);
                        await _cargarEmisiones();
                      } catch (e) {
                        debugPrint("❌ Error insertando emisión fugitiva: $e");
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
          ),
    );
  }

  Future<void> _eliminar(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Eliminar registro"),
            content: const Text("¿Seguro que deseas eliminar este registro?"),
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
      await supabase.from('emisiones_fugitivas').delete().eq('id', id);
      await _cargarEmisiones();
    } catch (e) {
      debugPrint("❌ Error eliminando registro: $e");
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
        title: const Text("Emisiones Fugitivas"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarEmisiones,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _emisiones.isEmpty
              ? const Center(child: Text("No hay registros"))
              : ListView.builder(
                itemCount: _emisiones.length,
                itemBuilder: (context, index) {
                  final e = _emisiones[index];
                  final periodo =
                      "${e['periodo']?['ano'] ?? ''}-${e['periodo']?['mes'] ?? ''}";
                  final em = (e['emisiones_tco2e'] as num?)?.toDouble();

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      title: Text(
                        "${e['tipo_refrigerante'] ?? '-'} — ${e['cantidad_kg']} kg",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "Periodo: $periodo\n"
                        "Fuente: ${e['descripcion_fuente'] ?? '-'}\n"
                        "Equipo: ${e['equipo'] ?? '-'}\n"
                        "Emisiones: ${em?.toStringAsFixed(6) ?? '-'} t CO₂e\n"
                        "Incert. dato: ${e['incertidumbre_dato'] ?? 0}% · "
                        "Incert. fuente: ${e['incertidumbre_fuente'] ?? 0}%",
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminar(e['id'] as int),
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarEmision,
        child: const Icon(Icons.add),
      ),
    );
  }
}
