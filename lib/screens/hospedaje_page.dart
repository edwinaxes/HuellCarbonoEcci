import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HospedajePage extends StatefulWidget {
  const HospedajePage({super.key});

  @override
  State<HospedajePage> createState() => _HospedajePageState();
}

class _HospedajePageState extends State<HospedajePage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('hospedaje')
          .select(
            'id, descripcion_fuente, alojamiento, unidad, visitantes, '
            'emisiones_tco2e, incertidumbre_dato, incertidumbre_fuente, '
            'periodo(ano, mes)',
          )
          .order('id');

      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando hospedaje: $e');
      setState(() {
        _items = [];
        _loading = false;
      });
    }
  }

  Future<void> _agregar() async {
    final descCtrl = TextEditingController();
    final visitantesCtrl = TextEditingController();
    final incDatoCtrl = TextEditingController(text: '0');
    final incFuenteCtrl = TextEditingController(text: '0');

    String? alojamiento;
    int? periodoId;
    double? factorKgPorNoche;
    double emisionesT = 0;

    final periodos = await supabase
        .from('periodo')
        .select('id, ano, mes')
        .order('ano');

    // Recalcular emisiones
    void recalcular(StateSetter setState) {
      final visitantesInt = (double.tryParse(visitantesCtrl.text) ?? 0).round();
      if (factorKgPorNoche != null) {
        emisionesT = (visitantesInt * factorKgPorNoche!) / 1000.0;
      } else {
        emisionesT = 0;
      }
      setState(() {});
    }

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Registrar hospedaje'),
                content: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.95,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Descripción de la fuente *',
                          ),
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: alojamiento,
                          hint: const Text('Tipo de alojamiento *'),
                          items: const [
                            DropdownMenuItem(
                              value: 'Hotel',
                              child: Text('Hotel'),
                            ),
                            DropdownMenuItem(
                              value: 'Alojamiento y desayuno',
                              child: Text('Alojamiento y desayuno'),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => alojamiento = v);
                            // Aquí cargarías el factor real según DB
                            factorKgPorNoche = 30.0; // ejemplo: 30 kgCO2e/noche
                            recalcular(setState);
                          },
                        ),

                        const SizedBox(height: 12),

                        TextFormField(
                          enabled: false,
                          initialValue: 'noche',
                          decoration: const InputDecoration(
                            labelText: 'Unidad',
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: visitantesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'No. de noches *',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => recalcular(setState),
                        ),
                        const SizedBox(height: 12),

                        Text(
                          'Emisiones: ${emisionesT.toStringAsFixed(4)} tCO₂e',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: incDatoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Incertidumbre por datos (%)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        TextField(
                          controller: incFuenteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Incertidumbre de la fuente (%)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<int>(
                          value: periodoId,
                          hint: const Text('Periodo *'),
                          items: [
                            for (var p in periodos)
                              DropdownMenuItem(
                                value: p['id'],
                                child: Text('${p['ano']}-${p['mes']}'),
                              ),
                          ],
                          onChanged: (v) => setState(() => periodoId = v),
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
                    onPressed: () async {
                      final visitantesInt =
                          (double.tryParse(visitantesCtrl.text) ?? 0).round();

                      if (descCtrl.text.trim().isEmpty ||
                          alojamiento == null ||
                          periodoId == null ||
                          visitantesInt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Completa todos los campos requeridos',
                            ),
                          ),
                        );
                        return;
                      }

                      final emisionesFinalT =
                          (visitantesInt * (factorKgPorNoche ?? 0)) / 1000.0;

                      try {
                        await supabase.from('hospedaje').insert({
                          'descripcion_fuente': descCtrl.text.trim(),
                          'alojamiento': alojamiento,
                          'unidad': 'noche', // 🔹 fijo
                          'visitantes': visitantesInt,
                          'periodo_id': periodoId,
                          'emisiones_tco2e': emisionesFinalT,
                          'incertidumbre_dato':
                              double.tryParse(incDatoCtrl.text) ?? 0,
                          'incertidumbre_fuente':
                              double.tryParse(incFuenteCtrl.text) ?? 0,
                        });

                        if (context.mounted) Navigator.pop(context);
                        _cargar();
                      } catch (e) {
                        debugPrint('❌ Error insertando hospedaje: $e');
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
      appBar: AppBar(title: const Text('Hospedaje')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? const Center(child: Text('No hay registros'))
              : ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final h = _items[i];
                  return Card(
                    margin: const EdgeInsets.all(8),
                    child: ListTile(
                      title: Text('${h['descripcion_fuente']}'),
                      subtitle: Text(
                        'Alojamiento: ${h['alojamiento']}\n'
                        'Unidad: ${h['unidad']}\n'
                        'Visitantes/noches: ${h['visitantes']}\n'
                        'Emisiones: ${h['emisiones_tco2e']} tCO₂e\n'
                        'Periodo: ${h['periodo']?['ano']}-${h['periodo']?['mes']}',
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
