"""Genera los SQL de carga a partir del banco extraído del Word de equivalencias.

Uso:
  python3 tools/generar_seeds.py RUTA/banco_completo.json

Salidas:
  supabase/seed_publico.sql  pilares, preguntas situacionales (sin niveles) y biblioteca de acciones
  privado/seed_clave.sql     clave de niveles. CONFIDENCIAL: la carpeta privado/ está en .gitignore

banco_completo.json es una lista de objetos con id, codigo, pilar, componente, tipo,
enunciado, opciones [{id, texto}] y niveles {a..e: 0..4}. No se versiona.
"""
import json
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PILARES = [
    (1, "Gobierno y rol de TI", "A", 10, ["Apoyo al negocio"]),
    (2, "Valor de negocio y portafolio", "A", 14, ["Apoyo al negocio"]),
    (3, "Finanzas y economía unitaria", "A", 10, ["Eficiencia"]),
    (4, "Modelo operativo y entrega", "B", 10, ["Productividad"]),
    (5, "Operación y servicio", "B", 9, ["Productividad", "Eficiencia"]),
    (6, "Resiliencia y continuidad", "C", 8, ["Resiliencia"]),
    (7, "Seguridad y riesgo", "C", 9, ["Resiliencia"]),
    (8, "Arquitectura, datos e infraestructura", "D", 8, ["Innovación y futuro"]),
    (9, "Talento, organización y proveedores", "D", 6, ["Eficiencia"]),
    (10, "Adopción, cultura y gestión del cambio", "D", 8, ["Productividad", "Apoyo al negocio"]),
    (11, "Innovación e IA", "D", 8, ["Innovación y futuro", "Apoyo al negocio"]),
]

# Biblioteca de acciones típicas: una por pilar y horizonte (33 celdas).
# Redacción propuesta para arrancar; conviene reemplazarla por la tabla 8.5 del marco.
BIBLIOTECA = {
    1: [
        ("quick_win", "Nombrar un comité de TI y negocio con agenda mensual y acta de decisiones.", "Actas de comité emitidas por mes"),
        ("90_dias", "Escribir y aprobar el plan de TI derivado del plan de negocio, con fecha de revisión.", "Iniciativas enlazadas a un objetivo del negocio (%)"),
        ("12_meses", "Implantar un modelo de gobierno con derechos de decisión, políticas vigentes y auditoría periódica.", "Hallazgos de auditoría cerrados en plazo (%)"),
    ],
    2: [
        ("quick_win", "Levantar el inventario completo de proyectos en curso con dueño del negocio y beneficio esperado.", "Proyectos con dueño y beneficio declarado (%)"),
        ("90_dias", "Exigir caso de negocio y dueño del beneficio para aprobar cualquier iniciativa nueva.", "Iniciativas aprobadas con caso de negocio (%)"),
        ("12_meses", "Medir la realización de beneficios al cierre y a los 6 meses de cada proyecto, y racionalizar aplicaciones.", "Beneficios realizados frente a comprometidos (%)"),
    ],
    3: [
        ("quick_win", "Consolidar el gasto de TI del último año por servicio, proveedor y área consumidora.", "Gasto de TI asignado a un servicio (%)"),
        ("90_dias", "Revisar contratos, licencias y nube para eliminar consumo ocioso o duplicado.", "Ahorro anual identificado"),
        ("12_meses", "Implantar economía unitaria (costo por usuario, transacción o servicio) con revisión trimestral.", "Costo unitario por servicio y su tendencia"),
    ],
    4: [
        ("quick_win", "Publicar un tablero de trabajo en curso con prioridades acordadas con el negocio.", "Trabajo en curso por equipo"),
        ("90_dias", "Medir tiempo de entrega y tasa de fallas en cambios, y fijar metas con el negocio.", "Tiempo de entrega y tasa de fallas en cambios"),
        ("12_meses", "Rediseñar el modelo de entrega por flujos de valor con automatización de pruebas y despliegue.", "Frecuencia de despliegue y tiempo de entrega"),
    ],
    5: [
        ("quick_win", "Publicar el catálogo de servicios con horarios, canales y tiempos de respuesta.", "Servicios con acuerdo de nivel publicado (%)"),
        ("90_dias", "Instituir gestión de problemas con análisis de causa raíz para incidentes repetidos.", "Incidentes repetidos por mes"),
        ("12_meses", "Implantar mejora continua del servicio con encuesta de experiencia y revisión de acuerdos de nivel.", "Satisfacción del usuario y cumplimiento de acuerdos"),
    ],
    6: [
        ("quick_win", "Probar la restauración de los respaldos de los sistemas críticos y registrar el resultado.", "Restauraciones probadas con éxito (%)"),
        ("90_dias", "Realizar el análisis de impacto en el negocio y fijar objetivos de tiempo y punto de recuperación.", "Sistemas críticos con objetivos de recuperación aprobados (%)"),
        ("12_meses", "Implantar y probar el plan de continuidad y recuperación ante desastres con ejercicios anuales.", "Ejercicios de recuperación superados"),
    ],
    7: [
        ("quick_win", "Activar doble factor de autenticación en correo, accesos remotos y cuentas privilegiadas.", "Cuentas privilegiadas con doble factor (%)"),
        ("90_dias", "Inventariar activos, datos sensibles y proveedores críticos, y revisar accesos privilegiados.", "Activos críticos inventariados (%)"),
        ("12_meses", "Implantar un programa de gestión de riesgo tecnológico con detección, respuesta y pruebas periódicas.", "Tiempo de detección y de respuesta a incidentes"),
    ],
    8: [
        ("quick_win", "Documentar el mapa de aplicaciones e integraciones críticas con su dueño.", "Aplicaciones críticas documentadas (%)"),
        ("90_dias", "Cuantificar la deuda técnica y priorizar su reducción con el negocio.", "Deuda técnica priorizada con plan"),
        ("12_meses", "Implantar gobierno de datos con dueños, calidad medida y acceso controlado, base para la IA.", "Datos críticos con dueño y calidad medida (%)"),
    ],
    9: [
        ("quick_win", "Mapear capacidades y cargas del equipo de TI, internas y externas.", "Personas con carga mayor a la sostenible"),
        ("90_dias", "Definir plan de desarrollo de habilidades y revisar desempeño de proveedores clave contra contrato.", "Proveedores evaluados contra acuerdo de nivel (%)"),
        ("12_meses", "Rediseñar la estructura de TI y el modelo de abastecimiento según la estrategia.", "Rotación voluntaria y cobertura de roles críticos"),
    ],
    10: [
        ("quick_win", "Medir el uso real de los sistemas entregados en los últimos 12 meses.", "Usuarios activos frente a licenciados (%)"),
        ("90_dias", "Incorporar gestión del cambio y capacitación en cada proyecto desde su inicio.", "Proyectos con plan de cambio (%)"),
        ("12_meses", "Implantar medición de adopción y beneficios por área con responsables del negocio.", "Adopción y beneficio por área"),
    ],
    11: [
        ("quick_win", "Inventariar los usos de IA actuales, incluidos los no autorizados, y publicar reglas básicas de uso.", "Usos de IA inventariados"),
        ("90_dias", "Definir gobierno de IA con portafolio de casos de uso priorizados por valor y riesgo.", "Casos de uso con dueño y métrica de valor"),
        ("12_meses", "Escalar los casos de IA con valor demostrado, con controles de riesgo y plataforma de datos lista.", "Valor anual atribuible a casos de IA"),
    ],
}


