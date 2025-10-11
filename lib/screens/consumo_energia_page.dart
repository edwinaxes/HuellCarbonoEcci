import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConsumoEnergiaPage extends StatefulWidget {
  const ConsumoEnergiaPage({super.key});

  @override
  State<ConsumoEnergiaPage> createState() => _ConsumoEnergiaPageState();
}

class _ConsumoEnergiaPageState extends State<ConsumoEnergiaPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _consumos = [];

  static const List<String> kUnidades = ['kWh', 'MWh'];

  @override
  void initState() {
    super.initState();
    _cargarConsumos();
  }

  double _mwhToKwh(double mwh) => mwh * 1000.0;

  double? _recalcular({
    required String valorTexto,
    required String unidadUI,
    required double? factorKgCo2ePorKwh,
  }) {
    final v = double.tryParse(valorTexto.trim()) ?? 0;
    if (v <= 0 || (factorKgCo2ePorKwh ?? 0) <= 0) return null;
    final kwh = (unidadUI == 'MWh') ? _mwhToKwh(v) : v;
    return (kwh * factorKgCo2ePorKwh!) / 1000.0;
  }

  Future<double?> _buscarFactorKwh() async {
    try {
      final data = await supabase
          .from('factor_emision')
          .select(
            'valor, vigente_desde, unidad_medida(codigo), fuente_emision(subtipo)',
          )
          .eq('unidad_medida.codigo', 'kWh')
          .eq('fuente_emision.subtipo', 'Energía eléctrica')
          .order('vigente_desde', ascending: false)
          .limit(1);

      final rows = List<Map<String, dynamic>>.from(data as List);
      if (rows.isNotEmpty) {
        final r = rows.first;
        return (r['valor'] as num?)?.toDouble();
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error buscando factor energía: $e');
      return null;
    }
  }

  Future<void> _cargarConsumos() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('consumo_energia')
          .select(
            'id, descripcion_fuente, unidad, consumo_valor, kwh, '
            'emisiones_tco2e, incertidumbre_dato, incertidumbre_fuente, '
            'periodo(ano, mes)',
          )
          .order('id');

      setState(() {
        _consumos = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando consumos energía: $e");
      setState(() {
        _loading = false;
        _consumos = [];
      });
    }
  }

  Future<void> _agregarConsumo() async {
    final descCtrl = TextEditingController();
    final valCtrl = TextEditingController();
    final incDatoCtrl = TextEditingController();
    final incFuenteCtrl = TextEditingController();

    int? periodoId;
    String unidadSel = 'kWh';
    double? vistaTco2e;
    double? factorKwh;

    final periodos = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano');

    // Evita usar context si el widget fue desmontado después del await
    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setStateDialog) {
              Future<void> intentarBuscarFactor() async {
                final f = await _buscarFactorKwh();
                setStateDialog(() {
                  factorKwh = f;
                  vistaTco2e = _recalcular(
                    valorTexto: valCtrl.text,
                    unidadUI: unidadSel,
                    factorKgCo2ePorKwh: factorKwh,
                  );
                });
              }

              // Trae factor al abrir
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (factorKwh == null) intentarBuscarFactor();
              });

              final guardarDeshabilitado =
                  periodoId == null ||
                  descCtrl.text.trim().isEmpty ||
                  valCtrl.text.trim().isEmpty ||
                  factorKwh == null ||
                  vistaTco2e == null;

              return AlertDialog(
                title: const Text("Registrar consumo de energía"),
                content: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        value: periodoId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Periodo *',
                        ),
                        items:
                            (periodos as List)
                                .map((e) => Map<String, dynamic>.from(e))
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

                      TextField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Descripción de la fuente *',
                        ),
                        onChanged: (_) => setStateDialog(() {}),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: unidadSel,
                              decoration: const InputDecoration(
                                labelText: 'Unidad *',
                              ),
                              items:
                                  kUnidades
                                      .map(
                                        (u) => DropdownMenuItem(
                                          value: u,
                                          child: Text(u),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (v) {
                                setStateDialog(() {
                                  unidadSel = v ?? 'kWh';
                                  vistaTco2e = _recalcular(
                                    valorTexto: valCtrl.text,
                                    unidadUI: unidadSel,
                                    factorKgCo2ePorKwh: factorKwh,
                                  );
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: valCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Valor *',
                              ),
                              onChanged: (_) {
                                setStateDialog(() {
                                  vistaTco2e = _recalcular(
                                    valorTexto: valCtrl.text,
                                    unidadUI: unidadSel,
                                    factorKgCo2ePorKwh: factorKwh,
                                  );
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Text(
                        factorKwh == null
                            ? 'Factor: no encontrado'
                            : 'Factor: ${factorKwh!.toStringAsFixed(6)} kg CO₂e/kWh',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              factorKwh == null
                                  ? Colors.red
                                  : Colors.green[700],
                        ),
                      ),
                      const SizedBox(height: 6),

                      Text(
                        vistaTco2e == null
                            ? 'Emisiones totales: —'
                            : 'Emisiones totales: ${vistaTco2e!.toStringAsFixed(6)} t CO₂e',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              vistaTco2e == null
                                  ? Colors.red
                                  : Colors.green[700],
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: incDatoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Incertidumbre por datos de actividad (%)',
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
                              final valorUi =
                                  double.tryParse(valCtrl.text.trim()) ?? 0.0;
                              final incDato =
                                  double.tryParse(incDatoCtrl.text.trim()) ??
                                  0.0;
                              final incFuente =
                                  double.tryParse(incFuenteCtrl.text.trim()) ??
                                  0.0;

                              final kwh =
                                  (unidadSel == 'MWh')
                                      ? _mwhToKwh(valorUi)
                                      : valorUi;

                              try {
                                await supabase.from('consumo_energia').insert({
                                  'periodo_id': periodoId,
                                  'descripcion_fuente': descCtrl.text.trim(),
                                  'unidad': unidadSel,
                                  'consumo_valor': valorUi,
                                  'kwh': kwh,
                                  'emisiones_tco2e': vistaTco2e,
                                  'incertidumbre_dato': incDato,
                                  'incertidumbre_fuente': incFuente,
                                });

                                if (mounted) Navigator.pop(context);
                                await _cargarConsumos();
                              } catch (e) {
                                debugPrint("❌ Error insertando consumo: $e");
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
      appBar: AppBar(title: const Text("Consumo de Energía")),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _consumos.isEmpty
              ? const Center(child: Text("No hay consumos registrados"))
              : ListView.builder(
                itemCount: _consumos.length,
                itemBuilder: (context, index) {
                  final c = _consumos[index];
                  final periodo =
                      "${c['periodo']?['ano'] ?? ''}-${c['periodo']?['mes'] ?? ''}";
                  final valor = (c['consumo_valor'] as num?)?.toDouble();
                  final unidad = c['unidad'] ?? 'kWh';
                  final em = (c['emisiones_tco2e'] as num?)?.toDouble();

                  return Card(
                    margin: const EdgeInsets.all(8),
                    child: ListTile(
                      title: Text(
                        "Descripción: ${c['descripcion_fuente'] ?? '-'}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "Consumo: ${valor?.toStringAsFixed(3) ?? '-'} $unidad "
                        "(≈ ${c['kwh']} kWh)\n"
                        "Emisiones totales: ${em?.toStringAsFixed(6) ?? '-'} t CO₂e\n"
                        "Incertidumbre (dato): ${c['incertidumbre_dato'] ?? 0}%\n"
                        "Incertidumbre (fuente): ${c['incertidumbre_fuente'] ?? 0}%\n"
                        "Periodo: $periodo",
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
