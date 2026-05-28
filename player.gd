## Skrypt odpowiedzialny za fizykę, logikę walki, poruszanie się oraz zarządzanie stanem gracza w trybie wieloosobowym.
class_name Player extends CharacterBody3D

#region STAŁE I ZMIENNE WĘZŁÓW
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera = $Camera3D
@onready var raycast = $Camera3D/RayCast3D
@onready var hud = $HUD
@onready var health_bar = %HealthBar
@onready var ammo_label = $HUD/AmmoLabel
@onready var scoreboard = $HUD/Scoreboard
@onready var score_list = $HUD/Scoreboard/ScoreList
@onready var shoot_sound = $Camera3D/ShootSound
@onready var hitmarker_sound = $HitmarkerSound
@onready var reload_sound = $ReloadSound
@onready var footstep_sound = $FootstepSound
@onready var anim_player = $Camera3D/WeaponPivot/revolver/AnimationPlayer
@onready var land_sound = $LandSound
@onready var muzzle_flash = $Camera3D/WeaponPivot/MuzzleFlash
@onready var weapon_pivot = $Camera3D/WeaponPivot
@onready var anim_tree = $Ch28_nonPBR/AnimationTree

## Zmienna synchronizowana w sieci, odpowiadająca za pozycję kropki na wykresie animacji.
@export var sync_blend_pos := Vector2.ZERO
#endregion

#region ZMIENNE EKSPORTOWANE
## Maksymalna liczba punktów zdrowia, z którą gracz zaczyna rundę.
@export var health: int = 100

## Nazwa gracza wyświetlana w grze.
@export var nickname = ""

## Aktualna liczba zabójstw gracza.
@export var kills = 0

## Aktualna liczba zgonów gracza.
@export var deaths = 0
#endregion

#region ZMIENNE STANU GRACZA I BRONI
var default_weapon_pos: Vector3
var bob_time = 0.0
var bob_speed = 12.0   
var bob_amount = 0.009  

var was_in_air = false 
var last_fall_speed = 0.0
var footstep_timer = 0.0
var footstep_delay = 0.4

var is_dead = false
var is_frozen = false
var max_ammo = 6
var current_ammo = 6
var fire_rate = 0.7
var can_shoot = true
var is_reloading = false

## Wymagana liczba zabójstw, aby wygrać mecz.
var kills_to_win = 5
#endregion

#region FUNKCJE CYKLU ŻYCIA I INICJALIZACJI
## Ustawia autorytet multiplayer w oparciu o unikalną nazwę węzła (ID peera).
func _enter_tree():
	set_multiplayer_authority(name.to_int())

## Inicjalizuje gracza, ustawia kamerę, ukrywa HUD dla innych graczy i spawnuje na mapie.
func _ready():
	randomize()
	hud.hide()
	default_weapon_pos = weapon_pivot.position
	if is_multiplayer_authority():
		weapon_pivot.show()
		$Ch28_nonPBR.hide()
		
		if not Global.match_started:
			is_frozen = true
			_show_waiting_screen()
			
			if multiplayer.is_server():
				multiplayer.peer_connected.connect(_on_peer_joined)
		
		var spawn_points_node = get_tree().current_scene.get_node_or_null("SpawnPoints")
		
		if spawn_points_node and spawn_points_node.get_child_count() > 0:
			var points = spawn_points_node.get_children()
			global_position = points.pick_random().global_position
		else:
			global_position = Vector3(randf_range(-5, 5), 5, randf_range(-5, 5))
	
		health_bar.value = health
		nickname = Global.my_nickname
		hud.show()
		$HUD/Scoreboard.hide()
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		await get_tree().create_timer(0.5).timeout
		rpc("broadcast_system_message", nickname + " dołączył do gry.")
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		weapon_pivot.hide()
		$Ch28_nonPBR.show()
		hud.hide()
	raycast.add_exception($HeadHitbox)
	raycast.add_exception($BodyHitbox)
	
	update_ammo_label()

