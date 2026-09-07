# Taskbar Hero Northflank Docker v4

Versión mejorada para primera instalación.

Incluye:
- Ubuntu 22.04 minimal
- Xvfb virtual display
- Openbox ligero
- x11vnc con password
- noVNC web
- limpieza de temporales
- logs separados
- creación segura del password

Acceso:

/vnc.html

Password:

cambiar123

Mejoras respecto a v3:
- No recrea password cada reinicio.
- Logs para diagnóstico.
- Más tolerante a reinicios.
- Menos basura temporal.
- Instalación más ligera.

Siguiente optimización:
Después de entrar y dejar Steam autenticado:
1. Persistir carpeta Steam.
2. Arrancar directamente Taskbar Hero.
3. Eliminar noVNC/Openbox para bajar RAM.
