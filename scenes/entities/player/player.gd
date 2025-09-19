extends CharacterBody3D

@export var step_audio_paths: Array[NodePath] = []
var step_audios: Array[AudioStreamPlayer3D] = []
var _next_step_index := 0

# Variable para alternar entre los dos audios.
var _next_step_is_first := true

# Duración (segundos) con la que cada sonido de paso debe sonar.
@export var step_sound_duration := 1.25

# Referencia al nodo AnimatedSprite3D para cambiar la animación.
@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D

# Velocidad de movimiento (unidades por segundo).
# Ajusta este valor desde el editor si querés que el personaje vaya más rápido o más lento.
@export var base_speed := 10.0

# Velocidad de carrera (unidades por segundo).
# Se usa si querés implementar una tecla para correr.
@export var run_speed := 10.0

# Fuerza con la que el jugador empuja a otros objetos.
# Ajusta este valor para que el empuje se sienta más o menos fuerte.
@export var push_force := 50.0

# Referencia a la cámara del juego.
# Se usa para que "adelante" del jugador coincida con hacia donde mira la cámara.
@onready var camera = $CameraController/Camera3D

# Entrada de movimiento en el plano horizontal.
# Vector2(x, y): x = izquierda/derecha, y = adelante/atrás. Valores entre -1 y 1.
var movement_input := Vector2.ZERO

func _ready() -> void:
	# Construye la lista de AudioStreamPlayer3D a partir de los NodePath exportados.
	for p in step_audio_paths:
		var n = get_node_or_null(p)
		if n and n is AudioStreamPlayer3D:
			step_audios.append(n)

func _physics_process(delta: float) -> void:
	# Esta función se ejecuta en cada paso físico (no en cada frame de render).
	# 'delta' es el tiempo en segundos desde la última llamada: se usa para que el
	# movimiento sea consistente sin importar la velocidad de la máquina.
	complex_movement(delta)

	# Actualiza la animación según la tecla presionada.
	set_animation()

	# Aplica la velocidad calculada al cuerpo y gestiona colisiones automáticamente.
	move_and_slide()
	
	set_sound()
	
	physics_logic()

func complex_movement(delta: float) -> void:
	if not is_on_floor():
		# Si no estamos en el suelo, aplicamos gravedad.
		# Esto permite que el personaje caiga si está en el aire.
		velocity += get_gravity() * delta

	# 1) Leemos la entrada del teclado (left/right/forward/backward).
	#    Entradas configuradas en Proyecto -> Configuración del Proyecto -> Mapa de Entrada.
	# 2) Rotamos esa entrada para que esté alineada con la cámara,
	#    así "adelante" siempre será hacia donde la cámara mira.
	movement_input = Input.get_vector("left", "right", "forward", "backward").rotated(-camera.global_rotation.y)
	# vel_2d contiene la velocidad actual en el plano horizontal (X,Z).
	var vel_2d = Vector2(velocity.x, velocity.z)
	
	var acceleration := 4.0 * delta

	# Comprobamos si el jugador está corriendo (tecla "run" presionada).
	var is_running = Input.is_action_pressed("run")

	if movement_input != Vector2.ZERO:
		# Si hay entrada de la tecla "run": calculamos la velocidad objetivo (camina o corre).
		var speed = run_speed if is_running else base_speed
		
		# Si hay entrada: aplicamos una aceleración suave.
		# Multiplicamos por 'delta' para que la aceleración dependa del tiempo.
		vel_2d += movement_input * speed * acceleration
		
		# Limitamos la magnitud para que no supere la velocidad máxima (speed).
		vel_2d = vel_2d.limit_length(speed)
		
		# Actualizamos la velocidad 3D conservando la componente vertical (Y),
		# que puede venir de la gravedad o de un salto.
		velocity = vec2_to_vec3(vel_2d, velocity.y)
	else:
		# Si no hay entrada: desaceleramos suavemente hacia cero.
		# Esto evita detenerse de golpe y da una sensación más natural.
		vel_2d = vel_2d.move_toward(Vector2.ZERO, base_speed * 4.0 * acceleration)
		velocity = vec2_to_vec3(vel_2d, velocity.y)

