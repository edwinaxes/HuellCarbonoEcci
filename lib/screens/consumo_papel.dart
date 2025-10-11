import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConsumoPapelPage extends StatefulWidget {
  const ConsumoPapelPage({super.key});

  @override
  State<ConsumoPapelPage> createState() => _ConsumoPapelPageState();
}

class _ConsumoPapelPageState extends State<ConsumoPapelPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  List<dynamic> _consumos = [];
  List<dynamic> _periodos = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_cargarPeriodos(), _cargarConsumos()]);
    setState(() => _loading = false);
  }

  Future<void> _cargarPeriodos() async {
    try {
      final data = await supabase
          .from('periodo')
          .select('id, ano, mes')
          .order('ano')
          .order('mes');
      _periodos = data;
    } catch (e) {
      _periodos = [];
    }
  }

  Future<void> _cargarConsumos() async {
    try {
      final data = await supabase
          .from('consumo_papel')
          .select(
            'id, descripcion_fuente, tipo, unidad, cantidad_kg, emisiones_tco2e, '
            'incertidumbre_dato, incertidumbre_fuente, periodo(ano, mes)',
          )
          .order('id');
      setState(() {
        _consumos = data;
      });
    } catch (e) {
      setState(() {
        _consumos = [];
      });
    }
  }

  /// Lee el factor (kgCO2e por kg de papel) desde factor_emision_papel
  Future<double?> _factorPorTipo(String tipo) async {
    try {
      final rows = await supabase
          .from('factor_emision_papel')
          .select('factor_kgco2e')
          .eq('tipo_papel', tipo) // 'bond' o 'reciclado'
          .limit(1);
      if (rows.isEmpty) return null;
      return (rows.first['factor_kgco2e'] as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  Future<void> _agregarConsumo() async {
    final fuenteCtrl = TextEditingController();
    final cantidadCtrl = TextEditingController();
    final incDatoCtrl = TextEditingController();
    final incFuenteCtrl = TextEditingController();

    String tipo = 'bond';
    int? periodoId;

    double? factor; // kgCO2e/kg
    double cantidadKg = 0;
    double emisionesT = 0;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setSt) {
              Future<void> _recalcular() async {
                // Traer factor si no está o si cambió el tipo
                if (factor == null) {
                  factor = await _factorPorTipo(tipo);
                }
                final parsed =
                    double.tryParse(cantidadCtrl.text.replaceAll(',', '.')) ??
                    0.0;
                cantidadKg = parsed;
                emisionesT =
                    (factor ?? 0) * cantidadKg; // (kg/kg)*kg = kg → /1000?
                // Tu tabla ya guarda tCO2e. Los factores de esa tabla
                // están en tCO2e por kg (usualmente kgCO2e/kg / 1000),
                // así que asumimos factor en **tCO2e por kg**.
                // Si tus factores están en kgCO2e/kg, divide entre 1000 aquí.
                setSt(() {});
              }

              // cada apertura intenta precargar factor
              if (factor == null) {
                _factorPorTipo(tipo).then((v) {
                  factor = v;
                  _recalcular();
                });
              }

              return AlertDialog(
                title: const Text('Registrar consumo de papel'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: fuenteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Descripción de la fuente',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: tipo,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de papel',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'bond',
                            child: Text('Papel Bond'),
                          ),
                          DropdownMenuItem(
                            value: 'reciclado',
                            child: Text('Papel Reciclado'),
                          ),
                        ],
                        onChanged: (v) {
                          tipo = v ?? 'bond';
                          factor = null; // forzar recarga del factor
                          _recalcular();
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: const [
                          Expanded(
                            child: Text(
                              'Unidad',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Valor', textAlign: TextAlign.right),
                          ),
                        ],
                      ),
                      Row(
                        children: const [
                          Expanded(child: Text('kg')),
                          SizedBox(width: 8),
                          Expanded(child: SizedBox()),
                        ],
                      ),
                      TextField(
                        controller: cantidadCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad (kg)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _recalcular(),
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud, color: Colors.grey),
                        title: Text(
                          'Emisiones totales: ${emisionesT.toStringAsFixed(4)} t CO₂e',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          factor == null
                              ? 'Factor: no encontrado para "$tipo"'
                              : 'Factor aplicado: ${factor!.toStringAsFixed(6)} (t CO₂e / kg)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: incDatoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Incertidumbre por datos de actividad (%)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      TextField(
                        controller: incFuenteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Incertidumbre de la fuente (%)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: periodoId,
                        hint: const Text('Selecciona un periodo'),
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
                      // Validaciones mínimas
                      final cantOk =
                          double.tryParse(
                            cantidadCtrl.text.replaceAll(',', '.'),
                          ) ??
                          0.0;
                      if (cantOk <= 0 || periodoId == null || factor == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Completa cantidad, periodo y verifica que exista un factor para el tipo de papel.',
                            ),
                          ),
                        );
                        return;
                      }

                      try {
                        await supabase.from('consumo_papel').insert({
                          'descripcion_fuente':
                              fuenteCtrl.text.trim().isEmpty
                                  ? 'Sin descripción'
                                  : fuenteCtrl.text.trim(),
                          'tipo': tipo, // 'bond' o 'reciclado'
                          'unidad': 'kg',
                          'cantidad_kg': cantOk,
                          'emisiones_tco2e': emisionesT, // tCO2e calculadas
                          'incertidumbre_dato':
                              double.tryParse(
                                incDatoCtrl.text.replaceAll(',', '.'),
                              ) ??
                              0,
                          'incertidumbre_fuente':
                              double.tryParse(
                                incFuenteCtrl.text.replaceAll(',', '.'),
                              ) ??
                              0,
                          'periodo_id': periodoId,
                        });

                        if (context.mounted) Navigator.pop(context);
                        await _cargarConsumos();
                        setState(() {});
                      } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consumo de Papel')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _consumos.isEmpty
              ? const Center(child: Text('No hay consumos registrados'))
              : ListView.builder(
                itemCount: _consumos.length,
                itemBuilder: (context, index) {
                  final c = _consumos[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      title: Text(
                        '${c['cantidad_kg']} ${c['unidad']} - ${c['tipo']}',
                      ),
                      subtitle: Text(
                        'Fuente: ${c['descripcion_fuente']}\n'
                        'Emisiones: ${c['emisiones_tco2e']} t CO₂e\n'
                        'Incert. actividad: ${c['incertidumbre_dato']}%\n'
                        'Incert. fuente: ${c['incertidumbre_fuente']}%\n'
                        'Periodo: ${c['periodo']?['ano'] ?? ''}-${c['periodo']?['mes'] ?? ''}',
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
