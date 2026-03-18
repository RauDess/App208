import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/constants.dart';
import 'package:app208/utils/notificaciones.dart';

class ConfigurarPreguntasScreen extends StatefulWidget {
  final bool obligatorio;
  final bool esActualizacion;

  const ConfigurarPreguntasScreen({super.key,this.obligatorio = false,this.esActualizacion = false,
  });

  @override
  State<ConfigurarPreguntasScreen> createState() => _ConfigurarPreguntasScreenState();
}

class _ConfigurarPreguntasScreenState extends State<ConfigurarPreguntasScreen> {
  final _formKey = GlobalKey<FormState>();

  // Banco de preguntas
  final List<String> _bancoPreguntas = [
    '¿Cuál es el nombre de tu primera mascota?',
    '¿En qué ciudad naciste?',
    '¿Cuál es tu color favorito?',
    '¿Cuál es el segundo nombre de tu madre?',
    '¿Cuál es el apellido de soltera de tu madre?',
    '¿Cuál fue el nombre de tu primera escuela?',
    '¿Cuál es tu comida favorita?',
    '¿En qué año te graduaste de la universidad?',
    '¿Cuál es el nombre de tu mejor amigo de la infancia?',
    '¿Cuál es tu película favorita?',
  ];

  String? _pregunta1;
  String? _pregunta2;
  String? _pregunta3;

  final _respuesta1Controller = TextEditingController();
  final _respuesta2Controller = TextEditingController();
  final _respuesta3Controller = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _respuesta1Controller.dispose();
    _respuesta2Controller.dispose();
    _respuesta3Controller.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _guardarPreguntas() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pregunta1 == null || _pregunta2 == null || _pregunta3 == null) {
      Notificaciones.mostrarError(context, 'Debes seleccionar las 3 preguntas');
      return;
    }

    if (_pregunta1 == _pregunta2 || _pregunta1 == _pregunta3 || _pregunta2 == _pregunta3) {
      Notificaciones.mostrarError(context, 'No puedes repetir preguntas');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await _getToken();

      // Determinar endpoint según si es actualización o configuración inicial
      final url = widget.esActualizacion
          ? '${AppConstants.baseUrl}/auth/actualizar-preguntas'
          : '${AppConstants.baseUrl}/auth/configurar-preguntas';

      final response = widget.esActualizacion
          ? await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'pregunta1': _pregunta1,
          'respuesta1': _respuesta1Controller.text.trim(),
          'pregunta2': _pregunta2,
          'respuesta2': _respuesta2Controller.text.trim(),
          'pregunta3': _pregunta3,
          'respuesta3': _respuesta3Controller.text.trim(),
        }),
      )
          : await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'pregunta1': _pregunta1,
          'respuesta1': _respuesta1Controller.text.trim(),
          'pregunta2': _pregunta2,
          'respuesta2': _respuesta2Controller.text.trim(),
          'pregunta3': _pregunta3,
          'respuesta3': _respuesta3Controller.text.trim(),
        }),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 30),
                  SizedBox(width: 10),
                  Text('¡Listo!'),
                ],
              ),
              content: Text(
                widget.esActualizacion
                    ? 'Tus preguntas de seguridad han sido actualizadas exitosamente.'
                    : 'Tus preguntas de seguridad han sido configuradas exitosamente.\n\n'
                    'Podrás usar estas preguntas para recuperar tu contraseña en el futuro.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(AppConstants.primaryColor),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        }
      } else {
        final error = jsonDecode(response.body)['message'];
        if (mounted) {
          Notificaciones.mostrarError(context, error);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error de conexión: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(  // ← AGREGAR ESTO
        onWillPop: () async {
          // Si es obligatorio, NO permitir regresar
          if (widget.obligatorio) {
            Notificaciones.mostrarAdvertencia(context, 'Debes configurar tus preguntas para continuar');
            return false; // No permite regresar
          }
          return true; // Permite regresar si no es obligatorio
        },
        child: Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Preguntas de Seguridad'),
        backgroundColor: const Color(AppConstants.primaryColor),
        foregroundColor: Colors.white,
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
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Ícono
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.security,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Card principal
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Preguntas de Seguridad',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Selecciona 3 preguntas y proporciona sus respuestas. '
                                'Las usarás para recuperar tu contraseña si la olvidas.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Pregunta 1
                          const Text(
                            'Pregunta 1',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _pregunta1,
                            isExpanded: true,  // ← AGREGAR ESTA LÍNEA
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Selecciona una pregunta',
                            ),
                            items: _bancoPreguntas
                                .map((pregunta) => DropdownMenuItem(
                              value: pregunta,
                              child: Text(
                                pregunta,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,  // ← AGREGAR ESTA LÍNEA
                              ),
                            ))
                                .toList(),
                            onChanged: (value) {
                              setState(() => _pregunta1 = value);
                            },
                            validator: (value) {
                              if (value == null) return 'Selecciona una pregunta';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _respuesta1Controller,
                            decoration: const InputDecoration(
                              labelText: 'Respuesta',
                              border: OutlineInputBorder(),
                              hintText: 'Tu respuesta',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingresa tu respuesta';
                              }
                              if (value.trim().length < 2) {
                                return 'Respuesta muy corta';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          // Pregunta 2
                          const Text(
                            'Pregunta 2',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _pregunta1,
                            isExpanded: true,  // ← AGREGAR ESTA LÍNEA
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Selecciona una pregunta',
                            ),
                            items: _bancoPreguntas
                                .map((pregunta) => DropdownMenuItem(
                              value: pregunta,
                              child: Text(
                                pregunta,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,  // ← AGREGAR ESTA LÍNEA
                              ),
                            ))
                                .toList(),
                            onChanged: (value) {
                              setState(() => _pregunta2 = value);
                            },
                            validator: (value) {
                              if (value == null) return 'Selecciona una pregunta';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _respuesta2Controller,
                            decoration: const InputDecoration(
                              labelText: 'Respuesta',
                              border: OutlineInputBorder(),
                              hintText: 'Tu respuesta',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingresa tu respuesta';
                              }
                              if (value.trim().length < 2) {
                                return 'Respuesta muy corta';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          // Pregunta 3
                          const Text(
                            'Pregunta 3',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _pregunta1,
                            isExpanded: true,  // ← AGREGAR ESTA LÍNEA
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Selecciona una pregunta',
                            ),
                            items: _bancoPreguntas
                                .map((pregunta) => DropdownMenuItem(
                              value: pregunta,
                              child: Text(
                                pregunta,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,  // ← AGREGAR ESTA LÍNEA
                              ),
                            ))
                                .toList(),
                            onChanged: (value) {
                              setState(() => _pregunta3 = value);
                            },
                            validator: (value) {
                              if (value == null) return 'Selecciona una pregunta';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _respuesta3Controller,
                            decoration: const InputDecoration(
                              labelText: 'Respuesta',
                              border: OutlineInputBorder(),
                              hintText: 'Tu respuesta',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingresa tu respuesta';
                              }
                              if (value.trim().length < 2) {
                                return 'Respuesta muy corta';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 32),

                          // Botón guardar
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _guardarPreguntas,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(AppConstants.primaryColor),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                                  : const Text(
                                'Guardar Preguntas',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
     ),
    );
  }
}