import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'package:app208/utils/notificaciones.dart';

class EditarDatosScreen extends StatefulWidget {
  const EditarDatosScreen({Key? key}) : super(key: key);

  @override
  State<EditarDatosScreen> createState() => _EditarDatosScreenState();
}

class _EditarDatosScreenState extends State<EditarDatosScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _cedulaController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosActuales();
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? '';
  }

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

  Future<void> _cargarDatosActuales() async {
    setState(() => _isLoading = true);

    try {
      final token = await _getToken();

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
          _nombreController.text = data['nombre'] ?? '';
          _cedulaController.text = data['cedula'] ?? '';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final token = await _getToken();

      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/usuarios/actualizar-datos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'nombre': _nombreController.text.trim(),
          'cedula': _cedulaController.text.trim(),
        }),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        /// NO actualizar SharedPreferences - los datos vienen del backend
        if (mounted) {
          Navigator.pop(context, true);
          Notificaciones.mostrarExito(context, 'Datos actualizados correctamente');
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
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppConstants.primaryColor),
      appBar: AppBar(
        title: const Text('Editar mis datos'),
        backgroundColor: const Color(AppConstants.primaryColor),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Card blanca con formulario
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Actualiza tu información',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(AppConstants.primaryColor),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Los cambios se verán en toda la aplicación',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 30),

                      // CAMPO: Nombres Completos
                      TextFormField(
                        controller: _nombreController,
                        maxLength: 100,
                        decoration: InputDecoration(
                          labelText: 'Nombres Completos',
                          hintText: 'Nombre y Apellido',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]')
                          ),
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
                          // Validar mínimo 2 palabras (nombre + apellido)
                          if (value.trim().split(RegExp(r'\s+')).length < 2) {
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

                      // CAMPO: Cédula
                      TextFormField(
                        controller: _cedulaController,
                        decoration: InputDecoration(
                          labelText: 'Cédula',
                          hintText: '1234567890',
                          prefixIcon: const Icon(Icons.badge),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Ingrese su cédula';
                          }
                          if (value.trim().length != 10) {
                            return 'La cédula debe tener 10 dígitos';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),

                      // Botón Guardar
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _guardarCambios,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(AppConstants.primaryColor),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Guardar cambios',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _cedulaController.dispose();
    super.dispose();
  }
}