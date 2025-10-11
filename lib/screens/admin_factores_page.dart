import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla: Administración → Factores y fórmulas
/// - Muestra factores (energía/combustibles, residuos, papel, refrigerantes, lubricantes)
/// - Explica fórmula usada y dónde aplica en la BD
/// - Soporta búsqueda por texto
class AdminFactoresPage extends StatefulWidget {
  const AdminFactoresPage({super.key});

  @override
  State<AdminFactoresPage> createState() => _AdminFactoresPageState();
}

class _AdminFactoresPageState extends State<AdminFactoresPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late final TabController _tab;
  bool _loading = true;
  String _q = '';

  // Datos
  List<Map<String, dynamic>> _factorEmision =
      []; // join con fuente_emision + unidad_medida
  List<Map<String, dynamic>> _combustiblesRef = []; // tipos_combustible_ref
  List<Map<String, dynamic>> _residuosFactor =
      []; // factor_emision_residuos + joins
  List<Map<String, dynamic>> _papelFactor = []; // factor_emision_papel
  List<Map<String, dynamic>> _refrigerantes = []; // refrigerantes_ref

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      // Factores generales: factor_emision + fuente_emision + unidad_medida
      final f1 = await supabase
          .from('factor_emision')
          .select(
            'valor, fuente_dato, version, vigente_desde, gas, '
            'fuente_emision(id, subtipo, descripcion, categoria_id), '
            'unidad_medida(id, codigo, descripcion)',
          )
          .order('vigente_desde', ascending: false);

      // Combustibles catálogo (para estacionarios/móviles si se usa)
      final f2 = await supabase
          .from('tipos_combustible_ref')
          .select('nombre, categoria, factor_kgco2e')
          .order('nombre');

      // Residuos: factor_emision_residuos + subcategoría + categoría
      final f3 = await supabase
          .from('factor_emision_residuos')
          .select(
            'factor_kgco2e, fuente, version, vigente_desde, '
            'subcategorias_residuos_ref(id, nombre, '
            'categorias_residuos_ref(id, nombre))',
          )
          .order('vigente_desde', ascending: false);

      // Papel
      final f4 = await supabase
          .from('factor_emision_papel')
          .select('tipo_papel, factor_kgco2e, fuente')
          .order('tipo_papel');

      // Refrigerantes
      final f5 = await supabase
          .from('refrigerantes_ref')
          .select('nombre, factor_kgco2e')
          .order('nombre');

      setState(() {
        _factorEmision = List<Map<String, dynamic>>.from(f1 as List);
        _combustiblesRef = List<Map<String, dynamic>>.from(f2 as List);
        _residuosFactor = List<Map<String, dynamic>>.from(f3 as List);
        _papelFactor = List<Map<String, dynamic>>.from(f4 as List);
        _refrigerantes = List<Map<String, dynamic>>.from(f5 as List);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando factores: $e')));
    }
  }

  // =================== Helpers UI ===================

  bool _match(Object? v) {
    if (_q.trim().isEmpty) return true;
    final q = _q.toLowerCase();
    return (v?.toString().toLowerCase() ?? '').contains(q);
  }

  Widget _headerInfo({
    required String titulo,
    required String formula,
    required String aplicaA,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fórmula: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Expanded(child: Text(formula)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Se usa en: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Expanded(child: Text(aplicaA)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =================== Tabs ===================

  Widget _tabFactoresGenerales() {
    // Mapeo de subtipo a explicación de uso típico y fórmula
    // (nota: la fórmula global tCO2e = actividad × factor(kg)/1000)
    // Aquí solo personalizamos ejemplos comunes.
    String usoPara(String subtipo, String unidad) {
      final u = unidad.toLowerCase();
      if (u == 'kwh') {
        return 'Consumo de energía eléctrica (tabla consumo_energia.kwh).';
      } else if (u == 'km') {
        return 'Transporte (distancia en km), p.ej. transporte_personas.distancia_km.';
      } else if (u == 'galones' || u == 'm3' || u == 'kg' || u == 'l') {
        return 'Combustibles (estacionarios/móviles) según unidad. '
            'consumo_combustible.consumo/galones según corresponda.';
      }
      return 'Según subtipo y unidad asociada en tus formularios.';
    }

    final list =
        _factorEmision.where((e) {
          final fe = e['fuente_emision'] as Map?;
          final um = e['unidad_medida'] as Map?;
          return _match(fe?['subtipo']) ||
              _match(fe?['descripcion']) ||
              _match(um?['codigo']) ||
              _match(e['valor']) ||
              _match(e['fuente_dato']) ||
              _match(e['version']);
        }).toList();

    return Column(
      children: [
        _headerInfo(
          titulo: 'Factores generales (factor_emision)',
          formula: 'tCO₂e = Dato_actividad × (kgCO₂e/Unidad) ÷ 1000',
          aplicaA:
              'Energía eléctrica (kWh), transporte por km, combustibles por unidad '
              '(galones/m³/kg/L), viajes si se parametriza por distancia, etc.',
        ),
        Expanded(
          child:
              list.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final fe = Map<String, dynamic>.from(
                        row['fuente_emision'] as Map? ?? {},
                      );
                      final um = Map<String, dynamic>.from(
                        row['unidad_medida'] as Map? ?? {},
                      );
                      final subtipo = fe['subtipo'] ?? '-';
                      final unidad = um['codigo'] ?? '-';
                      final valor = (row['valor'] as num?)?.toDouble();
                      final fuente = row['fuente_dato'] ?? '';
                      final version = row['version'] ?? '';
                      final vd = row['vigente_desde'] ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ExpansionTile(
                          leading: const Icon(Icons.functions),
                          title: Text('$subtipo — $unidad'),
                          subtitle: Text(
                            'Valor: ${valor?.toStringAsFixed(6) ?? '-'} kgCO₂e/$unidad',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          children: [
                            _kv('Uso típico', usoPara(subtipo, unidad)),
                            _kv(
                              'Fórmula',
                              'tCO₂e = actividad($unidad) × ${valor ?? 0} / 1000',
                            ),
                            _kv('Fuente', fuente.toString()),
                            _kv('Versión', version.toString()),
                            _kv('Vigente desde', vd.toString()),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _tabCombustibles() {
    final list =
        _combustiblesRef.where((e) {
          return _match(e['nombre']) ||
              _match(e['categoria']) ||
              _match(e['factor_kgco2e']);
        }).toList();

    return Column(
      children: [
        _headerInfo(
          titulo: 'Combustibles (tipos_combustible_ref)',
          formula: 'tCO₂e = Consumo(unidad) × (kgCO₂e/unidad) ÷ 1000',
          aplicaA:
              'Tabla consumo_combustible: estacionarios (vehiculo_id NULL) y móviles (vehiculo_id NOT NULL).',
        ),
        Expanded(
          child:
              list.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final nombre = row['nombre'] ?? '-';
                      final cat = row['categoria'] ?? '-';
                      final factor = (row['factor_kgco2e'] as num?)?.toDouble();

                      // Unidad depende de la categoría (según tu app):
                      // Liquido → galones, Gaseoso → m3, Sólido → kg
                      final unidad = switch (cat) {
                        'Liquido' => 'galones',
                        'Gaseoso' => 'm3',
                        'Solido' => 'kg',
                        _ => 'unidad',
                      };

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ExpansionTile(
                          leading: const Icon(Icons.local_gas_station),
                          title: Text(nombre),
                          subtitle: Text(
                            'Categoría: $cat • Factor: ${factor ?? 0} kgCO₂e/$unidad',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          children: [
                            _kv('Unidad esperada', unidad),
                            _kv(
                              'Fórmula',
                              'tCO₂e = consumo($unidad) × ${factor ?? 0} / 1000',
                            ),
                            _kv(
                              'Se usa en',
                              'consumo_combustible.consumo / galones (según unidad)',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _tabResiduos() {
    final list =
        _residuosFactor.where((e) {
          final sc = Map<String, dynamic>.from(
            e['subcategorias_residuos_ref'] as Map? ?? {},
          );
          final cat = Map<String, dynamic>.from(
            sc['categorias_residuos_ref'] as Map? ?? {},
          );
          return _match(sc['nombre']) ||
              _match(cat['nombre']) ||
              _match(e['factor_kgco2e']) ||
              _match(e['fuente']) ||
              _match(e['version']);
        }).toList();

    return Column(
      children: [
        _headerInfo(
          titulo: 'Residuos (factor_emision_residuos)',
          formula: 'tCO₂e = kg_residuo × (kgCO₂e/kg) ÷ 1000',
          aplicaA: 'Tabla residuos (antes residuos_solidos): emisiones_tco2e.',
        ),
        Expanded(
          child:
              list.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final sc = Map<String, dynamic>.from(
                        row['subcategorias_residuos_ref'] as Map? ?? {},
                      );
                      final cat = Map<String, dynamic>.from(
                        sc['categorias_residuos_ref'] as Map? ?? {},
                      );
                      final subNombre = sc['nombre'] ?? '-';
                      final catNombre = cat['nombre'] ?? '-';
                      final factor =
                          (row['factor_kgco2e'] as num?)?.toDouble() ?? 0.0;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ExpansionTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text('$catNombre → $subNombre'),
                          subtitle: Text(
                            'Factor: ${factor.toStringAsFixed(6)} kgCO₂e/kg',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          children: [
                            _kv(
                              'Fórmula',
                              'tCO₂e = kg × ${factor.toStringAsFixed(6)} / 1000',
                            ),
                            _kv('Fuente', (row['fuente'] ?? '').toString()),
                            _kv('Versión', (row['version'] ?? '').toString()),
                            _kv(
                              'Vigente desde',
                              (row['vigente_desde'] ?? '').toString(),
                            ),
                            _kv(
                              'Se usa en',
                              'Formulario de residuos → emisiones_tco2e',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _tabPapel() {
    final list =
        _papelFactor.where((e) {
          return _match(e['tipo_papel']) ||
              _match(e['factor_kgco2e']) ||
              _match(e['fuente']);
        }).toList();

    return Column(
      children: [
        _headerInfo(
          titulo: 'Papel (factor_emision_papel)',
          formula: 'tCO₂e = kg_papel × (kgCO₂e/kg) ÷ 1000',
          aplicaA: 'Tabla consumo_papel.emisiones_tco2e.',
        ),
        Expanded(
          child:
              list.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final tipo = row['tipo_papel'] ?? '-';
                      final factor =
                          (row['factor_kgco2e'] as num?)?.toDouble() ?? 0.0;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ExpansionTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(tipo),
                          subtitle: Text(
                            'Factor: ${factor.toStringAsFixed(6)} kgCO₂e/kg',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          children: [
                            _kv(
                              'Fórmula',
                              'tCO₂e = kg × ${factor.toStringAsFixed(6)} / 1000',
                            ),
                            _kv('Fuente', (row['fuente'] ?? '').toString()),
                            _kv(
                              'Se usa en',
                              'consumo_papel (bond / reciclado) → emisiones_tco2e',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _tabRefrigerantes() {
    final list =
        _refrigerantes.where((e) {
          return _match(e['nombre']) || _match(e['factor_kgco2e']);
        }).toList();

    return Column(
      children: [
        _headerInfo(
          titulo: 'Refrigerantes (refrigerantes_ref)',
          formula: 'tCO₂e = kg_refrigerante × (kgCO₂e/kg) ÷ 1000',
          aplicaA:
              'Tabla emisiones_fugitivas: cantidad_kg × factor_kgco2e / 1000.',
        ),
        Expanded(
          child:
              list.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final nombre = row['nombre'] ?? '-';
                      final factor =
                          (row['factor_kgco2e'] as num?)?.toDouble() ?? 0.0;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ExpansionTile(
                          leading: const Icon(Icons.ac_unit_outlined),
                          title: Text(nombre),
                          subtitle: Text(
                            'Factor: ${factor.toStringAsFixed(2)} kgCO₂e/kg',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          children: [
                            _kv(
                              'Fórmula',
                              'tCO₂e = kg × ${factor.toStringAsFixed(2)} / 1000',
                            ),
                            _kv(
                              'Se usa en',
                              'emisiones_fugitivas.emisiones_tco2e (trigger/cliente)',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  // key-value line
  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  // =================== Build ===================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración · Factores y fórmulas'),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Generales'),
            Tab(text: 'Combustibles'),
            Tab(text: 'Residuos'),
            Tab(text: 'Papel'),
            Tab(text: 'Refrigerantes'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Buscador
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar (nombre, unidad, versión, fuente...)',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                      controller: _tab,
                      children: [
                        _tabFactoresGenerales(),
                        _tabCombustibles(),
                        _tabResiduos(),
                        _tabPapel(),
                        _tabRefrigerantes(),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}
