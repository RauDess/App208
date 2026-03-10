import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/constants.dart';
import 'configurar_preguntas_screen.dart';

class RecuperarContrasenaScreen extends StatefulWidget {
  const RecuperarContrasenaScreen({super.key});

  @override
  State<RecuperarContrasenaScreen> createState() => _RecuperarContrasenaScreenState();
}

class _RecuperarContrasenaScreenState extends State<RecuperarContrasenaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cedulaController = TextEditingController();

  // Para coordinador
  final _respuesta1Controller = TextEditingController();
  final _respuesta2Controller = TextEditingController();
  final _respuesta3Controller = TextEditingController();

  // Para todos
  final _nuevaContrasenaController = TextEditingController();
  final _confirmarContrasenaController = TextEditingController();

  bool _isLoading = false;
  bool _obscureNueva = true;
  bool _obscureConfirmar = true;
  bool _cedulaValidada = false;
  bool _esCoordinador = false;

  String _nombreUsuario = '';
  List<String> _preguntas = [];

  @override
  void dispose() {
    _cedulaController.dispose();
    _respuesta1Controller.dispose();
    _respuesta2Controller.dispose();
    _respuesta3Controller.dispose();
    _nuevaContrasenaController.dispose();
    _confirmarContrasenaController.dispose();
    super.dispose();
  }

  Future<void> _validarCedula() async {
    if (_cedulaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa tu cédula'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_cedulaController.text.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cédula debe tener 10 dígitos'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Primero verificar si es coordinador
      final responseCoord = await http.get(
        Uri.parse('${AppConstants.baseUrl}/auth/tiene-preguntas/${_cedulaController.text}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (responseCoord.statusCode == 200) {
        final dataCoord = jsonDecode(responseCoord.body);

        if (dataCoord['es_coordinador'] == true) {
          // ES COORDINADOR - Obtener preguntas
          if (!dataCoord['tiene_preguntas']) {
            setState(() => _isLoading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No tienes preguntas de seguridad configuradas. Contacta al administrador.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 4),
                ),
              );
            }
            return;
          }

          // Obtener las preguntas
          final responsePreguntas = await http.get(
            Uri.parse('${AppConstants.baseUrl}/auth/obtener-preguntas/${_cedulaController.text}'),
            headers: {'Content-Type': 'application/json'},
          );

          if (responsePreguntas.statusCode == 200) {
            final dataPreguntas = jsonDecode(responsePreguntas.body);
            setState(() {
              _cedulaValidada = true;
              _esCoordinador = true;
              _nombreUsuario = dataPreguntas['nombre'];
              _preguntas = List<String>.from(dataPreguntas['preguntas']);
              _isLoading = false;
            });
            return;
          }
        }
      }

      // NO ES COORDINADOR - Validar como usuario normal
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/validar-cedula'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'cedula': _cedulaController.text}),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _cedulaValidada = true;
          _esCoordinador = false;
          _nombreUsuario = data['nombre'];
        });
      } else {
        final error = jsonDecode(response.body)['message'];
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _recuperarCoordinador() async {
    if (_respuesta1Controller.text.trim().isEmpty ||
        _respuesta2Controller.text.trim().isEmpty ||
        _respuesta3Controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes responder las 3 preguntas'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_nuevaContrasenaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa tu nueva contraseña'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_nuevaContrasenaController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La contraseña debe tener al menos 8 caracteres'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_nuevaContrasenaController.text != _confirmarContrasenaController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las contraseñas no coinciden'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/recuperar-coordinador'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'cedula': _cedulaController.text,
          'respuesta1': _respuesta1Controller.text.trim(),
          'respuesta2': _respuesta2Controller.text.trim(),
          'respuesta3': _respuesta3Controller.text.trim(),
          'nueva_contrasena': _nuevaContrasenaController.text,
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
                  Text('¡Contraseña Actualizada!'),
                ],
              ),
              content: const Text(
                'Tu contraseña ha sido cambiada exitosamente.\n\n'
                    'Ya puedes iniciar sesión con tu nueva contraseña.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(AppConstants.primaryColor),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Ir a Iniciar Sesión'),
                ),
              ],
            ),
          );
        }
      } else {
        final error = jsonDecode(response.body)['message'];
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cambiarContrasenaUsuario() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/solicitar-cambio-contrasena'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'cedula': _cedulaController.text,
          'nueva_contrasena': _nuevaContrasenaController.text,
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
                  Text('Solicitud Enviada'),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tu solicitud de cambio de contraseña fue enviada al coordinador.',
                    style: TextStyle(fontSize: 15),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Espera la aprobación para poder iniciar sesión con tu nueva contraseña.',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'ℹ️ Recibirás una notificación cuando sea aprobada.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(AppConstants.primaryColor),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperar Contraseña'),
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Ícono
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _esCoordinador ? Icons.admin_panel_settings : Icons.lock_reset,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Card principal
                    Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              _esCoordinador ? 'Recuperar Contraseña - Coordinador' : 'Recuperar Contraseña',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              _cedulaValidada
                                  ? (_esCoordinador
                                  ? 'Hola $_nombreUsuario, responde tus preguntas de seguridad.'
                                  : 'Hola $_nombreUsuario, ingresa tu nueva contraseña.')
                                  : 'Ingresa tu cédula para continuar.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Campo: Cédula
                            TextFormField(
                              controller: _cedulaController,
                              keyboardType: TextInputType.number,
                              enabled: !_cedulaValidada,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              maxLength: 10,
                              decoration: InputDecoration(
                                labelText: 'Cédula',
                                prefixIcon: const Icon(Icons.badge),
                                border: const OutlineInputBorder(),
                                counterText: '',
                                filled: _cedulaValidada,
                                fillColor: _cedulaValidada ? Colors.grey[200] : null,
                                suffixIcon: _cedulaValidada
                                    ? const Icon(Icons.check_circle, color: Colors.green)
                                    : null,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Botón: Validar Cédula
                            if (!_cedulaValidada)
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _validarCedula,
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
                                    'Validar Cédula',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),

                            // COORDINADOR - Preguntas de seguridad
                            if (_cedulaValidada && _esCoordinador) ...[
                              Text(
                                _preguntas[0],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _respuesta1Controller,
                                decoration: const InputDecoration(
                                  labelText: 'Respuesta 1',
                                  border: OutlineInputBorder(),
                                ),
                              ),

                              const SizedBox(height: 16),

                              Text(
                                _preguntas[1],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _respuesta2Controller,
                                decoration: const InputDecoration(
                                  labelText: 'Respuesta 2',
                                  border: OutlineInputBorder(),
                                ),
                              ),

                              const SizedBox(height: 16),

                              Text(
                                _preguntas[2],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _respuesta3Controller,
                                decoration: const InputDecoration(
                                  labelText: 'Respuesta 3',
                                  border: OutlineInputBorder(),
                                ),
                              ),

                              const SizedBox(height: 24),
                            ],

                            // Campos de contraseña (para ambos)
                            if (_cedulaValidada) ...[
                              TextFormField(
                                controller: _nuevaContrasenaController,
                                obscureText: _obscureNueva,
                                decoration: InputDecoration(
                                  labelText: 'Nueva Contraseña',
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureNueva ? Icons.visibility_off : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() => _obscureNueva = !_obscureNueva);
                                    },
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Ingresa una contraseña';
                                  }
                                  if (value.length < 8) {
                                    return 'Mínimo 8 caracteres';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              TextFormField(
                                controller: _confirmarContrasenaController,
                                obscureText: _obscureConfirmar,
                                decoration: InputDecoration(
                                  labelText: 'Confirmar Contraseña',
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmar ? Icons.visibility_off : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() => _obscureConfirmar = !_obscureConfirmar);
                                    },
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Confirma tu contraseña';
                                  }
                                  if (value != _nuevaContrasenaController.text) {
                                    return 'Las contraseñas no coinciden';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 24),

                              // Botón: Cambiar Contraseña
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : (_esCoordinador ? _recuperarCoordinador : _cambiarContrasenaUsuario),
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
                                    'Cambiar Contraseña',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            // Botón: Cancelar
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
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