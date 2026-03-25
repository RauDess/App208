import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/usuario.dart';
import '../utils/constants.dart';
import 'package:app208/utils/notificaciones.dart';

class ConsumoScreen extends StatefulWidget {
  final Usuario usuario;

  const ConsumoScreen({super.key, required this.usuario});

  @override
  State<ConsumoScreen> createState() => _ConsumoScreenState();
}

class _ConsumoScreenState extends State<ConsumoScreen> {
  Timer? _timer;

  // Patrones de consum automaticos
  String _patronDetectado = '';
  String _anomaliaDetectada = '';

  // Datos de consumo
  int _wattsActual = 0;
  int _gruposEncendidos = 0;
  int _tubosEncendidos = 0;
  double _kwhEstimadoHora = 0.0;

  // Datos de hoy
  int _usosHoy = 0;
  double _horasTotales = 0.0;
  double _kwhHoy = 0.0;
  double _costoHoy = 0.0;

  // Datos de semana
  double _kwhSemana = 0.0;
  double _costoSemana = 0.0;

  // Comparación
  String _mensajeAhorro = '';
  bool _esAhorro = false;

  // Gráfica
  List<FlSpot> _datosGrafica = [];
  List<Map<String, dynamic>> _clasificacionDias = [];
  Map<String, dynamic> _clusteringData = {};
  bool _isLoadingMineria = false;
  bool _isLoading = true;
  List<dynamic> _reportes = [];

