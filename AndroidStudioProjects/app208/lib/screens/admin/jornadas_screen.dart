import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../models/usuario.dart';
import '../../utils/constants.dart';
import 'package:flutter/services.dart';
import 'package:app208/utils/notificaciones.dart';

class JornadasScreen extends StatefulWidget {
  final Usuario usuario;

  const JornadasScreen({super.key, required this.usuario});

  @override
  State<JornadasScreen> createState() => _JornadasScreenState();
}

// Formatea fecha: YYYY-MM-DD (0000-00-00)
class _FechaInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    String text = newValue.text;

    // Permitir vacío
    if (text.isEmpty) {
      return newValue;
    }

    // Remover guiones
    String digits = text.replaceAll('-', '');

    // Solo dígitos
    if (!RegExp(r'^\d*$').hasMatch(digits)) {
      return oldValue;
    }

    // Limitar a 8 dígitos
    if (digits.length > 8) {
      return oldValue;
    }

    // Formatear
    String formatted = '';

    if (digits.length <= 4) {
      formatted = digits;
    } else if (digits.length <= 6) {
      formatted = '${digits.substring(0, 4)}-${digits.substring(4)}';
    } else {
      formatted = '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _JornadasScreenState extends State<JornadasScreen> {
  String _diaSeleccionado = 'Lunes';
  Map<String, dynamic> _jornadaDelDia = {};
  bool _isLoading = true;
  String _periodoActual = '';

  @override
  void initState() {
    super.initState();
    _verificarPeriodoActivo();
    _cargarPeriodo();
    _cargarJornadas();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _verificarPeriodoActivo() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/periodo/activo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['activo'] == false && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['mensaje']),
              backgroundColor: Colors.orange[700],
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      // Silencioso
    }
  }

  Future<void> _cargarPeriodo() async {
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
        setState(() {
          _periodoActual = data['periodo'] ?? '';
        });
      }
    } catch (e) {
      print('Error cargando periodo: $e');
    }
  }

  Future<void> _cargarJornadas() async {
    setState(() => _isLoading = true);

    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/jornadas/$_diaSeleccionado'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _jornadaDelDia = data;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error cargando jornadas: $e');
      setState(() => _isLoading = false);
    }
  }

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null) return null;
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } catch (e) {
      print('Error parseando tiempo: $e');
    }
    return null;
  }

  String _timeToString(TimeOfDay? time) {
    if (time == null) return '';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }

  Future<void> _guardarJornada(
      String dia,
      TimeOfDay? inicioMat,
      TimeOfDay? finMat,
      TimeOfDay? inicioVesp,
      TimeOfDay? finVesp,
      ) async {
    try {
      final token = await _getToken();
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/jornadas/$dia'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'hora_inicio_matutina': inicioMat != null ? _timeToString(inicioMat) : null,
          'hora_fin_matutina': finMat != null ? _timeToString(finMat) : null,
          'hora_inicio_vespertina': inicioVesp != null ? _timeToString(inicioVesp) : null,
          'hora_fin_vespertina': finVesp != null ? _timeToString(finVesp) : null,
        }),
      );

      if (response.statusCode == 200) {
        await _cargarJornadas();
        if (mounted) {
          Notificaciones.mostrarExito(context, 'Jornada de $dia actualizada');
        }
      } else {
        final error = jsonDecode(response.body)['message'];
        if (mounted) {
          Notificaciones.mostrarError(context, 'Error: $error');
        }
      }
    } catch (e) {
      print('Error guardando jornada: $e');
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error de conexión: $e');
      }
    }
  }

  Future<void> _cambiarPeriodo() async {
    final periodoController = TextEditingController(text: '');
    final fechaInicioController = TextEditingController(text: '');
    final fechaFinController = TextEditingController(text: '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          'Configurar Período Académico',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Complete la información del nuevo período académico:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              // CAMPO 1: Período
              TextField(
                controller: periodoController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Período',
                  hintText: 'YYYY-N',
                  border: OutlineInputBorder(),
                  helperText: 'Formato: YYYY-1 o YYYY-2',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
              ),
              const SizedBox(height: 16),

              // CAMPO 2: Fecha inicio
              TextField(
                controller: fechaInicioController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Fecha de inicio',
                  hintText: 'YYYY-MM-DD',
                  border: OutlineInputBorder(),
                  helperText: 'Formato: YYYY-MM-DD',
                  prefixIcon: Icon(Icons.event),
                ),
              ),
              const SizedBox(height: 16),

              // CAMPO 3: Fecha fin
              TextField(
                controller: fechaFinController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Fecha de fin',
                  hintText: 'YYYY-MM-DD',
                  border: OutlineInputBorder(),
                  helperText: 'Formato: YYYY-MM-DD',
                  prefixIcon: Icon(Icons.event_available),
                ),
              ),
              const SizedBox(height: 12),

              // NOTA INFORMATIVA
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El período debe tener al menos 4 meses de duración',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
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
              final nuevoPeriodo = periodoController.text.trim();
              final fechaInicio = fechaInicioController.text.trim();
              final fechaFin = fechaFinController.text.trim();

              // VALIDACIONES FRONTEND
              if (nuevoPeriodo.isEmpty || fechaInicio.isEmpty || fechaFin.isEmpty) {
                Notificaciones.mostrarError(context, 'Todos los campos son obligatorios');
                return;
              }

              // Validar formato período
              final validacionPeriodo = _validarPeriodo(nuevoPeriodo);
              if (validacionPeriodo != null) {
                Notificaciones.mostrarError(context, validacionPeriodo);
                return;
              }

              // Validar formato fechas
              final validacionFechas = _validarFechas(fechaInicio, fechaFin, nuevoPeriodo);
              if (validacionFechas != null) {
                Notificaciones.mostrarError(context, validacionFechas);
                return;
              }

              // ENVIAR AL BACKEND
              try {
                final token = await _getToken();
                final response = await http.put(
                  Uri.parse('${AppConstants.baseUrl}/jornadas/periodo'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $token',
                  },
                  body: jsonEncode({
                    'periodo': nuevoPeriodo,
                    'fecha_inicio': fechaInicio,
                    'fecha_fin': fechaFin,
                  }),
                );

                if (response.statusCode == 200) {
                  Navigator.pop(context);  // Cerrar diálogo de configuración

                  // RECARGAR DATOS
                  await _cargarPeriodo();
                  await _cargarJornadas();

                  // MOSTRAR DIÁLOGO DE ÉXITO (IGUAL QUE EL DE CONFIGURAR)
                  if (mounted) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        title: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green[600], size: 28),
                            const SizedBox(width: 12),
                            const Text(
                              'Período Configurado',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        content: Text(
                          'El período $nuevoPeriodo se ha configurado correctamente.\n\nInicio: $fechaInicio\nFin: $fechaFin',
                          style: const TextStyle(fontSize: 14),
                        ),
                        actions: [
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(AppConstants.primaryColor),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Aceptar'),
                          ),
                        ],
                      ),
                    );
                  }
                } else {
                  // ERROR: Mostrar diálogo de error
                  final error = jsonDecode(response.body)['message'];
                  Navigator.pop(context);  // Cerrar diálogo de configuración

                  if (mounted) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => AlertDialog(
                        title: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[600], size: 28),
                            const SizedBox(width: 12),
                            const Text(
                              'Error de Validación',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        content: Text(
                          error,
                          style: const TextStyle(fontSize: 14),
                        ),
                        actions: [
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Entendido'),
                          ),
                        ],
                      ),
                    );
                  }
                }

              } catch (e) {
                if (mounted) {
                  Notificaciones.mostrarError(context, 'Error de conexión: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(AppConstants.primaryColor),
              foregroundColor: Colors.white,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  String? _validarPeriodo(String periodo) {
    // Validar que no esté vacío
    if (periodo.isEmpty) {
      return 'Ingresa un periodo válido';
    }

    // Validar formato YYYY-N
    final regex = RegExp(r'^(\d{4})-([1-2])$');
    final match = regex.firstMatch(periodo);

    if (match == null) {
      return 'Formato incorrecto. Usa: YYYY-1 o YYYY-2';
    }

    final ano = int.parse(match.group(1)!);
    final periodo_num = match.group(2)!;

    // Validar que el periodo sea 1 o 2
    if (periodo_num != '1' && periodo_num != '2') {
      return 'El periodo debe ser 1 o 2';
    }

    return null; // Válido
  }

  String? _validarFechas(String fechaInicio, String fechaFin, String periodo) {
    // Validar formato YYYY-MM-DD
    final regexFecha = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
    final regexPeriodo = RegExp(r'^(\d{4})-([1-2])$');

    final matchInicio = regexFecha.firstMatch(fechaInicio);
    final matchFin = regexFecha.firstMatch(fechaFin);
    final matchPeriodo = regexPeriodo.firstMatch(periodo);

    if (matchPeriodo == null) {
      return 'El formato de período no es correcto';
    }

    if (matchInicio == null) {
      return 'El formato de fecha de inicio no es correcto';
    }

    if (matchFin == null) {
      return 'El formato de fecha de fin no es correcto';
    }

    // Extraer componentes
    final anoPeriodo = int.parse(matchPeriodo.group(1)!);
    final numeroPeriodo = matchPeriodo.group(2)!;

    final anoInicio = int.parse(matchInicio.group(1)!);
    final mesInicio = int.parse(matchInicio.group(2)!);
    final diaInicio = int.parse(matchInicio.group(3)!);

    final anoFin = int.parse(matchFin.group(1)!);
    final mesFin = int.parse(matchFin.group(2)!);
    final diaFin = int.parse(matchFin.group(3)!);

    // VALIDACIÓN 1: Año del período debe coincidir con inicio O fin
    if (anoPeriodo != anoInicio && anoPeriodo != anoFin) {
      return 'El año del período ($anoPeriodo) debe coincidir con el año de inicio ($anoInicio) o fin ($anoFin)';
    }

    // VALIDACIÓN 1.5: Fechas no muy antiguas ni futuras (coherencia básica)
    final anoActual = DateTime.now().year;

    if (anoInicio < anoActual - 2 || anoInicio > anoActual + 2) {
      return 'La fecha de inicio ($fechaInicio) parece incorrecta. Verifique el año.';
    }

    if (anoFin < anoActual - 2 || anoFin > anoActual + 2) {
      return 'La fecha de fin ($fechaFin) parece incorrecta. Verifique el año.';
    }

    // VALIDACIÓN 2: Mes entre 01-12
    if (mesInicio < 1 || mesInicio > 12) {
      return 'El mes de inicio debe estar entre 01 y 12';
    }

    if (mesFin < 1 || mesFin > 12) {
      return 'El mes de fin debe estar entre 01 y 12';
    }

    // VALIDACIÓN 3: Día según el mes
    final diasPorMes = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    // Verificar año bisiesto para febrero
    bool esBisiesto(int ano) {
      return (ano % 4 == 0 && ano % 100 != 0) || (ano % 400 == 0);
    }

    // Días máximos para cada mes
    int diasMaxInicio = diasPorMes[mesInicio - 1];
    if (mesInicio == 2 && esBisiesto(anoInicio)) {
      diasMaxInicio = 29;
    }

    int diasMaxFin = diasPorMes[mesFin - 1];
    if (mesFin == 2 && esBisiesto(anoFin)) {
      diasMaxFin = 29;
    }

    if (diaInicio < 1 || diaInicio > diasMaxInicio) {
      return 'El día de inicio debe estar entre 01 y $diasMaxInicio para el mes $mesInicio';
    }

    if (diaFin < 1 || diaFin > diasMaxFin) {
      return 'El día de fin debe estar entre 01 y $diasMaxFin para el mes $mesFin';
    }

    // VALIDACIÓN 4: Validar que las fechas existan
    try {
      final inicio = DateTime(anoInicio, mesInicio, diaInicio);
      final fin = DateTime(anoFin, mesFin, diaFin);

      // VALIDACIÓN 5: Fecha fin > fecha inicio
      if (fin.isBefore(inicio) || fin.isAtSameMomentAs(inicio)) {
        return 'La fecha de fin debe ser posterior a la de inicio';
      }

      // VALIDACIÓN 6: Rango de 115 a 150 días
      final diferencia = fin.difference(inicio).inDays;

      if (diferencia < 120) {
        return 'El período debe tener al menos 120 días (4 meses). Actual: $diferencia días';
      }

      if (diferencia > 150) {
        return 'El período no puede exceder 150 días (5 meses). Actual: $diferencia días';
      }

      return null; // Válido

    } catch (e) {
      return 'Fechas inválidas. Verifique día/mes/año';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Jornadas'),
        backgroundColor: const Color(AppConstants.primaryColor),
        foregroundColor: Colors.white,
        actions: [
          // Mostrar periodo en el AppBar
          if (widget.usuario.rol == 'coordinador')
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: GestureDetector(
                  onTap: _cambiarPeriodo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _periodoActual,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.school, size: 40, color: Color(AppConstants.primaryColor)),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aula 208',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'ULEAM El Carmen',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                height: 50,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    'Lunes',
                    'Martes',
                    'Miércoles',
                    'Jueves',
                    'Viernes',
                  ].map((dia) => _buildDiaChip(dia)).toList(),
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: Colors.white))
                    : _jornadaDelDia.isEmpty
                    ? _buildSinJornada()
                    : _buildJornadaInfo(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.usuario.rol == 'coordinador'
          ? FloatingActionButton.extended(
        onPressed: () => _mostrarDialogoEditarJornada(),
        backgroundColor: const Color(AppConstants.primaryColor),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit),
        label: const Text('Editar Jornada'),
      )
          : null,
    );
  }

  Widget _buildDiaChip(String dia) {
    final isSelected = dia == _diaSeleccionado;

    return GestureDetector(
      onTap: () {
        setState(() {
          _diaSeleccionado = dia;
        });
        _cargarJornadas();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Text(
          dia,
          style: TextStyle(
            color: isSelected ? const Color(AppConstants.primaryColor) : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSinJornada() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 80,
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Sin jornada configurada para $_diaSeleccionado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJornadaInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_jornadaDelDia['hora_inicio_matutina'] != null)
            _buildJornadaCard(
              titulo: 'Jornada Matutina',
              horaInicio: _jornadaDelDia['hora_inicio_matutina'],
              horaFin: _jornadaDelDia['hora_fin_matutina'],
              icono: Icons.wb_sunny,
              color: Colors.amber,
            ),

          const SizedBox(height: 16),

          if (_jornadaDelDia['hora_inicio_vespertina'] != null)
            _buildJornadaCard(
              titulo: 'Jornada Vespertina',
              horaInicio: _jornadaDelDia['hora_inicio_vespertina'],
              horaFin: _jornadaDelDia['hora_fin_vespertina'],
              icono: Icons.wb_twilight,
              color: Colors.indigo,
            ),
        ],
      ),
    );
  }

  Widget _buildJornadaCard({
    required String titulo,
    required String horaInicio,
    required String horaFin,
    required IconData icono,
    required MaterialColor color,
  }) {
    final bool esMatutina = titulo.contains('Matutina');

    final Color colorPrincipal = esMatutina
        ? const Color(0xFFFFA726)  // Naranja cálido profesional
        : const Color(0xFF5C6BC0);  // Azul índigo profesional

    final Color colorFondo1 = esMatutina
        ? const Color(0xFFFFE0B2)  // Naranja claro
        : const Color(0xFFE8EAF6);  // Índigo muy claro

    final Color colorFondo2 = esMatutina
        ? const Color(0xFFFFF3E0)  // Naranja muy claro
        : const Color(0xFFF5F5FF);  // Índigo ultra claro

    return Card(
      elevation: 4,  // Reducido de 6 a 4
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colorFondo1, colorFondo2],
          ),
        ),
        child: Row(
          children: [
            Icon(icono, size: 48, color: colorPrincipal),  // Tamaño reducido
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 16,  // Reducido de 18
                      fontWeight: FontWeight.w600,  // Menos bold
                      color: colorPrincipal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$horaInicio - $horaFin',
                    style: const TextStyle(
                      fontSize: 22,  // Reducido de 24
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF263238),  // Gris oscuro profesional
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarDialogoEditarJornada() async {
    TimeOfDay? horaInicioMat = _parseTime(_jornadaDelDia['hora_inicio_matutina']);
    TimeOfDay? horaFinMat = _parseTime(_jornadaDelDia['hora_fin_matutina']);
    TimeOfDay? horaInicioVesp = _parseTime(_jornadaDelDia['hora_inicio_vespertina']);
    TimeOfDay? horaFinVesp = _parseTime(_jornadaDelDia['hora_fin_vespertina']);

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Editar Jornada - $_diaSeleccionado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Jornada Matutina',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                _buildCupertinoTimePickerField(
                  label: 'Hora inicio',
                  time: horaInicioMat,
                  icon: Icons.wb_sunny,
                  onTap: () async {
                    final picked = await _showCupertinoTimePicker(
                      context,
                      horaInicioMat ?? const TimeOfDay(hour: 7, minute: 0),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        horaInicioMat = picked;
                      });
                    }
                  },
                ),

                const SizedBox(height: 8),

                _buildCupertinoTimePickerField(
                  label: 'Hora fin',
                  time: horaFinMat,
                  icon: Icons.wb_sunny,
                  onTap: () async {
                    final picked = await _showCupertinoTimePicker(
                      context,
                      horaFinMat ?? const TimeOfDay(hour: 12, minute: 0),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        horaFinMat = picked;
                      });
                    }
                  },
                ),

                const SizedBox(height: 20),

                const Text(
                  'Jornada Vespertina',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                _buildCupertinoTimePickerField(
                  label: 'Hora inicio',
                  time: horaInicioVesp,
                  icon: Icons.wb_twilight,
                  onTap: () async {
                    final picked = await _showCupertinoTimePicker(
                      context,
                      horaInicioVesp ?? const TimeOfDay(hour: 14, minute: 0),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        horaInicioVesp = picked;
                      });
                    }
                  },
                ),

                const SizedBox(height: 8),

                _buildCupertinoTimePickerField(
                  label: 'Hora fin',
                  time: horaFinVesp,
                  icon: Icons.wb_twilight,
                  onTap: () async {
                    final picked = await _showCupertinoTimePicker(
                      context,
                      horaFinVesp ?? const TimeOfDay(hour: 18, minute: 0),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        horaFinVesp = picked;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                _guardarJornada(
                  _diaSeleccionado,
                  horaInicioMat,
                  horaFinMat,
                  horaInicioVesp,
                  horaFinVesp,
                );
                Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(AppConstants.primaryColor),
                foregroundColor: Colors.white,
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoTimePickerField({
    required String label,
    required TimeOfDay? time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$label: ${time != null ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : 'No configurado'}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const Icon(Icons.access_time, size: 20),
          ],
        ),
      ),
    );
  }

  Future<TimeOfDay?> _showCupertinoTimePicker(
      BuildContext context,
      TimeOfDay initialTime,
      ) async {
    int selectedHour = initialTime.hour;
    int selectedMinute = initialTime.minute;

    return await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16),  // ← MARGEN FLOTANTE
          child: Container(
            height: 320,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),  // ← MÁS REDONDEADO
              boxShadow: [  // ← SOMBRA FLOTANTE
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(AppConstants.primaryColor).withOpacity(0.08),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const Text(
                        'Seleccionar Hora',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            TimeOfDay(hour: selectedHour, minute: selectedMinute),
                          );
                        },
                        child: const Text(
                          'Listo',
                          style: TextStyle(
                            color: Color(AppConstants.primaryColor),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedHour,
                          ),
                          itemExtent: 44,
                          magnification: 1.15,  // ← EFECTO DE ZOOM
                          squeeze: 0.9,
                          useMagnifier: true,
                          looping: true,
                          onSelectedItemChanged: (int index) {
                            selectedHour = index;
                          },
                          children: List<Widget>.generate(24, (int index) {
                            return Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF263238),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      const Text(
                        ':',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF263238),
                        ),
                      ),

                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedMinute,
                          ),
                          itemExtent: 44,
                          magnification: 1.15,
                          squeeze: 0.9,
                          useMagnifier: true,
                          looping: true,
                          onSelectedItemChanged: (int index) {
                            selectedMinute = index;
                          },
                          children: List<Widget>.generate(60, (int index) {
                            return Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF263238),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}