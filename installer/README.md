# Release Windows

Esta carpeta ya quedo preparada para empaquetar la aplicacion real de este proyecto con Inno Setup.

## Que toma el instalador

- Nombre del producto: `FullTech`
- Ejecutable: `fulltech_app.exe`
- Icono del setup: `apps/fulltech_app/windows/runner/resources/app_icon.ico`
- Release Flutter esperado: `apps/fulltech_app/build/windows/x64/runner/Release`
- Redistributables: `installer/redist/VC_redist.x64.exe` y `installer/redist/MicrosoftEdgeWebView2RuntimeInstallerX64.exe`

## Generar el setup

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" .\installer\setup.iss /DMyAppVersion=1.0.0+1 /DMyAppVersionInfo=1.0.0.1
```

Antes de compilar el setup, genera la release de Windows:

```powershell
Set-Location .\apps\fulltech_app
flutter build windows --release
```

Despues compila el instalador desde la raiz del repo:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" .\installer\setup.iss /DMyAppVersion=1.0.0+1 /DMyAppVersionInfo=1.0.0.1
```

El ejecutable final queda en `installer/output/setup.exe`.

Si quieres forzar otra version puntual:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" .\installer\setup.iss /DMyAppVersion=1.2.0+5 /DMyAppVersionInfo=1.2.0.5
```

## Overrides opcionales en setup.iss

`setup.iss` acepta estos defines opcionales:

- `MyAppPublisher`
- `MyAppPublisherURL`
- `MyAppSupportURL`
- `SupportLabel`
- `MyAppLicenseFile`
- `BrandWizardImage`
- `BrandWizardSmallImage`