## Obsługuje zerwanie połączenia z serwerem i przekierowuje do menu.
func _on_server_disconnected():
	if Global.match_over: 
		return
	print("Host left!\nReturning to menu...")
	Global.disconnect_reason="Connection lost! Host left game."
	multiplayer.multiplayer_peer = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://menu.tscn")
#endregion

#region FUNKCJE GŁÓWNEJ PĘTLI I RUCHU
## Przechwytuje wejścia myszy i przetwarza ruchy kamery w trybie pierwszej osoby.
## [param event] Przechwycone zdarzenie wejścia.
func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE: return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * 0.005)
		camera.rotate_x(-event.relative.y * 0.005)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

## Główna pętla fizyki. Obsługuje grawitację, poruszanie się, skakanie, bujanie bronią oraz strzelanie.
## [param delta] Czas trwania ostatniej klatki w sekundach.
func _physics_process(delta):
	if not is_multiplayer_authority(): return
	
	if not is_on_floor():
		velocity.y -= gravity * delta
		was_in_air = true 
		last_fall_speed = velocity.y 
	elif is_on_floor() and was_in_air:
		was_in_air = false
		if last_fall_speed < -3.0:
			rpc("play_land_sound")
		last_fall_speed = 0.0
	
	if is_dead or is_frozen:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		move_and_slide()
		return 

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var target_blend = Vector2(input_dir.x, -input_dir.y)
		var current_blend = anim_tree.get("parameters/Ruch/blend_position")
		
		if current_blend != null:
			var smooth_blend = current_blend.lerp(target_blend, delta * 20.0)
			anim_tree.set("parameters/Ruch/blend_position", smooth_blend)
			sync_blend_pos = smooth_blend

		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
			
			if is_on_floor():
				footstep_timer -= delta
				if footstep_timer <= 0:
					rpc("play_footstep")
					footstep_timer = footstep_delay
				
				if not is_reloading:
					bob_time += delta
					var bob_y = sin(bob_time * bob_speed) * bob_amount
					var bob_x = cos(bob_time * bob_speed / 2.0) * bob_amount
					weapon_pivot.position = default_weapon_pos + Vector3(bob_x, bob_y, 0)
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
			footstep_timer = 0.0
			bob_time = 0.0
			weapon_pivot.position = weapon_pivot.position.lerp(default_weapon_pos, delta * 10.0)

		if Input.is_action_just_pressed("shoot") and current_ammo > 0 and can_shoot and not is_reloading and not Global.match_over and not is_frozen:
			can_shoot = false
			current_ammo -= 1 
			update_ammo_label() 
			
			rpc("play_shoot_sound")
			var tween = create_tween()
			var original_rot = weapon_pivot.rotation_degrees
			tween.tween_property(weapon_pivot, "rotation_degrees:x", original_rot.x + 15.0, 0.05)
			tween.tween_property(weapon_pivot, "rotation_degrees:x", original_rot.x, 0.2)
			
			if raycast.is_colliding():
				var target = raycast.get_collider()
				if target.is_in_group("Head") or target.is_in_group("Body"):
					var hit_player = target.get_parent() 
					var damage = 0
					hitmarker_sound.play()
					
					if target.is_in_group("Head"):
						print("HEADSHOT!")
						damage = 100 
					elif target.is_in_group("Body"):
						print("Trafienie w ciało!")
						damage = 25
						
					var my_id = str(multiplayer.get_unique_id())
					hit_player.rpc("receive_damage", damage, my_id, nickname)
					
			await get_tree().create_timer(0.05).timeout
			if current_ammo > 0:
				await get_tree().create_timer(fire_rate).timeout
				can_shoot = true
			elif current_ammo <= 0 and not is_reloading:
				can_shoot = true
				reload()
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
		  
