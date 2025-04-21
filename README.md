# Zendure - Fhem
## Zendure - Fhem Integration

**ZendureUtils.pm**

Diese Modul ergänzt einen MQTT2_CLIENT mit einem Zendure Login und erzeugt für jedes Zendure Gerät ein MQTT2_DEVICE auf Wunsch automatisch. 

**76_Zendure.pm**

Mit diesem Fhem Modul können die Daten für ein Zendure Login erzeugt werden. Mit diesen Zugangsdaten kann anschließend ein beliebiger MQTT Client konfiguriert werden. 

**update**

`update add https://raw.githubusercontent.com/RP-Develop/Zendure/main/controls_Zendure.txt`

### Voraussetzung:
Ein zweiter Zendure Account ist notwendig. Im Hauptaccount wird der Zugriff für den Zweiten freigegeben. Notwendig dafür ist eine zweite Emailadresse.

### Einschränkung:
Die App mit dem zweiten Account kann nicht ohne weiteres benutzt werden. Erfolgt dies trotzdem, kommen beide Anmeldungen (Fhem + Zendure 2. Account) in Konflikt und ggf. wird der Token ungültig. Selbiges gilt bei Nutzung von ZendureUtil.pm und 76_Zendure.pm mit gleichem Account.

### Fhem  - ZendureUtils.pm
`define <name> MQTT2_CLIENT <name>`

`attr <name> username Username`

`attr <name> connectFn {use ZendureUtils;;Zendure_connect($NAME,"global",1)}`

`set <name> password Password`

Ein MQTT2_CLIENT wird normalerweise mit HOST:Port definiert. In diesem Falle nicht. Es muss aber mindestens ein Parameter angegeben werden, der dann in der DEF steht. Hier kann man den \<name\> benutzen. 

Username und Password sind vom zweiten Zendure Account. 

Die Parameter im Ausdruck `Zendure_connect($NAME,"global",1)` haben folgende Funktion:

2. Parameter "global" - bezieht sich auf den Zendure Server. Es gibt einen 'Global' und einen 'EU'. Als Parameterwert kann ' global | Global | v2 ' für den Globalen und ' eu | EU ' für den EU Server verwendet werden. Welcher Server benutzt wird, wird bei der Erstanmeldung festgelegt. Beachte: Ein Wechsel löscht alle gespeicherten Daten.

3. Parameter 1 - ' 1 ' erstellt automatisch alle MQTT2_DEVICE's der Zendure Geräte in der Device List, ' 0 ' erstellt keine.

`set <name> connect`

Ruft einen neuen Token ab, wie auch die Device List und baut eine Verbindung zum MQTT Server auf. Der Token ist 30 Tage gültig, mindestens aber so lange, bis ein anderer Client sich mit den selben Nutzerdaten anmeldet.

`set <name> disconnect`

Beendet die Vervindung zum MQTT Server.

`attr <name> updateInterval`

default = 0 : in Minuten : Ruft nach Interval per Polling die Statistikdaten für den aktuellen Tag ab, wie auch die Daten der gesamten Laufzeit. Die Daten werden als Readings in das entsprechende MQTT2_DEVICE gespeichert. 

updateIntervall = 0 | updateInterval delete : stoppt das Polling

`attr <name> expert`

default = 0 : 0 | 1 : Es werden nur gerätespezifische Statistikdaten angezeigt. Derzeit sind diese für den HUB 2000 und Hyper 2000 definiert. Mit expert = 1 werden alle abrufbaren Daten angezeigt. 

### Fhem  - 76_Zendure.pm
`define <name> Zendure <username> <password> <server>`

Username und Password sind die vom zweiten Zendure Account. Werden anschließend verschlüsselt im DEF angezeigt.

Parameter "server" - bezieht sich auf den Zendure Server. Es gibt einen 'Global' und einen 'EU'. Als Parameterwert kann ' global | Global | v2 ' für den Globalen und ' eu | EU ' für den EU Server verwendet werden. Welcher Server benutzt wird, wird bei der Erstanmeldung festgelegt. Beachte: Ein Wechsel löscht alle gespeicherten Daten.

`set <name> Login`

Ruft einen neuen Token ab, wie auch die Device List. Der Token ist 30 Tage gültig, mindestens aber so lange, bis ein anderer Client sich mit den selben Nutzerdaten anmeldet. 

Der Token kann als clientId für einen MQTT Client benutzt werde. In den Readings werden weiter Informationen zum Anlegen des Zugangs für den MQTT Server angegeben. Dies ist der MQTT Server, mit dem auch die originale Zendure App kommuniziert.

`set <name> Update`

Ruft erneut die DeviceList, wie auch die Statistikdaten erneut ab. Es wird kein neuer Token erzeugt.

`get <name> Account`

Zeigt die verschlüsselten Zugansdaten an.

`get <name> ConfigProposal`

Zeigt ein vollständig ausgefülltes Set zur Konfiguration eines MQTT2_CIENT und MQTT2_DEVICE, wie auch ein Vorschlag zur Konfiguration einer Bridge im Mosquitto.

`get <name> showData AccessToken`

Zeigt die Antwort der Token Abfrage.

`get <name> showData DeviceList`

Zeigt die Antwort der DeviceList Abfrage.

`get <name> showData Energy`

Zeigt die Antwort der Energy Statistik Abfrage.

`get <name> showData Electric`

Zeigt die Antwort der Electric Statistik Abfrage.

`get <name> showData Details`

Zeigt die Antwort der Detail Abfrage.

`attr <name> updateInterval`

default = 0 : in Minuten : Ruft nach Interval per Polling die Statistikdaten für den aktuellen Tag ab, wie auch die Daten der gesamten Laufzeit. Die Daten werden als Readings in das entsprechende MQTT2_DEVICE gespeichert. 

updateIntervall = 0 | updateInterval delete : stoppt das Polling

`attr <name> expert`

default = 0 : 0 | 1 : Es werden nur gerätespezifische Statistikdaten angezeigt. Derzeit sind diese für den HUB 2000 und Hyper 2000 definiert. Mit expert = 1 werden alle abrufbaren Daten angezeigt. 

### Quellen
Fhem - LandroidUtils.pm

Vielen Dank an Rudolf Koenig, für den initialen Tipp connectFn im MQTT2_CLIENT zu nutzen.

[GitHub Zendure/developer-device-data-report](https://github.com/Zendure/developer-device-data-report)

[GitHub nograx/ioBroker.zendure-solarflow](https://github.com/nograx/ioBroker.zendure-solarflow)

