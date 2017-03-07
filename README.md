# DxClusterInterface

Mittels ''telnet db0erf.de 41113'' kann man ein textbasierte Verbindung zum DXSpider herstellen. http://wiki.dxcluster.org/index.php/German

Man kann Filter selbst definieren, aber pro Benutzer-Rufzeichen nur einen Filter. Da man mehrere Filter-Einstellungen braucht, ist hier etwas zu überlegen.
Das DXCluster senden die DX-Meldungen über telnet nach dem Verbindungsaufbau. Beispiel

``DX de VE1SKY:    50280.0  N3RG         FN74IU<MS>FM29KI msk144 rox    1522Z FN74``

Diesen Text kann man dann entgegen nehmen, DX de entfernen und die Leerzeichen ebenfalls. Dann in einer möglichst sinnvollen und kompakten Form zusammenfassen und für die REST API vorbereiten.

Dazu kann entweder eine in der Skriptsprache enthaltene Methode verwendet werden oder curl auf der Linux-Console. Beipiel (hier zum Absenden von pers. Nachrichten, aber im Prinzip ähnlich)

``curl -H "Content-Type: application/json" -X POST -u USER:PASSWORD -d '{ "text": "FUNKRUFTEXT", "callSignNames": ["RUFZEICHEN"], "transmitterGroupNames": ["SENDERGRUPPENNAME"], "emergency": false }' URL/calls``

Die Bahandlund der Rubriken ist zur Zeit noch in Überarbeitung https://github.com/DecentralizedAmateurPagingNetwork/Core/issues/68 , kann aber schon mal getestet werden. API Beschreibung hier: https://github.com/DecentralizedAmateurPagingNetwork/Core/wiki/Beschreibung%20der%20REST%20API

Vorschlag der Filter-Klassen
* KW
* KW-CW
* VHF/UHF/SHF
* 4m/5m/6m