## Reaguje na precyzyjne wejścia, jak wywołanie przeładowania lub tabeli wyników.
## [param event] Przechwycone zdarzenie wejścia.
func _input(event):
	if not is_multiplayer_authority(): return
	if event.is_action_pressed("reload") and current_ammo < max_ammo and not is_reloading:
		reload()
	if event.is_action_pressed("ui_focus_next"):
		update_scoreboard()
		scoreboard.show()
	elif event.is_action_released("ui_focus_next"):
		scoreboard.hide()

## Synchronizuje stan animacji (ruchu nóg) u innych graczy w sieci.
## [param _delta] Czas trwania ostatniej klatki.
func _process(_delta):
	if not is_multiplayer_authority() and anim_tree != null:
		anim_tree.set("parameters/Ruch/blend_position", sync_blend_pos)
#endregion

#region LOGIKA BRONI I WALKI
## Przeładowuje broń odtwarzając animację i dźwięk. Blokuje strzelanie na czas trwania akcji.
func reload():
	print("RELOADING...")
	is_reloading = true
	ammo_label.text = "RELOADING..."
	reload_sound.play()

	if anim_player.has_animation("reload_revolver"):
		anim_player.play("reload_revolver", -1.0, 1.248)
	
	await get_tree().create_timer(2.57).timeout
	current_ammo = max_ammo
	is_reloading = false
	update_ammo_label()
	print("Reloaded!")

## Odświeża informacje o ilości amunicji w interfejsie HUD.
func update_ammo_label():
	if is_multiplayer_authority():
		ammo_label.text = "Ammo: " + str(current_ammo) + " / " + str(max_ammo)
#endregion

#region SYSTEM ZDROWIA, ŚMIERCI I ODRADZANIA
## Zadaje obrażenia graczowi i sprawdza, czy nastąpiła śmierć. Funkcja wywoływana zdalnie (RPC).
## [param damage] Ilość odebranych punktów zdrowia.
## [param attacker_id] Unikalne ID sieciowe gracza, który zadał obrażenia.
## [param attacker_name] Nickname strzelca wyświetlany w Killfeedzie.
@rpc("any_peer", "call_local")
func receive_damage(damage, attacker_id, attacker_name):
	if is_dead or Global.match_over or is_frozen:
		return

	if is_multiplayer_authority():
		health -= damage
		health_bar.value = health
		
		if health <= 0:
			deaths += 1
			var attacker = get_parent().get_node_or_null(attacker_id)
			if attacker:
				attacker.rpc("add_kill")
			rpc("update_killfeed", attacker_name, nickname)
			die_and_respawn()

## Obsługuje zgon gracza, ukrywa jego model, wywołuje czarny ekran śmierci i odradza po odliczeniu.
func die_and_respawn():
	if is_dead: return
	is_dead = true
	
	print("💀 ZGINĄŁEŚ!")
	
	$Ch28_nonPBR.hide()
	$CollisionShape3D.set_deferred("disabled", true)
	$HeadHitbox/CollisionShape3D.set_deferred("disabled", true)
	$BodyHitbox/CollisionShape3D.set_deferred("disabled", true)
	
	var death_screen = ColorRect.new()
	death_screen.name = "DeathScreen"
	death_screen.color = Color(0, 0, 0, 0.8)
	
	$HUD.add_child(death_screen)
	death_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var killfeed = $HUD.get_node_or_null("KillfeedContainer")
	if killfeed:
		$HUD.move_child(killfeed, -1)
		
	var scoreboard_ui = $HUD.get_node_or_null("Scoreboard")
	if scoreboard_ui:
		$HUD.move_child(scoreboard_ui, -1)
	
	var death_label = Label.new()
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER 
	death_label.add_theme_font_size_override("font_size", 40)
	death_label.add_theme_color_override("font_color", Color(1, 0, 0))
	
	death_screen.add_child(death_label)
	death_label.anchors_preset = Control.PRESET_CENTER
	death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	death_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	
	await get_tree().create_timer(0.3).timeout
	global_position = Vector3(0, 1000, 0)

	for i in range(3, 0, -1):
		if not is_instance_valid(death_label):
			return 
		if Global.match_over:
			if is_instance_valid(death_screen):
				death_screen.queue_free()
			return
		
		death_label.text = "ZGINĄŁEŚ!\nOdrodzenie za " + str(i) + "..."
		await get_tree().create_timer(1.0).timeout 
	
	if is_instance_valid(death_screen):
		death_screen.queue_free()
	
	global_position = _get_safe_spawn_position()
	
	velocity = Vector3.ZERO 
	was_in_air = false
	last_fall_speed = 0.0
	
	$Ch28_nonPBR.show()
	if is_multiplayer_authority():
		$Ch28_nonPBR.hide() 
	$CollisionShape3D.set_deferred("disabled", false)
	$HeadHitbox/CollisionShape3D.set_deferred("disabled", false)
	$BodyHitbox/CollisionShape3D.set_deferred("disabled", false)
	
	health = 100
	health_bar.value = health
	is_dead = false

