# Hito 3 — sandbox Wasm

El propósito es ejecutar código de terceros que no es de confianza. El caso que orienta el diseño es, más adelante, un agente de IA aislado. Este hito no aloja un agente. El modelo está en [modelo-de-amenazas.md](modelo-de-amenazas.md). Lo que no está hecho está en [siguientes-pasos.md](siguientes-pasos.md): WASI, Python o JavaScript compilados a Wasm, floats, SIMD, llamadas indirectas, y correr el servidor dentro de Firecracker o gVisor.

## Qué hace

Un subconjunto de Wasm: enteros de 32 y 64 bits, control estructurado (`block`, `loop`, `if`, `br`, `br_if`), una memoria lineal, llamadas directas y cinco funciones de host del módulo `vlab`: `fs_read`, `fs_write`, `net_send`, `clock_ms`, `random`. No hay floats, SIMD ni `call_indirect`. El parser rechaza el resto.

Cada sandbox tiene concesión y cuota propias. La concesión sale en el texto de creación (`fs-read`, `fs-write`, `clock`, `random`, `net host puerto cuerpo`). No hay un permiso por defecto. `net_send` no abre un socket: si el destino está concedido, copia el `cuerpo` fijado en la concesión. El reloj, si se concede, es el del servidor al empezar esa ejecución. El azar solo se pide al sistema si `random` está concedido.

Cada `exec` nace con la memoria lineal a cero, el combustible lleno y el contador de llamadas a cero. El directorio virtual (`data/sandboxes/<id>/`) vive mientras vive el sandbox y se borra al destruirlo. La auditoría en cairn (colección `aud-<id>`) no se borra.

Techos del proceso, además de la petición: combustible ≤ 100000, memoria ≤ 1 MiB, llamadas de host ≤ 1000, módulo ≤ 16 KiB en binario, 32 sandboxes vivos, 256 KiB en el directorio virtual.

El lienzo uvl ejecuta el mismo intérprete puro en tres botones (`oob`, `bucle`, `denegar`) y pinta el nombre del teorema. El panel HTML de al lado crea, ejecuta y destruye sandboxes en el servidor.

## Cómo se comprobó

En esta máquina (4 vCPU, Xeon a 2400 MHz, ext4 en `/dev/vdc`), con wasmtime 27.0.0:

- `lake test` imprime `vlab tests ok`. Ahí entran el parser de la concesión, `../` rechazado, `a/../b` queda en `b`, el módulo `add` devuelve 42, el acceso fuera de memoria es `bounds`, el bucle con combustible 30 es `outOfFuel`, `fs_read` sin concesión deja el directorio virtual vacío y anota `deny fs_read`, y `..` con concesión de lectura es `escape`.
- El mismo `add.wasm` bajo wasmtime `--invoke main` imprime `42`. El `oob.wasm` termina con código distinto de 0. El `loop.wasm` con `timeout 2 wasmtime` termina con código 124 (el límite del `timeout`, no una trampa de wasmtime). El nuestro para por combustible.
- `scripts/e2e.sh` crea dos sandboxes, ejecuta `add` (valor 42), `oob` (`bounds`), `loop` (`outOfFuel`) y `host` (`deny fs_read` en la auditoría, citando `fsReadOk_grant`). La trampa `bounds` queda en cairn con `load?_inRange`, y `outOfFuel` con `evalList_zero`. Destruir el primero hace que otro `exec` responda 404. La auditoría del segundo sigue.
- `node web/smoke-node.cjs` imprimió `wasm smoke ok 480x360 ink=30302`. El clic en `oob` deja `bounds` en el árbol de accesibilidad. El módulo pesa 2,2 MiB.

## Demostrado

Sin `sorry` en este código. Los teoremas que compilan son:

- `normalize_safe`: si `normalize` devuelve segmentos, ninguno es `..`, `.` ni vacío.
- `load?_inRange`: una lectura que devuelve bytes cumple `addr + len ≤ mem.size`.
- `store?_size`: una escritura que tiene éxito no cambia el tamaño del array.
- `grow_le`: crecer por debajo de la cuota deja la memoria en o bajo la cuota.
- `fsReadOk_grant`, `fsWriteOk_grant`, `netOk_grant`, `clockOk_grant`, `randomOk_grant`: el booleano de admisión es verdadero solo si esa capacidad está en la lista.
- `deny_keeps`: construir una denegación no cambia el sistema de ficheros virtual, el cursor de entropía ni las concesiones.
- `evalList_zero`: con combustible 0 el evaluador responde `outOfFuel` y no ejecuta una instrucción.

Las líneas de auditoría citan esos nombres (`fsReadOk_grant`, no un `perform_allow_*` que no existe). `tag_known` dice que cada cita sale de esa lista, y el archivo de tests hace `#check` de cada declaración. Una trampa (`bounds`, `outOfFuel`, `escape`, y el resto) se escribe en cairn además de las llamadas al host. `scripts/check-axioms.sh` imprime `#print axioms` de estos teoremas y falla si aparece `sorryAx` o un axioma distinto de `propext`, `Classical.choice` y `Quot.sound`.

El evaluador está definido por recursión sobre el combustible, así que una ejecución termina. Cada instrucción gasta una unidad. Eso es la definición, no un teorema aparte que cuente los pasos de un programa arbitrario.

No está demostrado que el evaluador entero solo toque la memoria a través de `load?`, `store?` y `grow`. Esas son las únicas escrituras en el código de `evalList`. No está demostrada la equivalencia con la especificación de Wasm. El parser, `IO.FS`, cairn, el runtime de Lean y el kernel quedan fuera. La red simulada no es una prueba de que un socket futuro obedecería la misma lista.

## Base de confianza

Confiamos en el kernel de Lean, en el compilador, en el runtime en C, en el proceso que hace `IO`, en el kernel del sistema y en el hardware. wasmtime no forma parte de esa base: es el otro lado del diferencial. No es imposible escapar. Firecracker o gVisor serían la capa que este hito no tiene.
