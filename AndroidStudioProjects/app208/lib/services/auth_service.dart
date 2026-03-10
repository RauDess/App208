import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/usuario.dart';
import '../utils/constants.dart';

class AuthService {
  // Login
  Future<Map<String, dynamic>> login(String cedula, String contrasena) async {
    try {
      final response = await http.post(
        Uri.parse(AppConstants.loginEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'cedula': cedula,
          'contrasena': contrasena,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Guardar token y datos del usuario
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('usuario', jsonEncode(data['usuario']));

        return {
          'success': true,
          'usuario': Usuario.fromJson(data['usuario']),
          'message': 'Inicio de sesión exitoso'
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Cédula o contraseña incorrecta'
        };
      } else if (response.statusCode == 403) {
        return {
          'success': false,
          'message': 'Usuario no aprobado por el coordinador'
        };
      } else {
        return {
          'success': false,
          'message': 'Error del servidor' //+response.statusCode.toString()
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: $e'
      };
    }
  }

  // Registro de nuevo usuario
  Future<Map<String, dynamic>> registro(
      String nombre,
      String cedula,
      String rol,
      String contrasena,
      ) async {
    try {
      final response = await http.post(
        Uri.parse(AppConstants.registroEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nombre': nombre,
          'cedula': cedula,
          'rol': rol,
          'contrasena': contrasena,
        }),
      );

      if (response.statusCode == 201) {
        return {
          'success': true,
          'message': 'Solicitud de registro enviada'
        };
      } else if (response.statusCode == 409) {
        return {
          'success': false,
          'message': 'Esta cédula ya está registrada'
        };
      } else {
        return {
          'success': false,
          'message': 'Error al registrar usuario'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión: $e'
      };
    }
  }

  // Verificar si hay sesión activa
  Future<Usuario?> getUsuarioActual() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final usuarioJson = prefs.getString('usuario');

      if (usuarioJson != null) {
        return Usuario.fromJson(jsonDecode(usuarioJson));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Cerrar sesión
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('usuario');
  }
}