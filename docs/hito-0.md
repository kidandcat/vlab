# Hito 0 — esqueleto

Informe de lo que hay en este árbol: un binario `vlab-server`, un directorio cairn y un front uvl. El laboratorio de funciones es el hito 1. El sandbox Wasm verificado es el hito 3 y el foco del proyecto. No hay un mini SO RISC-V.

## Cómo está hecho

El listener es `Std.Http.Server` de Lean 4.35.0 (`Std.Async` y `Std.Internal.UV` por debajo). Se probó un servidor mínimo, aparte de vlab, antes de apoyar el diseño en él: `GET`, `POST` con cuerpo, dos peticiones en la misma conexión (keep-alive) y un cuerpo `Transfer-Encoding: chunked`. Las cuatro respondieron `HTTP/1.1 200` con el cuerpo esperado. No hizo falta un shim en C.

cairn entra como dependencia Lake en `543684716dde412bb803702efdf6e6406f435c9d`. `ShardSet.openFiles` abre `dir/shard-0.cairn` con `Epoch.single`. Las notas son la colección `notes`. El contador de arranques es la clave `meta:boots`. Un commit se responde solo después del `sync` de ese shard.

uvl entra en `ff2f323df25f2e260c19a28d220c3bf507b033df`. `web/build.sh` sigue el de uvl: runtime de Lean e `Init` a Wasm con Emscripten 6.0.12, y los `.c` del módulo `VlabWeb.App` y de los módulos de uvl que importa. El shell de navegador (`web_shell.c`, `lean_stubs.c`, `uvl-web.js`) se toma de esa revisión de uvl; no está copiado al repositorio. El servidor solo entrega los cuatro ficheros de la lista blanca (`index.html`, `uvl.js`, `uvl.wasm`, `uvl-web.js`). No hay unión de rutas, así que una petición no sale de esa lista.

El host por defecto es `127.0.0.1`. El cuerpo HTTP máximo es 64 KiB. El texto de una nota, 4000 caracteres. No hay límite de tasa: eso queda para el hito 1. Decisión conservadora, y queda escrita aquí.

## Cómo se comprobó

En esta máquina (4 vCPU, Intel Xeon a 2400 MHz, ext4 en `/dev/vdc`):

1. `lake test` imprime `vlab tests ok`. Ahí entran el parser del cuerpo `{"text":...}`, las rutas (incluida `..`), el id en hexadecimal en los dos extremos (`0` y `2^48-1` / `2^80-1`) y un directorio cairn real: se escribe una nota, se cierra, se vuelve a abrir, la nota sigue y el contador de arranques pasa de 1 a 2. Una nota vacía no se guarda.
2. `bash scripts/e2e.sh` levanta el binario, hace `POST` y `GET`, keep-alive de dos `GET /health`, un `POST` con cuerpo fragmentado, mata el proceso y lo vuelve a abrir sobre el mismo directorio. La nota sigue. `boots` vale 2. Imprimió `e2e ok boots=2 notes=2`. Sin `web/dist`, `GET /` responde 200 en texto plano diciendo que falta el front. Un JSON a medias responde 400. `POST /` responde 405.
3. El front, cuando `web/build.sh` termina: `node web/smoke-node.cjs` (un frame, el árbol de accesibilidad, un clic en el botón) y `REQUIRE_FRONT=1 bash scripts/e2e.sh` (el Wasm servido empieza por `\0asm`).

El `Dockerfile` no se ha construido: en esta máquina no hay Docker. El fichero y [despliegue.md](despliegue.md) quedan para cuando haya un daemon.

## Demostrado y solo probado

Nada de este repositorio es un teorema del servidor. No hay `sorry` en el código de vlab. Tampoco hay una prueba de que el parser, el id o las rutas sean correctos para toda entrada: eso está ejecutado en `lake test` sobre los casos de arriba.

De cairn se usa lo ya demostrado allí (el pliegue de un lote, la colección con compare-and-set, el prefijo de un corte de fichero bien formado, el `sync` como barrera). Esos teoremas no hablan de este proceso HTTP ni de que `IO.Ref` publique el `View` de forma atómica. El modelo de fallo sigue siendo el de cairn: un prefijo de un fichero bien formado, no basura arbitraria, y un disco que mienta en el flush queda fuera.

`Std.Http.Server` no está demostrado. Está probado con las peticiones de arriba, aquí y otra vez dentro de `scripts/e2e.sh`.

El id en hexadecimal está probado en los extremos, no demostrado para todo `Ulid`. El parser JSON es una función total (el combustible baja en cada paso) y está probado con comillas, barra, salto de línea, UTF-8 y `\u00e1`. Rechaza un sustituto `\u` suelto. No es un parser de JSON completo: un objeto con otro campo, o dos campos, es un error.

El front uvl no está demostrado aquí. uvl ya demuestra, en su repositorio, que un píxel no se escribe fuera del framebuffer y que un hijo no se sale del padre. Este hito solo comprueba que el módulo arranca en Wasm y que un clic cambia el contador.

## Números

Misma máquina. Una pasada de `scripts/e2e.sh`, sin promediar. `tookNs` es el reloj monótono alrededor de `addNote` (el commit con sync). `wallUs` es el tiempo que ve el cliente, incluida la conexión.

```
post tookNs 965248 757605 254850 410444 950380
post wallUs 18281 2245 1122 1343 1857
health wallUs 729
```

El commit de una nota corta quedó entre unos 0,25 ms y unos 0,97 ms. La primera petición vista desde el cliente fue más lenta (unos 18 ms); las siguientes, entre 1,1 ms y 2,2 ms. `GET /health` recorre la colección: con pocas notas, unos 0,7 ms vistos desde el cliente. No es una cota. Un disco que espere al medio estable será más lento que este ext4.

El módulo del front pesa 2,1 MiB (`web/dist/uvl.wasm`). Tras pasar el paquete a `vlab`, `node web/smoke-node.cjs` imprimió `wasm smoke ok 480x360 ink=37757`: un frame de 480×360 y un clic en el botón que pasa el contador de `pings 0` a `pings 1`. Con el front servido, `REQUIRE_FRONT=1 bash scripts/e2e.sh` comprobó que `GET /uvl.wasm` empieza por la magia `\0asm` y que `GET /` es el `index.html`.

`web/build.sh` en caliente (el runtime de Lean e `Init` ya compilados en `.lake/build/wasm`) tardó 16 s. La primera pasada, sin esa caché, no se cronometró aparte: compiló el runtime, los 653 módulos de `Init` y la app, y terminó en esta misma máquina. En CI esa caché se guarda; la primera vez no está.

Cuatro símbolos de elaborador (`initialize_Lean`, `initialize_Std_Tactic_BVDecide` y dos de `Lean.Parser`) quedan como stubs que abortan si se llaman. El inicializador de `VlabWeb.App` no es uno de ellos. Cuando el paquete aún se llamaba leanlab, un primer enlace sustituyó `initialize_leanlab_…` por un stub: el patrón `initialize_Lean` también casaba con `Leanlab`, y el módulo lanzaba una excepción de Wasm. El script no trata `initialize_vlab_` como código de compilación. Eso se vio al ejecutar el smoke, no solo al enlazar.
