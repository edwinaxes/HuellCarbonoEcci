import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehiculoPage extends StatefulWidget {
  const VehiculoPage({super.key});

  @override
  State<VehiculoPage> createState() => _VehiculoPageState();
}

class _VehiculoPageState extends State<VehiculoPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _vehiculos = [];

  @override
  void initState() {
    super.initState();
    _cargarVehiculos();
  }

  Future<void> _cargarVehiculos() async {
    try {
      final data = await supabase
          .from('vehiculo')
          .select('id, placa, tipo, combustible, rendimiento_km_gal')
          .order('placa');
      setState(() {
        _vehiculos = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando vehículos: $e");
      setState(() {
        _loading = false;
        _vehiculos = [];
      });
    }
  }

  /// 👉 Formulario para registrar un vehículo
  Future<void> _agregarVehiculo() async {
    final placaCtrl = TextEditingController();
    final rendimientoCtrl = TextEditingController();

    String? tipoVehiculo;
    String? tipoCombustible;

    // Traer tipos de combustible
    final tiposData = await supabase
        .from('tipos_combustible_ref')
        .select('nombre')
        .order('nombre');
    final tiposCombustible = List<String>.from(
      tiposData.map((e) => e['nombre'].toString()),
    );

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text("Registrar vehículo"),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: placaCtrl,
                          decoration: const InputDecoration(
                            labelText: "Placa del vehículo *",
                            hintText: "ABC123",
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 12),

                        // SOLO automovil, camioneta, bus
                        DropdownButtonFormField<String>(
                          value: tipoVehiculo,
                          hint: const Text("Tipo de vehículo *"),
                          items: const [
                            DropdownMenuItem(
                              value: "automovil",
                              child: Text("Automóvil"),
                            ),
                            DropdownMenuItem(
                              value: "camioneta",
                              child: Text("Camioneta"),
                            ),
                            DropdownMenuItem(value: "bus", child: Text("Bus")),
                          ],
                          onChanged: (v) => setState(() => tipoVehiculo = v),
                        ),
                        const SizedBox(height: 12),

                        DropdownButton<String>(
                          value: tipoCombustible,
                          hint: const Text("Tipo de combustible *"),
                          isExpanded: true,
                          underline: const SizedBox(),
                          items:
                              tiposCombustible
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setState(() => tipoCombustible = v),
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: rendimientoCtrl,
                          decoration: const InputDecoration(
                            labelText: "Rendimiento (km/gal) *",
                            hintText: "12.5",
                          ),
                          keyboardType: TextInputType.number,
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
                      if (placaCtrl.text.isEmpty ||
                          tipoVehiculo == null ||
                          tipoCombustible == null ||
                          rendimientoCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Por favor, complete todos los campos obligatorios (*)",
                            ),
                          ),
                        );
                        return;
                      }

                      try {
                        await supabase.from('vehiculo').insert({
                          'placa': placaCtrl.text.toUpperCase(),
                          'tipo': tipoVehiculo, // automovil | camioneta | bus
                          'combustible': tipoCombustible,
                          'rendimiento_km_gal':
                              double.tryParse(rendimientoCtrl.text) ?? 0,
                          // ❌ sin sede_id
                        });

                        if (context.mounted) Navigator.pop(context);
                        _cargarVehiculos();
                      } catch (e) {
                        debugPrint("❌ Error insertando vehículo: $e");
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

  /// 👉 Eliminar vehículo
  Future<void> _eliminarVehiculo(int id, String placa) async {
    final confirmar = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Confirmar eliminación"),
            content: Text("¿Está seguro de eliminar el vehículo $placa?"),
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

    if (confirmar == true) {
      try {
        await supabase.from('vehiculo').delete().eq('id', id);
        _cargarVehiculos();
      } catch (e) {
        debugPrint("❌ Error eliminando vehículo: $e");
        if (!mounted) return;
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
        title: const Text("Gestión de Vehículos"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarVehiculos,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _vehiculos.isEmpty
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_car, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      "No hay vehículos registrados",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                itemCount: _vehiculos.length,
                itemBuilder: (context, index) {
                  final v = _vehiculos[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      leading: _getIconByTipo(v['tipo']),
                      title: Text(
                        v['placa'] ?? 'Sin placa',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Tipo: ${_getTipoText(v['tipo'])}"),
                          Text(
                            "Combustible: ${v['combustible'] ?? 'Desconocido'}",
                          ),
                          Text(
                            "Rendimiento: ${v['rendimiento_km_gal']} km/gal",
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminarVehiculo(v['id'], v['placa']),
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarVehiculo,
        child: const Icon(Icons.add),
      ),
    );
  }

  // Helpers para iconos y textos
  Icon _getIconByTipo(String? tipo) {
    switch (tipo) {
      case 'automovil':
        return const Icon(Icons.directions_car, color: Colors.grey);
      case 'camioneta':
        return const Icon(
          Icons.local_shipping,
          color: Colors.green,
        ); // si tu SDK no tiene Icons.suv, usa local_shipping
      case 'bus':
        return const Icon(Icons.directions_bus, color: Colors.blue);
      default:
        return const Icon(Icons.help_outline, color: Colors.grey);
    }
  }

  String _getTipoText(String? tipo) {
    switch (tipo) {
      case 'automovil':
        return 'Automóvil';
      case 'camioneta':
        return 'Camioneta';
      case 'bus':
        return 'Bus';
      default:
        return tipo ?? 'Desconocido';
    }
  }
}
