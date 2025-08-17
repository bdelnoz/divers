# 1) Supprime le préfixe pour repartir propre
rm -rf ~/wine/copilot32

# 2) Recrée un préfixe 32 bits tout neuf
WINEPREFIX=~/wine/copilot32 WINEARCH=win32 winecfg

# 3) Installe les bases OLE manuellement AVANT le .NET
WINEPREFIX=~/wine/copilot32 winetricks ole32 oleaut32

# 4) Installe .NET 4.8
WINEPREFIX=~/wine/copilot32 winetricks dotnet48

# 5) Vérifie
WINEPREFIX=~/wine/copilot32 winecfg
