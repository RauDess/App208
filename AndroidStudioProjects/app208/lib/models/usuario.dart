class Usuario {
  final int idUsuario;
  final String nombre;
  final String cedula;
  final String rol;
  final bool aprobado;
  final String estado;

  Usuario({
    required this.idUsuario,
    required this.nombre,
    required this.cedula,
    required this.rol,
    required this.aprobado,
    required this.estado,
  });
  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      idUsuario: json['idUsuario'] ?? 0,
      nombre: json['nombre'] ?? '',
      cedula: json['cedula'] ?? '',
      rol: json['rol'] ?? '',
      aprobado: json['aprobado'] == 1 || json['aprobado'] == true,
      estado: json['estado'] ?? 'activo',
    );
  }
  // Convertir JSON a objeto Usuario
  Map<String, dynamic> toJson() {
    return {
      'idUsuario': idUsuario,
      'nombre': nombre,
      'cedula': cedula,
      'rol': rol,
      'aprobado': aprobado,
      'estado': estado,
    };
  }
}