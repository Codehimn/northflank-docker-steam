# Taskbar Hero Northflank Docker

Diseñado para:
- Ubuntu minimal
- Xvfb (pantalla virtual)
- Openbox (gestor gráfico mínimo)
- noVNC para login manual
- Wine para ejecutar juegos Windows

Flujo recomendado:

1. Crear servicio en Northflank.
2. Construir la imagen.
3. Entrar por noVNC.
4. Hacer login de Steam y resolver captcha.
5. Descargar/copiar Taskbar Hero.
6. Cambiar start.sh para lanzar el ejecutable.

Ejemplo:

wine /opt/taskbarhero/game/TBH.exe

Para ahorrar RAM después del login:
- quitar noVNC
- quitar Openbox si no es necesario
- arrancar solamente Xvfb + Wine + juego