## Zwraca współrzędne najbezpieczniejszego punktu odrodzenia (najdalej od przeciwników).
func _get_safe_spawn_position() -> Vector3:
	var spawn_points_node = get_tree().current_scene.get_node_or_null("SpawnPoints")
		
	if not spawn_points_node or spawn_points_node.get_child_count() == 0:
		return Vector3(randf_range(-5, 5), 5, randf_range(-5, 5))
		
	var all_points = spawn_points_node.get_children()
	var MIN_SAFE_DISTANCE = 22.5
	var safe_points = []
	
	var other_players = []
	for p in get_parent().get_children():
		if p != self and "is_dead" in p and not p.is_dead:
			other_players.append(p)
			
	if other_players.is_empty():
		return all_points.pick_random().global_position
		
	for point in all_points:
		var is_safe = true
		for enemy in other_players:
			if point.global_position.distance_to(enemy.global_position) < MIN_SAFE_DISTANCE:
				is_safe = false
				break 
		if is_safe:
			safe_points.append(point)

	if safe_points.size() > 0:
		return safe_points.pick_random().global_position
		
	var best_point = all_points[0]
	var max_distance_to_closest_enemy = -1.0
	
	for point in all_points:
		var closest_enemy_dist = 9999.0
		for enemy in other_players:
			var dist = point.global_position.distance_to(enemy.global_position)
			if dist < closest_enemy_dist:
				closest_enemy_dist = dist
				
		if closest_enemy_dist > max_distance_to_closest_enemy:
			max_distance_to_closest_enemy = closest_enemy_dist
			best_point = point
			
	return best_point.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
#endregion

#region LOGIKA SIECIOWA, POSTĘPU I UI
## Wyświetla komunikat systemowy (czat) dla wszystkich połączonych klientów.
## [param msg] Treść wiadomości do wyświetlenia.
@rpc("any_peer", "call_local")
func broadcast_system_message(msg):
	var my_id = str(multiplayer.get_unique_id())
	var my_player = get_parent().get_node_or_null(my_id)
	
	if my_player:
		my_player.show_local_message(msg)

## Formatuje i dodaje wpis wiadomości systemowej do Logu Zdarzeń w interfejsie HUD.
## [param msg] Treść wiadomości.
func show_local_message(msg):
	if is_multiplayer_authority():
		var label = Label.new()
		label.text = msg
		label.add_theme_color_override("font_color", Color(1, 0.8, 0)) 
		
		$HUD/EventLog.add_child(label)
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(label):
			label.queue_free()

## Dodaje jedno zabójstwo do statystyk gracza i sprawdza, czy osiągnięto cel potrzebny do wygrania meczu.
@rpc("any_peer", "call_local")
func add_kill():
	if is_multiplayer_authority():
		if Global.match_over: return
		kills += 1
		
		if kills >= Global.kills_to_win:
			rpc("show_victory_screen", nickname)

