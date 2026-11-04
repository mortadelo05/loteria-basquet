// =========================================================================
// CÓDIGO MAESTRO COMPLETO Y BLINDADO: GESTIÓN DE LOTERÍA - CLUB DE BÀSQUET
// Plataforma: Flutter 3.27+ / Android SDK 34 / Modo Dual: Firestore + Local Autónomo
// =========================================================================

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:convert';

// Variable global de conectividad con Firebase
bool gFirebaseConectado = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Evitar la pantalla gris bajo cualquier fallo de inicialización
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFFF8F9FA),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sports_basketball, size: 64, color: Color(0xFF1F4E79)),
                const SizedBox(height: 16),
                const Text(
                  'Lotería Club Bàsquet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Iniciando en modo seguro autónomo...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F4E79),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Entrar a la Aplicación'),
                  onPressed: () => runApp(const ClubBasketApp()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  // 2. Intentar inicializar Firebase de forma segura y no bloqueante
  try {
    await Firebase.initializeApp();
    gFirebaseConectado = Firebase.apps.isNotEmpty;
  } catch (e) {
    debugPrint('Firebase no configurado o sin google-services.json. Iniciando Modo Local Autónomo: $e');
    gFirebaseConectado = false;
  }

  runApp(const ClubBasketApp());
}

