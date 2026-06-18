# CocoaWget

Interfaz gráfica nativa (Cocoa / AppKit) para [GNU wget](https://www.gnu.org/software/wget/) en macOS.
CocoaWget actúa como un **gestor de descargas** que envuelve el binario `wget` de línea de
comandos: añade una cola de descargas, edición visual de las opciones de wget, descarga
recursiva de sitios, reanudación de transferencias, soporte de proxy y más, sin necesidad de
abrir el Terminal.

> **Estado del proyecto:** código histórico (≈2008) escrito en Objective‑C con *Manual Reference
> Counting*. Compila contra el SDK de macOS con objetivo de despliegue **10.13**, pero el binario
> `wget` incluido es de arquitecturas **i386 + PowerPC** y **no se ejecuta en macOS moderno**
> (macOS 10.15+ eliminó el soporte de 32 bits). Consulta el plan de modernización en
> [ROADMAP.md](ROADMAP.md).

---

## Características

- **Cola de descargas** con tabla de elementos, estado, porcentaje y velocidad en tiempo real.
- **Reordenación por arrastrar y soltar** dentro de la cola; también se pueden soltar URLs desde
  el navegador o desde texto.
- **Añadir varias URLs a la vez** (una por línea).
- **Expansión de URLs secuenciales**: `http://host/img[000-999].jpg` genera automáticamente las
  999 URLs correspondientes (`expandSequencialURL:` en [CWArrayController.m](CWArrayController.m)).
- **Reanudar descargas** interrumpidas (`wget -c`).
- **Comprobación de marca de tiempo** (`wget -N`) para descargar solo si el archivo remoto es más
  reciente.
- **Descarga recursiva de sitios** (`wget -r`) con control de:
  - nivel de profundidad (`-l`),
  - ámbito: *no subir de directorio* (`--no-parent`), *mismo host* o *abarcar hosts*
    (`--span-hosts`),
  - filtros de extensión permitida/denegada (`-A` / `-R`),
  - filtros de dominio permitido/denegado (`-D` / `--exclude-domains`),
  - filtros de directorio permitido/denegado (`--include-directories` / `--exclude-directories`).
- **Autenticación HTTP** (usuario y contraseña) y cabecera **Referer** personalizada.
- **Captura automática del Referer desde Safari** mediante AppleScript
  ([GetURLFromSafari.scpt](GetURLFromSafari.scpt)).
- **Soporte de proxy** (HTTP/FTP, con usuario y contraseña) escrito en `~/.wgetrc`, con
  copia de seguridad y restauración del `.wgetrc` del usuario.
- **Opciones globales**: número de reintentos (`-t`), *timeout* (`-T`), tamaño máximo de descarga
  (`-Q`), *User-Agent* personalizado, FTP pasivo (`--passive-ftp`), conversión de enlaces a rutas
  relativas (`-k`) y un campo libre para pasar **opciones arbitrarias de wget**.
- **Descarga automática** mediante un temporizador que va lanzando elementos en espera respetando
  un máximo de conexiones simultáneas (global y por dominio).
- **Acciones al finalizar**: abrir el archivo descargado, guardar la URL de origen como comentario
  Finder del archivo (vía AppleScript) y eliminar de la lista los elementos completados.
- **Cajón de registro (log)** que muestra la salida en vivo de wget para el elemento seleccionado.
- **Localización** en inglés, alemán, japonés y **español**.

---

## Arquitectura

CocoaWget es una aplicación AppKit basada en *Cocoa Bindings* y `NSUserDefaultsController`. No
contiene código de red propio: delega toda la transferencia en el ejecutable `wget` incluido en el
*bundle*, lanzado como subproceso (`NSTask`), y analiza su salida estándar/estándar de error línea
a línea para actualizar la interfaz.

| Componente | Archivo | Responsabilidad |
|---|---|---|
| `main` | [main.m](main.m) | Punto de entrada (`NSApplicationMain`). |
| `MainController` | [MainController.h](MainController.h) · [MainController.m](MainController.m) | Ciclo de vida de la app, selección de carpeta de descargas, diálogos de cierre, apertura de ayuda. |
| `CWArrayController` | [CWArrayController.h](CWArrayController.h) · [CWArrayController.m](CWArrayController.m) | Subclase de `NSArrayController`; gestiona la cola, el *parsing* de URLs, arrastrar y soltar, el temporizador de auto‑descarga, la persistencia de la lista y el cajón de log. |
| `DownloadItem` | [DownloadItem.h](DownloadItem.h) · [DownloadItem.m](DownloadItem.m) | Modelo de cada descarga; construye los argumentos de wget, lanza/detiene el `NSTask`, analiza el progreso y gestiona el `~/.wgetrc`. |
| Interfaz | `*.lproj/MainMenu.xib` | Ventana principal, panel de preferencias y menús (Interface Builder). |
| AppleScript | [GetURLFromSafari.scpt](GetURLFromSafari.scpt) | Obtiene la URL de la pestaña activa de Safari para usarla como Referer. |
| Binario | `wget` | Ejecutable de GNU wget empaquetado en `Contents/Resources`. |

### Flujo de una descarga

1. El usuario añade una o varias URLs; `CWArrayController` las normaliza, expande secuencias y crea
   un `DownloadItem` por cada una.
2. Al iniciar (manual o por el temporizador), `DownloadItem` construye la lista de argumentos
   (`getArgument`) a partir de las preferencias del usuario y de las opciones del propio elemento.
3. Hace copia de seguridad del `~/.wgetrc`, escribe uno temporal con la configuración de proxy y
   lanza `wget` con `NSTask`, redirigiendo `stdout`/`stderr` a un `NSPipe`.
4. La salida se lee en segundo plano; `parseDownloadingProgress:` extrae porcentaje y velocidad, y
   `parseLog:` detecta errores y la ruta final del archivo.
5. Al terminar el proceso se restaura el `~/.wgetrc`, se marca el estado (`Finished` / `Error`) y se
   ejecutan las acciones de fin de descarga.

### Persistencia

La cola y la configuración se guardan en los *user defaults* de la aplicación
(`NSUserDefaultsController`). La lista se serializa como un array de diccionarios bajo la clave
`list` (ver `saveList` / `loadList`).

---

## Compilación

### Requisitos

- macOS con Xcode (Command Line Tools incluidas).
- El proyecto se abre con **Xcode** (`CocoaWget.xcodeproj`). Es un formato de proyecto antiguo
  (`objectVersion = 45`); Xcode ofrecerá actualizar la configuración recomendada.

### Pasos

```sh
# Compilar desde la línea de comandos
xcodebuild -project CocoaWget.xcodeproj -configuration Release

# O abrir en Xcode y pulsar ⌘R
open CocoaWget.xcodeproj
```

> ⚠️ **Importante:** el ejecutable `wget` versionado en el repositorio es una *Mach‑O universal
> binary* de arquitecturas `i386` y `ppc_7400`, incompatible con macOS actual. Antes de poder
> ejecutar la app necesitas **reconstruir `wget` para `arm64` + `x86_64`** con
> [buildwget.sh](buildwget.sh). Consulta el [ROADMAP.md](ROADMAP.md) para los detalles de la
> modernización.

### Reconstruir el binario wget

El script [buildwget.sh](buildwget.sh) descarga, compila e instala un **wget moderno, universal
(arm64 + x86_64) y autónomo** (con OpenSSL enlazado estáticamente, sin dependencias de Homebrew),
apto para empaquetar y notarizar. Solo necesita las *Command Line Tools* de Xcode (clang, make,
curl, lipo) y conexión a internet.

```sh
./buildwget.sh                      # universal arm64 + x86_64 (por defecto)
ARCHS="arm64" ./buildwget.sh        # solo la arquitectura del host (build local más rápido)
WGET_VERSION=1.25.0 OPENSSL_VERSION=3.4.1 ./buildwget.sh
```

**Verificación de las fuentes.** Antes de compilar, el script valida la integridad de los tarballs
descargados: usa el `.sha256` publicado por OpenSSL y la firma GPG de wget (contra el llavero
oficial de GNU, si hay `gpg`/`gpgv` instalado). Para una compilación reproducible y segura, fija
los hashes esperados; con `STRICT_VERIFY=1` el script aborta si no puede verificar una fuente:

```sh
WGET_SHA256=<hash> OPENSSL_SHA256=<hash> STRICT_VERIFY=1 ./buildwget.sh
```

**Instalación en el bundle (opcional).** Pásale un `.app` ya compilado y copiará el binario a
`Contents/Resources/wget`, re‑firmándolo *ad-hoc*:

```sh
./buildwget.sh /ruta/a/CocoaWget.app
# o: APP_BUNDLE=/ruta/a/CocoaWget.app ./buildwget.sh
```

Si no usas esa opción, el binario se deja en la raíz del proyecto y debe copiarse a los *Resources*
del *bundle* (lo hace la fase de recursos del proyecto Xcode). El script firma el binario de forma
*ad-hoc* para poder ejecutarlo localmente; para distribuir, se vuelve a firmar con el certificado
**Developer ID** al notarizar la app.

---

## Uso

1. Abre CocoaWget.
2. Escribe o pega una URL (`http://`, `https://`, `ftp://`) en el campo superior y pulsa **Add** /
   Intro. También puedes arrastrar enlaces a la ventana.
3. Ajusta las opciones por elemento (reanudar, recursivo, autenticación…) o las globales en el
   panel de **Preferencias** (carpeta de descargas, proxy, reintentos, *User‑Agent*, etc.).
4. Pulsa **Start** para iniciar la descarga (o activa la descarga automática).
5. Abre el cajón de **log** para ver la salida de wget en tiempo real.

---

## Estructura del repositorio

```
cocoawget/
├── main.m                     Punto de entrada de la app
├── MainController.{h,m}       Controlador de aplicación / ventana
├── CWArrayController.{h,m}    Cola de descargas (NSArrayController)
├── DownloadItem.{h,m}         Modelo de descarga + ejecución de wget
├── CocoaWget_Prefix.pch       Cabecera precompilada
├── Info.plist                 Metadatos del bundle (v2.7.0, min 10.13)
├── CocoaWget.icns             Icono de la app
├── GetURLFromSafari.scpt      AppleScript para obtener el Referer de Safari
├── buildwget.sh               Script para compilar el binario wget
├── wget                       Binario de wget empaquetado (¡obsoleto: i386/ppc!)
├── English.lproj/             Localización inglesa (xib + strings) — región de desarrollo
├── German.lproj/              Localización alemana
├── Japanese.lproj/            Localización japonesa
├── Spanish.lproj/             Localización española (xib + strings)
├── scripts/                   Utilidades (p. ej. create-github-issues.sh)
└── CocoaWget.xcodeproj/       Proyecto de Xcode
```

---

## Localización

CocoaWget está localizado en **inglés, alemán, japonés y español**. Cada idioma vive en una carpeta
`<Idioma>.lproj/` (se usan los nombres heredados de macOS — `English`, `German`, `Japanese`,
`Spanish` — en vez de los códigos ISO `en`/`de`/`ja`/`es`, por coherencia con el proyecto original).
El inglés es la **región de desarrollo** (`CFBundleDevelopmentRegion`) y actúa como respaldo.

Cada `*.lproj/` contiene dos piezas:

| Archivo | Qué contiene | Cómo se usa |
|---|---|---|
| `Localizable.strings` | Cadenas en tiempo de ejecución (estados de descarga, alertas, botones). | Resueltas en el código con `NSLocalizedString(...)` (ver [DownloadItem.h](DownloadItem.h) y [CWArrayController.m](CWArrayController.m)). |
| `MainMenu.xib` | La interfaz (ventana principal, preferencias y menús). | Cargada por AppKit según el idioma del sistema. |

### Mantener el español (y cualquier idioma) al día

1. **Cadenas (`Localizable.strings`)** — es la parte que el código consume. Las claves deben ser
   **idénticas** en todos los idiomas; solo cambia el valor de la derecha. Si añades un
   `NSLocalizedString(@"NuevaClave", @"")` en el código, **añade `"NuevaClave"="…";` a las cuatro
   localizaciones** ([English](English.lproj/Localizable.strings),
   [German](German.lproj/Localizable.strings), [Japanese](Japanese.lproj/Localizable.strings),
   [Spanish](Spanish.lproj/Localizable.strings)). Guarda en **UTF‑8**.
2. **Interfaz (`MainMenu.xib`)** — el `Spanish.lproj/MainMenu.xib` actual es **una copia del de
   inglés**: la app ya carga la localización española, pero los rótulos de menús y ventanas siguen
   en inglés hasta traducirlos en Xcode / Interface Builder. Traducir el XIB es una tarea aparte
   (ver [ROADMAP.md](ROADMAP.md) → Fase 3).
3. **Registro en el proyecto** — un idioma nuevo debe añadirse a los `PBXVariantGroup` de
   `MainMenu.xib` y `Localizable.strings` en [project.pbxproj](CocoaWget.xcodeproj/project.pbxproj)
   (o, más cómodo, desde Xcode: *Project ▸ Info ▸ Localizations ▸ +*).

> Comprobación rápida de paridad de claves entre dos idiomas:
> ```sh
> diff <(grep -oE '^"[^"]+"' English.lproj/Localizable.strings | sort) \
>      <(grep -oE '^"[^"]+"' Spanish.lproj/Localizable.strings | sort)
> ```

---

## Limitaciones conocidas

- **El binario `wget` incluido no funciona en macOS moderno** (arquitecturas de 32 bits / PowerPC).
- Código en **Objective‑C con conteo manual de referencias (MRC)**, no ARC.
- Uso de **APIs obsoletas o eliminadas** (`NSDrawer`, `NSStringPboardType`,
  `setKeys:triggerChangeNotificationsForDependentKey:`, `NSWorkspace iconForFileType:` /
  `openFile:`, `NSTask -launch`, etc.).
- **No está firmado ni notarizado**; Gatekeeper lo bloqueará en una distribución normal.
- Modifica el **`~/.wgetrc` global** del usuario (incompatible con el *App Sandbox*).
- Depende de **AppleScript para controlar Safari y Finder**, lo que requiere permisos de
  Automatización (TCC) en macOS actual.

El plan para resolver todo esto está en [ROADMAP.md](ROADMAP.md).

---

## Licencia

El código de la aplicación CocoaWget se distribuye bajo la licencia **MIT** (ver
[LICENSE](LICENSE)). El binario de **GNU wget** que se empaqueta es un programa independiente bajo
la **GNU GPL v3**; sus términos no se ven afectados por la licencia MIT del proyecto.

## Créditos

- Aplicación original **CocoaWget** por *hirama* (2008).
- [GNU wget](https://www.gnu.org/software/wget/) — Free Software Foundation.
