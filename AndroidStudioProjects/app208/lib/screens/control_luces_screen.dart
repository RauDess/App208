import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import 'dart:convert';
import 'login_screen.dart';
import 'consumo_screen.dart';
import 'admin/jornadas_screen.dart';
import 'admin/aprobar_usuarios_screen.dart';
import 'admin/solicitudes_cambio_pwd_screen.dart';
import 'package:flutter/cupertino.dart';
import 'configurar_preguntas_screen.dart';
import 'cambiar_contrasena_screen.dart';
import 'editar_datos_screen.dart';

class ControlLucesScreen extends StatefulWidget {
  final Usuario usuario;

  const ControlLucesScreen({super.key, required this.usuario});

  @override
  State<ControlLucesScreen> createState() => _ControlLucesScreenState();
}

class _ControlLucesScreenState extends State<ControlLucesScreen> {
  bool _grupo1Encendido = false;
  bool _grupo2Encendido = false;
  bool _isLoading = false;
  final _authService = AuthService();
  Timer? _timer;
  TimeOfDay? _horaTemporizador;
  bool _temporizadorActivo = false;
  String _temporizadorHora = '';
  String _nombreUsuario = '';
  String _rolUsuario = '';

  @override
  void initState() {
    super.initState();
    _cargarEstadoLuces();
    _cargarDatosUsuario();
    _cargarEstadoTemporizador();

    // Timer cada 5 segundos
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _cargarEstadoLuces();
      _cargarEstadoTemporizador();
    });

    // Verificar preguntas de seguridad (solo coordinador)
    if (widget.usuario.rol == 'coordinador') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verificarPreguntasSeguridad();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancelar timer al salir
    super.dispose();
  }

  void _reiniciarTimer() {
    _timer?.cancel();  // Cancelar el anterior
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _cargarEstadoLuces();
      _cargarEstadoTemporizador();
    });
  }

  // Obtener token
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Actualizar Datos Usuario
  Future<void> _cargarDatosUsuario() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/usuarios/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _nombreUsuario = data['nombre'] ?? widget.usuario.nombre;
          _rolUsuario = data['rol'] ?? widget.usuario.rol;
        });
      }
    } catch (e) {
      // Si hay error, usar datos del widget
      setState(() {
        _nombreUsuario = widget.usuario.nombre;
        _rolUsuario = widget.usuario.rol;
      });
    }
  }

  // Cambiar de estado Grupo 1
  Future<void> _toggleGrupo1() async {
    _timer?.cancel();
    final nuevoEstado = !_grupo1Encendido;
    final estadoAnterior = _grupo1Encendido;

    // Actualización optimista
    setState(() {
      _grupo1Encendido = nuevoEstado;
      _isLoading = true;
    });

    try {
      final token = await _getToken();
      final endpoint = nuevoEstado ? 'encender' : 'apagar';

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/luces/$endpoint'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'grupo': 1}),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['temporizador_cancelado'] == true) {
          setState(() {
            _temporizadorActivo = false;
            _temporizadorHora = '';
          });
        }
        // Solo mostrar si realmente cambió algo (no si ya estaba en ese estado)
        if (nuevoEstado != estadoAnterior) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(nuevoEstado ? 'Grupo 1 encendido' : 'Grupo 1 apagado'),
                backgroundColor: nuevoEstado ? Colors.green[600] : Colors.grey[700],
                duration: const Duration(milliseconds: 1500),
              ),
            );
          }
        }
      } else {
        // Revertir
        setState(() => _grupo1Encendido = estadoAnterior);

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al cambiar estado del Grupo 1'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1), // ← OPTIMIZADO: 1 segundo para errores
            ),
          );
        }
      }
    } catch (e) {
      // Revertir
      setState(() {
        _grupo1Encendido = estadoAnterior;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1), // ← OPTIMIZADO
          ),
        );
      }
    }
    _reiniciarTimer();
  }

  // Cambiar de estado Grupo 2
  Future<void> _toggleGrupo2() async {
    _timer?.cancel();
    final nuevoEstado = !_grupo2Encendido;
    final estadoAnterior = _grupo2Encendido;

    // Actualización optimista
    setState(() {
      _grupo2Encendido = nuevoEstado;
      _isLoading = true;
    });

    try {
      final token = await _getToken();
      final endpoint = nuevoEstado ? 'encender' : 'apagar';

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/luces/$endpoint'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'grupo': 2}),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['temporizador_cancelado'] == true) {
          setState(() {
            _temporizadorActivo = false;
            _temporizadorHora = '';
          });
        }
        // Solo mostrar si realmente cambió algo (no si ya estaba en ese estado)
        if (nuevoEstado != estadoAnterior) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(nuevoEstado ? 'Grupo 2 encendido' : 'Grupo 2 apagado'),
                backgroundColor: nuevoEstado ? Colors.green[600] : Colors.grey[700],
                duration: const Duration(milliseconds: 1500),
              ),
            );
          }
        }
      } else {
        // Revertir si falló
        setState(() => _grupo2Encendido = estadoAnterior);
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al cambiar estado del Grupo 2'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1), // ← OPTIMIZADO
            ),
          );
        }
      }
    } catch (e) {
      // Revertir si hay error
      setState(() {
        _grupo2Encendido = estadoAnterior;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1), // ← OPTIMIZADO
          ),
        );
      }
    }
    _reiniciarTimer();
  }

  // Apagar Todo
  Future<void> _apagarTodo() async {
    _timer?.cancel();
    final estadoAnteriorG1 = _grupo1Encendido;
    final estadoAnteriorG2 = _grupo2Encendido;

    // Actualización optimista
    setState(() {
      _grupo1Encendido = false;
      _grupo2Encendido = false;
      _isLoading = true;
    });

    try {
      final token = await _getToken();

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/luces/apagar'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'grupo': 'todos'}),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['temporizador_cancelado'] == true) {
          setState(() {
            _temporizadorActivo = false;
            _temporizadorHora = '';
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message']),
              backgroundColor: Colors.grey[700],
              behavior: SnackBarBehavior.floating,
              duration: const Duration(milliseconds: 1000), // ← OPTIMIZADO: 1 segundo
            ),
          );
        }
      } else {
        // Revertir si falló
        setState(() {
          _grupo1Encendido = estadoAnteriorG1;
          _grupo2Encendido = estadoAnteriorG2;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al apagar las luces'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1), // ← OPTIMIZADO
            ),
          );
        }
      }
    } catch (e) {
      // Revertir si hay error
      setState(() {
        _grupo1Encendido = estadoAnteriorG1;
        _grupo2Encendido = estadoAnteriorG2;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1), // ← OPTIMIZADO
          ),
        );
      }
    }
    _reiniciarTimer();
  }

  Future<void> _verificarPreguntasSeguridad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/auth/tiene-preguntas-configuradas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        print('DEBUG Preguntas:');
        print('tiene_preguntas: ${data['tiene_preguntas']}');
        print('debe_mostrar: ${data['debe_mostrar']}');
        print('es_obligatorio: ${data['es_obligatorio']}');

        // Si debe mostrar el recordatorio
        if (data['debe_mostrar'] == true && data['tiene_preguntas'] == false) {
          final esObligatorio = data['es_obligatorio'] ?? false;

          // ← AGREGAR ESTE LOG AQUÍ:
          print('   MOSTRANDO DIÁLOGO:');
          print('   es_obligatorio: $esObligatorio');
          print('   veces_pospuesto: ${data['veces_pospuesto']}');

          if (mounted) {
            _mostrarDialogoPreguntas(esObligatorio);
          }
        }
      }
    } catch (e) {
      print('Error verificando preguntas: $e');
    }
  }

  void _mostrarDialogoPreguntas(bool esObligatorio) {
    showDialog(
      context: context,
      barrierDismissible: !esObligatorio, // No se puede cerrar si es obligatorio
      builder: (context) => WillPopScope(
        onWillPop: () async => !esObligatorio, // Bloquear botón de atrás si es obligatorio
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                esObligatorio ? Icons.warning : Icons.security,
                color: esObligatorio ? Colors.orange : const Color(AppConstants.primaryColor),
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  esObligatorio
                      ? '¡Acción Requerida!'
                      : 'Preguntas de Seguridad',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                esObligatorio
                    ? 'Por seguridad, debes configurar tus preguntas de seguridad para continuar usando la aplicación.'
                    : 'Te recomendamos configurar tus preguntas de seguridad. Las usarás para recuperar tu contraseña si la olvidas.',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Solo toma 2 minutos configurarlas',
                        style: TextStyle(fontSize: 13, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (!esObligatorio)
              TextButton(
                onPressed: () async {
                  // Posponer recordatorio
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    final token = prefs.getString('token');

                    await http.post(
                      Uri.parse('${AppConstants.baseUrl}/auth/tiene-preguntas-configuradas'),
                      headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer $token',
                      },
                    );

                    Navigator.pop(context);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Te recordaremos más tarde'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error posponiendo: $e');
                    Navigator.pop(context);
                  }
                },
                child: const Text('Más Tarde'),
              ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                // Ir a configurar preguntas
                final configurado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ConfigurarPreguntasScreen(),
                  ),
                );

                // Si configuró exitosamente
                if (configurado == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Preguntas configuradas correctamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(AppConstants.primaryColor),
                foregroundColor: Colors.white,
              ),
              child: const Text('Configurar Ahora'),
            ),
          ],
        ),
      ),
    );
  }

  Future<int> _obtenerSolicitudesCambioPwd() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/usuarios/solicitudes-cambio-pwd'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.length;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  //Cerrar Sesión y apagar luces
  Future<void> _cerrarSesion() async {
    // Si hay luces encendidas, preguntar
    if (_grupo1Encendido || _grupo2Encendido) {
      final confirmar = await showDialog<bool>(
        context: context,
        barrierDismissible: false, // No cerrar tocando fuera
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Luces encendidas'),
            ],
          ),
          content: const Text(
            '¿Deseas apagar las luces antes de cerrar sesión?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Dejar encendidas'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Apagar luces'),
            ),
          ],
        ),
      );

      if (confirmar == true) {
        await _apagarTodo();
        // Esperar a que se apaguen
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // Cerrar sesión
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
    );
  }

  Future<int> _obtenerUsuariosPendientes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/usuarios/pendientes'),

        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.length;
      }
      return 0;
    }catch (e) {
      return 0;
    }
  }

  Future<void> _cargarEstadoLuces() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/luces/estado'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _grupo1Encendido = data['grupo1'];
          _grupo2Encendido = data['grupo2'];
        });
        print('Estado cargado: Grupo1=${data['grupo1']}, Grupo2=${data['grupo2']}');
      }
    } catch (e) {
      print('Error cargando estado: $e');
    }
  }

  Future<void> _cargarEstadoTemporizador() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/temporizador/estado'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _temporizadorActivo = data['activo'];
          if (_temporizadorActivo) {
            _temporizadorHora = data['hora'];
          }
        });
      }
    } catch (e) {
      print('Error cargando temporizador: $e');
    }
  }

  // Metodo para mostrar rueda infinita de las hora
  Future<TimeOfDay?> _showCupertinoTimePicker(
      BuildContext context,
      TimeOfDay initialTime,
      ) async {
    int selectedHour = initialTime.hour;
    int selectedMinute = initialTime.minute;

    return await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: 350,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[300]!),
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
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Text(
                      'Seleccionar Hora',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(AppConstants.primaryColor),
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Hora actual seleccionada (grande)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 32,
                      color: Color(AppConstants.primaryColor),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Color(AppConstants.primaryColor),
                      ),
                    ),
                  ],
                ),
              ),

              // Ruedas de selección
              Expanded(
                child: Row(
                  children: [
                    // Rueda de HORAS
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: selectedHour,
                        ),
                        itemExtent: 50,
                        looping: true,
                        onSelectedItemChanged: (int index) {
                          selectedHour = index;
                          // Actualizar el display de hora
                          (context as Element).markNeedsBuild();
                        },
                        children: List<Widget>.generate(24, (int index) {
                          return Center(
                            child: Text(
                              index.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Separador ":"
                    const Text(
                      ':',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(AppConstants.primaryColor),
                      ),
                    ),

                    // Rueda de MINUTOS
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: selectedMinute,
                        ),
                        itemExtent: 50,
                        looping: true,
                        onSelectedItemChanged: (int index) {
                          selectedMinute = index;
                          // Actualizar el display de hora
                          (context as Element).markNeedsBuild();
                        },
                        children: List<Widget>.generate(60, (int index) {
                          return Center(
                            child: Text(
                              index.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),

              // Footer con indicador
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Desliza para seleccionar',
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
        );
      },
    );
  }

  Future<void> _programarTemporizador() async {
    // Mostrar selector de hora
    final TimeOfDay? picked = await _showCupertinoTimePicker(
      context,
      TimeOfDay.now(),
    );

    if (picked == null) return;

    final horaFormateada = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

    try {
      final token = await _getToken();

      setState(() => _isLoading = true);

      // 1. PRIMERO VALIDAR EL TEMPORIZADOR (sin encender nada)
      final validacionResponse = await http.post(
        Uri.parse('${AppConstants.baseUrl}/temporizador/programar'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'hora': horaFormateada, 'grupos': 'todos'}),
      );

      setState(() => _isLoading = false);

      // 2. SI LA HORA ES INVÁLIDA, MOSTRAR ERROR Y SALIR
      if (validacionResponse.statusCode != 200) {
        final errorMsg = validacionResponse.statusCode == 400
            ? jsonDecode(validacionResponse.body)['message']
            : 'Error al programar temporizador';

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return; // SALIR - NO ENCENDER LUCES
      }

      // 3. SI LA VALIDACIÓN PASÓ, AHORA SÍ ENCENDER LUCES SI ESTÁN APAGADAS
      final bool hayLucesApagadas = !_grupo1Encendido || !_grupo2Encendido;
      final bool estadoAnteriorG1 = _grupo1Encendido;  // ← AGREGAR ESTA LÍNEA
      final bool estadoAnteriorG2 = _grupo2Encendido;  // ← AGREGAR ESTA LÍNEA

      if (hayLucesApagadas) {
        setState(() {
          _grupo1Encendido = true;
          _grupo2Encendido = true;
          _isLoading = true;
        });

        bool todoOk = true;

        if (!estadoAnteriorG1) {
          final r1 = await http.post(
            Uri.parse('${AppConstants.baseUrl}/luces/encender'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode({'grupo': 1, 'metodo': 'Temporizador'}),
          );
          if (r1.statusCode != 200) todoOk = false;
        }

        if (!estadoAnteriorG2) {
          final r2 = await http.post(
            Uri.parse('${AppConstants.baseUrl}/luces/encender'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode({'grupo': 2, 'metodo': 'Temporizador'}),
          );
          if (r2.statusCode != 200) todoOk = false;
        }

        setState(() => _isLoading = false);

        if (!todoOk) {
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error al encender luces'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 1),
              ),
            );
          }
          return;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Luces encendidas'),
              backgroundColor: Colors.green,
              duration: Duration(milliseconds: 800),
            ),
          );
        }
      }

      // 4. CONFIRMAR TEMPORIZADOR ACTIVADO
      setState(() {
        _temporizadorActivo = true;
        _temporizadorHora = horaFormateada;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Apagado programado: $horaFormateada'),
            backgroundColor: Colors.blue[700],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }

    } catch (e) {
      setState(() => _isLoading = false);
      print('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _cancelarTemporizador() async {
    // Guardar estado anterior
    final bool estadoAnteriorG1 = _grupo1Encendido;
    final bool estadoAnteriorG2 = _grupo2Encendido;
    final bool estadoAnteriorTemp = _temporizadorActivo;
    final String horaAnterior = _temporizadorHora;

    // Actualización optimista
    setState(() {
      _temporizadorActivo = false;
      _temporizadorHora = '';
      _grupo1Encendido = false;
      _grupo2Encendido = false;
      _isLoading = true;
    });

    try {
      final token = await _getToken();

      // Cancelar temporizador y apagar luces
      final results = await Future.wait([
        http.delete(
          Uri.parse('${AppConstants.baseUrl}/temporizador/cancelar'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        ),
        http.post(
          Uri.parse('${AppConstants.baseUrl}/luces/apagar'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({'grupo': 'todos'}),
        ),
      ]);

      setState(() => _isLoading = false);

      if (results.every((r) => r.statusCode == 200)) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Temporizador cancelado - Luces apagadas'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              duration: Duration(milliseconds: 1000), // ← OPTIMIZADO: 1 segundo
            ),
          );
        }
      } else {
        // Revertir si falló
        setState(() {
          _grupo1Encendido = estadoAnteriorG1;
          _grupo2Encendido = estadoAnteriorG2;
          _temporizadorActivo = estadoAnteriorTemp;
          _temporizadorHora = horaAnterior;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al cancelar'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1), // ← OPTIMIZADO
            ),
          );
        }
      }
    } catch (e) {
      // Revertir si hay error
      setState(() {
        _grupo1Encendido = estadoAnteriorG1;
        _grupo2Encendido = estadoAnteriorG2;
        _temporizadorActivo = estadoAnteriorTemp;
        _temporizadorHora = horaAnterior;
        _isLoading = false;
      });
      print('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1), // ← OPTIMIZADO
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Control de luces'),
        backgroundColor: const Color(AppConstants.primaryColor),
        foregroundColor: Colors.white,
        actions: [
          if (widget.usuario.rol == 'coordinador')
            IconButton(
              icon: const Icon(Icons.schedule),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        JornadasScreen(usuario: widget.usuario),
                  ),
                );
              },
              tooltip: 'Gestionar horarios',
            ),

          if (widget.usuario.rol == 'coordinador')
            FutureBuilder<int>(
              future: _obtenerUsuariosPendientes(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.people),
                      onPressed: (){
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                AprobarUsuariosScreen(usuario: widget.usuario),
                          ),
                        ).then((_) => setState(() {})); //Recargar al volver
                      },
                      tooltip: 'Aprobar usuarios',
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

          if (widget.usuario.rol == 'coordinador')
            FutureBuilder<int>(
              future: _obtenerSolicitudesCambioPwd(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.lock_reset),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SolicitudesCambioPwdScreen(
                              usuario: widget.usuario,
                            ),
                          ),
                        ).then((_) => setState(() {}));
                      },
                      tooltip: 'Cambios de contraseña',
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

          // Configuración de seguridad (con menú desplegable)
          PopupMenuButton<String>(
            icon: const Icon(Icons.security),
            tooltip: 'Configuración de seguridad',
            onSelected: (String value) async {
              if (value == 'cambiar_contraseña') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const CambiarContrasenaScreen(),
                  ),
                );
              } else if (value == 'cambiar_preguntas') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ConfigurarPreguntasScreen(
                      esActualizacion: true,
                    ),
                  ),
                );
              } else if (value == 'editar_datos') {
                final resultado = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const EditarDatosScreen(),
                  ),
                );

                if (resultado == true) {
                  await _cargarDatosUsuario(); // ← Esperar a que termine
                  setState(() {}); // ← Forzar reconstrucción del widget completo
                }
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(  // ← AGREGAR PRIMERO
                value: 'editar_datos',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20, color: Color(AppConstants.primaryColor)),
                    SizedBox(width: 10),
                    Text('Editar mis datos'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'cambiar_contraseña',
                child: Row(
                  children: [
                    Icon(
                      Icons.lock,
                      size: 20,
                      color: Color(AppConstants.primaryColor), // ← AGREGAR COLOR
                    ),
                    SizedBox(width: 10),
                    Text('Cambiar Contraseña'),
                  ],
                ),
              ),
              if (widget.usuario.rol == 'coordinador')
                const PopupMenuItem<String>(
                  value: 'cambiar_preguntas',
                  child: Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 20,
                        color: Color(AppConstants.primaryColor), // ← AGREGAR COLOR
                      ),
                      SizedBox(width: 10),
                      Text('Cambiar Preguntas de Seguridad'),
                    ],
                  ),
                ),
            ],
          ),

          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ConsumoScreen(usuario: widget.usuario),
                ),
              );
            },
            tooltip: 'Ver consumo',
          ),

          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar sesión',
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                //Tarjeta de información del usuario
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: const Color(
                            AppConstants.primaryColor,
                          ),
                          child: Text(
                            _nombreUsuario.isNotEmpty ? _nombreUsuario[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              fontSize: 28,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _nombreUsuario,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _rolUsuario.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Activo',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                const Text(
                  'Aula 208 - ULEAM El Carmen',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Control de Iluminación',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),

                const SizedBox(height: 30),

                //Control grupo 1
                _buildControlCard(
                  titulo: 'Grupo 1',
                  subtitulo: '9 Tubos Fluerescentes',
                  encendido: _grupo1Encendido,
                  onToggle: _toggleGrupo1,
                  icono: Icons.lightbulb,
                ),

                const SizedBox(height: 20),

                //Control grupo 2
                _buildControlCard(
                  titulo: 'Grupo 2',
                  subtitulo: '9 Tubos Fluerescentes',
                  encendido: _grupo2Encendido,
                  onToggle: _toggleGrupo2,
                  icono: Icons.lightbulb,
                ),

                const SizedBox(height: 30),

                //Botón para apagar todo
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed:
                    (_grupo1Encendido || _grupo2Encendido) && !_isLoading
                        ? _apagarTodo
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 4,
                    ),
                    icon: const Icon(Icons.power_settings_new, size: 28),
                    label: const Text(
                      'Apagar todo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Temporizador
                Container(
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
                      Row(
                        children: [
                          Icon(
                            Icons.alarm,
                            color: const Color(AppConstants.primaryColor),
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Temporizador',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      if (_temporizadorActivo) ...[
                        // Temporizador activo
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green[300]!, width: 2),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.schedule, color: Colors.green[700], size: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Apagado programado',
                                      style: TextStyle(
                                        color: Colors.green[900],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Hora: $_temporizadorHora',
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _cancelarTemporizador,
                                icon: Icon(Icons.cancel, color: Colors.red[700], size: 32),
                                tooltip: 'Cancelar temporizador',
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Sin temporizador
                        Text(
                          'Programa una hora para apagar las luces automáticamente',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _programarTemporizador,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(AppConstants.primaryColor),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.access_time),
                            label: const Text(
                              'Programar Apagado',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                //Informacion Adicional
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.white.withOpacity(0.9),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Los cambios se registran automaticamente en el sistema',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
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

  Widget _buildControlCard({
    required String titulo,
    required String subtitulo,
    required bool encendido,
    required VoidCallback onToggle,
    required IconData icono,
  }) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: encendido
                ? [Colors.amber[100]!, Colors.orange[50]!]
                : [Colors.grey[100]!, Colors.grey[50]!],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
                Icon(
                  icono,
                  size: 50,
                  color: encendido ? Colors.amber[700] : Colors.grey[400],
                ),
              ],
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: !encendido && !_isLoading ? onToggle : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      'ON',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: encendido && !_isLoading ? onToggle : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      'OFF',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: encendido ? Colors.green[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: encendido ? Colors.green[700] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    encendido ? 'ENCENDIDO' : 'APAGADO',
                    style: TextStyle(
                      color: encendido ? Colors.green[700] : Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
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
}