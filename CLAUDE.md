# NEXØ · App del grupo 18

## Qué es la app

NEXØ sirve para **prescribir entrenamientos y registrar las sesiones de nuestros atletas** para conocer su rendimiento. Es para deportistas de piragüismo, ciclismo y carrera de fondo.

- **El entrenador** da de alta a los deportistas, registra sus tests (FTP, VO₂ máx, contrarreloj de 30 min, contrarreloj de 2000 m, sprint de 200 m) y diseña sesiones con tareas. Cada tarea lleva un % de esfuerzo sobre un test de referencia.
- **El deportista** ve solo sus datos y anota lo que ha hecho en cada sesión: minutos, ritmo, FC, RPE y, si quiere, el archivo GPX o TCX de su reloj.
- La app calcula la carga con el **hrTSS** (`hrTSS = horas × hrIF² × 100`, con `hrIF = (FC media − FC reposo) / (FC umbral − FC reposo)`), el % de cumplimiento y un análisis de cada sesión con zonas de esfuerzo. Para la carga, cada deportista necesita su FC en reposo y su FC umbral (LTHR). Antes de entrenar, cada sesión muestra una **carga estimada** con la misma fórmula: el hrIF esperado sale del % de esfuerzo de cada tarea respecto al umbral del deportista (sin pasar del que permite su FC máxima), los descansos cuentan como suaves y las tareas sin % usan el RPE previsto.

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

El diagrama entidad-relación está en `docs/modelo-er.png`. Tablas en PostgreSQL (Supabase), con nombres en español, en minúsculas y sin tildes:

| Tabla | Qué guarda | Clave primaria | Claves foráneas |
|---|---|---|---|
| `entrenadores` | Entrenadores del grupo | `dni_entrenador` | — |
| `deportistas` | Ficha de cada deportista y su deporte | `dni` | `dni_entrenador` → `entrenadores` |
| `tests` | Resultados de FTP, VO₂ máx, contrarrelojes de 30 min y 2000 m y sprint de 200 m (columna `tipo`) | `id_test` | `dni_deportista` → `deportistas` |
| `sesiones` | Sesión que realiza un deportista y diseña un entrenador | `id_sesion` (único también: deportista + fecha + hora) | `dni_deportista`, `dni_entrenador` |
| `tareas` | Bloques de la sesión: orden, series, descanso, zona de entrenamiento (%), duración | `id_tarea` | `id_sesion`, `id_test_referencia`, `id_tarea_padre` |
| `tareas_distancia`, `tareas_potencia`, `tareas_tiempo`, `tareas_ritmo`, `tareas_frecuencia` | Subentidades de la tarea: lo que se mide | `id_tarea` | `id_tarea` → `tareas` (1:1) |
| `sesiones_realizadas` | Lo que el deportista anota de la sesión | `id_sesion` | `id_sesion` → `sesiones` (1:1) |
| `tareas_realizadas` | Lo realizado en cada tarea | `id_tarea` | `id_tarea` → `tareas` (1:1) |
| `trazas` | Puntos del archivo del reloj (jsonb) | `id_sesion` | `id_sesion` → `sesiones_realizadas` (1:1) |

- Relaciones del diagrama, todas 1:N: **Entrena** (entrenador → deportistas), **Realizan** (deportista → sesiones), **Diseña** (entrenador → sesiones), **Tienen** (sesión → tareas) y cada test (deportista → resultados). No hay relaciones N:M.
- Un deportista tiene **un solo entrenador**. **Cada entrenador ve solo a sus deportistas** (y a los que aún no tienen entrenador, para poder asignárselos). Cada deportista ve solo sus datos.
- Fuera del diagrama, añadido por la app: lo realizado (`sesiones_realizadas`, `tareas_realizadas`, `trazas`), el test de referencia de cada tarea, las tareas compuestas (`id_tarea_padre`), el nombre del entrenador y `usuario_id` en `entrenadores` y `deportistas`, que enlaza cada ficha con su cuenta de Supabase Auth para la seguridad (RLS).
- Las migraciones están en `supabase/migraciones/`:
  - `001_tablas.sql` crea las tablas.
  - `002_seguridad.sql` activa RLS y crea las políticas.
  - `003_fc_umbral.sql` añade `deportistas.fc_umbral` (LTHR) para el hrTSS. Es una propuesta pendiente de aprobación.

## Reglas para trabajar en este repositorio

1. **Explica cada cambio para principiantes.** Di qué has cambiado, por qué y cómo comprobarlo, sin dar por sabido el vocabulario técnico. Si usas un término como «clave foránea» o «política RLS», explícalo en una frase.
2. **No cambies las tablas sin aprobación del grupo.** Nada de crear, borrar ni modificar tablas, columnas, restricciones o políticas en Supabase sin que el grupo lo apruebe antes. Propón el cambio como una nueva migración numerada en `supabase/migraciones/` (por ejemplo `003_...sql`) y espera el visto bueno antes de ejecutarla.
3. **No uses nunca la secret key de Supabase.** En el código solo puede aparecer la clave pública (publishable key), que está protegida por RLS. La secret key se salta toda la seguridad: no se escribe en el código, ni en commits, ni en mensajes, ni se pide.
4. Trabaja en una rama y abre un pull request hacia `main`. No subas cambios directamente a `main`.
5. Mantén la app sin paso de compilación: HTML, CSS y JS que funcionen abriendo el archivo, con las librerías desde un CDN y una versión fija.
