## Globalny singleton (AutoLoad) przechowujący stan gry oraz metadane gracza.
extends Node

## Nickname gracza wyświetlany w grze.
var my_nickname = "Gracz"

## Powód rozłączenia z serwerem, wyświetlany po powrocie do menu.
var disconnect_reason = ""

## Liczba zabójstw wymagana do wygrania meczu.
var kills_to_win = 5

## Flaga określająca, czy mecz dobiegł końca.
var match_over = false

## Flaga określająca, czy mecz się rozpoczął (zakończono odliczanie).
var match_started = false

## Synchronizuje limit zabójstw z serwera do wszystkich podłączonych klientów.
## [param limit] Nowa wartość wymaganych zabójstw.
@rpc("authority", "call_remote")
func sync_kills_limit(limit):
	kills_to_win = limit
	print("Serwer ustawił limit fragów na: ", kills_to_win)