  @override
  void initState() {
    super.initState();
    _cargarTodosLosDatos();
    _cargarReportesInicial();

      // Timer cada 10 segundos
      _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _cargarTodosLosDatos();
        _verificarAdvertencias();
      });
    }

    @override
    void dispose() {
      _timer?.cancel();
      super.dispose();
    }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String> _obtenerPeriodoActual() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/jornadas/periodo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['periodo'] ?? '2026-1';
      }
      return '2026-1';
    } catch (e) {
      return '2026-1';
    }
  }

  Future<void> _cargarTodosLosDatos() async {
    await Future.wait([
      _cargarConsumoActual(),
      _cargarConsumoHoy(),
      _cargarConsumoSemana(),
      _cargarComparacion(),
      _cargarHistorico(),
      _cargarClasificacion(),
      _cargarClustering(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _cargarReportesInicial() async {
    try {
      final reportes = await _obtenerReportes();
      if (mounted) {
        setState(() {
          _reportes = reportes;
        });
      }
    } catch (e) {
      print('Error cargando reportes: $e');
    }
  }

  Future<void> _cargarConsumoActual() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/consumo/actual'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _wattsActual = data['watts'];
          _gruposEncendidos = data['grupos_encendidos'];
          _tubosEncendidos = data['tubos_encendidos'];
          _kwhEstimadoHora = data['kwh_estimado_hora'];
        });
      }
    } catch (e) {
      print('Error cargando consumo actual: $e');
    }
  }

  Future<void> _cargarConsumoHoy() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/consumo/hoy'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _usosHoy = data['usos_hoy'];
          _horasTotales = data['horas_totales'];
          _kwhHoy = data['kwh_total'];
          _costoHoy = data['costo_usd'];
        });
      }
    } catch (e) {
      print('Error cargando consumo de hoy: $e');
    }
  }

  Future<void> _cargarConsumoSemana() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/consumo/semana'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _kwhSemana = data['kwh_total'];
          _costoSemana = data['costo_usd'];
        });
      }
    } catch (e) {
      print('Error cargando consumo semanal: $e');
    }
  }

  Future<void> _cargarComparacion() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/consumo/comparacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _mensajeAhorro = data['mensaje'];
          _esAhorro = data['es_ahorro'];
        });
      }
    } catch (e) {
      print('Error cargando comparación: $e');
    }
  }

  Future<void> _cargarHistorico() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/consumo/historico'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> datos = data['datos'];

        setState(() {
          _datosGrafica = datos.map((punto) {
            return FlSpot(
              punto['hora'].toDouble(),
              punto['kwh'] * 1000, // Convertir a Watts para visualización
            );
          }).toList();

          // Si no hay datos, mostrar gráfica vacía
          if (_datosGrafica.isEmpty) {
            _datosGrafica = [const FlSpot(0, 0)];
          }
        });
      }
    } catch (e) {
      print('Error cargando histórico: $e');
    }
  }

  // FUNCIÓN: MOSTRAR BOTTOM SHEET DE REPORTES
  void _mostrarReportes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(25),
              topRight: Radius.circular(25),
            ),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(AppConstants.primaryColor),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(25),
                    topRight: Radius.circular(25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.assessment, color: Colors.white, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Reportes Semanales',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Botón: Generar Nuevo Reporte
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => _generarNuevoReporte(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 24),
                    label: const Text(
                      'Generar Nuevo Reporte',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(),

              // Lista de reportes
              Expanded(
                child: _reportes.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox,
                        size: 80,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay reportes generados',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Genera tu primer reporte',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _reportes.length,
                  itemBuilder: (context, index) {
                    final reporte = _reportes[index];
                    return _buildReporteCard(reporte);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // FUNCIÓN: OBTENER LISTA DE REPORTES
  Future<List<dynamic>> _obtenerReportes() async {
    try {
      final token = await _getToken();
      // Obtener período actual
      final periodoActual = await _obtenerPeriodoActual();
      // Obtener reportes del período actual
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/reportes?periodo=$periodoActual'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['reportes'];
      }
      return [];
    } catch (e) {
      print('Error obteniendo reportes: $e');
      return [];
    }
  }

  // FUNCIÓN: GENERAR NUEVO REPORTE
  Future<void> _generarNuevoReporte(BuildContext contextSheet) async {
    try {
      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
      );

      final token = await _getToken();
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/reportes/generar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      // Cerrar indicador de carga
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // RECARGAR LISTA ANTES DE CERRAR
        final reportesActualizados = await _obtenerReportes();
        if (mounted) {
          setState(() {
            _reportes = reportesActualizados;
          });
          Notificaciones.mostrarExito(context, data['message']);

          // Cerrar el bottom sheet y volver a abrirlo para refrescar
          Navigator.pop(contextSheet);
          _mostrarReportes();
        }
      } else if (response.statusCode == 409) {
        // Ya existe un reporte
        final data = jsonDecode(response.body);
        if (mounted) {
          Notificaciones.mostrarAdvertencia(context, data['message']);
        }
      } else {
        if (mounted) {
          Notificaciones.mostrarError(context, 'Error al generar reporte');
        }
      }
    } catch (e) {
      // Cerrar indicador de carga si hay error
      Navigator.pop(context);

      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  // WIDGET: CARD DE REPORTE
  Widget _buildReporteCard(Map<String, dynamic> reporte) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título y fecha CON BOTÓN ELIMINAR
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(AppConstants.primaryColor).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.description,
                      color: Color(AppConstants.primaryColor),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reporte['descripcion'] ?? 'Reporte semanal',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Generado: ${reporte['fecha_generacion']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ← BOTÓN ELIMINAR AGREGADO AQUÍ ↓
                  if (widget.usuario.rol == 'coordinador')
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Eliminar reporte',
                      onPressed: () => _confirmarEliminarReporte(reporte),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Datos del reporte
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildReporteInfo(
                      icono: Icons.flash_on,
                      valor: '${double.tryParse(reporte['total_consumo_kWh'].toString())?.toStringAsFixed(1) ?? '0.0'} kWh',
                      etiqueta: 'Consumo',
                    ),
                    Container(width: 1, height: 40, color: Colors.grey[300]),
                    _buildReporteInfo(
                      icono: Icons.access_time,
                      valor: '${double.tryParse(reporte['total_horas_uso'].toString())?.toStringAsFixed(1) ?? '0.0'} h',
                      etiqueta: 'Horas',
                    ),
                    Container(width: 1, height: 40, color: Colors.grey[300]),
                    _buildReporteInfo(
                      icono: Icons.trending_up,
                      valor: '${double.tryParse(reporte['promedio_diario_kWh'].toString())?.toStringAsFixed(1) ?? '0.0'} kWh',
                      etiqueta: 'Promedio',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Botón de descarga
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _descargarPDF(reporte['id_reporte']),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(AppConstants.primaryColor),
                    side: const BorderSide(
                      color: Color(AppConstants.primaryColor),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.download, size: 20),
                  label: const Text(
                    'Descargar PDF',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // FUNCIÓN: CONFIRMAR ELIMINACIÓN DE REPORTE
  Future<void> _confirmarEliminarReporte(Map<String, dynamic> reporte) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            const Text('Confirmar eliminación'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Está seguro de eliminar este reporte?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Reporte: ${reporte['descripcion'] ?? 'Reporte semanal'}',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            Text(
              'Generado: ${reporte['fecha_generacion']}',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta acción no se puede deshacer',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _eliminarReporte(reporte['id_reporte']);
    }
  }

// FUNCIÓN: ELIMINAR REPORTE
  Future<void> _eliminarReporte(int idReporte) async {
    try {
      final token = await _getToken();

      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/reportes/eliminar/$idReporte'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          // Recargar lista de reportes
          final reportesActualizados = await _obtenerReportes();
          setState(() {
            _reportes = reportesActualizados;  // ← ACTUALIZAR LISTA
          });
          Notificaciones.mostrarExito(context, 'Reporte eliminado correctamente');
          Navigator.pop(context);  // Cierra el BottomSheet actual
          _mostrarReportes();      // Reabre con lista actualizada
        }
      } else {
        final error = jsonDecode(response.body)['message'];
        if (mounted) {
          Notificaciones.mostrarError(context, 'Error: $error');
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error al eliminar: $e');
      }
    }
  }

  Widget _buildReporteInfo({
    required IconData icono,
    required String valor,
    required String etiqueta,
  }) {
    return Column(
      children: [
        Icon(icono, size: 20, color: const Color(AppConstants.primaryColor)),
        const SizedBox(height: 4),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(AppConstants.primaryColor),
          ),
        ),
        Text(etiqueta, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  // FUNCIÓN: DESCARGAR PDF
  Future<void> _descargarPDF(int idReporte) async {
    try {
      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
      );

      final token = await _getToken();
      final url = '${AppConstants.baseUrl}/reportes/$idReporte/pdf';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      // Cerrar indicador de carga
      Navigator.pop(context);

      if (response.statusCode == 200) {
        // Guardar el PDF
        await _guardarPDF(response.bodyBytes, idReporte);
      } else {
        if (mounted) {
          Notificaciones.mostrarError(context, 'Error al descargar PDF');
        }
      }
    } catch (e) {
      // Cerrar indicador de carga si hay error
      Navigator.pop(context);

      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  // FUNCIÓN: GUARDAR PDF EN EL DISPOSITIVO
  Future<void> _guardarPDF(List<int> bytes, int idReporte) async {
    try {
      if (Platform.isAndroid) {
        // Android - Usar selector de archivos del sistema
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filename = 'Reporte_Consumo_$idReporte\_$timestamp.pdf';

        final params = SaveFileDialogParams(
          data: Uint8List.fromList(bytes),
          fileName: filename,
          mimeTypesFilter: ['application/pdf'],
        );

        final filePath = await FlutterFileDialog.saveFile(params: params);

        if (filePath != null && mounted) {
          Notificaciones.mostrarExito(context, 'PDF guardado correctamente');
        }
      } else {
        // iOS
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filename = 'Reporte_Consumo_$idReporte\_$timestamp.pdf';
        final filePath = '${directory.path}/$filename';

        final file = File(filePath);
        await file.writeAsBytes(bytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF guardado: $filename'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'Abrir',
                textColor: Colors.white,
                onPressed: () => OpenFile.open(filePath),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error al guardar: $e');
      }
    }
  }

  // FUNCIÓN: CARGAR CLASIFICACIÓN - CLUSTERING (MINERÍA)
  Future<void> _cargarClasificacion() async {
    setState(() => _isLoadingMineria = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/mineria/clasificacion'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _clasificacionDias = List<Map<String, dynamic>>.from(data['resultados']);
          _patronDetectado = data['patron'] ?? '';
          _anomaliaDetectada = data['anomalia'] ?? '';
        });
      }
    } catch (e) {
      print('Error cargando clasificación: $e');
    } finally {
      setState(() => _isLoadingMineria = false);
    }
  }

  Future<void> _cargarClustering() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/mineria/clustering'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _clusteringData = data;
        });
      }
    } catch (e) {
      print('Error cargando clustering: $e');
    }
  }

  Future<void> _verificarAdvertencias() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/luces/advertencias'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['advertencia'] == true && mounted) {
          Notificaciones.mostrarAdvertencia(context, 'mensaje');
        }
      }
    } catch (e) {
      // Silencioso
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consumo Energético'),
        backgroundColor: const Color(AppConstants.primaryColor),
        foregroundColor: Colors.white,
        actions: [
          // Botón: Refrescar
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarTodosLosDatos,
            tooltip: 'Actualizar',
          ),

          // Botón: Reportes (solo coordinador)
          if (widget.usuario.rol == 'coordinador')
            IconButton(
              icon: const Icon(Icons.assessment),
              onPressed: _mostrarReportes,
              tooltip: 'Ver reportes',
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(AppConstants.primaryColor),
              Color(AppConstants.secondaryColor),
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Consumo actual
                      _buildConsumoCard(
                        titulo: 'Consumo Actual',
                        valor: '$_wattsActual W',
                        subtitulo: '$_tubosEncendidos tubos encendidos',
                        icono: Icons.bolt,
                        colorInicio: Colors.pink[400]!,
                        colorFin: Colors.yellow[300]!,
                      ),

                      const SizedBox(height: 16),

                      // Consumo diario
                      _buildConsumoCard(
                        titulo: 'Consumo Hoy',
                        valor: '${_kwhHoy.toStringAsFixed(2)} kWh',
                        subtitulo: '\$${_costoHoy.toStringAsFixed(2)} USD',
                        icono: Icons.today,
                        colorInicio: Colors.cyan[400]!,
                        colorFin: Colors.purple[900]!,
                      ),

                      const SizedBox(height: 30),

                      // Grid de estadísticas
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              valor: '${_horasTotales.toStringAsFixed(1)} h',
                              etiqueta: 'Tiempo encendido',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              valor: '$_usosHoy',
                              etiqueta: 'Usos hoy',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              valor: '${_kwhSemana.toStringAsFixed(1)} kWh',
                              etiqueta: 'Esta semana',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              valor: '\$${_costoSemana.toStringAsFixed(2)}',
                              etiqueta: 'Costo semanal',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),

                      // Sección: Análisis Inteligente
                      const Text(
                        'Análisis Inteligente',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Card: Clasificación de Días
                      _buildClasificacionCard(),
                      const SizedBox(height: 16),

                      // Card: Clustering de Semanas
                      _buildClusteringCard(),
                      const SizedBox(height: 20),

                      // Mensaje de ahorro
                      if (_mensajeAhorro.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _esAhorro
                                ? Colors.green[100]
                                : Colors.orange[100],
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _esAhorro
                                  ? Colors.green[300]!
                                  : Colors.orange[300]!,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _esAhorro ? Icons.check_circle : Icons.warning,
                                color: _esAhorro
                                    ? Colors.green[700]
                                    : Colors.orange[700],
                                size: 30,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _mensajeAhorro,
                                  style: TextStyle(
                                    color: _esAhorro
                                        ? Colors.green[900]
                                        : Colors.orange[900],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildConsumoCard({
    required String titulo,
    required String valor,
    required String subtitulo,
    required IconData icono,
    required Color colorInicio,
    required Color colorFin,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorInicio, colorFin],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icono, color: Colors.white, size: 30),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({required String valor, required String etiqueta}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            valor,
            style: const TextStyle(
              color: Color(AppConstants.primaryColor),
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            etiqueta,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // WIDGETS DE MINERÍA
  Widget _buildClasificacionCard() {
    // Crear lista completa de 7 días (Lun-Dom)
    final diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final hoy = DateTime.now();
    final inicioSemana = hoy.subtract(Duration(days: hoy.weekday - 1)); // Lunes

    // Crear mapa de días con datos
    final Map<int, Map<String, dynamic>> diasConDatos = {};
    for (var dia in _clasificacionDias) {
      final fecha = DateTime.parse(dia['fecha']);
      final diaSemana = fecha.weekday; // 1=Lun, 7=Dom
      diasConDatos[diaSemana] = dia;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(AppConstants.primaryColor).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bar_chart,
                  color: Color(AppConstants.primaryColor),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clasificación de Días',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(AppConstants.primaryColor),
                      ),
                    ),
                    Text(
                      'Esta semana (Lun-Dom)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Gráfico de barras (SIEMPRE 7 días)
          SizedBox(
            height: 200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final diaSemana = index + 1; // 1=Lun, 7=Dom
                final fechaDia = inicioSemana.add(Duration(days: index));
                final esHoyOAntes = fechaDia.isBefore(hoy.add(Duration(days: 1)));

                // Verificar si hay datos para este día
                final dia = diasConDatos[diaSemana];

                if (dia == null || !esHoyOAntes) {
                  // Día sin datos o futuro - mostrar barra vacía
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: 25,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        diasSemana[index],
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  );
                }

                // Día con datos
                final consumo = dia['consumo_kWh'] ?? 0.0;
                final maxConsumo = 30.0;
                final altura = (consumo / maxConsumo * 150).clamp(20.0, 150.0);

                Color color;
                if (dia['clasificacion'] == 'Alto') {
                  color = Colors.red;
                } else if (dia['clasificacion'] == 'Medio') {
                  color = Colors.orange;
                } else {
                  color = Colors.green;
                }

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Valor
                    Text(
                      '${consumo.toStringAsFixed(1)} kWh',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Barra
                    Container(
                      width: 25,
                      height: altura,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Día
                    Text(
                      diasSemana[index],
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),

          const SizedBox(height: 20),

          // Leyenda
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLeyenda(Colors.green, 'Bajo'),
              const SizedBox(width: 12),
              _buildLeyenda(Colors.orange, 'Medio'),
              const SizedBox(width: 12),
              _buildLeyenda(Colors.red, 'Alto'),
            ],
          ),

          const SizedBox(height: 16),

          // Resumen
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildResumenStat(
                  '${_clasificacionDias.where((d) => d['clasificacion'] == 'Alto').length}',
                  'Días alto',
                  Colors.red,
                ),
                _buildResumenStat(
                  '${_clasificacionDias.where((d) => d['clasificacion'] == 'Medio').length}',
                  'Días medio',
                  Colors.orange,
                ),
                _buildResumenStat(
                  '${_clasificacionDias.where((d) => d['clasificacion'] == 'Bajo').length}',
                  'Días bajo',
                  Colors.green,
                ),
              ],
            ),
          ),
          // Detectar patrones automáticamente
          if (_patronDetectado.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _patronDetectado,
                      style: TextStyle(
                        color: Colors.blue[900],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_anomaliaDetectada.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _anomaliaDetectada,
                      style: TextStyle(
                        color: Colors.orange[900],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClusteringCard() {
    final List<dynamic> semanas = _clusteringData['resultados'] ?? [];
    final List<dynamic> clustersInfo = _clusteringData['clusters_info'] ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.table_chart,
                  color: Colors.purple,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patrones de Semanas (K-Means)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    Text(
                      'Agrupación por consumo similar',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (semanas.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Se necesitan al menos 3 semanas de datos',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ),
            )
          else
            Column(
              children: [
                // Información de la semana actual
                if (semanas.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.shade50,
                          Colors.purple.shade100,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Esta Semana',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              semanas.first['cluster_nombre'] ?? 'Cluster indefinido',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${semanas.first['consumo_kWh']} kWh',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // Resumen de Clusters
                const Text(
                  'Resumen de Clusters',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 12),

                // Tabla de clusters
                if (clustersInfo.isNotEmpty)
                  ...clustersInfo.map((cluster) {
                    Color color;
                    IconData icono;
                    if (cluster['nombre'] == 'Bajo consumo') {
                      color = Colors.green;
                      icono = Icons.arrow_downward;
                    } else if (cluster['nombre'] == 'Consumo medio') {
                      color = Colors.orange;
                      icono = Icons.remove;
                    } else {
                      color = Colors.red;
                      icono = Icons.arrow_upward;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          // Icono
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icono, color: color, size: 18),
                          ),
                          const SizedBox(width: 12),
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cluster['nombre'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${cluster['num_semanas']} semanas',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      ' • ',
                                      style: TextStyle(color: Colors.grey[400]),
                                    ),
                                    Text(
                                      'Promedio: ${cluster['consumo_promedio']} kWh',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),

                const SizedBox(height: 16),

                // Tabla detallada de semanas
                const Text(
                  'Últimas Semanas',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 12),

                // Header de tabla
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Semana',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Consumo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Cluster',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Filas de tabla
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8),
                    ),
                  ),
                  child: Column(
                    children: semanas.take(8).map((semana) {
                      Color clusterColor;
                      if (semana['cluster_nombre'] == 'Bajo consumo') {
                        clusterColor = Colors.green;
                      } else if (semana['cluster_nombre'] == 'Consumo medio') {
                        clusterColor = Colors.orange;
                      } else {
                        clusterColor = Colors.red;
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                semana['fecha_inicio'] ?? '',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${semana['consumo_kWh']} kWh',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: clusterColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  semana['cluster_nombre']
                                      ?.split(' ')
                                      .first ??
                                      '',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: clusterColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLeyenda(Color color, String texto) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          texto,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildResumenStat(String valor, String etiqueta, Color color) {
    return Column(
      children: [
        Text(
          valor,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          etiqueta,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  String _obtenerDiaAbreviado(String fecha) {
    try {
      final date = DateTime.parse(fecha);
      const dias = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
      return dias[date.weekday % 7];
    } catch (e) {
      return '?';
    }
  }
}