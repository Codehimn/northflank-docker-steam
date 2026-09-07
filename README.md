# Taskbar Hero Northflank Docker v2

Cambios incluidos:
- Añadido x11vnc.
- Corregida cadena gráfica:
  Xvfb -> x11vnc -> websockify -> noVNC.
- Puerto público recomendado en Northflank:
  6080 HTTP.

Acceso:
http://TU_DOMINIO:6080/vnc.html

Esta versión permite entrar por navegador para realizar login/captcha.

Después de conseguir la sesión de Steam se puede optimizar:
- eliminar noVNC
- eliminar Openbox
- ejecutar solamente Wine + Taskbar Hero para reducir RAM.
