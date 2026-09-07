# Northflank v14

Put all files directly in repository root.

Expose:
- port 6080
- protocol HTTP

Recommended persistent volume:
- /data

Default VNC password:
- cambia12

The most important next log is:

=== WINDOWS PE COMPATIBILITY CHECK ===
PE64 TEST: ...
PE32 TEST: ...

If PE32 is OK, this version also tries to bypass SteamSetup.exe by extracting
the Steam bootstrapper directly.
