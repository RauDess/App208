import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/usuario.dart';
import '../../utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app208/utils/notificaciones.dart';

class AprobarUsuariosScreen extends StatefulWidget {
  final Usuario usuario;

  const AprobarUsuariosScreen({super.key, required this.usuario});

  @override
  State<AprobarUsuariosScreen> createState() => _AprobarUsuariosScreenState();
}

class _AprobarUsuariosScreenState extends State<AprobarUsuariosScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  List<Map<String, dynamic>> _usuariosPendientes = [];
  List<Map<String, dynamic>> _usuariosActivos = [];
  List<Map<String, dynamic>> _usuariosInactivos = [];
  List<Map<String, dynamic>> _usuariosRechazados = [];

  bool _isLoading = true;

  // PALETA DE COLORES MEJORADA
  static const Color colorExito = Color(0xFF00897B);
  static const Color colorError = Color(0xFFD32F2F);
  static const Color colorAdvertencia = Color(0xFFFFA000);
  static const Color colorInfo = Color(0xFF00ACC1);
  static const Color colorEliminado = Color(0xFFAD1457);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging){
        setState(() {
        });
      }
    });
    _cargarTodosLosUsuarios();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _cargarTodosLosUsuarios() async {
    setState(() => _isLoading = true);

    await Future.wait([
      _cargarUsuariosPendientes(),
      _cargarUsuariosActivos(),
      _cargarUsuariosInactivos(),
      _cargarUsuariosRechazados(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _cargarUsuariosPendientes() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/usuarios/pendientes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _usuariosPendientes = data.map((u) => Map<String, dynamic>.from(u)).toList();
        });
      }
    } catch (e) {
      print('Error cargando pendientes: $e');
    }
  }

  Future<void> _cargarUsuariosActivos() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/usuarios/activos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _usuariosActivos = data.map((u) => Map<String, dynamic>.from(u)).toList();
        });
      }
    } catch (e) {
      print('Error cargando activos: $e');
    }
  }

  Future<void> _cargarUsuariosInactivos() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/usuarios/inactivos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _usuariosInactivos = data.map((u) => Map<String, dynamic>.from(u)).toList();
        });
      }
    } catch (e) {
      print('Error cargando inactivos: $e');
    }
  }

  Future<void> _cargarUsuariosRechazados() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/usuarios/rechazados'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _usuariosRechazados = data.map((u) => Map<String, dynamic>.from(u)).toList();
        });
      }
    } catch (e) {
      print('Error cargando rechazados: $e');
    }
  }

  Future<void> _aprobarUsuario(int id, String nombre) async {
    final token = await _getToken();

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/usuarios/$id/aprobar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        await _cargarTodosLosUsuarios();

        if (mounted) {
          Notificaciones.mostrarExito(context, '✓ $nombre aprobado correctamente');
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  Future<void> _rechazarUsuario(int id, String nombre) async {
    final token = await _getToken();

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/usuarios/$id/rechazar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        await _cargarTodosLosUsuarios();

        if (mounted) {
          Notificaciones.mostrarAdvertencia(context, '✗ Solicitud de $nombre rechazada');
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  Future<void> _aprobarRechazado(int id, String nombre) async {
    final token = await _getToken();

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/usuarios/$id/aprobar-rechazado'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        await _cargarTodosLosUsuarios();

        if (mounted) {
          Notificaciones.mostrarExito(context, '✓ $nombre aprobado (rechazo revertido)');
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  Future<void> _eliminarPermanente(int id, String nombre) async {
    final token = await _getToken();

    try {
      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/usuarios/$id/eliminar-permanente'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        await _cargarTodosLosUsuarios();

        if (mounted) {
          Notificaciones.mostrarError(context, '⊗ $nombre eliminado permanentemente');
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  Future<void> _desactivarUsuario(int id, String nombre) async {
    final token = await _getToken();

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/usuarios/$id/desactivar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        await _cargarTodosLosUsuarios();

        if (mounted) {
          Notificaciones.mostrarAdvertencia(context, '⊘ $nombre desactivado');
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  Future<void> _reactivarUsuario(int id, String nombre) async {
    final token = await _getToken();

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/usuarios/$id/reactivar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        await _cargarTodosLosUsuarios();

        if (mounted) {
          Notificaciones.mostrarExito(context, '✓ $nombre reactivado');
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  Future<void> _editarRolUsuario(int id, String nombreUsuario, String rolActual) async {
    final nuevoRol = rolActual == 'docente' ? 'limpieza' : 'docente';
    final nombreNuevoRol = nuevoRol == 'docente' ? 'Docente' : 'Personal de Limpieza';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar Rol'),
        content: Text(
            'Usuario: $nombreUsuario\n\n'
                'Cambiar rol a: $nombreNuevoRol'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    final token = await _getToken();

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.baseUrl}/usuarios/$id/editar-rol'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'rol': nuevoRol}),
      );

      if (response.statusCode == 200) {
        await _cargarTodosLosUsuarios();

        if (mounted) {
          Notificaciones.mostrarInfo(context, '✎ Rol de $nombreUsuario actualizado a $nombreNuevoRol');
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  Future<void> _vaciarRechazados() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vaciar Rechazados'),
        content: const Text(
          '¿Eliminar permanentemente todos los rechazados con más de 15 días?\n\n'
              'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: colorEliminado),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    final token = await _getToken();

    try {
      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/usuarios/vaciar-rechazados'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _cargarTodosLosUsuarios();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message']),
              backgroundColor: colorEliminado,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  Future<void> _vaciarInactivos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vaciar Inactivos'),
        content: const Text(
          '¿Eliminar permanentemente todos los usuarios inactivos?\n\n'
              'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: colorEliminado),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    final token = await _getToken();

    try {
      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/usuarios/vaciar-inactivos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _cargarTodosLosUsuarios();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message']),
              backgroundColor: colorEliminado,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Notificaciones.mostrarError(context, 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        backgroundColor: const Color(AppConstants.primaryColor),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: [
            Tab(
              icon: Badge(
                label: Text('${_usuariosPendientes.length}'),
                isLabelVisible: _usuariosPendientes.isNotEmpty,
                child: const Icon(Icons.pending_actions),
              ),
              text: 'Pendientes',
            ),
            Tab(
              icon: Badge(
                label: Text('${_usuariosRechazados.length}'),
                isLabelVisible: _usuariosRechazados.isNotEmpty,
                backgroundColor: colorError,
                child: const Icon(Icons.block),
              ),
              text: 'Rechazados',
            ),
            Tab(
              icon: Badge(
                label: Text('${_usuariosActivos.length}'),
                child: const Icon(Icons.check_circle),
              ),
              text: 'Activos',
            ),
            Tab(
              icon: Badge(
                label: Text('${_usuariosInactivos.length}'),
                isLabelVisible: _usuariosInactivos.isNotEmpty,
                child: const Icon(Icons.pause_circle),
              ),
              text: 'Inactivos',
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarTodosLosUsuarios,
            tooltip: 'Recargar',
          ),
          // Solo mostrar menú en pestañas 1 y 3
          if (_tabController.index == 1 || _tabController.index == 3)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'vaciar_rechazados') {
                  _vaciarRechazados();
                } else if (value == 'vaciar_inactivos') {
                  _vaciarInactivos();
                }
              },
              itemBuilder: (context) {
                final tabIndex = _tabController.index;

                if (tabIndex == 1) {
                  return [
                    const PopupMenuItem(
                      value: 'vaciar_rechazados',
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep, color: colorEliminado),
                          SizedBox(width: 8),
                          Text('Vaciar rechazados antiguos'),
                        ],
                      ),
                    ),
                  ];
                } else {
                  return [
                    const PopupMenuItem(
                      value: 'vaciar_inactivos',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever, color: colorAdvertencia),
                          SizedBox(width: 8),
                          Text('Vaciar inactivos'),
                        ],
                      ),
                    ),
                  ];
                }
              },
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : TabBarView(
          controller: _tabController,
          children: [
            _buildListaUsuarios(_usuariosPendientes, 'pendientes'),
            _buildListaUsuarios(_usuariosRechazados, 'rechazados'),
            _buildListaUsuarios(_usuariosActivos, 'activos'),
            _buildListaUsuarios(_usuariosInactivos, 'inactivos'),
          ],
        ),
      ),
    );
  }

  Widget _buildListaUsuarios(List<Map<String, dynamic>> usuarios, String tipo) {
    if (usuarios.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tipo == 'pendientes' ? Icons.check_circle_outline :
              tipo == 'rechazados' ? Icons.block :
              tipo == 'activos' ? Icons.people_outline : Icons.pause_circle_outline,
              size: 80,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              tipo == 'pendientes' ? 'No hay solicitudes pendientes' :
              tipo == 'rechazados' ? 'No hay usuarios rechazados' :
              tipo == 'activos' ? 'No hay usuarios activos' :
              'No hay usuarios inactivos',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: usuarios.length,
      itemBuilder: (context, index) {
        final usuario = usuarios[index];
        return _buildUsuarioCard(usuario, tipo);
      },
    );
  }

  Widget _buildUsuarioCard(Map<String, dynamic> usuario, String tipo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(AppConstants.primaryColor),
                  child: Text(
                    usuario['nombre'][0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        usuario['nombre'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cédula: ${usuario['cedula']}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      if (tipo == 'rechazados' && usuario['dias_rechazado'] != null)
                        Text(
                          'Rechazado hace ${usuario['dias_rechazado']} días',
                          style: TextStyle(fontSize: 12, color: Colors.red[700]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: usuario['rol'] == 'docente' ? Colors.blue[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                usuario['rol'] == 'docente' ? 'Docente' : 'Personal de Limpieza',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: usuario['rol'] == 'docente' ? Colors.blue[700] : Colors.green[700],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildBotones(usuario, tipo),
          ],
        ),
      ),
    );
  }

  Widget _buildBotones(Map<String, dynamic> usuario, String tipo) {
    if (tipo == 'pendientes') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirmarAprobacion(usuario['id_usuario'], usuario['nombre']),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorExito,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Aprobar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirmarRechazo(usuario['id_usuario'], usuario['nombre']),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorError,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.close, size: 20),
              label: const Text('Rechazar'),
            ),
          ),
        ],
      );
    } else if (tipo == 'rechazados') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirmarAprobarRechazado(usuario['id_usuario'], usuario['nombre']),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorExito,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Aprobar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirmarEliminarPermanente(usuario['id_usuario'], usuario['nombre']),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorEliminado,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.delete_forever, size: 20),
              label: const Text('Eliminar'),
            ),
          ),
        ],
      );
    } else if (tipo == 'activos') {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _editarRolUsuario(
                      usuario['id_usuario'],
                      usuario['nombre'],
                      usuario['rol']
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorInfo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.edit, size: 20),
                  label: const Text('Editar Rol'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _confirmarDesactivacion(usuario['id_usuario'], usuario['nombre']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorAdvertencia,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.block, size: 20),
                  label: const Text('Desactivar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmarEliminarPermanente(usuario['id_usuario'], usuario['nombre']),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorEliminado,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.delete_forever, size: 20),
              label: const Text('Eliminar Permanentemente'),
            ),
          ),
        ],
      );
    } else {
      // INACTIVOS
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmarReactivacion(usuario['id_usuario'], usuario['nombre']),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorExito,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Reactivar'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmarEliminarPermanente(usuario['id_usuario'], usuario['nombre']),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorEliminado,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.delete_forever, size: 20),
              label: const Text('Eliminar Permanentemente'),
            ),
          ),
        ],
      );
    }
  }

  void _confirmarAprobacion(int id, String nombre) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar aprobación'),
        content: Text('¿Aprobar el registro de $nombre?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _aprobarUsuario(id, nombre);
            },
            child: const Text('Aprobar', style: TextStyle(color: colorExito)),
          ),
        ],
      ),
    );
  }

  void _confirmarRechazo(int id, String nombre) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar rechazo'),
        content: Text('¿Rechazar la solicitud de $nombre?\n\nPodrás revertir esta acción desde la pestaña "Rechazados".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _rechazarUsuario(id, nombre);
            },
            child: const Text('Rechazar', style: TextStyle(color: colorError)),
          ),
        ],
      ),
    );
  }

  void _confirmarAprobarRechazado(int id, String nombre) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar aprobación'),
        content: Text('¿Aprobar a $nombre?\n\nEsto revertirá el rechazo anterior.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _aprobarRechazado(id, nombre);
            },
            child: const Text('Aprobar', style: TextStyle(color: colorExito)),
          ),
        ],
      ),
    );
  }

  void _confirmarEliminarPermanente(int id, String nombre) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Eliminar Permanentemente'),
        content: Text(
          '¿Eliminar permanentemente a $nombre?\n\n'
              '⚠️ ESTA ACCIÓN NO SE PUEDE DESHACER.\n'
              'Se borrará completamente de la base de datos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _eliminarPermanente(id, nombre);
            },
            child: const Text('ELIMINAR', style: TextStyle(color: colorEliminado, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmarDesactivacion(int id, String nombre) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar desactivación'),
        content: Text('¿Desactivar a $nombre?\n\nPodrás reactivarlo después si es necesario.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _desactivarUsuario(id, nombre);
            },
            child: const Text('Desactivar', style: TextStyle(color: colorAdvertencia)),
          ),
        ],
      ),
    );
  }

  void _confirmarReactivacion(int id, String nombre) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar reactivación'),
        content: Text('¿Reactivar a $nombre?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _reactivarUsuario(id, nombre);
            },
            child: const Text('Reactivar', style: TextStyle(color: colorExito)),
          ),
        ],
      ),
    );
  }
}