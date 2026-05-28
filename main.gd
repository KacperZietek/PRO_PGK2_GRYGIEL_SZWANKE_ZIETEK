## Główny skrypt zarządzający instancją świata gry oraz podłączaniem graczy.
extends Node3D

## Referencja do spakowanej sceny gracza, używana do instancjonowania.
var player_scene = preload("res://player.tscn")

## Inicjalizuje serwer i łączy sygnały sieciowe z odpowiednimi funkcjami.
func _ready():
	randomize()
	if multiplayer.is_server():
		add_player(1)
		multiplayer.peer_connected.connect(add_player)
		multiplayer.peer_disconnected.connect(_remove_player)

## Dodaje nowego gracza do świata gry, przypisując mu unikalne ID i losową pozycję startową.
## [param peer_id] Unikalny identyfikator sieciowy gracza.
func add_player(peer_id):
	var player = player_scene.instantiate()
	player.name = str(peer_id)
	
	var random_pos = Vector3(randf_range(-5, 5), 5, randf_range(-5, 5))
	player.position = random_pos
  
	$Players.add_child(player)
	
	if multiplayer.is_server() and peer_id != 1:
		Global.rpc_id(peer_id, "sync_kills_limit", Global.kills_to_win)

## Usuwa gracza ze świata po rozłączeniu i wysyła globalne powiadomienie na czat.
## [param id] Identyfikator sieciowy gracza, który opuścił grę.
func _remove_player(id):
	var player_to_remove = $Players.get_node_or_null(str(id)) 
	
	if player_to_remove:
		var escaping_nick = player_to_remove.nickname 
		player_to_remove.queue_free()
		
		var host_player = $Players.get_node_or_null("1")
		if host_player:
			host_player.rpc("broadcast_system_message", escaping_nick + " left the game (Reason: Skill issue).")
