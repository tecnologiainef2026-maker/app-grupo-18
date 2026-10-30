# NEXØ · App del grupo 18

## Qué es la app

NEXØ sirve para **prescribir entrenamientos y registrar las sesiones de nuestros atletas** para conocer su rendimiento. Es para deportistas de piragüismo, ciclismo y carrera de fondo.

- **El entrenador** da de alta a los deportistas, registra sus tests (FTP, VO₂ máx, contrarreloj de 30 min, contrarreloj de 2000 m, sprint de 200 m) y diseña sesiones con tareas. Cada tarea lleva un % de esfuerzo sobre un test de referencia.
- **El deportista** ve solo sus datos y anota lo que ha hecho en cada sesión: minutos, ritmo, FC, RPE y, si quiere, el archivo GPX o TCX de su reloj.
- La app calcula la carga (sRPE = RPE × minutos), el % de cumplimiento y un análisis de cada sesión con zonas de esfuerzo.

## Miembros del grupo

- Martín Antelo
- Gonzalo Aguin
- Alvaro Anes

## Tecnología

- **Página estática** en HTML, CSS y JavaScript, sin paso de compilación: no hay `npm run build`, los archivos se sirven tal cual.
- **Supabase** como base de datos y para las cuentas de usuario. La página usa `supabase-js` cargado desde un CDN, con una versión fija, por ejemplo `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4`.
- **Cloudflare Pages** para publicarla: proyecto conectado al repositorio de GitHub, rama de producción `main`, sin comando de build y con `/` como directorio de salida.

Estado actual: la app funciona como artefacto de Claude en `registro-entrenamiento/index.html` y guarda los datos en la base de datos del artefacto. El paso siguiente es moverla a Supabase con las migraciones de `supabase/migraciones/`, que todavía no se han ejecutado.

## Modelo de datos

Tablas en PostgreSQL (Supabase), con nombres en español, en minúsculas y sin tildes:

| Tabla | Qué guarda | Clave primaria | Se relaciona con |
|---|---|---|---|
| `entrenadores` | Entrenadores del grupo | `dni` | — |
| `deportistas` | Ficha de cada deportista y su deporte | `dni` | `entrenadores` (su entrenador) |
| `tests` | Resultados de los tests de rendimiento | `id` | `deportistas` |
| `sesiones` | Sesión que realiza un deportista y diseña un entrenador | `id` | `deportistas`, `entrenadores` |
| `tareas` | Bloques de la sesión, en orden, con su % de esfuerzo | `id` | `sesiones`, `tests` (test de referencia) |
| `partes_tarea` | Partes de una tarea compuesta | `id` | `tareas`, `tests` |
| `sesiones_realizadas` | Lo que el deportista anota de la sesión (1 por sesión) | `id_sesion` | `sesiones` |
| `tareas_realizadas` | Lo realizado en cada tarea (1 por tarea) | `id_tarea` | `tareas` |
| `trazas` | Puntos del archivo del reloj (jsonb) | `id_sesion` | `sesiones_realizadas` |

- `entrenadores.usuario_id` y `deportistas.usuario_id` enlazan cada ficha con su cuenta de Supabase Auth. La seguridad (RLS) usa ese enlace para saber quién es quién.
- Un deportista tiene **un solo entrenador**, y un entrenador tiene muchos deportistas. Un deportista tiene muchas sesiones y tests. Una sesión tiene muchas tareas.
- **Cada entrenador ve solo a sus deportistas** (y a los que aún no tienen entrenador, para poder asignárselos). Cada deportista ve solo sus datos.
- La relación muchos a muchos entre entrenadores y deportistas («el entrenador diseña sesiones para el deportista») se resuelve con la tabla `sesiones`.
- Las migraciones están en `supabase/migraciones/`:
  - `001_tablas.sql` crea las tablas.
  - `002_seguridad.sql` activa RLS y crea las políticas.

## Reglas para trabajar en este repositorio

1. **Explica cada cambio para principiantes.** Di qué has cambiado, por qué y cómo comprobarlo, sin dar por sabido el vocabulario técnico. Si usas un término como «clave foránea» o «política RLS», explícalo en una frase.
2. **No cambies las tablas sin aprobación del grupo.** Nada de crear, borrar ni modificar tablas, columnas, restricciones o políticas en Supabase sin que el grupo lo apruebe antes. Propón el cambio como una nueva migración numerada en `supabase/migraciones/` (por ejemplo `003_...sql`) y espera el visto bueno antes de ejecutarla.
3. **No uses nunca la secret key de Supabase.** En el código solo puede aparecer la clave pública (publishable key), que está protegida por RLS. La secret key se salta toda la seguridad: no se escribe en el código, ni en commits, ni en mensajes, ni se pide.
4. Trabaja en una rama y abre un pull request hacia `main`. No subas cambios directamente a `main`.
5. Mantén la app sin paso de compilación: HTML, CSS y JS que funcionen abriendo el archivo, con las librerías desde un CDN y una versión fija.
