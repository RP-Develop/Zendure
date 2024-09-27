# Zendure - Fhem
 ## Zendure - Fhem Integration

**ZendureUtils.pm**

Diese Modul ergänzt einen MQTT2_CLIENT mit dem Zendure Login und erzeugt automatisch für jedes Zendure Gerät ein MQTT2_DEVICE. 

**76_Zendure.pm**

Mit diesem Fhem Modul können die Daten für ein Zendure Login erzeugt werden. Mit diesen Zugangsdaten kann anschließend ein MQTT Client konfiguriert werden. 

### Voraussetzung:
Ein zweiter Zendure Account ist notwendig. Im Hauptaccount wird der Zugriff für den Zweiten freigegeben. Notwendig dafür ist eine zweite Emailadresse.

### Einschränkung:
Die App mit dem zweiten Account kann nicht ohne weiteres benutzt werden. Erfolgt dies trotzdem, kommen beide Anmeldungen (Fhem + Zendure 2. Account) in Konflikt und ggf. wird der Token ungültig.

### Fhem  - ZendureUtils.pm
**define \<name\> MQTT2_CLIENT \<name\>**
attr \<name\> username Username (
attr \<name\> connectFn {use ZendureUtils;;Zendure_connect($NAME,"global",1)}
set \<name\> password Password 

Der MQTT2_CLIENT wird normalerweise mit HOST:Port definiert. In diesem Falle nicht. Es muss aber ein Parameter angegeben werden, der dann in der DEF steht. Hier kann man den \<name\> benutzen. 

Username und Password sind vom zweiten Zendure Account. 

Die Parameter im Ausdruck **Zendure_connect($NAME,"global",1)** haben folgende Funktion:

2. Parameter "global" - bezieht sich auf den Zendure Server. Es gibt einen Global und einen EU. Als Parameterwert kann global | Global | v2 für den globalen und eu | EU für den EU Server verwendet werden. 

3. Parameter 1 - 1 erstellt automatisch die MQTT2_DEVICES, 0 erstellt keine automatisch.


### Fhem  - 76_Zendure.pm
**define \<name\> Zendure \<user\> \<password\>**

User und Password sind die vom zweiten Zendure Account.

**set \<name\> Login**

Ruft einen Token ab, wie auch die Device List. Der Token ist gültig, mindestens so lange, bis ein Neuer abgefragt wird, z.B. über die Zendure App (zweiter Account).
Der Token wird als clientId für einen MQTT Client benutzt.

In den Readings werden weiter Informationen zum Anlegen des Zugangs für den MQTT Server angegeben. Dies ist der MQTT Server, mit dem auch die originale Zendure App kommuniziert.

**get  \<name\>  AccessToken**

Zeigt die Antwort der Tokenabfrage.

**get  \<name\>  DeviceList**

Zeigt die Antwort der DeviceList abfrage.

**get  \<name\>  ConfigProposal**

Zeigt ein vollständig ausgefülltes Set zur Konfiguration eines MQTT2_CIENT und MQTT2_DEVICE, wie auch ein Vorschlag zur Konfiguration einer Bridge im Mosquitto.

### Quellen
Fhem - LandroidUtils.pm

[GitHub Zendure/developer-device-data-report](https://github.com/Zendure/developer-device-data-report)

[GitHub nograx/ioBroker.zendure-solarflow](https://github.com/nograx/ioBroker.zendure-solarflow)

