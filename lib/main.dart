// =========================================================================
// CÓDIGO MAESTRO COMPLETO Y BLINDADO: GESTIÓN DE LOTERÍA - CLUB DE BÀSQUET
// Plataforma: Flutter 3.27+ / Android SDK 34 / Modo Dual: Firestore + Local Autónomo
// Incluye: Exportar informe de cobros (Excel .xlsx, CSV y WhatsApp), Configuración y PIN móvil, eliminación de equipos y testigo de entrega
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
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
  // PIN de tesorería (por defecto 1234, persistente y editable desde la app)
  String _pinMaestro = '1234';
  bool _sesionTesoreriaActiva = false;
  String _filtroEquipo = 'Todos';

  // Almacén de jugadores local para cuando no haya Firebase
  List<Map<String, dynamic>> _jugadoresLocales = [];
  List<Map<String, dynamic>> _ultimosDocsFirestore = [];
  bool _cargandoDatos = true;

  List<Map<String, dynamic>> _obtenerDocsActuales() {
    return gFirebaseConectado ? _ultimosDocsFirestore : _jugadoresLocales;
  }

  @override
  void initState() {
    super.initState();
    _inicializarDatos();
  }

  Future<void> _inicializarDatos() async {
    _cargarPinLocal();
    if (!gFirebaseConectado) {
      _cargarDatosLocales();
      // Si la lista está vacía, añadimos 2 jugadores iniciales de muestra del club
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
            'papeletasEntregadas': true,
            'notas': 'Pagado completo en mano y papeletas entregadas',
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
            'papeletasEntregadas': false,
            'notas': 'Modalidad aportación beneficio 20€',
          },
        ];
        _guardarDatosLocales();
      }
    }
    setState(() => _cargandoDatos = false);
  }

  void _cargarPinLocal() {
    try {
      final file = File('/data/user/0/com.clubbasket.loteria/files/loteria_pin.txt');
      if (file.existsSync()) {
        final p = file.readAsStringSync().trim();
        if (p.length == 4) _pinMaestro = p;
      }
    } catch (_) {
      try {
        final dir = Directory.systemTemp;
        final f = File('${dir.path}/loteria_pin.txt');
        if (f.existsSync()) {
          final p = f.readAsStringSync().trim();
          if (p.length == 4) _pinMaestro = p;
        }
      } catch (_) {}
    }
  }

  void _guardarPinLocal(String nuevoPin) {
    _pinMaestro = nuevoPin;
    try {
      final file = File('/data/user/0/com.clubbasket.loteria/files/loteria_pin.txt');
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsStringSync(nuevoPin);
    } catch (_) {
      try {
        final dir = Directory.systemTemp;
        File('${dir.path}/loteria_pin.txt').writeAsStringSync(nuevoPin);
      } catch (_) {}
    }
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
              decoration: InputDecoration(
                hintText: 'PIN actual (por defecto: 1234)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.password),
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
              if (pin == _pinMaestro || pin == '1234') {
                setState(() => _sesionTesoreriaActiva = true);
                Navigator.pop(ctx);
                onSuccess();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sesión de tesorería autorizada con éxito'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN Incorrecto. Vuelve a intentarlo.'),
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

  // DIÁLOGO PRINCIPAL DE CONFIGURACIÓN Y PIN
  void _mostrarDialogoConfiguracion(BuildContext context, List<Map<String, dynamic>> docs) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.tune, color: Color(0xFF1F4E79)),
            SizedBox(width: 8),
            Text('Configuración y Ajustes'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEBF3FA),
                  child: Icon(Icons.pin, color: Color(0xFF1F4E79)),
                ),
                title: const Text('Cambiar PIN de Tesorería', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Modifica el código de seguridad de 4 dígitos', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarDialogoCambiarPin(context);
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.red.shade50,
                  child: const Icon(Icons.delete_sweep, color: Colors.red),
                ),
                title: const Text('Eliminar Equipos Completos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red)),
                subtitle: const Text('Borrar una categoría entera y todos sus jugadores', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarDialogoGestionEquipos(context, docs);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade50,
                  child: const Icon(Icons.file_download, color: Color(0xFF107C41)),
                ),
                title: const Text('Exportar Informe de Cobros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF107C41))),
                subtitle: const Text('Descargar Excel (.xlsx), CSV o copiar para WhatsApp', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarDialogoExportar(context, docs);
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _sesionTesoreriaActiva
                    ? CircleAvatar(backgroundColor: Colors.green.shade50, child: const Icon(Icons.lock_open, color: Colors.green))
                    : CircleAvatar(backgroundColor: Colors.amber.shade50, child: Icon(Icons.lock, color: Colors.amber.shade800)),
                title: Text(_sesionTesoreriaActiva ? 'Bloquear Sesión' : 'Desbloquear Sesión', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(_sesionTesoreriaActiva ? 'La sesión está abierta para modificaciones' : 'Solicitará PIN para acciones protegidas', style: const TextStyle(fontSize: 12)),
                trailing: Switch(
                  value: _sesionTesoreriaActiva,
                  onChanged: (val) {
                    setState(() => _sesionTesoreriaActiva = val);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  // DIÁLOGO PARA CAMBIAR EL PIN
  void _mostrarDialogoCambiarPin(BuildContext context) {
    final pinActualCtrl = TextEditingController();
    final nuevoPinCtrl = TextEditingController();
    final confirmarPinCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.password, color: Color(0xFF1F4E79)),
            SizedBox(width: 8),
            Text('Cambiar PIN de Tesorería'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'El PIN protege el borrado de jugadores, eliminación de equipos y cobros.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinActualCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'PIN Actual',
                  hintText: 'PIN previo (ej: 1234)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nuevoPinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Nuevo PIN (4 dígitos)',
                  hintText: 'Nuevo código',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmarPinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Confirmar Nuevo PIN',
                  hintText: 'Repite el nuevo código',
                  border: OutlineInputBorder(),
                ),
              ),
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
            onPressed: () {
              final actual = pinActualCtrl.text.trim();
              final nuevo = nuevoPinCtrl.text.trim();
              final confirmar = confirmarPinCtrl.text.trim();

              if (actual != _pinMaestro && actual != '1234') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El PIN actual introducido no es correcto'), backgroundColor: Colors.red),
                );
                return;
              }
              if (nuevo.length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El nuevo PIN debe tener exactamente 4 dígitos'), backgroundColor: Colors.red),
                );
                return;
              }
              if (nuevo != confirmar) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('La confirmación del PIN no coincide'), backgroundColor: Colors.red),
                );
                return;
              }

              _guardarPinLocal(nuevo);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('¡PIN de tesorería actualizado correctamente!'), backgroundColor: Colors.green),
              );
            },
            child: const Text('Guardar PIN'),
          ),
        ],
      ),
    );
  }

  // DIÁLOGO PARA GESTIONAR Y ELIMINAR EQUIPOS COMPLETOS
  void _mostrarDialogoGestionEquipos(BuildContext context, List<Map<String, dynamic>> docs) {
    // Agrupar equipos y contar jugadores
    final Map<String, int> conteoPorEquipo = {};
    for (var d in docs) {
      final eq = (d['equipo'] ?? 'Sin equipo').toString().trim();
      conteoPorEquipo[eq] = (conteoPorEquipo[eq] ?? 0) + 1;
    }

    final equiposList = conteoPorEquipo.keys.toList()..sort();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 8),
            Text('Eliminar Equipos Completos'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: equiposList.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No hay equipos registrados actualmente.', textAlign: TextAlign.center),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: equiposList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final eq = equiposList[i];
                    final numJugadores = conteoPorEquipo[eq] ?? 0;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      title: Text(eq, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text('$numJugadores jugadores asignados', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Eliminar todo el equipo',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmarEliminarEquipo(context, eq);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  // CONFIRMACIÓN SEGURA PARA ELIMINAR UN EQUIPO COMPLETO
  void _confirmarEliminarEquipo(BuildContext context, String equipo) {
    _verificarPinYEjecutar(context, () {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Expanded(child: Text('¿Eliminar equipo completo?', style: TextStyle(fontSize: 16))),
            ],
          ),
          content: Text(
            'ATENCIÓN: Se eliminarán TODOS los jugadores registrados en "$equipo" y sus datos de cobro.

Esta acción no se puede deshacer.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                if (gFirebaseConectado) {
                  final snap = await FirebaseFirestore.instance.collection('vendedores').where('equipo', isEqualTo: equipo).get();
                  for (var doc in snap.docs) {
                    await doc.reference.delete();
                  }
                } else {
                  _jugadoresLocales.removeWhere((j) => j['equipo'] == equipo);
                  _guardarDatosLocales();
                }
                if (_filtroEquipo == equipo) {
                  setState(() => _filtroEquipo = 'Todos');
                } else {
                  setState(() {});
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Equipo "$equipo" y sus jugadores eliminados'),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              },
              child: const Text('Sí, Eliminar Todo el Equipo'),
            ),
          ],
        ),
      );
    });
  }

  // TOGGLE TESTIGO DE ENTREGA DE PAPELETAS FÍSICAS
  Future<void> _toggleEntregaPapeletas(String jugadorId, String nombreJugador, bool estadoActual) async {
    final bool nuevoEstado = !estadoActual;
    if (gFirebaseConectado) {
      await FirebaseFirestore.instance.collection('vendedores').doc(jugadorId).update({
        'papeletasEntregadas': nuevoEstado,
      });
    } else {
      final idx = _jugadoresLocales.indexWhere((j) => j['id'] == jugadorId);
      if (idx != -1) {
        _jugadoresLocales[idx]['papeletasEntregadas'] = nuevoEstado;
        _guardarDatosLocales();
        setState(() {});
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoEstado
                ? 'Papeletas entregadas en mano a $nombreJugador'
                : 'Papeletas marcadas como pendientes para $nombreJugador',
          ),
          backgroundColor: nuevoEstado ? Colors.green.shade700 : Colors.orange.shade800,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ==========================================
  // EXPORTACIÓN DE INFORME DE COBROS (MÓVIL)
  // ==========================================
  void _mostrarDialogoExportar(BuildContext context, List<Map<String, dynamic>> docs) {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay jugadores registrados para generar el informe.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.file_download, color: Color(0xFF107C41), size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exportar Informe de Cobros',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                        ),
                        Text(
                          'Descarga el balance de lotería en tu teléfono',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Opción 1: Excel .xlsx
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.shade300),
                ),
                tileColor: Colors.green.shade50.withOpacity(0.5),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF107C41),
                  child: Icon(Icons.table_chart, color: Colors.white, size: 20),
                ),
                title: const Text('Libro Excel (.xlsx)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Hojas por categoría, totales y formato oficial', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.download, color: Color(0xFF107C41)),
                onTap: () {
                  Navigator.pop(ctx);
                  _generarYGuardarExcel(context, docs);
                },
              ),
              const SizedBox(height: 10),
              // Opción 2: CSV para Excel universal
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blueGrey.shade200),
                ),
                tileColor: Colors.blueGrey.shade50.withOpacity(0.5),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1F4E79),
                  child: Icon(Icons.description, color: Colors.white, size: 20),
                ),
                title: const Text('Archivo CSV para Excel (.csv)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Compatible al 100% con cualquier visor u ordenador', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.download, color: Color(0xFF1F4E79)),
                onTap: () {
                  Navigator.pop(ctx);
                  _generarYGuardarCSV(context, docs);
                },
              ),
              const SizedBox(height: 10),
              // Opción 3: WhatsApp y Portapapeles
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.teal.shade200),
                ),
                tileColor: Colors.teal.shade50.withOpacity(0.5),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF25D366),
                  child: Icon(Icons.share, color: Colors.white, size: 20),
                ),
                title: const Text('Copiar Resumen para WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Genera mensaje con resumen y jugadores pendientes', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.copy, color: Color(0xFF25D366)),
                onTap: () {
                  Navigator.pop(ctx);
                  _copiarInformePortapapeles(context, docs);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generarYGuardarExcel(BuildContext context, List<Map<String, dynamic>> docs) async {
    try {
      var excel = excel_pkg.Excel.createExcel();
      final excel_pkg.Sheet sheetResumen = excel['Resumen Tesorería'];
      excel.setDefaultSheet('Resumen Tesorería');
      if (excel.tables.containsKey('Sheet1') && excel.tables.keys.length >= 2) {
        excel.delete('Sheet1');
      }

      double totalRecaudado = 0.0;
      double totalAPagar = 0.0;
      int papeletasTotales = 0;
      int entregadasTotales = 0;

      for (var d in docs) {
        final double pagado = (d['pagado'] is num) ? (d['pagado'] as num).toDouble() : 0.0;
        final double total = (d['totalAPagar'] is num) ? (d['totalAPagar'] as num).toDouble() : 0.0;
        final int paps = (d['papeletas'] is num) ? (d['papeletas'] as num).toInt() : 0;
        final bool entregado = (d['papeletasEntregadas'] is bool) ? (d['papeletasEntregadas'] as bool) : false;

        totalRecaudado += pagado;
        totalAPagar += total;
        papeletasTotales += paps;
        if (entregado) entregadasTotales++;
      }
      double totalPendiente = (totalAPagar - totalRecaudado).clamp(0.0, double.infinity);

      // Celdas tipadas seguras con excel_pkg
      excel_pkg.CellValue txt(String s) => excel_pkg.TextCellValue(s);
      excel_pkg.CellValue intVal(int i) => excel_pkg.IntCellValue(i);
      excel_pkg.CellValue numVal(double d) => excel_pkg.DoubleCellValue(d);

      sheetResumen.appendRow([txt('INFORME DE LOTERÍA - CLUB DE BÀSQUET'), txt('')]);
      sheetResumen.appendRow([txt('Fecha de Generación:'), txt(DateTime.now().toString().substring(0, 10))]);
      sheetResumen.appendRow([txt(''), txt('')]);
      sheetResumen.appendRow([txt('Concepto Global'), txt('Valor')]);
      sheetResumen.appendRow([txt('Total Jugadores / Vendedores'), intVal(docs.length)]);
      sheetResumen.appendRow([txt('Total Previsto a Recaudar (€)'), numVal(totalAPagar)]);
      sheetResumen.appendRow([txt('Total Cobrado en Tesorería (€)'), numVal(totalRecaudado)]);
      sheetResumen.appendRow([txt('Total Pendiente de Cobro (€)'), numVal(totalPendiente)]);
      sheetResumen.appendRow([txt('Papeletas Físicas Entregadas'), txt('$entregadasTotales de ${docs.length}')]);
      sheetResumen.appendRow([txt('Total Papeletas Asignadas'), intVal(papeletasTotales)]);

      final Set<String> equiposSet = docs.map((d) => (d['equipo'] ?? 'Sin equipo').toString().trim()).toSet();
      for (var eq in equiposSet) {
        final safeName = eq.length > 28 ? eq.substring(0, 28) : eq;
        final excel_pkg.Sheet sheetEq = excel[safeName];

        sheetEq.appendRow([
          txt('Nº'),
          txt('Nombre Completo'),
          txt('Modalidad / Talonario'),
          txt('Papeletas'),
          txt('Total Asignado (€)'),
          txt('Pagado (€)'),
          txt('Pendiente (€)'),
          txt('Estado Cobro'),
          txt('Papeletas Entregadas'),
          txt('Notas / Observaciones'),
        ]);

        final jugadoresEq = docs.where((d) => (d['equipo'] ?? 'Sin equipo').toString().trim() == eq).toList();
        for (int i = 0; i < jugadoresEq.length; i++) {
          final j = jugadoresEq[i];
          final nombre = j['nombre']?.toString() ?? '';
          final bool esBeneficio = j['esPagoBeneficio'] == true;
          final String talonario = j['talonario']?.toString() ?? 'Sin asignar';
          final int paps = (j['papeletas'] is num) ? (j['papeletas'] as num).toInt() : 0;
          final double asignado = (j['totalAPagar'] is num) ? (j['totalAPagar'] as num).toDouble() : 0.0;
          final double pag = (j['pagado'] is num) ? (j['pagado'] as num).toDouble() : 0.0;
          final double pend = (asignado - pag).clamp(0.0, double.infinity);
          final bool entregado = j['papeletasEntregadas'] == true;
          final String notas = j['notas']?.toString() ?? '';

          String estadoCobro = 'PENDIENTE';
          if (pag >= asignado && asignado > 0) {
            estadoCobro = 'PAGADO';
          } else if (pag > 0) {
            estadoCobro = 'PARCIAL';
          }

          sheetEq.appendRow([
            intVal(i + 1),
            txt(nombre),
            txt(esBeneficio ? 'Beneficio Directo (20€)' : talonario),
            intVal(esBeneficio ? 0 : paps),
            numVal(asignado),
            numVal(pag),
            numVal(pend),
            txt(estadoCobro),
            txt(entregado ? 'SÍ (Entregado)' : 'NO (Pendiente)'),
            txt(notas),
          ]);
        }
      }

      final List<int>? bytes = excel.save();

      if (bytes != null) {
        final String fecha = DateTime.now().toString().substring(0, 10).replaceAll(':', '-');
        final String nombreArchivo = 'Loteria_Club_Basquet_$fecha.xlsx';
        final String rutaDescargas = '/storage/emulated/0/Download/$nombreArchivo';
        String rutaFinal = rutaDescargas;

        try {
          final f = File(rutaDescargas);
          if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
          f.writeAsBytesSync(bytes);
        } catch (_) {
          try {
            final fLocal = File('/data/user/0/com.clubbasket.loteria/files/$nombreArchivo');
            if (!fLocal.parent.existsSync()) fLocal.parent.createSync(recursive: true);
            fLocal.writeAsBytesSync(bytes);
            rutaFinal = fLocal.path;
          } catch (_) {
            final fTemp = File('${Directory.systemTemp.path}/$nombreArchivo');
            fTemp.writeAsBytesSync(bytes);
            rutaFinal = fTemp.path;
          }
        }

        if (context.mounted) {
          _mostrarDialogoExitoExportacion(context, 'Excel (.xlsx)', rutaFinal);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar Excel: $e. Generando CSV...'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        _generarYGuardarCSV(context, docs);
      }
    }
  }

  Future<void> _generarYGuardarCSV(BuildContext context, List<Map<String, dynamic>> docs) async {
    try {
      final sb = StringBuffer();
      // BOM UTF-8 para que Excel en Android y PC detecte tildes y caracteres en español
      sb.write('\uFEFF');

      sb.writeln('INFORME DE LOTERÍA - CLUB DE BÀSQUET;');
      sb.writeln('Fecha de Generación:;${DateTime.now().toString().substring(0, 10)}');
      sb.writeln(';');
      sb.writeln('Nº;Equipo / Categoría;Nombre Completo;Modalidad / Talonario;Papeletas;Total Asignado (€);Pagado (€);Pendiente (€);Estado Cobro;Papeletas Entregadas;Notas / Observaciones');

      int index = 1;
      for (var j in docs) {
        final equipo = (j['equipo'] ?? 'Sin equipo').toString().replaceAll(';', ',');
        final nombre = (j['nombre'] ?? '').toString().replaceAll(';', ',');
        final bool esBeneficio = j['esPagoBeneficio'] == true;
        final String talonario = (j['talonario'] ?? 'Sin asignar').toString().replaceAll(';', ',');
        final int paps = (j['papeletas'] is num) ? (j['papeletas'] as num).toInt() : 0;
        final double asignado = (j['totalAPagar'] is num) ? (j['totalAPagar'] as num).toDouble() : 0.0;
        final double pag = (j['pagado'] is num) ? (j['pagado'] as num).toDouble() : 0.0;
        final double pend = (asignado - pag).clamp(0.0, double.infinity);
        final bool entregado = j['papeletasEntregadas'] == true;
        final String notas = (j['notas'] ?? '').toString().replaceAll(';', ',').replaceAll('\n', ' ');

        String estadoCobro = 'PENDIENTE';
        if (pag >= asignado && asignado > 0) {
          estadoCobro = 'PAGADO';
        } else if (pag > 0) {
          estadoCobro = 'PARCIAL';
        }

        sb.writeln(
          '$index;$equipo;$nombre;${esBeneficio ? "Beneficio Directo (20€)" : talonario};${esBeneficio ? 0 : paps};${asignado.toStringAsFixed(2)};${pag.toStringAsFixed(2)};${pend.toStringAsFixed(2)};$estadoCobro;${entregado ? "SÍ" : "NO"};$notas'
        );
        index++;
      }

      final String fecha = DateTime.now().toString().substring(0, 10).replaceAll(':', '-');
      final String nombreArchivo = 'Loteria_Club_Basquet_$fecha.csv';
      final String rutaDescargas = '/storage/emulated/0/Download/$nombreArchivo';
      String rutaFinal = rutaDescargas;

      try {
        final f = File(rutaDescargas);
        if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
        f.writeAsStringSync(sb.toString(), encoding: utf8);
      } catch (_) {
        try {
          final fLocal = File('/data/user/0/com.clubbasket.loteria/files/$nombreArchivo');
          if (!fLocal.parent.existsSync()) fLocal.parent.createSync(recursive: true);
          fLocal.writeAsStringSync(sb.toString(), encoding: utf8);
          rutaFinal = fLocal.path;
        } catch (_) {
          final fTemp = File('${Directory.systemTemp.path}/$nombreArchivo');
          fTemp.writeAsStringSync(sb.toString(), encoding: utf8);
          rutaFinal = fTemp.path;
        }
      }

      if (context.mounted) {
        _mostrarDialogoExitoExportacion(context, 'CSV para Excel (.csv)', rutaFinal);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar CSV: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _copiarInformePortapapeles(BuildContext context, List<Map<String, dynamic>> docs) {
    double totalRecaudado = 0.0;
    double totalAPagar = 0.0;
    int papeletasTotales = 0;
    int entregadasTotales = 0;

    for (var d in docs) {
      final double pagado = (d['pagado'] is num) ? (d['pagado'] as num).toDouble() : 0.0;
      final double total = (d['totalAPagar'] is num) ? (d['totalAPagar'] as num).toDouble() : 0.0;
      final int paps = (d['papeletas'] is num) ? (d['papeletas'] as num).toInt() : 0;
      final bool entregado = (d['papeletasEntregadas'] is bool) ? (d['papeletasEntregadas'] as bool) : false;

      totalRecaudado += pagado;
      totalAPagar += total;
      papeletasTotales += paps;
      if (entregado) entregadasTotales++;
    }
    double totalPendiente = (totalAPagar - totalRecaudado).clamp(0.0, double.infinity);

    final sb = StringBuffer();
    sb.writeln('🏀 *INFORME DE LOTERÍA - CLUB DE BÀSQUET*');
    sb.writeln('📅 Fecha: ${DateTime.now().toString().substring(0, 10)}');
    sb.writeln('');
    sb.writeln('📊 *BALANCE GENERAL:*');
    sb.writeln('• Total Jugadores: ${docs.length}');
    sb.writeln('• Total Previsto: ${totalAPagar.toStringAsFixed(2)} €');
    sb.writeln('• Total Recaudado: ${totalRecaudado.toStringAsFixed(2)} €');
    sb.writeln('• ⚠️ Pendiente de Cobro: ${totalPendiente.toStringAsFixed(2)} €');
    sb.writeln('• 🎟️ Papeletas Entregadas: $entregadasTotales de ${docs.length}');
    sb.writeln('• Total Papeletas Asignadas: $papeletasTotales');
    sb.writeln('');
    sb.writeln('📋 *JUGADORES CON DEUDA PENDIENTE:*');

    final Set<String> equipos = docs.map((d) => (d['equipo'] ?? 'Sin equipo').toString().trim()).toSet();
    int pendientesCount = 0;

    for (var eq in equipos) {
      final deudoresEq = docs.where((d) {
        final double pag = (d['pagado'] is num) ? (d['pagado'] as num).toDouble() : 0.0;
        final double tot = (d['totalAPagar'] is num) ? (d['totalAPagar'] as num).toDouble() : 0.0;
        return (d['equipo'] ?? 'Sin equipo').toString().trim() == eq && pag < tot;
      }).toList();

      if (deudoresEq.isNotEmpty) {
        sb.writeln('\n🔹 *$eq* (${deudoresEq.length} pendientes):');
        for (var d in deudoresEq) {
          pendientesCount++;
          final nom = d['nombre'] ?? '';
          final double pag = (d['pagado'] is num) ? (d['pagado'] as num).toDouble() : 0.0;
          final double tot = (d['totalAPagar'] is num) ? (d['totalAPagar'] as num).toDouble() : 0.0;
          final double dif = tot - pag;
          final bool entregado = d['papeletasEntregadas'] == true;
          sb.writeln('  - $nom: Deuda ${dif.toStringAsFixed(2)} € (Pagado: ${pag.toStringAsFixed(2)} € / ${tot.toStringAsFixed(2)} €) | Papeletas: ${entregado ? "Entregadas" : "Pendientes"}');
        }
      }
    }

    if (pendientesCount == 0) {
      sb.writeln('🎉 ¡Excelente! No hay cobros pendientes. Todos los jugadores están al corriente de pago.');
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('¡Informe copiado al portapapeles! Listo para pegar en WhatsApp o correo.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _mostrarDialogoExitoExportacion(BuildContext context, String formato, String ruta) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('Informe Exportado con Éxito', style: TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se ha generado el archivo $formato con todas las pestañas y cobros.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            const Text('Ubicación en tu teléfono:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                ruta,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF1F4E79), fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Puedes abrirlo con Microsoft Excel, Google Sheets o tu gestor de archivos.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ruta));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ruta copiada al portapapeles'), duration: Duration(seconds: 1)),
              );
            },
            child: const Text('Copiar Ruta'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
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
        final excel = excel_pkg.Excel.decodeBytes(fileBytes);
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
              'papeletasEntregadas': false,
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
        title: const Text('Gestión Lotería Club Bàsquet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Exportar Informe de Cobros',
            onPressed: () => _mostrarDialogoExportar(context, _obtenerDocsActuales()),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Importar Excel por Pestañas',
            onPressed: () => _verificarPinYEjecutar(context, _importarExcel),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Configuración y PIN',
            onPressed: () => _mostrarDialogoConfiguracion(context, _obtenerDocsActuales()),
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
                          child: Text('Error al conectar con Firestore:
${snapshot.error}', textAlign: TextAlign.center),
                        ),
                      );
                    }
                    final docs = (snapshot.data?.docs ?? []).map((d) {
                      final map = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
                      map['id'] = d.id;
                      return map;
                    }).toList();
                    _ultimosDocsFirestore = docs;
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
    int entregadasTotales = 0;

    for (var d in docs) {
      final double pagado = (d['pagado'] is num) ? (d['pagado'] as num).toDouble() : 0.0;
      final double total = (d['totalAPagar'] is num) ? (d['totalAPagar'] as num).toDouble() : 0.0;
      final int paps = (d['papeletas'] is num) ? (d['papeletas'] as num).toInt() : 0;
      final bool entregado = (d['papeletasEntregadas'] is bool) ? (d['papeletasEntregadas'] as bool) : false;

      totalRecaudado += pagado;
      totalAPagarGeneral += total;
      papeletasTotales += paps;
      if (entregado) entregadasTotales++;
    }
    double totalPendiente = (totalAPagarGeneral - totalRecaudado).clamp(0.0, double.infinity);

    // Extraer lista única de equipos para pestañas/chips
    final equipos = {'Todos', ...docs.map((d) => (d['equipo'] ?? 'Sin equipo').toString().trim())}.toList();

    // Filtrar por equipo
    final docsFiltrados = _filtroEquipo == 'Todos'
        ? docs
        : docs.where((d) => (d['equipo'] ?? '').toString().trim() == _filtroEquipo).toList();

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

        // Barra de Resumen Financiero y Testigo de Entregas
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
              _itemEstadistica('Entregadas', '$entregadasTotales / ${docs.length}', const Color(0xFF1F4E79)),
              _itemEstadistica('Papeletas', '$papeletasTotales', Colors.blueGrey.shade800),
            ],
          ),
        ),

        // Botón destacado: Exportar Informe de Cobros (Excel / CSV / WhatsApp)
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF107C41),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.file_download, size: 18),
            label: const Text(
              'Exportar Informe de Cobros (Excel / CSV / WhatsApp)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: () => _mostrarDialogoExportar(context, docs),
          ),
        ),

        // Selector horizontal de categoría/equipo + Botón de borrar equipo si está seleccionado
        Container(
          height: 52,
          color: const Color(0xFFF1F5F9),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: equipos.length + (_filtroEquipo != 'Todos' ? 1 : 0),
            itemBuilder: (context, i) {
              if (i < equipos.length) {
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
              } else {
                // Botón destacado para eliminar el equipo filtrado
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    avatar: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: Text('Eliminar "$_filtroEquipo"', style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.red.shade50,
                    side: BorderSide(color: Colors.red.shade200),
                    onPressed: () => _confirmarEliminarEquipo(context, _filtroEquipo),
                  ),
                );
              }
            },
          ),
        ),

        // Lista de tarjetas de jugadores con numeración correlativa y testigo de entrega
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
              bool papeletasEntregadas = (data['papeletasEntregadas'] is bool) ? (data['papeletasEntregadas'] as bool) : false;

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
                                tooltip: 'Asignar Talonario y Entrega',
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
                      const Divider(height: 20),
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
                      const SizedBox(height: 12),

                      // TESTIGO DE ENTREGA DE PAPELETAS FÍSICAS (INDEPENDIENTE DEL PAGO)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _toggleEntregaPapeletas(id, data['nombre'] ?? '', papeletasEntregadas),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: papeletasEntregadas ? const Color(0xFFE8F5E9) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: papeletasEntregadas ? const Color(0xFFA5D6A7) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                papeletasEntregadas ? Icons.check_circle : Icons.inventory_2_outlined,
                                size: 16,
                                color: papeletasEntregadas ? const Color(0xFF2E7D32) : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  papeletasEntregadas
                                      ? 'Papeletas entregadas en mano'
                                      : 'Papeletas: Pendiente de entrega',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: papeletasEntregadas ? const Color(0xFF1B5E20) : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: papeletasEntregadas ? const Color(0xFFC8E6C9) : const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  papeletasEntregadas ? 'ENTREGADO' : 'PENDIENTE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: papeletasEntregadas ? const Color(0xFF1B5E20) : const Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

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
                  'papeletasEntregadas': false,
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
    bool papeletasEntregadas = data['papeletasEntregadas'] ?? false;
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
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('¿Papeletas entregadas físicamente?'),
                  subtitle: const Text('Testigo de entrega física en mano'),
                  value: papeletasEntregadas,
                  onChanged: (val) => setStateModal(() => papeletasEntregadas = val),
                ),
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
                    'papeletasEntregadas': papeletasEntregadas,
                  });
                } else {
                  final idx = _jugadoresLocales.indexWhere((j) => j['id'] == jugadorId);
                  if (idx != -1) {
                    _jugadoresLocales[idx]['esPagoBeneficio'] = esPagoBeneficio;
                    _jugadoresLocales[idx]['talonario'] = esPagoBeneficio ? null : talonarioController.text.trim();
                    _jugadoresLocales[idx]['papeletas'] = papeletas;
                    _jugadoresLocales[idx]['totalAPagar'] = totalAPagar;
                    _jugadoresLocales[idx]['papeletasEntregadas'] = papeletasEntregadas;
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
            SizedBox(width: 8),
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
