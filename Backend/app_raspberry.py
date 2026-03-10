from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import mysql.connector
import bcrypt
import jwt
import time
import threading
import os
import re
from functools import wraps
from dotenv import load_dotenv
from apscheduler.schedulers.background import BackgroundScheduler
from datetime import datetime, timedelta, timezone, time as dt_time
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter, A4
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Image
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from io import BytesIO
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import atexit
import platform
import numpy as np
from sklearn.tree import DecisionTreeClassifier
from sklearn.cluster import KMeans

# Detectar si estamos en Raspberry Pi
ES_RASPBERRY = platform.machine().startswith('arm') or platform.machine().startswith('aarch')

# Cargar variables de entorno
load_dotenv()

# Función: Leer estado inicial de la BD
def leer_estado_inicial_bd():
    try:
        import mysql.connector
        conn = mysql.connector.connect(
            host=os.getenv('DB_HOST'),
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASSWORD'),
            database=os.getenv('DB_NAME')
        )
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute("""
            SELECT grupo_luces FROM consumo 
            WHERE dato_apagado IS NULL
        """)
        registros = cursor.fetchall()
        
        grupo1_encendido = any(r['grupo_luces'] == 'Grupo 1' for r in registros)
        grupo2_encendido = any(r['grupo_luces'] == 'Grupo 2' for r in registros)
        
        cursor.close()
        conn.close()
        
        print(f"[BD INICIAL] Grupo1: {'ON' if grupo1_encendido else 'OFF'}, Grupo2: {'ON' if grupo2_encendido else 'OFF'}")  

        return (grupo1_encendido, grupo2_encendido)
        
    except Exception as e:
        print(f"Error leyendo estado inicial: {e}")
        # Por defecto, asumir apagado
        return (False, False)
    
# ============================================
# CONFIGURAR GPIO CON ESTADO INICIAL DE BD
# ============================================
if ES_RASPBERRY:
    # Liberar GPIO si están ocupados
    try:
        import lgpio
        h = lgpio.gpiochip_open(0)
        try:
            lgpio.gpio_free(h, 23)
        except:
            pass
        try:
            lgpio.gpio_free(h, 24)
        except:
            pass
        lgpio.gpiochip_close(h)
        print("GPIO liberados correctamente")
    except Exception as e:
        print(f"Nota GPIO: {e}")
    
    from gpiozero import OutputDevice, Button
    
    # LEER ESTADO DE BD ANTES DE CONFIGURAR
    grupo1_encendido, grupo2_encendido = leer_estado_inicial_bd()
    
    print(f"[INICIO] BD indica - Grupo1: {'ON' if grupo1_encendido else 'OFF'}, Grupo2: {'ON' if grupo2_encendido else 'OFF'}")

    # CONFIGURAR GPIO CON EL ESTADO CORRECTO
    # Con active_high=True: initial_value=False ENCIENDE, initial_value=True APAGA
    RELAY_GRUPO1 = OutputDevice(23, active_high=True, initial_value=not grupo1_encendido)
    RELAY_GRUPO2 = OutputDevice(24, active_high=True, initial_value=not grupo2_encendido)
    
    # Explicación del "not":
    # - Si grupo1_encendido=True → initial_value=False → GPIO envía LOW → Relé ENCIENDE
    # - Si grupo1_encendido=False → initial_value=True → GPIO envía HIGH → Relé APAGA
    
    def cleanup_gpio():
        RELAY_GRUPO1.close()
        RELAY_GRUPO2.close()

    atexit.register(cleanup_gpio)
    print("GPIO configurado correctamente")

else: 
    # Modo simulación (Windows/Mac)
    class GPIOSimulado:
        BCM = 'BCM'
        OUT = 'OUT'
        HIGH = 1
        LOW = 0
        
        estado_pines = {}
        
        @staticmethod
        def setmode(mode):
            print("[SIMULADO] GPIO.setmode(BCM)")
        
        @staticmethod
        def setwarnings(state):
            pass
        
        @staticmethod
        def setup(pin, mode):
            GPIOSimulado.estado_pines[pin] = GPIOSimulado.LOW
            print(f"[SIMULADO] GPIO.setup(pin {pin}, OUTPUT)")
        
        @staticmethod
        def output(pin, state):
            GPIOSimulado.estado_pines[pin] = state
            estado_texto = "HIGH (ON)" if state == GPIOSimulado.HIGH else "LOW (OFF)"
            print(f"[SIMULADO] GPIO.output(pin {pin}, {estado_texto})")
        
        @staticmethod
        def input(pin):
            return GPIOSimulado.estado_pines.get(pin, GPIOSimulado.LOW)
        
        @staticmethod
        def cleanup():
            print("[SIMULADO] GPIO.cleanup()")
    
    GPIO = GPIOSimulado()
    RELAY_GRUPO1 = 17
    RELAY_GRUPO2 = 27
    
    print("Modo SIMULACIÓN activado (no estás en Raspberry Pi)")

# ============================================
# CONFIGURAR INTERRUPTORES MANUALES (AMBOS)
# ============================================
PIN_INTERRUPTOR_G1 = 17  # Pin 11
PIN_INTERRUPTOR_G2 = 27  # Pin 13

def crear_handlers_interruptor(numero_grupo, relay):
    """Factory para crear funciones de encendido/apagado"""
    
    def encender():
        print(f"\n[INTERRUPTOR MANUAL G{numero_grupo}] Estado: ON")
        relay.on()
        
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO consumo 
            (id_usuario, nombre_usuario, grupo_luces, dato_encendido, 
             metodo_encendido, tipo_dia, estado)
            VALUES (%s, %s, %s, NOW(), %s, %s, %s)
        """, (1, 'Manual', f'Grupo {numero_grupo}', 'Manual - Interruptor', 
              'Laborable', 'encendido'))
        conn.commit()
        cursor.close()
        conn.close()
        print(f"Grupo {numero_grupo} encendido")
    
    def apagar():
        print(f"\n[INTERRUPTOR MANUAL G{numero_grupo}] Estado: OFF")
        relay.off()
        
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE consumo 
            SET dato_apagado = NOW(),
                encendido_segundos = TIMESTAMPDIFF(SECOND, dato_encendido, NOW()),
                consumo_kW = (648 * TIMESTAMPDIFF(SECOND, dato_encendido, NOW())) / 3600000.0,
                metodo_apagado = %s,
                estado = 'apagado'
            WHERE grupo_luces = %s AND dato_apagado IS NULL
            ORDER BY dato_encendido DESC LIMIT 1
        """, ('Manual - Interruptor', f'Grupo {numero_grupo}'))
        conn.commit()
        cursor.close()
        conn.close()
        print(f"Grupo {numero_grupo} apagado")
    
    return encender, apagar

# Crear handlers
encender_g1, apagar_g1 = crear_handlers_interruptor(1, RELAY_GRUPO1)
encender_g2, apagar_g2 = crear_handlers_interruptor(2, RELAY_GRUPO2)

# Configurar botones
interruptor_g1 = Button(PIN_INTERRUPTOR_G1, pull_up=False, bounce_time=0.3)
interruptor_g1.when_pressed = encender_g1
interruptor_g1.when_released = apagar_g1

interruptor_g2 = Button(PIN_INTERRUPTOR_G2, pull_up=False, bounce_time=0.3)
interruptor_g2.when_pressed = encender_g2
interruptor_g2.when_released = apagar_g2

print("[GPIO] Interruptores Grupo 1 y 2 activados")

#============================================
def generar_pdf_reporte(reporte_data):
    """
    Genera un PDF profesional del reporte semanal
    
    Args:
        reporte_data: dict con los datos del reporte
    
    Returns:
        BytesIO con el PDF generado
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter, 
                           rightMargin=72, leftMargin=72,
                           topMargin=72, bottomMargin=18)
    
    # Contenedor de elementos
    elements = []
    styles = getSampleStyleSheet()
    
    # Estilo personalizado para título
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        textColor=colors.HexColor('#1a237e'),
        spaceAfter=30,
        alignment=TA_CENTER,
        fontName='Helvetica-Bold'
    )
    
    # Estilo para subtítulos
    subtitle_style = ParagraphStyle(
        'CustomSubtitle',
        parent=styles['Heading2'],
        fontSize=14,
        textColor=colors.HexColor('#1a237e'),
        spaceAfter=12,
        spaceBefore=12,
        fontName='Helvetica-Bold'
    )
    
    # ENCABEZADO CON LOGO
    try:
        logo = Image('static/logo_uleam.png', width=1.5*inch, height=0.75*inch)
        logo.hAlign = 'CENTER'
        elements.append(logo)
        elements.append(Spacer(1, 12))
    except:
        print("No se pudo cargar el logo")
    
    # Título principal
    titulo = Paragraph("REPORTE SEMANAL DE CONSUMO ENERGÉTICO", title_style)
    elements.append(titulo)
    
    subtitulo = Paragraph("Aula 208 - ULEAM El Carmen", styles['Normal'])
    subtitulo.alignment = TA_CENTER
    elements.append(subtitulo)
    elements.append(Spacer(1, 20))
    
    # INFORMACIÓN DEL PERÍODO
    info_periodo = [
        ['Período:', reporte_data['descripcion']],
        ['Fecha de generación:', reporte_data['fecha_generacion']],
        ['Período académico:', reporte_data['periodo']],
    ]
    
    tabla_periodo = Table(info_periodo, colWidths=[2*inch, 4*inch])
    tabla_periodo.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#e3f2fd')),
        ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
        ('ALIGN', (0, 0), (0, -1), 'RIGHT'),
        ('ALIGN', (1, 0), (1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTNAME', (1, 0), (1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('GRID', (0, 0), (-1, -1), 1, colors.grey),
    ]))
    
    elements.append(tabla_periodo)
    elements.append(Spacer(1, 20))
    
    # RESUMEN GENERAL
    elements.append(Paragraph("RESUMEN GENERAL", subtitle_style))
    
    datos_resumen = [
        ['Concepto', 'Valor'],
        ['Consumo total', f"{reporte_data['total_consumo_kWh']:.2f} kWh"],
        ['Horas de uso', f"{reporte_data['total_horas_uso']:.2f} h"],
        ['Promedio diario', f"{reporte_data['promedio_diario_kWh']:.2f} kWh"],
        ['Costo estimado', f"${float(reporte_data['total_consumo_kWh']) * 0.13:.2f} USD"],
    ]
    
    tabla_resumen = Table(datos_resumen, colWidths=[3*inch, 3*inch])
    tabla_resumen.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1a237e')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 12),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
        ('GRID', (0, 0), (-1, -1), 1, colors.black),
        ('FONTNAME', (0, 1), (0, -1), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 1), (-1, -1), 11),
        ('TOPPADDING', (0, 1), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 1), (-1, -1), 8),
    ]))
    
    elements.append(tabla_resumen)
    elements.append(Spacer(1, 30))
    
    # NOTA AL PIE
    nota_style = ParagraphStyle(
        'Nota',
        parent=styles['Normal'],
        fontSize=9,
        textColor=colors.grey,
        alignment=TA_CENTER,
        spaceAfter=6
    )
    
    nota = Paragraph(
        "Tarifa eléctrica: $0.13 USD/kWh | "
        "Sistema de control automatizado - ULEAM El Carmen",
        nota_style
    )
    elements.append(Spacer(1, 20))
    elements.append(nota)
    
    fecha_generacion = Paragraph(
        f"Documento generado automáticamente el {datetime.now().strftime('%d/%m/%Y a las %H:%M')}",
        nota_style
    )
    elements.append(fecha_generacion)
    
    # CONSTRUIR PDF
    doc.build(elements)
    buffer.seek(0)
    return buffer


app = Flask(__name__)
scheduler = BackgroundScheduler()  
temporizadores_activos = {}  # Diccionario para guardar temporizadores
CORS(app)  # Permite peticiones desde Flutter

# Configuración
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY')

# Conexión a la base de datos
def get_db_connection():
    return mysql.connector.connect(
        host=os.getenv('DB_HOST'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD'),
        database=os.getenv('DB_NAME')
    )

# Decorador para verificar token JWT
def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        
        if not token:
            return jsonify({'message': 'Token faltante'}), 401
        
        try:
            # Remover "Bearer " del token
            if token.startswith('Bearer '):
                token = token[7:]
            
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
            current_user_id = data['user_id']
        except:
            return jsonify({'message': 'Token inválido'}), 401
        
        return f(current_user_id, *args, **kwargs)
    
    return decorated

def sincronizar_bd_con_gpio_al_arrancar():
    """
    Al arrancar el servicio:
    Verifica que GPIO y BD estén sincronizados
    (Los GPIO ya se configuraron con el estado correcto)
    """
    print("\n" + "="*60)
    print("VERIFICANDO SINCRONIZACIÓN GPIO-BD")
    print("="*60)
    
    if not ES_RASPBERRY:
        print("No es Raspberry Pi, saltando verificación")
        return
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # LEER ESTADO EN BD
        cursor.execute("""
            SELECT grupo_luces FROM consumo 
            WHERE dato_apagado IS NULL
        """)
        registros_bd = cursor.fetchall()
        
        bd_grupo1 = any(r['grupo_luces'] == 'Grupo 1' for r in registros_bd)
        bd_grupo2 = any(r['grupo_luces'] == 'Grupo 2' for r in registros_bd)
        
        # LEER ESTADO GPIO
        gpio1_encendido = not RELAY_GRUPO1.value
        gpio2_encendido = not RELAY_GRUPO2.value  
        
        print(f"[BD] Grupo 1: {'ON' if bd_grupo1 else 'OFF'}, Grupo 2: {'ON' if bd_grupo2 else 'OFF'}")
        print(f"[GPIO] Grupo 1: {'ON' if gpio1_encendido else 'OFF'}, Grupo 2: {'ON' if gpio2_encendido else 'OFF'}")
        
        # Verificar sincronización
        if bd_grupo1 == gpio1_encendido and bd_grupo2 == gpio2_encendido:
            print(" GPIO y BD sincronizados correctamente")
        else:
            print(" Detectada desincronización (esto no debería pasar)")
        
        cursor.close()
        conn.close()
        
        print("="*60 + "\n")
        
    except Exception as e:
        print(f" ERROR en verificación: {str(e)}")
        import traceback
        traceback.print_exc()

# FUNCIÓN: VERIFICAR SI PERÍODO ESTÁ ACTIVO
def periodo_activo():
    """
    Verifica si estamos dentro del período académico configurado
    Retorna: (True/False, periodo_nombre o None)
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener período activo
        cursor.execute("""
            SELECT periodo, fecha_inicio_periodo, fecha_fin_periodo
            FROM jornadas
            WHERE activo = 1
            LIMIT 1
        """)
        
        jornada = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if not jornada or not jornada['fecha_inicio_periodo'] or not jornada['fecha_fin_periodo']:
            return (False, None)
        
        # Verificar si hoy está dentro del rango
        hoy = datetime.now().date()
        inicio = jornada['fecha_inicio_periodo']
        fin = jornada['fecha_fin_periodo']
        
        if inicio <= hoy <= fin:
            return (True, jornada['periodo'])
        else:
            return (False, None)
            
    except Exception as e:
        print(f"Error verificando período: {e}")
        return (False, None)

