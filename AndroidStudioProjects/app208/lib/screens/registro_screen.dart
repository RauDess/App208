import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';


class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _cedulaController = TextEditingController();
  final _contrasenaController = TextEditingController();
  final _confirmarContrasenaController = TextEditingController();
  final _authService = AuthService();

  String _rolSeleccionado = '';
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _validarNombreReal(String nombre) {
    final palabras = nombre.trim().split(RegExp(r'\s+'));

    for (var palabra in palabras) {
      // Muy corta (menos de 3 letras)
      if (palabra.length < 3) {
        return 'Nombre/apellido muy corto';
      }

      // Sin vocales
      if (!RegExp(r'[aeiouáéíóúAEIOUÁÉÍÓÚ]').hasMatch(palabra)) {
        return 'Verifique su nombre'; // Sin vocales
      }

      // 4+ consonantes seguidas
      if (RegExp(r'[bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ]{4,}').hasMatch(palabra)) {
        return 'Consonantes consecutivas'; // Consonantes consecutivas
      }

      // 4+ vocales seguidas
      if (RegExp(r'[aeiouáéíóúAEIOUÁÉÍÓÚ]{4,}', caseSensitive: false).hasMatch(palabra)) {
        return 'Verifique su nombre'; //Vocales consecutivas
      }
    }
    return null; // Parece válido
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _cedulaController.dispose();
    _contrasenaController.dispose();
    _confirmarContrasenaController.dispose();
    super.dispose();
  }

  Future<void> _handleRegistro() async {
    if (!_formKey.currentState!.validate()) return;

    if (_rolSeleccionado.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecciona tu rol'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.registro(
      _nombreController.text.trim(),
      _cedulaController.text.trim(),
      _rolSeleccionado,
      _contrasenaController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success']) {
      // Mostrar mensaje de éxito
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Solicitud Enviada'),
          content: const Text(
            'Tu solicitud de registro ha sido envidada.\n\n'
            'El coordinador debe aprobarla para que puedas iniciar sesión.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cerrar diálogo
                Navigator.of(context).pop(); // Volver a login
              },
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(AppConstants.primaryColor),
              Color(AppConstants.secondaryColor),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              //Boton volver
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              //Contenido scrolleable
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        //Icono
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person_add,
                            size: 50,
                            color: Color(AppConstants.primaryColor),
                          ),
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'Crear Cuenta',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 10),

                        const Text(
                          'Registrate para controlar las luces',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 30),
                        //ALERTA ************
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: const Text(
                                  'Tu solicitud será revisada por el coordinador',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),

                        //Card con formulario
                        Card(
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [

                                //NOMBRE ************************************

                                TextFormField(
                                  controller: _nombreController,
                                  maxLength: 100,  // ← Límite de caracteres
                                  decoration: InputDecoration(
                                    labelText: 'Nombres Completos',
                                    prefixIcon: const Icon(Icons.person),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]')), // Solo letras y espacios
                                  ],
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Ingrese sus nombres completos';
                                    }
                                    if (value.trim().length < 5) {
                                      return 'Nombre muy corto (mínimo 5 caracteres)';
                                    }
                                    if (!RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$').hasMatch(value.trim())) {
                                      return 'Solo letras y espacios';
                                    }
                                    if (value.trim().split(RegExp(r'\s+')).length < 2) { // Para múltiples espacios
                                      return 'Ingrese nombre y apellido';
                                    }
                                    // Validar nombre real
                                    final nombreReal = _validarNombreReal(value.trim());
                                    if (nombreReal != null) {
                                      return nombreReal;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                //CEDULA *******************

                            TextFormField(
                                controller: _cedulaController,
                                keyboardType: TextInputType.number,
                                maxLength: 10,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly, // Solo números
                                ],
                                  decoration: InputDecoration(
                                    labelText: 'Cédula',
                                    prefixIcon: const Icon(Icons.badge),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    counterText: '',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Por favor, ingrese su cédula';
                                    }
                                    if (value.length != 10) {
                                      return 'La cédula debe tener 10 dígitos';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 16),

                                //ROL ***************************

                                DropdownButtonFormField<String>(
                                  value: _rolSeleccionado.isEmpty
                                      ? null
                                      : _rolSeleccionado,
                                  decoration: InputDecoration(
                                    labelText: 'Rol',
                                    prefixIcon: const Icon(Icons.work),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'docente',
                                      child: Text('Docente'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'limpieza',
                                      child: Text('Personal de limpieza'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _rolSeleccionado = value ?? '';
                                    });
                                  },
                                ),
                                const SizedBox(height: 16),

                                //CONTRASEÑA **********************

                                TextFormField(
                                  controller: _contrasenaController,
                                  maxLength: 50,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    prefixIcon: const Icon(Icons.lock),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Por favor, ingrese una contraseña';
                                    }
                                    if (value.length < 8) {
                                      return 'La contraseña debe tener al menos 8 caracteres';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                //CONFIRMAR CONTRASEÑA  **************************

                                TextFormField(
                                  controller: _confirmarContrasenaController,
                                  obscureText: _obscureConfirmPassword,
                                  decoration: InputDecoration(
                                    labelText: 'Confirmar Contraseña',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConfirmPassword
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscureConfirmPassword =
                                              !_obscureConfirmPassword;
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Por favor, confirme su contraseña';
                                    }
                                    if (value != _contrasenaController.text) {
                                      return 'Las contraseñas no coinciden';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 24),

                                //Boton registrar
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _handleRegistro,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(
                                        AppConstants.primaryColor,
                                      ),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text(
                                            'Enviar Solicitud',
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
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}