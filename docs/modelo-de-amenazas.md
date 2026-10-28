# Modelo de amenazas

El sandbox de vlab existe para ejecutar código de terceros que no es de confianza. El caso que orienta el diseño, aunque este hito no aloje todavía un agente completo, es un agente de IA aislado: el modelo propone un módulo Wasm y el servidor lo corre con las herramientas que un operador le concedió, y con ninguna más.

El atacante es ese módulo, o el agente que lo eligió. Quiere salir del sandbox, leer o escribir fuera de su directorio, hablar con un destino de red que no está en la lista, o agotar CPU, memoria o el disco.

## Qué se asume del atacante

- Controla todos los bytes del módulo y todos los bytes que escribe en su memoria lineal.
- Puede llamar a las funciones de host exportadas por el intérprete (`fs_read`, `fs_write`, `net_send`, `clock_ms`, `random`).
- Puede intentar rutas `..`, direcciones fuera de la memoria, bucles y muchas llamadas.
- No se asume que el módulo esté bien formado más allá de lo que el parser acepta. Si el parser lo rechaza, no se ejecuta.
- No es un atacante del kernel, ni del operador que elige las cuotas, ni de quien puede escribir en el directorio de datos del servidor por otro camino.

## Capas

| Capa | Qué garantiza en este hito | Qué no garantiza |
| --- | --- | --- |
| Teoremas Lean (`Vlab.Wasm`, `Vlab.Sandbox`) | Un `load`/`store` que devuelve bytes está dentro del tamaño de la memoria. `store` no cambia ese tamaño. `grow` no pasa de la cuota si se parte de una memoria que ya cabía. `normalize` no devuelve un camino con `..`, `.` o un segmento vacío: `..` que saldría de la raíz es `none`. Una llamada de host admitida tenía la capacidad en la lista; una denegada no modifica el sistema de ficheros virtual ni la tabla de red. Con combustible 0 el evaluador para en `outOfFuel`. El evaluador está definido por recursión sobre el combustible, así que una ejecución para. | No es una bisimulación con la especificación de Wasm. No cubre floats, SIMD, llamadas indirectas, ni WASI. No habla del parser, ni de `IO`, ni del disco, ni del kernel. |
| Intérprete | El único efecto de host pasa por `perform`. La memoria del huésped solo cambia por `store?` o `grow`. Cada instrucción gasta una unidad del combustible que se le pasó. La red no abre un socket: `net_send` mira una tabla en memoria. | Un fallo del parser puede rechazar un módulo válido o, si acepta algo fuera del subconjunto, interpretarlo mal. El diferencial contra wasmtime cubre unos módulos pequeños, no todo el subconjunto. |
| Host (este proceso) | Cada sandbox tiene su directorio. Las escrituras usan la lista de segmentos ya normalizada, no la cadena cruda. No se siguen enlaces simbólicos: solo se leen ficheros normales. Las cuotas de combustible, memoria, llamadas de host y bytes del directorio virtual están acotadas por el proceso además de por la petición. Crear, ejecutar y destruir son API distintas. Cada ejecución nace con memoria lineal a cero, combustible lleno y contador de llamadas a cero. El directorio virtual vive lo que vive el sandbox. | El teorema no menciona `IO.FS`. Confiamos en que el runtime de Lean y el kernel aplican esa ruta. Un sandbox no protege de otro proceso con acceso al mismo directorio de datos. |
| Contenedor | No está en este hito. El `Dockerfile` del servidor no es un aislamiento del código huésped. | No hay gVisor ni Firecracker. Un fallo en el runtime de Lean, en el compilador o en el kernel no queda contenido por una capa inferior. |

## Capacidades

Todas se conceden al crear el sandbox. No hay un permiso por defecto.

- `fsRead` / `fsWrite` con un prefijo dentro del directorio virtual de ese sandbox. El prefijo vacío es la raíz virtual, no el disco del servidor.
- `net` con host y puerto. En este hito la respuesta es un cuerpo fijado en la concesión (`body`). No sale un paquete a la red.
- `clock`. La lectura es el reloj del servidor en el instante de arrancar esa ejecución, congelado durante ella.
- `random`. Solo si está concedida se piden bytes al sistema, y como mucho 256 por llamada.

Cuotas, también explícitas, con techo del servidor: combustible ≤ 100000, memoria ≤ 1 MiB, llamadas de host ≤ 1000, bytes totales del directorio virtual ≤ 256 KiB, módulo ≤ 16 KiB, como mucho 32 sandboxes vivos.

## Aislamiento entre sandboxes

Cada id tiene su concesión, su cuota y su directorio. Una ejecución no hereda la memoria lineal ni el combustible de otra. Destruir un sandbox borra su directorio. El registro en cairn no se borra: la auditoría se puede reconstruir después.

## Base de confianza

Confiamos en el kernel de Lean, en el compilador de Lean, en el runtime de Lean escrito en C, en el proceso que hace `IO`, en el kernel del sistema y en el hardware. El diferencial contra wasmtime es una prueba de acuerdo en unos programas, no una prueba de que el intérprete implementa Wasm. wasmtime no está en la base de confianza del sandbox: si discrepamos, hay un defecto que investigar, no un permiso para el huésped.

No es imposible escapar. Un defecto en el parser, en la parte de `IO` que el teorema no mira, o en el runtime, puede serlo. La defensa que falta es ejecutar este proceso dentro de gVisor o Firecracker, sin privilegios, y está escrita en [siguientes-pasos.md](siguientes-pasos.md) como trabajo futuro, no como una propiedad de este hito.