def q(texto):
    return "'" + str(texto).replace("'", "''") + "'"


def main():
    banco = json.load(open(sys.argv[1], encoding="utf8"))
    assert len(banco) == 221
    for b in banco:
        for o in b["opciones"]:
            assert chr(0x2014) not in o["texto"] and chr(0x2013) not in o["texto"]

    orden = {}
    pub = [
        "-- Carga pública: pilares, preguntas situacionales (sin niveles) y biblioteca de acciones.",
        "-- Generado por tools/generar_seeds.py. Ejecutar después de schema.sql.",
        "begin;",
        "insert into public.pilares_cfg(n, nombre, bloque, peso, ejes) values",
        ",\n".join(
            f"  ({n}, {q(nom)}, {q(bl)}, {peso}, array[{', '.join(q(e) for e in ejes)}]::text[])"
            for n, nom, bl, peso, ejes in PILARES
        ),
        "on conflict (n) do update set nombre = excluded.nombre, bloque = excluded.bloque,",
        "  peso = excluded.peso, ejes = excluded.ejes;",
        "",
        "insert into public.preguntas(id, grupo, orden, enunciado, opciones) values",
    ]
    filas = []
    for b in banco:
        orden[b["pilar"]] = orden.get(b["pilar"], 0) + 1
        ops = json.dumps(b["opciones"], ensure_ascii=False)
        filas.append(f"  ({q(b['id'])}, {b['pilar']}, {orden[b['pilar']]}, {q(b['enunciado'])}, {q(ops)}::jsonb)")
    pub.append(",\n".join(filas))
    pub.append("on conflict (id) do update set grupo = excluded.grupo, orden = excluded.orden,")
    pub.append("  enunciado = excluded.enunciado, opciones = excluded.opciones;")
    pub.append("")
    pub.append("insert into public.biblioteca_acciones(pilar, horizonte, accion, indicador) values")
    pub.append(",\n".join(
        f"  ({n}, {q(h)}, {q(a)}, {q(i)})" for n, filas_b in BIBLIOTECA.items() for h, a, i in filas_b
    ))
    pub.append("on conflict (pilar, horizonte, accion) do update set indicador = excluded.indicador;")
    pub.append("commit;")
    open(os.path.join(RAIZ, "supabase", "seed_publico.sql"), "w", encoding="utf8").write("\n".join(pub) + "\n")

    priv = [
        "-- CONFIDENCIAL. Clave de niveles por opción. No subir a ningún repositorio ni compartir.",
        "-- Ejecutar en el editor SQL de Supabase después de seed_publico.sql.",
        "begin;",
        "insert into public.clave_privada(id, pilar, componente, tipo, niveles) values",
        ",\n".join(
            f"  ({q(b['id'])}, {b['pilar']}, {q(b['componente'])}, {q(b['tipo'])}, {q(json.dumps(b['niveles']))}::jsonb)"
            for b in banco
        ),
        "on conflict (id) do update set pilar = excluded.pilar, componente = excluded.componente,",
        "  tipo = excluded.tipo, niveles = excluded.niveles;",
        "commit;",
        "-- Verificación: debe devolver 38a9d85fa57392cf2a9c6e33425a293e",
        "select md5(string_agg(id || pilar || componente || tipo || (niveles->>'a') || (niveles->>'b')"
        " || (niveles->>'c') || (niveles->>'d') || (niveles->>'e'), '|' order by id)) from public.clave_privada;",
    ]
    os.makedirs(os.path.join(RAIZ, "privado"), exist_ok=True)
    open(os.path.join(RAIZ, "privado", "seed_clave.sql"), "w", encoding="utf8").write("\n".join(priv) + "\n")
    print("ok", len(banco), "preguntas")


if __name__ == "__main__":
    main()
