import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LubricantesPage extends StatefulWidget {
  const LubricantesPage({super.key});

  @override
  State<LubricantesPage> createState() => _LubricantesPageState();
}

class _LubricantesPageState extends State<LubricantesPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _registros = [];

  static const String kAceites = 'Aceites lubricantes';
  static const String kGrasas = 'Grasas lubricantes';

  static const List<String> kUnidadesAceites = ['L', 'gal'];
  static const List<String> kUnidadesGrasas = ['kg'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('emisiones_lubricantes')
          .select(
            'id, tipo, unidad, cantidad, descripcion_fuente, '
            'emisiones_tco2e, incertidumbre_dato, incertidumbre_fuente, '
            'periodo(ano, mes)',
          )
          .order('id', ascending: true);

      setState(() {
        _registros = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _registros = [];
        _loading = false;
      });
      debugPrint('❌ Error cargando lubricantes: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando: $e')));
      }
    }
  }

  /// Busca factor (kg CO2e / unidad) en 3 pasos:
  /// 1) fuente_emision.id por subtipo (agente)
  /// 2) unidad_medida.id por codigo (L o kg)
  /// 3) factor_emision más vigente para esos ids
  Future<double?> _buscarFactor(String agente, String unidadCodigo) async {
    try {
      // 1) fuente_emision (subtipo exacto)
      final fe = await supabase
          .from('fuente_emision')
          .select('id, subtipo')
          .eq('subtipo', agente)
          .limit(1);
      if (fe.isEmpty) return null;
      final int fuenteId = fe.first['id'] as int;

      // 2) unidad_medida (codigo exacto)
      final um = await supabase
          .from('unidad_medida')
          .select('id, codigo')
          .eq('codigo', unidadCodigo)
          .limit(1);
      if (um.isEmpty) return null;
      final int unidadId = um.first['id'] as int;

      // 3) factor_emision vigente
      final fac = await supabase
          .from('factor_emision')
          .select('valor, vigente_desde')
          .eq('fuente_id', fuenteId)
          .eq('unidad_id', unidadId)
          .order('vigente_desde', ascending: false)
          .limit(1);
      if (fac.isEmpty) return null;

      final num? v = fac.first['valor'];
      return (v ?? 0).toDouble();
    } catch (e) {
      debugPrint('❌ Error buscando factor ($agente/$unidadCodigo): $e');
      return null;
    }
  }

  double _galToL(double gal) => gal * 3.785;

  Future<void> _agregar() async {
    final descCtrl = TextEditingController();
    final cantidadCtrl = TextEditingController();
    final incDatoCtrl = TextEditingController();
    final incFuenteCtrl = TextEditingController();

    int? periodoId;
    String agenteSel = kAceites;
    String unidadSel = 'L'; // por defecto para aceites
    double? tco2eVista;
    double? factorEnBD;

    final periodos = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano', ascending: true)
        .order('mes', ascending: true);

    List<String> _unidadesParaAgente(String agente) {
      return agente == kGrasas ? kUnidadesGrasas : kUnidadesAceites;
    }

    double? _recalcularValor({
      required String agente,
      required String unidadUI,
      required String cantidadTexto,
      required double? factor,
    }) {
      final cantUi =
          double.tryParse(cantidadTexto.trim().replaceAll(',', '.')) ?? 0.0;
      if (cantUi <= 0) return null;

      final bool esGrasa = (agente == kGrasas);

      // Cantidad en la unidad del factor (kg para grasas, L para aceites)
      double cantidadBase;
      if (esGrasa) {
        cantidadBase = cantUi; // kg
      } else {
        cantidadBase = (unidadUI == 'gal') ? _galToL(cantUi) : cantUi; // L
      }

      if ((factor ?? 0) <= 0) return null;

      // tCO2e = (cantidadBase * kgCO2e/unidadBase) / 1000
      return (cantidadBase * factor!) / 1000.0;
    }

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setStateDialog) {
              Future<void> _intentarBuscarFactor() async {
                final unidadFactor = (agenteSel == kGrasas) ? 'kg' : 'L';
                final f = await _buscarFactor(agenteSel, unidadFactor);
                setStateDialog(() {
                  factorEnBD = f;
                  tco2eVista = _recalcularValor(
                    agente: agenteSel,
                    unidadUI: unidadSel,
                    cantidadTexto: cantidadCtrl.text,
                    factor: factorEnBD,
                  );
                });
              }

              // Buscar factor al abrir
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (factorEnBD == null) {
                  _intentarBuscarFactor();
                }
              });

              final bool guardarDeshabilitado =
                  periodoId == null ||
                  descCtrl.text.trim().isEmpty ||
                  cantidadCtrl.text.trim().isEmpty ||
                  factorEnBD == null ||
                  tco2eVista == null;

              return AlertDialog(
                title: const Text('Registrar lubricante'),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                  ),
                  child: SingleChildScrollView(
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
                          onChanged: (v) {
                            periodoId = v;
                            setStateDialog(() {});
                          },
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Descripción de la fuente *',
                            hintText:
                                'p.ej., Factura compra lubricantes / OT mantenimiento',
                          ),
                          onChanged: (_) => setStateDialog(() {}),
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: agenteSel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Agente utilizado *',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: kAceites,
                              child: Text(kAceites),
                            ),
                            DropdownMenuItem(
                              value: kGrasas,
                              child: Text(kGrasas),
                            ),
                          ],
                          onChanged: (v) async {
                            final nuevo = v ?? kAceites;
                            setStateDialog(() {
                              agenteSel = nuevo;
                              unidadSel = _unidadesParaAgente(nuevo).first;
                              factorEnBD = null;
                              tco2eVista = null;
                            });
                            await _intentarBuscarFactor();
                          },
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: unidadSel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Unidad *',
                          ),
                          items:
                              _unidadesParaAgente(agenteSel)
                                  .map(
                                    (u) => DropdownMenuItem<String>(
                                      value: u,
                                      child: Text(u),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            unidadSel =
                                v ?? _unidadesParaAgente(agenteSel).first;
                            tco2eVista = _recalcularValor(
                              agente: agenteSel,
                              unidadUI: unidadSel,
                              cantidadTexto: cantidadCtrl.text,
                              factor: factorEnBD,
                            );
                            setStateDialog(() {});
                          },
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: cantidadCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Cantidad ($unidadSel) *',
                            hintText:
                                agenteSel == kGrasas
                                    ? 'p.ej., 12.5'
                                    : (unidadSel == 'L'
                                        ? 'p.ej., 25'
                                        : 'p.ej., 6'),
                          ),
                          onChanged: (_) {
                            tco2eVista = _recalcularValor(
                              agente: agenteSel,
                              unidadUI: unidadSel,
                              cantidadTexto: cantidadCtrl.text,
                              factor: factorEnBD,
                            );
                            setStateDialog(() {});
                          },
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                factorEnBD == null
                                    ? 'Factor: no encontrado'
                                    : 'Factor: ${factorEnBD!.toStringAsFixed(4)} kg CO₂e/${agenteSel == kGrasas ? 'kg' : 'L'}',
                                style: TextStyle(
                                  color:
                                      factorEnBD == null
                                          ? Colors.red
                                          : Colors.green[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Buscar/actualizar factor en BD',
                              icon: const Icon(Icons.search),
                              onPressed: _intentarBuscarFactor,
                            ),
                          ],
                        ),
                        if (factorEnBD == null)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Carga el factor en la tabla factor_emision: '
                                'subtipo = Aceites/Grasas y unidad = L/kg.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),

                        TextField(
                          controller: incDatoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Incertidumbre (dato actividad, %)',
                            hintText: 'p.ej., 5',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: incFuenteCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Incertidumbre (fuente, %)',
                            hintText: 'p.ej., 10',
                          ),
                        ),
                        const SizedBox(height: 16),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tco2eVista == null
                                    ? 'Emisiones: —'
                                    : 'Emisiones: ${tco2eVista!.toStringAsFixed(6)} t CO₂e',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      tco2eVista == null
                                          ? Colors.red
                                          : Colors.green[700],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                agenteSel == kGrasas
                                    ? 'Fórmula: tCO₂e = (kg × kgCO₂e/kg) / 1000.'
                                    : 'Fórmula: tCO₂e = (L × kgCO₂e/L) / 1000 (si usas gal, convierto a L ×3.785).',
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
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed:
                        guardarDeshabilitado
                            ? null
                            : () async {
                              final incDato =
                                  double.tryParse(incDatoCtrl.text.trim()) ??
                                  0.0;
                              final incFuente =
                                  double.tryParse(incFuenteCtrl.text.trim()) ??
                                  0.0;
                              final cantidadUi =
                                  double.tryParse(
                                    cantidadCtrl.text.trim().replaceAll(
                                      ',',
                                      '.',
                                    ),
                                  ) ??
                                  0.0;

                              try {
                                await supabase
                                    .from('emisiones_lubricantes')
                                    .insert({
                                      'periodo_id': periodoId,
                                      'descripcion_fuente':
                                          descCtrl.text.trim(),
                                      'tipo': agenteSel, // Aceites o Grasas
                                      'unidad': unidadSel, // L | gal | kg
                                      'cantidad':
                                          cantidadUi, // como la ingresó el usuario
                                      'emisiones_tco2e':
                                          tco2eVista, // toneladas
                                      'incertidumbre_dato': incDato,
                                      'incertidumbre_fuente': incFuente,
                                    });

                                if (mounted) Navigator.pop(context);
                                await _cargar();
                              } catch (e) {
                                debugPrint('❌ Error insertando lubricante: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error al guardar: $e'),
                                    ),
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

  Future<void> _eliminar(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar registro'),
            content: const Text('¿Seguro que deseas eliminar este registro?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Eliminar',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (ok != true) return;

    try {
      await supabase.from('emisiones_lubricantes').delete().eq('id', id);
      await _cargar();
    } catch (e) {
      debugPrint('❌ Error eliminando registro: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lubricantes'),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _registros.isEmpty
              ? const Center(child: Text('No hay registros'))
              : ListView.builder(
                itemCount: _registros.length,
                itemBuilder: (context, i) {
                  final r = _registros[i];
                  final periodo =
                      '${r['periodo']?['ano'] ?? ''}-${r['periodo']?['mes'] ?? ''}';
                  final em = (r['emisiones_tco2e'] as num?)?.toDouble();
                  final tipo = r['tipo'] ?? '-';
                  final unidad = r['unidad'] ?? '';
                  final cantidad = (r['cantidad'] as num?)?.toDouble();

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      title: Text(
                        '$tipo — ${cantidad?.toStringAsFixed(3) ?? '-'} $unidad',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Periodo: $periodo\n'
                        'Fuente: ${r['descripcion_fuente'] ?? '-'}\n'
                        'Emisiones: ${em?.toStringAsFixed(6) ?? '-'} t CO₂e\n'
                        'Incert. dato: ${r['incertidumbre_dato'] ?? 0}% · '
                        'Incert. fuente: ${r['incertidumbre_fuente'] ?? 0}%',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminar(r['id'] as int),
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregar,
        child: const Icon(Icons.add),
      ),
    );
  }
}
