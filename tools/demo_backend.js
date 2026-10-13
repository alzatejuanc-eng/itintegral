// Backend simulado para la demo navegable. Corre en el navegador y guarda en localStorage.
// Usa una clave FICTICIA generada al azar: no contiene la clave real ni sirve para puntuar.
// Reproduce las reglas de supabase/schema.sql (disparadores y funciones) para recorrer el flujo.
(function () {
  "use strict";
  const PREG = window.IAB_DEMO_PREGUNTAS;
  const PILARES = [
    [1, "Gobierno y rol de TI", "A", 10, ["Apoyo al negocio"]], [2, "Valor de negocio y portafolio", "A", 14, ["Apoyo al negocio"]],
    [3, "Finanzas y economía unitaria", "A", 10, ["Eficiencia"]], [4, "Modelo operativo y entrega", "B", 10, ["Productividad"]],
    [5, "Operación y servicio", "B", 9, ["Productividad", "Eficiencia"]], [6, "Resiliencia y continuidad", "C", 8, ["Resiliencia"]],
    [7, "Seguridad y riesgo", "C", 9, ["Resiliencia"]], [8, "Arquitectura, datos e infraestructura", "D", 8, ["Innovación y futuro"]],
    [9, "Talento, organización y proveedores", "D", 6, ["Eficiencia"]], [10, "Adopción, cultura y gestión del cambio", "D", 8, ["Productividad", "Apoyo al negocio"]],
    [11, "Innovación e IA", "D", 8, ["Innovación y futuro", "Apoyo al negocio"]],
  ].map(([n, nombre, bloque, peso, ejes]) => ({ n, nombre, bloque, peso, ejes }));
  const BIB = window.IAB_DEMO_BIBLIOTECA;

  // Clave ficticia con semilla fija
  let s = 424242; const rnd = () => (s = (s * 1103515245 + 12345) % 2147483648) / 2147483648;
  const CLAVE = PREG.map((p) => {
    const lv = [0, 1, 2, 3, 4]; for (let i = 4; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [lv[i], lv[j]] = [lv[j], lv[i]]; }
    const niveles = {}; "abcde".split("").forEach((l, i) => (niveles[l] = lv[i]));
    return { id: p.id, pilar: p.grupo, componente: `P${p.grupo}.${Math.floor((p.orden - 1) / 4) + 1}`, tipo: rnd() < 0.36 ? "D" : "E", niveles };
  });

  const KEY = "iab-demo-v1";
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : "id-" + Math.random().toString(36).slice(2) + Date.now());
  const now = () => new Date().toISOString();
  const PESOS = Object.fromEntries(PILARES.map((p) => [p.n, p.peso]));
  const ONES = (v) => Object.fromEntries(PILARES.map((p) => [p.n, v]));
  let DB;
  function guardar() { try { localStorage.setItem(KEY, JSON.stringify(DB)); } catch (e) { /* sin almacenamiento: la demo sigue en memoria */ } }
  function cargar() { try { const x = localStorage.getItem(KEY); if (x) return JSON.parse(x); } catch (e) { /* ignorar */ } return null; }

  const fail = (m) => { throw new Error(m); };
  const tablas = {
    pilares_cfg: () => PILARES, preguntas: () => PREG, biblioteca_acciones: () => BIB,
    evaluaciones: () => DB.evaluaciones, respuestas: () => DB.respuestas, acciones_roadmap: () => DB.acciones_roadmap,
  };

  function validarEval(e, old, servidor) {
    if (!servidor && old) {
      e.resultados = old.resultados; e.calculado_at = old.calculado_at; e.ajustes_log = old.ajustes_log;
      if (old.pesos_bloqueados && !e.pesos_bloqueados) fail("Para reabrir los pesos use la función reabrir_pesos con un motivo.");
      if (old.pesos_bloqueados && (JSON.stringify(e.pesos) !== JSON.stringify(old.pesos) || JSON.stringify(e.objetivos) !== JSON.stringify(old.objetivos)))
        fail("Los pesos y objetivos están bloqueados porque ya hay respuestas. Reábralos indicando un motivo.");
    }
    const suma = Object.values(e.pesos).reduce((a, b) => a + Number(b), 0);
    if (Math.abs(suma - 100) > 0.001) fail(`Los pesos deben sumar 100 (suman ${suma}).`);
    const cambia = PILARES.some((p) => Number(e.pesos[p.n]) !== p.peso);
    if (cambia && !(e.justificacion_pesos || "").trim()) fail("Si cambia algún peso base, la justificación escrita es obligatoria.");
    e.updated_at = now();
  }
  function trasRespuesta(evId) {
    const e = DB.evaluaciones.find((x) => x.id === evId);
    if (e) { e.pesos_bloqueados = true; if (e.estado === "borrador") e.estado = "en_curso"; }
  }
  function validarResp(r) {
    if (r.ne) r.opcion_id = null;
    if (["documento", "datos", "mejora"].includes(r.evidencia_tipo) && !(r.fuente_texto || "").trim())
      fail("Describa la fuente cuando el respaldo es documento, datos o mejora.");
  }
  function reglaPlan(a) {
    if (a.estado !== "en_brechas" && (!(a.dueno || "").trim() || a.costo_estimado == null || !a.fecha)) a.estado = "en_brechas";
    a.updated_at = now();
  }

  function from(t) {
    const st = { op: "select", where: [], order: [], single: false, ret: false, row: null };
    const b = {
      select() { if (st.op !== "select") st.ret = true; return b; },
      eq(c, v) { st.where.push([c, v]); return b; },
      order(c, o = {}) { st.order.push([c, o.ascending !== false, o.nullsFirst]); return b; },
      single() { st.single = true; return b; },
      insert(r) { st.op = "insert"; st.row = r; return b; },
      upsert(r) { st.op = "upsert"; st.row = r; return b; },
      update(r) { st.op = "update"; st.row = r; return b; },
      delete() { st.op = "delete"; return b; },
      then(res, rej) { return Promise.resolve().then(exec).then(res, rej); },
    };
    function exec() {
      try {
        const rows = tablas[t]();
        const match = (r) => st.where.every(([c, v]) => r[c] === v);
        let out;
        if (st.op === "select") {
          out = rows.filter(match).map((r) => JSON.parse(JSON.stringify(r)));
          for (const [c, asc, nf] of [...st.order].reverse()) out.sort((x, y) => {
            const a = x[c], z = y[c];
            const nullsFirst = nf ?? !asc;
            if (a == null || z == null) return a == null && z == null ? 0 : a == null ? (nullsFirst ? -1 : 1) : (nullsFirst ? 1 : -1);
            return (a < z ? -1 : a > z ? 1 : 0) * (asc ? 1 : -1);
          });
        } else if (st.op === "insert") {
          let r = { id: uid(), created_at: now(), updated_at: now(), ...st.row };
          if (t === "evaluaciones") {
            r = { owner_id: "demo", contexto: {}, pesos: { ...PESOS }, objetivos: ONES(3), riesgos_pilar: ONES(1), pesos_bloqueados: false,
              ajustes_log: [], estado: "borrador", version_marco: "1.0", resultados: null, calculado_at: null, regulada: false, escala_ia: false, ...r };
            validarEval(r, null, true);
          }
          if (t === "acciones_roadmap") { r = { estado: "en_brechas", origen: "manual", prioridad: null, ...r }; reglaPlan(r); }
          rows.push(r); out = [r];
        } else if (st.op === "upsert") {
          const r = { fuentes: 1, ...st.row, updated_at: now() }; validarResp(r);
          const i = rows.findIndex((x) => x.evaluacion_id === r.evaluacion_id && x.pregunta_id === r.pregunta_id);
          if (i >= 0) rows[i] = { ...rows[i], ...r }; else rows.push({ id: uid(), ...r });
          trasRespuesta(r.evaluacion_id); out = [r];
        } else if (st.op === "update") {
          out = [];
          rows.forEach((x, i) => {
            if (!match(x)) return;
            const n = { ...x, ...st.row };
            if (t === "evaluaciones") validarEval(n, x, false);
            if (t === "acciones_roadmap") reglaPlan(n);
            rows[i] = n; out.push(n);
          });
        } else if (st.op === "delete") {
          out = rows.filter(match);
          for (const r of out) {
            rows.splice(rows.indexOf(r), 1);
            if (t === "evaluaciones") {
              DB.respuestas = DB.respuestas.filter((x) => x.evaluacion_id !== r.id);
              DB.acciones_roadmap = DB.acciones_roadmap.filter((x) => x.evaluacion_id !== r.id);
            }
          }
        }
        if (st.op !== "select") guardar();
        if (st.single) { if (!out.length) return { data: null, error: { message: "No se encontró el registro." } }; out = out[0]; }
        return { data: st.op === "select" || st.ret || st.single ? out : null, error: null };
      } catch (e) { return { data: null, error: { message: e.message } }; }
    }
    return b;
  }

  // Cálculo: mismas reglas que calcular_evaluacion en supabase/schema.sql
  const rd = (x, d) => { const f = 10 ** d; return Math.round((x + Number.EPSILON) * f) / f; };
  const avg = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
  const TECHO = { verbal: 2, documento: 3, datos: 4, mejora: 5 };
  function calcular(e) {
    const resp = new Map(DB.respuestas.filter((r) => r.evaluacion_id === e.id).map((r) => [r.pregunta_id, r]));
    const acc = {}; const comp = {};
    PILARES.forEach((p) => (acc[p.n] = { total: 0, resp: 0, techos: 0, prac: [], res: [], conf: [] }));
    for (const c of CLAVE) {
      const a = acc[c.pilar]; a.total++;
      const r = resp.get(c.id); if (!r || r.ne || !r.opcion_id) continue;
      const nop = c.niveles[r.opcion_id]; const ev = TECHO[r.evidencia_tipo] ? r.evidencia_tipo : "verbal";
      const mej = ev === "mejora" && nop === 4; const nivel = mej ? 5 : Math.min(nop, TECHO[ev]);
      a.resp++; if (!mej && nop > TECHO[ev]) a.techos++;
      (c.tipo === "D" ? a.res : a.prac).push(nivel);
      const fuerte = ev !== "verbal", multi = (r.fuentes || 1) >= 2;
      a.conf.push(fuerte ? (multi ? 3 : 2) : multi ? 2 : 1);
      (comp[c.componente] ??= []).push(nivel);
    }
    const pil = PILARES.map((p) => {
      const a = acc[p.n]; const pr = avg(a.prac), rs = avg(a.res);
      const practica = pr === null ? null : rd(pr, 2), resultado = rs === null ? null : rd(rs, 2);
      const ne = a.total === 0 || a.resp / a.total < 0.5 || practica === null || resultado === null;
      const cf = avg(a.conf);
      return { n: p.n, nombre: p.nombre, bloque: p.bloque, peso: Number(e.pesos[p.n] ?? p.peso), practica, resultado,
        nota: ne ? null : rd(0.4 * practica + 0.6 * resultado, 2), ne,
        confianza: cf === null ? null : cf >= 2.5 ? "alta" : cf >= 1.75 ? "media" : "baja",
        alerta_actividad: practica !== null && resultado !== null && resultado <= practica - 2, veto: false, respondidas: a.resp, total: a.total };
    });
    const by = (n) => pil.find((p) => p.n === n); const pe = (n) => (by(n).ne ? null : by(n).practica);
    const vetoP = [6, 7].filter((n) => pe(n) !== null && pe(n) <= 1); vetoP.forEach((n) => (by(n).veto = true));
    const evd = pil.filter((p) => !p.ne);
    const pt = pil.reduce((a, p) => a + p.peso, 0), pev = evd.reduce((a, p) => a + p.peso, 0);
    const nota = pev > 0 ? rd(evd.reduce((a, p) => a + p.peso * p.nota, 0) / pev, 1) : null;
    let L = nota === null ? null : nota >= 4.5 ? "A" : nota >= 3.5 ? "B" : nota >= 2.5 ? "C" : nota >= 1.5 ? "D" : "E";
    if (L && vetoP.length && "ABC".includes(L)) L = "D";
    const NOM = { A: "Líder", B: "Sólido", C: "Funcional", D: "Frágil", E: "Crítico" };
    const VER = { A: "Líder. La función de TI es un activo estratégico demostrado.", B: "Sólido. Funciona bien con brechas puntuales.",
      C: "Funcional. Cumple lo básico, pero limita al negocio en áreas relevantes.",
      D: "Frágil. Hay riesgos de operación, de valor o de protección que requieren acción prioritaria.",
      E: "Crítico. La función no sostiene al negocio de forma confiable." };
    const pnb = pil.filter((p) => p.ne || p.confianza === "baja").reduce((a, p) => a + p.peso, 0);
    const prov = nota === null || pnb > pt / 3;
    const pcob = evd.filter((p) => p.confianza === "alta" || p.confianza === "media").reduce((a, p) => a + p.peso, 0);
    const disp = e.escala_ia || (by(11).practica !== null && by(11).practica >= 3);
    const ia = { disparada: disp, riesgo_mayor: false, pilares: [], no_descartable: [] };
    if (disp) for (const n of [1, 7, 8]) { if (by(n).ne) ia.no_descartable.push(n); else if (by(n).practica < 2) ia.pilares.push(n); }
    ia.riesgo_mayor = ia.pilares.length > 0;
    const vista = (ns) => { const v = ns.map(by).filter((p) => !p.ne); const w = v.reduce((a, p) => a + p.peso, 0);
      return { pilares: ns, nota: w > 0 ? rd(v.reduce((a, p) => a + p.peso * p.nota, 0) / w, 2) : null, evaluados: v.length }; };
    const est = (vs) => (vs.some((v) => v === null) ? "sin_evidencia" : vs.every((v) => v >= 2) ? "cumple" : "no_cumple");
    const dc = comp["P8.3"]?.length ? rd(avg(comp["P8.3"]), 2) : null;
    const componentes = {}; for (const [k, xs] of Object.entries(comp)) if (xs.length >= 2) componentes[k] = { nivel: rd(avg(xs), 2), respondidas: xs.length };
    const prioridades = pil.map((p) => {
      const objetivo = Number(e.objetivos[p.n] ?? 3), riesgo = p.veto ? 3 : Number(e.riesgos_pilar[p.n] ?? 1);
      const brecha = p.nota === null ? null : rd(Math.max(0, objetivo - p.nota), 2);
      return { n: p.n, nombre: p.nombre, objetivo, nota: p.nota, brecha, peso: p.peso, riesgo,
        prioridad: brecha === null ? null : rd(brecha * p.peso * riesgo, 2), exige_causa_raiz: p.alerta_actividad, ne: p.ne };
    }).sort((a, b) => (b.prioridad ?? -1) - (a.prioridad ?? -1));
    const R = {
      pilares: pil,
      global: { nota, rating_calculado: L, rating_nombre: L && NOM[L], rating_definitivo: prov || !L ? null : L, veredicto: L && VER[L],
        provisional: prov, cobertura: pt > 0 ? rd((pcob / pt) * 100, 1) : 0, peso_ne_o_baja: pnb, peso_total: pt },
      ejes: { Productividad: vista([4, 5, 10]), Eficiencia: vista([3, 5, 9]), "Apoyo al negocio": vista([1, 2, 10, 11]), Resiliencia: vista([6, 7]), "Innovación y futuro": vista([8, 11]) },
      bloques: { A: vista([1, 2, 3]), B: vista([4, 5]), C: vista([6, 7]), D: vista([8, 9, 10, 11]) },
      veto: { activo: vetoP.length > 0, pilares: vetoP }, alerta_ia: ia,
      compuertas: [
        { id: "C1", nombre: "Protección", estado: est([pe(6), pe(7)]), frena: "Ampliar superficie tecnológica (nuevas nubes, proveedores críticos, agentes de IA con acceso a sistemas)." },
        { id: "C2", nombre: "Gobierno y datos", estado: est([pe(1), dc]), frena: "Escalar IA a más procesos o áreas." },
        { id: "C3", nombre: "Valor", estado: est([pe(2)]), frena: "Aprobar nuevos proyectos grandes sin caso de negocio ni dueño del beneficio." },
        { id: "C4", nombre: "Adopción", estado: est([pe(10)]), frena: "Nuevas implementaciones masivas de sistemas o herramientas de IA." },
      ],
      prioridades, componentes,
      techos_aplicados: Object.fromEntries(PILARES.map((p) => [p.n, acc[p.n].techos])),
      ne_por_pilar: Object.fromEntries(PILARES.map((p) => [p.n, acc[p.n].total - acc[p.n].resp])),
      respondidas_por_pilar: Object.fromEntries(PILARES.map((p) => [p.n, acc[p.n].resp])),
    };
    e.resultados = R; e.calculado_at = now();
    if (nota !== null) e.estado = prov ? "provisional" : "definitiva";
    return R;
  }

  function sugerir(e) {
    if (!e.resultados) fail("Calcule los resultados antes de sugerir el roadmap.");
    DB.acciones_roadmap = DB.acciones_roadmap.filter((a) => !(a.evaluacion_id === e.id && a.origen === "sugerida" && a.estado === "en_brechas" && !a.dueno && a.costo_estimado == null && !a.fecha));
    let k = 0; const coma = (v) => String(v).replace(".", ",");
    const add = (a) => { const r = { id: uid(), evaluacion_id: e.id, origen: "sugerida", estado: "en_brechas", created_at: now(), ...a }; reglaPlan(r); DB.acciones_roadmap.push(r); k++; };
    for (const p of e.resultados.prioridades) {
      if (p.ne) { add({ pilar: p.n, brecha: "Pilar no evaluable por falta de evidencia", accion: `Levantar la evidencia faltante del pilar ${p.nombre} y completar las respuestas pendientes.`, horizonte: "quick_win", prioridad: null, riesgo_si_no: "El rating sigue provisional y el pilar no entra en la nota global." }); continue; }
      if (!(p.prioridad > 0)) continue;
      if (p.exige_causa_raiz) add({ pilar: p.n, brecha: "Actividad sin resultado: la práctica supera al resultado en 2 o más puntos", accion: `Analizar la causa raíz de por qué la práctica declarada no se traduce en resultados medibles en ${p.nombre}.`, horizonte: "quick_win", prioridad: p.prioridad, riesgo_si_no: "Se invierte en actividades que no mueven el resultado." });
      const orden = { quick_win: 1, "90_dias": 2, "12_meses": 3 };
      for (const b of BIB.filter((x) => x.pilar === p.n).sort((x, y) => orden[x.horizonte] - orden[y.horizonte])) {
        let hz = b.horizonte; if (e.resultados.veto.pilares.includes(p.n) && hz === "12_meses") hz = "90_dias";
        add({ pilar: p.n, brecha: `Nota ${coma(p.nota)} frente a objetivo ${p.objetivo} (brecha ${coma(p.brecha)})`, accion: b.accion, horizonte: hz, indicador: b.indicador,
          nivel_esperado: Math.min(5, p.objetivo), prioridad: p.prioridad,
          riesgo_si_no: p.riesgo >= 3 ? "Riesgo alto de continuidad, seguridad o cumplimiento." : p.riesgo === 2 ? "Riesgo medio para el negocio." : "La brecha se mantiene y limita al negocio." });
      }
    }
    return k;
  }

  async function rpc(fn, args) {
    try {
      const e = DB.evaluaciones.find((x) => x.id === args.p_id); if (!e) fail("Evaluación no encontrada.");
      let data;
      if (fn === "calcular_evaluacion") data = calcular(e);
      else if (fn === "sugerir_roadmap") data = sugerir(e);
      else if (fn === "reabrir_pesos") {
        if (!(args.p_motivo || "").trim()) fail("El motivo de la reapertura es obligatorio.");
        e.pesos_bloqueados = false; e.ajustes_log = [...e.ajustes_log, { fecha: now(), motivo: args.p_motivo.trim() }]; data = null;
      } else fail("Función desconocida.");
      guardar(); return { data, error: null };
    } catch (err) { return { data: null, error: { message: err.message } }; }
  }

  // Evaluación de ejemplo para abrir la demo en un estado realista
  function semilla() {
    DB = { evaluaciones: [], respuestas: [], acciones_roadmap: [] };
    const e = { id: uid(), owner_id: "demo", created_at: now(), updated_at: now(), version_marco: "1.0", estado: "borrador",
      evaluador_nombre: "Laura Gómez (ejemplo)", evaluador_cargo: "Gerente financiera", evaluador_correo: "laura.gomez@ejemplo.com", evaluador_telefono: "+593 99 000 0000",
      empresa: "Comercializadora Andina S.A. (ejemplo)", empresa_id_fiscal: "0990000000001", sector: "Distribución y retail", pais: "Ecuador y Perú", tamano: "850 empleados, 14 sedes",
      decision: "Priorizar el plan de inversión en TI 2027", patrocinador: "Gerencia general", periodo_meses: 12, alcance: "Sede principal, ERP, comercio electrónico y centros de distribución",
      contexto: { C1: "Comercializadora Andina, área de TI corporativa. Distribución y retail en Ecuador y Perú.", C2: "Priorizar el plan de inversión en TI 2027 y decidir si se escala IA en ventas.",
        C3: "Patrocina la gerencia general; el informe va al directorio.", C5: "Duplicar ventas digitales en 3 años. Riesgos: ciberseguridad y dependencia del ERP.",
        C7: "12 meses. Sede principal, ERP, comercio electrónico y centros de distribución." },
      regulada: false, escala_ia: true, pesos: { ...PESOS }, objetivos: { ...ONES(3), 6: 4, 7: 4 }, riesgos_pilar: { ...ONES(1), 6: 2, 7: 3, 2: 2 },
      justificacion_pesos: null, pesos_bloqueados: true, ajustes_log: [], resultados: null, calculado_at: null };
    DB.evaluaciones.push(e);
    let t = 99; const r2 = () => (t = (t * 1103515245 + 12345) % 2147483648) / 2147483648;
    const meta = { 1: 2.6, 2: 2.2, 3: 2.8, 4: 2.4, 5: 3.0, 6: 1.6, 7: 2.0, 8: 2.3, 9: 2.7, 10: 1.9, 11: 2.1 };
    for (const c of CLAVE) {
      if (c.pilar === 9 && r2() < 0.2) { DB.respuestas.push({ id: uid(), evaluacion_id: e.id, pregunta_id: c.id, opcion_id: null, ne: true, fuentes: 1 }); continue; }
      const objetivo = Math.max(0, Math.min(4, Math.round(meta[c.pilar] + (r2() - 0.5) * 2.2)));
      const op = Object.keys(c.niveles).find((k) => c.niveles[k] === objetivo);
      const ev = r2() < 0.55 ? (r2() < 0.6 ? "datos" : "documento") : "verbal";
      DB.respuestas.push({ id: uid(), evaluacion_id: e.id, pregunta_id: c.id, opcion_id: op, ne: false, evidencia_tipo: ev, fuentes: r2() < 0.5 ? 2 : 1,
        fuente_texto: ev === "verbal" ? null : ev === "datos" ? "Reporte del sistema del periodo" : "Documento aprobado y acta de uso", updated_at: now() });
    }
    e.estado = "en_curso"; calcular(e); sugerir(e);
    const dueños = ["Gerente de TI", "Jefe de seguridad", "Gerente financiera", "Gerente de operaciones"];
    DB.acciones_roadmap.filter((a) => a.evaluacion_id === e.id && a.prioridad !== null).slice(0, 5).forEach((a, i) => {
      a.dueno = dueños[i % 4]; a.costo_estimado = [4000, 12000, 25000, 8000, 60000][i]; a.fecha = ["2026-11-15", "2026-12-20", "2027-01-31", "2026-11-30", "2027-06-30"][i];
      a.indicador_meta = "Meta definida con el dueño"; a.estado = i === 0 ? "en_curso" : "en_plan"; reglaPlan(a);
    });
    guardar();
  }

  DB = cargar(); if (!DB || !DB.evaluaciones) semilla();
  const session = { user: { id: "demo", email: "evaluador@demo" } };
  window.IAB_CLIENT = { from, rpc, auth: { getSession: async () => ({ data: { session } }), onAuthStateChange() {}, signOut: async () => ({}) } };
  window.IAB_DEMO = "Demo con clave ficticia: los puntajes no son reales. Los cambios se guardan solo en este navegador.";
})();