# Alternativa simple de movimiento (sin aceleración). 
# Rota al jugador instantáneamente según la entrada de la cámara.
# func simple_movement(delta: float) -> void:
#     movement_input = Input.get_vector("left", "right", "forward", "backward").rotated(-camera.global_rotation.y)
#     velocity = Vector3(movement_input.x, 0, movement_input.y) * base_speed

# Convierte un Vector2 (X,Z) en Vector3 respetando la altura (Y) dada.
# Usamos esto para combinar la velocidad horizontal con la velocidad vertical y evitar repetir código.
func vec2_to_vec3(v2: Vector2, y: float) -> Vector3:
	return Vector3(v2.x, y, v2.y)

# Función XOR para booleanos (no existe en GDScript).
# Devuelve verdadero si uno y solo uno de los dos valores es verdadero.
func xor(b1: bool, b2: bool) -> bool:
	return (b1 and not b2) or (b2 and not b1)

# Cambia la animación según la tecla presionada.
func set_animation() -> void:
	var pressing_left := Input.is_action_pressed("left")
	var pressing_right := Input.is_action_pressed("right")
	var pressing_backward := Input.is_action_pressed("backward")
	var pressing_forward := Input.is_action_pressed("forward")
	
	# Si presionamos izquierda o derecha (pero no ambas), 
	# reproducimos "sidewalk" (caminar de lado)
	# y volteamos el sprite si es necesario.
	if (xor(pressing_left, pressing_right)):
		animated_sprite.play("sidewalk")
		animated_sprite.flip_h = pressing_right
	# Si presionamos atrás, reproducimos "backwalk" (caminar hacia atrás).
	# Esto tiene prioridad sobre "sidewalk" si se presionan ambas.
	elif pressing_backward:
		animated_sprite.play("backwalk")
	elif pressing_forward:
		animated_sprite.play("frontwalk")
	# Si no se presiona ninguna tecla o presionamos izquierda y derecha a la vez, 
	# reproducimos "idle" (quieto).
	else:
		animated_sprite.play("idle")

# Esta función se llama después de move_and_slide() para manejar interacciones.
# Aquí, comprobamos si el jugador ha chocado con un RigidBody3D y lo empujamos.
func physics_logic() -> void:
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)

		var collider = collision.get_collider()
		if collider is RigidBody3D:
			# Para evitar que la fuerza se acumule y cause inestabilidad, solo la aplicamos
			# si el jugador está activamente intentando moverse hacia el objeto.
			# Usamos `movement_input` porque representa la intención del jugador, mientras que `velocity`
			# es modificado por `move_and_slide()` al colisionar, lo que haría que la condición falle.
			
			# Obtenemos la dirección de la colisión en el plano horizontal.
			var collision_normal_2d = Vector2(collision.get_normal().x, collision.get_normal().z)
			
			# Si la intención de movimiento del jugador (`movement_input`) es opuesta a la normal de la colisión, aplicamos la fuerza.
			# El umbral de -0.5 asegura que solo empujemos cuando nos movemos mayormente "contra" el objeto.
			if movement_input.dot(collision_normal_2d) < -0.5:
				# Usamos `apply_force` en lugar de `apply_central_force` para que el objeto rote.
				# `apply_central_force` solo empuja desde el centro, sin causar rotación.
				# `apply_force` necesita la posición del impacto (relativa al centro del objeto) para calcular el torque.
				var force_position = collision.get_position() - collider.global_transform.origin
				collider.apply_force(-collision.get_normal() * push_force, force_position)
		
func set_sound() -> void:
	# Considerar pequeño umbral para evitar ruido por valores casi cero.
	var is_moving := velocity.length() > 0.1

	if step_audios.size() == 0:
		return

	# ¿Alguno de los audios está sonando?
	var any_playing := false
	for p in step_audios:
		if p.playing:
			any_playing = true
			break

	if is_moving:
		# Si ninguno está sonando, reproducimos el siguiente en la lista (rotando).
		if not any_playing:
			var idx := _next_step_index % step_audios.size()
			var player := step_audios[idx]
			player.play()
			_next_step_index += 1
	else:
		# Parar todos los audios al dejar de moverse.
		for p in step_audios:
			if p.playing:
				p.stop()
