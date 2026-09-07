# Taskbar Hero / Northflank v8

## Qué corrige

Tu log mostraba que Ubuntu sí alcanzó a hacer:

- `Setting up steam:i386`
- `Setting up steam-installer`

pero el comando de instalación terminó con un error posterior al escribir
`/var/lib/apt/extended_states`. El script antiguo interpretaba cualquier
código distinto de cero como "Steam package unavailable", aunque Steam ya
había sido desempaquetado/configurado.

Además, el launcher de Steam en Ubuntu está en:

`/usr/games/steam`

y el script antiguo comprobaba `command -v steam`. En un contenedor, `/usr/games`
no siempre está en PATH, por lo que podía decir "Steam command not found"
aunque el launcher existiera.

## Solución v8

- Steam se instala durante el BUILD.
- No se ejecuta apt/dpkg durante el arranque.
- Se añade `/usr/games` al PATH.
- Se inicia explícitamente `/usr/games/steam`.
- Se instala `udev`, por lo que existe `udevadm`.
- Se usa un usuario normal `steamuser`.
- Se instala `x11-utils` para comprobar Xvfb.
- Se añade una sesión D-Bus mínima.
- Se fuerza renderizado Mesa por software.
- Steam se inicia con `-no-cef-sandbox`.
- noVNC sigue disponible aunque Steam salga pronto.

## Northflank

Puerto:
- 6080
- HTTP

Ruta:
- `/vnc.html`

Contraseña VNC:
- `cambiar123`

Puedes cambiarla con:
`VNC_PASSWORD=otra_clave`

## Persistencia

Para conservar login, Steam y juegos entre reemplazos del contenedor,
monta un volumen persistente en:

`/home/steamuser`

## 512 MB

El escritorio mínimo es pequeño, pero el Steam moderno usa `steamwebhelper`
(Chromium/CEF). 512 MB puede ser suficiente para el contenedor base y aun así
Steam puede ser terminado por falta de memoria durante login/actualización.
La meta final es autenticar e instalar primero y luego reducir procesos para
dejar Taskbar Hero funcionando con el mínimo de RAM.
