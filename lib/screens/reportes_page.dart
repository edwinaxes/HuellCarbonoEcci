import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;

  // Para "anual" trae filas de reporte_anual. Para "periodo" construimos una
  // lista con los campos por periodo_id. Para "totales" usamos la suma local.
  List<dynamic> _reportes = [];
  List<dynamic> _periodos = [];

  String _modo = "anual"; // "anual" | "periodo" | "totales"

  @override
  void initState() {
    super.initState();
    _cargarPeriodos();
    _cargarReportes();
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

  Future<void> _cargarReportes() async {
    if (_modo == "totales") {
      // Para totales usamos lo que ya esté cargado (de periodo o anual).
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      if (_modo == "anual") {
        final data = await supabase
            .from('reporte_anual')
            .select()
            .order('ano', ascending: true);
        setState(() {
          _reportes = data;
          _loading = false;
        });
        return;
      }

      // ================== POR PERIODO ==================
      // Todos estos campos deben estar en tCO2e en la BD
      final energia = await supabase
          .from('consumo_energia')
          .select('periodo_id, emisiones_tco2e');

      // Combustibles estacionarios: consumo_combustible con vehiculo_id IS NULL
      final combEst = await supabase
          .from('consumo_combustible')
          .select('periodo_id, emisiones_tco2e, vehiculo_id')
          .isFilter('vehiculo_id', null);

      // Combustibles móviles: consumo_combustible con vehiculo_id NOT NULL
      final combMov = await supabase
          .from('consumo_combustible')
          .select('periodo_id, emisiones_tco2e, vehiculo_id')
          .not('vehiculo_id', 'is', null);

      // Transporte empleados
      final transpEmpl = await supabase
          .from('desplazamientos_empleados')
          .select('periodo_id, emisiones_tco2e');

      // Larga distancia (bus)
      final busLD = await supabase
          .from('transporte_personas')
          .select('periodo_id, emisiones_tco2e');

      // Viajes aéreos
      final viajes = await supabase
          .from('viajes_aereos')
          .select('periodo_id, emisiones_tco2e');

      // Papel
      final papel = await supabase
          .from('consumo_papel')
          .select('periodo_id, emisiones_tco2e');

      // Residuos (antes residuos_sólidos, ahora etiqueta "Residuos")
      final residuos = await supabase
          .from('residuos_solidos')
          .select('periodo_id, emisiones_tco2e');

      // Emisiones fugitivas (refrigerantes)
      final fugitivas = await supabase
          .from('emisiones_fugitivas')
          .select('periodo_id, emisiones_tco2e');

      // Lubricantes
      final lubricantes = await supabase
          .from('emisiones_lubricantes')
          .select('periodo_id, emisiones_tco2e');

      // Procesos industriales (campo emisiones_co2e)
      final procesosInd = await supabase
          .from('procesos_industriales')
          .select('periodo_id, emisiones_co2e');

      // Remociones (se restan)
      final forestal = await supabase
          .from('remocion_forestal')
          .select('periodo_id, tco2e_ev');

      final reciclaje = await supabase
          .from('remocion_reciclaje')
          .select('periodo_id, tco2e_ev');

      final Map<int, Map<String, dynamic>> byPeriodo = {};

      void ensure(int p) {
        byPeriodo.putIfAbsent(p, () {
          return {
            // ENTRADAS POSITIVAS
            "energia": 0.0,
            "combustibles_estacionarios": 0.0,
            "combustibles_moviles": 0.0,
            "transporte_empleados": 0.0,
            "transporte_larga_dist_bus": 0.0,
            "viajes_aereos": 0.0,
            "papel": 0.0,
            "residuos": 0.0,
            "emisiones_fugitivas": 0.0,
            "lubricantes": 0.0,
            "procesos_industriales": 0.0,
            // REMOCIONES (NEGATIVO)
            "remocion_forestal": 0.0,
            "remocion_reciclaje": 0.0,
            // TOTAL
            "huella_co2e": 0.0,
          };
        });
      }

      void addEmis(
        List<dynamic> lista,
        String campoPeriodo,
        String campoEmis,
        String alias,
      ) {
        for (final e in lista) {
          final int? p = e[campoPeriodo] as int?;
          if (p == null) continue;
          ensure(p);
          final v = _toDouble(e[campoEmis]);
          byPeriodo[p]![alias] = _toDouble(byPeriodo[p]![alias]) + v;
          byPeriodo[p]!["huella_co2e"] =
              _toDouble(byPeriodo[p]!["huella_co2e"]) + v;
        }
      }

      // Sumar todo (en toneladas CO2e) — orden no afecta el total, es solo visual
      addEmis(energia, 'periodo_id', 'emisiones_tco2e', 'energia');
      addEmis(
        combEst,
        'periodo_id',
        'emisiones_tco2e',
        'combustibles_estacionarios',
      );
      addEmis(combMov, 'periodo_id', 'emisiones_tco2e', 'combustibles_moviles');
      addEmis(
        transpEmpl,
        'periodo_id',
        'emisiones_tco2e',
        'transporte_empleados',
      );
      addEmis(
        busLD,
        'periodo_id',
        'emisiones_tco2e',
        'transporte_larga_dist_bus',
      );
      addEmis(viajes, 'periodo_id', 'emisiones_tco2e', 'viajes_aereos');
      addEmis(papel, 'periodo_id', 'emisiones_tco2e', 'papel');
      addEmis(residuos, 'periodo_id', 'emisiones_tco2e', 'residuos');
      addEmis(
        fugitivas,
        'periodo_id',
        'emisiones_tco2e',
        'emisiones_fugitivas',
      );
      addEmis(lubricantes, 'periodo_id', 'emisiones_tco2e', 'lubricantes');

      for (final e in procesosInd) {
        final int? p = e['periodo_id'] as int?;
        if (p == null) continue;
        ensure(p);
        final v = _toDouble(e['emisiones_co2e']);
        byPeriodo[p]!['procesos_industriales'] =
            _toDouble(byPeriodo[p]!['procesos_industriales']) + v;
        byPeriodo[p]!['huella_co2e'] =
            _toDouble(byPeriodo[p]!['huella_co2e']) + v;
      }

      // Remociones (restar del total)
      for (final e in forestal) {
        final int? p = e['periodo_id'] as int?;
        if (p == null) continue;
        ensure(p);
        final v = _toDouble(e['tco2e_ev']);
        byPeriodo[p]!['remocion_forestal'] =
            _toDouble(byPeriodo[p]!['remocion_forestal']) + v;
        byPeriodo[p]!['huella_co2e'] =
            _toDouble(byPeriodo[p]!['huella_co2e']) - v;
      }
      for (final e in reciclaje) {
        final int? p = e['periodo_id'] as int?;
        if (p == null) continue;
        ensure(p);
        final v = _toDouble(e['tco2e_ev']);
        byPeriodo[p]!['remocion_reciclaje'] =
            _toDouble(byPeriodo[p]!['remocion_reciclaje']) + v;
        byPeriodo[p]!['huella_co2e'] =
            _toDouble(byPeriodo[p]!['huella_co2e']) - v;
      }

      final lista =
          byPeriodo.entries
              .map((e) => {"periodo_id": e.key, ...e.value})
              .toList()
            ..sort(
              (a, b) =>
                  (a['periodo_id'] as int).compareTo(b['periodo_id'] as int),
            );

      setState(() {
        _reportes = lista;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error cargando reportes: $e");
      setState(() {
        _reportes = [];
        _loading = false;
      });
    }
  }

  // ===== Helpers =====
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Widget _buildTotalItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Expanded(child: Text(label)), Text(value)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totales = _calcularTotales();

    return Scaffold(
      appBar: AppBar(title: const Text("Reportes de Huella de Carbono")),
      body: Column(
        children: [
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() => _modo = "anual");
                    _cargarReportes();
                  },
                  child: const Text("Anuales"),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _modo = "periodo");
                    _cargarReportes();
                  },
                  child: const Text("Por periodo"),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _modo = "totales");
                  },
                  child: const Text("Totales"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                _loading && _modo != "totales"
                    ? const Center(child: CircularProgressIndicator())
                    : _modo == "anual"
                    ? _buildAnualView()
                    : _modo == "periodo"
                    ? _buildPeriodoView()
                    : _buildTotalesView(totales),
          ),
        ],
      ),
    );
  }

  // ===== Vistas =====
  Widget _buildAnualView() {
    return ListView.builder(
      itemCount: _reportes.length,
      itemBuilder: (context, i) {
        final r = _reportes[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text("Año: ${r['ano']}"),
            subtitle: Text(
              "Total CO₂e: ${_toDouble(r['tco2e_total']).toStringAsFixed(2)} t",
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeriodoView() {
    return ListView.builder(
      itemCount: _reportes.length,
      itemBuilder: (context, i) {
        final r = Map<String, dynamic>.from(_reportes[i] as Map);
        final periodoId = r['periodo_id'];
        final periodoInfo = _periodos.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['id'] == periodoId,
          orElse: () => {'ano': 'N/A', 'mes': 'N/A'},
        );

        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Periodo: ${periodoInfo['ano']}-${periodoInfo['mes']}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // ===== Orden como en la app =====
                _buildTotalItem(
                  "⚡ Energía",
                  "${_toDouble(r['energia']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "🔥 Combustibles estacionarios",
                  "${_toDouble(r['combustibles_estacionarios']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "🚗 Combustibles móviles",
                  "${_toDouble(r['combustibles_moviles']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "🧍 Transporte empleados",
                  "${_toDouble(r['transporte_empleados']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "🚌 Larga distancia (Bus)",
                  "${_toDouble(r['transporte_larga_dist_bus']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "✈️ Viajes aéreos",
                  "${_toDouble(r['viajes_aereos']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "📄 Papel",
                  "${_toDouble(r['papel']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "🗑️ Residuos",
                  "${_toDouble(r['residuos']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "❄️ Emisiones fugitivas (refrigerantes)",
                  "${_toDouble(r['emisiones_fugitivas']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "🛢️ Lubricantes",
                  "${_toDouble(r['lubricantes']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "🏭 Procesos industriales",
                  "${_toDouble(r['procesos_industriales']).toStringAsFixed(2)} t CO₂e",
                ),

                const Divider(),
                _buildTotalItem(
                  "🌳 Remoción forestal",
                  "- ${_toDouble(r['remocion_forestal']).toStringAsFixed(2)} t CO₂e",
                ),
                _buildTotalItem(
                  "♻️ Reciclaje",
                  "- ${_toDouble(r['remocion_reciclaje']).toStringAsFixed(2)} t CO₂e",
                ),
                const SizedBox(height: 8),

                Text(
                  "Huella CO₂e del periodo: ${_toDouble(r['huella_co2e']).toStringAsFixed(2)} t",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTotalesView(Map<String, dynamic> t) {
    return SingleChildScrollView(
      child: Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "📊 Totales Generales",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildTotalItem(
                "⚡ Energía",
                "${_toDouble(t['energia']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "🔥 Combustibles estacionarios",
                "${_toDouble(t['combustibles_estacionarios']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "🚗 Combustibles móviles",
                "${_toDouble(t['combustibles_moviles']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "🧍 Transporte empleados",
                "${_toDouble(t['transporte_empleados']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "🚌 Larga distancia (Bus)",
                "${_toDouble(t['transporte_larga_dist_bus']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "✈️ Viajes aéreos",
                "${_toDouble(t['viajes_aereos']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "📄 Papel",
                "${_toDouble(t['papel']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "🗑️ Residuos",
                "${_toDouble(t['residuos']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "❄️ Emisiones fugitivas (refrigerantes)",
                "${_toDouble(t['emisiones_fugitivas']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "🛢️ Lubricantes",
                "${_toDouble(t['lubricantes']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "🏭 Procesos industriales",
                "${_toDouble(t['procesos_industriales']).toStringAsFixed(2)} t CO₂e",
              ),
              const Divider(),
              _buildTotalItem(
                "🌳 Remoción forestal",
                "- ${_toDouble(t['remocion_forestal']).toStringAsFixed(2)} t CO₂e",
              ),
              _buildTotalItem(
                "♻️ Reciclaje",
                "- ${_toDouble(t['remocion_reciclaje']).toStringAsFixed(2)} t CO₂e",
              ),
              const SizedBox(height: 8),
              Text(
                "Huella Total CO₂e: ${_toDouble(t['huella_co2e']).toStringAsFixed(2)} t",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _calcularTotales() {
    final t = <String, dynamic>{
      "energia": 0.0,
      "combustibles_estacionarios": 0.0,
      "combustibles_moviles": 0.0,
      "transporte_empleados": 0.0,
      "transporte_larga_dist_bus": 0.0,
      "viajes_aereos": 0.0,
      "papel": 0.0,
      "residuos": 0.0,
      "emisiones_fugitivas": 0.0,
      "lubricantes": 0.0,
      "procesos_industriales": 0.0,
      "remocion_forestal": 0.0,
      "remocion_reciclaje": 0.0,
      "huella_co2e": 0.0,
    };

    for (final r in _reportes) {
      final m = Map<String, dynamic>.from(r as Map);
      t["energia"] += _toDouble(m["energia"]);
      t["combustibles_estacionarios"] += _toDouble(
        m["combustibles_estacionarios"],
      );
      t["combustibles_moviles"] += _toDouble(m["combustibles_moviles"]);
      t["transporte_empleados"] += _toDouble(m["transporte_empleados"]);
      t["transporte_larga_dist_bus"] += _toDouble(
        m["transporte_larga_dist_bus"],
      );
      t["viajes_aereos"] += _toDouble(m["viajes_aereos"]);
      t["papel"] += _toDouble(m["papel"]);
      t["residuos"] += _toDouble(m["residuos"]);
      t["emisiones_fugitivas"] += _toDouble(m["emisiones_fugitivas"]);
      t["lubricantes"] += _toDouble(m["lubricantes"]);
      t["procesos_industriales"] += _toDouble(m["procesos_industriales"]);
      t["remocion_forestal"] += _toDouble(m["remocion_forestal"]);
      t["remocion_reciclaje"] += _toDouble(m["remocion_reciclaje"]);
      t["huella_co2e"] += _toDouble(m["huella_co2e"]);
    }
    return t;
  }
}
