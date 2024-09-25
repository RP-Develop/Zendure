# Zendure - Fhem
 ## Zendure - Fhem Integration

Mit diesem Fhem Modul können die Daten für ein Zendure Login erzeugt werden. Mit diesen Zugangsdaten kann anschließend ein MQTT Client konfiguriert werden. Damit können Werte empfangen, wie auch gesendet (published) werden.

### Voraussetzung:
Ein zweiter Zendure Account ist notwendig. Im Hauptaccount wird sodann der Zugriff für den Zweiten freigegeben. Notwendig dafür ist eine zweite Emailadresse.

### Einschränkung:
Die App mit dem zweiten Account kann nicht ohne weiteres benutzt werden. Erfolgt dies trotzdem, kommen beide Anmeldungen (Fhem + Zendure 2. Account) in Konflikt und ggf. wird der Token ungültig.
Da der Token die ClientId im MQTT Client ist, muss bei Ungültigkeit die Konfiguration geändert werden. Nicht schön, ist aber vorerst so.

### Fhem
**define \<name\> Zendure \<user\> \<password\>**

User und Password sind die vom zweiten Zendure Account.

**set \<name\> Login**

Ruft einen Token ab, wie auch die Device List. Der Token ist gültig, mindestens so lange, bis keine neuer abgefragt wird, z.B. über die Zendure App (zweiter Account).
Der Token wird als clientId für einen MQTT Client benutzt.

In den Readings werden weiter Informationen zum Anlegen des Zugangs für den MQTT Server angegeben. Dies ist der MQTT Server, mit dem auch die originale Zendure App kommuniziert.

**get  \<name\>  AccessToken**

Zeigt die Antwort der Tokenabfrage.

**get  \<name\>  DeviceList**

Zeigt die Antwort der DeviceList abfrage.

**get  \<name\>  ConfigProposal**

Zeigt ein vollständig ausgefülltes Set zur Konfiguration eines MQTT2_CIENT und MQTT2_DEVICE, wie auch ein Vorschlag zur Konfiguration einer Bridge im Mosquitto.

### Quellen

[GitHub Zendure/developer-device-data-report](https://github.com/Zendure/developer-device-data-report)
[GitHub nograx/ioBroker.zendure-solarflow](https://github.com/nograx/ioBroker.zendure-solarflow)