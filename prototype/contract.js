/* Сверка ответов API со схемами контракта Specification/State_machine/openapi.json
   (prototype/openapi.js). Ею пользуются самопроверка прототипа и тесты API (tests/api.html). */
(() => {
  /* Сверка ответа со схемой openapi.json: типы, обязательные поля, перечисления, вложенные
     схемы. Поле, которого нет в схеме, — тоже расхождение: контракт должен описывать всё,
     что отдаёт сервер. Формат строк (format) и пояснения $comment не проверяются. */
  function checkSchema(spec, schema, value, where, out) {
    if (!schema || out.length > 40) return;
    if (schema.$ref) return checkSchema(spec, spec.components.schemas[schema.$ref.split("/").pop()], value, where, out);
    if (schema.allOf) {
      const merged = { type: "object", properties: {}, required: [] };
      schema.allOf.forEach((part) => {
        const s = part.$ref ? spec.components.schemas[part.$ref.split("/").pop()] : part;
        Object.assign(merged.properties, s.properties || {});
        merged.required = merged.required.concat(s.required || []);
      });
      return checkSchema(spec, merged, value, where, out);
    }
    const alts = schema.anyOf || schema.oneOf;
    if (alts) {
      const fits = alts.some((alt) => {
        const errs = [];
        checkSchema(spec, alt, value, where, errs);
        return !errs.length;
      });
      if (!fits) {
        const errs = [];
        checkSchema(spec, alts.find((a) => !(a.type === "null")) || alts[0], value, where, errs);
        out.push(...(errs.length ? errs : [`${where}: не подходит ни под один вариант`]));
      }
      return;
    }
    const types = [].concat(schema.type || []);
    const kind = value === null ? "null" : Array.isArray(value) ? "array" : Number.isInteger(value) ? "integer" : typeof value;
    if (types.length && !types.includes(kind) && !(kind === "integer" && types.includes("number"))) {
      out.push(`${where}: ${kind} вместо ${types.join("|")}`);
      return;
    }
    if (schema.enum && !schema.enum.includes(value)) out.push(`${where}: «${value}» нет в enum`);
    if (kind === "array" && schema.items) value.forEach((item, i) => checkSchema(spec, schema.items, item, `${where}[${i}]`, out));
    if (kind === "object" && (schema.properties || schema.required)) {
      (schema.required || []).forEach((key) => {
        if (!(key in value)) out.push(`${where}: нет обязательного «${key}»`);
      });
      Object.entries(value).forEach(([key, v]) => {
        // Ключи с «$» — пояснения внутри машины ($comment), не данные
        if (key.startsWith("$")) return;
        const prop = (schema.properties || {})[key];
        if (prop) checkSchema(spec, prop, v, `${where}.${key}`, out);
        else if (schema.additionalProperties === undefined || schema.additionalProperties === false) out.push(`${where}: поля «${key}» нет в схеме`);
        else if (typeof schema.additionalProperties === "object") checkSchema(spec, schema.additionalProperties, v, `${where}.${key}`, out);
      });
    }
  }

  // Ответы сервера {method, template, status, body, kind} → список расхождений с контрактом
  function problems(spec, recorded) {
    const out = [];
    const seen = new Set();
    (recorded || []).forEach((r) => {
      let schema;
      if (r.kind === "stream") schema = { $ref: "#/components/schemas/IncidentStreamEvent" };
      else {
        const op = (spec.paths[r.template] || {})[r.method.toLowerCase()];
        if (!op) {
          out.push(`${r.method} ${r.template}: нет в контракте`);
          return;
        }
        let res = op.responses[String(r.status)];
        if (res && res.$ref) res = spec.components.responses[res.$ref.split("/").pop()];
        if (!res) {
          out.push(`${r.method} ${r.template}: ответа ${r.status} нет в контракте`);
          return;
        }
        if (r.status === 204) return;
        // Ошибки описаны как application/problem+json — их тела тоже сверяются
        const content = res.content && (res.content["application/json"] || res.content["application/problem+json"]);
        schema = content && content.schema;
        if (!schema) {
          if (r.status < 400) out.push(`${r.method} ${r.template} ${r.status}: у ответа нет схемы`);
          return;
        }
      }
      const errs = [];
      checkSchema(spec, schema, r.body, `${r.method} ${r.template} ${r.status}`, errs);
      errs.forEach((e) => {
        const key = e.replace(/\[\d+\]/g, "[]");
        if (!seen.has(key)) {
          seen.add(key);
          out.push(key);
        }
      });
    });
    return out;
  }

  window.IMContract = { problems, check: (spec, schema, value, where) => {
    const out = [];
    checkSchema(spec, schema, value, where || "", out);
    return out;
  } };
})();
