# Zendure
 Control of Zendure

Mit diesem Fhem Modul kann ein Login für Zendure erzeigt werden. Anschließend kann der Zugriff auf alle relevanten Daten über MQTT erfolgen, wie auch Werte published werden.

Voraussetzung:
Ein zweiter Zendure Account ist notwendig. Im Hauptaccount  wird sodann der Zugriff für den zweiten freigegeben. Notwendig dafür ist eine zweite Emailadresse. Der Vorgang ist selbsterklärend.

Einschränkung:
Die App mit dem zweiten Account kann nicht ohne weiteres benutzt werden. Erfolgt dies trotzdem, kommen beide Anmeldungen (Fhem + Zendure 2. Account) in Konflikt und ggf. wird der Token ungültig.
Da der Token die ClientId im MQTT Client ist, muss bei Ungültigkeit die Konfiguration geändert werden. Nicht schön, ist aber vorerst so.

Fhem
define <name> Zendure <user> <password> 
User und Password sind die vom zweiten Zendure Account.

set <name>  Login
Ruft einen Token ab, wie auch die Device List. Der Token ist gültig, mindestens so lange, bis keine neuer abgefragt wird, z.B. über die Zendure App (zweiter Account).
Der Token wird als clientId für einen MQTT Client benutzt.

In den Readings werden weiter Informationen zum Anlegen des Zugangs für den MQTT Server angegeben. Dies ist der MQTT Server, mit dem auch die originale Zendure App kommuniziert.

get  <name>  AccessToken
Zeigt die Antwort der Tokenabfrage.

get  <name>  DeviceList
Zeigt die Antwort der DeviceList abfrage.

get  <name>  ConfigProposal
Zeit ein vollständig ausgefülltes Set zur Konfiguration eines MQTT2_CIENT und MQTT2_DEVICE, wie auch ein Vorschlag zur Konfiguarion einer Bridge im Mosquitto.