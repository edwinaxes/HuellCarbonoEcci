import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConsumoEstacionarioPage extends StatefulWidget {
  const ConsumoEstacionarioPage({super.key});

  @override
  State<ConsumoEstacionarioPage> createState() =>
      _ConsumoEstacionarioPageState();
}

class _ConsumoEstacionarioPageState extends State<ConsumoEstacionarioPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<dynamic> _consumos = [];
  List<Map<String, dynamic>> _combustibles = [];

  @override
  void initState() {
    super.initState();
    _cargarCombustibles();
    _cargarConsumos();
  }

  Future<void> _cargarConsumos() async {
    setState(() => _loading = true);
    try {
      final response = await supabase
          .from('consumo_combustible')
          .select(
            'id, descripcion_fuente, consumo, unidad, emisiones_tco2e, '
            'incertidumbre_dato, incertidumbre_fuente, '
            'periodo(ano, mes), tipo_combustible_id, tipo',
          )
          .filter('vehiculo_id', 'is', null)
          .order('id');

      setState(() {
        _consumos = response;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando consumos estacionarios: $e");
      setState(() {
        _consumos = [];
        _loading = false;
      });
    }
  }

  Future<void> _cargarCombustibles() async {
    try {
      final response = await supabase
          .from('tipos_combustible_ref')
          .select('id, nombre, categoria, factor_kgco2e')
          .order('nombre');

      setState(() {
        _combustibles =
            (response as List).map((e) {
              final num? f = e['factor_kgco2e'];
              return {
                'id': e['id'],
                'nombre': e['nombre'],
                'categoria': e['categoria'],
                'factor': (f ?? 0).toDouble(),
              };
            }).toList();
      });
    } catch (e) {
      debugPrint("❌ Error cargando tipos de combustible: $e");
    }
  }

  // ---------- FORMULARIO EN BOTTOM SHEET ----------
  void _abrirFormulario() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (context) => _FormConsumoEstacionario(
            combustibles: _combustibles,
            onSaved: () async {
              Navigator.pop(context);
              await _cargarConsumos();
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Combustibles Estacionarios")),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _consumos.isEmpty
              ? const Center(child: Text("No hay consumos registrados"))
              : ListView.builder(
                itemCount: _consumos.length,
                itemBuilder: (context, i) {
                  final c = _consumos[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: ListTile(
                      isThreeLine: true,
                      title: Text(
                        "${c['consumo']} ${c['unidad']} - ${c['tipo']}",
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        "Fuente: ${c['descripcion_fuente']}\n"
                        "Periodo: ${c['periodo']?['ano']}-${c['periodo']?['mes']}\n"
                        "Emisiones: ${c['emisiones_tco2e']} tCO₂e\n"
                        "Incertidumbre dato: ${c['incertidumbre_dato']}% • fuente: ${c['incertidumbre_fuente']}%",
                        softWrap: true,
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirFormulario,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ------------ WIDGET DEL FORM (BOTTOM SHEET) ------------
class _FormConsumoEstacionario extends StatefulWidget {
  const _FormConsumoEstacionario({
    required this.combustibles,
    required this.onSaved,
  });

  final List<Map<String, dynamic>> combustibles;
  final Future<void> Function() onSaved;

  @override
  State<_FormConsumoEstacionario> createState() =>
      _FormConsumoEstacionarioState();
}

class _FormConsumoEstacionarioState extends State<_FormConsumoEstacionario> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final fuenteCtrl = TextEditingController();
  final consumoCtrl = TextEditingController();
  final incDatoCtrl = TextEditingController();
  final incFuenteCtrl = TextEditingController();

  int? periodoId;
  Map<String, dynamic>? combustible;
  String? unidad;

  List<dynamic> _periodos = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cargarPeriodos();
  }

  Future<void> _cargarPeriodos() async {
    try {
      final data = await supabase
          .from('periodo')
          .select('id, ano, mes')
          .order('ano')
          .order('mes');
      setState(() => _periodos = data);
    } catch (e) {
      debugPrint("❌ Error cargando periodos: $e");
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: const OutlineInputBorder(),
  );

  @override
  void dispose() {
    fuenteCtrl.dispose();
    consumoCtrl.dispose();
    incDatoCtrl.dispose();
    incFuenteCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (combustible == null || unidad == null || periodoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complete los campos requeridos.")),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final consumo = double.tryParse(consumoCtrl.text) ?? 0;

      await supabase.from('consumo_combustible').insert({
        'descripcion_fuente': fuenteCtrl.text,
        'periodo_id': periodoId,
        'tipo_combustible_id': combustible!['id'],
        'tipo': combustible!['nombre'],
        'unidad': unidad,
        'consumo': consumo,
        // emisiones_tco2e: se calcula en la BD (trigger)
        'incertidumbre_dato': double.tryParse(incDatoCtrl.text) ?? 0,
        'incertidumbre_fuente': double.tryParse(incFuenteCtrl.text) ?? 0,
        'vehiculo_id': null, // estacionario
      });

      await widget.onSaved();
    } catch (e) {
      debugPrint("❌ Error insertando consumo: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error insertando consumo: $e")));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottom, // se eleva con el teclado
        top: 8,
      ),
      child: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Título fijo del sheet
                const SizedBox(height: 4),
                const Text(
                  "Registrar consumo estacionario",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: fuenteCtrl,
                  decoration: _dec("Descripción de la fuente *"),
                  textInputAction: TextInputAction.next,
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty) ? "Requerido" : null,
                ),
                const SizedBox(height: 10),

                // Periodo
                DropdownButtonFormField<int>(
                  value: periodoId,
                  isExpanded: true,
                  decoration: _dec("Periodo *"),
                  items: [
                    for (var p in _periodos)
                      DropdownMenuItem(
                        value: p['id'],
                        child: Text("${p['ano']}-${p['mes']}"),
                      ),
                  ],
                  onChanged: (v) => setState(() => periodoId = v),
                  validator: (v) => v == null ? "Requerido" : null,
                ),
                const SizedBox(height: 10),

                // Combustible
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: combustible,
                  isExpanded: true,
                  decoration: _dec("Combustible *"),
                  items: [
                    for (var c in widget.combustibles)
                      DropdownMenuItem(value: c, child: Text(c['nombre'])),
                  ],
                  onChanged: (v) {
                    setState(() {
                      combustible = v;
                      switch (v?['categoria']) {
                        case 'Liquido':
                          unidad = "galones";
                          break;
                        case 'Gaseoso':
                          unidad = "m3";
                          break;
                        case 'Solido':
                          unidad = "kg";
                          break;
                        default:
                          unidad = "unidad";
                      }
                    });
                  },
                  validator: (v) => v == null ? "Requerido" : null,
                ),
                const SizedBox(height: 10),

                // Consumo
                TextFormField(
                  controller: consumoCtrl,
                  decoration: _dec(
                    "Consumo ${unidad != null ? '($unidad)' : ''} *",
                    hint: "Ej. 120.5",
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    final d = double.tryParse(v ?? "");
                    if (d == null) return "Número inválido";
                    if (d < 0) return "Debe ser mayor o igual a 0";
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // Incertidumbres (solo se guardan)
                TextFormField(
                  controller: incDatoCtrl,
                  decoration: _dec(
                    "Incertidumbre (dato actividad, %)",
                    hint: "0 – 100",
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: incFuenteCtrl,
                  decoration: _dec(
                    "Incertidumbre (fuente, %)",
                    hint: "0 – 100",
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _guardar,
                    child:
                        _saving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text("Guardar"),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