## Przekazuje sygnał zakończenia meczu i zleca wygenerowanie ekranu zwycięstwa.
## [param winner_name] Nickname gracza, który wygrał mecz.
@rpc("any_peer", "call_local")
func show_victory_screen(winner_name):
	if Global.match_over: return
	Global.match_over = true
	
	var my_id = multiplayer.get_unique_id()
	var local_player = get_parent().get_node_or_null(str(my_id))
	
	if local_player:
		local_player._display_victory_label(winner_name)

## Generuje wizualny element tekstowy informujący o wygranej na ekranie (Złoty napis).
## [param winner_name] Imię zwycięzcy.
func _display_victory_label(winner_name):
	var old_death_screen = $HUD.get_node_or_null("DeathScreen")
	if old_death_screen:
		old_death_screen.queue_free()
		
	var victory_label = Label.new()
	victory_label.text = "WINNER WINNER CHICKEN DINNER!\n" + winner_name + " WINS!!"
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 45)
	victory_label.add_theme_color_override("font_color", Color(1, 0.8, 0))
	victory_label.add_theme_constant_override("outline_size", 12)
	victory_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	
	$HUD.add_child(victory_label)
	victory_label.anchors_preset = Control.PRESET_CENTER
	victory_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	victory_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	victory_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	
	if $HUD.has_node("Crosshair"):
		$HUD/Crosshair.hide()
	
	_quit_to_menu_delayed(winner_name)

## Czeka ustaloną liczbę sekund po wygranej, a następnie rozłącza sesję i wraca do menu.
## [param winner_name] Nazwa zwycięzcy przekazywana do zmiennej [member Global.disconnect_reason].
func _quit_to_menu_delayed(winner_name):
	await get_tree().create_timer(5.0).timeout
	Global.disconnect_reason = "Zwycięzca: " + winner_name
	multiplayer.multiplayer_peer = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://menu.tscn")

## Aktualizuje tabelę wyników widoczną pod klawiszem TAB, pobierając statystyki wszystkich graczy.
func update_scoreboard():
	for child in score_list.get_children():
		child.queue_free()
		
	var players = get_parent().get_children()
	var header = Label.new()
	header.text = "--- TABELA WYNIKÓW ---"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_list.add_child(header)
	
	for p in players:
		var row = Label.new()
		row.text = str(p.nickname) + " | Kills: " + str(p.kills) + " | Deaths: " + str(p.deaths)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_list.add_child(row)

## Wyświetla na ekranie komunikat informujący, że brakuje graczy do startu rozgrywki.
func _show_waiting_screen():
	var label = Label.new()
	label.name = "WaitLabel"
	label.text = "OCZEKIWANIE NA PRZECIWNIKA..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	$HUD.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)

## Sprawdza warunki startowe, gdy nowy gracz dołącza do serwera.
## [param id] Unikalne ID sieciowe nowo podłączonego gracza.
func _on_peer_joined(id):
	if Global.match_started:
		await get_tree().create_timer(1.5).timeout
		rpc_id(id, "begin_match_sequence")
		
	elif not Global.match_started and multiplayer.get_peers().size() >= 1:
		await get_tree().create_timer(0.5).timeout
		rpc("begin_match_sequence")

## Pinging do poszczególnych klientów o rozpoczęciu lokalnej sekwencji rozruchu meczu (odliczanie).
@rpc("any_peer", "call_local")
func begin_match_sequence():
	if Global.match_started: return
	
	var my_id = multiplayer.get_unique_id()
	var local_player = get_parent().get_node_or_null(str(my_id))
	
	if local_player:
		local_player._run_local_countdown()