class ClubBasketApp extends StatelessWidget {
  const ClubBasketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lotería Club Bàsquet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F4E79),
          primary: const Color(0xFF1F4E79),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F4E79),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _pinMaestro = '1234';
  bool _sesionTesoreriaActiva = false;
  String _filtroEquipo = 'Todos';

  // Almacén de jugadores local para cuando no haya Firebase configurado
  List<Map<String, dynamic>> _jugadoresLocales = [];
  bool _cargandoDatos = true;

  @override
  void initState() {
    super.initState();
    _inicializarDatos();
  }

  Future<void> _inicializarDatos() async {
    if (!gFirebaseConectado) {
      _cargarDatosLocales();
      // Si la lista está vacía, añadimos 2 jugadores iniciales de muestra
      if (_jugadoresLocales.isEmpty) {
        _jugadoresLocales = [
          {
            'id': '1',
            'nombre': 'Marc Soler Garcia',
            'equipo': 'Junior Masculí',
            'esPagoBeneficio': false,
            'talonario': '001-050',
            'papeletas': 20,
            'totalAPagar': 100.0,
            'pagado': 100.0,
            'notas': 'Pagado completo en mano',
          },
          {
            'id': '2',
            'nombre': 'Pol Rodriguez Valls',
            'equipo': 'Cadet Masculí',
            'esPagoBeneficio': true,
            'talonario': null,
            'papeletas': 0,
            'totalAPagar': 20.0,
            'pagado': 0.0,
            'notas': 'Modalidad aportación beneficio 20€',
          },
        ];
        _guardarDatosLocales();
      }
    }
    setState(() => _cargandoDatos = false);
  }

  void _guardarDatosLocales() {
    try {
      final file = File('/data/user/0/com.clubbasket.loteria/files/loteria_datos.json');
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsStringSync(jsonEncode(_jugadoresLocales));
    } catch (_) {
      try {
        final dir = Directory.systemTemp;
        File('${dir.path}/loteria_datos.json').writeAsStringSync(jsonEncode(_jugadoresLocales));
      } catch (_) {}
    }
  }

  void _cargarDatosLocales() {
    try {
      final file = File('/data/user/0/com.clubbasket.loteria/files/loteria_datos.json');
      if (file.existsSync()) {
        final raw = file.readAsStringSync();
        final List<dynamic> parsed = jsonDecode(raw);
        _jugadoresLocales = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
  }

  void _verificarPinYEjecutar(BuildContext context, VoidCallback accion) {
    if (_sesionTesoreriaActiva) {
      accion();
    } else {
      _mostrarDialogoPin(context, accion);
    }
  }

  void _mostrarDialogoPin(BuildContext context, VoidCallback onSuccess) {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFF1F4E79)),
            SizedBox(width: 8),
            Text('PIN de Tesorería'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Introduce el PIN de 4 dígitos para autorizar acciones de tesorería:',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'PIN (por defecto: 1234)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.password),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final pin = pinController.text.trim();
              if (pin == _pinMaestro) {
                setState(() => _sesionTesoreriaActiva = true);
                Navigator.pop(ctx);
                onSuccess();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sesión de tesorería desbloqueada con éxito'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN Incorrecto (El PIN por defecto es 1234)'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Acceder'),
          ),
        ],
      ),
    );
  }

  Future<void> _importarExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null && result.files.single.path != null) {
        final fileBytes = File(result.files.single.path!).readAsBytesSync();
        final excel = Excel.decodeBytes(fileBytes);
        int importados = 0;

        for (var nombrePestana in excel.tables.keys) {
          final sheet = excel.tables[nombrePestana];
          if (sheet == null) continue;
          final equipo = nombrePestana.trim();

          String obtenerTextoCelda(dynamic celda) {
            if (celda == null) return '';
            try {
              final dynamic v = celda.value;
              if (v != null) return v.toString().trim();
            } catch (_) {}
            return celda.toString().trim();
          }

          for (int i = 1; i < sheet.maxRows; i++) {
            final row = sheet.rows[i];
            if (row.isEmpty) continue;

            final dynamic cellA = row.isNotEmpty ? row[0] : null;
            final dynamic cellB = row.length > 1 ? row[1] : null;

            final String nombre = obtenerTextoCelda(cellA);
            final String apellido = obtenerTextoCelda(cellB);
            final String nombreCompleto = apellido.isNotEmpty ? '$nombre $apellido' : nombre;

            if (nombreCompleto.isEmpty) continue;

            final nuevoItem = {
              'id': 'jugador_${DateTime.now().microsecondsSinceEpoch}_$importados',
              'equipo': equipo,
              'nombre': nombreCompleto,
              'esPagoBeneficio': false,
              'talonario': null,
              'papeletas': 0,
              'totalAPagar': 0.0,
              'pagado': 0.0,
              'notas': '',
            };

            if (gFirebaseConectado) {
              await FirebaseFirestore.instance.collection('vendedores').add(nuevoItem);
            } else {
              _jugadoresLocales.add(nuevoItem);
            }
            importados++;
          }
        }

        if (!gFirebaseConectado) {
          _guardarDatosLocales();
          setState(() {});
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Importación completada! Se añadieron $importados jugadores.'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar Excel: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión Lotería Club Bàsquet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Importar Excel por Pestañas',
            onPressed: () => _verificarPinYEjecutar(context, _importarExcel),
          ),
          IconButton(
            icon: Icon(_sesionTesoreriaActiva ? Icons.lock_open : Icons.lock),
            tooltip: _sesionTesoreriaActiva ? 'Sesión de Tesorería Activa' : 'Bloqueado con PIN',
            onPressed: () {
              setState(() => _sesionTesoreriaActiva = !_sesionTesoreriaActiva);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_sesionTesoreriaActiva ? 'Sesión desbloqueada' : 'Sesión bloqueada'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: _cargandoDatos
          ? const Center(child: CircularProgressIndicator())
          : gFirebaseConectado
              ? StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('vendedores').orderBy('equipo').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text('Error al conectar con Firestore:\n${snapshot.error}', textAlign: TextAlign.center),
                        ),
                      );
                    }
                    final docs = (snapshot.data?.docs ?? []).map((d) {
                      final map = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
                      map['id'] = d.id;
                      return map;
                    }).toList();
                    return _construirCuerpoConLista(docs);
                  },
                )
              : _construirCuerpoConLista(_jugadoresLocales),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
        onPressed: () => _verificarPinYEjecutar(context, () => _mostrarDialogoNuevoJugador(context)),
        label: const Text('Nuevo Jugador'),
        icon: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _construirCuerpoConLista(List<Map<String, dynamic>> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sports_basketball, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No hay jugadores cargados.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                'Usa el icono superior para importar un archivo Excel por pestañas o pulsa "Nuevo Jugador" para dar de alta uno manual.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Estadísticas globales
    double totalRecaudado = 0.0;
    double totalAPagarGeneral = 0.0;
    int papeletasTotales = 0;
    for (var d in docs) {
      final double pagado = (d['pagado'] is num) ? (d['pagado'] as num).toDouble() : 0.0;
      final double total = (d['totalAPagar'] is num) ? (d['totalAPagar'] as num).toDouble() : 0.0;
      final int paps = (d['papeletas'] is num) ? (d['papeletas'] as num).toInt() : 0;
      totalRecaudado += pagado;
      totalAPagarGeneral += total;
      papeletasTotales += paps;
    }
    double totalPendiente = (totalAPagarGeneral - totalRecaudado).clamp(0.0, double.infinity);

    // Extraer lista única de equipos para pestañas/chips
    final equipos = {'Todos', ...docs.map((d) => d['equipo']?.toString() ?? 'Sin equipo')}.toList();

    // Filtrar por equipo
    final docsFiltrados = _filtroEquipo == 'Todos'
        ? docs
        : docs.where((d) => d['equipo'] == _filtroEquipo).toList();

    return Column(
      children: [
        // Barra informativa de Modo (Nube vs Local Autónomo)
        Container(
          width: double.infinity,
          color: gFirebaseConectado ? Colors.teal.shade50 : const Color(0xFFEBF3FA),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                gFirebaseConectado ? Icons.cloud_done : Icons.phone_android,
                size: 16,
                color: gFirebaseConectado ? Colors.teal.shade700 : const Color(0xFF1F4E79),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  gFirebaseConectado
                      ? 'Nube Firestore Conectada'
                      : 'Modo Local Autónomo (Datos guardados en este dispositivo)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: gFirebaseConectado ? Colors.teal.shade800 : const Color(0xFF1F4E79),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Barra de Resumen Financiero
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _itemEstadistica('Recaudado', '${totalRecaudado.toStringAsFixed(0)} €', Colors.green.shade700),
              _itemEstadistica('Pendiente', '${totalPendiente.toStringAsFixed(0)} €', Colors.orange.shade800),
              _itemEstadistica('Total Objetivo', '${totalAPagarGeneral.toStringAsFixed(0)} €', const Color(0xFF1F4E79)),
              _itemEstadistica('Papeletas', '$papeletasTotales', Colors.blueGrey.shade800),
            ],
          ),
        ),

        // Selector horizontal de categoría/equipo
        Container(
          height: 48,
          color: const Color(0xFFF1F5F9),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: equipos.length,
            itemBuilder: (context, i) {
              final eq = equipos[i];
              final isSelected = _filtroEquipo == eq;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(eq),
                  selectedColor: const Color(0x261F4E79),
                  labelStyle: TextStyle(
                    color: isSelected ? const Color(0xFF1F4E79) : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _filtroEquipo = eq),
                ),
              );
            },
          ),
        ),

        // Lista de tarjetas de jugadores con numeración correlativa
        Expanded(
          child: ListView.builder(
            itemCount: docsFiltrados.length,
            padding: const EdgeInsets.only(bottom: 80, top: 8),
            itemBuilder: (context, index) {
              var data = docsFiltrados[index];
              String id = data['id'] ?? index.toString();
              int numeroCorrelativo = index + 1;
              double pagado = (data['pagado'] is num) ? (data['pagado'] as num).toDouble() : 0.0;
              double totalAPagar = (data['totalAPagar'] is num) ? (data['totalAPagar'] as num).toDouble() : 0.0;
              bool estaPagado = pagado >= totalAPagar && totalAPagar > 0;
              double porcentaje = totalAPagar > 0 ? (pagado / totalAPagar).clamp(0.0, 1.0) : 0.0;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: estaPagado ? Colors.green.shade50 : Colors.orange.shade50,
                                  child: Text(
                                    '$numeroCorrelativo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: estaPagado ? Colors.green.shade700 : Colors.orange.shade800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['nombre'] ?? '',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        data['equipo'] ?? '',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.note_alt_outlined,
                                  color: (data['notas'] != null && data['notas'].toString().trim().isNotEmpty)
                                      ? Colors.amber.shade800
                                      : Colors.grey,
                                ),
                                tooltip: 'Notas de Tesorería',
                                onPressed: () => _mostrarDialogoNotas(
                                  context,
                                  id,
                                  data['nombre'] ?? '',
                                  data['notas']?.toString() ?? '',
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings_outlined, color: Colors.grey),
                                tooltip: 'Asignar Talonario',
                                onPressed: () => _verificarPinYEjecutar(
                                  context,
                                  () => _mostrarDialogoAsignacion(context, id, data['nombre'] ?? '', data),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                tooltip: 'Eliminar Jugador',
                                onPressed: () => _verificarPinYEjecutar(
                                  context,
                                  () => _confirmarEliminarJugador(context, id, data['nombre'] ?? ''),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (data['notas'] != null && data['notas'].toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _mostrarDialogoNotas(context, id, data['nombre'] ?? '', data['notas']?.toString() ?? ''),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.edit_note, size: 16, color: Colors.amber.shade900),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    data['notas'].toString(),
                                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontStyle: FontStyle.italic),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            (data['esPagoBeneficio'] ?? false)
                                ? 'Modalidad: Beneficio Directo (20 €)'
                                : 'Talonario: ${data['talonario'] ?? "Sin asignar"}',
                            style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700),
                          ),
                          Text(
                            '${pagado.toStringAsFixed(2)} € / ${totalAPagar.toStringAsFixed(2)} €',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: estaPagado ? Colors.green.shade800 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: porcentaje,
                          backgroundColor: Colors.grey.shade200,
                          color: estaPagado ? Colors.green.shade600 : Colors.orange.shade600,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: estaPagado ? Colors.green.shade800 : const Color(0xFF1F4E79),
                            side: BorderSide(color: estaPagado ? Colors.green : const Color(0xFF1F4E79)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: Icon(estaPagado ? Icons.check_circle : Icons.payment, size: 18),
                          label: Text(estaPagado ? 'Liquidado Totalmente (Cobrar más)' : 'Registrar Cobro'),
                          onPressed: () => _mostrarDialogoCobro(context, id, data['nombre'] ?? '', pagado, totalAPagar),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _itemEstadistica(String titulo, String valor, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(valor, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  void _mostrarDialogoNuevoJugador(BuildContext context) {
    final nombreController = TextEditingController();
    final equipoController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir Nuevo Jugador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre y Apellidos',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: equipoController,
              decoration: const InputDecoration(
                labelText: 'Categoría / Equipo (ej: Senior Masc)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (nombreController.text.trim().isNotEmpty && equipoController.text.trim().isNotEmpty) {
                final nuevo = {
                  'id': 'jugador_${DateTime.now().microsecondsSinceEpoch}',
                  'nombre': nombreController.text.trim(),
                  'equipo': equipoController.text.trim(),
                  'esPagoBeneficio': false,
                  'talonario': null,
                  'papeletas': 0,
                  'totalAPagar': 0.0,
                  'pagado': 0.0,
                  'notas': '',
                };
                if (gFirebaseConectado) {
                  await FirebaseFirestore.instance.collection('vendedores').add(nuevo);
                } else {
                  _jugadoresLocales.add(nuevo);
                  _guardarDatosLocales();
                  setState(() {});
                }
                Navigator.pop(ctx);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAsignacion(BuildContext context, String jugadorId, String nombreJugador, Map<String, dynamic> data) {
    bool esPagoBeneficio = data['esPagoBeneficio'] ?? false;
    final talonarioController = TextEditingController(text: data['talonario'] ?? '');
    final numPapeletasController = TextEditingController(text: (data['papeletas'] ?? 0).toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text('Asignar Lotería: $nombreJugador', style: const TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('¿Pago Beneficio Directo?'),
                  subtitle: const Text('Aporta los 20 € sin retirar papeletas'),
                  value: esPagoBeneficio,
                  onChanged: (val) => setStateModal(() => esPagoBeneficio = val),
                ),
                const SizedBox(height: 8),
                if (!esPagoBeneficio) ...[
                  TextField(
                    controller: talonarioController,
                    decoration: const InputDecoration(
                      labelText: 'Rango Talonario (ej: 001-050)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numPapeletasController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número de papeletas (5€ c/u)',
                      helperText: 'Beneficio mínimo obligatorio: 20 €',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF1F4E79)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Aportación directa obligatoria: 20,00 €',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F4E79),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                double totalAPagar = 20.0;
                int papeletas = 0;
                if (!esPagoBeneficio) {
                  papeletas = int.tryParse(numPapeletasController.text.trim()) ?? 0;
                  double valorPapeletas = papeletas * 5.0;
                  double beneficioCalculado = papeletas * 1.0;
                  if (beneficioCalculado < 20.0) {
                    totalAPagar = valorPapeletas + (20.0 - beneficioCalculado);
                  } else {
                    totalAPagar = valorPapeletas;
                  }
                }
                if (gFirebaseConectado) {
                  await FirebaseFirestore.instance.collection('vendedores').doc(jugadorId).update({
                    'esPagoBeneficio': esPagoBeneficio,
                    'talonario': esPagoBeneficio ? null : talonarioController.text.trim(),
                    'papeletas': papeletas,
                    'totalAPagar': totalAPagar,
                  });
                } else {
                  final idx = _jugadoresLocales.indexWhere((j) => j['id'] == jugadorId);
                  if (idx != -1) {
                    _jugadoresLocales[idx]['esPagoBeneficio'] = esPagoBeneficio;
                    _jugadoresLocales[idx]['talonario'] = esPagoBeneficio ? null : talonarioController.text.trim();
                    _jugadoresLocales[idx]['papeletas'] = papeletas;
                    _jugadoresLocales[idx]['totalAPagar'] = totalAPagar;
                    _guardarDatosLocales();
                    setState(() {});
                  }
                }
                Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoCobro(BuildContext context, String jugadorId, String nombreJugador, double pagadoActual, double totalAPagar) {
    final montoController = TextEditingController();
    double pendiente = (totalAPagar - pagadoActual).clamp(0.0, double.infinity);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Registrar Cobro: $nombreJugador', style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pendiente == 0 ? Colors.green.shade50 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Pendiente de pago:'),
                  Text(
                    '${pendiente.toStringAsFixed(2)} €',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: pendiente == 0 ? Colors.green.shade800 : Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Cantidad entregada (€)',
                hintText: 'Ej: 28.00 o 50.00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.euro),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final raw = montoController.text.replaceAll(',', '.').trim();
              double ingreso = double.tryParse(raw) ?? 0.0;
              if (ingreso > 0) {
                double nuevoPagado = pagadoActual + ingreso;
                if (nuevoPagado <= totalAPagar + 0.001) {
                  if (gFirebaseConectado) {
                    await FirebaseFirestore.instance.collection('vendedores').doc(jugadorId).update({
                      'pagado': nuevoPagado,
                    });
                  } else {
                    final idx = _jugadoresLocales.indexWhere((j) => j['id'] == jugadorId);
                    if (idx != -1) {
                      _jugadoresLocales[idx]['pagado'] = nuevoPagado;
                      _guardarDatosLocales();
                      setState(() {});
                    }
                  }
                  Navigator.pop(ctx);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('La cantidad supera la deuda total (${totalAPagar.toStringAsFixed(2)} €)'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Aceptar Cobro'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoNotas(BuildContext context, String jugadorId, String nombreJugador, String notasActuales) {
    final notasController = TextEditingController(text: notasActuales);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.note_alt, color: Color(0xFF1F4E79)),
            const SizedBox(width: 8),
            Expanded(child: Text('Notas: $nombreJugador', style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anotaciones internas de tesorería (ej: llamadas, pagos acordados, devoluciones):',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notasController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Escribe aquí observaciones...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (notasActuales.isNotEmpty)
            TextButton(
              onPressed: () async {
                if (gFirebaseConectado) {
                  await FirebaseFirestore.instance.collection('vendedores').doc(jugadorId).update({'notas': ''});
                } else {
                  final idx = _jugadoresLocales.indexWhere((j) => j['id'] == jugadorId);
                  if (idx != -1) {
                    _jugadoresLocales[idx]['notas'] = '';
                    _guardarDatosLocales();
                    setState(() {});
                  }
                }
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Borrar Nota', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (gFirebaseConectado) {
                await FirebaseFirestore.instance.collection('vendedores').doc(jugadorId).update({
                  'notas': notasController.text.trim(),
                });
              } else {
                final idx = _jugadoresLocales.indexWhere((j) => j['id'] == jugadorId);
                if (idx != -1) {
                  _jugadoresLocales[idx]['notas'] = notasController.text.trim();
                  _guardarDatosLocales();
                  setState(() {});
                }
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminarJugador(BuildContext context, String jugadorId, String nombreJugador) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Seguro que deseas eliminar a $nombreJugador de la lista?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              if (gFirebaseConectado) {
                await FirebaseFirestore.instance.collection('vendedores').doc(jugadorId).delete();
              } else {
                _jugadoresLocales.removeWhere((j) => j['id'] == jugadorId);
                _guardarDatosLocales();
                setState(() {});
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
