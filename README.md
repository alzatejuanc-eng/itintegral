# IT Assessment Board

Página web para evaluar el área de TI de una empresa con el Marco de evaluación integral del área de TI (v1.0) de Transformación ExO. Guarda quién diligencia, la empresa, el contexto, las respuestas, el resultado calculado y el roadmap sugerido.

- `index.html`: la aplicación completa. Es un solo archivo, se conecta a Supabase y funciona en cualquier hosting estático.
- `supabase/schema.sql`: tablas, seguridad (RLS), reglas y las funciones del servidor (`calcular_evaluacion`, `sugerir_roadmap`, `reabrir_pesos`).
- `supabase/seed_publico.sql`: 11 pilares, 221 preguntas situacionales (sin niveles) y la biblioteca de 33 acciones típicas.
- `tools/generar_seeds.py`: regenera los SQL de carga a partir del banco extraído del Word de equivalencias.

La clave de niveles **no está en este repositorio**. Se carga aparte con `privado/seed_clave.sql`, y la carpeta `privado/` está excluida en `.gitignore`.

## Puesta en marcha

1. Cree un proyecto en [supabase.com](https://supabase.com).
2. En SQL Editor, ejecute en este orden:
   1. `supabase/schema.sql`
   2. `supabase/seed_publico.sql`
   3. `privado/seed_clave.sql`. Al final devuelve un hash que debe ser `38a9d85fa57392cf2a9c6e33425a293e`.
3. En Authentication, Providers, deje activo Email. Si no quiere confirmar el correo al registrarse, desactive "Confirm email".
4. En Project Settings, API, copie la URL del proyecto y la llave publicable (o anon) y péguelas en `IAB_CONFIG`, al inicio de `index.html`. Esa llave es pública por diseño. La seguridad la dan RLS y las funciones del servidor.
5. Publique `index.html` en cualquier hosting estático (GitHub Pages, Netlify, Vercel) o ábralo localmente. En Authentication, URL Configuration, agregue la URL donde quede publicado.

## Flujo

1. **Datos generales**: quien diligencia (nombre, cargo, correo, teléfono) y la empresa (razón social, identificación, sector, país, tamaño, si es regulada).
2. **Contexto C1 a C11**: C1, C2, C3 y C7 son obligatorias. Si quedan vacías aparecen como brecha pendiente. Aquí también está el interruptor de escalamiento de IA.
3. **Pesos y objetivos**: los pesos deben sumar 100 y, si cambian, exigen justificación. Se bloquean con la primera respuesta y solo se reabren con un motivo, que queda en una bitácora con fecha.
4. **Cuestionario**: 221 preguntas en 11 secciones con nombres neutros, sin códigos, sin nombres de pilar y sin niveles. Cada respuesta se guarda sola, con su respaldo (tipo de evidencia, fuentes, descripción, fecha y comentario) o marcada como No evaluable.
5. **Resultados**: se calculan en el servidor. Muestra rating A a E, nota global, estado definitivo o provisional, scorecard, ejes, bloques, veto, alerta de IA, compuertas y prioridades.
6. **Roadmap**: genera acciones sugeridas según la prioridad (brecha × peso × riesgo) y la biblioteca. Una acción sin dueño, costo y fecha se queda en el registro de brechas.
7. **Informe**: informe ejecutivo para imprimir o guardar en PDF, más un resumen que se copia para el diagnóstico de madurez digital.

## Seguridad

- `clave_privada` tiene RLS activo, ninguna política y `REVOKE ALL` para `anon` y `authenticated`. Solo la leen las funciones `SECURITY DEFINER`.
- `calcular_evaluacion` devuelve y guarda solo agregados, nunca el nivel de una pregunta u opción.
- Cada usuario ve y modifica solo sus propias evaluaciones, respuestas y acciones.
- El navegador no puede escribir resultados, desbloquear pesos ni alterar la bitácora de ajustes.

## Verificación hecha

- La clave extraída del Word coincide con el hash del traspaso.
- En 80 escenarios aleatorios, el cálculo SQL se comparó contra el cálculo de referencia en TypeScript del proyecto anterior. Coinciden en todos los valores salvo un redondeo en el tercer decimal: con 4,475 el SQL da 4,48 y JavaScript da 4,47 por coma flotante. El SQL es el correcto.
- Se probó el recorrido completo en navegador sobre Postgres 16 con las reglas reales: creación, contexto, pesos (rechazo sin justificación), 221 respuestas, techo por evidencia, resultados, roadmap, regla del plan e informe. También se revisó la vista móvil sin scroll horizontal.

## Límites conocidos

- La versión 1 es para un evaluador con cuenta. Si van a responder directivos de la empresa evaluada, falta un modo por enlace con token que oculte pesos y resultados.
- La biblioteca de acciones es una propuesta inicial (una acción por pilar y horizonte). Conviene reemplazarla por la tabla 8.5 del marco.
- Aún no están construidos el comité de cuatro asientos, los hallazgos (plantilla B), los riesgos con probabilidad e impacto (C) ni las listas D y E.
- Las respuestas por escenario son declarativas. El techo por evidencia solo sirve si el evaluador exige respaldo real.
- No es certificación de auditoría ni concepto legal.
