# Taskbar Hero / Northflank v9

Esta versión diagnostica el error real antes de seguir reintentando Steam.

## Por qué

Steam para Linux todavía usa un bootstrap x86 de 32 bits en:
`~/.steam/debian-installation/ubuntu12_32/steam`

El error:
`Exec format error`

puede ocurrir si el kernel del runtime no permite ejecutar binarios ELF x86
de 32 bits. Instalar paquetes i386 no basta: el kernel también debe soportarlos.

v9 ejecuta automáticamente:

`/lib/ld-linux.so.2 --help`

Si funciona:
- imprime `IA32 TEST: OK`
- limpia archivos `.part`
- valida el bootstrap descargado
- reintenta Steam hasta 2 veces

Si falla:
- imprime `IA32 TEST: FAILED`
- deja noVNC funcionando
- evita descargar/reextraer Steam en bucle

## Northflank

Puerto: 6080 HTTP
Ruta: /vnc.html
Password: cambiar123

## Qué línea necesito del próximo log

Busca y copia solamente desde:

`=== PLATFORM CHECK ===`

hasta:

`IA32 TEST: ...`

y, si dice OK, las últimas líneas de Steam.
