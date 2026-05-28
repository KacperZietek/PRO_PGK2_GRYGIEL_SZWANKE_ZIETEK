## Skrypt obsługujący nakładkę menu pauzy w trakcie trwania rozgrywki.
extends CanvasLayer

## Ukrywa menu pauzy natychmiast po załadowaniu sceny.
func _ready():
	hide()

## Przechwytuje globalne zdarzenia wejścia i przełącza widoczność menu pauzy (np. po wciśnięciu ESC).
## [param event] Przechwycone zdarzenie wejścia (klawiatura/mysz).
func _unhandled_input(event):
	if event.is_action_pressed("pause"):
		if visible:
			hide()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			show()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Zamyka całkowicie grę z poziomu menu pauzy.
func _on_button_pressed():
	$ClickSound.play()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

## Przerywa połączenie sieciowe i przenosi gracza powrotem do menu głównego.
func _on_return_button_pressed():
	$ClickSound.play()
	await get_tree().create_timer(0.3).timeout
	multiplayer.multiplayer_peer = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://menu.tscn")