###################################### INICIO SESIÓN ###################################################
# ============================================
# ENDPOINT: LOGIN
# ============================================
@app.route('/api/auth/login', methods=['POST'])
def login():
    data = request.get_json()
    cedula = data.get('cedula')
    contrasena = data.get('contrasena')

    print(f"\n=== INTENTO DE LOGIN ===")
    print(f"Cedula recibida: {cedula}")

    if not cedula or not contrasena:
        print("ERROR: Faltan Datos")
        return jsonify({'message': 'Faltan datos'}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Buscar usuario
        cursor.execute(
            "SELECT * FROM usuarios WHERE cedula = %s",
            (cedula,)
        )
        usuario = cursor.fetchone()
        
        print(f"Usuario encontrado en BD: {usuario is not None}")

        if not usuario:
            print("ERROR: Usuario no existe")
            cursor.close()
            conn.close()
            return jsonify({'message': 'Cédula o contraseña incorrecta'}), 401
        
        print(f"Usuario: {usuario['nombre']}")
        print(f"Rol: {usuario['rol']}")
        print(f"Aprobado: {usuario['aprobado']}")
        print(f"Estado: {usuario['estado']}")
        
        # VERIFICAR ESTADO ANTES DE VERIFICAR CONTRASEÑA
        # Verificar contraseña
        try:
            password_match = bcrypt.checkpw(
                contrasena.encode('utf-8'), 
                usuario['contrasena'].encode('utf-8')
            )
            print(f"¿Contraseña coincide?: {password_match}")
            
            if not password_match:
                print("ERROR: Contraseña incorrecta")
                cursor.close()
                conn.close()
                return jsonify({'message': 'Cédula o contraseña incorrecta'}), 401
                
        except Exception as e:
            print(f"ERROR al verificar contraseña: {e}")
            cursor.close()
            conn.close()
            return jsonify({'message': f'Error al verificar contraseña: {str(e)}'}), 500
        
        # Verificar si tiene solicitud pendiente de cambio de contraseña
        if usuario.get('solicitud_cambio_pwd') == 1:
            cursor.close()
            conn.close()
            return jsonify({
                'message': 'Tienes una solicitud de cambio de contraseña pendiente. Debes esperar la aprobación del coordinador.'
            }), 403

        solicitudes = cursor.fetchone()

        if solicitudes and solicitudes['pendientes'] > 0:
            cursor.close()
            conn.close()
            return jsonify({
                'message': 'Tienes una solicitud de cambio de contraseña pendiente. Debes esperar la aprobación del coordinador.'
            }), 403

        # VERIFICAR ESTADO Y APROBACIÓN CON MENSAJES APROPIADOS
        # Usuario pendiente de aprobación
        if usuario['estado'] == 'pendiente' or (not usuario['aprobado'] and usuario['estado'] != 'rechazado'):
            print("ERROR: Usuario pendiente de aprobación")
            cursor.close()
            conn.close()
            return jsonify({'message': 'Su solicitud aún no ha sido aprobada por el coordinador'}), 403
        
        # Usuario rechazado
        if usuario['estado'] == 'rechazado':
            print("ERROR: Usuario rechazado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'Su solicitud de registro fue rechazada'}), 403
        
        # Usuario inactivo (desactivado)
        if usuario['estado'] == 'inactivo':
            print("ERROR: Usuario inactivo")
            cursor.close()
            conn.close()
            return jsonify({'message': 'Su cuenta ha sido desactivada. Contacte al coordinador'}), 403
        
        # Verificar que esté activo Y aprobado
        if usuario['estado'] != 'activo' or not usuario['aprobado']:
            print("ERROR: Usuario no activo o no aprobado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No tiene acceso al sistema'}), 403
        
        # LOGIN EXITOSO
        token = jwt.encode({
            'user_id': usuario['id_usuario'],
            'exp': datetime.now(timezone.utc) + timedelta(days=7)
        }, app.config['SECRET_KEY'], algorithm="HS256")

        print("Login exitoso, generando token")

        cursor.close()
        conn.close()

        # Remover contraseña antes de enviar
        del usuario['contrasena']

        return jsonify({
            'token': token,
            'usuario': usuario
        }), 200
    
    except Exception as e:
        print(f"ERROR GENERAL: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500
    

# ============================================
# ENDPOINT: REGISTRO
# ============================================
@app.route('/api/auth/registro', methods=['POST'])
def registro():
    data = request.get_json()
    nombre = data.get('nombre')
    cedula = data.get('cedula')
    rol = data.get('rol')
    contrasena = data.get('contrasena')

    print(f"\n=== INTENTO DE REGISTRO ===")
    print(f"Nombre: {nombre}")
    print(f"Cédula: {cedula}")
    print(f"Rol: {rol}")
    
    if not all([nombre, cedula, rol, contrasena]):
        print("ERROR: Faltan datos")
        return jsonify({'message': 'Faltan datos'}), 400
    
    if rol not in ['docente', 'limpieza']:
        print(f"ERROR: Rol inválido: {rol}")
        return jsonify({'message': 'Rol inválido'}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar si la cédula ya existe
        cursor.execute(
            "SELECT id_usuario FROM usuarios WHERE cedula = %s",
            (cedula,)
        )
        usuario_existente = cursor.fetchone()

        if usuario_existente:
        # Si existe (cualquier estado) → No permitir
            return jsonify({'message': 'Esta cédula ya está registrada'}), 409

        # Si NO existe → Continuar con INSERT normal
        # (Puede ser primera vez O usuario eliminado previamente, da igual)
        
        # Encriptar contraseña
        print("Encriptando contraseña...")
        hashed_password = bcrypt.hashpw(contrasena.encode('utf-8'), bcrypt.gensalt())
    
        # INSERTAR CON ESTADO 'pendiente'
        print("Insertando en BD...")
        cursor.execute(
            """INSERT INTO usuarios 
            (nombre, cedula, rol, contrasena, fecha_registro, estado, aprobado) 
            VALUES (%s, %s, %s, %s, CURDATE(), 'pendiente', FALSE)""",  
            (nombre, cedula, rol, hashed_password.decode('utf-8'))
        )
        
        conn.commit()
        print("Usuario registrado exitosamente con estado 'pendiente'")
        cursor.close()
        conn.close()
        
        return jsonify({'message': 'Solicitud de registro enviada'}), 201
        
    except Exception as e:
        print(f"ERROR GENERAL: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500

################################################ CONTRASEÑA ###############################################
# ============================================
# ENDPOINT: VALIDAR CÉDULA PARA RECUPERACIÓN
# ============================================
@app.route('/api/auth/validar-cedula', methods=['POST'])
def validar_cedula():
    """Valida si una cédula existe y está activa"""
    print("\n[VALIDAR CÉDULA]")
    
    data = request.get_json()
    cedula = data.get('cedula')
    
    if not cedula:
        return jsonify({'message': 'Cédula no proporcionada'}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute(
            """SELECT id_usuario, nombre, rol, aprobado, estado 
            FROM usuarios 
            WHERE cedula = %s""",
            (cedula,)
        )
        usuario = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        if not usuario:
            print(f"Cédula no encontrada: {cedula}")
            return jsonify({'existe': False, 'message': 'Cédula no registrada'}), 404
        
        if not usuario['aprobado'] or usuario['estado'] != 'activo':
            print(f"Usuario no activo: {usuario['nombre']}")
            return jsonify({'existe': False, 'message': 'Usuario no activo. Contacte al coordinador'}), 403
        
        if usuario['rol'] == 'coordinador':
            print(f"Coordinador intentó recuperar: {usuario['nombre']}")
            return jsonify({
                'existe': False, 
                'message': 'Los coordinadores deben contactar al administrador del sistema'
            }), 403
        
        print(f"Cédula válida: {usuario['nombre']}")
        return jsonify({
            'existe': True, 
            'nombre': usuario['nombre'],
            'message': 'Cédula encontrada'
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: RECUPERAR CONTRASEÑA (SIN APROBACIÓN)
# ============================================
@app.route('/api/auth/recuperar-contrasena-directa', methods=['POST'])
def recuperar_contrasena_directa():
    """Usuario cambia contraseña directamente proporcionando cédula"""
    print("\n[RECUPERAR CONTRASEÑA DIRECTA]")
    
    data = request.get_json()
    cedula = data.get('cedula')
    nueva_contrasena = data.get('nueva_contrasena')
    
    if not cedula or not nueva_contrasena:
        return jsonify({'message': 'Faltan datos'}), 400
    
    # Validar longitud de contraseña
    if len(nueva_contrasena) < 8:
        return jsonify({'message': 'La contraseña debe tener al menos 8 caracteres'}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que usuario existe y está aprobado
        cursor.execute(
            """SELECT id_usuario, nombre, rol, aprobado 
            FROM usuarios 
            WHERE cedula = %s""",
            (cedula,)
        )
        usuario = cursor.fetchone()

        if not usuario:
            cursor.close()
            conn.close()
            print(f" Cédula no encontrada: {cedula}")
            return jsonify({'message': 'Cédula no encontrada'}), 404

        if not usuario['aprobado']:
            cursor.close()
            conn.close()
            print(f" Usuario no aprobado: {usuario['nombre']}")
            return jsonify({'message': 'Usuario no aprobado. Contacte al coordinador'}), 403
        
        # Verificar que la nueva contraseña sea diferente
        if bcrypt.checkpw(nueva_contrasena.encode('utf-8'), usuario['contrasena'].encode('utf-8')):
            cursor.close()
            conn.close()
            return jsonify({
                'message': 'La nueva contraseña debe ser diferente a la actual'
            }), 400

        # ESPECIAL: Si es coordinador, no permitir cambio directo
        if usuario['rol'] == 'coordinador':
            cursor.close()
            conn.close()
            print(f" Coordinador intentó recuperar contraseña: {usuario['nombre']}")
            return jsonify({
                'message': 'Los coordinadores deben contactar al administrador del sistema para cambiar su contraseña',
                'requiere_soporte': True
            }), 403
        
        # Encriptar nueva contraseña
        hashed = bcrypt.hashpw(nueva_contrasena.encode('utf-8'), bcrypt.gensalt())
        
        # Cambiar contraseña INMEDIATAMENTE
        cursor.execute(
            "UPDATE usuarios SET contrasena = %s WHERE cedula = %s",
            (hashed.decode('utf-8'), cedula)
        )
        
        conn.commit()
        print(f" Contraseña cambiada exitosamente para: {usuario['nombre']} (ID: {usuario['id_usuario']})")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'message': 'Contraseña actualizada exitosamente',
            'nombre': usuario['nombre']
        }), 200
        
    except Exception as e:
        print(f" ERROR en recuperar contraseña: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500
    

# ============================================
# ENDPOINT: VER SOLICITUDES DE CAMBIO DE CONTRASEÑA
# ============================================
@app.route('/api/usuarios/solicitudes-cambio-pwd', methods=['GET'])
@token_required
def ver_solicitudes_cambio(current_user_id):
    """Coordinador ve solicitudes de cambio de contraseña"""
    print(f"\n[SOLICITUDES CAMBIO ] Usuario {current_user_id}")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que es coordinador
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener solicitudes pendientes ORDENADAS POR MÁS RECIENTE
        cursor.execute(
            """SELECT id_usuario, nombre, cedula, rol, 
                      fecha_solicitud_cambio
            FROM usuarios 
            WHERE solicitud_cambio_pwd = 1 
            ORDER BY fecha_solicitud_cambio DESC"""  
        )
        solicitudes = cursor.fetchall()
        
        # Convertir datetime a string
        for sol in solicitudes:
            if sol['fecha_solicitud_cambio']:
                sol['fecha_solicitud_cambio'] = sol['fecha_solicitud_cambio'].strftime('%Y-%m-%d %H:%M:%S')
        
        print(f" {len(solicitudes)} solicitudes encontradas")
        
        cursor.close()
        conn.close()
        return jsonify(solicitudes), 200
        
    except Exception as e:
        print(f" ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: SOLICITAR CAMBIO DE CONTRASEÑA
# ============================================
@app.route('/api/auth/solicitar-cambio-contrasena', methods=['POST'])
def solicitar_cambio_contrasena():
    """Usuario solicita cambio de contraseña con nueva contraseña"""
    print("\n" + "="*60)
    print("SOLICITUD: Cambio de contraseña")
    print("="*60)
    
    data = request.get_json()
    cedula = data.get('cedula')
    nueva_contrasena = data.get('nueva_contrasena')
    
    if not cedula or not nueva_contrasena:
        return jsonify({'message': 'Faltan datos requeridos'}), 400
    
    if len(nueva_contrasena) < 8:
        return jsonify({'message': 'La contraseña debe tener al menos 8 caracteres'}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que el usuario existe y está aprobado
        cursor.execute(
            """SELECT id_usuario, nombre, aprobado, estado 
            FROM usuarios 
            WHERE cedula = %s""",
            (cedula,)
        )
        usuario = cursor.fetchone()
        
        if not usuario:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Cédula no registrada'}), 404
        
        if not usuario['aprobado'] or usuario['estado'] != 'activo':
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no activo. Contacte al coordinador'}), 403
        
        # Encriptar la nueva contraseña
        hashed = bcrypt.hashpw(nueva_contrasena.encode('utf-8'), bcrypt.gensalt())
        
        # Guardar contraseña pendiente y marcar solicitud
        cursor.execute(
            """UPDATE usuarios 
            SET solicitud_cambio_pwd = 1,
                contrasena_pendiente = %s,
                fecha_solicitud_cambio = NOW()
            WHERE cedula = %s""",
            (hashed.decode('utf-8'), cedula)
        )
        
        conn.commit()
        print(f" Solicitud registrada para: {usuario['nombre']}")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'message': 'Solicitud enviada. Espere aprobación del coordinador.',
            'nombre': usuario['nombre']
        }), 200
        
    except Exception as e:
        print(f" ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: APROBAR/RECHAZAR/CONGELAR CAMBIO DE CONTRASEÑA
# ============================================
@app.route('/api/usuarios/<int:id_usuario>/aprobar-cambio-pwd', methods=['PUT'])
@token_required
def aprobar_cambio_pwd(current_user_id, id_usuario):
    """Coordinador aprueba, rechaza o congela solicitud de cambio de contraseña"""
    print(f"\n[APROBAR CAMBIO PWD] Usuario {id_usuario} por coordinador {current_user_id}")
    
    data = request.get_json()
    accion = data.get('accion')  # 'aprobar', 'rechazar' o 'congelar'
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que es coordinador
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener usuario solicitante
        cursor.execute(
            """SELECT nombre, contrasena_pendiente 
            FROM usuarios 
            WHERE id_usuario = %s""",
            (id_usuario,)
        )
        user_data = cursor.fetchone()
        
        if not user_data:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no encontrado'}), 404
        
        if accion == 'aprobar':
            # APLICAR la contraseña pendiente
            cursor.execute(
                """UPDATE usuarios 
                SET contrasena = %s,
                    contrasena_pendiente = NULL,
                    solicitud_cambio_pwd = 0,
                    fecha_solicitud_cambio = NULL
                WHERE id_usuario = %s""",
                (user_data['contrasena_pendiente'], id_usuario)
            )
            mensaje = f"Cambio aprobado para {user_data['nombre']}"
            print(f"{mensaje}")
            
        elif accion == 'rechazar':
            # RECHAZAR solicitud
            cursor.execute(
                """UPDATE usuarios 
                SET contrasena_pendiente = NULL,
                    solicitud_cambio_pwd = 0,
                    fecha_solicitud_cambio = NULL
                WHERE id_usuario = %s""",
                (id_usuario,)
            )
            mensaje = f"Cambio rechazado para {user_data['nombre']}"
            print(f"{mensaje}")
            
        elif accion == 'congelar':
            # CONGELAR usuario (marcar como inactivo)
            cursor.execute(
                """UPDATE usuarios 
                SET aprobado = 0,
                    estado = 'congelado',
                    contrasena_pendiente = NULL,
                    solicitud_cambio_pwd = 0,
                    fecha_solicitud_cambio = NULL
                WHERE id_usuario = %s""",
                (id_usuario,)
            )
            mensaje = f"Usuario {user_data['nombre']} CONGELADO por seguridad"
            print(f"{mensaje}")
        
        else:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Acción inválida'}), 400
        
        conn.commit()
        
        cursor.close()
        conn.close()
        
        return jsonify({'message': mensaje}), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500
    

########################################## CONTRASEÑA 3 USUARIOS Y ACTUALIZAR DATOS ##########################################
# ============================================
# ENDPOINT: CAMBIAR CONTRASEÑA (DENTRO DE LA APP)
# ============================================
@app.route('/api/auth/cambiar-contrasena', methods=['PUT'])
@token_required
def cambiar_contrasena(current_user_id):
    """Usuario cambia su propia contraseña (requiere contraseña actual)"""
    print("\n[CAMBIAR CONTRASEÑA]")
    
    data = request.get_json()
    contrasena_actual = data.get('contrasena_actual')
    nueva_contrasena = data.get('nueva_contrasena')
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener usuario
        cursor.execute(
            "SELECT contrasena FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if not usuario:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no encontrado'}), 404
        
        # Verificar contraseña actual
        if not bcrypt.checkpw(contrasena_actual.encode('utf-8'), usuario['contrasena'].encode('utf-8')):
            cursor.close()
            conn.close()
            print("Contraseña actual incorrecta")
            return jsonify({'message': 'Contraseña actual incorrecta'}), 401
        
        # Verificar que la nueva contraseña sea diferente
        if bcrypt.checkpw(nueva_contrasena.encode('utf-8'), usuario['contrasena'].encode('utf-8')):
            cursor.close()
            conn.close()
            return jsonify({
                'message': 'La nueva contraseña debe ser diferente a la actual'
            }), 400
        
        # Validar nueva contraseña
        if len(nueva_contrasena) < 8:
            cursor.close()
            conn.close()
            return jsonify({'message': 'La contraseña debe tener al menos 8 caracteres'}), 400
        
        # Encriptar nueva contraseña
        hashed = bcrypt.hashpw(nueva_contrasena.encode('utf-8'), bcrypt.gensalt())
        
        # Actualizar contraseña
        cursor.execute(
            "UPDATE usuarios SET contrasena = %s WHERE id_usuario = %s",
            (hashed.decode('utf-8'), current_user_id)
        )
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"Contraseña actualizada para usuario ID: {current_user_id}")
        return jsonify({'message': 'Contraseña actualizada exitosamente'}), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500

# ============================================
# ENDPOINT: ACTUALIZAR DATOS PROPIOS
# ============================================
@app.route('/api/usuarios/actualizar-datos', methods=['PUT'])
@token_required
def actualizar_datos_propios(current_user_id):
    """Usuario actualiza su nombre y cédula"""
    print("\n[ACTUALIZAR DATOS PROPIOS]")
    
    try:
        data = request.get_json()
        nuevo_nombre = data.get('nombre')
        nueva_cedula = data.get('cedula')
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Validar que la cédula no esté en uso por otro usuario
        cursor.execute(
            "SELECT id_usuario FROM usuarios WHERE cedula = %s AND id_usuario != %s",
            (nueva_cedula, current_user_id)
        )
        
        if cursor.fetchone():
            cursor.close()
            conn.close()
            return jsonify({
                'message': 'Esta cédula ya está registrada por otro usuario'
            }), 400
        
        # Actualizar datos
        cursor.execute(
            """UPDATE usuarios 
               SET nombre = %s, cedula = %s 
               WHERE id_usuario = %s""",
            (nuevo_nombre, nueva_cedula, current_user_id)
        )
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"Datos actualizados para usuario {current_user_id}")
        return jsonify({
            'message': 'Datos actualizados correctamente'
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        return jsonify({'message': f'Error: {str(e)}'}), 500
    
# ============================================
# ENDPOINT: OBTENER DATOS DEL USUARIO ACTUAL
# ============================================
@app.route('/api/usuarios/me', methods=['GET'])
@token_required
def obtener_usuario_actual(current_user_id):
    """Obtiene datos del usuario logueado"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute("""
            SELECT nombre, cedula, rol
            FROM usuarios
            WHERE id_usuario = %s
        """, (current_user_id,))
        
        usuario = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if usuario:
            return jsonify(usuario), 200
        else:
            return jsonify({'message': 'Usuario no encontrado'}), 404
            
    except Exception as e:
        print(f"\n{'='*60}")
        print(f"ERROR EN /api/usuarios/me")
        print(f"User ID: {current_user_id}")
        print(f"Error: {e}")
        print(f"{'='*60}\n")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500

#####################################  GESTIÓN DE USUARIOS ############################################
# ============================================
# ENDPOINT: OBTENER USUARIOS PENDIENTES
# ============================================
@app.route('/api/usuarios/pendientes', methods=['GET'])
@token_required
def usuarios_pendientes(current_user_id):
    print(f"\n[PENDIENTES] Solicitud de usuario {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[PENDIENTES] Acceso denegado - Rol: {usuario['rol']}")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Filtrar solo pendientes (excluir eliminados)
        cursor.execute(
            """SELECT id_usuario, nombre, cedula, rol, fecha_registro 
            FROM usuarios 
            WHERE estado = 'pendiente' AND rol != 'coordinador'
            ORDER BY fecha_registro DESC"""
        )
        usuarios = cursor.fetchall()
        
        print(f"[PENDIENTES] {len(usuarios)} usuarios encontrados")
        
        cursor.close()
        conn.close()
        return jsonify(usuarios), 200
        
    except Exception as e:
        print(f"[PENDIENTES] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500

# ============================================
# ENDPOINT: APROBAR USUARIO
# ============================================
@app.route('/api/usuarios/<int:id_usuario>/aprobar', methods=['PUT'])
@token_required
def aprobar_usuario(current_user_id, id_usuario):
    print(f"\n[APROBAR] Usuario {id_usuario} por coordinador {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[APROBAR] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Aprobar y activar
        cursor.execute(
            "UPDATE usuarios SET aprobado = TRUE, estado = 'activo' WHERE id_usuario = %s",
            (id_usuario,)
        )
        
        conn.commit()
        print(f"[APROBAR] Usuario {id_usuario} aprobado exitosamente")
        
        cursor.close()
        conn.close()
        return jsonify({'message': 'Usuario aprobado'}), 200
        
    except Exception as e:
        print(f"[APROBAR] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: RECHAZAR USUARIO
# ============================================
@app.route('/api/usuarios/<int:id_usuario>/rechazar', methods=['PUT'])
@token_required
def rechazar_usuario(current_user_id, id_usuario):
    print(f"\n[RECHAZAR] Usuario {id_usuario} por coordinador {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[RECHAZAR] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Marcar como rechazado (sin fecha_rechazo)
        cursor.execute(
            "UPDATE usuarios SET estado = 'rechazado', aprobado = FALSE WHERE id_usuario = %s",
            (id_usuario,)
        )
        
        conn.commit()
        print(f"[RECHAZAR] Usuario {id_usuario} marcado como rechazado")
        
        cursor.close()
        conn.close()
        return jsonify({'message': 'Usuario rechazado'}), 200
        
    except Exception as e:
        print(f"[RECHAZAR] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: OBTENER USUARIOS RECHAZADOS
# ============================================
@app.route('/api/usuarios/rechazados', methods=['GET'])
@token_required
def usuarios_rechazados(current_user_id):
    print(f"\n[RECHAZADOS] Solicitud de usuario {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[RECHAZADOS] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener rechazados con días desde registro
        cursor.execute(
            """SELECT id_usuario, nombre, cedula, rol, fecha_registro, 
                      DATEDIFF(CURDATE(), fecha_registro) as dias_rechazado
            FROM usuarios 
            WHERE estado = 'rechazado' AND rol != 'coordinador'
            ORDER BY fecha_registro DESC"""
        )
        usuarios = cursor.fetchall()
        
        print(f"[RECHAZADOS] {len(usuarios)} usuarios encontrados")
        
        cursor.close()
        conn.close()
        return jsonify(usuarios), 200
        
    except Exception as e:
        print(f"[RECHAZADOS] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: APROBAR USUARIO RECHAZADO
# ============================================
@app.route('/api/usuarios/<int:id_usuario>/aprobar-rechazado', methods=['PUT'])
@token_required
def aprobar_rechazado(current_user_id, id_usuario):
    print(f"\n[APROBAR RECHAZADO] Usuario {id_usuario} por coordinador {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[APROBAR RECHAZADO] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Aprobar y activar (revertir rechazo)
        cursor.execute(
            "UPDATE usuarios SET estado = 'activo', aprobado = TRUE WHERE id_usuario = %s",
            (id_usuario,)
        )
        
        conn.commit()
        print(f"[APROBAR RECHAZADO] Usuario {id_usuario} aprobado (rechazo revertido)")
        
        cursor.close()
        conn.close()
        return jsonify({'message': 'Usuario aprobado'}), 200
        
    except Exception as e:
        print(f"[APROBAR RECHAZADO] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: VACIAR RECHAZADOS (>15 días desde registro)
# ============================================
@app.route('/api/usuarios/vaciar-rechazados', methods=['DELETE'])
@token_required
def vaciar_rechazados(current_user_id):
    print(f"\n[VACIAR RECHAZADOS] Solicitud de usuario {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener rechazados antiguos (>15 días)
        cursor.execute("""
            SELECT id_usuario, nombre 
            FROM usuarios 
            WHERE estado = 'rechazado' 
              AND DATEDIFF(CURDATE(), fecha_registro) > 15
        """)
        usuarios_a_procesar = cursor.fetchall()
        
        desactivados = 0
        eliminados = 0
        
        for usuario_row in usuarios_a_procesar:
            uid = usuario_row['id_usuario']
            
            # Verificar si tiene consumo
            cursor.execute("SELECT COUNT(*) as total FROM consumo WHERE id_usuario = %s", (uid,))
            tiene_consumo = cursor.fetchone()['total'] > 0
            
            if tiene_consumo:
                # Desactivar
                cursor.execute(
                    "UPDATE usuarios SET estado = 'inactivo', aprobado = 0 WHERE id_usuario = %s",
                    (uid,)
                )
                desactivados += 1
            else:
                # Eliminar
                cursor.execute("DELETE FROM preguntas_seguridad WHERE id_usuario = %s", (uid,))
                cursor.execute("DELETE FROM usuarios WHERE id_usuario = %s", (uid,))
                eliminados += 1
        
        conn.commit()
        cursor.close()
        conn.close()
        
        mensaje = f'{eliminados} eliminados, {desactivados} desactivados'
        print(f"[VACIAR RECHAZADOS] {mensaje}")
        
        return jsonify({
            'message': mensaje,
            'eliminados': eliminados,
            'desactivados': desactivados
        }), 200
        
    except Exception as e:
        print(f"[VACIAR RECHAZADOS] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500
    
# ============================================
# ENDPOINT: OBTENER USUARIOS ACTIVOS
# ============================================
@app.route('/api/usuarios/activos', methods=['GET'])
@token_required
def usuarios_activos(current_user_id):
    print(f"\n[ACTIVOS] Solicitud de usuario {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[ACTIVOS] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener activos
        cursor.execute(
            """SELECT id_usuario, nombre, cedula, rol, fecha_registro, estado
            FROM usuarios 
            WHERE aprobado = TRUE AND estado = 'activo' AND rol != 'coordinador'
            ORDER BY nombre ASC"""
        )
        usuarios = cursor.fetchall()
        
        print(f"[ACTIVOS] {len(usuarios)} usuarios encontrados")
        
        cursor.close()
        conn.close()
        return jsonify(usuarios), 200
        
    except Exception as e:
        print(f"[ACTIVOS] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: DESACTIVAR USUARIO
# ============================================
@app.route('/api/usuarios/<int:id_usuario>/desactivar', methods=['PUT'])
@token_required
def desactivar_usuario(current_user_id, id_usuario):
    print(f"\n[DESACTIVAR] Usuario {id_usuario} por coordinador {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[DESACTIVAR] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # No puede desactivarse a sí mismo
        if current_user_id == id_usuario:
            print(f"[DESACTIVAR] Intento de auto-desactivación")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No puedes desactivarte a ti mismo'}), 400
        
        # Desactivar
        cursor.execute("UPDATE usuarios SET estado = 'inactivo' WHERE id_usuario = %s", (id_usuario,))
        
        conn.commit()
        print(f"[DESACTIVAR] Usuario {id_usuario} desactivado exitosamente")
        
        cursor.close()
        conn.close()
        return jsonify({'message': 'Usuario desactivado'}), 200
        
    except Exception as e:
        print(f"[DESACTIVAR] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: EDITAR ROL DE USUARIO
# ============================================
@app.route('/api/usuarios/<int:id_usuario>/editar-rol', methods=['PUT'])
@token_required
def editar_rol_usuario(current_user_id, id_usuario):
    print(f"\n[EDITAR ROL] Usuario {id_usuario} por coordinador {current_user_id}")
    try:
        data = request.get_json()
        nuevo_rol = data.get('rol')
        
        # Validar rol
        if nuevo_rol not in ['docente', 'limpieza']:
            print(f"[EDITAR ROL] Rol inválido: {nuevo_rol}")
            return jsonify({'message': 'Rol inválido. Use "docente" o "limpieza"'}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[EDITAR ROL] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # No puede cambiar su propio rol
        if current_user_id == id_usuario:
            print(f"[EDITAR ROL] Intento de cambiar su propio rol")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No puedes cambiar tu propio rol'}), 400
        
        # Obtener usuario target
        cursor.execute("SELECT nombre, rol FROM usuarios WHERE id_usuario = %s", (id_usuario,))
        usuario_target = cursor.fetchone()
        
        if not usuario_target:
            print(f"[EDITAR ROL] Usuario {id_usuario} no encontrado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no encontrado'}), 404
        
        # No puede cambiar rol de coordinador
        if usuario_target['rol'] == 'coordinador':
            print(f"[EDITAR ROL] Intento de cambiar rol de coordinador")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No se puede cambiar el rol de un coordinador'}), 403
        
        # Actualizar rol
        cursor.execute("UPDATE usuarios SET rol = %s WHERE id_usuario = %s", (nuevo_rol, id_usuario))
        
        conn.commit()
        print(f"[EDITAR ROL] '{usuario_target['nombre']}': {usuario_target['rol']} → {nuevo_rol}")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'message': f'Rol actualizado a {nuevo_rol}',
            'usuario': usuario_target['nombre'],
            'rol_anterior': usuario_target['rol'],
            'rol_nuevo': nuevo_rol
        }), 200
        
    except Exception as e:
        print(f"[EDITAR ROL] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: OBTENER USUARIOS INACTIVOS
# ============================================
@app.route('/api/usuarios/inactivos', methods=['GET'])
@token_required
def usuarios_inactivos(current_user_id):
    print(f"\n[INACTIVOS] Solicitud de usuario {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[INACTIVOS] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener inactivos
        cursor.execute(
            """SELECT id_usuario, nombre, cedula, rol, fecha_registro, estado
            FROM usuarios 
            WHERE estado = 'inactivo' AND rol != 'coordinador'
            ORDER BY nombre ASC"""
        )
        usuarios = cursor.fetchall()
        
        print(f"[INACTIVOS] {len(usuarios)} usuarios encontrados")
        
        cursor.close()
        conn.close()
        return jsonify(usuarios), 200
        
    except Exception as e:
        print(f"[INACTIVOS] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: REACTIVAR USUARIO
# ============================================
@app.route('/api/usuarios/<int:id_usuario>/reactivar', methods=['PUT'])
@token_required
def reactivar_usuario(current_user_id, id_usuario):
    print(f"\n[REACTIVAR] Usuario {id_usuario} por coordinador {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            print(f"[REACTIVAR] Acceso denegado")
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Reactivar
        cursor.execute(
            "UPDATE usuarios SET estado = 'activo', aprobado = TRUE WHERE id_usuario = %s",
            (id_usuario,)
        )
        
        conn.commit()
        print(f"[REACTIVAR] Usuario {id_usuario} reactivado exitosamente")
        
        cursor.close()
        conn.close()
        return jsonify({'message': 'Usuario reactivado'}), 200
        
    except Exception as e:
        print(f"[REACTIVAR] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: VACIAR INACTIVOS
# ============================================
@app.route('/api/usuarios/vaciar-inactivos', methods=['DELETE'])
@token_required
def vaciar_inactivos(current_user_id):
    print(f"\n[VACIAR INACTIVOS] Solicitud de usuario {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener inactivos
        cursor.execute("SELECT id_usuario FROM usuarios WHERE estado = 'inactivo'")
        usuarios_a_procesar = cursor.fetchall()
        
        eliminados = 0
        
        for usuario_row in usuarios_a_procesar:
            uid = usuario_row['id_usuario']
            
            # Verificar si tiene consumo
            cursor.execute("SELECT COUNT(*) as total FROM consumo WHERE id_usuario = %s", (uid,))
            tiene_consumo = cursor.fetchone()['total'] > 0
            
            if not tiene_consumo:
                # Solo eliminar si NO tiene consumo
                cursor.execute("DELETE FROM preguntas_seguridad WHERE id_usuario = %s", (uid,))
                cursor.execute("DELETE FROM usuarios WHERE id_usuario = %s", (uid,))
                eliminados += 1
        
        conn.commit()
        cursor.close()
        conn.close()
        
        mensaje = f'{eliminados} usuarios eliminados (sin historial)'
        print(f"[VACIAR INACTIVOS] {mensaje}")
        
        return jsonify({
            'message': mensaje,
            'eliminados': eliminados
        }), 200
        
    except Exception as e:
        print(f"[VACIAR INACTIVOS] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500
    
# ============================================
# ENDPOINT: ELIMINAR USUARIO PERMANENTEMENTE
# ============================================
@app.route('/api/usuarios/<int:id_usuario>/eliminar-permanente', methods=['DELETE'])
@token_required
def eliminar_permanente(current_user_id, id_usuario):
    """
    LÓGICA INTELIGENTE:
    - Si tiene registros de consumo → Solo DESACTIVAR
    - Si NO tiene consumo → ELIMINAR de BD
    """
    print(f"\n[ELIMINAR USUARIO] Usuario {id_usuario} por coordinador {current_user_id}")
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar permisos
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if not usuario or usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # No puede eliminarse a sí mismo
        if current_user_id == id_usuario:
            cursor.close()
            conn.close()
            return jsonify({'message': 'No puedes eliminarte a ti mismo'}), 400
        
        # Obtener datos del usuario
        cursor.execute("SELECT nombre, estado FROM usuarios WHERE id_usuario = %s", (id_usuario,))
        usuario_target = cursor.fetchone()
        
        if not usuario_target:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no encontrado'}), 404
        
        # VERIFICAR SI TIENE REGISTROS DE CONSUMO
        cursor.execute(
            "SELECT COUNT(*) as total FROM consumo WHERE id_usuario = %s",
            (id_usuario,)
        )
        resultado_consumo = cursor.fetchone()
        tiene_consumo = resultado_consumo['total'] > 0
        
        print(f"Usuario '{usuario_target['nombre']}' tiene {resultado_consumo['total']} registros de consumo")

        if tiene_consumo:
            # CASO 1: TIENE CONSUMO → BORRAR usuario 
            print(f"→ Eliminando usuario (consumo mantiene nombre)")
            cursor.execute(
                "DELETE FROM usuarios WHERE id_usuario = %s",
                (id_usuario,)
            )
            conn.commit()
    
            cursor.close()
            conn.close()
    
            return jsonify({
                'message': f'Usuario marcado como eliminado (mantiene historial de {resultado_consumo["total"]} registros)',
                'accion': 'eliminado',  # ← Cambiar de 'desactivado' a 'eliminado'
                'tiene_historial': True,
                'registros_consumo': resultado_consumo['total']
            }), 200
            
        else:
            # CASO 2: NO TIENE CONSUMO → Eliminar de BD
            print(f"→ Eliminando usuario permanentemente (sin historial)")
            
            # Eliminar preguntas de seguridad si existen
            cursor.execute("DELETE FROM preguntas_seguridad WHERE id_usuario = %s", (id_usuario,))
            preguntas_eliminadas = cursor.rowcount
            
            # Eliminar usuario
            cursor.execute("DELETE FROM usuarios WHERE id_usuario = %s", (id_usuario,))
            
            conn.commit()
            
            cursor.close()
            conn.close()
            
            return jsonify({
                'message': 'Usuario eliminado permanentemente',
                'accion': 'eliminado',
                'tiene_historial': False
            }), 200
        
    except Exception as e:
        print(f"[ELIMINAR USUARIO] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500
    
################################### LUCES ########################################
# ============================================
# ENDPOINT: OBTENER ESTADO ACTUAL DE LAS LUCES
# ============================================
@app.route('/api/luces/estado', methods=['GET'])
@token_required
def obtener_estado_luces(current_user_id):
    """
    Obtiene el estado actual de las luces leyendo GPIO
    Sincroniza con BD si hay diferencias
    """
    print("\n" + "="*60)
    print("SOLICITUD: Obtener estado de luces")
    print("="*60)
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # LEER ESTADO REAL DE GPIO
        estado_gpio1 = not RELAY_GRUPO1.value
        estado_gpio2 = not RELAY_GRUPO2.value
        
        print(f"GPIO - Grupo 1: {'ON' if estado_gpio1 else 'OFF'}")
        print(f"GPIO - Grupo 2: {'ON' if estado_gpio2 else 'OFF'}")
        
        # Verificar estado en BD
        cursor.execute("""
            SELECT grupo_luces FROM consumo 
            WHERE dato_apagado IS NULL
        """)
        registros_bd = cursor.fetchall()
        grupo1_bd = any(r['grupo_luces'] == 'Grupo 1' for r in registros_bd)
        grupo2_bd = any(r['grupo_luces'] == 'Grupo 2' for r in registros_bd)
        
        print(f"BD - Grupo 1: {'ON' if grupo1_bd else 'OFF'}")
        print(f"BD - Grupo 2: {'ON' if grupo2_bd else 'OFF'}")
        
        # SINCRONIZAR GRUPO 1 si hay diferencias
        if estado_gpio1 != grupo1_bd:
            print(f"DESINCRONIZACIÓN Grupo 1: GPIO={estado_gpio1}, BD={grupo1_bd}")
            
            if estado_gpio1 and not grupo1_bd:
                # GPIO ON pero BD dice OFF → Crear registro "desconocido"
                print("Creando registro de encendido desconocido...")
                cursor.execute("SELECT nombre FROM usuarios WHERE id_usuario = %s", (current_user_id,))
                usuario_info = cursor.fetchone()
                nombre_usuario = usuario_info['nombre'] if usuario_info else 'Usuario desconocido'

                cursor.execute("""
                    INSERT INTO consumo 
                    (id_usuario, nombre_usuario, grupo_luces, dato_encendido, metodo_encendido, estado, tipo_dia)
                    VALUES (%s, %s, 'Grupo 1', NOW(), 'Interruptor manual', 'encendido',
                            CASE DAYOFWEEK(NOW())
                                WHEN 1 THEN 'Domingo'
                                WHEN 2 THEN 'Lunes'
                                WHEN 3 THEN 'Martes'
                                WHEN 4 THEN 'Miércoles'
                                WHEN 5 THEN 'Jueves'
                                WHEN 6 THEN 'Viernes'
                                WHEN 7 THEN 'Sábado'
                            END)
                """, (current_user_id, nombre_usuario))
                
            elif not estado_gpio1 and grupo1_bd:
                # GPIO OFF pero BD dice ON → Cerrar registro
                print("Cerrando registro de apagado desconocido...")
                cursor.execute("""
                    UPDATE consumo 
                    SET dato_apagado = NOW(), 
                        metodo_apagado = 'Interruptor manual',
                        estado = 'apagado',
                        encendido_segundos = TIMESTAMPDIFF(SECOND, dato_encendido, NOW()),
                        consumo_kW = (TIMESTAMPDIFF(SECOND, dato_encendido, NOW()) * 324) / 3600000.0
                    WHERE grupo_luces = 'Grupo 1' AND dato_apagado IS NULL
                """)
        
        # SINCRONIZAR GRUPO 2 si hay diferencias
        if estado_gpio2 != grupo2_bd:
            print(f"DESINCRONIZACIÓN Grupo 2: GPIO={estado_gpio2}, BD={grupo2_bd}")
            
            if estado_gpio2 and not grupo2_bd:
                # GPIO ON pero BD dice OFF → Crear registro "desconocido"
                print("Creando registro de encendido desconocido...")
                cursor.execute("SELECT nombre FROM usuarios WHERE id_usuario = %s", (current_user_id,))
                usuario_info = cursor.fetchone()
                nombre_usuario = usuario_info['nombre'] if usuario_info else 'Usuario desconocido'

                cursor.execute("""
                    INSERT INTO consumo 
                    (id_usuario, nombre_usuario, grupo_luces, dato_encendido, metodo_encendido, estado, tipo_dia)
                    VALUES (%s, %s, 'Grupo 2', NOW(), 'Interruptor manual', 'encendido',
                            CASE DAYOFWEEK(NOW())
                                WHEN 1 THEN 'Domingo'
                                WHEN 2 THEN 'Lunes'
                                WHEN 3 THEN 'Martes'
                                WHEN 4 THEN 'Miércoles'
                                WHEN 5 THEN 'Jueves'
                                WHEN 6 THEN 'Viernes'
                                WHEN 7 THEN 'Sábado'
                            END)
                """, (current_user_id, nombre_usuario))

            elif not estado_gpio2 and grupo2_bd:
                # GPIO OFF pero BD dice ON → Cerrar registro
                print("Cerrando registro de apagado desconocido...")
                cursor.execute("""
                    UPDATE consumo 
                    SET dato_apagado = NOW(), 
                        metodo_apagado = 'Interruptor manual',
                        estado = 'apagado',
                        encendido_segundos = TIMESTAMPDIFF(SECOND, dato_encendido, NOW()),
                        consumo_kW = (TIMESTAMPDIFF(SECOND, dato_encendido, NOW()) * 324) / 3600000.0
                    WHERE grupo_luces = 'Grupo 2' AND dato_apagado IS NULL
                """)
        
        conn.commit()
        
        sincronizado = (estado_gpio1 == grupo1_bd) and (estado_gpio2 == grupo2_bd)
        print(f"Estado sincronizado: {sincronizado}")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'grupo1': estado_gpio1,
            'grupo2': estado_gpio2,
            'watts_grupo1': 324 if estado_gpio1 else 0,
            'watts_grupo2': 324 if estado_gpio2 else 0,
            'sincronizado': sincronizado
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500

# ============================================
# ENDPOINT: OBTENER ADVERTENCIAS
# ============================================
@app.route('/api/luces/advertencias', methods=['GET'])
@token_required
def obtener_advertencias(current_user_id):
    """
    Verifica si hay luces encendidas fuera de horario
    Retorna advertencia si están por apagarse
    """
    try:
        if not ES_RASPBERRY:
            return jsonify({'advertencia': False}), 200
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener día y hora actual
        ahora = datetime.now()
        dia_semana = ahora.strftime('%A')
        
        dias_map = {
            'Monday': 'Lunes',
            'Tuesday': 'Martes',
            'Wednesday': 'Miércoles',
            'Thursday': 'Jueves',
            'Friday': 'Viernes',
            'Saturday': 'Sábado',
            'Sunday': 'Domingo'
        }
        dia_actual = dias_map.get(dia_semana, dia_semana)
        hora_actual = ahora.time()
        
        # Buscar jornada del día
        cursor.execute("""
            SELECT hora_inicio_matutina, hora_fin_matutina,
                   hora_inicio_vespertina, hora_fin_vespertina
            FROM jornadas
            WHERE dia_semana = %s AND activo = 1
        """, (dia_actual,))
        
        jornada = cursor.fetchone()
        
        # Convertir timedelta a time si es necesario
        if jornada:
            for key in ['hora_inicio_matutina', 'hora_fin_matutina', 
                        'hora_inicio_vespertina', 'hora_fin_vespertina']:
                if jornada.get(key) and isinstance(jornada[key], timedelta):
                    jornada[key] = (datetime.min + jornada[key]).time()

        # Verificar si estamos en horario
        en_horario = False
        
        if jornada:
            if jornada['hora_inicio_matutina'] and jornada['hora_fin_matutina']:
                if jornada['hora_inicio_matutina'] <= hora_actual <= jornada['hora_fin_matutina']:
                    en_horario = True
            
            if jornada['hora_inicio_vespertina'] and jornada['hora_fin_vespertina']:
                if jornada['hora_inicio_vespertina'] <= hora_actual <= jornada['hora_fin_vespertina']:
                    en_horario = True
        
        # Si estamos FUERA de horario, verificar luces encendidas
        if not en_horario:
            cursor.execute("""
                SELECT grupo_luces,
                       TIMESTAMPDIFF(MINUTE, dato_encendido, NOW()) as minutos_encendidos
                FROM consumo
                WHERE dato_apagado IS NULL
            """)
            
            registros = cursor.fetchall()
            
            for registro in registros:
                minutos = registro['minutos_encendidos']
                
                # Advertencia entre 28-29 minutos
                if 28 <= minutos < 30:
                    minutos_restantes = 30 - minutos
                    cursor.close()
                    conn.close()
                    return jsonify({
                        'advertencia': True,
                        'mensaje': f'Consumo fuera de horario. Las luces se apagarán en {minutos_restantes} minutos',
                        'minutos_restantes': minutos_restantes,
                        'grupo': registro['grupo_luces']
                    }), 200
        
        cursor.close()
        conn.close()
        
        return jsonify({'advertencia': False}), 200
        
    except Exception as e:
        print(f"Error obteniendo advertencias: {e}")
        return jsonify({'advertencia': False}), 200

# ============================================
# ENDPOINT: ENCENDER LUCES
# ============================================
@app.route('/api/luces/encender', methods=['POST'])
@token_required
def encender_luces(current_user_id):
    """
    Enciende un grupo de luces (1 o 2)
    Registra en consumo y activa GPIO
    """
    print("\n" + "="*60)
    print("SOLICITUD: ENCENDER LUCES")
    print("="*60)
    
    try:
        data = request.get_json()
        grupo = data.get('grupo')  # 1 o 2
        metodo = data.get('metodo', 'Aplicación')
        
        if grupo not in [1, 2]:
            return jsonify({'message': 'Grupo inválido. Use 1 o 2'}), 400
        
        grupo_nombre = f'Grupo {grupo}'
        print(f"Grupo solicitado: {grupo_nombre}")
        print(f"Usuario ID: {current_user_id}")
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener nombre del usuario
        cursor.execute(
            "SELECT nombre FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if not usuario:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no encontrado'}), 404
        
        # Verificar si ya está encendido en BD
        cursor.execute(
            """SELECT id_consumo FROM consumo 
            WHERE grupo_luces = %s 
              AND dato_apagado IS NULL
            LIMIT 1""",
            (grupo_nombre,)
        )
        registro_abierto = cursor.fetchone()
        
        if registro_abierto:
            print(f"{grupo_nombre} ya está encendido en BD")
            cursor.close()
            conn.close()
            return jsonify({
                'message': f'{grupo_nombre} ya está encendido',
                'grupo': grupo,
                'estado': 'encendido'
            }), 200
        
        # Crear registro de encendido en BD
        cursor.execute("SELECT nombre FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario_info = cursor.fetchone()
        nombre_usuario = usuario_info['nombre'] if usuario_info else 'Usuario desconocido'

        cursor.execute(
            """INSERT INTO consumo 
            (id_usuario, nombre_usuario, grupo_luces, dato_encendido, metodo_encendido, estado, tipo_dia) 
            VALUES (%s, %s, %s, NOW(), %s, 'encendido', 
                CASE DAYOFWEEK(NOW())
                    WHEN 1 THEN 'Domingo'
                    WHEN 2 THEN 'Lunes'
                    WHEN 3 THEN 'Martes'
                    WHEN 4 THEN 'Miércoles'
                    WHEN 5 THEN 'Jueves'
                    WHEN 6 THEN 'Viernes'
                    WHEN 7 THEN 'Sábado'
                END
            )""",
            (current_user_id, nombre_usuario, grupo_nombre, metodo)
        )
        
        conn.commit()

        # ACTIVAR GPIO FÍSICAMENTE
        if grupo == 1:
            RELAY_GRUPO1.off()  # Con active_high=True, .off() ENCIENDE
            print("GPIO23 activado - Grupo 1 encendido")
        elif grupo == 2:
            RELAY_GRUPO2.off()  # Con active_high=True, .off() ENCIENDE
            print("GPIO24 activado - Grupo 2 encendido")
        
        print(f"{grupo_nombre} ENCENDIDO por {usuario['nombre']}")
        
        cursor.close()
        conn.close()

        return jsonify({
            'message': f'{grupo_nombre} encendido correctamente',
            'grupo': grupo,
            'estado': 'encendido',
            'usuario': usuario['nombre']
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: APAGAR LUCES
# ============================================
@app.route('/api/luces/apagar', methods=['POST'])
@token_required
def apagar_luces(current_user_id):
    """
    Apaga un grupo de luces (1, 2, o 'todos')
    Actualiza registro con dato_apagado, calcula consumo y desactiva 
    
    Cálculo consumo:
    - Grupo 1: 9 tubos × 36W = 324W
    - Grupo 2: 9 tubos × 36W = 324W
    """
    print("\n" + "="*60)
    print("SOLICITUD: APAGAR LUCES")
    print("="*60)
    
    try:
        data = request.get_json()
        grupo = data.get('grupo')  # 1, 2, o 'todos'
        
        if grupo not in [1, 2, 'todos']:
            return jsonify({'message': 'Grupo inválido. Use 1, 2 o "todos"'}), 400
        
        print(f"Solicitud: {grupo}")
        print(f"Usuario ID: {current_user_id}")
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener nombre del usuario
        cursor.execute(
            "SELECT nombre FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if not usuario:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no encontrado'}), 404
        
        # Determinar qué grupos apagar
        grupos_a_apagar = []
        if grupo == 'todos':
            grupos_a_apagar = ['Grupo 1', 'Grupo 2']
            print("Apagando TODOS los grupos")
        else:
            grupos_a_apagar = [f'Grupo {grupo}']
        
        registros_actualizados = 0
        
        # Apagar cada grupo EN BD
        for grupo_nombre in grupos_a_apagar:
            # Buscar registro abierto (encendido sin apagar)
            cursor.execute(
                """SELECT id_consumo, dato_encendido 
                FROM consumo 
                WHERE grupo_luces = %s 
                  AND dato_apagado IS NULL
                LIMIT 1""",
                (grupo_nombre,)
            )
            registro = cursor.fetchone()
            
            if registro:
                # Calcular watts según grupo (9 tubos × 36W = 324W por grupo)
                watts = 324
                
                # Actualizar con dato de apagado y calcular consumo
                cursor.execute(
                    """UPDATE consumo 
                    SET dato_apagado = NOW(),
                        metodo_apagado = %s,
                        estado = 'apagado',
                        encendido_segundos = TIMESTAMPDIFF(SECOND, dato_encendido, NOW()),
                        consumo_kW = (TIMESTAMPDIFF(SECOND, dato_encendido, NOW()) * %s) / 3600000.0
                    WHERE id_consumo = %s""",
                    (data.get('metodo_apagado', 'Aplicación'), watts, registro['id_consumo'])
                )
                registros_actualizados += 1
                print(f"{grupo_nombre} actualizado en BD (Registro {registro['id_consumo']})")
            else:
                print(f"{grupo_nombre} ya estaba apagado en BD")
        
        conn.commit()
        
        # DESACTIVAR GPIO 
        if grupo == 1:
            RELAY_GRUPO1.on()  # Con active_high=True, .on() APAGA
            print("GPIO23 desactivado - Grupo 1 apagado")
        elif grupo == 2:
            RELAY_GRUPO2.on()  # Con active_high=True, .on() APAGA
            print("GPIO24 desactivado - Grupo 2 apagado")
        elif grupo == 'todos': 
            RELAY_GRUPO1.on()  # Apaga Grupo 1
            RELAY_GRUPO2.on()  # Apaga Grupo 2
            print("GPIO23 desactivado - Grupo 1 apagado")
            print("GPIO24 desactivado - Grupo 2 apagado")
        
        print(f"{registros_actualizados} registro(s) actualizado(s) por {usuario['nombre']}")
        
        cursor.close()
        conn.close()
        
        if registros_actualizados == 0:
            mensaje = 'Las luces ya estaban apagadas'
        else:
            mensaje = 'Todas las luces apagadas' if grupo == 'todos' else f'Grupo {grupo} apagado correctamente'

        return jsonify({
            'message': mensaje,
            'grupo': grupo,
            'estado': 'apagado',
            'usuario': usuario['nombre'],
            'registros_actualizados': registros_actualizados
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


#################################### CONSUMO ENERGÉTICO ####################################
# ============================================
# ENDPOINT: CONSUMO ACTUAL
# ============================================
@app.route('/api/consumo/actual', methods=['GET'])
@token_required
def consumo_actual(current_user_id):
    """
    Obtiene el consumo actual en tiempo real
    - Watts actuales
    - Cuántos grupos encendidos
    - Cuántos tubos encendidos
    """
    print("\n" + "="*60)
    print("SOLICITUD: Consumo actual")
    print("="*60)
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Contar grupos encendidos (registros con dato_apagado NULL)
        cursor.execute(
            """SELECT COUNT(*) as grupos_encendidos
            FROM consumo 
            WHERE dato_apagado IS NULL"""
        )
        resultado = cursor.fetchone()
        grupos_encendidos = resultado['grupos_encendidos']
        
        # Calcular consumo actual
        # Grupo 1: 9 tubos × 36W = 324W
        # Grupo 2: 9 tubos × 36W = 324W
        watts_por_grupo = 324
        watts_actual = grupos_encendidos * watts_por_grupo
        tubos_encendidos = grupos_encendidos * 9
        
        
        print(f" Grupos encendidos: {grupos_encendidos}")
        print(f" Consumo actual: {watts_actual} W")
        print(f" Tubos encendidos: {tubos_encendidos}")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'watts': watts_actual,
            'grupos_encendidos': grupos_encendidos,
            'tubos_encendidos': tubos_encendidos,
            'kwh_estimado_hora': round(watts_actual / 1000, 3)  # kWh si sigue así 1 hora
        }), 200
        
    except Exception as e:
        print(f" ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: CONSUMO DE HOY
# ============================================
@app.route('/api/consumo/hoy', methods=['GET'])
@token_required
def consumo_hoy(current_user_id):
    """Obtiene estadísticas del día actual"""
    print("\n" + "="*60)
    print("SOLICITUD: Consumo de hoy")
    print("="*60)
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute(
            """SELECT 
                COUNT(*) as usos_hoy,
                COALESCE(SUM(encendido_segundos), 0) as segundos_totales,
                COALESCE(SUM(consumo_kW), 0) as kwh_total
            FROM consumo 
            WHERE DATE(dato_encendido) = CURDATE()
              AND dato_apagado IS NOT NULL"""
        )
        stats = cursor.fetchone()
        
        # Convertir a tipos correctos
        kwh_total = float(stats['kwh_total']) if stats['kwh_total'] else 0.0
        segundos_totales = int(stats['segundos_totales']) if stats['segundos_totales'] else 0
        usos_hoy = int(stats['usos_hoy']) if stats['usos_hoy'] else 0
        
        # Calcular costo
        costo_kwh = 0.13
        costo_total = kwh_total * costo_kwh
        
        print(f"Usos hoy: {usos_hoy}")
        print(f"kWh totales: {kwh_total}")
        print(f"Costo: ${costo_total:.2f}")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'usos_hoy': usos_hoy,
            'segundos_totales': segundos_totales,
            'minutos_totales': round(segundos_totales / 60, 1),
            'horas_totales': round(segundos_totales / 3600, 2),
            'kwh_total': round(kwh_total, 2),
            'costo_usd': round(costo_total, 2)
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: CONSUMO SEMANAL
# ============================================
@app.route('/api/consumo/semana', methods=['GET'])
@token_required
def consumo_semana(current_user_id):
    """Obtiene estadísticas de la semana actual"""
    print("\n" + "="*60)
    print("SOLICITUD: Consumo semanal")
    print("="*60)
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute(
            """SELECT 
                COALESCE(SUM(consumo_kW), 0) as kwh_total,
                COUNT(*) as usos_totales
            FROM consumo 
            WHERE YEARWEEK(dato_encendido, 1) = YEARWEEK(CURDATE(), 1)
              AND dato_apagado IS NOT NULL"""
        )
        stats = cursor.fetchone()
        
        # PRIMERO: Convertir a float
        kwh_total = float(stats['kwh_total']) if stats['kwh_total'] else 0.0
        usos_totales = int(stats['usos_totales']) if stats['usos_totales'] else 0
        
        # DESPUÉS: Calcular costo
        costo_kwh = 0.13
        costo_total = kwh_total * costo_kwh
        
        print(f" kWh esta semana: {kwh_total}")
        print(f" Costo: ${costo_total:.2f}")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'kwh_total': round(kwh_total, 2),
            'costo_usd': round(costo_total, 2),
            'usos_totales': usos_totales
        }), 200
        
    except Exception as e:
        print(f" ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: HISTÓRICO PARA GRÁFICA
# ============================================
@app.route('/api/consumo/historico', methods=['GET'])
@token_required
def consumo_historico(current_user_id):
    """
    Obtiene datos para la gráfica de consumo
    - Últimas 24 horas
    - Agrupado por hora
    """
    print("\n" + "="*60)
    print("SOLICITUD: Consumo histórico")
    print("="*60)
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Consumo por hora (últimas 24 horas)
        cursor.execute(
            """SELECT 
                HOUR(dato_encendido) as hora,
                COALESCE(SUM(consumo_kW), 0) as kwh_total,
                COUNT(*) as usos
            FROM consumo 
            WHERE dato_encendido >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
              AND dato_apagado IS NOT NULL
            GROUP BY HOUR(dato_encendido)
            ORDER BY hora ASC"""
        )
        datos = cursor.fetchall()
        
        # Convertir a formato para gráfica
        grafica = []
        for dato in datos:
            grafica.append({
                'hora': dato['hora'],
                'kwh': round(dato['kwh_total'], 3),
                'usos': dato['usos']
            })
        
        print(f" {len(grafica)} puntos de datos")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'datos': grafica,
            'total_puntos': len(grafica)
        }), 200
        
    except Exception as e:
        print(f" ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: COMPARACIÓN CON SEMANA ANTERIOR
# ============================================
@app.route('/api/consumo/comparacion', methods=['GET'])
@token_required
def consumo_comparacion(current_user_id):
    """
    Compara consumo de esta semana vs semana anterior
    Para mostrar % de ahorro
    """
    print("\n" + "="*60)
    print("SOLICITUD: Comparación semanal")
    print("="*60)
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Semana actual
        cursor.execute(
            """SELECT COALESCE(SUM(consumo_kW), 0) as kwh_total
            FROM consumo 
            WHERE YEARWEEK(dato_encendido, 1) = YEARWEEK(CURDATE(), 1)
              AND dato_apagado IS NOT NULL"""
        )
        semana_actual = cursor.fetchone()['kwh_total']
        
        # Semana anterior
        cursor.execute(
            """SELECT COALESCE(SUM(consumo_kW), 0) as kwh_total
            FROM consumo 
            WHERE YEARWEEK(dato_encendido, 1) = YEARWEEK(DATE_SUB(CURDATE(), INTERVAL 1 WEEK), 1)
              AND dato_apagado IS NOT NULL"""
        )
        semana_anterior = cursor.fetchone()['kwh_total']
        
        # Calcular porcentaje de cambio
        if semana_anterior > 0:
            cambio_porcentaje = ((semana_actual - semana_anterior) / semana_anterior) * 100
        else:
            cambio_porcentaje = 0
        
        es_ahorro = cambio_porcentaje < 0
        
        print(f" Semana actual: {semana_actual} kWh")
        print(f" Semana anterior: {semana_anterior} kWh")
        print(f" Cambio: {cambio_porcentaje:.1f}%")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'semana_actual_kwh': round(semana_actual, 2),
            'semana_anterior_kwh': round(semana_anterior, 2),
            'cambio_porcentaje': round(cambio_porcentaje, 1),
            'es_ahorro': es_ahorro,
            'mensaje': f"{'Ahorro' if es_ahorro else 'Aumento'} del {abs(round(cambio_porcentaje, 1))}% vs semana anterior"
        }), 200
        
    except Exception as e:
        print(f" ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500

# ============================================
# ENDPOINT: ADVERTENCIA CONSUMO EXCESIVO
# ============================================
@app.route('/api/consumo/advertencia-alto', methods=['GET'])
@token_required
def advertencia_consumo_alto(current_user_id):
    """
    Verifica si hay luces encendidas por más de 3 horas
    """
    try:
        if not ES_RASPBERRY:
            return jsonify({'advertencia': False}), 200
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Buscar luces encendidas actualmente
        cursor.execute("""
            SELECT 
                grupo_luces,
                dato_encendido,
                TIMESTAMPDIFF(HOUR, dato_encendido, NOW()) as horas_encendidas,
                TIMESTAMPDIFF(MINUTE, dato_encendido, NOW()) as minutos_encendidos
            FROM consumo
            WHERE dato_apagado IS NULL
        """)
        
        registros = cursor.fetchall()
        cursor.close()
        conn.close()
        
        # Verificar si algún grupo lleva >3 horas (180 minutos)
        for registro in registros:
            minutos = registro['minutos_encendidos']
            horas = registro['horas_encendidas']
            
            if minutos >= 180:  # 3 horas = 180 minutos
                return jsonify({
                    'advertencia': True,
                    'mensaje': f'Consumo excesivo detectado. Las luces del {registro["grupo_luces"]} llevan {horas} horas encendidas',
                    'horas': horas,
                    'minutos': minutos,
                    'grupo': registro['grupo_luces']
                }), 200
        
        return jsonify({'advertencia': False}), 200
        
    except Exception as e:
        print(f"Error verificando advertencia: {e}")
        return jsonify({'advertencia': False}), 200

############################################## REPORTES DE CONSUMO ##############################################
# ============================================
# ENDPOINT: LISTAR REPORTES DE CONSUMO
# ============================================
@app.route('/api/reportes', methods=['GET'])
@token_required
def listar_reportes(current_user_id):
    """Obtiene lista de reportes generados (ordenados por más reciente)"""
    print("\n[LISTAR REPORTES]")
    
    try:
        # Verificar que es coordinador PRIMERO
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute(
            "SELECT rol FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener período (si viene)
        periodo = request.args.get('periodo')
        
        # Consultar reportes
        if periodo:
            cursor.execute("""
                SELECT 
                    id_reporte, fecha_inicio, fecha_fin, periodo,
                    total_consumo_kWh, total_horas_uso, promedio_diario_kWh,
                    descripcion, archivo_pdf, fecha_generacion
                FROM reportes_consumo
                WHERE periodo = %s
                ORDER BY fecha_generacion DESC
            """, (periodo,))
        else:
            cursor.execute("""
                SELECT 
                    id_reporte, fecha_inicio, fecha_fin, periodo,
                    total_consumo_kWh, total_horas_uso, promedio_diario_kWh,
                    descripcion, archivo_pdf, fecha_generacion
                FROM reportes_consumo
                ORDER BY fecha_generacion DESC
            """)
        
        reportes = cursor.fetchall()
        
        cursor.close()
        conn.close()
        
        # Formatear fechas
        for reporte in reportes:
            reporte['fecha_inicio'] = reporte['fecha_inicio'].strftime('%Y-%m-%d')
            reporte['fecha_fin'] = reporte['fecha_fin'].strftime('%Y-%m-%d')
            reporte['fecha_generacion'] = reporte['fecha_generacion'].strftime('%Y-%m-%d %H:%M:%S')
        
        print(f"Reportes encontrados: {len(reportes)}")
        return jsonify({'reportes': reportes}), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500

# ============================================
# ENDPOINT: GENERAR REPORTE SEMANAL
# ============================================
@app.route('/api/reportes/generar', methods=['POST'])
@token_required
def generar_reporte(current_user_id):
    """Genera un nuevo reporte semanal de consumo"""
    print("\n[GENERAR REPORTE]")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que es coordinador
        cursor.execute(
            "SELECT rol FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Calcular fechas de la semana (Lunes-Viernes)
        from datetime import datetime, timedelta
        
        hoy = datetime.now().date()
        dias_desde_lunes = hoy.weekday()  # 0=Lunes, 4=Viernes
        lunes_actual = hoy - timedelta(days=dias_desde_lunes)
        
        # Si hoy es sábado o domingo, usar la semana anterior
        if hoy.weekday() >= 5:  # 5=Sábado, 6=Domingo
            viernes_actual = lunes_actual - timedelta(days=3)
            lunes_actual = viernes_actual - timedelta(days=4)
            fecha_inicio = lunes_actual
            fecha_fin = viernes_actual
        else:
            # Semana actual hasta hoy (o hasta viernes si ya pasó)
            if hoy.weekday() <= 4:  # Lunes-Viernes
                fecha_inicio = lunes_actual
                fecha_fin = hoy if hoy.weekday() <= 4 else lunes_actual + timedelta(days=4)
            else:
                fecha_inicio = lunes_actual
                fecha_fin = lunes_actual + timedelta(days=4)  # Viernes
        
        fecha_inicio_str = fecha_inicio.strftime('%Y-%m-%d')
        fecha_fin_str = fecha_fin.strftime('%Y-%m-%d')
        
        # Obtener período actual
        cursor.execute(
            "SELECT periodo FROM jornadas WHERE activo = 1 LIMIT 1"
        )
        periodo_actual = cursor.fetchone()
        periodo = periodo_actual['periodo'] if periodo_actual else '2025-2'
        
        # Calcular consumo total en el rango de fechas (SOLO días laborables)
        cursor.execute(
            """SELECT 
                SUM(consumo_kW) as total_consumo,
                SUM(encendido_segundos) as total_segundos
            FROM consumo
            WHERE DATE(dato_encendido) >= %s 
            AND DATE(dato_encendido) <= %s
            AND DAYOFWEEK(dato_encendido) BETWEEN 2 AND 6""",  # Lunes=2, Viernes=6
            (fecha_inicio_str, fecha_fin_str)
        )
        resultado = cursor.fetchone()
        
        total_consumo = float(resultado['total_consumo'] or 0)
        total_segundos = int(resultado['total_segundos'] or 0)
        total_horas = round(total_segundos / 3600, 2)
        
        # Calcular días laborables reales en el rango
        dias_laborables = 0
        fecha_temp = fecha_inicio
        while fecha_temp <= fecha_fin:
            if fecha_temp.weekday() < 5:  # Lunes-Viernes
                dias_laborables += 1
            fecha_temp += timedelta(days=1)
        
        promedio_diario = round(total_consumo / dias_laborables, 2) if dias_laborables > 0 else 0
        
        # Generar descripción
        descripcion = f"Semana del {fecha_inicio.strftime('%d/%m')} al {fecha_fin.strftime('%d/%m/%Y')} - Periodo {periodo}"
        
        # Verificar si ya existe un reporte para estas fechas
        cursor.execute(
            """SELECT id_reporte FROM reportes_consumo 
            WHERE fecha_inicio = %s AND fecha_fin = %s""",
            (fecha_inicio_str, fecha_fin_str)
        )
        existente = cursor.fetchone()
        
        if existente:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Ya existe un reporte para este período'}), 409
        
        # Guardar reporte
        cursor.execute(
            """INSERT INTO reportes_consumo 
            (fecha_inicio, fecha_fin, periodo, total_consumo_kWh, total_horas_uso, 
             promedio_diario_kWh, descripcion, generado_por)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
            (fecha_inicio_str, fecha_fin_str, periodo, total_consumo, total_horas, 
             promedio_diario, descripcion, current_user_id)
        )
        
        id_reporte = cursor.lastrowid
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"Reporte generado con ID: {id_reporte}")
        
        return jsonify({
            'message': 'Reporte generado exitosamente',
            'id_reporte': id_reporte,
            'descripcion': descripcion,
            'total_consumo': total_consumo,
            'total_horas': total_horas,
            'promedio_diario': promedio_diario
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500

# ============================================
# FUNCIÓN: GENERAR REPORTE AUTOMÁTICO SEMANAL
# ============================================
def generar_reporte_automatico_semanal():
    """
    Genera automáticamente un reporte semanal
    Se ejecuta cada domingo a las 23:59 vía scheduler
    """
    print("\n" + "="*60)
    print("GENERANDO REPORTE AUTOMÁTICO SEMANAL")
    print("="*60)
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Calcular semana anterior (Lunes-Domingo)
        hoy = datetime.now().date()
        dias_desde_lunes = hoy.weekday()  # 0=Lunes, 6=Domingo
        lunes_esta_semana = hoy - timedelta(days=dias_desde_lunes)
        
        # Semana ANTERIOR
        domingo_anterior = lunes_esta_semana - timedelta(days=1)
        lunes_anterior = domingo_anterior - timedelta(days=6)
        
        fecha_inicio = lunes_anterior.strftime('%Y-%m-%d')
        fecha_fin = domingo_anterior.strftime('%Y-%m-%d')
        
        print(f"Generando reporte: {fecha_inicio} al {fecha_fin}")

        # Verificar si el período está activo
        esta_activo, periodo_actual = periodo_activo()

        if not esta_activo:
            # Usar año actual con -0 para períodos vencidos
            ano_actual = datetime.now().year
            periodo = f"{ano_actual}-0"  # Ej: "2026-0"
            print(f"Período vencido - usando: {periodo}")
        else:
            periodo = periodo_actual
            print(f"Período activo: {periodo}")
        
        # Calcular consumo total PRIMERO
        cursor.execute("""
            SELECT 
                SUM(consumo_kW) as total_consumo,
                SUM(encendido_segundos) as total_segundos,
                COUNT(*) as total_usos
            FROM consumo
            WHERE DATE(dato_encendido) >= %s 
              AND DATE(dato_encendido) <= %s
              AND dato_apagado IS NOT NULL
        """, (fecha_inicio, fecha_fin))
        
        resultado = cursor.fetchone()
        
        if not resultado or not resultado['total_consumo']:
            print("No hay datos de consumo para esta semana")
            cursor.close()
            conn.close()
            return
        
        total_consumo = float(resultado['total_consumo'])
        total_segundos = int(resultado['total_segundos'])
        total_horas = round(total_segundos / 3600, 2)
        promedio_diario = round(total_consumo / 7, 2)  # 7 días
        
        # Generar descripción
        inicio_obj = datetime.strptime(fecha_inicio, '%Y-%m-%d')
        fin_obj = datetime.strptime(fecha_fin, '%Y-%m-%d')
        descripcion = f"Semana del {inicio_obj.strftime('%d/%m')} al {fin_obj.strftime('%d/%m/%Y')} - Período {periodo}"
        
        # Verificar si ya existe un reporte
        cursor.execute("""
            SELECT id_reporte FROM reportes_consumo 
            WHERE fecha_inicio = %s AND fecha_fin = %s
        """, (fecha_inicio, fecha_fin))

        reporte_existente = cursor.fetchone()

        if reporte_existente:
            # SOBRESCRIBIR reporte parcial con datos completos
            print(f"Actualizando reporte existente ID: {reporte_existente['id_reporte']}")
            
            cursor.execute("""
                UPDATE reportes_consumo
                SET total_consumo_kWh = %s,
                    total_horas_uso = %s,
                    promedio_diario_kWh = %s,
                    descripcion = %s,
                    periodo = %s,
                    fecha_generacion = NOW()
                WHERE id_reporte = %s
            """, (total_consumo, total_horas, promedio_diario, descripcion, periodo, reporte_existente['id_reporte']))
            
            print("Reporte actualizado con datos completos")
        else:
            # Crear nuevo reporte
            cursor.execute("""
                INSERT INTO reportes_consumo 
                (fecha_inicio, fecha_fin, periodo, total_consumo_kWh, 
                 total_horas_uso, promedio_diario_kWh, descripcion, generado_por)
                VALUES (%s, %s, %s, %s, %s, %s, %s, 1)
            """, (fecha_inicio, fecha_fin, periodo, total_consumo, 
                  total_horas, promedio_diario, descripcion))
            
            print("Reporte nuevo creado")
        
        conn.commit()
        
        print(f"Reporte generado exitosamente")
        print(f"Consumo: {total_consumo:.2f} kWh | Horas: {total_horas:.2f}")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"Error generando reporte automático: {e}")
        import traceback
        traceback.print_exc()

# ============================================
# ENDPOINT: ELIMINAR REPORTE
# ============================================
@app.route('/api/reportes/eliminar/<int:id_reporte>', methods=['DELETE'])
@token_required
def eliminar_reporte(current_user_id, id_reporte):
    """Elimina un reporte (solo coordinadores)"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que el usuario es coordinador
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if not usuario or usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'Solo coordinadores pueden eliminar reportes'}), 403
        
        # Verificar que el reporte existe
        cursor.execute("SELECT id_reporte FROM reportes_consumo WHERE id_reporte = %s", (id_reporte,))
        reporte = cursor.fetchone()
        
        if not reporte:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Reporte no encontrado'}), 404
        
        # Eliminar reporte
        cursor.execute("DELETE FROM reportes_consumo WHERE id_reporte = %s", (id_reporte,))
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"[ELIMINAR REPORTE] Reporte {id_reporte} eliminado por usuario {current_user_id}")
        
        return jsonify({'message': 'Reporte eliminado correctamente'}), 200
        
    except Exception as e:
        print(f"Error al eliminar reporte: {e}")
        return jsonify({'message': f'Error: {str(e)}'}), 500
    

################################ TEMPORIZADOR ################################
# ============================================
# ENDPOINT: PROGRAMAR TEMPORIZADOR
# ============================================
@app.route('/api/temporizador/programar', methods=['POST'])
@token_required
def programar_temporizador(current_user_id):
    """
    Programa apagado automático a una hora específica
    Body: {"hora": "18:00", "grupos": [1, 2]} o {"hora": "18:00", "grupos": "todos"}
    """
    print("\n" + "="*60)
    print("SOLICITUD: PROGRAMAR TEMPORIZADOR")
    print("="*60)
    
    try:
        data = request.get_json()
        hora_str = data.get('hora')  # Formato: "HH:MM"
        grupos = data.get('grupos', 'todos')  # 1, 2, [1,2] o "todos"
        
        if not hora_str:
            return jsonify({'message': 'Hora no especificada'}), 400
        
        # Validar formato de hora
        try:
            hora_obj = datetime.strptime(hora_str, '%H:%M').time()
        except ValueError:
            return jsonify({'message': 'Formato de hora inválido. Use HH:MM'}), 400

        # Crear datetime de la hora programada
        ahora = datetime.now()
        hora_programada_dt = datetime.combine(ahora.date(), hora_obj)

        # Si la hora ya pasó hoy, es para mañana (NO PERMITIR)
        if hora_programada_dt <= ahora:
            return jsonify({
                'success': False,
                'message': f'La hora debe ser posterior a la actual ({ahora.strftime("%H:%M")})'
            }), 400

        # Verificar que sea al menos 1 minuto adelante
        if hora_programada_dt <= ahora + timedelta(minutes=1):
            return jsonify({
                'success': False,
                'message': 'El temporizador debe programarse al menos 1 minuto después'
            }), 400

        # Verificar que sea máximo 1 hora adelante
        if hora_programada_dt > ahora + timedelta(hours=1):
            return jsonify({
                'success': False,
                'message': 'El temporizador no puede programarse más de 1 hora adelante (máximo 60 minutos)'
            }), 400
        
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener nombre del usuario
        cursor.execute(
            "SELECT nombre FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if not usuario:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no encontrado'}), 404
        
        # Determinar qué grupos apagar
        if grupos == 'todos' or grupos == ['todos']:
            grupos_nombres = ['Grupo 1', 'Grupo 2']
            grupos_texto = "todos los grupos"
        else:
            if isinstance(grupos, int):
                grupos = [grupos]
            grupos_nombres = [f'Grupo {g}' for g in grupos]
            grupos_texto = ', '.join(grupos_nombres)
        
        # Guardar temporizador en memoria
        temporizador_id = f"user_{current_user_id}"
        temporizadores_activos[temporizador_id] = {
            'usuario_id': current_user_id,
            'usuario_nombre': usuario['nombre'],
            'hora': hora_str,
            'grupos': grupos_nombres,
            'programado_en': datetime.now().isoformat()
        }
        
        print(f" Temporizador programado para {hora_str}")
        print(f" Se apagarán: {grupos_texto}")
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'message': f'Temporizador programado para las {hora_str}',
            'hora': hora_str,
            'grupos': grupos_texto,
            'usuario': usuario['nombre']
        }), 200
        
    except Exception as e:
        print(f" ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: OBTENER TEMPORIZADOR ACTIVO
# ============================================
@app.route('/api/temporizador/estado', methods=['GET'])
@token_required
def obtener_temporizador(current_user_id):
    """
    Obtiene el temporizador activo del usuario actual
    """
    try:
        temporizador_id = f"user_{current_user_id}"
        
        if temporizador_id in temporizadores_activos:
            temp = temporizadores_activos[temporizador_id]
            return jsonify({
                'activo': True,
                'hora': temp['hora'],
                'grupos': temp['grupos'],
                'programado_en': temp['programado_en']
            }), 200
        else:
            return jsonify({
                'activo': False,
                'message': 'No hay temporizador activo'
            }), 200
            
    except Exception as e:
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# ENDPOINT: CANCELAR TEMPORIZADOR
# ============================================
@app.route('/api/temporizador/cancelar', methods=['DELETE'])
@token_required
def cancelar_temporizador(current_user_id):
    """
    Cancela el temporizador activo del usuario
    """
    print("\n" + "="*60)
    print("SOLICITUD: CANCELAR TEMPORIZADOR")
    print("="*60)
    
    try:
        temporizador_id = f"user_{current_user_id}"
        
        if temporizador_id in temporizadores_activos:
            temp = temporizadores_activos[temporizador_id]
            print(f" Cancelando temporizador de {temp['usuario_nombre']}")
            del temporizadores_activos[temporizador_id]
            
            return jsonify({
                'message': 'Temporizador cancelado correctamente'
            }), 200
        else:
            return jsonify({
                'message': 'No hay temporizador activo para cancelar'
            }), 200
            
    except Exception as e:
        print(f" ERROR: {str(e)}")
        return jsonify({'message': f'Error del servidor: {str(e)}'}), 500


# ============================================
# FUNCIÓN: VERIFICAR TEMPORIZADORES  
# ============================================
def verificar_temporizadores():
    """
    Función que se ejecuta cada minuto para verificar si hay que apagar luces
    """
    hora_actual = datetime.now().time()
    hora_actual_str = hora_actual.strftime('%H:%M')
    
    temporizadores_a_eliminar = []
    
    for temp_id, temp_data in temporizadores_activos.items():
        hora_programada = temp_data['hora']
        
        if hora_actual_str == hora_programada:
            print(f" ¡HORA DE APAGAR! Usuario: {temp_data['usuario_nombre']}")
            
            # Apagar los grupos programados
            try:
                print(f"Intentando apagar grupos...")
                conn = get_db_connection()
                cursor = conn.cursor(dictionary=True)
                
                for grupo_nombre in temp_data['grupos']:
                    # Buscar registro abierto
                    cursor.execute(
                        """SELECT id_consumo, dato_encendido 
                        FROM consumo 
                        WHERE grupo_luces = %s 
                          AND dato_apagado IS NULL
                        LIMIT 1""",
                        (grupo_nombre,)
                    )
                    registro = cursor.fetchone()
                    
                    if registro:
                        # Calcular watts (324W por grupo)
                        watts = 324
                        
                        # Apagar
                        cursor.execute(
                            """UPDATE consumo 
                            SET dato_apagado = NOW(),
                                metodo_apagado = 'Temporizador',
                                estado = 'apagado',
                                encendido_segundos = TIMESTAMPDIFF(SECOND, dato_encendido, NOW()),
                                consumo_kW = (TIMESTAMPDIFF(SECOND, dato_encendido, NOW()) * %s) / 3600000.0
                            WHERE id_consumo = %s""",
                            (watts, registro['id_consumo'])
                        )
                        print(f" {grupo_nombre} apagado automáticamente")
                                
                        # APAGAR GPIO FÍSICAMENTE
                        if ES_RASPBERRY:
                            if grupo_nombre == 'Grupo 1':
                                RELAY_GRUPO1.on()  # Apagar (invertido)
                                print(f"GPIO Grupo 1 apagado")
                            elif grupo_nombre == 'Grupo 2':
                                RELAY_GRUPO2.on()  # Apagar (invertido)
                                print(f"GPIO Grupo 2 apagado")
                
                conn.commit()
                cursor.close()
                conn.close()
                
                print(f" Temporizador de {temp_data['usuario_nombre']} ejecutado correctamente")
                
            except Exception as e:
                print(f" ERROR al ejecutar temporizador: {str(e)}")
            
            # Marcar para eliminar
            temporizadores_a_eliminar.append(temp_id)
    
    # Eliminar temporizadores ejecutados
    for temp_id in temporizadores_a_eliminar:
        del temporizadores_activos[temp_id]
        print(f" Temporizador {temp_id} eliminado")

    # Verificar luces fuera de horario
    verificar_luces_fuera_horario()

# ============================================
# ENDPOINT: VERIFICAR LUCES FUERA DE HORARIO
# ============================================
def verificar_luces_fuera_horario():
    """
    Verifica si hay luces encendidas fuera de horario de jornada
    Las apaga después de 30 minutos
    """
    if not ES_RASPBERRY:
        return
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener día actual y hora
        ahora = datetime.now()
        dia_semana = ahora.strftime('%A')  # Monday, Tuesday, etc.
        
        # Mapear días en inglés a español
        dias_map = {
            'Monday': 'Lunes',
            'Tuesday': 'Martes',
            'Wednesday': 'Miércoles',
            'Thursday': 'Jueves',
            'Friday': 'Viernes',
            'Saturday': 'Sábado',
            'Sunday': 'Domingo'
        }
        dia_actual = dias_map.get(dia_semana, dia_semana)
        hora_actual = ahora.time()
        
        # Buscar jornada activa para hoy
        cursor.execute("""
            SELECT hora_inicio_matutina, hora_fin_matutina,
                    hora_inicio_vespertina, hora_fin_vespertina
            FROM jornadas
            WHERE dia_semana = %s AND activo = 1
        """, (dia_actual,))

        jornada = cursor.fetchone()
        
        if not jornada:
            cursor.close()
            conn.close()
            return
        
        # Convertir timedelta a time si es necesario
        for key in ['hora_inicio_matutina', 'hora_fin_matutina', 
                    'hora_inicio_vespertina', 'hora_fin_vespertina']:
            if jornada.get(key) and isinstance(jornada[key], timedelta):
                jornada[key] = (datetime.min + jornada[key]).time()
        
        # Verificar si estamos FUERA de horario
        en_horario = False

        if jornada['hora_inicio_matutina'] and jornada['hora_fin_matutina']:
            if jornada['hora_inicio_matutina'] <= hora_actual <= jornada['hora_fin_matutina']:
                en_horario = True

        if jornada['hora_inicio_vespertina'] and jornada['hora_fin_vespertina']:
            if jornada['hora_inicio_vespertina'] <= hora_actual <= jornada['hora_fin_vespertina']:
                en_horario = True
        
        # Si NO estamos en horario, verificar luces encendidas
        if not en_horario:
            # Buscar registros de consumo abiertos (luces encendidas)
            cursor.execute("""
                SELECT id_consumo, grupo_luces, dato_encendido,
                       TIMESTAMPDIFF(MINUTE, dato_encendido, NOW()) as minutos_encendidos
                FROM consumo
                WHERE dato_apagado IS NULL
            """)
            
            registros = cursor.fetchall()

            for registro in registros:
                minutos = registro['minutos_encendidos']
                grupo = registro['grupo_luces']
    
                # ADVERTENCIA a los 28 minutos (2 min antes)
                if minutos == 28:
                    print(f"ADVERTENCIA: {grupo} se apagará en 2 minutos (fuera de horario)")
                # Aquí puedes enviar notificación push si quieres
                # Por ahora solo log
    
                # APAGADO a los 30 minutos
                elif minutos >= 30:
                    print(f"APAGADO AUTOMÁTICO: {grupo} lleva {minutos} min encendido fuera de horario")
                    
                    # Apagar GPIO
                    if grupo == 'Grupo 1':
                        RELAY_GRUPO1.on()  # Apagar
                        print(f"GPIO Grupo 1 apagado (fuera de horario)")
                    elif grupo == 'Grupo 2':
                        RELAY_GRUPO2.on()  # Apagar
                        print(f"GPIO Grupo 2 apagado (fuera de horario)")
                    
                    # Actualizar BD
                    cursor.execute("""
                        UPDATE consumo
                        SET dato_apagado = NOW(),
                            metodo_apagado = 'Automático - Fuera de horario',
                            estado = 'apagado',
                            encendido_segundos = TIMESTAMPDIFF(SECOND, dato_encendido, NOW()),
                            consumo_kW = (TIMESTAMPDIFF(SECOND, dato_encendido, NOW()) * 324) / 3600000.0
                        WHERE id_consumo = %s
                    """, (registro['id_consumo'],))
                    
                    print(f"{grupo} apagado y registrado en BD")
            
            conn.commit()
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"Error verificando luces fuera de horario: {e}")
        
#################################### JORNADAS ####################################
# ============================================
# ENDPOINT: OBTENER JORNADA POR DÍA
# ============================================
@app.route('/api/jornadas/<string:dia>', methods=['GET'])
@token_required
def obtener_jornada(current_user_id, dia):
    """Obtiene horarios de jornada para un día específico"""
    print(f"\n[OBTENER JORNADA] Día: {dia}")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute("""
            SELECT dia_semana, hora_inicio_matutina, hora_fin_matutina,
                   hora_inicio_vespertina, hora_fin_vespertina, periodo
            FROM jornadas 
            WHERE LOWER(dia_semana) = LOWER(%s) AND activo = 1
        """, (dia,))
        
        jornada = cursor.fetchone()
        cursor.close()
        conn.close()
        
        if jornada:
            # Convertir timedelta a string
            def timedelta_to_str(td):
                if td is None:
                    return None
                total_seconds = int(td.total_seconds())
                hours = total_seconds // 3600
                minutes = (total_seconds % 3600) // 60
                seconds = total_seconds % 60
                return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
            
            jornada['hora_inicio_matutina'] = timedelta_to_str(jornada.get('hora_inicio_matutina'))
            jornada['hora_fin_matutina'] = timedelta_to_str(jornada.get('hora_fin_matutina'))
            jornada['hora_inicio_vespertina'] = timedelta_to_str(jornada.get('hora_inicio_vespertina'))
            jornada['hora_fin_vespertina'] = timedelta_to_str(jornada.get('hora_fin_vespertina'))
                
            print(f"Jornada encontrada: {jornada}")
            return jsonify(jornada), 200
        else:
            print(f"No se encontró jornada activa para: {dia}")
            return jsonify({'message': f'No se encontró jornada para {dia}'}), 404
            
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500

# ============================================
# ENDPOINT: OBTENER TODAS LAS JORNADAS
# ============================================
@app.route('/api/jornadas', methods=['GET'])
@token_required
def obtener_todas_jornadas(current_user_id):
    """Obtiene todas las jornadas de la semana"""
    print(f"\n[JORNADAS] Solicitud de todas las jornadas")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        cursor.execute("""
            SELECT dia_semana, hora_inicio_matutina, hora_fin_matutina,
                   hora_inicio_vespertina, hora_fin_vespertina, activo
            FROM jornadas 
            ORDER BY FIELD(dia_semana, 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado')
        """)
        jornadas = cursor.fetchall()
        
        # Convertir timedelta a string
        def timedelta_to_str(td):
            if td is None:
                return None
            total_seconds = int(td.total_seconds())
            hours = total_seconds // 3600
            minutes = (total_seconds % 3600) // 60
            seconds = total_seconds % 60
            return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
        
        for jornada in jornadas:
            jornada['hora_inicio_matutina'] = timedelta_to_str(jornada.get('hora_inicio_matutina'))
            jornada['hora_fin_matutina'] = timedelta_to_str(jornada.get('hora_fin_matutina'))
            jornada['hora_inicio_vespertina'] = timedelta_to_str(jornada.get('hora_inicio_vespertina'))
            jornada['hora_fin_vespertina'] = timedelta_to_str(jornada.get('hora_fin_vespertina'))
        
        cursor.close()
        conn.close()
        
        return jsonify(jornadas), 200
        
    except Exception as e:
        print(f"[JORNADAS] ERROR: {str(e)}")
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: ACTUALIZAR JORNADA
# ============================================
@app.route('/api/jornadas/<string:dia>', methods=['PUT'])
@token_required
def actualizar_jornada(current_user_id, dia):
    """Coordinador actualiza horarios de jornada"""
    print(f"\n[ACTUALIZAR JORNADA] Día: {dia}")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que es coordinador
        cursor.execute("SELECT rol FROM usuarios WHERE id_usuario = %s", (current_user_id,))
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        data = request.get_json()
        
        hora_inicio_mat = data.get('hora_inicio_matutina')
        hora_fin_mat = data.get('hora_fin_matutina')
        hora_inicio_vesp = data.get('hora_inicio_vespertina')
        hora_fin_vesp = data.get('hora_fin_vespertina')
        
        print(f"Datos recibidos: {data}")
        
        # Cambiar jornada a la actual
        cursor.execute(
            """UPDATE jornadas 
            SET hora_inicio_matutina = %s,
                hora_fin_matutina = %s,
                hora_inicio_vespertina = %s,
                hora_fin_vespertina = %s
            WHERE LOWER(dia_semana) = LOWER(%s) AND activo = 1""",  # ← AGREGAR activo = 1
            (hora_inicio_mat, hora_fin_mat, hora_inicio_vesp, hora_fin_vesp, dia)
        )
        
        conn.commit()
        
        rows_affected = cursor.rowcount
        print(f"Filas actualizadas: {rows_affected}")
        
        cursor.close()
        conn.close()
        
        if rows_affected > 0:
            return jsonify({'message': f'Jornada de {dia} actualizada'}), 200
        else:
            return jsonify({
            'message': f'No se encontró jornada activa para {dia}. Cree un período académico primero.'
            }), 404
        
    except Exception as e:
        print(f"[ACTUALIZAR JORNADA] ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500

    
# ============================================
# ENDPOINT: GESTIONAR PERIODO DE LA JORNADA
# ============================================
@app.route('/api/jornadas/periodo', methods=['GET', 'PUT'])
@token_required
def gestionar_periodo(current_user_id):
    """Obtener o actualizar periodo académico actual"""
    
    if request.method == 'GET':
        print("\n[PERIODO] Obteniendo periodo actual")
        try:
            conn = get_db_connection()
            cursor = conn.cursor(dictionary=True)
            
            # Obtener periodo activo
            cursor.execute(
                "SELECT periodo FROM jornadas WHERE activo = 1 LIMIT 1"
            )
            result = cursor.fetchone()
            
            cursor.close()
            conn.close()
            
            # Si no hay período activo, calcular automáticamente
            if not result:
                ano_actual = datetime.now().year
                mes_actual = datetime.now().month
                periodo_num = '1' if mes_actual <= 7 else '2'
                periodo_actual = f'{ano_actual}-{periodo_num}'
                
                print(f" No hay período activo. Período calculado: {periodo_actual}")
                print("   El coordinador debe crear el período desde la app")
            else:
                periodo_actual = result['periodo']
            
            print(f" Periodo actual: {periodo_actual}")
            
            return jsonify({'periodo': periodo_actual}), 200
            
        except Exception as e:
            print(f" ERROR: {str(e)}")
            import traceback
            traceback.print_exc()
            return jsonify({'message': f'Error: {str(e)}'}), 500
    
    elif request.method == 'PUT':
        print("\n" + "="*60)
        print(" CAMBIO DE PERIODO")
        print("="*60)
        
        try:
            # Verificar que es coordinador
            conn = get_db_connection()
            cursor = conn.cursor(dictionary=True)
            
            cursor.execute(
                "SELECT rol FROM usuarios WHERE id_usuario = %s", 
                (current_user_id,)
            )
            usuario = cursor.fetchone()
            
            if usuario['rol'] != 'coordinador':
                print(" Usuario no autorizado")
                cursor.close()
                conn.close()
                return jsonify({'message': 'No autorizado'}), 403
            
            data = request.get_json()
            nuevo_periodo = data.get('periodo')
            fecha_inicio = data.get('fecha_inicio')  # Formato: YYYY-MM-DD
            fecha_fin = data.get('fecha_fin')        # Formato: YYYY-MM-DD
            
            # VALIDACIÓN 1: Datos obligatorios
            if not nuevo_periodo:
                cursor.close()
                conn.close()
                return jsonify({'message': 'Periodo no proporcionado'}), 400
            
            if not fecha_inicio or not fecha_fin:
                cursor.close()
                conn.close()
                return jsonify({'message': 'Debe proporcionar fecha de inicio y fin del período académico'}), 400
            
            # VALIDACIÓN 2: Formato del período (YYYY-1 o YYYY-2)
            patron = r'^(\d{4})-([1-2])$'
            match = re.match(patron, nuevo_periodo)
            
            if not match:
                cursor.close()
                conn.close()
                return jsonify({'message': 'Formato incorrecto. Debe ser YYYY-1 o YYYY-2'}), 400
            
            ano = int(match.group(1))
            periodo_num = match.group(2)
            
            # VALIDACIÓN 3: Periodo debe ser 1 o 2
            if periodo_num not in ['1', '2']:
                cursor.close()
                conn.close()
                return jsonify({'message': 'El periodo debe ser 1 o 2'}), 400
            
            # VALIDACIÓN 4: Formato de fechas
            try:
                fecha_inicio_obj = datetime.strptime(fecha_inicio, '%Y-%m-%d')
                fecha_fin_obj = datetime.strptime(fecha_fin, '%Y-%m-%d')
            except ValueError:
                cursor.close()
                conn.close()
                return jsonify({'message': 'Formato de fecha inválido. Use YYYY-MM-DD (ejemplo: 2025-09-15)'}), 400

            # VALIDACIÓN 4.5: Año del período debe coincidir con fechas ingresadas
            ano_periodo = int(nuevo_periodo.split('-')[0])
            ano_inicio = fecha_inicio_obj.year
            ano_fin = fecha_fin_obj.year

            # El año del período DEBE coincidir con el año de inicio O fin
            if ano_periodo != ano_inicio and ano_periodo != ano_fin:
                cursor.close()
                conn.close()
                return jsonify({
                    'message': f'El año del período ({ano_periodo}) debe coincidir con el año de inicio ({ano_inicio}) o fin ({ano_fin})'
                }), 400

            # Validar que las fechas sean coherentes (no muy antiguas ni muy futuras)
            ano_actual = datetime.now().year

            if ano_inicio < ano_actual - 2 or ano_inicio > ano_actual + 2:
                cursor.close()
                conn.close()
                return jsonify({
                    'message': f'La fecha de inicio ({fecha_inicio}) parece incorrecta. Verifique el año.'
                }), 400

            if ano_fin < ano_actual - 2 or ano_fin > ano_actual + 2:
                cursor.close()
                conn.close()
                return jsonify({
                    'message': f'La fecha de fin ({fecha_fin}) parece incorrecta. Verifique el año.'
                }), 400
            
            # VALIDACIÓN 5: Fecha fin debe ser posterior a fecha inicio
            if fecha_fin_obj <= fecha_inicio_obj:
                cursor.close()
                conn.close()
                return jsonify({'message': 'La fecha de fin debe ser posterior a la fecha de inicio'}), 400
            
            # VALIDACIÓN 6: Período debe tener entre 115 y 150 días 
            diferencia_dias = (fecha_fin_obj - fecha_inicio_obj).days

            if diferencia_dias < 115:
                cursor.close()
                conn.close()
                return jsonify({
                    'message': f'El período debe tener al menos 4 meses (115 días). Actual: {diferencia_dias} días'
                }), 400

            if diferencia_dias > 150:
                cursor.close()
                conn.close()
                return jsonify({
                    'message': f'El período no puede exceder 5 meses (150 días). Actual: {diferencia_dias} días'
                }), 400
            
            # VALIDACIÓN 7: Fecha fin NO debe estar en el pasado
            hoy = datetime.now().date()

            if fecha_fin_obj.date() < hoy:
                cursor.close()
                conn.close()
                return jsonify({
                    'message': f'La fecha de fin ({fecha_fin}) ya pasó. No puede crear un período vencido.'
                }), 400

            print(f"   Validaciones exitosas")
            print(f"   Período: {nuevo_periodo}")
            print(f"   Inicio: {fecha_inicio}")
            print(f"   Fin: {fecha_fin}")
            print(f"   Duración: {diferencia_dias} días")
            
            # Verificar si el período ya existe
            cursor.execute(
                "SELECT COUNT(*) as count FROM jornadas WHERE periodo = %s",
                (nuevo_periodo,)
            )
            existe = cursor.fetchone()['count']
            
            if existe > 0:
                print(f" Período {nuevo_periodo} ya existe")
                
                # Desactivar todos los períodos
                cursor.execute("UPDATE jornadas SET activo = 0")
                
                # Activar el período seleccionado y actualizar fechas
                cursor.execute(
                    """UPDATE jornadas 
                    SET activo = 1,
                        fecha_inicio_periodo = %s,
                        fecha_fin_periodo = %s
                    WHERE periodo = %s""",
                    (fecha_inicio, fecha_fin, nuevo_periodo)
                )
                
                mensaje = f"Período {nuevo_periodo} activado"
                
            else:
                print(f" Creando nuevas jornadas para período {nuevo_periodo}...")
                
                # Desactivar períodos anteriores
                cursor.execute("UPDATE jornadas SET activo = 0")
                
                # Crear jornadas con horarios en 00:00:00
                jornadas_vacias = [
                    ('Lunes', '00:00:00', '00:00:00', '00:00:00', '00:00:00'),
                    ('Martes', '00:00:00', '00:00:00', '00:00:00', '00:00:00'),
                    ('Miércoles', '00:00:00', '00:00:00', '00:00:00', '00:00:00'),
                    ('Jueves', '00:00:00', '00:00:00', '00:00:00', '00:00:00'),
                    ('Viernes', '00:00:00', '00:00:00', '00:00:00', '00:00:00'),
                ]
                
                for dia, inicio_mat, fin_mat, inicio_vesp, fin_vesp in jornadas_vacias:
                    cursor.execute(
                        """INSERT INTO jornadas 
                        (dia_semana, hora_inicio_matutina, hora_fin_matutina, 
                         hora_inicio_vespertina, hora_fin_vespertina, activo, periodo,
                         fecha_inicio_periodo, fecha_fin_periodo)
                        VALUES (%s, %s, %s, %s, %s, 1, %s, %s, %s)""",
                        (dia, inicio_mat, fin_mat, inicio_vesp, fin_vesp, nuevo_periodo,
                         fecha_inicio, fecha_fin)
                    )
                    print(f" {dia}: Creado con horarios 00:00:00")
                
                mensaje = f"Nuevas jornadas creadas para período {nuevo_periodo}"
            
            conn.commit()
            print(f" {mensaje}")
            print("="*60)
            
            cursor.close()
            conn.close()
            
            return jsonify({'message': mensaje}), 200
            
        except Exception as e:
            print(f" ERROR: {str(e)}")
            import traceback
            traceback.print_exc()
            return jsonify({'message': f'Error: {str(e)}'}), 500

###################################### PERIODO ################################################### 
# ============================================
# ENDPOINT: VERIFICAR PERÍODO ACTIVO
# ============================================
@app.route('/api/periodo/activo', methods=['GET'])
@token_required
def verificar_periodo_activo(current_user_id):
    """
    Verifica si el período académico está vigente
    """
    try:
        esta_activo, periodo = periodo_activo()
        
        if esta_activo:
            return jsonify({
                'activo': True,
                'periodo': periodo,
                'mensaje': f'Período {periodo} vigente'
            }), 200
        else:
            return jsonify({
                'activo': False,
                'periodo': None,
                'mensaje': 'Período académico vencido. Configure nuevo período.'
            }), 200
            
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

###################################### CONTRASEÑA COORDINADOR ###################################################
# ============================================
# ENDPOINT: VERIFICAR SI COORDINADOR TIENE PREGUNTAS CONFIGURADAS
# ============================================
@app.route('/api/auth/tiene-preguntas/<cedula>', methods=['GET'])
def tiene_preguntas(cedula):
    """Verifica si el coordinador tiene preguntas de seguridad configuradas"""
    print(f"\n[VERIFICAR PREGUNTAS] Cédula: {cedula}")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener usuario
        cursor.execute(
            "SELECT id_usuario, rol FROM usuarios WHERE cedula = %s",
            (cedula,)
        )
        usuario = cursor.fetchone()
        
        if not usuario:
            cursor.close()
            conn.close()
            return jsonify({'existe': False}), 404
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'es_coordinador': False}), 200
        
        # Verificar si tiene preguntas
        cursor.execute(
            "SELECT id_pregunta FROM preguntas_seguridad WHERE id_usuario = %s",
            (usuario['id_usuario'],)
        )
        tiene = cursor.fetchone() is not None
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'es_coordinador': True,
            'tiene_preguntas': tiene
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: CONFIGURAR PREGUNTAS DE SEGURIDAD (Primera vez)
# ============================================
@app.route('/api/auth/configurar-preguntas', methods=['POST'])
@token_required
def configurar_preguntas(current_user_id):
    """Coordinador configura sus preguntas de seguridad por primera vez"""
    print("\n[CONFIGURAR PREGUNTAS]")
    
    data = request.get_json()
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que es coordinador
        cursor.execute(
            "SELECT rol FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'Solo coordinadores pueden configurar preguntas'}), 403
        
        # Verificar que no tenga preguntas ya configuradas
        cursor.execute(
            "SELECT id_pregunta FROM preguntas_seguridad WHERE id_usuario = %s",
            (current_user_id,)
        )
        if cursor.fetchone():
            cursor.close()
            conn.close()
            return jsonify({'message': 'Ya tienes preguntas configuradas'}), 400

        # Validar que las preguntas sean diferentes
        if (data['pregunta1'] == data['pregunta2'] or 
            data['pregunta1'] == data['pregunta3'] or 
            data['pregunta2'] == data['pregunta3']):
            cursor.close()
            conn.close()
            return jsonify({
                'message': 'Las 3 preguntas de seguridad deben ser diferentes'
            }), 400
        
        # Encriptar respuestas
        respuesta1_hash = bcrypt.hashpw(data['respuesta1'].lower().strip().encode('utf-8'), bcrypt.gensalt())
        respuesta2_hash = bcrypt.hashpw(data['respuesta2'].lower().strip().encode('utf-8'), bcrypt.gensalt())
        respuesta3_hash = bcrypt.hashpw(data['respuesta3'].lower().strip().encode('utf-8'), bcrypt.gensalt())
        
        # Guardar preguntas
        cursor.execute(
            """INSERT INTO preguntas_seguridad 
            (id_usuario, pregunta1, respuesta1_hash, pregunta2, respuesta2_hash, pregunta3, respuesta3_hash)
            VALUES (%s, %s, %s, %s, %s, %s, %s)""",
            (current_user_id, data['pregunta1'], respuesta1_hash.decode('utf-8'),
             data['pregunta2'], respuesta2_hash.decode('utf-8'),
             data['pregunta3'], respuesta3_hash.decode('utf-8'))
        )
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print("Preguntas configuradas exitosamente")
        return jsonify({'message': 'Preguntas configuradas exitosamente'}), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: OBTENER PREGUNTAS DEL COORDINADOR (para recuperar contraseña)
# ============================================
@app.route('/api/auth/obtener-preguntas/<cedula>', methods=['GET'])
def obtener_preguntas(cedula):
    """Obtiene las preguntas de seguridad de un coordinador"""
    print(f"\n[OBTENER PREGUNTAS] Cédula: {cedula}")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener usuario
        cursor.execute(
            "SELECT id_usuario, nombre, rol FROM usuarios WHERE cedula = %s",
            (cedula,)
        )
        usuario = cursor.fetchone()
        
        if not usuario:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Cédula no encontrada'}), 404
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'Esta cédula no pertenece a un coordinador'}), 403
        
        # Obtener preguntas (sin las respuestas)
        cursor.execute(
            """SELECT pregunta1, pregunta2, pregunta3 
            FROM preguntas_seguridad 
            WHERE id_usuario = %s""",
            (usuario['id_usuario'],)
        )
        preguntas = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        if not preguntas:
            return jsonify({'message': 'Este coordinador no tiene preguntas configuradas'}), 404
        
        return jsonify({
            'nombre': usuario['nombre'],
            'preguntas': [
                preguntas['pregunta1'],
                preguntas['pregunta2'],
                preguntas['pregunta3']
            ]
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: VALIDAR RESPUESTAS Y CAMBIAR CONTRASEÑA (Coordinador)
# ============================================
@app.route('/api/auth/recuperar-coordinador', methods=['POST'])
def recuperar_coordinador():
    """Valida respuestas de seguridad y cambia contraseña del coordinador"""
    print("\n[RECUPERAR CONTRASEÑA COORDINADOR]")
    
    data = request.get_json()
    cedula = data.get('cedula')
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener usuario
        cursor.execute(
            "SELECT id_usuario, nombre FROM usuarios WHERE cedula = %s",
            (cedula,)
        )
        usuario = cursor.fetchone()
        
        if not usuario:
            cursor.close()
            conn.close()
            return jsonify({'message': 'Usuario no encontrado'}), 404
        
        # Obtener respuestas guardadas
        cursor.execute(
            """SELECT respuesta1_hash, respuesta2_hash, respuesta3_hash 
            FROM preguntas_seguridad 
            WHERE id_usuario = %s""",
            (usuario['id_usuario'],)
        )
        respuestas_guardadas = cursor.fetchone()
        
        if not respuestas_guardadas:
            cursor.close()
            conn.close()
            return jsonify({'message': 'No hay preguntas configuradas'}), 404
        
        # Validar respuestas (convertir a minúsculas y quitar espacios)
        respuesta1 = data['respuesta1'].lower().strip().encode('utf-8')
        respuesta2 = data['respuesta2'].lower().strip().encode('utf-8')
        respuesta3 = data['respuesta3'].lower().strip().encode('utf-8')
        
        valida1 = bcrypt.checkpw(respuesta1, respuestas_guardadas['respuesta1_hash'].encode('utf-8'))
        valida2 = bcrypt.checkpw(respuesta2, respuestas_guardadas['respuesta2_hash'].encode('utf-8'))
        valida3 = bcrypt.checkpw(respuesta3, respuestas_guardadas['respuesta3_hash'].encode('utf-8'))
        
        if not (valida1 and valida2 and valida3):
            cursor.close()
            conn.close()
            print("Respuestas incorrectas")
            return jsonify({'message': 'Una o más respuestas son incorrectas'}), 401
        
        # Respuestas correctas - cambiar contraseña
        nueva_contrasena = data.get('nueva_contrasena')
        
        if len(nueva_contrasena) < 8:
            cursor.close()
            conn.close()
            return jsonify({'message': 'La contraseña debe tener al menos 8 caracteres'}), 400
        
        hashed = bcrypt.hashpw(nueva_contrasena.encode('utf-8'), bcrypt.gensalt())
        
        cursor.execute(
            "UPDATE usuarios SET contrasena = %s WHERE id_usuario = %s",
            (hashed.decode('utf-8'), usuario['id_usuario'])
        )
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print(f"Contraseña actualizada para: {usuario['nombre']}")
        return jsonify({'message': 'Contraseña actualizada exitosamente'}), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: VERIFICAR SI COORDINADOR TIENE PREGUNTAS (SIMPLE)
# ============================================
@app.route('/api/auth/tiene-preguntas-configuradas', methods=['GET'])
@token_required
def tiene_preguntas_configuradas(current_user_id):
    """Verifica si el coordinador tiene preguntas configuradas (SIMPLE)"""
    
    print(f"\n[VERIFICAR PREGUNTAS] Usuario ID: {current_user_id}")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que es coordinador
        cursor.execute(
            "SELECT rol FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if not usuario or usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'es_coordinador': False}), 200
        
        # Verificar si tiene preguntas
        cursor.execute(
            "SELECT id_pregunta FROM preguntas_seguridad WHERE id_usuario = %s",
            (current_user_id,)
        )
        tiene_preguntas = cursor.fetchone() is not None
        
        cursor.close()
        conn.close()
        
        print(f"Coordinador tiene preguntas: {tiene_preguntas}")
        
        return jsonify({
            'es_coordinador': True,
            'tiene_preguntas': tiene_preguntas
        }), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500


# ============================================
# ENDPOINT: ACTUALIZAR PREGUNTAS DE SEGURIDAD
# ============================================
@app.route('/api/auth/actualizar-preguntas', methods=['PUT'])
@token_required
def actualizar_preguntas(current_user_id):
    """Coordinador actualiza sus preguntas de seguridad"""
    print("\n[ACTUALIZAR PREGUNTAS]")
    
    data = request.get_json()
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que es coordinador
        cursor.execute(
            "SELECT rol FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'Solo coordinadores pueden actualizar preguntas'}), 403
        
        # Encriptar nuevas respuestas
        respuesta1_hash = bcrypt.hashpw(data['respuesta1'].lower().strip().encode('utf-8'), bcrypt.gensalt())
        respuesta2_hash = bcrypt.hashpw(data['respuesta2'].lower().strip().encode('utf-8'), bcrypt.gensalt())
        respuesta3_hash = bcrypt.hashpw(data['respuesta3'].lower().strip().encode('utf-8'), bcrypt.gensalt())
        
        # Actualizar preguntas (o insertar si no existen)
        cursor.execute(
            """INSERT INTO preguntas_seguridad 
            (id_usuario, pregunta1, respuesta1_hash, pregunta2, respuesta2_hash, pregunta3, respuesta3_hash)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
            pregunta1 = VALUES(pregunta1),
            respuesta1_hash = VALUES(respuesta1_hash),
            pregunta2 = VALUES(pregunta2),
            respuesta2_hash = VALUES(respuesta2_hash),
            pregunta3 = VALUES(pregunta3),
            respuesta3_hash = VALUES(respuesta3_hash),
            fecha_actualizacion = CURRENT_TIMESTAMP""",
            (current_user_id, data['pregunta1'], respuesta1_hash.decode('utf-8'),
             data['pregunta2'], respuesta2_hash.decode('utf-8'),
             data['pregunta3'], respuesta3_hash.decode('utf-8'))
        )
        
        conn.commit()
        cursor.close()
        conn.close()
        
        print("Preguntas actualizadas exitosamente")
        return jsonify({'message': 'Preguntas actualizadas exitosamente'}), 200
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500


###################################### PDF ###################################################
# ============================================
# ENDPOINT: DESCARGAR PDF DE REPORTE
# ============================================
@app.route('/api/reportes/<int:id_reporte>/pdf', methods=['GET'])
@token_required
def descargar_pdf_reporte(current_user_id, id_reporte):
    """Genera y descarga el PDF de un reporte específico"""
    print(f"\n[DESCARGAR PDF] Reporte ID: {id_reporte}")
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Verificar que es coordinador
        cursor.execute(
            "SELECT rol FROM usuarios WHERE id_usuario = %s",
            (current_user_id,)
        )
        usuario = cursor.fetchone()
        
        if usuario['rol'] != 'coordinador':
            cursor.close()
            conn.close()
            return jsonify({'message': 'No autorizado'}), 403
        
        # Obtener datos del reporte
        cursor.execute(
            """SELECT 
                id_reporte,
                fecha_inicio,
                fecha_fin,
                periodo,
                total_consumo_kWh,
                total_horas_uso,
                promedio_diario_kWh,
                descripcion,
                fecha_generacion
            FROM reportes_consumo
            WHERE id_reporte = %s""",
            (id_reporte,)
        )
        reporte = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        if not reporte:
            return jsonify({'message': 'Reporte no encontrado'}), 404
        
        # Formatear fechas
        reporte['fecha_generacion'] = reporte['fecha_generacion'].strftime('%d/%m/%Y %H:%M')
        
        # Generar PDF
        pdf_buffer = generar_pdf_reporte(reporte)
        
        # Nombre del archivo
        filename = f"Reporte_Semana_{reporte['fecha_inicio']}_{reporte['fecha_fin']}.pdf"
        
        print(f"PDF generado: {filename}")
        
        # Enviar PDF
        return send_file(
            pdf_buffer,
            mimetype='application/pdf',
            as_attachment=True,
            download_name=filename
        )
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'message': f'Error: {str(e)}'}), 500

###################################### MINERÍA ###################################################
# ============================================
# ENDPOINT: MINERÍA CLASIFICACIÓN
# ============================================
@app.route('/api/mineria/clasificacion', methods=['GET'])
@token_required
def mineria_clasificacion(current_user_id):
    """
    Clasifica días de LA SEMANA ACTUAL (Lunes-Domingo)
    Muestra TODOS los días de la semana
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener fecha de inicio de esta semana (Lunes)
        from datetime import datetime, timedelta
        hoy = datetime.now()
        inicio_semana = hoy - timedelta(days=hoy.weekday())  # Lunes
        
        # Obtener consumo de TODA la semana (incluyendo Sáb/Dom)
        cursor.execute("""
            SELECT 
                DATE(dato_encendido) as fecha,
                DAYOFWEEK(dato_encendido) as dia_semana,
                SUM(
                    CASE 
                        WHEN estado = 'apagado' THEN consumo_kW
                        WHEN estado = 'encendido' THEN 
                            (648 * TIMESTAMPDIFF(SECOND, dato_encendido, NOW())) / 3600000.0
                        ELSE 0
                    END
                ) as consumo_kWh,
                COUNT(*) as num_usos,
                SUM(
                    CASE 
                        WHEN estado = 'apagado' THEN encendido_segundos
                        WHEN estado = 'encendido' THEN TIMESTAMPDIFF(SECOND, dato_encendido, NOW())
                        ELSE 0
                    END
                ) / 3600.0 as horas_uso
            FROM consumo
            WHERE 
                DATE(dato_encendido) >= %s
                AND DATE(dato_encendido) <= CURDATE()
            GROUP BY DATE(dato_encendido)
            ORDER BY fecha ASC
        """, (inicio_semana.date(),))
        
        datos = cursor.fetchall()
        cursor.close()
        conn.close()
        
        # Preparar resultados
        resultados = []

        for dia in datos:
            consumo = float(dia['consumo_kWh'])
    
            # Clasificación
            if consumo >= 20.0:
                clasificacion = 'Alto'
            elif consumo >= 10.0:
                clasificacion = 'Medio'
            else:
                clasificacion = 'Bajo'
    
            resultados.append({
                'fecha': dia['fecha'].strftime('%Y-%m-%d'),
                'consumo_kWh': round(consumo, 2),
                'clasificacion': clasificacion,
                'num_usos': dia['num_usos'],
                'horas_uso': round(float(dia['horas_uso']), 1),
                'dia_semana': dia['dia_semana'],
                'metodo': 'Reglas + Tiempo real'
            })

        # Detectar patrones automáticamente
        patron_detectado = ""
        anomalia_detectada = ""

        if len(resultados) >= 3:
            consumos = [r['consumo_kWh'] for r in resultados]
            promedio = sum(consumos) / len(consumos)
    
            # Patrón: Todos altos
            if all(c >= 20.0 for c in consumos):
                patron_detectado = "Semana de uso intensivo constante"
    
            # Patrón: Todos bajos
            elif all(c < 10.0 for c in consumos):
                patron_detectado = "Semana de bajo uso (posible vacaciones)"
    
            # Detectar anomalías
            for resultado in resultados:
                consumo = resultado['consumo_kWh']
                # Si un día consume 50% menos que el promedio
                if consumo < promedio * 0.5 and promedio > 10:
                    dia_semana_num = resultado['dia_semana']
                    if dia_semana_num >= 2:  # Evitar error si es Domingo (1)
                        dia_nombre = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'][dia_semana_num - 2]
                    else:
                        dia_nombre = 'Dom'
                    anomalia_detectada = f"{dia_nombre} tuvo consumo inusualmente bajo ({consumo:.1f} kWh vs promedio {promedio:.1f} kWh)"
                    break
    
        return jsonify({
            'success': True,
            'resultados': resultados,
            'patron': patron_detectado,
            'anomalia': anomalia_detectada,
            'semana_actual': True,
            'total_dias': len(resultados)
        }), 200
        
    except Exception as e:
        print(f"Error en clasificación: {e}")
        return jsonify({
            'success': False,
            'message': f'Error: {str(e)}'
        }), 500
        
# ============================================
# ENDPOINT: MINERÍA CLUSTERING (K-MEANS)
# ============================================
@app.route('/api/mineria/clustering', methods=['GET'])
@token_required
def mineria_clustering(current_user_id):
    """
    Agrupa las últimas semanas por patrones de consumo usando K-Means
    INCLUYE consumo actual de registros abiertos
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        
        # Obtener consumo semanal INCLUYENDO registros abiertos
        cursor.execute("""
            SELECT 
                YEARWEEK(dato_encendido, 1) as semana_id,
                DATE(DATE_SUB(dato_encendido, INTERVAL WEEKDAY(dato_encendido) DAY)) as fecha_inicio,
                SUM(
                    CASE 
                        WHEN estado = 'apagado' THEN consumo_kW
                        WHEN estado = 'encendido' THEN 
                            (648 * TIMESTAMPDIFF(SECOND, dato_encendido, NOW())) / 3600000.0
                        ELSE 0
                    END
                ) as consumo_kWh,
                COUNT(*) as num_usos,
                SUM(
                    CASE 
                        WHEN estado = 'apagado' THEN encendido_segundos
                        WHEN estado = 'encendido' THEN TIMESTAMPDIFF(SECOND, dato_encendido, NOW())
                        ELSE 0
                    END
                ) / 3600.0 as horas_uso
            FROM consumo
            WHERE 
                dato_encendido >= DATE_SUB(CURDATE(), INTERVAL 12 WEEK)
            GROUP BY YEARWEEK(dato_encendido, 1)
            HAVING consumo_kWh > 0
            ORDER BY semana_id DESC
        """)
        
        datos = cursor.fetchall()
        cursor.close()
        conn.close()
        
        if not datos or len(datos) < 3:
            return jsonify({
                'success': True,
                'resultados': [],
                'clusters_info': [],
                'mensaje': 'Se necesitan al menos 3 semanas de datos'
            }), 200
        
        # Preparar datos para clustering
        X = np.array([[
            float(d['consumo_kWh']),
            d['num_usos'],
            float(d['horas_uso'])
        ] for d in datos])
        
        # Normalizar datos
        X_normalized = (X - X.mean(axis=0)) / (X.std(axis=0) + 1e-10)
        
        # Aplicar K-Means (3 clusters)
        n_clusters = min(3, len(datos))
        kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10)
        clusters = kmeans.fit_predict(X_normalized)
        
        # Calcular centroides originales
        centroides_originales = []
        for i in range(n_clusters):
            mask = clusters == i
            centroide = X[mask].mean(axis=0)
            centroides_originales.append(centroide)
        
        # Ordenar clusters por consumo (0=bajo, 1=medio, 2=alto)
        orden = np.argsort([c[0] for c in centroides_originales])
        mapeo_clusters = {old: new for new, old in enumerate(orden)}
        clusters = np.array([mapeo_clusters[c] for c in clusters])
        
        # Nombres de clusters
        nombres_clusters = ['Bajo consumo', 'Consumo medio', 'Alto consumo']
        if n_clusters == 2:
            nombres_clusters = ['Bajo consumo', 'Alto consumo']
        
        # Preparar resultados
        resultados = []
        for i, dato in enumerate(datos):
            cluster_id = int(clusters[i])
            resultados.append({
                'fecha_inicio': dato['fecha_inicio'].strftime('%Y-%m-%d'),
                'consumo_kWh': round(float(dato['consumo_kWh']), 1),
                'num_usos': dato['num_usos'],
                'horas_uso': round(float(dato['horas_uso']), 1),
                'cluster': cluster_id,
                'cluster_nombre': nombres_clusters[cluster_id]
            })
        
        # Información de clusters
        clusters_info = []
        for i in range(n_clusters):
            semanas_cluster = [r for r in resultados if r['cluster'] == i]
            if semanas_cluster:
                consumo_promedio = np.mean([s['consumo_kWh'] for s in semanas_cluster])
                clusters_info.append({
                    'cluster': i,
                    'nombre': nombres_clusters[i],
                    'num_semanas': len(semanas_cluster),
                    'consumo_promedio': round(consumo_promedio, 1)
                })
        
        return jsonify({
            'success': True,
            'resultados': resultados,
            'clusters_info': clusters_info,
            'total_semanas': len(resultados),
            'metodo': 'K-Means + Tiempo real'
        }), 200
        
    except Exception as e:
        print(f"Error en clustering: {e}")
        return jsonify({
            'success': False,
            'message': f'Error: {str(e)}'
        }), 500

# ============================================
# INICIAR GENERADOR AUTOMÁTICO EN BACKGROUND
# ============================================
def iniciar_cron_reportes():
    """Inicia el generador automático de reportes en un hilo separado"""
    hilo = threading.Thread(target=generar_reporte_automatico, daemon=True)
    hilo.start()
    print("Generador automático de reportes iniciado")

# Llamar esta función al final del archivo, antes de if __name__ == '__main__':
# iniciar_cron_reportes()  # ← DESHABILITADO TEMPORALMENTE

# ============================================
# EJECUTAR SERVIDOR
# ============================================
if __name__ == '__main__':
    if ES_RASPBERRY:
        sincronizar_bd_con_gpio_al_arrancar()
    
    # Iniciar scheduler de temporizadores
    print("Activando verificador de temporizadores...")
    scheduler.add_job(
        func=verificar_temporizadores,
        trigger="interval",
        seconds=5,  # Cada 60 segundos (1 minuto)
        id='verificar_temporizadores'
    )
    scheduler.start()
    print("Scheduler activado\n")
    # AGREGAR REPORTE AUTOMÁTICO
    scheduler.add_job(
        func=generar_reporte_automatico_semanal,
        trigger='cron',
        day_of_week='sun',  # Domingo
        hour=23,
        minute=59,
        id='reporte_semanal'
    )
    print("Reportes automáticos: Domingos 23:59\n")

    print("\n" + "="*60)
    print("SISTEMA AULA 208 - CONTROL DE ILUMINACIÓN")
    print("="*60 + "\n")
    
    app.run(host='0.0.0.0', port=3000, debug=False, threaded=True)