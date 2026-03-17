import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';
import 'utils/constants.dart';
import 'package:app208/utils/notificaciones.dart';

// Clave global para navegación
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {  // ← CAMBIAR A StatefulWidget
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {  // ← Crear State
  Timer? _timerAdvertencias;

  @override
  void initState() {
    super.initState();
    _iniciarVerificacionAdvertencias();
  }

  void _iniciarVerificacionAdvertencias() {
    // Verificar cada 60 segundos
    _timerAdvertencias = Timer.periodic(const Duration(seconds: 5), (timer) {
      _verificarAdvertenciaConsumoAlto();
    });
  }

  Future<void> _verificarAdvertenciaConsumoAlto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) return; // Usuario no logueado

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/consumo/advertencia-alto'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['advertencia'] == true) {
          // Mostrar notificación global
          final context = navigatorKey.currentContext;
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['mensaje']),
                backgroundColor: Colors.red[700],
                duration: const Duration(seconds: 10),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'OK',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      // Silencioso - no mostrar error de conexión al usuario
    }
  }

  @override
  void dispose() {
    _timerAdvertencias?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,  // ← AGREGAR
      title: 'Control Eficiente',
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}