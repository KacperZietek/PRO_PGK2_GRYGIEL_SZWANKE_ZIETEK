## Skrypt obsługujący menu główne gry, w tym tworzenie serwera i dołączanie jako klient.
extends Control

## Domyślny port używany do komunikacji sieciowej.
const PORT = 7000

## Instancja klienta/serwera ENet.
var peer = ENetMultiplayerPeer.new()

## Pole tekstowe do wpisywania adresu IP serwera.
@onready var ip_address_field = $VBoxContainer/IPAddress

## Wyskakujące okienko z ustawieniami hostowania nowej gry.
@onready var host_popup = $HostPopup

## Inicjalizuje stan w menu i weryfikuje komunikaty o ewentualnym rozłączeniu z poprzedniej gry.
func _ready():
	Global.match_over = false
	Global.match_started = false
	if Global.disconnect_reason != "":
		%Label.text = Global.disconnect_reason
		%Label.show()
		Global.disconnect_reason = ""
	else:
		%Label.hide()

## Otwiera okienko konfiguracji serwera po kliknięciu przycisku Host.
func _on_host_button_pressed():
	$ClickSound.play()
	host_popup.show()
	
## Próbuje połączyć gracza z serwerem o podanym adresie IP po kliknięciu przycisku Join.
func _on_join_button_pressed():
	$ClickSound.play()
	await get_tree().create_timer(0.3).timeout
	if $VBoxContainer/NicknameInput.text != "":
		Global.my_nickname = $VBoxContainer/NicknameInput.text
	# Dołączanie do serwera (Client)
	var address = ip_address_field.text
	if address == "":
		address = "127.0.0.1"
		
	var error = peer.create_client(address, PORT)
	if error != OK:
		print("Błąd podczas próby dołączenia: ", error)
		return
		
	multiplayer.multiplayer_peer = peer
	start_game()

## Zmienia aktywną scenę na główną mapę po udanym nawiązaniu połączenia.
func start_game():
	print("Połączono! Zmieniam scenę na mapę...")
	get_tree().change_scene_to_file("res://main.tscn")

## Tworzy nowy serwer multiplayer i ładuje mapę.
func _on_start_game_button_pressed():
	$ClickSound.play()
	await get_tree().create_timer(0.3).timeout
	if $VBoxContainer/NicknameInput.text != "":
		Global.my_nickname = $VBoxContainer/NicknameInput.text
	Global.kills_to_win = int(%SpinBox.value)
	# Tworzenie serwera (Host)
	var error = peer.create_server(PORT)
	if error != OK:
		print("Błąd podczas tworzenia serwera: ", error)
		return
	
	multiplayer.multiplayer_peer = peer
	start_game()

## Zamyka okienko hostowania i wraca do głównego widoku menu.
func _on_cancel_button_pressed():
	$ClickSound.play()
	host_popup.hide()

## Przełącza odtwarzanie muzyki w menu głównym.
func _on_music_button_pressed():
	var click = get_node_or_null("ClickSound")
	if click:
		click.play()
		
	var music = $MenuMusic
	var btn = %MusicButton
	
	if music.playing:
		music.stop()
		btn.text = "MUSIC ON"
	else:
		music.play()
		btn.text = "MUSIC OFF"

## Wyłącza aplikację po kliknięciu przycisku wyjścia.
func _on_exit_button_pressed():
	$ClickSound.play()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