## Uruchamia odliczanie przedmeczowe na danym kliencie ("3..2..1..FIGHT") i odblokowuje kontrolę.
func _run_local_countdown():
	var spawn_points_node = get_tree().current_scene.get_node_or_null("SpawnPoints")
	
	if spawn_points_node and spawn_points_node.get_child_count() > 0:
		var points = spawn_points_node.get_children()
		var all_ids = Array(multiplayer.get_peers())
		if not all_ids.has(1):
			all_ids.append(1) 
		all_ids.sort()
		
		var my_rank = all_ids.find(multiplayer.get_unique_id())
		var spawn_index = my_rank % points.size()
		global_position = points[spawn_index].global_position
	else:
		global_position = Vector3(randf_range(-5, 5), 5, randf_range(-5, 5))
	
	health = 100
	health_bar.value = health
	current_ammo = max_ammo
	update_ammo_label()
	
	var label = $HUD.get_node_or_null("WaitLabel")
	if label:
		for i in range(3, 0, -1):
			if not is_instance_valid(label): return
			label.text = "- MECZ ROZPOCZNIE SIĘ ZA -\n" + str(i)
			$BeepSound.play()
			await get_tree().create_timer(1.0).timeout
			
		if is_instance_valid(label):
			label.text = "FIGHT!"
			label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			$FightSound.play()
			await get_tree().create_timer(1.0).timeout
			label.queue_free()

	Global.match_started = true
	is_frozen = false
	await get_tree().create_timer(0.05).timeout

## Uruchamia u każdego klienta proces dodania nowego wpisu do Killfeeda (Prawy górny róg).
## [param killer_name] Imię zabójcy.
## [param victim_name] Imię ofiary.
@rpc("any_peer", "call_local")
func update_killfeed(killer_name: String, victim_name: String):
	var my_id = str(multiplayer.get_unique_id())
	var local_player = get_parent().get_node_or_null(my_id)
	
	if local_player:
		local_player._add_killfeed_entry(killer_name, victim_name)

## Funkcja wewnętrzna odpowiedzialna za wygenerowanie elementu tekstowego i wstawienie go do Killfeeda.
## Usuwa najstarsze wiadomości, gdy ich liczba przekroczy limit.
func _add_killfeed_entry(killer_name: String, victim_name: String):
	var feed_container = $HUD.get_node_or_null("KillfeedContainer")
	if not feed_container: 
		return 

	var kill_entry = Label.new()
	kill_entry.text = killer_name + " smashed " + victim_name 
	
	kill_entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kill_entry.add_theme_font_size_override("font_size", 20)
	kill_entry.add_theme_constant_override("outline_size", 4)
	kill_entry.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	feed_container.add_child(kill_entry)
	
	if feed_container.get_child_count() > 5:
		feed_container.get_child(0).queue_free()
	
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(kill_entry):
		kill_entry.queue_free()
#endregion

#region EFEKTY AUDIO-WIZUALNE (RPC)
## Odtwarza efekty wystrzału (dźwięk oraz światło lufy) u wszystkich graczy widzących strzelca.
@rpc("any_peer", "call_local")
func play_shoot_sound():
	shoot_sound.play()
	if muzzle_flash != null: 
		muzzle_flash.show()
	var world_flash = get_node_or_null("Ch28_nonPBR/Skeleton3D/BoneAttachment3D/MuzzleFlashWorld")
	if world_flash != null: 
		world_flash.show()
	await get_tree().create_timer(0.05).timeout
	if muzzle_flash != null: muzzle_flash.hide()
	if world_flash != null: world_flash.hide()
	
## Odtwarza dźwięk kroków ze zróżnicowanym tonem (pitch), aby symulować naprzemienne stawianie nóg.
@rpc("any_peer", "call_local")
func play_footstep():
	footstep_sound.pitch_scale = randf_range(0.55, 1.15)
	footstep_sound.play()

## Odtwarza dźwięk twardego lądowania przy powrocie na podłoże z dużej wysokości.
@rpc("any_peer", "call_local")
func play_land_sound():
	land_sound.pitch_scale = randf_range(0.85, 1.0)
	land_sound.play()
#endregion
