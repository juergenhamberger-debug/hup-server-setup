# hup-server-setup

Öffentliches Einrichtungsskript für den Server des HUP-Befragungstools (Dr. Hamberger & Partner).
Enthält keine Geheimnisse. Der Anwendungscode liegt in einem privaten Repository; der Server erhält
dafür einen eigenen Deploy-Schlüssel mit reinem Leserecht.

Aufruf einmalig als root auf einem frischen Ubuntu-24.04-Server:

```
curl -fsSL https://raw.githubusercontent.com/juergenhamberger-debug/hup-server-setup/main/setup.sh | bash
```
