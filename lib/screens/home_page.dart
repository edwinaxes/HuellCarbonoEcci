import 'package:flutter/material.dart';

// Páginas
import 'procesos_industriales_page.dart';
import 'emisiones_fugitivas_page.dart';
import 'lubricantes_page.dart';
import 'consumo_energia_page.dart';
import 'viajes_aereos_page.dart';
import 'transporte_empleados_page.dart';
import 'transporte_personas_page.dart';
import 'hospedaje_page.dart';
import 'consumo_papel.dart';
import 'residuos_solidos_page.dart';
import 'inventario_forest_page.dart';
import 'remocion_reciclaje_page.dart';
import 'reportes_page.dart';
import 'test_connection_page.dart';
import 'vehiculo_page.dart';
import 'consumo_estacionario_page.dart';
import 'consumo_movil_page.dart';
import 'admin_factores_page.dart'; // ✅ Nueva pantalla

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 6,
        backgroundColor: Colors.green[700],
        centerTitle: true,
        title: const Text(
          "Huella de Carbono ECCI",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),

            _buildSectionTitle("🌍 Emisiones Directas"),
            _buildGridSection(context, [
              _buildModuleCard(
                context,
                icon: Icons.local_gas_station,
                color1: Colors.orange,
                color2: Colors.deepOrange,
                title: "Combustibles estacionarios",
                page: const ConsumoEstacionarioPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.directions_car,
                color1: Colors.red,
                color2: Colors.redAccent,
                title: "Combustibles móviles",
                page: const ConsumoMovilPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.factory,
                color1: Colors.blueGrey,
                color2: Colors.blue,
                title: "Procesos industriales",
                page: const ProcesosIndustrialesPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.ac_unit,
                color1: Colors.cyan,
                color2: Colors.blueAccent,
                title: "Emisiones fugitivas",
                page: const EmisionesFugitivasPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.oil_barrel,
                color1: Colors.brown,
                color2: Colors.orange,
                title: "Lubricantes",
                page: const LubricantesPage(),
              ),
            ]),

            const SizedBox(height: 24),
            _buildSectionTitle("⚡ Emisiones Indirectas"),
            _buildGridSection(context, [
              _buildModuleCard(
                context,
                icon: Icons.flash_on,
                color1: Colors.yellow,
                color2: Colors.amber,
                title: "Electricidad",
                page: const ConsumoEnergiaPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.airplanemode_active,
                color1: Colors.cyan,
                color2: Colors.teal,
                title: "Viajes aéreos",
                page: const ViajesAereosPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.directions_walk,
                color1: Colors.lightGreen,
                color2: Colors.green,
                title: "Transporte empleados",
                page: const TransporteEmpleadosPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.directions_bus,
                color1: Colors.deepPurple,
                color2: Colors.purple,
                title: "Transporte de Personas",
                page: const TransportePersonasPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.hotel,
                color1: Colors.indigo,
                color2: Colors.blue,
                title: "Hospedaje",
                page: const HospedajePage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.description,
                color1: Colors.brown,
                color2: Colors.deepOrange,
                title: "Consumo de papel",
                page: const ConsumoPapelPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.delete,
                color1: Colors.red,
                color2: Colors.deepOrange,
                title: "Residuos",
                page: const ResiduosSolidosPage(),
              ),
            ]),

            const SizedBox(height: 24),
            _buildSectionTitle("🌳 Remociones"),
            _buildGridSection(context, [
              _buildModuleCard(
                context,
                icon: Icons.park,
                color1: Colors.green,
                color2: Colors.teal,
                title: "Inventario forestal",
                page: const InventarioForestPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.recycling,
                color1: Colors.teal,
                color2: Colors.green,
                title: "Residuos aprovechables",
                page: const ResiduosAprovechablesPage(),
              ),
            ]),

            const SizedBox(height: 24),
            _buildSectionTitle("📊 Huella de carbono"),
            _buildGridSection(context, [
              _buildModuleCard(
                context,
                icon: Icons.analytics,
                color1: Colors.deepPurple,
                color2: Colors.indigo,
                title: "Reportes",
                page: const ReportesPage(),
              ),
            ]),

            const SizedBox(height: 24),
            _buildSectionTitle("⚙️ Administración"),
            _buildGridSection(context, [
              _buildModuleCard(
                context,
                icon: Icons.wifi_find_rounded,
                color1: Colors.blueGrey,
                color2: Colors.blue,
                title: "Probar conexión",
                page: const TestConnectionPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.directions_car,
                color1: Colors.purple,
                color2: Colors.deepPurple,
                title: "Insertar vehículos",
                page: const VehiculoPage(),
              ),
              _buildModuleCard(
                context,
                icon: Icons.rule, // o Icons.functions
                color1: Colors.indigo,
                color2: Colors.blueAccent,
                title: "Factores y fórmulas",
                page: const AdminFactoresPage(),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ===== HEADER =====
  Widget _buildHeader() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.eco, size: 50, color: Colors.green),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                "Sistema de Cálculo\nHuella de Carbono",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== SUBTÍTULO =====
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  // ===== GRID (Responsivo) =====
  Widget _buildGridSection(BuildContext context, List<Widget> cards) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount =
        width >= 1100
            ? 4
            : width >= 800
            ? 3
            : 2;

    return GridView.count(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  // ===== CARD =====
  Widget _buildModuleCard(
    BuildContext context, {
    required IconData icon,
    required Color color1,
    required Color color2,
    required String title,
    required Widget page,
  }) {
    return InkWell(
      onTap:
          () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color1.withOpacity(0.8), color2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 50, color: Colors.white),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
