import 'package:flutter/material.dart';

class Notificaciones {
  /// Muestra una notificación de éxito (verde)
  static void mostrarExito(BuildContext context, String mensaje, {IconData? icono}) {
    _mostrarNotificacion(
      context: context,
      mensaje: mensaje,
      icono: icono ?? Icons.check_circle_outline,
      color: Colors.green[600]!,
    );
  }

  /// Muestra una notificación de error (rojo)
  static void mostrarError(BuildContext context, String mensaje, {IconData? icono}) {
    _mostrarNotificacion(
      context: context,
      mensaje: mensaje,
      icono: icono ?? Icons.error_outline,
      color: Colors.red[600]!,
    );
  }

  /// Muestra una notificación de advertencia (naranja)
  static void mostrarAdvertencia(BuildContext context, String mensaje, {IconData? icono}) {
    _mostrarNotificacion(
      context: context,
      mensaje: mensaje,
      icono: icono ?? Icons.warning_amber_rounded,
      color: Colors.orange[600]!,
    );
  }

  /// Muestra una notificación de información (azul)
  static void mostrarInfo(BuildContext context, String mensaje, {IconData? icono}) {
    _mostrarNotificacion(
      context: context,
      mensaje: mensaje,
      icono: icono ?? Icons.info_outline,
      color: Colors.blue[600]!,
    );
  }

  /// Función base para mostrar notificaciones
  static void _mostrarNotificacion({
    required BuildContext context,
    required String mensaje,
    required IconData icono,
    required Color color,
    Duration? duracion,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icono,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mensaje,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: duracion ?? const Duration(milliseconds: 1200),
        elevation: 6,
      ),
    );
  }
}