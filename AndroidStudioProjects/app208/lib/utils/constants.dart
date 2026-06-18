class AppConstants {
  static const String baseUrl = 'http://192.168.101.8:3000/api';   //URL para hacer las peticiones en Raspberry en la
  // Endpoints
  static const String editarRolEndpoint = '$baseUrl/usuarios';
  static const String loginEndpoint = '$baseUrl/auth/login';
  static const String registroEndpoint = '$baseUrl/auth/registro';
  static const String lucesEndpoint = '$baseUrl/luces';
  static const String consumoEndpoint = '$baseUrl/consumo';

  // Colores de la ap
  static const int primaryColor = 0xFF667EEA;
  static const int secondaryColor = 0xFF764BA2;

  // Roles
  static const String rolCoordinador = 'coordinador';
  static const String rolDocente = 'docente';
  static const String rolLimpieza = 'limpieza';
}