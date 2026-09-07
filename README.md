# TaskbarHero Northflank V6

Esta versión corrige el fallo de build de WineHQ.

Cambio principal:
- Eliminado apt-key de WineHQ (fallaba por gpg-agent).
- Usa paquetes oficiales Ubuntu para Wine.

Incluye:
- Ubuntu 22.04
- Wine
- Xvfb
- Openbox
- x11vnc con password
- noVNC
- intento de instalar Steam automáticamente

Acceso:
 /vnc.html

Password:
 cambiar123

Nota:
El objetivo de esta versión es tener un contenedor que construya y abra escritorio.
Después se ajusta Steam/TBH según los errores que aparezcan.
