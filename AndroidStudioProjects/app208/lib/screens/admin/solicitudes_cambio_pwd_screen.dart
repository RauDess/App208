import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../models/usuario.dart';
import '../../utils/constants.dart';
import 'package:app208/utils/notificaciones.dart';

class SolicitudesCambioPwdScreen extends StatefulWidget {
  final Usuario usuario;

  const SolicitudesCambioPwdScreen({super.key, required this.usuario});

  @override
  State<SolicitudesCambioPwdScreen> createState() => _SolicitudesCambioPwdScreenState();
}

class _SolicitudesCambioPwdScreenState extends State<SolicitudesCambioPwdScreen> {
  List<dynamic> _solicitudes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarSolicitudes();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _cargarSolicitudes() async {
    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/usuarios/solicitudes-cambio-pwd'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _solicitudes = data;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        print('Error cargando solicitudes: ${response.statusCode}');
      }
    } catch (e) {
      print('Error cargando solicitudes: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _aprobarSolicitud(int idUsuario, String nombreUsuario) async {
    try {
      final token = await _getToken();

      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/usuarios/$idUsuario/aprobar-cambio-pwd'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'accion': 'aprobar'}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          Notificaciones.mostrarExito(context, 'Cambio de contraseña aprobado para $nombreUsuario');
        }

        // Recargar lista
        _cargarSolicitudes();
      } else {
        String errorMsg = 'Error del servidor';
        try {
          final errorData = jsonDecode(response.body);
          errorMsg = errorData['message'] ?? errorMsg;
        } catch (e) {
          errorMsg = 'Error ${response.statusCode}';
        }
        print('❌ Error: $errorMsg');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error de conexión: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _mostrarDialogoConfirmacion(int idUsuario, String nombreUsuario) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 30),
            SizedBox(width: 10),
            Text('Aprobar Cambio'),
          ],
        ),
        content: Text(
          '¿Aprobar el cambio de contraseña para $nombreUsuario?\n\n'
              'El usuario podrá iniciar sesión con su nueva contraseña.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _aprobarSolicitud(idUsuario, nombreUsuario);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
  }

  Color _getRolColor(String rol) {
    switch (rol.toLowerCase()) {
      case 'docente':
        return Colors.teal;
      case 'limpieza':
        return Colors.orange;
      case 'coordinador':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes de Cambio de Contraseña'),
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
        child: _isLoading
            ? const Center(
          child: CircularProgressIndicator(color: Colors.white),
        )
            : _solicitudes.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 80,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No hay solicitudes pendientes',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 18,
                ),
              ),
            ],
          ),
        )
            : RefreshIndicator(
          onRefresh: _cargarSolicitudes,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _solicitudes.length,
            itemBuilder: (context, index) {
              final solicitud = _solicitudes[index];
              return _buildSolicitudCard(solicitud);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSolicitudCard(Map<String, dynamic> solicitud) {
    final nombre = solicitud['nombre'] ?? 'Sin nombre';
    final cedula = solicitud['cedula'] ?? 'Sin cédula';
    final rol = solicitud['rol'] ?? 'Sin rol';
    final idUsuario = solicitud['id_usuario'];
    final fechaSolicitud = solicitud['fecha_solicitud_cambio'] ?? '';

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con ícono y nombre
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _getRolColor(rol),
                  child: Text(
                    nombre[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cédula: $cedula',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Chip de rol
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getRolColor(rol),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    rol.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (fechaSolicitud.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    fechaSolicitud,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Botón: Aprobar (ancho completo)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _mostrarDialogoConfirmacion(idUsuario, nombre),
                icon: const Icon(Icons.check_circle, size: 22),
                label: const Text(
                  'Aprobar Cambio de Contraseña',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}