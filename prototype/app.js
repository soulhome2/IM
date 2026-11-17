(() => {

  /* ===== Языки =====
     Тексты состояний и переходов — переводимые лейблы, а не идентификаторы:
     переименование состояния не должно быть миграцией данных (§14.6).
     Ключ словаря — русская строка, значение — перевод. */

  const LANGS = [
    { id: "ru", label: "Русский", short: "RU", locale: "ru-RU" },
    { id: "en", label: "English", short: "EN", locale: "en-GB" },
  ];

  const DICT = {};
  LANGS.forEach(({ id }) => {
    if (id === "ru") return;
    DICT[id] = Object.assign(
      {},
      (window.IM_DICT_DATA || {})[id],
      (window.IM_DICT_HTML || {})[id],
      (window.IM_DICT_UI || {})[id]
    );
  });

  let LANG = "ru";
  // Каталоги строк по языкам (§14.9): ключ → строка ICU MessageFormat; получает boot() у сервера
  const CATALOGS = {};

  // Строка ICU MessageFormat: {name} — подстановка, {n, plural, one {…} few {…} other {…}} — форма
  // после числа, # — само число. Неизвестная подстановка остаётся как есть
  function icu(text, vars, number) {
    let out = "";
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (c === "#" && number != null) out += String(number);
      else if (c !== "{") out += c;
      else {
        let depth = 0;
        let j = i;
        for (; j < text.length; j++) if (text[j] === "{") depth++; else if (text[j] === "}" && --depth === 0) break;
        const m = text.slice(i + 1, j).match(/^\s*(\w+)\s*(?:,\s*plural\s*,([\s\S]*))?$/);
        const v = m && vars ? vars[m[1]] : undefined;
        if (!m || v === undefined) out += text.slice(i, j + 1);
        else if (!m[2]) out += String(v);
        else {
          const forms = {};
          m[2].replace(/([=\w]+)\s*\{((?:[^{}]|\{[^{}]*\})*)\}/g, (all, k, form) => (forms[k] = form));
          out += icu(forms[`=${v}`] || forms[new Intl.PluralRules(LANG).select(Number(v))] || forms.other || "", vars, v);
        }
        i = j;
      }
    }
    return out;
  }

  // Ключ каталога — строка каталога на языке интерфейса; русская фраза — по словарю (её ключами
  // станут на следующих шагах RULE-66)
  function t(ru, vars) {
    const catalog = CATALOGS[LANG] || {};
    if (catalog[ru] != null) return icu(catalog[ru], vars || {});
    // Фраза словаря интерфейса — тоже ICU MessageFormat: подстановки и формы после чисел
    const table = DICT[LANG];
    return icu((table && table[ru]) || ru, vars || {});
  }

  const te = (ru, vars) => escapeHtml(t(ru, vars));

  // Подпись из машины по ключу каталога (§14.9): labelKey, hintKey, titleKey…; нет ключа — сам текст
  const KEY_OF = { label: "labelKey", hint: "hintKey", title: "titleKey", confirmLabel: "confirmKey", placeholder: "placeholderKey", readOnlyReason: "readOnlyReasonKey", what: "whatKey" };
  const lbl = (o, field = "label") => (o ? t(o[KEY_OF[field]] || o[field] || "") : "");
  const hasLbl = (o, field) => Boolean(o && (o[KEY_OF[field]] || o[field]));


  // Кадры видеомонитора: инлайновые SVG-сцены, viewBox 320x180, растягиваются по кадру.
  const SCENES = {
    hall: `
      <rect width="320" height="180" fill="#20283a"/>
      <rect width="320" height="94" fill="#2a3448"/>
      <polygon points="0,180 320,180 246,94 74,94" fill="#3d465c"/>
      <polygon points="74,94 246,94 240,105 80,105" fill="#2b3446"/>
      <rect x="128" y="38" width="64" height="56" fill="#8fa3c6" opacity=".4"/>
      <rect x="136" y="46" width="48" height="48" fill="#cddcf5" opacity=".28"/>
      <polygon points="0,100 66,96 66,152 0,172" fill="#4a556f"/>
      <polygon points="320,100 254,96 254,152 320,172" fill="#4a556f"/>
      <g fill="#93a6c9">
        <rect x="4" y="106" width="58" height="7"/><rect x="4" y="122" width="58" height="7"/>
        <rect x="4" y="138" width="58" height="7"/><rect x="258" y="106" width="58" height="7"/>
        <rect x="258" y="122" width="58" height="7"/><rect x="258" y="138" width="58" height="7"/>
      </g>
      <g fill="#eef4ff" opacity=".5">
        <rect x="92" y="16" width="136" height="5" rx="2.5"/><rect x="106" y="4" width="108" height="4" rx="2"/>
      </g>
      <g fill="#131a28" opacity=".85">
        <ellipse cx="142" cy="150" rx="11" ry="4"/>
        <path d="M135 150c0-17 3.5-28 7-28s7 11 7 28z"/><circle cx="142" cy="116" r="6.5"/>
        <ellipse cx="198" cy="167" rx="12" ry="4.5"/>
        <path d="M190 167c0-19 4-31 8-31s8 12 8 31z"/><circle cx="198" cy="129" r="7.5"/>
      </g>
    `,
    checkout: `
      <rect width="320" height="180" fill="#222a3c"/>
      <rect width="320" height="80" fill="#2d374c"/>
      <polygon points="0,180 320,180 260,80 60,80" fill="#3f4960"/>
      <g fill="#eef4ff" opacity=".45">
        <rect x="70" y="10" width="180" height="5" rx="2.5"/><rect x="96" y="26" width="128" height="4" rx="2"/>
      </g>
      <polygon points="24,112 150,104 150,140 24,156" fill="#5b6580"/>
      <polygon points="24,112 150,104 150,112 24,120" fill="#7d89a5"/>
      <polygon points="176,104 300,112 300,156 176,140" fill="#5b6580"/>
      <polygon points="176,104 300,112 300,120 176,112" fill="#7d89a5"/>
      <g fill="#1a2130"><rect x="60" y="86" width="16" height="20" rx="2"/><rect x="238" y="88" width="16" height="20" rx="2"/></g>
      <g fill="#8ff0c0" opacity=".8"><rect x="63" y="90" width="10" height="7"/><rect x="241" y="92" width="10" height="7"/></g>
      <g fill="#131a28" opacity=".85">
        <path d="M154 150c0-19 4-31 8-31s8 12 8 31z"/><circle cx="162" cy="112" r="7"/>
        <path d="M186 158c0-20 4-33 8-33s8 13 8 33z"/><circle cx="194" cy="118" r="7.5"/>
      </g>
      <g fill="#d9a13a" opacity=".55"><rect x="150" y="150" width="26" height="30"/></g>
    `,
    storefront: `
      <rect width="320" height="180" fill="#1c2434"/>
      <rect width="320" height="22" fill="#141b28"/>
      <rect x="96" y="7" width="128" height="5" rx="2.5" fill="#eef4ff" opacity=".5"/>
      <rect x="20" y="22" width="280" height="76" fill="#0b111d"/>
      <rect x="20" y="86" width="280" height="12" fill="#1b2432"/>
      <g fill="#233045"><rect x="30" y="32" width="52" height="54"/><rect x="240" y="28" width="54" height="58"/></g>
      <g fill="#f7d9a0" opacity=".65">
        <rect x="36" y="38" width="10" height="10"/><rect x="52" y="38" width="10" height="10"/>
        <rect x="36" y="56" width="10" height="10"/><rect x="248" y="36" width="12" height="12"/>
        <rect x="272" y="56" width="12" height="12"/>
      </g>
      <g><rect x="150" y="34" width="4" height="52" fill="#4b5566"/><circle cx="152" cy="31" r="5.5" fill="#f7d9a0"/></g>
      <polygon points="146,34 158,34 172,86 132,86" fill="#f7d9a0" opacity=".12"/>
      <g fill="#3a465e"><rect x="186" y="66" width="74" height="20" rx="5"/><rect x="202" y="54" width="44" height="15" rx="4"/></g>
      <g fill="#0e131c"><circle cx="204" cy="86" r="6"/><circle cx="244" cy="86" r="6"/></g>
      <g fill="#c9d8ee" opacity=".07"><rect x="23" y="26" width="86" height="70"/><rect x="117" y="26" width="86" height="70"/><rect x="211" y="26" width="86" height="70"/></g>
      <g fill="#8fa3c6">
        <rect x="16" y="18" width="288" height="6"/><rect x="16" y="96" width="288" height="8"/>
        <rect x="16" y="18" width="7" height="86"/><rect x="110" y="18" width="7" height="86"/>
        <rect x="204" y="18" width="7" height="86"/><rect x="297" y="18" width="7" height="86"/>
      </g>
      <polygon points="0,180 320,180 304,104 16,104" fill="#39435a"/>
      <polygon points="16,104 304,104 300,114 20,114" fill="#2d364a"/>
      <g stroke="#4a556f" stroke-width="1.5" opacity=".6">
        <line x1="80" y1="104" x2="52" y2="180"/><line x1="160" y1="104" x2="160" y2="180"/>
        <line x1="240" y1="104" x2="268" y2="180"/>
      </g>
      <g fill="#1a2333">
        <rect x="56" y="142" width="62" height="7" rx="2"/>
        <path d="M79 142c0-27 4-42 8-42s8 15 8 42z"/><circle cx="87" cy="95" r="8"/>
        <rect x="198" y="152" width="68" height="7" rx="2"/>
        <path d="M223 152c0-29 4-45 9-45s9 16 9 45z"/><circle cx="232" cy="99" r="9"/>
      </g>
    `,
    corridor: `
      <rect width="320" height="180" fill="#232b3d"/>
      <polygon points="0,0 320,0 320,180 0,180" fill="#283145"/>
      <polygon points="118,54 202,54 202,126 118,126" fill="#161d2b"/>
      <polygon points="0,0 118,54 118,126 0,180" fill="#38425a"/>
      <polygon points="320,0 202,54 202,126 320,180" fill="#333c53"/>
      <polygon points="0,180 320,180 202,126 118,126" fill="#454f68"/>
      <polygon points="0,0 320,0 202,54 118,54" fill="#1f2738"/>
      <g fill="#b04a5a" opacity=".85">
        <polygon points="202,58 250,36 250,146 202,124"/>
        <polygon points="252,35 292,17 292,164 252,147"/>
      </g>
      <g fill="#8a3a48" opacity=".9">
        <rect x="224" y="46" width="3" height="96"/><rect x="270" y="28" width="3" height="126"/>
      </g>
      <g fill="#f2f7ff" opacity=".55">
        <rect x="140" y="8" width="40" height="4" rx="2"/><rect x="132" y="26" width="56" height="4" rx="2"/>
      </g>
      <g fill="#c9d4e8" opacity=".14"><polygon points="118,126 202,126 240,180 80,180"/></g>
      <g fill="#131a28" opacity=".8">
        <ellipse cx="160" cy="128" rx="9" ry="3.5"/>
        <path d="M154 128c0-15 2.5-24 6-24s6 9 6 24z"/><circle cx="160" cy="99" r="5.5"/>
      </g>
    `,
    gate: `
      <rect width="320" height="180" fill="#1e2534"/>
      <rect width="320" height="104" fill="#28303f"/>
      <polygon points="0,180 320,180 288,104 32,104" fill="#3b4252"/>
      <rect x="84" y="18" width="152" height="86" fill="#4a5364"/>
      <g stroke="#38404f" stroke-width="3">
        <line x1="84" y1="30" x2="236" y2="30"/><line x1="84" y1="44" x2="236" y2="44"/>
        <line x1="84" y1="58" x2="236" y2="58"/><line x1="84" y1="72" x2="236" y2="72"/>
        <line x1="84" y1="86" x2="236" y2="86"/>
      </g>
      <rect x="78" y="12" width="164" height="8" fill="#5b6577"/>
      <g fill="#d9a13a" opacity=".75"><rect x="30" y="112" width="260" height="4"/><rect x="20" y="160" width="280" height="5"/></g>
      <g fill="#8c6a3a">
        <rect x="24" y="118" width="46" height="26"/><rect x="24" y="112" width="46" height="7" fill="#a98046"/>
        <rect x="252" y="122" width="50" height="30"/><rect x="252" y="115" width="50" height="8" fill="#a98046"/>
      </g>
      <g fill="#f7d9a0" opacity=".1"><ellipse cx="160" cy="112" rx="96" ry="34"/></g>
      <g fill="#eef4ff" opacity=".55"><rect x="140" y="4" width="40" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".85">
        <ellipse cx="196" cy="150" rx="12" ry="4"/>
        <path d="M188 150c0-20 4-32 8-32s8 12 8 32z"/><circle cx="196" cy="112" r="7"/>
      </g>
    `,
    dock: `
      <rect width="320" height="180" fill="#1a2130"/>
      <rect width="320" height="96" fill="#101724"/>
      <polygon points="0,180 320,180 300,96 20,96" fill="#39414f"/>
      <rect x="96" y="14" width="150" height="96" rx="4" fill="#54606f"/>
      <rect x="104" y="24" width="134" height="72" fill="#6c7887"/>
      <g stroke="#4a545f" stroke-width="3"><line x1="171" y1="24" x2="171" y2="96"/></g>
      <g fill="#3d4652"><rect x="104" y="96" width="134" height="14"/></g>
      <g fill="#d9a13a"><rect x="96" y="110" width="150" height="6"/></g>
      <g fill="#d9a13a" opacity=".7"><rect x="20" y="132" width="280" height="4"/><rect x="10" y="164" width="300" height="5"/></g>
      <g fill="#8c6a3a"><rect x="34" y="128" width="42" height="26"/><rect x="34" y="121" width="42" height="8" fill="#a98046"/></g>
      <g fill="#f7d9a0" opacity=".1"><ellipse cx="170" cy="120" rx="92" ry="30"/></g>
      <g fill="#eef4ff" opacity=".5"><rect x="52" y="6" width="34" height="5" rx="2.5"/><rect x="252" y="6" width="34" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".9">
        <ellipse cx="264" cy="152" rx="12" ry="4"/>
        <path d="M256 152c0-21 4-33 8-33s8 12 8 33z"/><circle cx="264" cy="113" r="7"/>
        <path d="M257 106h14v-4a7 7 0 0 0-14 0z" fill="#e8b93c"/>
      </g>
    `,
    racks: `
      <rect width="320" height="180" fill="#1d2432"/>
      <rect width="320" height="88" fill="#252d3c"/>
      <polygon points="0,180 320,180 236,88 84,88" fill="#3c4453"/>
      <polygon points="0,88 78,86 78,158 0,178" fill="#4d5769"/>
      <polygon points="320,88 242,86 242,158 320,178" fill="#4d5769"/>
      <g fill="#39414f">
        <rect x="0" y="98" width="78" height="6"/><rect x="0" y="118" width="78" height="6"/><rect x="0" y="138" width="78" height="6"/>
        <rect x="242" y="98" width="78" height="6"/><rect x="242" y="118" width="78" height="6"/><rect x="242" y="138" width="78" height="6"/>
      </g>
      <g fill="#a98046">
        <rect x="6" y="104" width="30" height="14"/><rect x="44" y="104" width="28" height="14"/>
        <rect x="6" y="124" width="30" height="14"/><rect x="248" y="104" width="30" height="14"/>
        <rect x="286" y="124" width="28" height="14"/><rect x="248" y="144" width="30" height="14"/>
      </g>
      <polygon points="84,88 236,88 232,96 88,96" fill="#2a3240"/>
      <rect x="140" y="52" width="40" height="36" fill="#151c28"/>
      <g fill="#f7d9a0" opacity=".1"><ellipse cx="160" cy="128" rx="80" ry="46"/></g>
      <g fill="#eef4ff" opacity=".5">
        <rect x="126" y="10" width="68" height="5" rx="2.5"/><rect x="136" y="30" width="48" height="4" rx="2"/>
      </g>
      <g fill="#d9a13a" opacity=".7">
        <polygon points="86,96 92,96 78,180 66,180"/><polygon points="234,96 228,96 242,180 254,180"/>
      </g>
    `,
    receiving: `
      <rect width="320" height="180" fill="#20283a"/>
      <rect width="320" height="92" fill="#29334a"/>
      <polygon points="0,180 320,180 276,92 44,92" fill="#3e485e"/>
      <g fill="#d9a13a" opacity=".55">
        <polygon points="88,110 232,110 246,146 74,146"/>
      </g>
      <g fill="#3e485e"><polygon points="98,116 222,116 234,140 86,140"/></g>
      <rect x="30" y="40" width="70" height="52" fill="#4b5568"/>
      <g fill="#a98046">
        <rect x="236" y="96" width="54" height="30"/><rect x="236" y="88" width="54" height="9" fill="#c29452"/>
        <rect x="244" y="128" width="54" height="30"/><rect x="244" y="120" width="54" height="9" fill="#c29452"/>
      </g>
      <g fill="#5b6580"><rect x="120" y="86" width="80" height="6"/><rect x="126" y="92" width="6" height="26"/><rect x="188" y="92" width="6" height="26"/></g>
      <g fill="#eef4ff" opacity=".5"><rect x="112" y="12" width="96" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".88">
        <ellipse cx="160" cy="142" rx="11" ry="4"/>
        <path d="M152 142c0-20 4-31 8-31s8 11 8 31z"/><circle cx="160" cy="105" r="7"/>
        <path d="M153 98h14v-4a7 7 0 0 0-14 0z" fill="#e8b93c"/>
      </g>
    `,
    checkpoint: `
      <rect width="320" height="180" fill="#222a3c"/>
      <rect width="320" height="84" fill="#2b3448"/>
      <polygon points="0,180 320,180 272,84 48,84" fill="#414b61"/>
      <rect x="18" y="16" width="104" height="68" fill="#1a2334"/>
      <rect x="26" y="24" width="88" height="52" fill="#7d93b8" opacity=".45"/>
      <rect x="198" y="16" width="104" height="68" fill="#333d52"/>
      <rect x="206" y="26" width="88" height="42" fill="#95a8c9" opacity=".35"/>
      <g fill="#5b6580">
        <rect x="96" y="96" width="10" height="58" rx="3"/><rect x="214" y="96" width="10" height="58" rx="3"/>
        <rect x="60" y="112" width="46" height="6" rx="3"/><rect x="214" y="112" width="46" height="6" rx="3"/>
        <rect x="106" y="112" width="34" height="5" rx="2.5"/><rect x="180" y="112" width="34" height="5" rx="2.5"/>
      </g>
      <g fill="#8ff0c0" opacity=".85"><circle cx="101" cy="92" r="4"/></g>
      <g fill="#f2717f" opacity=".9"><circle cx="219" cy="92" r="4"/></g>
      <g fill="#f7d9a0" opacity=".09"><ellipse cx="160" cy="110" rx="92" ry="32"/></g>
      <g fill="#eef4ff" opacity=".5"><rect x="132" y="6" width="56" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".9">
        <ellipse cx="162" cy="150" rx="12" ry="4.5"/>
        <path d="M154 150c0-21 4-33 8-33s8 12 8 33z"/><circle cx="162" cy="110" r="7.5"/>
      </g>
      <g fill="#5b6580" opacity=".8"><rect x="150" y="86" width="24" height="4" rx="2"/></g>
    `,
    barrier: `
      <rect width="320" height="180" fill="#5b7290"/>
      <rect width="320" height="72" fill="#7d9bbd"/>
      <g fill="#9fb8d4" opacity=".8"><ellipse cx="70" cy="26" rx="40" ry="12"/><ellipse cx="236" cy="18" rx="52" ry="13"/></g>
      <rect y="66" width="320" height="12" fill="#4c6076"/>
      <polygon points="0,180 320,180 296,78 24,78" fill="#3f4653"/>
      <g stroke="#e8eef8" stroke-width="4" stroke-dasharray="16 14" opacity=".8"><line x1="160" y1="78" x2="160" y2="180"/></g>
      <g fill="#2f3846"><rect x="228" y="40" width="72" height="56"/></g>
      <rect x="236" y="48" width="56" height="30" fill="#a8c0dc" opacity=".55"/>
      <rect x="228" y="34" width="80" height="8" fill="#4b5566"/>
      <g fill="#e0e6f0"><rect x="96" y="60" width="10" height="46" rx="3"/></g>
      <g><rect x="100" y="58" width="120" height="8" rx="4" fill="#e8443c"/>
         <g fill="#f4f7fb"><rect x="118" y="58" width="16" height="8"/><rect x="154" y="58" width="16" height="8"/><rect x="190" y="58" width="16" height="8"/></g>
      </g>
      <g fill="#2a3140"><rect x="176" y="96" width="96" height="42" rx="6"/><rect x="192" y="80" width="64" height="22" rx="5"/></g>
      <rect x="198" y="84" width="52" height="16" fill="#8fa8c8" opacity=".6"/>
      <g fill="#151b26"><circle cx="198" cy="140" r="10"/><circle cx="252" cy="140" r="10"/></g>
      <g fill="#f2d98a"><rect x="266" y="106" width="8" height="8" rx="2"/></g>
      <g fill="#3f4653"><rect x="0" y="72" width="320" height="4" opacity=".4"/></g>
      <g fill="#e0e6f0" opacity=".9"><rect x="40" y="52" width="4" height="54"/><rect x="30" y="44" width="24" height="10" rx="3"/></g>
    `,
    entrance: `
      <rect width="320" height="180" fill="#232b3d"/>
      <rect width="320" height="100" fill="#2b3448"/>
      <polygon points="0,180 320,180 288,100 32,100" fill="#414b61"/>
      <rect x="88" y="14" width="144" height="86" fill="#0f1725"/>
      <g fill="#a6c2e4" opacity=".45"><rect x="94" y="20" width="64" height="80"/><rect x="162" y="20" width="64" height="80"/></g>
      <g stroke="#c9d8ee" stroke-width="3" opacity=".8"><line x1="160" y1="14" x2="160" y2="100"/><line x1="88" y1="56" x2="232" y2="56"/></g>
      <g fill="#dfe8f5" opacity=".22"><polygon points="94,100 226,100 250,180 70,180"/></g>
      <g fill="#2f3a4d"><rect x="20" y="70" width="52" height="30" rx="4"/></g>
      <g fill="#4a7f5a"><ellipse cx="264" cy="86" rx="20" ry="14"/><rect x="256" y="86" width="16" height="20" fill="#6b5138"/></g>
      <g fill="#eef4ff" opacity=".5"><rect x="130" y="4" width="60" height="5" rx="2.5"/></g>
      <g fill="#141a26" opacity=".85">
        <ellipse cx="158" cy="146" rx="12" ry="4.5"/>
        <path d="M150 146c0-21 4-33 8-33s8 12 8 33z"/><circle cx="158" cy="106" r="7.5"/>
      </g>
      <g fill="#31394a"><rect x="104" y="150" width="112" height="18" rx="3"/></g>
    `,
    guard: `
      <rect width="320" height="180" fill="#242c3e"/>
      <rect width="320" height="112" fill="#2c3549"/>
      <polygon points="0,180 320,180 300,112 20,112" fill="#3f4859"/>
      <g fill="#39435a"><rect x="34" y="118" width="252" height="48" rx="5"/></g>
      <g fill="#4b566e"><rect x="34" y="112" width="252" height="9" rx="3"/></g>
      <g fill="#101725"><rect x="64" y="54" width="82" height="52" rx="3"/><rect x="164" y="54" width="82" height="52" rx="3"/></g>
      <g fill="#3f6f9e" opacity=".8"><rect x="69" y="59" width="72" height="42"/><rect x="169" y="59" width="72" height="42"/></g>
      <g fill="#7fa8d4" opacity=".45">
        <rect x="72" y="64" width="30" height="14"/><rect x="106" y="64" width="30" height="14"/>
        <rect x="172" y="82" width="64" height="14"/>
      </g>
      <g fill="#2b3345"><rect x="96" y="106" width="18" height="8"/><rect x="196" y="106" width="18" height="8"/></g>
      <g fill="#c0392b"><circle cx="272" cy="128" r="8"/></g>
      <g fill="#8a2a20"><circle cx="272" cy="128" r="12" opacity=".4"/></g>
      <g fill="#141a26" opacity=".8"><rect x="130" y="150" width="60" height="30" rx="6"/><rect x="146" y="140" width="28" height="14" rx="5"/></g>
      <g fill="#eef4ff" opacity=".4"><rect x="18" y="20" width="60" height="4" rx="2"/><rect x="242" y="20" width="60" height="4" rx="2"/></g>
    `,
    server: `
      <rect width="320" height="180" fill="#131a28"/>
      <polygon points="0,180 320,180 250,84 70,84" fill="#232b3c"/>
      <polygon points="0,0 70,84 70,180 0,180" fill="#1b2231"/>
      <polygon points="320,0 250,84 250,180 320,180" fill="#1b2231"/>
      <polygon points="0,0 320,0 250,84 70,84" fill="#10161f"/>
      <g fill="#2b3446"><polygon points="0,20 70,84 70,180 0,180"/></g>
      <g fill="#2b3446"><polygon points="320,20 250,84 250,180 320,180"/></g>
      <g fill="#0d131d">
        <rect x="6" y="40" width="58" height="130"/><rect x="256" y="40" width="58" height="130"/>
      </g>
      <g fill="#3ddc84" opacity=".85">
        <rect x="12" y="50" width="14" height="4"/><rect x="12" y="62" width="20" height="4"/><rect x="12" y="74" width="10" height="4"/>
        <rect x="12" y="98" width="18" height="4"/><rect x="12" y="122" width="14" height="4"/><rect x="12" y="146" width="20" height="4"/>
        <rect x="288" y="52" width="18" height="4"/><rect x="288" y="76" width="12" height="4"/>
        <rect x="288" y="104" width="20" height="4"/><rect x="288" y="140" width="14" height="4"/>
      </g>
      <g fill="#f2b23c" opacity=".8"><rect x="36" y="86" width="10" height="4"/><rect x="272" y="120" width="10" height="4"/></g>
      <g fill="#7fa8d4" opacity=".25"><polygon points="70,84 250,84 234,180 86,180"/></g>
      <g fill="#eef4ff" opacity=".45"><rect x="128" y="10" width="64" height="4" rx="2"/><rect x="140" y="26" width="40" height="3" rx="1.5"/></g>
    `,
  };

  // Мини-глифы устройств для планов: система координат -8..8.
  const DEVICE_GLYPH = {
    camera: `<rect x="-7" y="-4" width="9" height="8" rx="1.5"/><path d="M2.4 -2.2 7.4 -5.2V5.2L2.4 2.2z"/>`,
    "fire-detector": `<path d="M0 -7c3.2 3.4 4.8 4.9 4.8 7.4A4.8 4.8 0 0 1 0 6.6a4.8 4.8 0 0 1-4.8-5.4C-4.8 -1.8 -2 -3.4 0 -7z"/>`,
    "panic-button": `<circle r="6.8" opacity=".35"/><circle r="3.4"/>`,
    "ppe-detector": `<path d="M-7 3.2h14A7 7 0 0 0-7 3.2z"/><rect x="-8.4" y="3.6" width="16.8" height="2.8" rx="1.4"/>`,
    "access-point": `<rect x="-6.4" y="-7" width="12.8" height="14" rx="1.6" fill="none" stroke="currentColor" stroke-width="2.2"/><circle cx="3" cy="0" r="1.5"/>`,
    microphone: `<rect x="-2.8" y="-7" width="5.6" height="9" rx="2.8"/><path d="M-5.4 0a5.4 5.4 0 0 0 10.8 0" fill="none" stroke="currentColor" stroke-width="2.2"/><path d="M0 5.4v3.2" stroke="currentColor" stroke-width="2.2"/>`,
  };

  const PLANS = {
    mall: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="158" height="106" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="210" y="32" width="158" height="106" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="32" y="152" width="120" height="76" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="172" y="152" width="196" height="76" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="150" y1="138" x2="176" y2="138"/><line x1="270" y1="138" x2="300" y2="138"/>
          <line x1="60" y1="228" x2="110" y2="228"/>
        </g>
        <g fill="var(--map-room-2)" opacity=".9">
          <rect x="44" y="72" width="46" height="7"/><rect x="44" y="88" width="46" height="7"/>
        </g>
        <g fill="var(--map-room)" opacity=".9">
          <rect x="292" y="62" width="9" height="30"/><rect x="308" y="62" width="9" height="30"/><rect x="324" y="62" width="9" height="30"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="48">Магазин 1 · торговый зал</text>
          <text x="220" y="48">Магазин 2 · примерочные</text>
          <text x="42" y="170">Входная группа · витрина</text>
          <text x="182" y="170">Атриум · галерея</text>
        </g>
      `,
    },
    warehouse: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="30" y="30" width="76" height="200" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="122" y="30" width="176" height="200" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="312" y="30" width="58" height="96" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="312" y="140" width="58" height="90" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g fill="var(--stroke-2)">
          <rect x="14" y="60" width="6" height="40"/><rect x="14" y="150" width="6" height="40"/>
        </g>
        <g fill="var(--map-room-2)" opacity=".95">
          <rect x="140" y="46" width="140" height="12"/><rect x="140" y="92" width="140" height="12"/>
          <rect x="140" y="158" width="140" height="12"/><rect x="140" y="200" width="140" height="12"/>
        </g>
        <g stroke="var(--warn)" stroke-width="2" stroke-dasharray="6 5" opacity=".6">
          <line x1="106" y1="130" x2="312" y2="130"/>
        </g>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="106" y1="112" x2="106" y2="146"/><line x1="298" y1="112" x2="298" y2="146"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="34" y="46">Рампа и ворота</text>
          <text x="140" y="42">Стеллажи А1–А8</text>
          <text x="140" y="152">Стеллажи А9–А16</text>
          <text x="316" y="46">Приёмка</text>
          <text x="316" y="156">Цех</text>
          <text x="206" y="124">Центральный проход</text>
        </g>
      `,
    },
    office: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="168" height="82" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="216" y="32" width="152" height="106" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="32" y="130" width="168" height="98" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="216" y="154" width="152" height="74" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="200" y1="170" x2="216" y2="170"/><line x1="120" y1="114" x2="150" y2="114"/>
          <line x1="90" y1="228" x2="140" y2="228"/>
        </g>
        <g fill="var(--map-room)" opacity=".9">
          <rect x="44" y="140" width="66" height="14" rx="3"/>
          <rect x="232" y="168" width="80" height="14" rx="3"/>
        </g>
        <g fill="var(--map-room-2)" opacity=".9">
          <rect x="60" y="52" width="112" height="30" rx="4"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="46">Конференц-зал</text>
          <text x="226" y="46">Зона ожидания</text>
          <text x="42" y="146">Приемная и ресепшн</text>
          <text x="226" y="168">Пост охраны</text>
          <text x="60" y="222">Главный вход</text>
        </g>
      `,
    },
    lab: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="158" height="94" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="210" y="32" width="158" height="94" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="32" y="140" width="336" height="36" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="32" y="190" width="158" height="38" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="210" y="190" width="158" height="38" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="96" y1="126" x2="130" y2="126"/><line x1="274" y1="126" x2="308" y2="126"/>
          <line x1="96" y1="190" x2="130" y2="190"/><line x1="274" y1="190" x2="308" y2="190"/>
        </g>
        <g fill="var(--map-room-2)" opacity=".9">
          <rect x="46" y="52" width="60" height="10" rx="2"/><rect x="46" y="72" width="60" height="10" rx="2"/>
          <rect x="228" y="52" width="60" height="10" rx="2"/><rect x="228" y="72" width="60" height="10" rx="2"/>
        </g>
        <g fill="var(--map-room)" opacity=".95">
          <rect x="320" y="44" width="16" height="34" rx="2"/><rect x="342" y="44" width="16" height="34" rx="2"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="46">Лаборатория 1</text>
          <text x="220" y="46">Лаборатория 2 · серверная</text>
          <text x="42" y="162">Коридор корпуса А</text>
          <text x="42" y="212">Склад реактивов</text>
          <text x="220" y="212">Комната персонала</text>
        </g>
      `,
    },
    checkpoint: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="16" y="96" width="368" height="66" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <g stroke="var(--map-label)" stroke-width="2" stroke-dasharray="12 10" opacity=".5">
          <line x1="16" y1="129" x2="384" y2="129"/>
        </g>
        <rect x="204" y="30" width="112" height="58" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="36" y="176" width="132" height="56" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="2" opacity=".7">
          <line x1="60" y1="176" x2="60" y2="232"/><line x1="90" y1="176" x2="90" y2="232"/>
          <line x1="120" y1="176" x2="120" y2="232"/><line x1="150" y1="176" x2="150" y2="232"/>
        </g>
        <g fill="var(--crit)" opacity=".7"><rect x="112" y="92" width="70" height="6" rx="3"/></g>
        <g fill="var(--stroke-2)"><rect x="106" y="86" width="8" height="22" rx="2"/></g>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="240" y1="88" x2="270" y2="88"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="212" y="46">Проходная · турникеты</text>
          <text x="42" y="192">Парковка персонала</text>
          <text x="30" y="116">Въезд</text>
          <text x="330" y="116">Территория</text>
        </g>
      `,
    },
    mall2: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="158" height="106" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="32" y="152" width="120" height="76" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="210" y="32" width="158" height="106" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="172" y="152" width="196" height="76" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="96" y1="138" x2="126" y2="138"/><line x1="270" y1="138" x2="300" y2="138"/><line x1="152" y1="190" x2="172" y2="190"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="48">Ресторан · зал</text>
          <text x="42" y="170">Кухня ресторана</text>
          <text x="220" y="48">Кинотеатр · кинозал №3</text>
          <text x="182" y="170">Фойе и бар</text>
        </g>
      `,
    },
    office2: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="200" height="196" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="248" y="32" width="120" height="120" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="248" y="166" width="120" height="62" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="232" y1="80" x2="248" y2="80"/><line x1="232" y1="196" x2="248" y2="196"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="48">Отдел разработки · опенспейс</text>
          <text x="258" y="48">Отдел маркетинга</text>
          <text x="258" y="182">Переговорная «Невада»</text>
        </g>
      `,
    },
    warehouse2: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="200" height="196" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="248" y="32" width="120" height="110" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="248" y="156" width="120" height="72" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="232" y1="70" x2="248" y2="70"/><line x1="232" y1="192" x2="248" y2="192"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="48">Склад №3 · стеллажи</text>
          <text x="258" y="48">Холодильная камера</text>
          <text x="258" y="172">Пост погрузчика</text>
        </g>
      `,
    },
    lab2: {
      svg: `
        <rect x="16" y="16" width="368" height="228" rx="6" fill="var(--map-floor)" stroke="var(--stroke-2)" stroke-width="2"/>
        <rect x="32" y="32" width="336" height="70" fill="var(--map-room)" stroke="var(--stroke-2)"/>
        <rect x="32" y="116" width="336" height="36" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="32" y="166" width="158" height="62" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <rect x="210" y="166" width="158" height="62" fill="var(--map-room-2)" stroke="var(--stroke-2)"/>
        <g stroke="var(--stroke-2)" stroke-width="6" stroke-linecap="round" opacity=".55">
          <line x1="96" y1="102" x2="130" y2="102"/><line x1="96" y1="152" x2="130" y2="152"/><line x1="274" y1="152" x2="308" y2="152"/>
        </g>
        <g fill="var(--map-label)" font-size="9" font-family="Inter, sans-serif">
          <text x="42" y="48">Офис 1</text>
          <text x="42" y="132">Коридор корпуса Б</text>
          <text x="42" y="182">Офис 2 · переговорная «Юпитер»</text>
          <text x="220" y="182">Офис 2 · кухня</text>
        </g>
      `,
    },
  };

  /* ===== Устройства на экране =====
     Название и тип устройства приходят от сервера (DeviceRef в карточке и дереве групп).
     Здесь только оформление: значок типа, кадр камеры, место на плане. */

  const DEVICE_ICON = {
    camera: "videocam",
    "fire-detector": "local_fire_department",
    "panic-button": "crisis_alert",
    "ppe-detector": "engineering",
    "access-point": "sensor_door",
    microphone: "mic",
  };

  const PAGE_SIZE = 8;

  /* ===== Связь с сервером =====
     Интерфейс говорит только с API (api.js) — запросами и ответами из openapi.json.
     По умолчанию это встроенный сервер в этой же вкладке (server.js), с ?api=… — настоящий бэкенд. */

  const apiBase = new URLSearchParams(location.search).get("api");
  // В самопроверке коллеги не эмулируются: очередь меняют только её шаги, и результат не зависит
  // от скорости машины. Эмуляцию коллег проверяют тесты API, где время идёт по /test/clock
  const selftestRun = new URLSearchParams(location.search).has("selftest");
  // В самопроверке у встроенного сервера есть служебные операции стенда (часы, роли): без них не
  // дойти до оповещения и потери доступа. Самопроверке — тот же клиент API (PROC-12)
  const embedded = apiBase
    ? null
    : IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, strings: window.IM_STRINGS, colleagues: selftestRun ? false : window.IM_COLLEAGUES, testSupport: selftestRun });
  const api = IMApi.create(apiBase ? { baseUrl: apiBase } : { server: embedded });
  if (selftestRun && embedded) window.IM_SELFTEST_API = api;
  // Ответы встроенного сервера — самопроверке: она сверяет их со схемами openapi.json
  if (embedded) window.IM_RECORDED = embedded.recorded;
  const enc = encodeURIComponent;
  const incPath = (guid) => `/operator/incidents/${enc(guid)}`;

  // Схема workflow — из /operator/workflow/active: формы, фильтры, справочники
  let WORKFLOW = null;
  let STATES = {};
  let LIMITS = {};
  let PRIORITIES = {};

  // Последние ответы сервера. Своих данных у интерфейса нет: всё — из этих ответов
  const store = {
    session: null,
    page: { items: [], total: 0, page: 1, pageSize: PAGE_SIZE },
    counters: {},
    // Числа кнопок шапки очереди (§7, план 87в): состояния — без своей группы кнопок, приоритеты — без выбранных
    // приоритетов (null — у фильтра без счётчиков чисел нет); блок «Мне на принятие» — свой запрос
    stateCounts: {},
    priCounts: null,
    block: { items: [], total: 0 },
    tree: [],
    eventTypes: [],
    scenarios: [],
    deviceTypes: [],
    targets: [],
    card: null,
    selection: null,
    // Идущие окна плановых работ, видимые оператору (ТЗ-21): пункт строки состояния поста и значки дерева
    maint: { windows: [], nextChangeAt: null },
  };

  const state = {
    mode: "queue",
    groupsOn: true,
    mediaOn: true,
    themeMode: "dark",
    camFor: null,
    mobileView: "queue",
    page: 1,
    focus: true,
    groupId: "all",
    openGroups: new Set(),
    groupQuery: "",
    // Узел дерева с фокусом клавиатуры — переживает перерисовку (RULE-88)
    treeFocus: null,
    // Текущее найденное в поиске по дереву и нужно ли прокрутить к нему (RULE-88)
    treeHit: 0,
    treeHitScroll: false,
    filter: "open",
    // Выбранные уровни приоритета — числа справочника (§2.5); пусто — все
    priorities: [],
    // Меню «Ещё ▾» шапки очереди на окне 1280–1559
    stateMenu: false,
    // Тип события и тип устройства — фильтры поверх выбранной группы (RULE-03)
    // Несколько значений сразу; пусто — все. tbOpen — какой из трёх списков раскрыт; сценарий — свой у каждого соседа по событию (§19.2)
    eventTypes: [],
    scenarios: [],
    deviceTypes: [],
    tbOpen: null,
    moreFilters: false,
    tbQ: {},
    // Вкладка карточки: сценарий или привязанные инциденты — и чья карточка
    workTab: "scenario",
    workTabFor: null,
    // Страница привязанных инцидентов в карточке основного (§11) и найденное поиском среди них
    linkedPage: 1,
    linkedFocus: null,
    search: "",
    selectedId: "INC-1847",
    checked: new Set(),
    // Шаг, который смотрит оператор в карточке на просмотр: курсор владельца не двигается
    viewStep: new Map(),
    // Черновики ответов на шаги сценария — до «Далее» (инцидент:шаг → { value, attachments })
    drafts: new Map(),
    // Инциденты, где оператор ушёл с шага «Итог» на шаги сценария: вернётся «Далее» с последнего шага или по «Итогу»
    summaryOff: new Set(),
    // Журнал карточки: раскрыт у этого инцидента; сколько записей уже видел оператор — новые подсвечиваются
    logOpen: null,
    moreOpen: null,
    logSeen: new Map(),
    videoMode: "archive",
    activeCam: null,
    full: null,
    dialog: null,
    // Мою открытую карточку увели (§22.7): инцидент → { who, what } — полоса «только просмотр» в карточке
    evicted: {},
  };

  const $ = (id) => document.getElementById(id);

  const can = (key) => Boolean(store.session && store.session.permissions.includes(key));
  const onBreak = () => Boolean(store.session && store.session.agentState === "not_ready");
  const signedOut = () => Boolean(store.session && store.session.agentState === "offline");
  const prefs = () => (store.session ? store.session.preferences : {});

  // Имя участника — из ActorRef ответа или из списка адресатов передачи
  const targetById = (id) => store.targets.find((x) => x.id === id) || null;
  const actorName = (ref) => {
    if (!ref) return t("Не назначен");
    if (typeof ref === "string") {
      const target = targetById(ref);
      return target ? t(target.name) : ref;
    }
    return t(ref.name || "");
  };

  // Ответ сервера [шаблон, подстановки] → строка на языке интерфейса
  const say = (key, vars) => (key ? t(key, logVars(vars)) : "");
  const problemText = (err) => {
    const p = err && err.problem;
    if (!p) return t("Нет связи с сервером");
    return p.messageKey ? say(p.messageKey, p.messageVars) : t(p.message || "");
  };

  // Поправка «время сервера − время пульта» (BUG-103): отсчёты и часы — по времени сервера, иначе часы пульта,
  // спешащие на минуты, показали бы «просрочено» раньше срока. Обновляется при каждом ответе с serverTime
  let skewMs = 0;
  const serverNow = () => Date.now() + skewMs;
  function noteServerTime(list) {
    const timer = (list || []).map((e) => e && (e.timer || e.holdTimer)).find((x) => x && x.serverTime);
    if (timer) skewMs = Date.parse(timer.serverTime) - Date.now();
  }

  function nowStamp() {
    const locale = (LANGS.find((l) => l.id === LANG) || LANGS[0]).locale;
    return new Date(serverNow()).toLocaleTimeString(locale, { hour12: false });
  }
  const fmtTime = (iso) => {
    const locale = (LANGS.find((l) => l.id === LANG) || LANGS[0]).locale;
    return iso ? new Date(iso).toLocaleTimeString(locale, { hour12: false }) : "";
  };

  const narrowQuery = window.matchMedia("(max-width: 900px)");

  function applyTheme(mode) {
    const theme = mode === "light" ? "light" : "dark";
    state.themeMode = theme;
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem("im-theme", theme);
    } catch (err) {
      /* ignore */
    }
    const label = t(theme === "light" ? "Светлая тема" : "Тёмная тема");
    const btn = $("themeToggle");
    btn.title = label;
    btn.setAttribute("aria-label", label);
    btn.setAttribute("aria-pressed", String(theme === "light"));
  }

  /* ===== Статичные тексты разметки =====
     Русский текст в index.html — он же ключ словаря. Оригиналы снимаются один
     раз до первой отрисовки, поэтому переключать язык можно сколько угодно. */

  /* ===== Статичные тексты разметки =====
     Русский текст в index.html — он же ключ словаря. Оригиналы снимаются один
     раз до первой отрисовки, поэтому переключать язык можно сколько угодно. */

  const STATIC = { text: [], attr: [], html: [] };
  const I18N_ATTRS = ["title", "placeholder", "aria-label"];
  const CYRILLIC = /[\u0400-\u04FF]/;

  function collectStatic() {
    document.querySelectorAll("[data-i18n-html]").forEach((el) => {
      STATIC.html.push({ el, ru: el.innerHTML.trim() });
    });
    document.querySelectorAll("*").forEach((el) => {
      I18N_ATTRS.forEach((attr) => {
        const value = el.getAttribute(attr);
        if (value && CYRILLIC.test(value)) STATIC.attr.push({ el, attr, ru: value.trim() });
      });
    });
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!CYRILLIC.test(node.nodeValue)) return NodeFilter.FILTER_REJECT;
        for (let p = node.parentElement; p; p = p.parentElement) {
          // Названия языков в переключателе всегда на своём языке
          if (p.hasAttribute("data-i18n-html") || p.hasAttribute("data-i18n-skip")) {
            return NodeFilter.FILTER_REJECT;
          }
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const raw = node.nodeValue;
      STATIC.text.push({
        node,
        ru: raw.trim(),
        pre: raw.match(/^\s*/)[0],
        post: raw.match(/\s*$/)[0],
      });
    }
    STATIC.title = document.title;
  }

  function applyStatic() {
    STATIC.html.forEach((item) => (item.el.innerHTML = t(item.ru)));
    STATIC.attr.forEach((item) => item.el.setAttribute(item.attr, t(item.ru)));
    STATIC.text.forEach((item) => (item.node.nodeValue = item.pre + t(item.ru) + item.post));
    syncTitle();
  }

  function applyLang(id) {
    LANG = LANGS.some((l) => l.id === id) ? id : "ru";
    document.documentElement.lang = LANG;
    try {
      localStorage.setItem("im-lang", LANG);
    } catch (err) {
      /* приватный режим: язык живёт до перезагрузки */
    }
    const select = $("langSelect");
    if (select.value !== LANG) select.value = LANG;
    select.title = t("Язык интерфейса");
    applyStatic();
    applyTheme(state.themeMode);
    renderTypeFilters();
    renderAll();
    // Окно «Выделить по фильтру» — тоже на новом языке, даже закрытое
    if (filt.view) {
      filt.focusSearch = false;
      renderFilter();
    }
    syncLocale().catch(() => {});
  }

  // Язык интерфейса — серверу (§14.9, preferences.locale): готовые тексты ответов — подписи кнопок,
  // причины, бейджи — приходят на нём
  async function syncLocale() {
    if (!store.session || prefs().locale === LANG) return;
    await api.patch("/operator/session/preferences", { locale: LANG });
    await reload();
  }

  function showModal(id) {
    const modal = $(id);
    if (!modal) return;
    document.querySelectorAll(".modal:not([hidden])").forEach((m) => (m.hidden = true));
    modal.hidden = false;
    const focusTarget = modal.querySelector(".modal-actions .btn");
    if (focusTarget) focusTarget.focus();
  }

  // Недоступная кнопка действия остаётся в фокусе и нажимается (aria-disabled, а не disabled):
  // нажатие показывает причину. Так её узнают и на телефоне, и с клавиатуры, и экранным диктором

  function explainIfOff(btn) {
    if (btn.getAttribute("aria-disabled") !== "true") return false;
    toast(btn.title || t("Действие недоступно"), "error");
    return true;
  }

  // Итог моего действия (§22.6) — одна плашка в верхней шапке справа от строки состояния поста (§22.4); узкое окно —
  // сразу под шапкой. done — итог, late — опоздал («Уже взял Петров»): уходят сами, новый заменяет прежний, никуда не
  // сохраняются. error — ошибка или отказ: висит до «✕»; новая заменяет её, на плашке «ещё N», нажатие — список
  // прежних под плашкой, «✕» убирает все. Итог при висящей ошибке встаёт поверх неё на время, затем ошибка
  // возвращается. О чужих и автоматических событиях — не здесь, а в колокольчике (notice); сюда — не в колокольчик
  const TOAST_MS = 3200;
  let toastMs = TOAST_MS;
  const toasts = { errors: [], soft: null, timer: 0 };
  function toastEl(text, kind) {
    const el = document.createElement("div");
    el.className = `toast ${kind}`;
    el.dataset.kind = kind;
    el.title = text;
    const msg = document.createElement("span");
    msg.className = "toast-text";
    msg.textContent = text;
    el.appendChild(msg);
    // Полный текст и прежние ошибки — по нажатию на плашку (текст обрезан многоточием, если места мало)
    el.addEventListener("click", (e) => {
      if (!e.target.closest(".toast-close")) toggleToastList(el);
    });
    return el;
  }
  function toggleToastList(el) {
    const list = $("toastList");
    if (!list.hidden || !el) {
      list.hidden = true;
      return;
    }
    const lines = el.dataset.kind === "error" ? toasts.errors.slice().reverse() : [el.textContent];
    list.innerHTML = lines.map((x) => `<li>${escapeHtml(x)}</li>`).join("");
    list.hidden = false;
  }
  // Открытый список закрывают щелчок мимо плашки и списка и Esc (onKey) — как в интерфейсе стенда
  document.addEventListener("click", (e) => {
    const list = $("toastList");
    if (list && !list.hidden && !e.target.closest(".toast-slot")) toggleToastList(null);
  });
  function closeErrors() {
    toasts.errors = [];
    $("toasts").querySelectorAll(".toast.error").forEach((x) => x.remove());
    toggleToastList(null);
    fitHead();
  }
  function toast(text, kind = "done") {
    const box = $("toasts");
    toggleToastList(null);
    clearTimeout(toasts.timer);
    if (toasts.soft) toasts.soft.remove();
    toasts.soft = null;
    if (kind === "error") {
      box.querySelectorAll(".toast.error").forEach((x) => x.remove());
      toasts.errors.push(text);
      const el = toastEl(text, kind);
      if (toasts.errors.length > 1) {
        // «ещё N» — рисует CSS из атрибута: текст плашки остаётся текстом ошибки
        const more = document.createElement("span");
        more.className = "toast-more";
        more.dataset.toastMore = t("ещё {n}", { n: toasts.errors.length - 1 });
        el.appendChild(more);
      }
      const x = document.createElement("button");
      x.type = "button";
      x.className = "toast-close";
      x.title = t("Закрыть сообщение");
      x.setAttribute("aria-label", x.title);
      x.onclick = closeErrors;
      el.appendChild(x);
      box.appendChild(el);
    } else {
      const under = box.querySelector(".toast.error");
      if (under) under.hidden = true;
      const el = toastEl(text, kind);
      box.appendChild(el);
      toasts.soft = el;
      toasts.timer = setTimeout(() => {
        if (toasts.soft !== el) return;
        if (!$("toastList").hidden) toggleToastList(null);
        el.remove();
        toasts.soft = null;
        const back = box.querySelector(".toast.error");
        if (back) back.hidden = false;
        fitHead();
      }, toastMs);
    }
    fitHead();
  }
  // Опоздал (§8.1, §22.6, RULE-142): действие не прошло, потому что инцидент уже ведёт другой человек — мягкое
  // «Уже принял / взял {who}». Что изменилось — отказ 412 INCIDENT_CHANGED с ключом changed.taken (владелец сменился;
  // закрытый — changed.state, переданный, но не принятый — changed.addressed), кто теперь — его current (без второго
  // запроса). Иначе или новый владелец — я — обычная ошибка с текстом сервера
  function lateText(transitionId, err, meGuid) {
    const p = err && err.problem;
    if (!p || p.code !== "INCIDENT_CHANGED" || p.messageKey !== "workflow.error.changed.taken") return null;
    const now = p.current;
    if (!now || !now.owner || now.owner.id === meGuid) return null;
    return t(transitionId === "accept" ? "Уже принял {who}" : "Уже взял {who}", { who: actorName(now.owner) });
  }

  /* ===== Колокольчик — журнал оповещений (§22.5) ===== */

  // Хранит браузер рабочего места, отдельно для каждого оператора каждой организации; старше display.noticeKeepHours —
  // выбрасывается; испорченная запись — пустой журнал. Организацию сессия не называет (она в токене): в прототипе —
  // параметр ?customer=, иначе адрес сервера (?api=) или «local» (§17)
  const NOTICE_KINDS = ["action", "system", "info"];
  const NOTICE_MAX = 500;
  const customerId = new URLSearchParams(location.search).get("customer") || apiBase || "local";
  const bell = { key: null, list: [], pending: [], open: false, tab: "all", fresh: new Set(), seq: 0 };
  const noticeKey = () => (store.session ? `im.notices.${customerId}.${store.session.operator.guid}` : null);
  const keepMs = () => ((WORKFLOW && WORKFLOW.display && WORKFLOW.display.noticeKeepHours) || 12) * 3600e3;
  const validNotice = (n) => n && typeof n === "object" && typeof n.text === "string" && typeof n.at === "number" && NOTICE_KINDS.includes(n.kind) && typeof n.id === "string";
  function noticesPrune() {
    const from = Date.now() - keepMs();
    bell.list = bell.list.filter((n) => n.at >= from).slice(-NOTICE_MAX);
  }
  // Журнал текущего оператора: сменился ключ (вошёл другой) — читается свой
  function noticeJournal() {
    const key = noticeKey();
    if (!key) return null;
    if (bell.key !== key) {
      bell.key = key;
      bell.fresh.clear();
      let list = [];
      try {
        const parsed = JSON.parse(localStorage.getItem(key) || "[]");
        list = Array.isArray(parsed) ? parsed.filter(validNotice) : [];
      } catch (e) {
        list = [];
      }
      bell.list = list;
      noticesPrune();
      // Записанное до сессии — в журнал оператора и сразу в браузер
      if (bell.pending.length) {
        bell.list.push(...bell.pending.splice(0));
        noticesSave();
      }
    }
    return bell.list;
  }
  function noticesSave() {
    if (!bell.key) return;
    try {
      localStorage.setItem(bell.key, JSON.stringify(bell.list));
    } catch (e) {
      /* хранилище недоступно — журнал до перезагрузки */
    }
  }
  // Запись в колокольчик: kind — action (нужно действие), system (состояние поста), info (сведения); guid — к инциденту
  function notice(text, opts) {
    const o = opts || {};
    const n = { id: `${Date.now().toString(36)}-${(bell.seq++).toString(36)}`, at: Date.now(), text: String(text), kind: NOTICE_KINDS.includes(o.kind) ? o.kind : "info", read: false };
    if (o.guid) n.guid = o.guid;
    if (o.number) n.number = o.number;
    const list = noticeJournal();
    if (!list) {
      bell.pending.push(n);
      return n;
    }
    list.push(n);
    noticesPrune();
    // Панель открыта — запись прочитана, выделена как новая
    if (bell.open) {
      n.read = true;
      bell.fresh.add(n.id);
    }
    noticesSave();
    renderBell();
    return n;
  }
  const inBellTab = (n) => bell.tab === "all" || n.kind === bell.tab;
  // Открыл панель — прочитано всё (§22.5): число на колокольчике — 0; непрочитанные до открытия выделены, пока панель открыта
  function bellMarkRead() {
    const list = noticeJournal() || [];
    let changed = false;
    list.forEach((n) => {
      if (!n.read) {
        n.read = true;
        bell.fresh.add(n.id);
        changed = true;
      }
    });
    if (changed) noticesSave();
  }
  function openBell(tab) {
    bell.open = true;
    if (tab) bell.tab = tab;
    noticeJournal();
    noticesPrune();
    bellMarkRead();
    const panel = $("bellPanel");
    const bar = document.querySelector(".topbar");
    if (bar) panel.style.top = `${Math.round(bar.getBoundingClientRect().bottom)}px`;
    renderBell();
    panel.hidden = false;
    $("bellBtn").setAttribute("aria-expanded", "true");
    const first = panel.querySelector(`[data-bell-tab="${bell.tab}"]`);
    if (first) first.focus();
  }
  function closeBell(focus) {
    bell.open = false;
    bell.fresh.clear();
    $("bellPanel").hidden = true;
    $("bellBtn").setAttribute("aria-expanded", "false");
    renderBell();
    if (focus) $("bellBtn").focus();
  }
  const BELL_TABS = [
    ["all", "Все"],
    ["action", "Нужно действие"],
    ["system", "Система"],
  ];
  function renderBell() {
    const btn = $("bellBtn");
    if (!btn) return;
    const list = noticeJournal() || bell.pending;
    const unread = list.filter((n) => !n.read).length;
    const count = $("bellCount");
    count.textContent = String(unread);
    count.hidden = !unread;
    const label = unread ? t("Оповещения: непрочитанных {n}", { n: unread }) : t("Оповещения");
    btn.title = label;
    btn.setAttribute("aria-label", label);
    $("bellTabs").innerHTML = BELL_TABS.map(
      ([id, name]) => `<button type="button" role="tab" class="bell-tab" data-bell-tab="${id}" aria-selected="${bell.tab === id}">${te(name)}</button>`
    ).join("");
    // Вкладка «Система»: сверху — идущие состояния поста полностью, с их кнопками (§22.4)
    const states = postActive().map((p) => postItemHtml(p, true));
    $("bellStates").innerHTML = states.join("");
    $("bellStates").hidden = bell.tab !== "system" || !states.length;
    // Список — заново, только если в нём что-то поменялось: строку поста перерисовывают часто
    const sig = `${bell.key}|${bell.tab}|${LANG}|${list.length}|${list.length ? list[list.length - 1].id : ""}|${unread}|${bell.fresh.size}`;
    if (sig === bell.drawn) return;
    bell.drawn = sig;
    const shown = [...list].reverse().filter(inBellTab);
    const when = (at) => fmtTime(new Date(at).toISOString());
    $("bellList").innerHTML = shown.length
      ? shown
          .map((n) => {
            const text = n.guid ? `<button type="button" class="link-btn" data-notice-go="${escapeHtml(n.guid)}" data-number="${escapeHtml(n.number || "")}">${escapeHtml(n.text)}</button>` : escapeHtml(n.text);
            return `<li class="notice ${n.kind}${bell.fresh.has(n.id) ? " unread" : ""}" data-notice="${escapeHtml(n.id)}" data-kind="${n.kind}" data-at="${n.at}"><time>${escapeHtml(when(n.at))}</time><span class="notice-text">${text}</span></li>`;
          })
          .join("")
      : `<li class="notice-empty">${te("Записей нет")}</li>`;
  }

  function bindBell() {
    window.addEventListener("resize", () => fitHead());
    $("bellBtn").addEventListener("click", () => (bell.open ? closeBell(false) : openBell()));
    $("bellClose").addEventListener("click", () => closeBell(true));
    $("bellPanel").addEventListener("click", (e) => {
      const tab = e.target.closest("[data-bell-tab]");
      if (tab) {
        bell.tab = tab.dataset.bellTab;
        bellMarkRead();
        renderBell();
        const now = $("bellTabs").querySelector(`[data-bell-tab="${bell.tab}"]`);
        if (now) now.focus();
        return;
      }
      const go = e.target.closest("[data-notice-go]");
      if (go) soundGo(go.dataset.noticeGo, go.dataset.number || go.textContent);
    });
    $("bellPanel").addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        closeBell(true);
      }
    });
  }

  /* ===== Строка состояния поста (§22.4) ===== */

  // Связь: поток событий оборвался или признак активности не дошёл — «Нет связи с агентом»
  const conn = { stream: true, heartbeat: true };
  // Пункты — из машины (display.postStatus) по убыванию серьёзности; active — что длится сейчас. «Мало места на диске»
  // (adminOnly) — только администратору, в «и ещё N» у оператора не входит. Видно самое серьёзное и «и ещё N»
  function postStatusLine(active, defs, isAdmin) {
    const list = (defs || []).filter((d) => active.includes(d.id) && (!d.adminOnly || isAdmin));
    return { top: list[0] || null, more: Math.max(0, list.length - 1), all: list };
  }
  // Что длится сейчас. Источника «мало места на диске» в прототипе нет (§17)
  function postNow() {
    const out = [];
    if (!conn.stream || !conn.heartbeat) out.push("connection");
    if (soundOn() && !soundOut().ready()) out.push("sound_off");
    if ((store.maint.windows || []).length) out.push("maintenance");
    if (soundOn() && onlyImportant()) out.push("only_important");
    return out;
  }
  const postDefs = () => (WORKFLOW && WORKFLOW.display && WORKFLOW.display.postStatus) || [];
  const postActive = () => postStatusLine(postNow(), postDefs(), can("incident:schema:admin")).all;
  const POST_ICON = { connection: "⚠", disk: "⚠", sound_off: "🔇", maintenance: "🛠", only_important: "🔉" };
  const POST_CLASS = { connection: "danger", disk: "warn", sound_off: "warn", maintenance: "info", only_important: "info" };
  // Конец состояния — запись в колокольчике (§22.4)
  const POST_END = {
    connection: "Связь восстановлена",
    disk: "Место на диске освободилось",
    sound_off: "Звук включён",
    maintenance: "Плановые работы закончились",
    only_important: "«Только важное» закончилось — звучит всё",
  };
  // Текст пункта в строке — коротко, простым текстом
  function postShort(def) {
    if (def.id === "maintenance") {
      const ws = store.maint.windows || [];
      const one = (w) => t("{what} — «{desc}», до {until}", { what: w.objectName, desc: w.description || "—", until: fmtUntil(w.endsAt) });
      return ws.length === 1
        ? t("Идут плановые работы: {one}.", { one: one(ws[0]) })
        : t("Идут плановые работы: {n, plural, one {# окно} few {# окна} other {# окон}}, ближайшее закончится в {until}.", { n: ws.length, until: fmtUntil(ws[0].endsAt) });
    }
    if (def.id === "only_important") return t("Только важное до {time}", { time: onlyUntilText() });
    return lbl(def);
  }
  // На вкладке «Система» — полностью (у работ — режим и список окон, §19.1), разметкой
  function postText(def, full) {
    if (!full || def.id !== "maintenance") return escapeHtml(postShort(def));
    const ws = store.maint.windows || [];
    const mark = (WORKFLOW.maintenance || {}).mode === "mark";
    const tail = te(mark ? "Тревоги с этих устройств приходят с пометкой и низшим приоритетом." : "Тревоги с этих устройств не создаются.");
    const item = (w) => te("{what} — «{desc}», с {from} до {until}", { what: w.objectName, desc: w.description || "—", from: fmtUntil(w.startsAt), until: fmtUntil(w.endsAt) });
    return `${escapeHtml(postShort(def))} ${tail}<ul class="maint-list">${ws.map((w) => `<li>${item(w)}</li>`).join("")}</ul>`;
  }
  // Кнопки пункта остаются в нём (§22.4): «Включить звук» (§21.5), «Вернуть» у «Только важного» (§21.4)
  function postButtons(def) {
    if (def.id === "sound_off") return ` <button type="button" class="btn small primary" data-sound-enable>${te("Включить звук")}</button>`;
    if (def.id === "only_important") return ` <button type="button" class="btn small ghost" data-sound-back>${te("Вернуть")}</button>`;
    return "";
  }
  const POST_SOUND_LINE = { sound_off: "off", only_important: "important" };
  // В строке текст — кнопка: щелчок открывает колокольчик на вкладке «Система» (§22.4); more — «и ещё N»
  function postItemHtml(def, full, more) {
    const line = POST_SOUND_LINE[def.id] ? ` data-sound-line="${POST_SOUND_LINE[def.id]}"` : "";
    const icon = `<span aria-hidden="true">${POST_ICON[def.id] || "•"}</span>`;
    const text = full ? `<span class="post-text">${postText(def, true)}</span>` : `<button type="button" class="post-text link-btn" data-post-open>${postText(def, false)}</button>`;
    // Места мало — от пункта остаются значок, кнопки и «+N» (fitHead); полный текст — в подсказке
    const tail = more
      ? ` <button type="button" class="link-btn post-more" data-post-open><span class="more-long">${te("и ещё {n}", { n: more })}</span><span class="more-short">+${more}</span></button>`
      : "";
    const title = full ? "" : ` title="${escapeHtml(more ? `${postShort(def)} · ${t("и ещё {n}", { n: more })}` : postShort(def))}"`;
    return `<div class="post-item ${POST_CLASS[def.id] || "info"}" data-post-state="${escapeHtml(def.id)}"${line}${title}>${icon} ${text}${postButtons(def)}${tail}</div>`;
  }
  let postPrev = null;
  // Что длилось при входе: ни начало, ни конец такого состояния в журнал не пишутся (§22.4)
  let postAtEntry = null;
  // Шапка тесна (§22.1, §22.4): сжимается текст пункта поста; почти не осталось — от пункта значок, кнопки и «+N».
  // Звук в середине шапки места не занимает: звенящий значок и «Тихо» — у колокольчика (§21.4). root — документ
  // (самопроверка мерит копию шапки)
  function fitHead(root) {
    const doc = root || document;
    const box = doc.querySelector(".topbar .post-status");
    const item = doc.querySelector(".topbar .post-item");
    // Гарантированный минимум (§22.4): ширина пункта с короткими метками и без текста — значок, цвет, кнопки, «+N»
    if (box) {
      box.style.minWidth = "";
      if (item) {
        item.classList.remove("tight");
        item.classList.add("fit-min");
        // Замер — без сжатия: пункт — гибкий элемент своей полосы и иначе сжался бы под неё
        item.style.width = "max-content";
        item.style.flexShrink = "0";
        const min = Math.ceil(item.getBoundingClientRect().width);
        item.style.width = "";
        item.style.flexShrink = "";
        item.classList.remove("fit-min");
        if (min) box.style.minWidth = `${min}px`;
      }
    }
    const text = item && item.querySelector(".post-text");
    if (text && text.scrollWidth > text.clientWidth + 1 && text.clientWidth < 48) item.classList.add("tight");
  }
  function renderPost() {
    const box = $("postStatus");
    if (!box || !WORKFLOW) return;
    const line = postStatusLine(postNow(), postDefs(), can("incident:schema:admin"));
    box.innerHTML = line.top ? postItemHtml(line.top, false, line.more) : "";
    box.hidden = !line.top;
    // Начало и конец состояния — записи «Система» в колокольчике; то, что длилось при входе, — не начало
    const now = new Set(line.all.map((d) => d.id));
    if (store.session) {
      if (postPrev) {
        line.all.filter((d) => !postPrev.has(d.id)).forEach((d) => notice(postShort(d), { kind: "system" }));
        postDefs()
          .filter((d) => postPrev.has(d.id) && !now.has(d.id))
          .forEach((d) => {
            if (postAtEntry.delete(d.id)) return;
            notice(POST_END[d.id] ? t(POST_END[d.id]) : t("{what} — закончилось", { what: lbl(d) }), { kind: "system" });
          });
      } else postAtEntry = new Set(now);
      postPrev = now;
    }
    fitHead();
    // Вкладка «Система» — идущие состояния полностью, и при закрытой панели: её откроют щелчком по строке
    renderBell();
  }

  /* ===== Загрузка с сервера ===== */

  function queueQuery() {
    return {
      filter: state.filter,
      search: state.search,
      sourceGroupGuid: state.groupId === "all" ? null : state.groupId,
      eventTypeGuid: state.eventTypes.length ? state.eventTypes.join(",") : null,
      scenarioGuid: state.scenarios.length ? state.scenarios.join(",") : null,
      deviceTypeId: state.deviceTypes.length ? state.deviceTypes.join(",") : null,
      priority: state.priorities.join(",") || null,
      // Строки блока «Мне на принятие» в списке не повторяются (§7)
      exceptFilter: blockShown() ? inboxCfg().filter : null,
      page: state.page,
      pageSize: PAGE_SIZE,
      focusGuid: state.selectedId,
    };
  }

  // Блок «Мне на принятие» (§7): какой фильтр, сколько строк, в каком порядке и когда его нет — из машины (display.inboxBlock)
  const inboxCfg = () => (WORKFLOW.display || {}).inboxBlock || null;
  const blockShown = () => {
    const c = inboxCfg();
    return Boolean(c) && !c.hiddenWith.includes(state.filter);
  };
  // У фильтра с counted: false чисел нет (§7): ни на его кнопке, ни на кнопках приоритетов
  const filterCounted = (id) => {
    const f = WORKFLOW.queueFilters.find((x) => x.id === id);
    return Boolean(f) && f.counted !== false;
  };
  // Сужения для чисел кнопок — те же, что у списка, без filter, страницы и блока
  function countersQuery(withPriorities) {
    const q = queueQuery();
    const out = { search: q.search, sourceGroupGuid: q.sourceGroupGuid, eventTypeGuid: q.eventTypeGuid, scenarioGuid: q.scenarioGuid, deviceTypeId: q.deviceTypeId };
    if (withPriorities) out.priority = q.priority;
    return out;
  }
  if (selftestRun)
    window.IM_SELFTEST_UI = {
      get priorityLetters() { return priorityLetters; },
      get headLayout() { return headLayout; },
      get freezeAbove() { return freezeAbove; },
      get hiddenBy() { return hiddenBy; },
      get postStatusLine() { return postStatusLine; },
      get lateText() { return lateText; },
      get fitHead() { return fitHead; },
      conn,
      heartbeat: () => heartbeat(true),
      toast: (text, kind) => toast(text, kind),
      skippedText: (skipped) => skippedText(skipped),
      // Время итога на плашке — короче для самопроверки; null — обычное
      toastMs: (ms) => {
        toastMs = ms || TOAST_MS;
      },
      // Журнал колокольчика — заново из браузера, как после перезагрузки страницы (§22.5)
      noticeReload: () => {
        bell.key = null;
        renderBell();
      },
      noticeKey: () => noticeKey(),
    };
  const queueItem = (guid) => store.page.items.find((e) => e.guid === guid) || store.block.items.find((e) => e.guid === guid) || null;

  /* ===== Новые строки и скрытое фильтром (§22.1, §22.3) ===== */

  // Заморозка выше курсора: shown — строки на экране, next — ответ сервера, anchorGuid — строка под курсором.
  // Она и всё выше неё — на своих местах: есть у сервера — с новыми данными, ушла — та же строка с gone (бледная,
  // без кнопок, решение 7). Новые строки, которые сервер ставит выше якоря, копятся в newAbove; ниже якоря — как
  // прислал сервер. Якоря нет на экране — заморозки нет
  function freezeAbove(shown, next, anchorGuid) {
    const at = anchorGuid == null ? -1 : shown.findIndex((r) => r.guid === anchorGuid);
    if (at === -1) return { rows: next.slice(), newAbove: [] };
    const pos = new Map(next.map((r, i) => [r.guid, i]));
    const top = shown.slice(0, at + 1).map((r) => (pos.has(r.guid) ? next[pos.get(r.guid)] : Object.assign({}, r, { gone: true })));
    const kept = new Set(top.map((r) => r.guid));
    const was = new Set(shown.map((r) => r.guid));
    // Граница в новом порядке — место якорной строки у сервера (ушла — ближайшей над ней, что ещё есть), а не самая
    // нижняя из замороженных: строка, которую сервер увёл ниже якоря, не делает новые строки под якорем «новыми выше»
    let edge = -1;
    for (let k = top.length - 1; k >= 0 && edge === -1; k--) if (!top[k].gone) edge = pos.get(top[k].guid);
    const newAbove = [];
    const below = [];
    next.forEach((r, i) => {
      if (kept.has(r.guid)) return;
      if (!was.has(r.guid) && i < edge) newAbove.push(r);
      else below.push(r);
    });
    return { rows: top.concat(below), newAbove };
  }

  // Что прячет строку инцидента от оператора (§22.3): incident — IncidentSummary (filters — фильтры машины, которые он
  // проходит для читающего), q — выбор оператора. Блок «Мне на принятие» фильтрами не сужается (§7): инцидент его
  // фильтра при видимом блоке не спрятан. Сценарий, узел дерева и поиск строка не несёт — клиент их не проверяет
  // (решение 6 плана 87в): заданы — значит могут прятать (UNSURE)
  const UNSURE = ["scenario", "node", "search"];
  function hiddenBy(incident, q) {
    const filters = incident.filters || [];
    if (q.blockFilter && filters.includes(q.blockFilter)) return [];
    const out = [];
    if (!filters.includes(q.filter)) out.push("filter");
    if (q.priorities.length && !q.priorities.includes(incident.priority)) out.push("priority");
    if (q.eventTypes.length && !q.eventTypes.includes(incident.eventType && incident.eventType.guid)) out.push("eventType");
    if (q.deviceTypes.length && !q.deviceTypes.includes(incident.sourceDeviceTypeId)) out.push("deviceType");
    if (q.scenarios.length) out.push("scenario");
    if (q.groupId && q.groupId !== "all") out.push("node");
    if (q.search) out.push("search");
    return out;
  }
  const filterChoice = () => ({
    filter: state.filter,
    priorities: state.priorities,
    eventTypes: state.eventTypes,
    deviceTypes: state.deviceTypes,
    scenarios: state.scenarios,
    groupId: state.groupId,
    search: state.search,
    blockFilter: blockShown() ? inboxCfg().filter : null,
  });
  // Последние известные строки инцидентов — из потока и ответов очереди: по ним — что прячет звучащее
  const incCache = new Map();
  function noteIncidents(items) {
    items.forEach((e) => e && e.guid && incCache.set(e.guid, e));
    if (incCache.size > 1000) [...incCache.keys()].slice(0, incCache.size - 1000).forEach((k) => incCache.delete(k));
  }
  // Строка спрятана: её нет ни в списке, ни в блоке, и что-то из выбора оператора может её прятать. Нет ничего —
  // она просто на другой странице
  function hiddenNow(guid) {
    const inc = incCache.get(guid);
    if (!inc || queueItem(guid)) return false;
    return hiddenBy(inc, filterChoice()).length > 0;
  }

  // К звучащему скрытому — щелчок по звенящему значку (§22.3, прежнее «Показать»): состояние — «Открытые», а если там его нет — фильтр, где он есть;
  // мешающие приоритеты, типы — долой; сценарий, поиск и узел — только если без них строки всё равно нет
  // (решение 6); затем очередь на странице инцидента и прокрутка к строке. «Сбросить фильтры» (§7) — другое: узел не трогает
  async function showHidden(guid) {
    const inc = incCache.get(guid);
    if (!inc) return;
    const why = hiddenBy(inc, filterChoice());
    const fs = WORKFLOW.queueFilters;
    const filters = inc.filters || [];
    const filter = filters.includes(fs[0].id) ? fs[0].id : ([...fs].reverse().find((f) => filters.includes(f.id)) || fs[0]).id;
    Object.assign(state, { filter, tbOpen: null, stateMenu: false });
    if (why.includes("priority")) state.priorities = [];
    if (why.includes("eventType")) state.eventTypes = [];
    if (why.includes("deviceType")) state.deviceTypes = [];
    const load = async () => {
      Object.assign(state, { selectedId: guid, page: 1, focus: false, jump: true });
      dropSelection();
      renderTypeLists();
      await reload();
      while (loading) await loading;
    };
    await load();
    if (!queueItem(guid) && (state.scenarios.length || state.search || state.groupId !== "all")) {
      Object.assign(state, { scenarios: [], search: "", groupId: "all", tbQ: {} });
      $("eventSearch").value = "";
      await load();
    }
    const row = $("eventsList").querySelector(`[data-id="${CSS.escape(guid)}"]`);
    if (row) row.scrollIntoView({ block: "nearest" });
    else toast(t("{id} скрыт фильтром очереди", { id: inc.number }));
  }

  // Всё, что видно на экране, — заново с сервера: сессия, страница очереди, счётчики, дерево,
  // карточка выбранного. Запросы во время загрузки не теряются: загрузка повторится один раз
  let loading = null;
  let reloadAgain = false;
  function reload() {
    if (loading) {
      reloadAgain = true;
      return loading;
    }
    loading = (async () => {
      const focus = state.focus;
      const jump = state.jump;
      state.focus = false;
      state.jump = false;
      const cfg = inboxCfg();
      let [session, page, counters, tree, maint, stateCounts, priCounts, block] = await Promise.all([
        api.get("/operator/session"),
        api.get("/operator/incidents", queueQuery()),
        api.get("/operator/incidents/counters"),
        api.get("/operator/reference/source-groups", { withCounters: true }),
        fetchMaintenance(),
        // Числа состояний — без выбранного состояния, числа приоритетов — без выбранных приоритетов (§7)
        api.get("/operator/incidents/counters", countersQuery(true)),
        filterCounted(state.filter) ? api.get("/operator/incidents/counters/priorities", Object.assign({ filter: state.filter }, countersQuery(false))) : null,
        // Блок — свой запрос: только его фильтр и порядок, остальные фильтры очереди его не прячут (§7)
        blockShown() ? api.get("/operator/incidents", { filter: cfg.filter, sort: cfg.sort, pageSize: cfg.maxRows, page: 1 }) : { items: [], total: 0 },
      ]);
      store.maint = maint;
      scheduleMaintenance();
      // После действия очередь открывается на странице с выбранным инцидентом
      if (jump && page.focusPage && page.focusPage !== page.page) {
        state.page = page.focusPage;
        page = await api.get("/operator/incidents", queueQuery());
      }
      noteServerTime(page.items);
      noteIncidents(page.items.concat(block.items));
      Object.assign(store, { session, page, counters, tree, stateCounts, priCounts, block });
      soundSession();
      state.page = page.page;
      if (!state.openGroups.size && !state.treeSeen) {
        tree.forEach((n) => state.openGroups.add(n.guid));
        state.treeSeen = true;
      }
      // Если выбранное событие спрятал фильтр, поиск или другая группа, выделение
      // переходит на первое видимое: иначе видеомонитор и карта показывают чужую зону.
      if (state.mode === "queue" && focus && page.focusPage == null && !block.items.some((e) => e.guid === state.selectedId)) {
        state.selectedId = page.items.length ? page.items[0].guid : null;
      }
      await loadCard();
      renderAll();
      // Очередь открыта на странице выбранного — и строка выбранного видна, а не за краем списка
      if (jump && state.mode === "queue") {
        const row = $("eventsList").querySelector(".event.selected");
        if (row) row.scrollIntoView({ block: "nearest" });
      }
    })()
      .catch((err) => toast(problemText(err), "error"))
      .finally(() => {
        loading = null;
        if (reloadAgain) {
          reloadAgain = false;
          reload();
        }
      });
    return loading;
  }

  // Идущие окна работ (ТЗ-21, §14.12): сервер отдаёт только видимые оператору; не ответил — полосы нет
  const fetchMaintenance = () => api.get("/operator/maintenance-windows/current").catch(() => ({ windows: [], nextChangeAt: null }));
  let maintTimer = null;
  // Окно начинается и кончается по времени, без события потока: список перечитывается в nextChangeAt
  function scheduleMaintenance() {
    clearTimeout(maintTimer);
    const at = store.maint.nextChangeAt ? Date.parse(store.maint.nextChangeAt) : NaN;
    if (Number.isNaN(at)) return;
    maintTimer = setTimeout(refreshMaintenance, Math.min(Math.max(at - serverNow(), 0) + 500, 864e5));
  }
  async function refreshMaintenance() {
    store.maint = await fetchMaintenance();
    scheduleMaintenance();
    renderPost();
    renderGroups();
  }

  async function loadCard() {
    const id = state.selectedId;
    store.card = id ? await api.get(incPath(id)).catch(() => null) : null;
    noteServerTime([store.card]);
    if (store.card) focusCameras(store.card);
    await loadLinked();
    heartbeat();
  }

  // Привязанные инциденты основного (§11) — постранично: их может быть сколько угодно.
  // Другая карточка — с первой страницы; страница опустела (отсоединили) — на последнюю
  const LINKED_PAGE = 10;
  // Привязанные этой карточки, найденные поиском очереди: строка основного несёт их в matchedLinked
  function foundLinked(guid) {
    const row = state.search && store.page.items.find((x) => x.guid === guid);
    return (row && row.matchedLinked) || [];
  }
  async function loadLinked() {
    const ev = store.card;
    if (!ev || !ev.linkedCount) {
      store.linked = null;
      return;
    }
    // Другая карточка — с первой страницы; открыта из поиска — со страницы найденного
    const fresh = !store.linked || store.linked.guid !== ev.guid;
    if (fresh) Object.assign(state, { linkedPage: 1, linkedFocus: (foundLinked(ev.guid)[0] || {}).guid || null });
    const get = (extra) => api.get(`${incPath(ev.guid)}/linked`, Object.assign({ page: state.linkedPage, pageSize: LINKED_PAGE }, extra)).catch(() => null);
    let page = await get(fresh && state.linkedFocus ? { focusGuid: state.linkedFocus } : {});
    if (page && page.focusPage && page.focusPage !== state.linkedPage) {
      state.linkedPage = page.focusPage;
      page = await get();
    }
    if (page && !page.items.length && page.total) {
      state.linkedPage = Math.ceil(page.total / LINKED_PAGE);
      page = await get();
    }
    store.linked = page && Object.assign(page, { guid: ev.guid });
  }

  // Признак активности оператора (§12.3) и какая карточка открыта (§9, порядок срабатывания, пункт 3): раз в
  // session.heartbeatSec и сразу, как только открытая карточка сменилась. Без него сервер
  // через idleHoldSec отложит инцидент оператора с причиной «нет связи»
  let lastOpen = undefined;
  function heartbeat(always) {
    const open = state.selectedId || null;
    if (!always && open === lastOpen) return;
    lastOpen = open;
    // Не дошёл — «Нет связи с агентом» в строке поста, пока следующий не дойдёт (§22.4)
    api
      .post("/operator/session/heartbeat", { openIncidentGuid: open })
      .then(() => setConn("heartbeat", true))
      .catch(() => setConn("heartbeat", false));
  }
  function setConn(what, ok) {
    if (conn[what] === ok) return;
    conn[what] = ok;
    renderPost();
  }

  // Выделенное событие: в карточке и для видео — полная карточка, в очереди — строка
  function selected() {
    if (store.card && store.card.guid === state.selectedId) return store.card;
    return queueItem(state.selectedId);
  }

  /* ===== Сценарий: сценарий и прохождение приходят в карточке (IncidentScenario, §14.5) =====
     Сценарий — формат машины сценариев (Specification/Scenario_machine/), прохождение ведёт сервер машиной сценариев:
     путь, курсор, прогресс, что дальше после ответа. Карточка показывает шаги пути и отправляет ответ. */

  const scenarioOf = (ev) => (ev && ev.scenario) || null;
  const pathOf = (ev) => (scenarioOf(ev) ? scenarioOf(ev).path : []);
  // Шаги впереди по кратчайшему пути до конца — серым, перейти на них нельзя: могут измениться от ответов (RULE-95)
  const aheadOf = (ev) => (scenarioOf(ev) ? scenarioOf(ev).ahead || [] : []);
  const stepOf = (ev, id) => (scenarioOf(ev) ? scenarioOf(ev).script.steps.find((s) => s.id === id) || null : null);
  const entryOf = (ev, id) => (scenarioOf(ev) && scenarioOf(ev).result.state[id]) || null;
  const runDone = (ev) => Boolean(scenarioOf(ev) && scenarioOf(ev).result.completedAt);
  const stepShort = (step) => step.title || step.view.label;
  // Обязательность (спецификация, раздел 9): Checkbox — minSelected > 0, Image — никогда, кнопку надо нажать
  function stepRequired(step) {
    if (step.type === "Message") return true;
    if (step.type === "Checkbox") return step.view.minSelected > 0;
    return step.type !== "Image" && step.view.required === true;
  }
  // Макрос, запущенный ответом на шаг, — из прохождения
  const macrosOf = (ev, id) =>
    scenarioOf(ev) ? scenarioOf(ev).result.history.filter((h) => h.stepId === id && h.action === "macro").map((h) => h.name) : [];

  // Ответ словами — у шагов пути
  function answerText(step, entry) {
    if (!entry) return "";
    if (entry.skipped) return t("Пропущено");
    const label = (options, id) => {
      const o = options.find((x) => x.id === id);
      return o ? t(o.label) : id;
    };
    const v = step.view;
    if (step.type === "Message") return t(v.label);
    if (step.type === "Image") return t("Фото: {n}", { n: 1 });
    if (step.type === "Select") return v.lists.flatMap((l) => (entry.value[l.id] || []).map((id) => label(l.options, id))).join(", ");
    if (step.type === "Checkbox") return entry.value.map((id) => label(v.options, id)).join(", ");
    if (step.type === "RadioButton") return label(v.options, entry.value);
    if (step.type === "Datetime") return fmtWhen(entry.value);
    return entry.value == null ? t("Прочитано") : String(entry.value);
  }

  // Ответ «дата и время» — местными датой и временем на языке интерфейса, а не строкой ISO (BUG-71)
  // «До» окна работ: сегодня — часы и минуты, другой день — дата и время
  function fmtUntil(value) {
    const locale = (LANGS.find((l) => l.id === LANG) || LANGS[0]).locale;
    const d = new Date(value);
    if (new Date(serverNow()).toDateString() !== d.toDateString()) return fmtWhen(value);
    return d.toLocaleTimeString(locale, { hour12: false, hour: "2-digit", minute: "2-digit" });
  }

  function fmtWhen(value) {
    const locale = (LANGS.find((l) => l.id === LANG) || LANGS[0]).locale;
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return String(value);
    return d.toLocaleString(locale, { hour12: false, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
  }

  // Черновик ответа — до «Далее»: { value, attachments } по инциденту и шагу
  const draftKey = (ev, id) => `${ev.guid}:${id}`;
  const draftOf = (ev, id) => state.drafts.get(draftKey(ev, id));
  function setDraft(ev, id, value, attachments) {
    state.drafts.set(draftKey(ev, id), attachments ? { value, attachments } : { value });
  }
  // Значение по умолчанию из сценария — у шага, на который ещё не отвечали (спецификация, раздел 6)
  function defaultOf(step) {
    const v = step.view;
    if (step.type === "RadioButton") return v.default;
    if (step.type === "Checkbox") return v.options.filter((o) => o.default).map((o) => o.id);
    if (step.type === "Select") return Object.fromEntries(v.lists.map((l) => [l.id, (l.default || []).slice()]));
    if (step.type === "Comment") return v.readonly ? null : v.default || null;
    return null;
  }
  // Что в поле шага: черновик, иначе записанный ответ, иначе значение по умолчанию. Ответом оно станет по «Далее»
  function valueOf(ev, step) {
    const d = draftOf(ev, step.id);
    if (d) return d.value;
    const e = entryOf(ev, step.id);
    if (e) return e.skipped ? null : e.value;
    return defaultOf(step);
  }
  // Есть ли ответ в поле: отмечено, выбрано, написано; у шага «только для показа» отвечать нечего
  function filled(step, value) {
    if (step.type === "Comment" && step.view.readonly) return true;
    if (step.type === "Select") return Boolean(value) && Object.values(value).some((ids) => ids.length > 0);
    if (Array.isArray(value)) return value.length > 0;
    return value != null && String(value).trim() !== "";
  }
  // Ответа в поле хватает обязательному шагу: у Select — в каждом списке, у Checkbox — не меньше minSelected
  function complete(step, value) {
    if (step.type === "Select") return Boolean(value) && step.view.lists.every((l) => (value[l.id] || []).length > 0);
    if (step.type === "Checkbox") return Array.isArray(value) && value.length >= Math.max(step.view.minSelected, 1);
    return filled(step, value);
  }
  // Черновик отличается от записанного ответа
  function changed(ev, step) {
    const d = draftOf(ev, step.id);
    if (!d) return false;
    const e = entryOf(ev, step.id);
    return JSON.stringify(d.value) !== JSON.stringify(e && !e.skipped ? e.value : null);
  }

  // Шаг пути на экране: у владельца — курсор показа сервера, на просмотре — свой, курсор владельца не трогаем
  function cursorOf(ev) {
    const path = pathOf(ev);
    if (!path.length) return 0;
    if (ev.readOnly && state.viewStep.has(ev.guid)) return Math.min(state.viewStep.get(ev.guid), path.length - 1);
    const i = path.lastIndexOf(ev.scenario.cursorStepId);
    return i === -1 ? path.length - 1 : i;
  }
  // Текущий шаг прохождения — последний шаг пути, пока сценарий не пройден
  const isCurrentStep = (ev, i) => !runDone(ev) && i === pathOf(ev).length - 1;
  // Ответ можно менять: на текущем шаге — всегда, на пройденном — если шаг revisitable (профиль МИ)
  const stepEditable = (ev, i, editable) => editable && (isCurrentStep(ev, i) || stepOf(ev, pathOf(ev)[i]).revisitable !== false);
  // Шаг без переответа (revisitable: false) — замок в ленте шагов и подсказка к нему
  const lockedStep = (step) => step.revisitable === false;
  const crumbLock = (step) => (lockedStep(step) ? `<span class="material-symbols-outlined crumb-lock" aria-hidden="true">lock</span>` : "");
  const crumbTitle = (step, extra) =>
    [t(stepShort(step)), extra, lockedStep(step) ? t("Ответ не меняется после перехода дальше") : ""].filter(Boolean).join(" — ");

  // «Далее»: на текущем шаге — есть ответ или шаг можно пропустить (кнопку — только нажать); на пройденном —
  // ответ изменён или впереди есть шаг пути. На последнем шаге пройденного сценария идти некуда (RULE-89)
  function canGoNext(ev, i, editable) {
    const path = pathOf(ev);
    const step = stepOf(ev, path[i]);
    if (!step) return false;
    if (stepEditable(ev, i, editable) && changed(ev, step)) return complete(step, valueOf(ev, step)) || !stepRequired(step);
    if (editable && isCurrentStep(ev, i)) return step.type !== "Message" && (!stepRequired(step) || complete(step, valueOf(ev, step)));
    return i < path.length - 1 || (runDone(ev) && !atSummary(ev));
  }
  // Почему «Далее» и «Назад» недоступны — словами, по нажатию, как у остальных кнопок (BUG-91)
  function nextWhy(ev, i, editable, tab, summary) {
    if (tab !== "scenario") return t("Шаги — на вкладке «Сценарий»");
    if (summary) return t("«Итог» — последний пункт");
    const step = stepOf(ev, pathOf(ev)[i]);
    if (step && ((stepEditable(ev, i, editable) && changed(ev, step)) || (editable && isCurrentStep(ev, i)))) return t("Сначала ответьте на этот шаг");
    return t("Дальше шагов пока нет: сценарий ещё не пройден");
  }
  const backWhy = (tab) => (tab !== "scenario" ? t("Шаги — на вкладке «Сценарий»") : t("Это первый шаг"));
  // Недоступная кнопка — aria-disabled с причиной в title: нажатие её показывает (explainIfOff)
  const offAttr = (on, why) => (on ? "" : `aria-disabled="true" title="${escapeHtml(why)}"`);
  function setOff(btn, off, why) {
    if (off) {
      btn.setAttribute("aria-disabled", "true");
      btn.title = why;
    } else {
      btn.removeAttribute("aria-disabled");
      btn.removeAttribute("title");
    }
  }

  // Шаг «Итог» — после финального шага пройденного сценария: закрытие результатом «Обработан» кнопкой
  // «Завершить инцидент». Карточка встаёт на него, когда сценарий пройден, пока оператор не ушёл на шаги
  const SUMMARY = "__summary__";
  const atSummary = (ev) => runDone(ev) && !state.summaryOff.has(ev.guid) && cursorOf(ev) === pathOf(ev).length - 1;
  // Результат полной обработки из ответа сервера (fieldOptions «Закрыть») — с причиной, если он недоступен
  function processedOption(ev) {
    const close = actionOf(ev, "close");
    const results = close && close.fieldOptions && close.fieldOptions.resultId ? close.fieldOptions.resultId.options : [];
    return results.find((r) => fullyProcessed(r.id)) || null;
  }
  const canFinish = (ev) => !ev.readOnly && canDo("close", ev) && Boolean(processedOption(ev)) && !processedOption(ev).disabled;

  // Название сценария; нет названия — «Без названия». Демо-названия переводит словарь данных, как типы событий
  const scenarioTitle = (ev) => t(ev.scenarioTitle || "Без названия");

  function stepProgress(ev) {
    if (!ev) return { filled: 0, total: 0 };
    return scenarioOf(ev) ? ev.scenario.progress : ev.scenarioProgress;
  }

  async function goToStep(ev, index) {
    const path = pathOf(ev);
    if (index < 0 || index >= path.length) return;
    state.summaryOff.add(ev.guid);
    if (ev.readOnly) {
      state.viewStep.set(ev.guid, index);
      renderScenario();
      renderStatus();
      return;
    }
    // Ушли с шага без «Далее» — его черновик не сохранён и сбрасывается: в поле всегда записанный ответ (BUG-70)
    state.drafts.delete(draftKey(ev, path[cursorOf(ev)]));
    try {
      ev.scenario = await api.put(`${incPath(ev.guid)}/scenario/cursor`, { stepId: path[index] });
    } catch (err) {
      toast(problemText(err), "error");
    }
    renderScenario();
    renderStatus();
  }

  // Что видел оператор (§14.1, RULE-142): состояние, адресат ("" — ничей) и последний номер записи журнала. Сервер
  // сверяет их, а не номер версии: эскалация без смены адресата и запись о нарушении действию не мешают
  // Одно отмеченное в выборке — снимок на момент отметки (seenAtMark), а не то, что прочитано перед отправкой (BUG-84)
  // Уровень приоритета — для смены приоритета (RULE-143): она сверяет его, а не адресата; выборкой она не делается
  const seenOf = (ev) =>
    Object.assign(
      ev.seenAtMark
        ? { expectedState: ev.seenAtMark.state, expectedAddressee: ev.seenAtMark.addressee || "", journalSeen: ev.seenAtMark.journalSeq || 0 }
        : { expectedState: ev.state, expectedAddressee: (ev.addressee && ev.addressee.id) || "", journalSeen: ev.journalSeq || 0 },
      ev.priority != null ? { expectedPriority: ev.priority } : {}
    );
  // Ответ на шаг: владелец и ответ шага, каким его видел оператор (null — без ответа): ответ из другой вкладки
  // или второе нажатие сервер не перепишет молча — 409 STEP_CHANGED
  const answerSeenOf = (ev, stepId) => {
    const was = ev.scenario && ev.scenario.result && (ev.scenario.result.state || {})[stepId];
    return { expectedOwner: (ev.owner && ev.owner.id) || "", seenAnswer: (was && was.answeredAt) || null };
  };

  // Ответ на шаг — серверу (POST …/scenario/answer); пустой необязательный шаг — пропуск. Что дальше — решает сервер
  async function submitStep(ev, step) {
    const d = draftOf(ev, step.id);
    const value = valueOf(ev, step);
    const body = Object.assign({ stepId: step.id }, answerSeenOf(ev, step.id));
    if (step.type === "Message") body.value = null;
    else if (!filled(step, value) && !stepRequired(step)) body.skip = true;
    else Object.assign(body, { value }, d && d.attachments ? { attachments: d.attachments } : {});
    try {
      ev.scenario = await api.post(`${incPath(ev.guid)}/scenario/answer`, body);
      state.drafts.delete(draftKey(ev, step.id));
    } catch (err) {
      // Опоздал — инцидент уже ведёт другой: мягкое «Уже взял Петров», уходит само, как у перехода (§14.1, §22.6)
      const late = lateText("answer", err, store.session && store.session.operator.guid);
      if (late) toast(late, "late");
      else toast(problemText(err), "error");
    }
    // Ответ меняет путь, доступность «Обработан», прогресс и журнал — карточку заново
    await loadCard();
    // Ответ завершил сценарий — карточка на шаге «Итог»: закрывает оператор, «Завершить инцидент» (§7)
    if (runDone(selected())) state.summaryOff.delete(ev.guid);
    renderScenario();
    renderStatus();
  }

  async function goNextStep(ev) {
    const i = cursorOf(ev);
    const path = pathOf(ev);
    const step = stepOf(ev, path[i]);
    if (!ev.readOnly && (isCurrentStep(ev, i) || (stepEditable(ev, i, true) && changed(ev, step)))) return submitStep(ev, step);
    if (i === path.length - 1 && runDone(ev)) return openSummary(ev);
    return goToStep(ev, i + 1);
  }

  async function openSummary(ev) {
    const last = pathOf(ev).length - 1;
    if (cursorOf(ev) !== last) await goToStep(ev, last);
    state.summaryOff.delete(ev.guid);
    renderScenario();
    renderStatus();
  }

  // «Завершить инцидент» на шаге «Итог» — переход «Закрыть» с результатом полной обработки, без формы
  async function finishIncident(ev) {
    if (!canFinish(ev)) return;
    const d = state.drafts.get(draftKey(ev, SUMMARY));
    if (await runTransition("close", ev, { resultId: processedOption(ev).id, comment: d ? d.value.trim() : "" }, "card")) state.drafts.delete(draftKey(ev, SUMMARY));
  }

  /* ===== Слой представления: моё, чужое, бейджи (§2.4) — считает сервер ===== */

  const isDone = (ev) => Boolean(ev) && ev.stateCategory === "done";
  const isMine = (ev) => Boolean(ev) && ev.ownership === "owner";
  const isTarget = (ev) => Boolean(ev) && ev.ownership === "target";

  function logVar(value) {
    if (Array.isArray(value)) return t(value[0], logVars(value[1]));
    return typeof value === "string" ? t(value) : value;
  }
  function logVars(vars) {
    const out = {};
    Object.entries(vars || {}).forEach(([key, value]) => (out[key] = logVar(value)));
    return out;
  }
  const journalText = (entry) => t(entry.templateKey || entry.text || "", logVars(entry.vars));

  /* ===== Таймеры (§4): дедлайны — метки времени, отсчёт рисует клиент ===== */

  function timerView(timer) {
    if (!timer) return null;
    const leftMs = timer.running && timer.dueAt ? Date.parse(timer.dueAt) - serverNow() : timer.remainingMs;
    return { kind: timer.id, label: timer.label, leftMs, running: timer.running, due: timer.running ? Date.parse(timer.dueAt) : null };
  }

  function badgeView(ev) {
    return { text: t(ev.badge.template || ev.badge.label, logVars(ev.badge.vars)), cls: ev.badge.style };
  }

  const holdLabel = (id) => {
    const item = WORKFLOW.reasonCatalogs.hold.items.find((r) => r.id === id);
    return item ? lbl(item) : t("Причина не указана");
  };
  // Подпись закрытого; причина — снимок названия на момент закрытия (closeCauseLabel), если подпись не она сама
  const resultLabel = (ev) => {
    const r = t(ev.closeResultLabel || "");
    const result = WORKFLOW.reasonCatalogs.close_result.items.find((i) => i.id === ev.closeResultId);
    if (!result || !result.causeCatalog || result.labelByCause || !ev.closeCauseId) return r;
    const item = ((WORKFLOW.reasonCatalogs[result.causeCatalog] || {}).items || []).find((i) => i.id === ev.closeCauseId);
    const cause = item ? lbl(item) : ev.closeCauseLabel;
    return cause ? `${r}: ${cause}` : r;
  };
  // Результат полной обработки — с признаком finish в справочнике close_result машины (§2.2, ARCH-08 в7):
  // им закрывает «Итог», в форме «Закрыть» без обработки его нет
  const fullyProcessed = (resultId) => {
    const item = WORKFLOW.reasonCatalogs.close_result.items.find((i) => i.id === resultId);
    return Boolean(item && item.finish);
  };

  /* ===== Действия: какие кнопки доступны, считает сервер (AvailableAction) ===== */

  const transitionDef = (id) => WORKFLOW.transitions.find((x) => x.id === id) || null;
  const navDef = (id) => WORKFLOW.navActions.items.find((x) => x.id === id) || null;
  const isNav = (id) => Boolean(navDef(id));
  const actionOf = (ev, id) => (ev && ev.actions ? ev.actions.find((a) => a.id === id) : null) || null;
  const canDo = (id, ev) => Boolean(actionOf(ev, id) && actionOf(ev, id).enabled);
  const actionWhy = (a) => (a && a.reasonKey ? say(a.reasonKey, a.reasonVars) : "");

  // «Закрыть» в ряду действий и в очереди — закрытие без обработки: результатом, кроме «Обработан», на любом этапе.
  // «Обработан» — «Завершить инцидент» на шаге «Итог»
  const actionLabel = (a) => (a.id === "close" ? t("Закрыть без обработки") : t(a.label));

  function actionView(a) {
    const def = a.kind === "nav" ? navDef(a.id) : transitionDef(a.id);
    const closeHint = t("Закрыть результатом, кроме «Обработан»: ложная тревога, дубликат и другие — с комментарием");
    return {
      id: a.id,
      label: actionLabel(a),
      hint: a.enabled ? (a.id === "close" ? closeHint : hasLbl(def, "hint") ? lbl(def, "hint") : t(a.label)) : actionWhy(a),
      style: a.style || "outline",
      icon: a.icon || null,
      disabled: !a.enabled,
      nav: a.kind === "nav",
      // Место в карточке — из машины (ui.placement, ui.danger перехода, §7): primary, menu или header
      placement: a.placement || "menu",
      danger: Boolean(a.danger),
    };
  }

  // Действие над выборкой — по ответу сервера на /incidents/selection (режимы bulk машины, §11)

  // Действия выборки — и для одного отмеченного: панель над очередью показывает, что с ним можно
  async function updateSelection() {
    if (!state.checked.size) {
      store.selection = null;
      checkedSeen.clear();
      return;
    }
    store.selection = await api.post("/operator/incidents/selection", { mode: "explicit", incidentGuids: [...state.checked] });
    // Что видел — на момент отметки: у отмеченного раньше не обновляется (BUG-84)
    [...checkedSeen.keys()].forEach((g) => state.checked.has(g) || checkedSeen.delete(g));
    Object.entries(store.selection.expected || {}).forEach(([g, v]) => checkedSeen.has(g) || checkedSeen.set(g, v));
  }
  // Что видел оператор у отмеченных на момент отметки (состояние, адресат, номер записи журнала) — серверу в expected:
  // изменённое после отметки он не тронет (§14.1, BUG-84, RULE-142)
  const checkedSeen = new Map();
  // Снять выборку — вместе со снимком: отмеченный снова получит его на момент новой отметки (BUG-106)
  function dropSelection() {
    state.checked.clear();
    store.selection = null;
    checkedSeen.clear();
  }
  // Новая выборка вместо прежней — тоже новая отметка: снимок заново (BUG-106)
  function selectOnly(guids) {
    state.checked = new Set(guids);
    checkedSeen.clear();
  }
  const expectedOf = (guids) => Object.fromEntries(guids.filter((g) => checkedSeen.has(g)).map((g) => [g, checkedSeen.get(g)]));
  // Сценарий основного, который назвала форма действия с bulk.scope (§11.1, RULE-142): основной сменился — 412
  const scopeScenarioOf = (id) => ((store.selection && store.selection.actions) || []).map((a) => (a.id === id ? a.scopeScenarioGuid : null)).find(Boolean);
  // Ключ повтора — новый на каждое действие: повтор того же запроса сервер не выполнит дважды (BUG-84)
  const newKey = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`);


  // Тексты действия на выборке: заголовок, пояснение и кнопка — ключами формы машины (bulkTitleKey, bulkNoteKey,
  // bulkConfirmKey, ARCH-08 в9); итог — уведомлением интерфейса. n — сколько инцидентов действие касается
  function bulkCopy(id, n) {
    const tr = transitionDef(id);
    const form = tr && tr.form ? WORKFLOW.forms.find((f) => f.id === tr.form) : null;
    // Итог — ключом перехода машины (ui.bulkDoneKey): {n} — сколько, {who} — адресат из формы
    const done = tr && tr.ui && tr.ui.bulkDoneKey;
    const copy = done ? { toast: (values) => t(done, { n, who: actorName(values.targetId) }) } : {};
    if (form && form.bulkTitleKey) Object.assign(copy, { title: t(form.bulkTitleKey, { n }), note: t(form.bulkNoteKey, { n }), confirm: t(form.bulkConfirmKey, { n }) });
    return Object.keys(copy).length ? copy : null;
  }

  async function openBulkDialog(id, ev, guids, surface) {
    if (guids.length < 2) return false;
    await openDialog(id, ev, surface);
    if (!state.dialog) return false;
    state.dialog.bulkIds = guids;
    // Закроются не все отмеченные — только сценария основного (bulk.scope машины, §11.1, ARCH-15): пояснение — от
    // сервера (сколько закроется, сколько останется открытыми), в заголовке и на кнопке — сколько закроется
    // Узнаётся по ключу пояснения из машины (bulk.scopeNoteKey перехода), а не по строке в коде
    const a = actionOf(ev, id);
    const bulk = (transitionDef(id) || {}).bulk || {};
    const noteKey = bulk.scopeNoteKey;
    const scoped = noteKey && a && a.formNote && a.formNote.key === noteKey ? a.formNote : null;
    const copy = bulkCopy(id, scoped ? scoped.vars.n : guids.length);
    if (copy) {
      $("dialogTitle").textContent = copy.title;
      $("dialogNote").textContent = scoped ? say(scoped.key, scoped.vars) : copy.note;
      $("dialogNote").hidden = false;
      $("dialogConfirm").textContent = copy.confirm;
    }
    return true;
  }

  // Главная причина отказа выборки (§11, BUG-28); номер — если инцидент есть в загруженном списке
  function failureText(failed) {
    const main = failed.find((f) => f.problem.code !== "BULK_SELECTION_INVALID") || failed[0];
    const why = problemText({ problem: main.problem });
    const ev = queueItem(main.incidentGuid);
    return ev ? `${ev.number}: ${why}` : why;
  }

  // Пропущенные сервером — другой сценарий, чем у основного выборки (skipped, §11.1, ARCH-15): по причине — сколько и
  // номера; больше SKIPPED_NUMBERS — два первых и «и ещё N»: плашка итога — одна строка (§22.6, BUG-123)
  const SKIPPED_NUMBERS = 5;
  function skippedText(skipped) {
    const by = new Map();
    (skipped || []).forEach((s) => by.set(s.reasonKey, (by.get(s.reasonKey) || []).concat(s.number)));
    const ids = (numbers) => (numbers.length <= SKIPPED_NUMBERS ? numbers.join(", ") : t("{ids} и ещё {n}", { ids: numbers.slice(0, 2).join(", "), n: numbers.length - 2 }));
    return [...by].map(([key, numbers]) => t("Не закрыты: {n} — {reason}: {ids}", { n: numbers.length, reason: say(key), ids: ids(numbers) })).join(". ");
  }
  // Два предложения уведомления — через точку: «Закрыто: 120. Не закрыты: 450 — другой сценарий»
  const sentences = (...parts) => parts.filter(Boolean).map((x, i, all) => (i < all.length - 1 && !/[.!?…]$/.test(x) ? `${x}.` : x)).join(" ");

  async function runBulk(id, guids, form, surface) {
    let res;
    try {
      const scope = scopeScenarioOf(id);
      res = await api.post(`/operator/incidents/transitions/${enc(id)}/bulk`, Object.assign({ incidentGuids: guids, formValues: form || {}, surface, expected: expectedOf(guids), idempotencyKey: newKey() }, scope ? { expectedScenario: scope } : {}));
    } catch (err) {
      toast(problemText(err), "error");
      // Основной выборки сменился, а действие с bulk.scope выполняется только по нему (412, §11.1, RULE-142): причину
      // оператор увидел, повтор — по нынешнему снимку и с новым пояснением формы (BUG-106)
      if (err && err.problem && err.problem.code === "INCIDENT_CHANGED") {
        checkedSeen.clear();
        await updateSelection();
      }
      return false;
    }
    if (!res.succeeded.length) {
      const why = res.failed.length ? failureText(res.failed) : t("Действие недоступно");
      // Пропущенные другого сценария — названы и здесь: им ничего не сделано (§11.1, ARCH-15)
      toast(sentences(why, skippedText(res.skipped)), "error");
      // Причину оператор увидел: у изменённых после отметки снимок — нынешний, повтор — его решение (BUG-106)
      res.failed.filter((f) => f.problem.code === "INCIDENT_CHANGED").forEach((f) => checkedSeen.delete(f.incidentGuid));
      await updateSelection();
      return false;
    }
    dropSelection();
    // Своё действие — для бледной строки (BUG-121): ответ приходит раньше событий потока
    noteOwn(res.succeeded);
    const done = res.succeeded.map((e) => ({ id: e.guid }));
    const copy = bulkCopy(id, done.length);
    const okText = copy && copy.toast ? copy.toast(form || {}) : t("Обработано: {n}", { n: done.length });
    // Не прошедшие — тоже в уведомлении: сколько и почему (§11, BUG-28)
    const failedText = res.failed.length ? sentences(okText, t("Не выполнено: {n}", { n: res.failed.length }), failureText(res.failed)) : okText;
    toast(sentences(failedText, skippedText(res.skipped)), res.failed.length ? "error" : "done");
    state.selectedId = done[0].id;
    navigate(res.navigate);
    await reload();
    return true;
  }

  function navigate(to) {
    if (to === "card") {
      state.mode = "work";
      state.mobileView = "card";
    } else if (to === "queue") {
      state.mode = "queue";
      state.focus = true;
      state.jump = true;
    }
  }

  // Кнопки очереди и карточки — те, что вернул сервер для этой поверхности (§7)
  // Кнопки строки — всегда только этот инцидент; массовые действия — панель выборки (§11)
  function queueActions(ev) {
    return ev.actions.map(actionView);
  }

  function cardActions(ev) {
    return ev.actions.filter((a) => a.kind === "transition").map(actionView);
  }

  /* ===== Выполнение перехода ===== */

  // Уведомления после перехода — забота интерфейса, а не машины
  const TOASTS = {
    claim: (ev) => t("{id} в работе", { id: ev.number }),
    accept: (ev) => t("{id} принят в работу", { id: ev.number }),
    reject: (ev) => t("{id} возвращён в очередь", { id: ev.number }),
    hold: (ev) => t("{id} отложен", { id: ev.number }),
    release: (ev) => t("{id} возвращён в очередь", { id: ev.number }),
    transfer: (ev) => t("{id} передан → {who}", { id: ev.number, who: actorName(ev.addressee) }),
    takeover: (ev) => t("Перехвачен {id}", { id: ev.number }),
    close: (ev) => t(fullyProcessed(ev.closeResultId) ? "{id} закрыт" : "{id} закрыт без обработки", { id: ev.number }),
    reopen: (ev) => t("{id} переоткрыт", { id: ev.number }),
  };

  async function runTransition(id, ev, form, surface) {
    if (!ev) return false;
    let res;
    try {
      res = await api.post(`${incPath(ev.guid)}/transitions/${enc(id)}`, Object.assign(seenOf(ev), { formValues: form || {}, surface, idempotencyKey: newKey() }));
    } catch (err) {
      // Изменилось то, что видел оператор (412 INCIDENT_CHANGED, RULE-142): карточка — из ответа, без второго запроса
      const current = err && err.problem && err.problem.code === "INCIDENT_CHANGED" ? err.problem.current : null;
      if (current && store.card && store.card.guid === current.guid) store.card = current;
      // Снимок отметки устарел, причину оператор увидел — повтор по нынешнему снимку, а не снова 412 (BUG-106)
      if (err && err.problem && err.problem.code === "INCIDENT_CHANGED") checkedSeen.delete(ev.guid);
      // Опоздал — инцидент уже у другого: мягкое «Уже взял Петров», уходит само (§8.1, §22.6); иначе — ошибка до «✕»
      // с текстом сервера: что изменилось («Пришло новое событие — проверьте»)
      const late = lateText(id, err, store.session && store.session.operator.guid);
      if (late) toast(late, "late");
      else toast(problemText(err), "error");
      await reload();
      return false;
    }
    state.selectedId = ev.guid;
    // Своё действие — для бледной строки (BUG-121): ответ приходит раньше события потока
    noteOwn([res.incident]);
    if (TOASTS[id]) toast(TOASTS[id](res.incident));
    if (state.checked.has(ev.guid)) dropSelection();
    store.selection = null;
    navigate(res.navigate);
    await reload();
    return true;
  }

  /* ===== Формы переходов: строятся по формам машины (forms) и вариантам из ответа сервера ===== */

  // Форма перерыва — не переход инцидента, а состояние оператора (§12): своя, по session машины
  // Пояснение смены состояния оператора — ключом перехода машины (session.transitions[].noteKey) в состояние to
  const sessionNote = (to, vars) => {
    const m = WORKFLOW.session.transitions.find((x) => x.to === to && x.noteKey);
    return m && m.noteKey ? t(m.noteKey, vars || {}) : "";
  };
  // Куда уходит отсоединённый — состояние после «Отсоединить» из машины (to перехода из linked)
  const detachedLabel = () => {
    const tr = WORKFLOW.transitions.find((x) => x.id === "detach");
    return tr && STATES[tr.to] ? lbl(STATES[tr.to]) : "";
  };
  const breakForm = () => ({
    id: "__break__",
    title: "Перерыв",
    confirmLabel: "Уйти на перерыв",
    style: "primary",
    note: sessionNote("not_ready"),
    // Причин у поста нет — поля нет: выбирать не из чего, сервер тогда причину не требует (requiresReasonExpr машины)
    fields: WORKFLOW.session.breakReasons.length
      ? [
          {
            name: "reasonId",
            kind: "select",
            label: "Причина перерыва",
            required: true,
            options: WORKFLOW.session.breakReasons.map((r) => ({ id: r.id, label: lbl(r) })).sort(byName((o) => o.label)),
          },
        ]
      : [],
  });

  // Видно ли поле и обязательно ли — по таблице сервера (fieldRules действия): правила форм вычисляет он.
  // Зависит от другого поля — значение по его выбранному варианту (dependsOn, byValue). Формы самого
  // интерфейса (перерыв, выход) — по required
  function fieldRule(field, values) {
    const r = field.rules;
    const base = !r ? { visible: true, required: Boolean(field.required) } : r.dependsOn ? r.byValue[values[r.dependsOn] || ""] || r.byValue[""] : r;
    // Выбранный вариант другого поля требует комментария (FieldOption.commentRequired, ТЗ-4: причина «Другое»)
    const byOption = field.kind === "text" && state.dialog && state.dialog.form.fields.some((f) => (f.options || []).some((o) => o.commentRequired && o.id === values[f.name] && fieldVisible(f, values)));
    return byOption && base.visible ? Object.assign({}, base, { required: true }) : base;
  }
  const fieldVisible = (field, values) => fieldRule(field, values).visible;
  const fieldRequired = (field, values) => fieldRule(field, values).required;

  const optionLabel = (o) => (o.disabled && o.reason ? `${t(o.label)} — ${t(o.reason)}` : t(o.label));
  // Списки причин — по алфавиту (§2.2, решение 2026-11-15): по показанному названию на языке интерфейса, без
  // учёта регистра и «ё», числа по значению; равные — по id. «Другое» — на своём месте по букве; порядок
  // в настройках поста не важен
  function byName(name) {
    const coll = new Intl.Collator(LANG, { sensitivity: "base", numeric: true });
    return (a, b) => coll.compare(name(a), name(b)) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  }
  const reasonSource = (source) => /^(reasonCatalog|causeCatalog):/.test(String(source || ""));
  const reasonsByName = (field) => (reasonSource(field.source) ? Object.assign({}, field, { options: (field.options || []).slice().sort(byName(optionLabel)) }) : field);

  // «Кому передать» (§8.1): поле с поиском по подстроке имени и роли. Сначала кто на месте, потом кого
  // нет — с причиной; в каждом разделе люди, потом дежурные группы, как их прислал сервер. Значение —
  // в скрытом поле формы, как у обычного списка
  const targetHit = (o, q) => comboHit(`${t(o.label)} ${t(o.role || "")}`, q);
  const targetsOf = (field) => (field.options || []).filter((o) => !o.disabled);
  function targetMenu(field, q, value) {
    const opt = (o) =>
      `<button type="button" class="mselect-opt target-opt ${o.available === false ? "away" : ""}" role="option" tabindex="-1" data-target-pick="${escapeHtml(o.id)}"
        aria-selected="${o.id === value}" ${targetHit(o, q) ? "" : "hidden"}><span>${escapeHtml(t(o.label))}</span><em>${escapeHtml(
        [t(o.role || ""), o.available === false && o.availabilityLabel ? t(o.availabilityLabel) : ""].filter(Boolean).join(" · ")
      )}</em></button>`;
    // Раздел — группа с названием: диктор читает «На месте» вместе с адресатами (BUG-46)
    const section = (title, list, id) =>
      list.length
        ? `<div role="group" aria-labelledby="${id}"><div class="mselect-head" id="${id}" ${list.some((o) => targetHit(o, q)) ? "" : "hidden"}>${te(
            title
          )}</div>${list.map(opt).join("")}</div>`
        : "";
    const all = targetsOf(field);
    return (
      section("На месте", all.filter((o) => o.available !== false), `${field.name}-here`) +
      section("Нет на месте", all.filter((o) => o.available === false), `${field.name}-away`) +
      `<div class="muted mselect-empty" data-combo-none ${all.some((o) => targetHit(o, q)) ? "hidden" : ""}>${te("Никого не найдено")}</div>`
    );
  }
  function renderTargetCombo(name) {
    const open = state.dialog;
    const box = $("dialogFields").querySelector(`[data-target-combo="${name}"]`);
    const field = open && open.form.fields.find((f) => f.name === name);
    if (!box || !field) return;
    const c = open.combo;
    const value = box.querySelector("[data-field]").value;
    const picked = targetsOf(field).find((o) => o.id === value);
    box.classList.toggle("open", c.open);
    box.querySelectorAll(".mselect-input, .mselect-menu").forEach((el) => el.remove());
    const hint = hasLbl(field, "placeholder") ? lbl(field, "placeholder") : "";
    box.insertAdjacentHTML(
      "beforeend",
      comboField("data-target-input", name, c.open, c.q, picked ? [value] : [], () => (picked ? t(picked.label) : ""), hint) +
        (c.open ? `<div class="mselect-menu" role="listbox" id="${name}-targets">${targetMenu(field, c.q, value)}</div>` : "")
    );
    // Имя поля для экранного диктора — подпись и выбранный адресат: «Кому передать, Петрова М.» (BUG-46)
    const input = box.querySelector("[data-target-input]");
    input.setAttribute("aria-label", `${lbl(field)}, ${picked ? t(picked.label) : hint}`);
    input.setAttribute("aria-controls", `${name}-targets`);
  }
  function openTargetCombo(name, q) {
    Object.assign(state.dialog.combo, { open: true, q: q || "" });
    renderTargetCombo(name);
    comboFocus($("dialogFields").querySelector(`[data-target-input="${name}"]`));
  }
  function closeTargetCombo(name, focus) {
    Object.assign(state.dialog.combo, { open: false, q: "" });
    renderTargetCombo(name);
    if (focus) $("dialogFields").querySelector(`[data-target-input="${name}"]`).focus();
  }
  function pickTarget(name, id) {
    $("dialogFields").querySelector(`[data-target-combo="${name}"] [data-field]`).value = id;
    closeTargetCombo(name, true);
    refreshDialogFields();
  }
  // Набор — без перерисовки: прячет неподходящих и пустые разделы
  function narrowTargets(input) {
    const menu = input.parentElement.querySelector(".mselect-menu");
    const field = state.dialog.form.fields.find((f) => f.name === input.dataset.targetInput);
    state.dialog.combo.q = input.value;
    if (menu && field) menu.innerHTML = targetMenu(field, input.value, input.parentElement.querySelector("[data-field]").value);
  }
  // Клавиши: ↓ — открыть и к вариантам, ↑/↓ — по вариантам, Enter — выбрать, Esc — закрыть список, не форму
  function targetKey(e) {
    const combo = e.target.closest("[data-target-combo]");
    if (!combo) return;
    const name = combo.dataset.targetCombo;
    const opts = [...combo.querySelectorAll(".target-opt:not([hidden])")];
    const at = opts.indexOf(e.target.closest(".target-opt"));
    if (e.key === "Escape" && state.dialog.combo.open) {
      e.stopPropagation();
      closeTargetCombo(name, true);
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      if (!state.dialog.combo.open) return openTargetCombo(name);
      if (opts.length) opts[Math.min(at + 1, opts.length - 1)].focus();
    } else if (e.key === "ArrowUp" && at >= 0) {
      e.preventDefault();
      (at > 0 ? opts[at - 1] : combo.querySelector("[data-target-input]")).focus();
    } else if (e.key === "Enter" && at < 0 && state.dialog.combo.open && opts.length) {
      e.preventDefault();
      pickTarget(name, opts[0].dataset.targetPick);
    }
  }

  function fieldHtml(field) {
    const box = `class="field" data-field-box="${field.name}"`;
    const label = `<span data-label-for="${field.name}">${escapeHtml(lbl(field))}</span>`;
    if (field.source === "transferTargets") {
      return `<div ${box}>${label}<div class="mselect target-combo" data-target-combo="${field.name}"><input type="hidden" data-field="${field.name}" value="" /></div></div>`;
    }
    // Файлы (ТЗ-18, 19): выбранные — списком под кнопкой; содержимое читается в форму, на сервер — с остальными полями
    if (field.kind === "files") {
      return `<div ${box}>${label}<input type="file" multiple data-files="${field.name}" /><ul class="file-list" data-file-list="${field.name}"></ul></div>`;
    }
    if (field.kind === "select") {
      const options = (field.options || [])
        .map((o) => `<option value="${escapeHtml(o.id)}" ${o.disabled ? "disabled" : ""}>${escapeHtml(optionLabel(o))}</option>`)
        .join("");
      // Подсказка списка — пустой вариант, который нельзя выбрать обратно (§2.2)
      const empty = hasLbl(field, "placeholder") ? `<option value="" disabled>${escapeHtml(lbl(field, "placeholder"))}</option>` : "";
      // Под списком — предупреждение выбранного варианта (FieldOption.warning, §2.2): выбрать он не мешает
      return `<label ${box}>${label}<select data-field="${field.name}">${empty}${options}</select><span class="field-warning" data-warning="${field.name}" hidden></span></label>`;
    }
    return `<label ${box}>${label}<textarea rows="3" data-field="${field.name}" placeholder="${escapeHtml(
      lbl(field, "placeholder")
    )}"></textarea></label>`;
  }

  // Подсказка у поля формы (§22.6): text — показать, пусто — снять
  function fieldError(name, text) {
    const box = $("dialogFields").querySelector(`[data-field-box="${name}"]`);
    if (!box) return;
    let hint = box.querySelector(`[data-field-error="${name}"]`);
    if (!hint && text) {
      hint = document.createElement("span");
      hint.className = "field-error";
      hint.dataset.fieldError = name;
      hint.id = `field-error-${name}`;
      box.appendChild(hint);
    }
    if (hint) {
      hint.textContent = text || "";
      hint.hidden = !text;
    }
    box.querySelectorAll(`[data-target-input="${name}"], [data-field="${name}"]:not([type='hidden']), [data-files="${name}"]`).forEach((el) => {
      if (text) {
        el.setAttribute("aria-invalid", "true");
        el.setAttribute("aria-describedby", hint.id);
      } else {
        el.removeAttribute("aria-invalid");
        el.removeAttribute("aria-describedby");
      }
    });
  }

  function dialogValues() {
    const values = {};
    $("dialogFields")
      .querySelectorAll("[data-field]")
      .forEach((el) => (values[el.dataset.field] = el.value.trim()));
    if (state.dialog && state.dialog.files) Object.entries(state.dialog.files).forEach(([name, list]) => (values[name] = list));
    return values;
  }

  // Видимость зависимых полей и звёздочка обязательности — по выбранному значению (§2.2)
  function refreshDialogFields() {
    const open = state.dialog;
    if (!open) return;
    const values = dialogValues();
    // Вариант, зависящий от другого поля (FieldOption.forValues), — только при его выбранном значении; выбранный
    // вариант, которого больше нет, снимается (ТЗ-4: сменили результат — причина очищается)
    open.form.fields.forEach((field) => {
      const dep = field.rules && field.rules.dependsOn;
      const el = $("dialogFields").querySelector(`select[data-field="${field.name}"]`);
      if (!dep || !el) return;
      [...el.options].forEach((o) => {
        const opt = (field.options || []).find((x) => x.id === o.value);
        o.hidden = Boolean(opt && opt.forValues && !opt.forValues.includes(values[dep]));
      });
      if (el.selectedOptions[0] && el.selectedOptions[0].hidden) {
        el.value = "";
        values[field.name] = "";
      }
    });
    open.form.fields.forEach((field) => {
      const visible = fieldVisible(field, values);
      // Поле заполнили — подсказка «Заполните поле» у него уходит (§22.6)
      if (values[field.name] && values[field.name].length !== 0) fieldError(field.name, "");
      const box = $("dialogFields").querySelector(`[data-field-box="${field.name}"]`);
      if (box) box.hidden = !visible;
      const label = $("dialogFields").querySelector(`[data-label-for="${field.name}"]`);
      if (label) label.textContent = lbl(field) + (visible && fieldRequired(field, values) ? " *" : "");
      const warn = $("dialogFields").querySelector(`[data-warning="${field.name}"]`);
      if (warn) {
        const picked = (field.options || []).find((o) => o.id === values[field.name]);
        const w = picked && picked.warning;
        warn.textContent = w ? say(w.key, w.vars) : "";
        warn.hidden = !w;
      }
    });
  }

  function showForm(open, given) {
    const form = Object.assign({}, given, { fields: given.fields.map(reasonsByName) });
    state.dialog = Object.assign(open, { form, combo: { open: false, q: "" } });
    $("dialogTitle").textContent = lbl(form, "title");
    $("dialogNote").textContent = form.note || "";
    $("dialogNote").hidden = !form.note;
    $("dialogFields").innerHTML = form.fields.map(fieldHtml).join("");
    form.fields.forEach((field) => {
      if (field.kind !== "select") return;
      const enabled = (field.options || []).filter((o) => !o.disabled);
      // Список с placeholder заполняется сам, только если выбирать не из чего или значение задала схема
      const fallback = hasLbl(field, "placeholder") ? (enabled.length === 1 ? enabled[0].id : "") : enabled[0] && enabled[0].id;
      const pick = enabled.some((o) => o.id === field.defaultValue) ? field.defaultValue : fallback;
      const el = $("dialogFields").querySelector(`[data-field="${field.name}"]`);
      if (el) el.value = pick || "";
      if (field.source === "transferTargets") renderTargetCombo(field.name);
    });
    refreshDialogFields();
    const confirm = $("dialogConfirm");
    confirm.textContent = lbl(form, "confirmLabel");
    confirm.className = `btn ${form.style || "primary"}`;
    $("modalDialog").hidden = false;
    ($("dialogFields").querySelector("[data-target-input], [data-field]:not([type='hidden'])") || confirm).focus();
  }

  // Форма — из машины (forms), варианты полей, правила полей и пояснение — из ответа сервера (fieldOptions, fieldRules, formNote)
  // Строка очереди не несёт варианты людей (решение 74): нет вариантов у поля с источником — их берут из карточки
  let dialogSeq = 0;
  async function openDialog(id, ev, surface) {
    const seq = ++dialogSeq;
    const tr = transitionDef(id);
    if (!tr || !tr.form || !ev) return;
    let a = actionOf(ev, id);
    if (!a || !a.enabled) {
      toast(actionWhy(a) || t("Действие «{name}» недоступно в текущем состоянии", { name: lbl(tr) }), "error");
      return;
    }
    const def = WORKFLOW.forms.find((f) => f.id === tr.form);
    if (def.fields.some((field) => field.source && !(a.fieldOptions || {})[field.name])) {
      let card;
      try {
        card = await api.get(incPath(ev.guid));
      } catch (err) {
        if (seq === dialogSeq) toast(problemText(err), "error");
        return;
      }
      // Пока шёл ответ, оператор нажал другую строку (побеждает последнее нажатие) или открылась другая форма
      // («Перерыв», «Выход»): эту не показываем
      if (seq !== dialogSeq || state.dialog) return;
      const fresh = actionOf(card, id);
      if (!fresh || !fresh.enabled) {
        toast(actionWhy(fresh) || t("Действие «{name}» недоступно в текущем состоянии", { name: lbl(tr) }), "error");
        return;
      }
      a = fresh;
    }
    // Форма «Закрыть» — закрытие без обработки: «Обработан» в ней не предлагается, им закрывает «Итог»
    const unprocessed = id === "close";
    const fields = def.fields.map((field) => {
      const opts = (a.fieldOptions || {})[field.name];
      const rules = (a.fieldRules || {})[field.name] || null;
      if (!opts) return Object.assign({}, field, { rules });
      if (unprocessed && field.name === "resultId") {
        const options = opts.options.filter((o) => !fullyProcessed(o.id));
        return Object.assign({}, field, { rules, options, defaultValue: options.some((o) => o.id === opts.defaultValue) ? opts.defaultValue : null });
      }
      return Object.assign({}, field, { rules, options: opts.options, defaultValue: opts.defaultValue });
    });
    let note = a.formNote ? say(a.formNote.key, a.formNote.vars) : "";
    // Пояснение в карточке — точнее, чем у машины: останется ли сценарий незавершённым
    if (unprocessed) {
      const prog = stepProgress(ev);
      if (surface === "card" && runDone(ev)) note = t("Сценарий пройден, но инцидент закроется выбранным результатом, а не «Обработан».");
      else if (surface === "card" && prog.total)
        note = t("Сценарий заполнен: {filled} из {total} — останется незавершённым.", { filled: prog.filled, total: prog.total });
    }
    state.selectedId = ev.guid;
    showForm({ id, eventId: ev.guid, ev, surface }, Object.assign({}, def, { fields, note }));
  }

  async function submitDialog() {
    const open = state.dialog;
    if (!open) return;
    const values = dialogValues();
    open.form.fields.forEach((field) => {
      if (!fieldVisible(field, values)) delete values[field.name];
    });
    const missing = open.form.fields.find((f) => fieldVisible(f, values) && fieldRequired(f, values) && !values[f.name]);
    if (missing) {
      // Не всплывает (§22.6): подсказка у самого поля — текст под полем и aria-invalid; правка поля её снимает
      const el = $("dialogFields").querySelector(`[data-target-input="${missing.name}"], [data-field="${missing.name}"]:not([type='hidden'])`);
      fieldError(missing.name, t("Заполните поле «{name}»", { name: lbl(missing) }));
      if (el) el.focus();
      return;
    }
    const bulkIds = open.bulkIds;
    closeDialog();
    if (open.id === "__break__") return goOnBreak(values.reasonId);
    if (open.id === "__signout__") return setPresence("offline", "Вы вышли из МИ");
    if (bulkIds && bulkIds.length > 1) return runBulk(open.id, bulkIds, values, open.surface);
    return runTransition(open.id, open.ev, values, open.surface);
  }

  // Файлы формы — как вложение шага: содержимое в dataBase64; пределы проверяет сервер по машине (limits)
  async function addDialogFiles(input) {
    const open = state.dialog;
    if (!open) return;
    const name = input.dataset.files;
    const read = (f) =>
      new Promise((done) => {
        const r = new FileReader();
        r.onload = () => done(String(r.result).replace(/^data:[^,]*,/, ""));
        r.readAsDataURL(f);
      });
    const added = await Promise.all(
      [...input.files].map(async (f, n) => ({ id: `file-${Date.now()}-${n}`, fileName: f.name, mime: f.type || "application/octet-stream", size: f.size, dataBase64: await read(f) }))
    );
    if (state.dialog !== open) return;
    open.files = Object.assign({}, open.files, { [name]: ((open.files || {})[name] || []).concat(added) });
    input.value = "";
    const list = $("dialogFields").querySelector(`[data-file-list="${name}"]`);
    if (list) list.innerHTML = open.files[name].map((f) => `<li>${escapeHtml(f.fileName)}</li>`).join("");
  }

  function closeDialog() {
    state.dialog = null;
    $("modalDialog").hidden = true;
  }

  // Переход либо спрашивает подробности в форме, либо выполняется сразу.
  // Кнопка на строке и в карточке — один инцидент; выборку передаёт только панель (targets)
  function trigger(id, ev, surface, targets) {
    if (!ev) return;
    if (isNav(id)) return openCard(id, ev);
    const tr = transitionDef(id);
    if (!tr) return;
    if (targets && targets.length >= 2) {
      if (tr.form) return openBulkDialog(id, ev, targets, surface);
      return runBulk(id, targets, {}, surface);
    }
    const a = actionOf(ev, id);
    if (!a || !a.enabled) {
      toast(actionWhy(a) || t("Действие «{name}» недоступно в текущем состоянии", { name: lbl(tr) }), "error");
      return;
    }
    if (tr.form) return openDialog(id, ev, surface);
    return runTransition(id, ev, {}, surface);
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  /* ===== Группы устройств: дерево с счётчиками приходит с сервера (SourceGroupNode) ===== */

  function findNode(nodes, id) {
    for (const node of nodes) {
      if (node.guid === id) return node;
      const found = findNode(node.children || [], id);
      if (found) return found;
    }
    return null;
  }

  // Цепочка групп от корня до той, где стоит устройство-источник события (§19.1, RULE-85).
  // Устройство может встречаться и в сквозных подборках — берём первое вхождение.
  function groupPathForDevices(deviceIds) {
    const wanted = new Set(deviceIds || []);
    const walk = (nodes, trail) => {
      for (const node of nodes) {
        if ((node.devices || []).some((d) => wanted.has(d.guid))) return trail.concat(node.guid);
        const found = walk(node.children || [], trail.concat(node.guid));
        if (found) return found;
      }
      return null;
    };
    return walk(store.tree, []) || [];
  }

  // В дереве — группы и все устройства группы, доступные оператору; у группы и устройства с открытыми
  // инцидентами — одно число, счётчик (§19.1, RULE-86, BUG-64)
  const groupDevices = (node) => node.devices || [];

  // Совпавшая с поиском часть названия — выделена (RULE-88)
  function markMatch(text, q) {
    const at = q ? text.toLowerCase().indexOf(q) : -1;
    if (at < 0) return escapeHtml(text);
    return `${escapeHtml(text.slice(0, at))}<mark>${escapeHtml(text.slice(at, at + q.length))}</mark>${escapeHtml(text.slice(at + q.length))}`;
  }

  function nodeMatchesQuery(node, q, isDevice) {
    if (!q) return true;
    if (t(node.name).toLowerCase().includes(q)) return true;
    if (isDevice) return false;
    return foundInside(node, q);
  }
  const foundInside = (node, q) =>
    (node.children || []).some((c) => nodeMatchesQuery(c, q)) || groupDevices(node).some((d) => nodeMatchesQuery(d, q, true));

  // Дерево с клавиатуры, как дерево WAI-ARIA (§13, RULE-88): ↑ ↓ — по видимым узлам, Home и End — первый
  // и последний, → — раскрыть или к первому вложенному, ← — свернуть или к родителю, Enter и пробел — выбрать
  const treeItems = () => [...$("groupsList").querySelectorAll(".tree-node")].filter((n) => n.getClientRects().length > 0);
  // Узлы, чьё название совпало с поиском, — по порядку дерева
  const treeHits = () => [...$("groupsList").querySelectorAll(".tree-node:not(.hidden) > .node-content mark")].map((m) => m.closest(".tree-node"));
  // ▲ ▼ у поиска, Enter и Shift+Enter в поле — к предыдущему и следующему найденному, по кругу
  function stepTreeHit(dir) {
    const n = treeHits().length;
    if (!n) return;
    state.treeHit = (state.treeHit + dir + n) % n;
    state.treeHitScroll = true;
    renderGroups();
  }
  function focusTreeNode(node) {
    if (!node) return;
    $("groupsList").querySelectorAll('.tree-node[tabindex="0"]').forEach((n) => (n.tabIndex = -1));
    node.tabIndex = 0;
    state.treeFocus = node.dataset.id;
    node.focus();
    node.querySelector(":scope > .node-content").scrollIntoView({ block: "nearest" });
  }
  function treeKey(e) {
    const node = e.target;
    if (!node.classList || !node.classList.contains("tree-node")) return;
    const items = treeItems();
    const at = items.indexOf(node);
    const moves = { ArrowDown: items[at + 1], ArrowUp: at > 0 ? items[at - 1] : null, Home: items[0], End: items[items.length - 1] };
    if (e.key in moves) {
      e.preventDefault();
      // Выше первого узла — в поиск
      return moves[e.key] ? focusTreeNode(moves[e.key]) : $("groupSearch").focus();
    }
    const id = node.dataset.id;
    const open = node.classList.contains("open");
    if (e.key === "ArrowRight" && node.classList.contains("has-children")) {
      e.preventDefault();
      if (open) return focusTreeNode(node.querySelector(":scope > ul > .tree-node:not(.hidden)"));
      state.treeFocus = id;
      state.openGroups.add(id);
      return renderGroups();
    }
    if (e.key === "ArrowLeft") {
      e.preventDefault();
      // Ветку с найденным раскрыл поиск — ← ведёт к родителю; раскрытую оператором — сворачивает
      if (open && !node.classList.contains("search-open")) {
        state.treeFocus = id;
        state.openGroups.delete(id);
        return renderGroups();
      }
      return focusTreeNode(node.parentElement.closest(".tree-node"));
    }
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      state.treeFocus = id;
      node.querySelector(":scope > .node-content").click();
    }
  }

  // Списки фильтров: по состоянию — из машины, типы событий и устройств — справочники сервера
  function renderTypeFilters() {
    renderQueueHead();
    renderTypeLists();
    renderQueueSort();
  }

  // Поле списка — редактируемое: щелчок открывает, набранный текст отбирает варианты (без запроса к серверу).
  // Пока ничего не набрано, в поле видно выбранное: первое значение подсказкой и «+N» отдельно — многоточие не съедает счёт
  function comboField(attr, id, open, q, picked, label, anyLabel) {
    const all = picked.map(label).join(", ") || anyLabel;
    return `<input type="text" class="mselect-input ${picked.length ? "has-value" : ""} ${picked.length > 1 ? "has-more" : ""}" ${attr}="${escapeHtml(id)}"
      role="combobox" aria-expanded="${open}" autocomplete="off" spellcheck="false" value="${open ? escapeHtml(q || "") : ""}"
      placeholder="${escapeHtml(picked.length ? label(picked[0]) : anyLabel)}" title="${escapeHtml(all)}" aria-label="${escapeHtml(all)}" />${
      picked.length > 1 ? `<span class="mselect-more">+${picked.length - 1}</span>` : ""
    }`;
  }
  const comboHit = (text, q) => !q || text.toLowerCase().includes(q.toLowerCase());
  // Набор в поле: прячет неподходящие варианты раскрытого списка, не перерисовывая его
  function comboNarrow(input) {
    const menu = input.parentElement.querySelector(".mselect-menu");
    if (!menu) return;
    menu.querySelectorAll(".mselect-opt").forEach((o) => (o.hidden = !comboHit(o.querySelector("span").textContent, input.value)));
    const none = menu.querySelector("[data-combo-none]");
    if (none) none.hidden = Boolean(menu.querySelector(".mselect-opt:not([hidden])"));
  }
  // Клавиши поля — как у обычного списка: Enter — первый подходящий вариант, ↓ — к вариантам
  function comboKey(e, close) {
    const input = e.target.closest(".mselect-input");
    if (!input) return;
    const first = input.parentElement.querySelector(".mselect-opt:not([hidden]) input:not(:disabled)");
    if (e.key === "Escape") {
      e.stopPropagation();
      close();
    } else if (e.key === "Enter" && first) {
      e.preventDefault();
      first.click();
    } else if (e.key === "ArrowDown" && first) {
      e.preventDefault();
      first.focus();
    }
  }
  function comboFocus(input) {
    if (!input) return;
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
  }
  const comboNone = (shown) => `<div class="muted mselect-empty" data-combo-none ${shown ? "hidden" : ""}>${te("Нет вариантов")}</div>`;

  // Типы устройств и событий над очередью — выпадающие списки с галочками, как в окне фильтра
  function typeList(elId, key, options, anyLabel) {
    const picked = state[key];
    const label = (v) => {
      const o = options.find((x) => x.id === v);
      return o ? t(o.label) : v;
    };
    const open = state.tbOpen === key;
    const q = state.tbQ[key] || "";
    const el = $(elId);
    el.classList.toggle("open", open);
    const opts = options.map(
      (o) =>
        `<label class="mselect-opt" ${comboHit(t(o.label), q) ? "" : "hidden"}><input type="checkbox" data-tb="${key}" value="${escapeHtml(o.id)}" ${
          picked.includes(o.id) ? "checked" : ""
        } /><span>${te(o.label)}</span><em></em></label>`
    );
    el.innerHTML =
      comboField("data-tb-toggle", key, open, q, picked, label, t(anyLabel)) +
      (open
        ? `<div class="mselect-menu">${opts.join("")}${comboNone(options.some((o) => comboHit(t(o.label), q)))}${
            picked.length ? `<button type="button" class="btn ghost small" data-tb-clear="${key}">${te(anyLabel)}</button>` : ""
          }</div>`
        : "");
  }
  function renderTypeLists() {
    typeList("deviceTypeFilter", "deviceTypes", store.deviceTypes.map((d) => ({ id: d.id, label: d.label })), "Все типы устройств");
    typeList("eventTypeFilter", "eventTypes", store.eventTypes.map((e) => ({ id: e.guid, label: e.name })), "Все типы событий");
    typeList("scenarioFilter", "scenarios", store.scenarios.map((s) => ({ id: s.guid, label: s.name })), "Все сценарии");
    if (state.tbOpen) comboFocus(document.querySelector(`[data-tb-toggle="${state.tbOpen}"]`));
    renderMoreFilters();
  }
  // Телефон (BUG-50): типы и порядок — под кнопкой «Фильтры»; число на ней — сколько типов выбрано,
  // чтобы скрытый фильтр не забылся. На широком экране кнопки нет, всё видно сразу
  function renderMoreFilters() {
    const n = state.deviceTypes.length + state.eventTypes.length + state.scenarios.length;
    $("eventsMoreN").hidden = !n;
    $("eventsMoreN").textContent = String(n);
    $("eventsToolbar").classList.toggle("more-open", state.moreFilters);
    const btn = $("eventsMoreBtn");
    btn.setAttribute("aria-expanded", String(state.moreFilters));
    btn.setAttribute("aria-label", n ? t("Фильтры: выбрано {n}", { n }) : t("Фильтры"));
  }

  // Порядок очереди (§7, BUG-34): список — только если администратор разрешил оператору выбирать;
  // выбор — в настройках оператора, сортирует сервер. Подписи — те же, что в настройках администратора
  function renderQueueSort() {
    const s = WORKFLOW.queueSort;
    const select = $("queueSortSelect");
    select.hidden = !s.operatorMayChange;
    if (select.hidden) return;
    const item = WORKFLOW.adminSettings.tabs.flatMap((tab) => tab.items || []).find((i) => i.path === "queueSort.default");
    select.innerHTML = s.options.map((id) => `<option value="${escapeHtml(id)}">${te(item.values[id])}</option>`).join("");
    select.value = s.options.includes(prefs().queueSort) ? prefs().queueSort : s.default;
    select.title = lbl(item);
    select.setAttribute("aria-label", lbl(item));
  }

  // all — узел внутри найденной группы, которую оператор раскрыл: поиск его не скрывает
  // Окна работ, действующие на узел дерева (ТЗ-21): окно на устройство — у устройства; окно на группу — у группы,
  // всех её подгрупп и устройств. Родителям группы окна значка нет: работы идут не во всей их зоне
  function maintByNode() {
    const out = new Map();
    const add = (id, w) => out.set(id, (out.get(id) || []).concat(w));
    const mark = (node, w) => {
      add(node.guid, w);
      (node.children || []).forEach((c) => mark(c, w));
      groupDevices(node).forEach((d) => add(d.guid, w));
    };
    const find = (nodes, id) => {
      for (const n of nodes) {
        if (n.guid === id) return n;
        const f = find(n.children || [], id);
        if (f) return f;
      }
      return null;
    };
    store.maint.windows.forEach((w) => {
      if (w.deviceGuid) return add(w.deviceGuid, w);
      const node = find(store.tree, w.sourceGroupGuid);
      if (node) mark(node, w);
    });
    return out;
  }
  let maintNodes = new Map();
  function maintBadge(id) {
    const ws = maintNodes.get(id);
    if (!ws) return "";
    const tip = ws.map((w) => t("Плановые работы: «{what}», до {until}", { what: w.description || w.objectName, until: fmtUntil(w.endsAt) })).join("\n");
    return `<span class="tree-maint material-symbols-outlined" title="${escapeHtml(tip)}" aria-label="${escapeHtml(tip)}">construction</span>`;
  }

  function treeItemHtml(item, isDevice, level, trace, q, all) {
    const kids = isDevice ? [] : (item.children || []).concat(groupDevices(item));
    const hasKids = kids.length > 0;
    const icon = isDevice ? DEVICE_ICON[item.typeId] || "videocam" : "folder";
    const counters = item.counters || { open: 0, critical: 0 };
    const hidden = q && !all && !nodeMatchesQuery(item, q, isDevice);
    // Поиск раскрывает путь к найденному. Группа, найденная только по своему названию, — свёрнута, как обычно;
    // раскрыл её оператор — внутри всё, а не пусто (BUG-67)
    const forceOpen = Boolean(q && !all && hasKids && foundInside(item, q));
    const open = forceOpen || state.openGroups.has(item.guid);
    const reveal = Boolean(all || (q && !forceOpen && open));
    const title = t(item.description || item.name);
    const traced = trace.ids.has(item.guid) ? (item.guid === trace.leaf ? "trace trace-leaf" : "trace") : "";
    const crit = counters.topPriority > 0;
    // Без открытых инцидентов — приглушён: путь к тревоге виден сразу, порядок группы не меняется (§19.1, RULE-92)
    const quiet = counters.open ? "" : "quiet";
    return `
          <li class="tree-node ${quiet} ${hasKids ? "has-children" : ""} ${open ? "open" : ""} ${forceOpen ? "search-open" : ""} ${
            state.groupId === item.guid ? "active" : ""
          } ${traced} ${isDevice ? "is-device" : ""} ${hidden ? "hidden" : ""} level-${level}"
              data-id="${escapeHtml(item.guid)}" data-type="${isDevice ? "device" : "group"}" role="treeitem" tabindex="-1"
              aria-level="${level + 1}" aria-selected="${state.groupId === item.guid}"${hasKids ? ` aria-expanded="${open}"` : ""}>
            <div class="node-content" title="${escapeHtml(title)}">
              <span class="toggle-icon material-symbols-outlined">chevron_right</span>
              <span class="material-symbols-outlined">${icon}</span>
              <span class="node-text">${markMatch(t(item.name), q)}</span>
              ${maintBadge(item.guid)}
              ${isDevice ? "" : filterButtons(item.guid)}
              ${
                counters.open
                  ? `<span class="tree-ev ${crit ? "crit" : ""}" title="${te("Открытых инцидентов{crit}", {
                      crit: crit ? t(", есть «{name}»", { name: inLang(store.priorities[0].name) }) : "",
                    })}">${counters.open}</span>`
                  : ""
              }
            </div>
            ${hasKids ? `<ul role="group">${renderTreeHtml(item, level + 1, trace, reveal)}</ul>` : ""}
          </li>`;
  }

  function renderTreeHtml(parent, level, trace, all) {
    const q = state.groupQuery.trim().toLowerCase();
    const groups = parent ? parent.children || [] : store.tree;
    const devices = parent ? groupDevices(parent) : [];
    return groups
      .map((g) => treeItemHtml(g, false, level, trace, q, all))
      .concat(devices.map((d) => treeItemHtml(d, true, level, trace, q, all)))
      .join("");
  }

  let tracedEventId = null;

  // Группа выбранного события подсвечивается вместе с родителями и
  // раскрывается — но только при смене события, чтобы не мешать сворачиванию
  function traceGroups() {
    const ev = selected();
    const devices = ev && ev.source ? [ev.source.guid] : [];
    const path = groupPathForDevices(devices);
    const changed = (ev ? ev.guid : null) !== tracedEventId && Boolean(ev && ev.source);
    if (changed) {
      tracedEventId = ev.guid;
      path.forEach((id) => state.openGroups.add(id));
    }
    return { ids: new Set(path), leaf: path[path.length - 1] || null, changed };
  }

  function renderGroups() {
    const hadFocus = $("groupsList").contains(document.activeElement);
    const trace = traceGroups();
    const collapseBtn = $("groupsCollapseAll");
    const expanded = state.openGroups.size > 0;
    collapseBtn.querySelector(".material-symbols-outlined").textContent = expanded ? "unfold_less" : "unfold_more";
    collapseBtn.title = t(expanded ? "Свернуть все группы" : "Развернуть все группы");

    const open = store.counters.open || 0;
    const crit = store.tree.some((n) => n.counters && n.counters.topPriority > 0);
    maintNodes = maintByNode();
    $("groupsList").innerHTML = `
      <li class="tree-node tree-all ${state.groupId === "all" ? "active" : ""}" data-id="all" data-type="group" role="treeitem" tabindex="-1"
          aria-level="1" aria-selected="${state.groupId === "all"}">
        <div class="node-content">
          <span class="toggle-icon material-symbols-outlined"></span>
          <span class="material-symbols-outlined">folder_open</span>
          <span class="node-text">${te("Все устройства")}</span>
          ${filterButtons("all")}
          <span class="tree-ev ${crit ? "crit" : ""}">${open}</span>
        </div>
      </li>
      ${renderTreeHtml(null, 0, trace)}
    `;
    const q = state.groupQuery.trim();
    // На экране — узел, который поиск не скрыл, а все его предки не скрыты и раскрыты: дети раскрытой группы
    // класса hidden не получают, но без найденного предка их не видно (BUG-92)
    const onScreen = (n) => {
      for (let x = n; x; x = x.parentElement.closest(".tree-node")) {
        if (x.classList.contains("hidden") || (x !== n && !x.classList.contains("open"))) return false;
      }
      return true;
    };
    const visible = [...$("groupsList").querySelectorAll(".tree-node")].filter((n) => n.dataset.id !== "all" && onScreen(n));
    $("groupsEmpty").hidden = !q || visible.length > 0;
    // Найденное и текущее из него: ▲ ▼ и Enter в поиске прыгают только по совпадениям (RULE-88)
    const hits = treeHits();
    $("groupsFound").hidden = !q || !hits.length;
    $("groupsFoundText").textContent = t("Найдено: {n}", { n: hits.length });
    state.treeHit = hits.length ? Math.min(state.treeHit, hits.length - 1) : 0;
    const hit = hits[state.treeHit];
    $("groupsHitPos").textContent = hits.length ? `${state.treeHit + 1} / ${hits.length}` : "";
    if (hit) {
      hit.classList.add("hit-current");
      if (state.treeHitScroll) hit.querySelector(":scope > .node-content").scrollIntoView({ block: "nearest" });
    }
    state.treeHitScroll = false;
    // Один узел дерева — в порядке Tab: тот, где был фокус, иначе выбранный, иначе первый (RULE-88)
    const items = treeItems();
    const byId = (id) => items.find((n) => n.dataset.id === id);
    const current = byId(state.treeFocus) || byId(state.groupId) || items[0];
    if (current) current.tabIndex = 0;
    if (current && hadFocus) current.focus();
    if (trace.changed) {
      const leaf = $("groupsList").querySelector(".trace-leaf > .node-content");
      if (leaf) leaf.scrollIntoView({ block: "nearest" });
    }
  }

  function pageSequence(current, total) {
    const set = new Set([1, total, current, current - 1, current + 1]);
    if (current <= 3) [2, 3, 4].forEach((n) => set.add(n));
    if (current >= total - 2) [total - 1, total - 2, total - 3].forEach((n) => set.add(n));
    const nums = [...set].filter((n) => n >= 1 && n <= total).sort((a, b) => a - b);
    const out = [];
    nums.forEach((n, i) => {
      if (i && n - nums[i - 1] > 1) out.push("gap");
      out.push(n);
    });
    return out;
  }

  function renderPager(total, pages, start, shown) {
    const pager = $("eventsPager");
    if (total <= PAGE_SIZE) {
      pager.hidden = true;
      pager.innerHTML = "";
      return;
    }
    const step = (page, icon, label, disabled) => `
      <button type="button" class="pager-btn" data-page="${page}" title="${label}" aria-label="${label}" ${
        disabled ? "disabled" : ""
      }>
        <span class="material-symbols-outlined">${icon}</span>
      </button>`;
    pager.hidden = false;
    pager.innerHTML = `
      <span class="pager-info">${te("{a}–{b} из {n}", { a: start + 1, b: start + shown, n: total })}</span>
      <div class="pager-nav">
        ${step(state.page - 1, "chevron_left", t("Предыдущая страница"), state.page === 1)}
        ${pageSequence(state.page, pages)
          .map((p) =>
            p === "gap"
              ? `<span class="pager-gap" aria-hidden="true">…</span>`
              : `<button type="button" class="pager-btn ${p === state.page ? "current" : ""}" data-page="${p}" ${
                  p === state.page ? 'aria-current="page"' : ""
                } aria-label="${te("Страница {p}", { p })}">${p}</button>`
          )
          .join("")}
        ${step(state.page + 1, "chevron_right", t("Следующая страница"), state.page === pages)}
      </div>
    `;
  }

  // Обратный отсчёт: подпись зависит от того, какой норматив идёт (§4)

  // «Скоро нарушение» — меньше display.lateSec машины до дедлайна (ARCH-08 в9)
  const lateMs = () => ((WORKFLOW.display || {}).lateSec || 0) * 1000;
  // Обратный отсчёт: подпись зависит от того, какой норматив идёт (§4)
  function timerChip(ev, extra) {
    const view = timerView(ev.timer);
    if (!view) {
      return ev.slaBreached ? `<span class="event-sla late breached">${te("Норматив нарушен")}</span>` : "";
    }
    const late = view.running && view.leftMs < lateMs();
    const cls = [extra || "event-sla", late ? "late" : "", view.running ? "" : "held", ev.slaBreached ? "breached" : ""]
      .filter(Boolean)
      .join(" ");
    const hint = view.running
      ? t(view.kind === "reaction" ? "Время до нарушения норматива реакции" : "Время до нарушения норматива закрытия")
      : t("Норматив закрытия приостановлен на время удержания");
    return `<span class="${cls}" data-timer="${escapeHtml(ev.guid)}" ${view.running ? `data-due="${view.due}"` : ""} title="${escapeHtml(hint)}">${te(
      view.label
    )} <b class="sla-t">${fmtSla(view.leftMs)}</b>${view.running ? "" : ' <span class="material-symbols-outlined">pause</span>'}</span>`;
  }

  // Предельный срок удержания по причине (таймер hold машины, §4): сколько ещё можно держать
  function holdChip(ev, extra) {
    const view = timerView(ev.holdTimer);
    if (!view) return "";
    const cls = [extra || "event-sla", view.leftMs < lateMs() ? "late" : ""].filter(Boolean).join(" ");
    const hint = t("Время до предельного срока удержания по причине");
    return `<span class="${cls}" data-hold-timer="${escapeHtml(ev.guid)}" data-due="${view.due}" title="${escapeHtml(hint)}">${te(
      "Удержание"
    )} <b class="sla-t">${fmtSla(view.leftMs)}</b></span>`;
  }

  // Чекбокс на любом событии очереди; смешанные типы можно набирать вручную (§11)
  // Лимит выборки null — без ограничения (§11, RULE-69)
  const bulkEligible = (ev) => state.checked.has(ev.guid) || LIMITS.maxBulk == null || state.checked.size < LIMITS.maxBulk;

  // ===== Шапка очереди и блок «Мне на принятие» (§7, план 87в): правило — в машине, здесь только вид =====

  // Раскладка шапки по ширине окна (§7): full — всё подписано; more — редкие состояния в «Ещё ▾»;
  // compact — состояние списком, приоритеты буквами; phone — приоритеты прокручиваемой строкой
  function headLayout(width) {
    return width >= 1560 ? "full" : width >= 1280 ? "more" : width >= 1024 ? "compact" : "phone";
  }
  // Первые три состояния машины (открытые, на принятие, мои) видны всегда, остальные уходят в «Ещё ▾»
  const STATES_ALWAYS = 3;

  // Буквы приоритета на узком окне: первая буква, а если у двух уровней первые совпали — столько, чтобы различить
  function priorityLetters(names) {
    const low = names.map((n) => n.toLowerCase());
    return names.map((name, i) => {
      for (let k = 1; k < name.length; k++) {
        if (low.every((o, j) => j === i || o.slice(0, k) !== low[i].slice(0, k))) return name.slice(0, k);
      }
      return name;
    });
  }

  function renderQueueHead() {
    const layout = headLayout(window.innerWidth);
    const head = $("queueHead");
    head.dataset.layout = layout;
    $("eventsToolbar").classList.toggle("narrow", layout === "compact" || layout === "phone");
    const cfg = inboxCfg();
    const counted = (f) => f.counted !== false && store.stateCounts[f.id] != null;
    // На кнопках — только число; к скрытому звучащему ведёт звенящий значок звука (§22.3)
    const num = (f) => (counted(f) ? `<b class="n">${store.stateCounts[f.id]}</b>` : "");
    const btn = (f) => {
      const hot = cfg && f.id === cfg.filter && counted(f) && store.stateCounts[f.id] > 0;
      return `<button type="button" class="state-btn ${hot ? "hot" : ""}" data-state="${escapeHtml(f.id)}" aria-pressed="${state.filter === f.id}">${escapeHtml(lbl(f))}${num(f)}</button>`;
    };
    const fs = WORKFLOW.queueFilters;
    let html;
    if (layout === "full") html = fs.map(btn).join("");
    else if (layout === "more") {
      const rest = fs.slice(STATES_ALWAYS);
      const on = rest.some((f) => f.id === state.filter);
      html =
        fs.slice(0, STATES_ALWAYS).map(btn).join("") +
        `<span class="state-more"><button type="button" class="state-btn ${on ? "on" : ""}" data-state-more aria-haspopup="menu" aria-expanded="${state.stateMenu}" aria-pressed="${on}">${te("Ещё")}<span class="material-symbols-outlined" aria-hidden="true">expand_more</span></button>${
          state.stateMenu ? `<div class="state-menu" role="menu">${rest.map(btn).join("")}</div>` : ""
        }</span>`;
    } else {
      // Список «Открытые 14 ▾» — рядом; «Мне на принятие» с числом — отдельной кнопкой: видна всегда
      html = cfg ? btn(fs.find((f) => f.id === cfg.filter)) : "";
    }
    $("stateButtons").innerHTML = html;
    // Список состояний: на широком окне скрыт, но хранит выбор
    const select = $("eventFilter");
    if (select.options.length !== fs.length) select.innerHTML = fs.map((f) => `<option value="${escapeHtml(f.id)}"></option>`).join("");
    fs.forEach((f, i) => (select.options[i].textContent = (counted(f) ? `${lbl(f)} ${store.stateCounts[f.id]}` : lbl(f))));
    select.value = state.filter;

    // Приоритеты: уровни справочника, цвета и названия оттуда; выбранный — рамка своего цвета и галочка
    const names = store.priorities.map((p) => inLang(p.name));
    const label = layout === "compact" || layout === "phone" ? priorityLetters(names) : names;
    $("priorityButtons").innerHTML = store.priorities
      .map((p, i) => {
        const on = state.priorities.includes(p.value);
        const n = store.priCounts ? store.priCounts[String(p.value)] || 0 : null;
        const aria = n == null ? names[i] : t("{name}: {n}", { name: names[i], n });
        return `<button type="button" class="pri-btn ${n === 0 && !on ? "zero" : ""}" data-pri="${p.value}" data-color="${escapeHtml(p.color)}" aria-pressed="${on}" title="${escapeHtml(inLang(p.description) || names[i])}" aria-label="${escapeHtml(aria)}"><span class="pri-tick material-symbols-outlined" aria-hidden="true">check</span>${escapeHtml(label[i])}${n == null ? "" : `<b class="n">${n}</b>`}</button>`;
      })
      .join("");
  }
  window.matchMedia("(min-width: 1024px)").addEventListener("change", () => renderQueueHead());
  window.matchMedia("(min-width: 1280px)").addEventListener("change", () => renderQueueHead());
  window.matchMedia("(min-width: 1560px)").addEventListener("change", () => renderQueueHead());

  // Сбросить фильтры (§7): «Открытые», приоритеты, типы, сценарий и поиск; узел дерева не меняется
  function resetFilters() {
    Object.assign(state, { filter: "open", priorities: [], eventTypes: [], scenarios: [], deviceTypes: [], search: "", tbOpen: null, tbQ: {} });
    $("eventSearch").value = "";
    renderTypeLists();
    return requery();
  }
  // Что-то, кроме узла дерева, сужает список: тогда пустой список — «По фильтрам ничего нет»
  const filtersOn = () =>
    state.filter !== "open" || Boolean(state.priorities.length || state.eventTypes.length || state.scenarios.length || state.deviceTypes.length || state.search);

  // Уровень эскалации (§8.3): название из машины по escalationLevel — текст организации (в демо его переводит словарь
  // данных); нет названия или уровня — «Уровень N»
  function levelName(n) {
    const lvl = (WORKFLOW.escalation.levels || []).find((l) => l.level === n);
    const name = lvl && typeof lvl.name === "string" ? lvl.name.trim() : "";
    return name ? t(name) : t("workflow.escalation.level.unnamed", { n });
  }
  // Метка «Эскалация: <название>» полностью; подсказка — шаг из потолка и, со второго шага, на каком шаге не взяли.
  // Уровень 0 — метки нет
  function levelChip(e) {
    const n = e && e.escalationLevel;
    if (!n) return "";
    const below = (WORKFLOW.escalation.levels || []).filter((l) => l.level < n).sort((a, b) => b.level - a.level)[0];
    let tip = t("Автоэскалация, шаг {n} из {max}", { n, max: WORKFLOW.escalation.maxLevel });
    if (n > 1) tip += ` ${t("— не взят вовремя на шаге «{name}»", { name: levelName(below ? below.level : n - 1) })}`;
    return `<span class="chip lvl" data-level="${n}" title="${escapeHtml(tip)}">${te("Эскалация: {name}", { name: levelName(n) })}</span>`;
  }
  // Звучащая строка (§22.3): маленький пульсирующий значок динамика слева от названия; что звучит — в подсказке
  function rowSoundTip(s) {
    return t("Звучит — {what}", { what: s.kind === "personal" ? t("лично вам") : priorityName(s.priority) });
  }
  function rowSound(e) {
    const s = soundingOf(e.guid);
    return s ? `<span class="row-sound" data-row-sound title="${escapeHtml(rowSoundTip(s))}" aria-label="${escapeHtml(rowSoundTip(s))}" role="img">🔊</span>` : "";
  }

  // Блок «Мне на принятие»: всё, что ждёт моего «Принять». Что в нём, сколько строк, в каком порядке — display.inboxBlock
  function inboxRowHtml(e) {
    const pri = PRIORITIES[e.priority];
    // Бледная строка: меток и таймера нет — они уже неправда (BUG-121)
    const view = e.gone ? null : timerView(e.timer);
    const acts = queueActions(e).filter((a) => a.id === "accept" || a.id === "reject");
    const left = view && view.running ? `<span class="inbox-left ${view.leftMs < 60000 ? "urgent" : ""}" data-due="${view.due}">${te("осталось")} <b class="sla-t">${fmtSla(view.leftMs)}</b></span>` : "";
    return `
    <article class="inbox-row ${state.selectedId === e.guid ? "selected" : ""} ${e.gone ? "gone" : ""} ${freshCls(e.guid)}" data-id="${escapeHtml(e.guid)}">
      <div class="inbox-pri" data-color="${escapeHtml(pri.color)}" aria-hidden="true"></div>
      <div class="inbox-main">
        <div class="inbox-top">
          ${e.gone ? goneWhyHtml(e) : `<span class="badge ${escapeHtml(e.badge.style)}">${escapeHtml(badgeView(e).text)}</span>
          ${levelChip(e)}
          ${rowSound(e)}`}<strong>${te(e.eventType.name)}</strong>
          <span class="inbox-num">${escapeHtml(e.number)}</span>
        </div>
        ${sourceLine(e)}
        <div class="inbox-meta"><span class="pri-name" data-color="${escapeHtml(pri.color)}">${escapeHtml(inLang(pri.name))}</span>${left}</div>
      </div>
      <div class="inbox-acts">${acts
        .map((a) => `<button type="button" class="btn ${a.style} event-act" data-do="${a.id}" data-ev="${escapeHtml(e.guid)}" title="${escapeHtml(a.hint)}" ${a.disabled ? 'aria-disabled="true"' : ""}>${escapeHtml(a.label)}</button>`)
        .join("")}</div>
    </article>`;
  }
  function renderInboxBlock(rows, more) {
    if (!blockShown()) return "";
    const cfg = inboxCfg();
    const name = lbl(WORKFLOW.queueFilters.find((f) => f.id === cfg.filter));
    if (!rows.length) return `<section class="inbox-block empty" aria-label="${escapeHtml(name)}">${te("{name}: ничего нет", { name })}</section>`;
    return `<section class="inbox-block" aria-label="${escapeHtml(name)}">${rows.map(inboxRowHtml).join("")}${
      more != null ? `<button type="button" class="inbox-more" data-inbox-all>${te("ещё {n} → показать все в «{name}»", { n: more, name })}</button>` : ""
    }</section>`;
  }

  // Курсор над очередью (§22.1): над строкой списка — выше неё ничего не двигается; над блоком — блок целиком;
  // в промежутке без строки — весь список (так ничто под курсором точно не сдвинется)
  // list — курсор уже был над строкой списка: тогда список держится и над блоком, по пути к «↑ N новых выше» (BUG-122)
  const hover = { over: false, guid: null, inBlock: false, list: false };
  // Что на экране: ключ выборки, строки списка и блока, была ли «ещё N» — с этим сравнивается новый ответ
  const view = { key: null, rows: null, block: null, more: false, guids: new Set() };
  const viewKey = () => JSON.stringify(Object.assign({}, queueQuery(), { focusGuid: null }));
  // Заморозить всё показанное: обновить на месте, новое — придержать
  function freezeAll(shown, next) {
    const r = shown.length ? freezeAbove(shown, next, shown[shown.length - 1].guid) : { rows: next, newAbove: [] };
    return { rows: r.rows.slice(0, shown.length), held: r.newAbove.length + r.rows.length - shown.length };
  }
  function queueView(key) {
    const live = { rows: store.page.items, block: store.block.items, more: store.block.total > store.block.items.length ? store.block.total - store.block.items.length : null, held: 0 };
    if (!hover.over || !view.rows || view.key !== key) return live;
    const blk = freezeAll(view.block, store.block.items);
    const visible = blk.rows.filter((r) => !r.gone).length;
    const out = { block: blk.rows, more: view.more ? Math.max(0, store.block.total - visible) : null, held: blk.held };
    if (hover.inBlock && !hover.list) return Object.assign(out, { rows: store.page.items });
    const anchor = view.rows.some((r) => r.guid === hover.guid) ? hover.guid : view.rows.length ? view.rows[view.rows.length - 1].guid : null;
    const list = freezeAbove(view.rows, store.page.items, anchor);
    return Object.assign(out, { rows: list.rows, held: out.held + list.newAbove.length });
  }
  // Ушедшая строка — бледная и без кнопок, пока курсор не ушёл (решение 7); вместо кнопок — почему ушла (BUG-121)
  const goneRow = (inBlock) => (e) => (e.gone ? Object.assign({}, e, { actions: [], goneWhy: goneWhy(e, inBlock) }) : e);
  // Последний переход инцидента, о котором знает клиент: событие потока или ответ на своё действие — кто и моё ли.
  // По нему и последней строке инцидента бледная строка говорит, почему ушла (§22.1, BUG-121)
  const lastMove = new Map();
  function noteMove(guid, actor, mine) {
    lastMove.delete(guid);
    lastMove.set(guid, { actor, mine });
    if (lastMove.size > 1000) lastMove.delete(lastMove.keys().next().value);
  }
  // Ответ на своё действие: строка и «моё». Поток уже сказал о более новой версии (чужой перехват раньше ответа) —
  // опоздавший ответ её не затирает. Поток и чтения очереди пишут всегда: они идут по порядку
  function noteOwn(items) {
    const n = (v) => (v == null || v === "" ? NaN : Number(v));
    (items || []).forEach((e) => {
      if (!e || !e.guid) return;
      const known = incCache.get(e.guid);
      if (known && n(e.version) < n(known.version)) return;
      noteIncidents([e]);
      noteMove(e.guid, null, true);
    });
  }
  // Почему строка ушла — по данным, а не по именам переходов (правил клиент не держит): e — строка, как она на экране,
  // inc — последняя известная. Закрыт (вами, кем, автоматически), объединён, новый владелец — принят, новый адресат
  // не я — передан; строка блока — ушла из блока (блок фильтрами не сужается, §7); не проходит фильтр — скрыт
  // фильтром; не знаем — «Ушёл из списка»
  function goneWhy(e, inBlock) {
    const inc = incCache.get(e.guid) || e;
    const mv = lastMove.get(e.guid) || {};
    const me = store.session && store.session.operator.guid;
    const idOf = (ref) => (ref && ref.id) || null;
    if (isDone(inc)) return mv.mine ? t("Закрыт вами") : mv.actor ? t("Закрыт — {who}", { who: actorName(mv.actor) }) : t("Закрыт");
    if (inc.linkedTo) {
      const main = incCache.get(inc.linkedTo);
      return main ? t("Объединён с {id}", { id: main.number }) : t("Объединён с другим инцидентом");
    }
    const owner = idOf(inc.owner);
    if (owner && owner !== idOf(e.owner)) return owner === me ? t("Принят вами") : t("Принят — {who}", { who: actorName(inc.owner) });
    const addressee = idOf(inc.addressee);
    if (addressee && addressee !== idOf(e.addressee) && addressee !== me) return t("Передан — {who}", { who: actorName(inc.addressee) });
    if (inBlock) return t("Ушёл из блока");
    if (hiddenBy(inc, filterChoice()).length) return t("Скрыт фильтром");
    return t("Ушёл из списка");
  }
  const goneWhyHtml = (e) => `<span class="gone-why" data-gone-why>${escapeHtml(e.goneWhy)}</span>`;

  // Подсветка новой строки (§22.3): display.freshRowSec с того момента, как строка показалась в видимой части списка.
  // Новая — пришла после загрузки событием потока (не моим действием, не сменой фильтра или страницы).
  // fresh: guid → когда снять подсветку (0 — ещё не показалась)
  const arrived = new Set();
  const fresh = new Map();
  const freshMs = () => ((WORKFLOW.display && WORKFLOW.display.freshRowSec) || 0) * 1000;
  let freshSeen = null;
  function litFresh(el) {
    const guid = el.dataset.id;
    if (fresh.get(guid) !== 0) return;
    fresh.set(guid, Date.now() + freshMs());
    el.classList.add("fresh");
    setTimeout(() => {
      fresh.delete(guid);
      const row = $("eventsList").querySelector(`[data-id="${CSS.escape(guid)}"]`);
      if (row) row.classList.remove("fresh");
    }, freshMs());
  }
  // Ждущие строки в видимой части списка — подсветить сейчас. Зовётся после отрисовки и на прокрутке списка;
  // IntersectionObserver — ещё и на смену размеров панелей
  function checkFresh() {
    const list = $("eventsList");
    const waiting = [...list.querySelectorAll("[data-id]")].filter((el) => fresh.get(el.dataset.id) === 0);
    if (!waiting.length) return [];
    // Видимая часть — окно, урезанное всеми прокручиваемыми предками строки (на узком окне прокручивается не список)
    let top = 0;
    let bottom = window.innerHeight;
    for (let p = list; p && p !== document.documentElement; p = p.parentElement) {
      if (getComputedStyle(p).overflowY === "visible") continue;
      const r = p.getBoundingClientRect();
      top = Math.max(top, r.top);
      bottom = Math.min(bottom, r.bottom);
    }
    const inView = (el) => {
      const r = el.getBoundingClientRect();
      return r.height > 0 && r.bottom > top && r.top < bottom;
    };
    waiting.filter(inView).forEach(litFresh);
    return waiting.filter((el) => fresh.get(el.dataset.id) === 0);
  }
  function watchFresh() {
    const waiting = checkFresh();
    if (!("IntersectionObserver" in window)) return;
    if (!freshSeen)
      freshSeen = new IntersectionObserver(
        (entries) =>
          entries.forEach((en) => {
            if (!en.isIntersecting) return;
            freshSeen.unobserve(en.target);
            litFresh(en.target);
          }),
        { root: null }
      );
    freshSeen.disconnect();
    waiting.forEach((el) => freshSeen.observe(el));
  }
  const freshCls = (guid) => (fresh.get(guid) > Date.now() ? "fresh" : "");

  function renderEvents() {
    // Панель выборки зависит от отметок — перерисовывается вместе с очередью
    renderSelectionBar();
    const { items, total } = store.page;
    $("eventsCount").textContent = String(total);
    // «Снять» — только когда что-то отмечено (§7)
    $("clearSelectionBtn").disabled = state.checked.size === 0;
    $("clearSelectionBtn").hidden = state.checked.size === 0;
    $("selectAllBtn").disabled = !items.some((e) => !isDone(e));
    const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    const start = (state.page - 1) * PAGE_SIZE;
    renderPager(total, pages, start, items.length);
    const none = filtersOn()
      ? `<div class="empty">${te("По фильтрам ничего нет")} · <button type="button" class="btn ghost small" data-reset-filters>${te("Сбросить фильтры")}</button></div>`
      : `<div class="empty">${te("Ничего нет")}</div>`;
    const key = viewKey();
    const v = queueView(key);
    // Строки, которых на экране этой же выборки не было и которые принёс поток, — новые: подсветить, как покажутся
    const shown = v.rows.concat(v.block);
    if (view.key === key && freshMs())
      shown.forEach((e) => !view.guids.has(e.guid) && arrived.has(e.guid) && !e.gone && !fresh.has(e.guid) && fresh.set(e.guid, 0));
    if (view.key !== key || arrived.size > 500) arrived.clear();
    shown.forEach((e) => arrived.delete(e.guid));
    // Ждавшая показа строка ушла с экрана (другая страница, фильтр) — подсвечивать нечего
    const onScreen = new Set(shown.map((e) => e.guid));
    [...fresh].forEach(([g, until]) => until === 0 && !onScreen.has(g) && fresh.delete(g));
    Object.assign(view, { key, rows: v.rows, block: v.block, more: v.more != null, guids: new Set(shown.map((e) => e.guid)) });
    // «↑ N новых выше»: в своей полосе над списком (#newRows), а не поверх строк (BUG-122)
    $("newRows").innerHTML = v.held
      ? `<button type="button" class="btn primary small" data-new-rows>${te("↑ {n, plural, one {# новый} few {# новых} other {# новых}} выше — показать", { n: v.held })}</button>`
      : "";
    $("eventsList").innerHTML = renderInboxBlock(v.block.map(goneRow(true)), v.more) + (v.rows.map(goneRow(false)).map(eventRowHtml).join("") || none);
    watchFresh();
  }

  // Источник в строке очереди (§7, план 87а): «устройство · адрес» под типом события, длинный адрес — многоточием,
  // полный — в подсказке; нет адреса — только устройство; удалено — «устройство удалено», адреса нет
  function sourceLine(e) {
    if (!e.source) return "";
    if (e.source.deleted) return `<div class="event-source">${te("устройство удалено")}</div>`;
    const where = e.address ? t(e.address) : "";
    return `<div class="event-source"${where ? ` title="${escapeHtml(where)}"` : ""}>${te(e.source.name)}${where ? ` · ${escapeHtml(where)}` : ""}</div>`;
  }
  // Название источника там, где адрес не нужен (привязанные): удалённое — «устройство удалено»
  const sourceName = (e) => (!e.source ? "" : e.source.deleted ? t("устройство удалено") : t(e.source.name));

  function eventRowHtml(e) {
    const badge = badgeView(e);
    const prog = stepProgress(e);
    // Значок (style: icon, §7) вместе с названием — одна кнопка: глаз слева, в своей колонке, и
    // название; остальные действия — колонкой справа (RULE-81)
    const open = queueActions(e).find((a) => a.style === "icon");
    const acts = queueActions(e).filter((a) => a.style !== "icon");
    const title = `${e.gone ? "" : rowSound(e)}<strong>${te(e.eventType.name)}</strong>`;
    const pickable = !e.gone && bulkEligible(e);
    return `
    <article class="event ${state.selectedId === e.guid ? "selected" : ""} ${e.gone ? "gone" : ""} ${freshCls(e.guid)}" data-id="${escapeHtml(e.guid)}">
      <input class="pick" type="checkbox" data-check="${escapeHtml(e.guid)}" aria-label="${te("Выбрать {id}", {
        id: e.number,
      })}" ${state.checked.has(e.guid) ? "checked" : ""} ${pickable ? "" : "disabled"} />
      <div class="event-pri" data-color="${escapeHtml(PRIORITIES[e.priority].color)}" role="img" aria-label="${te("Приоритет: {label}", {
        label: inLang(PRIORITIES[e.priority].name),
      })}" title="${escapeHtml(inLang(PRIORITIES[e.priority].description))}"></div>
      <div class="event-main">
        <div class="event-title">
          <span class="event-head">${
            open
              ? `<button type="button" class="event-open" data-do="${open.id}" data-ev="${escapeHtml(e.guid)}" title="${escapeHtml(
                  open.hint
                )}" aria-label="${escapeHtml(`${open.label}: ${te(e.eventType.name)}`)}"><span class="event-eye material-symbols-outlined" aria-hidden="true">${escapeHtml(
                  open.icon
                )}</span>${title}</button>`
              : title
          }${linkedChip(e)}${siblingChip(e)}</span>
          <time datetime="${escapeHtml(e.occurredAt)}">${fmtTime(e.occurredAt)}</time>
        </div>
        ${sourceLine(e)}
        <div class="event-sub">${escapeHtml(e.number)}${alarmTag(e)}</div>
        ${
          e.matchedLinked
            ? `<div class="event-found"><span class="material-symbols-outlined" aria-hidden="true">link</span>${te("Найдено в привязанных: {ids}", {
                ids: e.matchedLinked.map((x) => x.number).join(", "),
              })}</div>`
            : ""
        }
        <div class="event-foot">
          <span class="pri-name" data-color="${escapeHtml(PRIORITIES[e.priority].color)}">${escapeHtml(inLang(PRIORITIES[e.priority].name))}</span>
          ${
            // Бледная строка: вместо состояния, меток и таймеров — почему ушла; они уже неправда (BUG-121)
            e.gone
              ? goneWhyHtml(e)
              : `<span class="badge ${badge.cls}">${escapeHtml(badge.text)}</span>
          ${levelChip(e)}
          ${timerChip(e)}
          ${holdChip(e)}
          ${prog.total ? `<span class="event-prog">${escapeHtml(scenarioTitle(e))}</span>` : ""}`
          }
        </div>
      </div>
      <div class="event-acts">
        ${acts
          .map(
            (a) =>
              `<button type="button" class="btn ${a.style} event-act" data-do="${a.id}" data-ev="${escapeHtml(
                e.guid
              )}" title="${escapeHtml(a.hint)}" ${a.disabled ? 'aria-disabled="true"' : ""}>${escapeHtml(a.label)}</button>`
          )
          .join("")}
      </div>
    </article>
        `;
  }

  // Заголовок карточки — номер, состояние, уровень и нормативы; название и место — в самой карточке.
  // Один раз, без повтора номера и названия ниже
  function renderWorkHeader(ev) {
    if (!ev) {
      $("workTitle").textContent = t("Обработка");
      return;
    }
    const badge = badgeView(ev);
    $("workTitle").innerHTML = `
      <span class="work-num">${escapeHtml(ev.number)}</span>
      <span class="badge ${badge.cls}">${escapeHtml(badge.text)}</span>
      ${levelChip(ev)}
      ${PRIORITIES[ev.priority] ? `<span class="pri-name" data-color="${escapeHtml(PRIORITIES[ev.priority].color)}">${escapeHtml(inLang(PRIORITIES[ev.priority].name))}</span>` : ""}
      ${timerChip(ev, "sla")}
      ${holdChip(ev, "sla")}
      ${linkedChip(ev)}`;
  }

  // Пояснение в карточке — от сервера, по правилам cardNotes машины (§6.3): интерфейс только показывает
  function workNote(ev) {
    const n = ev && ev.note;
    if (!n) return "";
    return `<div class="work-note${n.style ? ` ${escapeHtml(n.style)}` : ""}">${escapeHtml(say(n.key, n.vars))}</div>`;
  }


  function renderScenario() {
    const ev = selected();
    const root = $("scenarioRoot");
    renderWorkHeader(ev);
    if (!ev || !ev.scenario) {
      root.innerHTML = `<div class="empty">${te("Инцидент не выбран")}</div>`;
      return;
    }
    const path = pathOf(ev);
    const editable = !ev.readOnly;
    const acts = cardActions(ev);
    const primary = acts.filter((a) => a.placement === "primary");
    const head = acts.filter((a) => a.placement === "header");
    const more = acts.filter((a) => a.placement === "menu");
    // Вкладка карточки: «Сценарий» или «Привязанные инциденты» (есть, только если привязанные есть);
    // другая карточка — со сценария
    // Открыта из поиска, нашедшего привязанный, — сразу на вкладке привязанных
    if (state.workTabFor !== ev.guid) Object.assign(state, { workTab: foundLinked(ev.guid).length ? "linked" : "scenario", workTabFor: ev.guid });
    const tab = ev.linkedCount ? state.workTab : "scenario";
    // Внизу один ряд (§7, RULE-89): «К очереди»; главные действия машины (ui.placement = primary) и меню «Ещё»
    // с остальными; «Назад» и «Далее» справа. Недоступные — серые, в том числе на вкладке привязанных.
    // «Комментарий» (placement = header) — в шапке карточки

    const i = cursorOf(ev);
    const step = stepOf(ev, path[i]);
    const summary = tab === "scenario" && atSummary(ev);
    const canNext = tab === "scenario" && !summary && canGoNext(ev, i, editable);
    // Подсказка на пройденном шаге — с какого шага продолжить, если закрыть «Обработан» пока нельзя: набор
    // «закрытие» — сценарий пройден до конца (§2.2, §14.5)
    const close = actionOf(ev, "close");
    const results = close && close.fieldOptions && close.fieldOptions.resultId ? close.fieldOptions.resultId.options : [];
    const canClose = editable && Boolean(close && close.enabled) && results.some((r) => fullyProcessed(r.id) && !r.disabled);
    const log = renderLog(ev);

    root.innerHTML = `
      <div class="work-wrap">
      <div class="work-doc">
        <div class="work-top">
          ${renderIncidentHead(ev, head)}
          ${workNote(ev)}
          ${alarmBlock(ev)}
          ${maintenanceBlock(ev)}
          ${workTabs(ev, tab)}
          ${
            tab !== "scenario"
              ? ""
              : `<ol class="crumbs ${editable ? "live" : ""}" aria-label="${te("Шаги сценария")}">
          ${path
            .map((id, idx) => {
              const s = stepOf(ev, id);
              const open = true;
              const current = idx === i && !summary;
              const answer = answerText(s, entryOf(ev, id));
              const nav = open && !current;
              return `
                <li class="crumb ${current ? "current" : ""} ${answer ? "done" : ""} ${open ? "" : "locked"} ${nav ? "nav" : ""}" ${
                  current ? 'aria-current="step"' : ""
                } ${nav ? `data-crumb="${idx}" role="button" tabindex="0"` : ""} title="${escapeHtml(crumbTitle(s))}">
                  <span class="crumb-track">
                    <span class="crumb-n">${idx + 1}</span>
                    <span class="crumb-line" aria-hidden="true"></span>
                  </span>
                  <span class="crumb-body">
                    <span class="crumb-name">${crumbLock(s)}${te(stepShort(s))}</span>
                    ${answer && !current ? `<span class="crumb-ans">${te(answer)}</span>` : ""}
                  </span>
                </li>
              `;
            })
            .join("")}
          ${aheadOf(ev)
            .map(
              (id, k) => `
                <li class="crumb locked ahead" title="${escapeHtml(crumbTitle(stepOf(ev, id), t("Может измениться от ответов")))}">
                  <span class="crumb-track">
                    <span class="crumb-n">${path.length + k + 1}</span>
                    <span class="crumb-line" aria-hidden="true"></span>
                  </span>
                  <span class="crumb-body">
                    <span class="crumb-name">${crumbLock(stepOf(ev, id))}${te(stepShort(stepOf(ev, id)))}</span>
                  </span>
                </li>
              `
            )
            .join("")}
          ${summaryCrumb(ev, summary)}
          </ol>`
          }
        </div>
        <div class="work-step ${tab === "linked" ? "lnk" : ""}">
          ${
            tab === "linked"
              ? `<div class="step-card lnk-panel">${linkedPanel(ev)}</div>`
              : summary
              ? `<div class="step-card summary-card">${summaryPanel(ev)}</div>`
              : `<div class="step-card">
            <div class="step-h">
              <strong>${te(stepShort(step))}</strong>
              ${stepTags(step, ev, i)}
            </div>
            ${lockedStep(step) && editable && !isCurrentStep(ev, i) ? `<p class="step-locked">${te("Ответ записан, этот шаг не переотвечается.")}</p>` : ""}
            ${renderStepControl(step, ev, stepEditable(ev, i, editable))}
          </div>`
          }
        </div>
        <div class="work-bottom">
          <div class="scenario-actions">
            <div class="scenario-actions-start">
              <button type="button" class="btn outline" id="backToQueue" aria-label="${te("К очереди")}" title="${te("Вернуться к очереди, инцидент остаётся за вами")}">
                <span class="material-symbols-outlined" aria-hidden="true">arrow_back</span><span class="btq-label">${te("К очереди")}</span>
              </button>
            </div>
            ${primary.length ? `<div class="work-acts">${primary.map((a) => actButton(a, ev)).join("")}</div>` : ""}
            ${moreMenu(primary, more, ev)}
            <div class="scenario-actions-end">
              <button type="button" class="btn outline" id="stepBack" ${offAttr(!(tab !== "scenario" || (i === 0 && !summary)), backWhy(tab))}>${te("Назад")}</button>
              <button type="button" class="btn ${editable ? "primary" : "outline"}" id="stepNext" ${offAttr(canNext, nextWhy(ev, i, editable, tab, summary))}>${te("Далее")}</button>
            </div>
          </div>
          ${
            tab === "scenario" && editable && !canClose && !runDone(ev) && !isCurrentStep(ev, i)
              ? `<p class="step-hint">${te("Сначала шаг {n}: {name}", { n: path.length, name: t(stepShort(stepOf(ev, path[path.length - 1]))) })}</p>`
              : ""
          }
          ${log.bar}
        </div>
      </div>
      ${log.side}
      </div>
    `;
    root.querySelectorAll(".log-pop, .side-log .log-list").forEach((list) => (list.scrollTop = list.scrollHeight));
  }

  // «Итог» в ленте шагов — после шагов впереди, без номера: в «Шаг N из M» не входит (RULE-95). До конца
  // сценария — бледный, после — можно перейти
  function summaryCrumb(ev, current) {
    const done = runDone(ev);
    const nav = done && !current;
    const closed = isDone(ev);
    const ans = closed ? resultLabel(ev) : nav ? t("Можно завершить") : "";
    return `
      <li class="crumb summary-crumb ${current ? "current" : ""} ${closed ? "done" : ""} ${done ? "" : "locked ahead"} ${nav ? "nav" : ""}" ${
        current ? 'aria-current="step"' : ""
      } ${nav ? 'data-crumb="summary" role="button" tabindex="0"' : ""} title="${te(done ? "Итог: результат и закрытие" : "Итог — после последнего шага сценария")}">
        <span class="crumb-track">
          <span class="crumb-n"><span class="material-symbols-outlined" aria-hidden="true">flag</span></span>
        </span>
        <span class="crumb-body">
          <span class="crumb-name">${te("Итог")}</span>
          ${ans ? `<span class="crumb-ans">${escapeHtml(ans)}</span>` : ""}
        </span>
      </li>
    `;
  }

  // Шаг «Итог»: сценарий пройден — результат «Обработан», комментарий необязателен, «Завершить инцидент».
  // Другой результат — «Закрыть без обработки» в ряду действий
  function summaryPanel(ev) {
    const head = `<div class="step-h"><strong>${te("Итог")}</strong></div>`;
    if (isDone(ev)) {
      const why = fullyProcessed(ev.closeResultId) ? t("Инцидент закрыт с результатом «Обработан».") : t("Инцидент закрыт: {why}.", { why: resultLabel(ev) });
      return `${head}<p class="step-ask">${escapeHtml(why)}</p>${ev.result ? `<p class="step-q">${escapeHtml(ev.result)}</p>` : ""}`;
    }
    const ok = canFinish(ev);
    const opt = processedOption(ev);
    const close = actionOf(ev, "close");
    const why = ev.readOnly ? "" : opt && opt.disabled ? opt.reason : close && !close.enabled ? actionWhy(close) : "";
    const d = state.drafts.get(draftKey(ev, SUMMARY));
    return `${head}
      <p class="step-ask">${te("Сценарий пройден до конца. Инцидент закроется с результатом «Обработан».")}</p>
      <p class="step-q">${te("Если нужен другой результат — «Закрыть без обработки».")}</p>
      <textarea class="summary-comment" rows="3" data-summary-comment placeholder="${te("Итог обработки для отчёта — необязательно")}" ${
        ok ? "" : "disabled"
      }>${escapeHtml(d ? d.value : "")}</textarea>
      <button type="button" class="btn primary summary-finish" data-finish ${ok ? "" : "disabled"}>
        <span class="material-symbols-outlined" aria-hidden="true">task_alt</span>${te("Завершить инцидент")}
      </button>
      ${why ? `<p class="step-locked">${escapeHtml(why)}</p>` : ""}`;
  }

  // Журнал — одной строкой под кнопками: последнее событие и сколько всего записей. По нажатию — весь журнал
  // лентой поверх шага, новые снизу; свернуть — тем же нажатием, Esc или щелчком мимо. Новая запись на миг
  // подсвечивается: заметно краем глаза, читать не обязательно
  // Карточка шире шага и журнала рядом — журнал колонкой справа на всю высоту (styles.css, @container card):
  // разметка у обоих видов есть сразу, какой показать — решает ширина
  function renderLog(ev) {
    const items = ev.journal || [];
    if (!items.length) return { bar: "", side: "" };
    const seen = state.logSeen.get(ev.guid);
    state.logSeen.set(ev.guid, items.length);
    const fresh = (i) => (seen != null && i >= seen ? "fresh" : "");
    const open = state.logOpen === ev.guid;
    const last = items[items.length - 1];
    const row = (l, i) => `
      <li class="log-row ${fresh(i)}">
        <time class="log-t">${escapeHtml(fmtTime(l.at))}</time>
        <span class="log-x">${escapeHtml(journalText(l))} <span class="log-who">${escapeHtml(actorName(l.actor))}</span>${(l.attachments || [])
          .map((f) => ` <span class="log-file"><span class="material-symbols-outlined" aria-hidden="true">attach_file</span>${escapeHtml(f.fileName || "")}</span>`)
          .join("")}</span>
      </li>`;
    const count = te("{n, plural, one {# запись} few {# записи} other {# записей}}", { n: items.length });
    const side = `
      <aside class="side-log" aria-label="${te("Журнал")}">
        <div class="side-log-h"><span class="log-h">${te("Журнал")}</span><span class="log-n">${count}</span></div>
        <ol class="log-list">${items.map(row).join("")}</ol>
      </aside>`;
    const bar = `
      <div class="log ${open ? "open" : ""}">
        ${open ? `<div class="log-pop" role="region" aria-label="${te("Журнал")}"><ol class="log-list">${items.map(row).join("")}</ol></div>` : ""}
        <button type="button" class="log-bar" data-log-toggle aria-expanded="${open}" title="${te(open ? "Свернуть журнал" : "Показать весь журнал")}">
          <span class="log-h">${te("Журнал")}</span>
          <span class="log-last ${fresh(items.length - 1)}"><time class="log-t">${escapeHtml(fmtTime(last.at))}</time> ${escapeHtml(journalText(last))}</span>
          <span class="log-n">${count}</span>
          <span class="material-symbols-outlined" aria-hidden="true">${open ? "expand_more" : "expand_less"}</span>
        </button>
      </div>`;
    return { bar, side };
  }
  function closeLog() {
    state.logOpen = null;
    renderScenario();
  }

  // Блок «Источник» карточки (§7, план 87а): устройство, тип и действующий адрес на момент открытия;
  // нет адреса — устройство и тип; удалено — «устройство удалено», адреса нет
  function sourceBlock(ev) {
    const src = ev.source;
    const body = !src
      ? `<span class="src-device">${te("Источник не указан")}</span>`
      : src.deleted
        ? `<span class="src-device">${te("устройство удалено")}</span>`
        : `<span class="src-device">${te(src.name)}</span> · <span class="src-type">${te(src.typeLabel)}</span>${
            ev.address ? `<span class="src-address" title="${escapeHtml(t(ev.address))}">${te(ev.address)}</span>` : ""
          }`;
    return `<div class="incident-source"><span class="src-label">${te("Источник")}</span>${body}</div>`;
  }
  // Над шагами полосы прогресса нет: сколько пройдено, видно по самим шагам (RULE-90). Номер, состояние
  // и нормативы — в заголовке карточки (renderWorkHeader)
  // Полоса «{что}: {кто} — только просмотр» (§22.7): пока карточка для меня только на просмотр; снова моя — полосы нет
  function evictedBar(ev) {
    const gone = state.evicted[ev.guid];
    if (!gone) return "";
    if (!ev.readOnly) {
      delete state.evicted[ev.guid];
      return "";
    }
    const text = gone.who ? te("{what}: {who} — только просмотр", { what: gone.what, who: gone.who }) : te("{what} — только просмотр", { what: gone.what });
    return `<div class="evicted-bar" role="status" data-evicted="${escapeHtml(ev.guid)}"><span class="material-symbols-outlined" aria-hidden="true">visibility</span> ${text}</div>`;
  }

  function renderIncidentHead(ev, acts) {
    return `${evictedBar(ev)}
      <div class="incident-head">
        <div class="incident-title">
          <h3>${te(ev.eventType.name)}</h3>
          ${sourceBlock(ev)}
        </div>
        ${acts && acts.length ? `<div class="head-acts">${acts.map((a) => actButton(a, ev)).join("")}</div>` : ""}
      </div>
    `;
  }

  // Кнопка действия карточки; item — пункт меню «Ещё» (primary — копия главного действия для узкой карточки)
  function actButton(a, ev, item) {
    const cls = item ? `more-item${a.danger ? " danger" : ""}${item === "primary" ? " more-primary" : ""}` : `btn ${a.style}`;
    return `<button type="button" class="${cls}" ${item ? 'role="menuitem" tabindex="-1"' : ""} data-do="${a.id}" data-ev="${escapeHtml(ev.guid)}" title="${escapeHtml(
      a.hint
    )}" ${a.disabled ? 'aria-disabled="true"' : ""}>${escapeHtml(a.label)}</button>`;
  }

  // Меню «Ещё» нижней панели (§7): действия с ui.placement = menu, опасные (ui.danger) — последними, после
  // разделителя. Главные действия здесь тоже есть — видны только на узкой карточке, где их нет в ряду
  function moreMenu(primary, more, ev) {
    if (!more.length && !primary.length) return "";
    const plain = more.filter((a) => !a.danger);
    const danger = more.filter((a) => a.danger);
    const open = state.moreOpen === ev.guid;
    const items = [
      ...primary.map((a) => actButton(a, ev, "primary")),
      ...plain.map((a) => actButton(a, ev, "menu")),
      ...(danger.length ? ['<div class="more-sep" role="separator"></div>', ...danger.map((a) => actButton(a, ev, "menu"))] : []),
    ];
    return `
      <div class="more${more.length ? "" : " only-primary"}">
        <button type="button" class="btn outline" id="moreActs" aria-haspopup="menu" aria-expanded="${open}" aria-controls="moreMenu">
          ${te("Ещё")}<span class="material-symbols-outlined" aria-hidden="true">expand_more</span>
        </button>
        <div class="more-menu" id="moreMenu" role="menu" aria-label="${te("Другие действия")}" ${open ? "" : "hidden"}>${items.join("")}</div>
      </div>`;
  }
  const moreItems = () => [...document.querySelectorAll("#moreMenu [role=menuitem]")].filter((b) => b.offsetParent);
  function setMore(open, focus) {
    const btn = $("moreActs");
    const menu = $("moreMenu");
    if (!btn || !menu) return;
    const ev = selected();
    state.moreOpen = open && ev ? ev.guid : null;
    menu.hidden = !open;
    btn.setAttribute("aria-expanded", String(open));
    if (open) {
      const list = moreItems();
      const at = focus === "last" ? list[list.length - 1] : list[0];
      if (focus && at) at.focus();
    } else if (focus) btn.focus();
  }
  // Клавиатура меню «Ещё»: Enter, пробел и стрелки открывают, стрелки, Home и End — по пунктам, Esc и Tab
  // закрывают, после Esc фокус — на «Ещё»
  function moreKey(e) {
    if (e.target.closest("#moreActs")) {
      if (["Enter", " ", "ArrowDown", "ArrowUp"].includes(e.key)) {
        e.preventDefault();
        setMore(true, e.key === "ArrowUp" ? "last" : "first");
      } else if (e.key === "Escape" && state.moreOpen) {
        e.preventDefault();
        e.stopPropagation();
        setMore(false, true);
      }
      return true;
    }
    if (!e.target.closest("#moreMenu")) return false;
    const list = moreItems();
    const i = list.indexOf(document.activeElement);
    const go = (k) => list.length && list[(k + list.length) % list.length].focus();
    if (e.key === "ArrowDown") go(i + 1);
    else if (e.key === "ArrowUp") go(i - 1);
    else if (e.key === "Home") go(0);
    else if (e.key === "End") go(list.length - 1);
    else if (e.key === "Escape") {
      e.stopPropagation();
      setMore(false, true);
    } else {
      if (e.key === "Tab") setMore(false);
      return true;
    }
    e.preventDefault();
    return true;
  }

  // Пометки в шапке шага: «необязательно»; у шага без переответа на текущем шаге — заранее, что ответ потом
  // не изменить
  function stepTags(step, ev, i) {
    const tags = [];
    if (!stepRequired(step)) tags.push(te("необязательно"));
    if (lockedStep(step) && isCurrentStep(ev, i))
      tags.push(`<span class="material-symbols-outlined step-lock" aria-hidden="true">lock</span>${te("ответ нельзя будет изменить")}`);
    return tags.length ? `<span class="step-tags">${tags.join(" · ")}</span>` : "";
  }

  // Поле шага по его типу: пояснение — description шага, вопрос — view.label, ответ — черновик, записанный
  // или значение по умолчанию. Ниже — макрос, который запустил ответ на этот шаг
  function renderStepControl(step, ev, enabled) {
    const dis = enabled ? "" : "disabled";
    const view = step.view || {};
    const value = valueOf(ev, step);
    const id = escapeHtml(step.id);
    const note = step.description ? `<p class="step-q">${te(step.description)}</p>` : "";
    const question = view.label && view.label !== stepShort(step) ? `<p class="step-ask">${te(view.label)}</p>` : "";
    const options = view.options || [];
    let control = "";
    if (step.type === "Checkbox" && options.length === 1) {
      // Одна отметка — кнопкой подтверждения
      const on = Array.isArray(value) && value.includes(options[0].id);
      control = `
        <button type="button" class="confirm-btn ${on ? "on" : ""}" data-confirm="${id}" ${dis}>
          <span class="material-symbols-outlined">${on ? "check_circle" : "radio_button_unchecked"}</span>
          ${te(options[0].label)}
        </button>`;
    } else if (step.type === "Checkbox") {
      const picked = Array.isArray(value) ? value : [];
      control = `<div class="checks">${options
        .map(
          (o) =>
            `<label class="${picked.includes(o.id) ? "picked" : ""}"><input type="checkbox" data-check="${id}" value="${escapeHtml(o.id)}" ${
              picked.includes(o.id) ? "checked" : ""
            } ${dis} /> ${te(o.label)}</label>`
        )
        .join("")}</div>`;
    } else if (step.type === "RadioButton") {
      control = `<div class="radios">${options
        .map(
          (o) =>
            `<label class="${value === o.id ? "picked" : ""}"><input type="radio" name="${id}" data-ans="${id}" value="${escapeHtml(o.id)}" ${
              value === o.id ? "checked" : ""
            } ${dis} /> ${te(o.label)}</label>`
        )
        .join("")}</div>`;
    } else if (step.type === "Select") {
      // Несколько списков, в каждом можно отметить несколько вариантов (спецификация, раздел 6.3)
      const picked = value || {};
      control = view.lists
        .map(
          (l) => `<div class="step-list">${
            // Подпись единственного списка, совпадающая с названием шага, не повторяется — как вопрос шага
            view.lists.length === 1 && l.label === stepShort(step) ? "" : `<p class="step-q">${te(l.label)}</p>`
          }<div class="checks">${l.options
            .map((o) => {
              const on = (picked[l.id] || []).includes(o.id);
              return `<label class="${on ? "picked" : ""}"><input type="checkbox" data-list="${id}" data-list-id="${escapeHtml(l.id)}" value="${escapeHtml(
                o.id
              )}" ${on ? "checked" : ""} ${dis} /> ${te(o.label)}</label>`;
            })
            .join("")}</div></div>`
        )
        .join("");
    } else if (step.type === "Comment" && view.readonly) {
      control = view.default ? `<p class="step-q">${te(view.default)}</p>` : "";
    } else if (step.type === "Comment") {
      control = `<textarea rows="4" data-ans="${id}" placeholder="${te(stepRequired(step) ? "" : "Можно пропустить")}" ${dis}>${escapeHtml(value || "")}</textarea>`;
    } else if (step.type === "Datetime") {
      control = `<input type="datetime-local" data-when="${id}" value="${escapeHtml(localWhen(value))}" ${dis} />`;
    } else if (step.type === "Image") {
      // Вложение одно (профиль МИ): новый снимок или файл заменяет прежний
      const pick =
        view.source === "fixed"
          ? view.image
            ? `<img class="step-img" src="${escapeHtml(view.image)}" alt="${te(view.label)}" />`
            : ""
          : view.source === "operator"
            ? `<input type="file" accept="image/*" data-file="${id}" ${dis} />`
            : `<button type="button" class="btn outline" data-snap="${id}" ${dis}>${te(view.source === "map" ? "Снимок карты" : "Снимок с камеры")}</button>`;
      control = `<div class="macro-row">${pick}${value ? `<span class="btn ok" aria-disabled="true">${te("Фото: {n}", { n: 1 })}</span>` : ""}</div>`;
    } else if (step.type === "Message") {
      control = `<button type="button" class="btn primary" data-press="${id}" ${dis}>${te(view.label)}</button>`;
    }
    const macros = macrosOf(ev, step.id);
    const launched = macros.length
      ? `<div class="macro-row">${macros.map((m) => `<span class="btn ok" aria-disabled="true">${te("Запущено")} · ${te(m)}</span>`).join("")}</div>`
      : "";
    return note + (step.type === "Message" ? "" : question) + control + launched;
  }

  // Дата и время шага Datetime: в прохождении — момент в UTC (ISO-8601), в поле — местное время браузера
  function localWhen(value) {
    if (!value) return "";
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return "";
    const pad = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  const isoWhen = (local) => (local ? new Date(local).toISOString().replace(/\.\d+Z$/, "Z") : null);

  /* ===== Видео и карта: камеры и устройства — из карточки (IncidentMedia, DeviceRef) ===== */

  const cardOfSelected = () => (store.card && store.card.guid === state.selectedId ? store.card : null);
  const camerasOf = (ev) => (ev && ev.media ? ev.media.cameras.map((c) => c.guid) : []);

  function devView(id) {
    const ev = cardOfSelected();
    const ref = (ev && ev.devices ? ev.devices.find((d) => d.guid === id) : null) || {};
    const cam = ev && ev.media ? ev.media.cameras.find((c) => c.guid === id) : null;
    return {
      id,
      name: ref.name || (cam && cam.name) || id,
      type: ref.typeId || "camera",
      typeLabel: ref.typeLabel || "Камера видеонаблюдения",
      thumbnailUrl: cam ? cam.thumbnailUrl : null,
    };
  }

  // Картинки камер и планов приходят ссылками (GET …/media). Ссылки demo:scene/<имя> и
  // demo:plan/<имя> из эталонного набора — рисунки-заглушки прототипа (SCENES, PLANS),
  // остальные — обычная картинка по ссылке
  const demoArt = (url, kind) => {
    const m = /^demo:(scene|plan)\/([\w-]+)$/.exec(url || "");
    return m && m[1] === kind ? m[2] : null;
  };

  function mediaMode() {
    const ev = cardOfSelected() || selected();
    const kinds = ev && ev.mediaKinds ? ev.mediaKinds : ["video", "map"];
    return kinds.length === 1 ? kinds[0] : "both";
  }

  function applyMediaLayout() {
    $("panelMedia").dataset.media = mediaMode();
  }

  function applyLayoutState() {
    const ws = $("workspace");
    const mode = mediaMode();
    if (state.full && mode !== "both" && mode !== state.full) state.full = null;
    ws.dataset.groups = state.groupsOn ? "on" : "off";
    ws.dataset.mediapanel = state.mediaOn ? "on" : "off";
    if (state.full) ws.dataset.full = state.full;
    else delete ws.dataset.full;
  }

  function toggleFull(which) {
    state.full = state.full === which ? null : which;
    applyLayoutState();
    renderTopbar();
  }

  // Подписи внутри готовых SVG-сцен и планов переводятся по тексту узла <text>

  function trSvg(svg) {
    if (LANG === "ru") return svg;
    return svg.replace(/(<text\b[^>]*>)([^<]+)(<\/text>)/g, (m, open, body, close) => {
      const label = body.trim();
      return open + escapeHtml(t(label)) + close;
    });
  }

  function renderVideo() {
    const ev = cardOfSelected();
    const cams = camerasOf(ev);
    if (!cams.length) {
      $("videoStage").innerHTML = `<div class="empty">${te("К инциденту не привязаны камеры")}</div>`;
      $("camStrip").hidden = true;
      $("camStrip").innerHTML = "";
      return;
    }
    if (!cams.includes(state.activeCam)) state.activeCam = cams[0];
    const idx = cams.indexOf(state.activeCam);
    const cam = devView(state.activeCam);
    const live = state.videoMode === "live";
    const many = cams.length > 1;

    $("videoStage").innerHTML = `
      <div class="cam" data-cam="${escapeHtml(state.activeCam)}">
        ${
          cam.thumbnailUrl && !demoArt(cam.thumbnailUrl, "scene")
            ? `<img class="cam-scene" src="${escapeHtml(cam.thumbnailUrl)}" alt="">`
            : `<svg class="cam-scene" viewBox="0 0 320 180" preserveAspectRatio="xMidYMid meet" aria-hidden="true">
          ${trSvg(SCENES[demoArt(cam.thumbnailUrl, "scene")] || SCENES.hall)}
        </svg>`
        }
        <div class="cam-hud">
          <div>
            <div class="mode-tag ${state.videoMode}">${live ? "LIVE" : te("АРХИВ")}</div>
            <b>${te(cam.name)}</b>
          </div>
          <span>${live ? nowStamp() : fmtTime(ev.occurredAt)}</span>
        </div>
      </div>
      ${
        many
          ? `
        <button type="button" class="cam-nav prev" data-cam-step="-1" title="${te("Предыдущая камера")}" aria-label="${te(
              "Предыдущая камера"
            )}">
          <span class="material-symbols-outlined">chevron_left</span>
        </button>
        <button type="button" class="cam-nav next" data-cam-step="1" title="${te("Следующая камера")}" aria-label="${te(
              "Следующая камера"
            )}">
          <span class="material-symbols-outlined">chevron_right</span>
        </button>`
          : ""
      }
    `;

    $("camStrip").hidden = !many;
    // Скрытая полоса не должна хранить подписи прошлого инцидента и прошлого языка
    if (!many) $("camStrip").innerHTML = "";
    if (many) {
      $("camStrip").innerHTML = `
        <div class="cam-ticks">
          ${cams
            .map((id, i) => {
              const c = devView(id);
              return `<button type="button" class="cam-tick ${i === idx ? "active" : ""}" data-cam="${escapeHtml(id)}" title="${te(
                c.name
              )}" aria-label="${te(c.name)}"></button>`;
            })
            .join("")}
        </div>
        <span class="cam-counter">${idx + 1} / ${cams.length}</span>
      `;
    }
  }

  function stepCamera(delta) {
    const cams = camerasOf(cardOfSelected());
    if (cams.length < 2) return;
    const i = cams.indexOf(state.activeCam);
    state.activeCam = cams[(Math.max(0, i) + delta + cams.length) % cams.length];
    renderVideo();
    renderMap();
  }

  function deviceMarker(pos, opts) {
    const id = pos.deviceGuid;
    const dev = devView(id);
    const cls = ["dev-marker", `dev-${dev.type}`, opts.source ? "is-source" : "", opts.active ? "is-active" : ""]
      .filter(Boolean)
      .join(" ");
    const clickable = dev.type === "camera" ? ` data-cam="${id}"` : "";
    return `
      <g class="${cls}"${clickable} transform="translate(${pos.x},${pos.y})">
        <title>${te(dev.typeLabel)}: ${te(dev.name)}${opts.source ? ` — ${te("источник события")}` : ""}</title>
        ${
          opts.source
            ? `<circle class="dev-halo" r="12">
                 <animate attributeName="r" values="11;20;11" dur="1.8s" repeatCount="indefinite"/>
                 <animate attributeName="opacity" values="0.5;0;0.5" dur="1.8s" repeatCount="indefinite"/>
               </circle>`
            : ""
        }
        <circle class="dev-bg" r="10.5"/>
        <g class="dev-glyph" transform="scale(0.8)">${DEVICE_GLYPH[dev.type] || DEVICE_GLYPH.camera}</g>
      </g>
    `;
  }

  function renderMap() {
    const ev = cardOfSelected();
    if (!ev) {
      $("mapCaption").textContent = t("Место сработки");
      $("mapRoot").innerHTML = `<div class="empty">${te("Инцидент не выбран")}</div>`;
      return;
    }
    const plan = ev.media && ev.media.map;
    if (!plan) {
      $("mapCaption").textContent = t("Место сработки");
      $("mapRoot").innerHTML = `<div class="empty">${te("План площадки не привязан")}</div>`;
      return;
    }
    const art = demoArt(plan.imageUrl, "plan");
    const drawing = art ? trSvg(PLANS[art] ? PLANS[art].svg : "") : `<image href="${escapeHtml(plan.imageUrl || "")}" width="400" height="260"/>`;
    const source = ev.source ? ev.source.guid : null;
    $("mapCaption").textContent = t(plan.planName);

    // Источник рисуем последним, чтобы пульсация была поверх остальных значков.
    const ordered = plan.markers.filter((m) => m.deviceGuid !== source).concat(plan.markers.filter((m) => m.deviceGuid === source));
    const markers = ordered.map((m) => deviceMarker(m, { source: m.deviceGuid === source, active: m.deviceGuid === state.activeCam })).join("");
    const srcDev = source ? devView(source) : null;
    const camCount = camerasOf(ev).length;

    $("mapRoot").innerHTML = `
      <svg class="map-svg" viewBox="0 0 400 260" role="img" aria-label="${te("План: {name}", { name: t(plan.planName) })}">
        ${drawing}
        ${markers}
      </svg>
      <div class="map-legend">
        <span class="map-legend-src">${srcDev ? `${te(srcDev.typeLabel)}: ${te(srcDev.name)}` : te("Источник не указан")}</span>
        <span class="map-legend-cams">${camCount ? te("Камер в зоне: {n}", { n: camCount }) : te("Камеры не привязаны")}</span>
      </div>
    `;
  }

  function renderStatus() {
    const ev = selected();
    const usage = store.session ? store.session.usage : { activeCount: 0, onHoldCount: 0 };
    // Лимит «в работе» снят — без «из N» (§10.2, RULE-69)
    const queueVars = { n: store.counters.open || 0, a: usage.activeCount, max: LIMITS.maxActive, h: usage.onHoldCount };
    // Открытые — все, а не по фильтру над очередью: словом «открытых», чтобы не путать с числом у «Очередь» (BUG-100)
    $("statusQueue").textContent =
      LIMITS.maxActive == null ? t("Открытых: {n} · у меня: {a}, отложено: {h}", queueVars) : t("Открытых: {n} · у меня: {a} из {max}, отложено: {h}", queueVars);
    if (!ev) {
      $("statusIncident").textContent = t("Очередь ожидает выбора инцидента");
      $("statusSteps").textContent = "";
      $("statusSla").textContent = "";
      return;
    }
    const prog = stepProgress(ev);
    const badge = badgeView(ev);
    $("statusIncident").textContent =
      state.mode === "work" ? t("Карточка {id} · {badge}", { id: ev.number, badge: badge.text }) : `${ev.number} · ${badge.text}`;
    $("statusSteps").textContent =
      state.mode === "work" && ev.scenario && atSummary(ev)
        ? t("Итог")
        : state.mode === "work" && ev.scenario
        ? t("Шаг {i} из {n}", { i: cursorOf(ev) + 1, n: prog.total })
        : scenarioTitle(ev);
    $("statusSla").textContent = statusTimerText(ev);
  }

  function statusTimerText(ev) {
    const view = timerView(ev.timer);
    if (!view) return ev.slaBreached ? t("Норматив нарушен") : "";
    if (!view.running) return t("{label}: на паузе, {time}", { label: t(view.label), time: fmtSla(view.leftMs) });
    return t("{label}: осталось {time}", { label: t(view.label), time: fmtSla(view.leftMs) });
  }

  function fmtSla(ms) {
    const total = Math.floor(Math.max(0, ms) / 1000);
    const m = Math.floor(total / 60);
    const s = total % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function renderAll() {
    if (!WORKFLOW) return;
    const ws = $("workspace");
    if (state.mode !== "work" && state.mobileView === "card") state.mobileView = "queue";
    ws.dataset.mode = state.mode;
    ws.dataset.view = state.mobileView;
    applyLayoutState();
    renderTopbar();
    renderSound();
    renderGroups();
    renderQueueHead();
    if (state.mode === "queue") {
      renderEvents();
    } else {
      renderWorkHeader(selected());
      renderScenario();
    }
    applyMediaLayout();
    renderVideo();
    renderMap();
    renderStatus();
    // Идут плановые работы и другие состояния поста — строка в середине шапки (§22.4, ТЗ-21)
    renderPost();
    // Экран «Смена и статистика» (§23): вкладки по праву, открытый экран — на новом языке и с новыми «сколько длится»
    renderScreen();
    renderShift();
    $("breakBanner").hidden = !onBreak();
    $("signedOutBanner").hidden = !signedOut();
  }

  function syncToggle(btn, on, iconOn, iconOff, titleOn, titleOff) {
    btn.classList.toggle("on", on);
    btn.setAttribute("aria-pressed", String(on));
    btn.querySelector(".material-symbols-outlined").textContent = on ? iconOn : iconOff;
    btn.title = on ? titleOn : titleOff;
  }

  function renderTopbar() {
    const groupsLocked = state.mode === "work" && !narrowQuery.matches;
    const groupsBtn = $("toggleGroups");
    syncToggle(groupsBtn, state.groupsOn, "left_panel_close", "left_panel_open", t("Скрыть панель групп"), t("Показать панель групп"));
    groupsBtn.disabled = groupsLocked;
    if (groupsLocked) groupsBtn.title = t("Панель групп скрыта на время обработки инцидента");
    [...$("mobileNav").children].forEach((b) => {
      const on = b.dataset.view === state.mobileView;
      b.classList.toggle("active", on);
      if (on) b.setAttribute("aria-current", "page");
      else b.removeAttribute("aria-current");
      if (b.dataset.view === "card") b.disabled = state.mode !== "work";
    });
    // То же число, что у «Очередь» в шапке: по фильтру над очередью (BUG-100)
    $("navQueueCount").textContent = String(store.page.total || 0);
    syncToggle(
      $("toggleMedia"),
      state.mediaOn,
      "right_panel_close",
      "right_panel_open",
      t("Скрыть видеомонитор и карту"),
      t("Показать видеомонитор и карту")
    );
    const mode = mediaMode();
    syncToggle(
      $("videoFull"),
      state.full === "video",
      "close_fullscreen",
      "open_in_full",
      t("Свернуть видеомонитор"),
      t("Развернуть видеомонитор на всю рабочую область")
    );
    syncToggle($("mapFull"), state.full === "map", "close_fullscreen", "open_in_full", t("Свернуть карту"), t("Развернуть карту на всю рабочую область"));
    $("videoFull").disabled = mode === "map";
    $("mapFull").disabled = mode === "video";
    // Состояние оператора — отдельная машина состояний (§12.1): значение отдаёт сервер, подпись — машина
    const agent = store.session ? store.session.agentState : "ready";
    const agentDef = WORKFLOW.session.states.find((s) => s.id === agent) || {};
    $("dutyBadge").textContent = agentDef.id ? lbl(agentDef) : t(agent);
    $("dutyBadge").classList.toggle("off", Boolean(agentDef.readOnly));
    $("breakBtnLabel").textContent = t(agent === "not_ready" ? "Вернуться с перерыва" : "Уйти на перерыв");
    $("breakBtn").disabled = signedOut();
    $("signOutBtn").hidden = signedOut();
    $("adminBtn").hidden = !can("incident:schema:admin");
  }

  // При переходе к другому инциденту показываем камеру, ближайшую к источнику события.
  function focusCameras(ev) {
    const cams = camerasOf(ev);
    if (!cams.length) return;
    if (state.camFor !== ev.guid || !cams.includes(state.activeCam)) {
      state.activeCam = cams[0];
      state.camFor = ev.guid;
    }
  }

  // Навигация без смены состояния (§6.3)
  async function openCard(navId, ev) {
    if (!ev) return;
    const a = actionOf(ev, navId);
    if (!a || !a.enabled) {
      if (actionWhy(a)) toast(actionWhy(a), "error");
      return;
    }
    state.selectedId = ev.guid;
    state.mode = "work";
    state.mobileView = "card";
    await loadCard();
    renderAll();
  }

  // «К очереди» ничего не меняет: инцидент остаётся в работе и виден
  // в очереди с кнопкой «Продолжить». Отложить — отдельное действие с причиной.
  function backToQueue() {
    state.mode = "queue";
    state.focus = true;
    state.jump = true;
    renderAll();
    return reload();
  }

  /* ===== Состояние оператора (§12.2): перерыв — запрос к серверу ===== */

  // Уход на перерыв — с причиной из машины (§12.1); активный инцидент откладывается системой,
  // право incident:hold не требуется (§12.2: system_hold_break)
  async function toggleBreak() {
    const notReady = WORKFLOW.session.states.find((s) => s.id === "not_ready");
    if (notReady.permission && !can(notReady.permission)) {
      toast(t("Нет права уходить на перерыв"), "error");
      return;
    }
    if (!onBreak()) {
      showForm({ id: "__break__" }, breakForm());
      return;
    }
    try {
      await api.put("/operator/session/agent-state", { agentState: "ready" });
      toast(t("Перерыв окончен"));
    } catch (err) {
      toast(problemText(err), "error");
    }
    await reload();
  }

  // Выход из МИ (§12.1): с подтверждением — свои в работе и отложенные сервер вернёт в очередь,
  // адресованные лично — дежурной группе или в очередь (owner_signed_out, addressee_signed_out_*).
  // Сколько вернётся — счётчики сессии от сервера (usage, §10.2): mineIn машины — свои в работе и отложенные,
  // те же, что в «Мои»; привязанные владельца не имеют и не считаются, единица лимита — один инцидент (BUG-25)
  const signOutForm = () => {
    return {
      id: "__signout__",
      title: "Выйти из МИ",
      confirmLabel: "Выйти",
      style: "danger",
      note: sessionNote("offline", { active: store.session.usage.activeCount, held: store.session.usage.onHoldCount }),
      fields: [],
    };
  };

  async function setPresence(agentState, done) {
    try {
      await api.put("/operator/session/agent-state", { agentState });
      toast(t(done));
    } catch (err) {
      toast(problemText(err), "error");
    }
    if (agentState === "offline") {
      state.selectedId = null;
      return backToQueue();
    }
    await reload();
  }

  async function goOnBreak(reasonId) {
    try {
      await api.put("/operator/session/agent-state", { agentState: "not_ready", reasonId });
      toast(t("Перерыв. Переданное вам будет ждать в «Мне на принятие»"));
    } catch (err) {
      toast(problemText(err), "error");
    }
    await reload();
  }

  function closeDrawer() {
    state.groupsOn = false;
    renderAll();
    $("toggleGroups").focus();
  }

  function closeMenus() {
    const open = [...document.querySelectorAll(".menu")].filter((m) => !m.querySelector(".menu-pop").hidden);
    open.forEach((menu) => {
      menu.querySelector(".menu-pop").hidden = true;
      menu.querySelector("[aria-haspopup]").setAttribute("aria-expanded", "false");
    });
    return open[0] || null;
  }

  /* ===== Сплиттеры: группы | очередь-карточка | видеомонитор + карта ===== */

  /* ===== Сплиттеры: группы | очередь-карточка | видеомонитор + карта ===== */

  const LAYOUT_VARS = { groups: "--w-groups-user", media: "--w-media-user", video: "--h-video-user" };
  const LAYOUT_MIN = { groups: 200, media: 280, stage: 320, video: 160, map: 160 };
  const SPLIT_W = 1;

  function setLayoutVar(key, px) {
    document.documentElement.style.setProperty(LAYOUT_VARS[key], `${Math.round(px)}px`);
  }

  function storeLayout() {
    const style = document.documentElement.style;
    const data = {};
    Object.entries(LAYOUT_VARS).forEach(([key, name]) => {
      const px = parseFloat(style.getPropertyValue(name));
      if (px > 0) data[key] = Math.round(px);
    });
    try {
      localStorage.setItem("im-layout", JSON.stringify(data));
    } catch (err) {
      /* приватный режим: раскладка живёт только до перезагрузки */
    }
  }

  function restoreLayout() {
    let data = {};
    try {
      data = JSON.parse(localStorage.getItem("im-layout") || "{}") || {};
    } catch (err) {
      data = {};
    }
    Object.keys(LAYOUT_VARS).forEach((key) => {
      const px = Number(data[key]);
      if (px > 0) setLayoutVar(key, px);
    });
  }

  // Панель не уже своего минимума и не отбирает место у центральной колонки

  function splitRange(key) {
    if (key === "video") {
      const stack = $("panelMedia").getBoundingClientRect().height;
      return [LAYOUT_MIN.video, stack - LAYOUT_MIN.map - SPLIT_W];
    }
    const ws = $("workspace").getBoundingClientRect().width;
    const other = key === "groups" ? $("panelMedia") : $("panelGroups");
    const busy = other.getBoundingClientRect().width;
    return [LAYOUT_MIN[key], ws - busy - LAYOUT_MIN.stage - SPLIT_W * 2];
  }

  function splitSize(key) {
    if (key === "video") return $("panelVideo").getBoundingClientRect().height;
    return $(key === "groups" ? "panelGroups" : "panelMedia").getBoundingClientRect().width;
  }

  function clampSize(v, min, max) {
    return max < min ? min : Math.min(Math.max(v, min), max);
  }

  function bindSplitter(id, key, axis) {
    const el = $(id);
    el.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const [min, max] = splitRange(key);
      const from = axis === "col" ? e.clientX : e.clientY;
      const size = splitSize(key);
      // Панель справа растёт влево, поэтому знак смещения зеркальный
      const sign = key === "media" ? -1 : 1;
      el.setPointerCapture(e.pointerId);
      el.classList.add("dragging");
      document.body.dataset.resize = axis;
      const move = (ev) => {
        const to = axis === "col" ? ev.clientX : ev.clientY;
        setLayoutVar(key, clampSize(size + (to - from) * sign, min, max));
      };
      const stop = () => {
        el.classList.remove("dragging");
        delete document.body.dataset.resize;
        el.removeEventListener("pointermove", move);
        el.removeEventListener("pointerup", stop);
        el.removeEventListener("pointercancel", stop);
        storeLayout();
      };
      el.addEventListener("pointermove", move);
      el.addEventListener("pointerup", stop);
      el.addEventListener("pointercancel", stop);
    });
    el.addEventListener("dblclick", () => {
      document.documentElement.style.removeProperty(LAYOUT_VARS[key]);
      storeLayout();
    });
    el.addEventListener("keydown", (e) => {
      const dir = { ArrowLeft: -1, ArrowUp: -1, ArrowRight: 1, ArrowDown: 1 }[e.key];
      if (!dir) return;
      e.preventDefault();
      e.stopPropagation();
      const [min, max] = splitRange(key);
      const step = e.shiftKey ? 48 : 16;
      setLayoutVar(key, clampSize(splitSize(key) + (key === "media" ? -dir : dir) * step, min, max));
      storeLayout();
    });
  }

  // Смена фильтра, группы или поиска: очередь — заново, выделение — на видимое
  // Другой список — другое выделение (§11.1): сменили узел дерева, фильтр, типы или поиск — отметки снимаются.
  // Порядок очереди состав списка не меняет: keepSelection — отметки остаются
  function requery(keepSelection) {
    state.page = 1;
    state.focus = true;
    if (!keepSelection) dropSelection();
    return reload();
  }

  function bind() {
    restoreLayout();
    bindSplitter("splitGroups", "groups", "col");
    bindSplitter("splitMedia", "media", "col");
    bindSplitter("splitVideo", "video", "row");
    $("themeToggle").addEventListener("click", () => {
      applyTheme(state.themeMode === "light" ? "dark" : "light");
    });
    $("langSelect").addEventListener("change", (e) => applyLang(e.target.value));
    $("toggleGroups").addEventListener("click", () => {
      state.groupsOn = !state.groupsOn;
      applyLayoutState();
      renderTopbar();
    });
    $("toggleMedia").addEventListener("click", () => {
      state.mediaOn = !state.mediaOn;
      if (!state.mediaOn) state.full = null;
      applyLayoutState();
      renderTopbar();
    });
    $("videoFull").addEventListener("click", () => toggleFull("video"));
    $("mapFull").addEventListener("click", () => toggleFull("map"));
    $("eventFilter").addEventListener("change", (e) => {
      state.filter = e.target.value;
      requery();
    });
    // Кнопки состояний: переключатель, выбрана всегда одна
    $("stateButtons").addEventListener("click", (e) => {
      if (e.target.closest("[data-state-more]")) {
        state.stateMenu = !state.stateMenu;
        return renderQueueHead();
      }
      const b = e.target.closest("[data-state]");
      if (!b) return;
      state.stateMenu = false;
      if (state.filter === b.dataset.state) return renderQueueHead();
      state.filter = b.dataset.state;
      requery();
    });
    document.addEventListener("click", (e) => {
      if (state.stateMenu && !e.target.closest(".state-more")) {
        state.stateMenu = false;
        renderQueueHead();
      }
    });
    // Кнопки приоритетов: несколько сразу, повторный щелчок снимает; ни одна — все
    $("priorityButtons").addEventListener("click", (e) => {
      const b = e.target.closest("[data-pri]");
      if (!b) return;
      const v = Number(b.dataset.pri);
      state.priorities = state.priorities.includes(v) ? state.priorities.filter((x) => x !== v) : state.priorities.concat(v);
      requery();
    });
    $("eventsMoreBtn").addEventListener("click", () => {
      state.moreFilters = !state.moreFilters;
      renderMoreFilters();
    });
    $("queueSortSelect").addEventListener("change", async (e) => {
      await api.patch("/operator/session/preferences", { queueSort: e.target.value });
      requery(true);
    });
    // Списки типов над очередью: щелчок по полю — открыть, набор — отбор вариантов, галочка — сразу отбор очереди,
    // «Все…» — снять, щелчок мимо и Esc — закрыть
    const closeTypeList = () => {
      state.tbOpen = null;
      state.tbQ = {};
      renderTypeLists();
    };
    ["deviceTypeFilter", "eventTypeFilter", "scenarioFilter"].forEach((id) => {
      $(id).addEventListener("click", (e) => {
        const toggle = e.target.closest("[data-tb-toggle]");
        const clear = e.target.closest("[data-tb-clear]");
        if (toggle) {
          if (state.tbOpen === toggle.dataset.tbToggle) return;
          state.tbOpen = toggle.dataset.tbToggle;
          state.tbQ = {};
        } else if (clear) {
          state[clear.dataset.tbClear] = [];
          requery();
        } else return;
        renderTypeLists();
      });
      $(id).addEventListener("change", (e) => {
        const box = e.target.closest("[data-tb]");
        if (!box) return;
        const key = box.dataset.tb;
        state[key] = box.checked ? state[key].concat(box.value) : state[key].filter((v) => v !== box.value);
        // Отметил — набранное стирается: можно сразу искать следующее
        state.tbQ = {};
        renderTypeLists();
        requery();
      });
      $(id).addEventListener("input", (e) => {
        const input = e.target.closest("[data-tb-toggle]");
        if (!input) return;
        state.tbQ[input.dataset.tbToggle] = input.value;
        if (state.tbOpen === input.dataset.tbToggle) return comboNarrow(input);
        state.tbOpen = input.dataset.tbToggle;
        renderTypeLists();
      });
      $(id).addEventListener("keydown", (e) => comboKey(e, closeTypeList));
    });
    document.addEventListener("click", (e) => {
      // Щелчок по самому списку его перерисовал — цель уже не на странице: это не «щелчок мимо»
      if (!state.tbOpen || !e.target.isConnected || e.target.closest(".mselect.tb")) return;
      closeTypeList();
    });
    $("eventSearch").addEventListener("input", (e) => {
      state.search = e.target.value;
      requery();
    });
    $("mobileNav").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-view]");
      if (!btn || btn.disabled) return;
      state.mobileView = btn.dataset.view;
      if (state.groupsOn && narrowQuery.matches) state.groupsOn = false;
      renderAll();
    });
    $("groupsScrim").addEventListener("click", closeDrawer);
    $("groupsClose").addEventListener("click", closeDrawer);
    $("eventsPager").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-page]");
      if (!btn || btn.disabled) return;
      state.page = Number(btn.dataset.page);
      reload().then(() => ($("eventsList").scrollTop = 0));
    });
    $("groupSearch").addEventListener("input", (e) => {
      state.groupQuery = e.target.value;
      state.treeHit = 0;
      state.treeHitScroll = true;
      renderGroups();
    });
    $("groupsHitPrev").addEventListener("click", () => stepTreeHit(-1));
    $("groupsHitNext").addEventListener("click", () => stepTreeHit(1));
    // ↓ — в дерево, на текущее найденное (или первый узел); Enter — к следующему найденному,
    // Shift+Enter — к предыдущему; Esc — очистить поиск (RULE-88)
    $("groupSearch").addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown") {
        const first = treeHits()[state.treeHit] || treeItems()[0];
        if (!first) return;
        e.preventDefault();
        focusTreeNode(first);
      } else if (e.key === "Enter") {
        e.preventDefault();
        stepTreeHit(e.shiftKey ? -1 : 1);
      } else if (e.key === "Escape" && e.target.value) {
        e.preventDefault();
        e.stopPropagation();
        e.target.value = "";
        state.groupQuery = "";
        state.treeHit = 0;
        renderGroups();
      }
    });
    $("groupsList").addEventListener("keydown", treeKey);
    $("groupsList").addEventListener("click", (e) => {
      const fbtn = e.target.closest("[data-filter]");
      if (fbtn) {
        e.stopPropagation();
        openFilter(fbtn.dataset.node);
        return;
      }
      const toggle = e.target.closest(".toggle-icon");
      const node = e.target.closest(".tree-node");
      if (!node) return;
      const id = node.dataset.id;
      if (toggle && node.classList.contains("has-children")) {
        e.stopPropagation();
        if (state.openGroups.has(id)) state.openGroups.delete(id);
        else state.openGroups.add(id);
        renderGroups();
        return;
      }
      if (!e.target.closest(".node-content")) return;
      // Путь к выбранному раскрыт: после очистки поиска узел виден и в порядке Tab (BUG-63)
      for (let up = node.parentElement.closest(".tree-node"); up; up = up.parentElement.closest(".tree-node")) state.openGroups.add(up.dataset.id);
      state.treeFocus = id;
      state.groupId = id;
      if (narrowQuery.matches) state.groupsOn = false;
      requery();
    });
    // Подсказка «событие: ещё N» — номера и бейджи соседей, при первом наведении
    $("eventsList").addEventListener("mouseover", (e) => {
      const chip = e.target.closest("[data-siblings]");
      if (chip) siblingTip(chip);
    });
    // Курсор над очередью (§22.1): какая строка под ним; ушёл — блок и список перестраиваются
    const aim = (e) => {
      hover.over = true;
      const row = e.target.closest && e.target.closest("article[data-id]");
      hover.inBlock = Boolean(e.target.closest && e.target.closest(".inbox-block"));
      // Над блоком якорь списка не меняется: список, остановленный на своей строке, держится по ней (BUG-122)
      if (hover.inBlock) return;
      hover.guid = row ? row.dataset.id : null;
      if (row) hover.list = true;
    };
    $("eventsList").addEventListener("mouseover", aim);
    $("eventsList").addEventListener("mousemove", aim);
    // Прокрутка списка или страницы — ждущие показа новые строки могли показаться (§22.3)
    document.addEventListener("scroll", () => fresh.size && checkFresh(), { capture: true, passive: true });
    // Полоса «↑ N новых выше» (#newRows) — над списком: переход курсора между ней и списком список не отпускает,
    // иначе кнопка пропадала бы, пока к ней ведут курсор (BUG-122)
    const leaveQueue = (e) => {
      if (e.relatedTarget && ($("eventsList").contains(e.relatedTarget) || $("newRows").contains(e.relatedTarget))) return;
      Object.assign(hover, { over: false, guid: null, inBlock: false, list: false });
      if (state.mode === "queue") renderEvents();
    };
    $("eventsList").addEventListener("mouseleave", leaveQueue);
    $("newRows").addEventListener("mouseleave", leaveQueue);
    // «↑ N новых выше — показать»: придержанные строки встают на место (§22.3)
    $("newRows").addEventListener("click", (e) => {
      if (!e.target.closest("[data-new-rows]")) return;
      view.rows = null;
      renderEvents();
    });
    $("eventsList").addEventListener("click", async (e) => {
      if (e.target.closest("[data-reset-filters]")) return void resetFilters();
      // «ещё N → показать все»: состояние переключается на фильтр блока
      if (e.target.closest("[data-inbox-all]")) {
        state.filter = inboxCfg().filter;
        return void requery();
      }
      const check = e.target.closest("[data-check]");
      if (check) {
        const id = check.dataset.check;
        if (state.checked.has(id)) state.checked.delete(id);
        else if (LIMITS.maxBulk != null && state.checked.size >= LIMITS.maxBulk) {
          toast(t("Не больше {max} инцидентов в выборке", { max: LIMITS.maxBulk }), "error");
          return;
        } else state.checked.add(id);
        await updateSelection();
        renderEvents();
        return;
      }
      const act = e.target.closest("[data-do]");
      if (act && explainIfOff(act)) return;
      if (act) {
        trigger(act.dataset.do, queueItem(act.dataset.ev), "queue");
        return;
      }
      const row = e.target.closest("[data-id]");
      if (!row || row.dataset.id === state.selectedId) return;
      state.selectedId = row.dataset.id;
      renderEvents();
      await loadCard();
      renderEvents();
      renderGroups();
      applyMediaLayout();
      renderVideo();
      renderMap();
      renderStatus();
    });
    // Текст шага — в черновик; перерисовывается только «Далее», чтобы поле не теряло фокус
    $("scenarioRoot").addEventListener("input", (e) => {
      const ev = selected();
      if (!ev || ev.readOnly) return;
      const note = e.target.closest("textarea[data-summary-comment]");
      if (note) return state.drafts.set(draftKey(ev, SUMMARY), { value: note.value });
      const el = e.target.closest("textarea[data-ans]");
      if (!el) return;
      setDraft(ev, el.dataset.ans, el.value);
      const next = $("stepNext");
      if (next) setOff(next, !canGoNext(ev, cursorOf(ev), true), nextWhy(ev, cursorOf(ev), true, "scenario", false));
    });
    // Выбор, отметки, дата и файлы — в черновик; ответ уходит по «Далее»
    $("scenarioRoot").addEventListener("change", async (e) => {
      const ev = selected();
      if (!ev || ev.readOnly) return;
      const ans = e.target.closest("[data-ans]");
      const check = e.target.closest("[data-check]");
      const list = e.target.closest("[data-list]");
      const when = e.target.closest("[data-when]");
      const file = e.target.closest("[data-file]");
      if (ans && ans.tagName !== "TEXTAREA") setDraft(ev, ans.dataset.ans, ans.value || null);
      else if (check) {
        const boxes = [...$("scenarioRoot").querySelectorAll(`[data-check="${check.dataset.check}"]`)];
        setDraft(ev, check.dataset.check, boxes.filter((b) => b.checked).map((b) => b.value));
      } else if (list) {
        // Ответ Select — отмеченные во всех списках шага: { <список>: [варианты] }
        const step = stepOf(ev, list.dataset.list);
        const boxes = [...$("scenarioRoot").querySelectorAll(`[data-list="${list.dataset.list}"]`)];
        setDraft(ev, step.id, Object.fromEntries(step.view.lists.map((l) => [l.id, boxes.filter((b) => b.checked && b.dataset.listId === l.id).map((b) => b.value)])));
      } else if (when) setDraft(ev, when.dataset.when, isoWhen(when.value));
      else if (file) {
        // Вложение — в самом прохождении, как в демо-runner DSL (dataBase64)
        const read = (f) =>
          new Promise((done) => {
            const r = new FileReader();
            r.onload = () => done(String(r.result).replace(/^data:[^,]*,/, ""));
            r.readAsDataURL(f);
          });
        const at = new Date().toISOString();
        const atts = await Promise.all(
          [...file.files].slice(0, 1).map(async (f, n) => ({
            id: `att-${Date.now()}-${n}`,
            stepId: file.dataset.file,
            source: "operator",
            mime: f.type || "application/octet-stream",
            fileName: f.name,
            size: f.size,
            capturedAt: at,
            dataBase64: await read(f),
          }))
        );
        if (!atts.length) return;
        setDraft(ev, file.dataset.file, atts[0].id, atts);
      } else return;
      renderScenario();
    });
    $("scenarioRoot").addEventListener("keydown", (e) => {
      if (moreKey(e)) return;
      if (e.key !== "Enter" && e.key !== " ") return;
      const crumb = e.target.closest("[data-crumb]");
      if (!crumb) return;
      e.preventDefault();
      e.stopPropagation();
      crumb.click();
    });
    // «+N инцидентов» в заголовке карточки — на вкладку привязанных
    $("workTitle").addEventListener("click", (e) => {
      const tabBtn = e.target.closest("[data-work-tab]");
      if (!tabBtn || !selected()) return;
      state.workTab = tabBtn.dataset.workTab;
      renderScenario();
    });
    $("scenarioRoot").addEventListener("click", async (e) => {
      if (e.target.closest("#backToQueue")) return backToQueue();
      const ev = selected();
      if (!ev) return;
      if (e.target.closest("#moreActs")) {
        setMore(state.moreOpen !== ev.guid);
        return;
      }
      if (state.moreOpen && e.target.closest("#moreMenu [data-do]")) setMore(false);
      if (e.target.closest("[data-log-toggle]")) {
        state.logOpen = state.logOpen === ev.guid ? null : ev.guid;
        renderScenario();
        return;
      }
      const tabBtn = e.target.closest("[data-work-tab]");
      if (tabBtn) {
        state.workTab = tabBtn.dataset.workTab;
        renderScenario();
        return;
      }
      const lnkPage = e.target.closest("[data-lnk-page]");
      if (lnkPage) {
        state.linkedPage = Number(lnkPage.dataset.lnkPage);
        await loadLinked();
        renderAll();
        return;
      }
      const detachAll = e.target.closest("[data-detach-all]");
      if (detachAll && explainIfOff(detachAll)) return;
      if (detachAll) {
        try {
          const after = await api.del(`/operator/incidents/${enc(ev.guid)}/linked`);
          toast(t("Отсоединено: {n} — теперь «{state}»", { n: ev.linkedCount - after.linkedCount, state: detachedLabel() }));
        } catch (err) {
          toast(problemText(err), "error");
        }
        await reload();
        return;
      }
      const detach = e.target.closest("[data-detach]");
      if (detach && explainIfOff(detach)) return;
      if (detach) {
        try {
          await api.del(`/operator/incidents/${enc(ev.guid)}/linked/${enc(detach.dataset.detach)}`);
          toast(t("{id} отсоединён — теперь «{state}»", { id: detach.dataset.number, state: detachedLabel() }));
        } catch (err) {
          toast(problemText(err), "error");
        }
        await reload();
        return;
      }
      const sibling = e.target.closest("[data-sibling]");
      if (sibling) {
        openSibling(sibling.dataset.sibling, sibling.dataset.number);
        return;
      }
      const act = e.target.closest("[data-do]");
      if (act && explainIfOff(act)) return;
      if (act) {
        trigger(act.dataset.do, ev, "card");
        return;
      }
      const crumb = e.target.closest("[data-crumb]");
      if (crumb) {
        if (crumb.dataset.crumb === "summary") openSummary(ev);
        else goToStep(ev, Number(crumb.dataset.crumb));
        return;
      }
      if (e.target.closest("[data-finish]")) {
        finishIncident(ev);
        return;
      }
      if (e.target.closest("#stepBack")) {
        if (explainIfOff(e.target.closest("#stepBack"))) return;
        // С «Итога» — на последний шаг сценария, курсор не двигается
        if (atSummary(ev)) {
          state.summaryOff.add(ev.guid);
          renderScenario();
          renderStatus();
        } else goToStep(ev, cursorOf(ev) - 1);
        return;
      }
      if (e.target.closest("#stepNext")) {
        if (explainIfOff(e.target.closest("#stepNext"))) return;
        goNextStep(ev);
        return;
      }
      // Одна отметка — кнопкой: в черновик, ответ уходит по «Далее»
      const confirm = e.target.closest("[data-confirm]");
      if (confirm && !ev.readOnly) {
        const step = stepOf(ev, confirm.dataset.confirm);
        const on = (valueOf(ev, step) || []).includes(step.view.options[0].id);
        setDraft(ev, step.id, on ? [] : [step.view.options[0].id]);
        renderScenario();
        return;
      }
      // Кнопка шага — сама ответ: нажатие уходит сразу
      const press = e.target.closest("[data-press]");
      if (press && !ev.readOnly) {
        submitStep(ev, stepOf(ev, press.dataset.press));
        return;
      }
      // Снимок с камеры или карты — в прототипе заглушка: вложение без содержимого
      const snap = e.target.closest("[data-snap]");
      if (snap && !ev.readOnly) {
        const step = stepOf(ev, snap.dataset.snap);
        const att = { id: `att-${Date.now()}`, stepId: step.id, source: step.view.source, mime: "image/png", capturedAt: new Date().toISOString(), dataBase64: "" };
        setDraft(ev, step.id, att.id, [att]);
        renderScenario();
      }
    });
    // Меню «Выделить» в шапке очереди: все в фильтре или окно «По фильтру…» для выбранного узла дерева
    $("selectAllBtn").addEventListener("click", () => {
      closeMenus();
      selectAllVisible();
    });
    $("selectByFilterBtn").addEventListener("click", () => {
      closeMenus();
      openFilter(state.groupId || "all");
    });
    $("clearSelectionBtn").addEventListener("click", () => clearSelection());
    $("videoStage").addEventListener("click", (e) => {
      const nav = e.target.closest("[data-cam-step]");
      if (nav) stepCamera(Number(nav.dataset.camStep));
    });
    $("camStrip").addEventListener("click", (e) => {
      const cam = e.target.closest("[data-cam]");
      if (!cam) return;
      state.activeCam = cam.dataset.cam;
      renderVideo();
      renderMap();
    });
    $("mapRoot").addEventListener("click", (e) => {
      const cam = e.target.closest("[data-cam]");
      if (!cam) return;
      state.activeCam = cam.dataset.cam;
      renderVideo();
      renderMap();
    });
    $("videoMode").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-mode]");
      if (!btn) return;
      state.videoMode = btn.dataset.mode;
      [...$("videoMode").children].forEach((b) => b.classList.toggle("active", b === btn));
      renderVideo();
    });
    $("breakBtn").addEventListener("click", () => {
      closeMenus();
      toggleBreak();
    });
    $("breakReturn").addEventListener("click", () => {
      if (onBreak()) toggleBreak();
    });
    $("signOutBtn").addEventListener("click", () => {
      closeMenus();
      api
        .get("/operator/session")
        .then((session) => {
          store.session = session;
          showForm({ id: "__signout__" }, signOutForm());
        })
        .catch((err) => toast(problemText(err), "error"));
    });
    $("signInBtn").addEventListener("click", () => setPresence("ready", "Вы вошли в МИ"));
    // Меню справки — по открытому инциденту: ссылки групп его источника (§7)
    $("helpBtn").addEventListener("click", () => renderHelpLinks());
    $("adminBtn").addEventListener("click", () => {
      closeMenus();
      openAdmin();
    });
    $("adminTabs").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-admin-tab]");
      if (!btn) return;
      adminState.tab = btn.dataset.adminTab;
      renderAdmin();
    });
    // Ссылка «Посмотреть состояние» на «Хранении» и кнопка «Обновить» раздела «Состояние системы» (§20)
    const adminLinks = (e) => {
      const go = e.target.closest("[data-admin-goto]");
      if (go) {
        adminState.tab = go.dataset.adminGoto;
        renderAdmin();
      }
      if (e.target.closest("[data-admin-refresh]")) renderAdmin();
      const play = e.target.closest("[data-sound-play]");
      if (play) soundPreview(play.dataset.soundPlay);
    };
    $("adminNote").addEventListener("click", adminLinks);
    $("adminTable").addEventListener("click", adminLinks);
    // Автообновление раздела с refreshSec, пока он открыт (раз в минуту — «Состояние системы»)
    setInterval(() => {
      if ($("modalAdmin").hidden) return;
      const tab = WORKFLOW.adminSettings.tabs.find((x) => x.id === adminState.tab);
      if (tab && tab.refreshSec && Date.now() - (adminState.shownAt || 0) >= tab.refreshSec * 1000) renderAdmin();
    }, 5000);
    document.querySelectorAll(".menu").forEach((menu) => {
      const trigger = menu.querySelector("[aria-haspopup]");
      const pop = menu.querySelector(".menu-pop");
      trigger.addEventListener("click", () => {
        const willOpen = pop.hidden;
        closeMenus();
        pop.hidden = !willOpen;
        trigger.setAttribute("aria-expanded", String(willOpen));
      });
      menu.addEventListener("click", (e) => {
        const link = e.target.closest("[data-url]");
        if (link) {
          closeMenus();
          window.open(link.dataset.url, "_blank", "noopener");
          return;
        }
        const item = e.target.closest("[data-doc]");
        if (!item) return;
        e.preventDefault();
        closeMenus();
        showModal(item.dataset.doc);
      });
    });
    document.addEventListener("click", (e) => {
      if (!e.target.closest(".menu")) closeMenus();
    });
    // Меню «Ещё» закрывается щелчком мимо
    document.addEventListener("click", (e) => {
      if (state.moreOpen && e.target.isConnected && !e.target.closest(".more")) setMore(false);
    });
    // Раскрытый журнал сворачивается щелчком мимо; нажатая при этом кнопка карточки тоже срабатывает
    document.addEventListener("click", (e) => {
      if (state.logOpen && e.target.isConnected && !e.target.closest(".log")) closeLog();
    });
    document.querySelectorAll("[data-close]").forEach((btn) => {
      btn.addEventListener("click", () => {
        if (btn.dataset.close === "modalDialog") closeDialog();
        else $(btn.dataset.close).hidden = true;
      });
    });
    $("dialogConfirm").addEventListener("click", submitDialog);
    $("groupingRows").addEventListener("change", (e) => {
      const same = e.target.closest("[data-same]");
      if (same) {
        Object.assign(filt, { same: same.checked, scenario: null, open: null, q: {} });
        return loadFilter();
      }
      const box = e.target.closest("[data-fkey]");
      if (box && box.dataset.fkey === "s:scenario") {
        Object.assign(filt, { scenario: box.value, open: null, q: {}, focusSearch: false });
        return loadFilter();
      }
      if (box) {
        const [i, key] = box.dataset.fkey.split(":");
        const c = filt.filter.any[Number(i)];
        if (key === "deviceTypeId") {
          // Каскад: сменили тип — события и устройства выбираются заново
          Object.assign(c, { deviceTypeId: box.value || null, eventTypeIds: [], deviceGuids: [] });
          filt.open = null;
          filt.q = {};
        } else c[key] = box.checked ? c[key].concat(box.value) : c[key].filter((v) => v !== box.value);
        // Галочка — список остаётся открытым, набранное стирается, фокус — в поле: можно искать следующее
        filt.q = {};
        filt.focusSearch = key !== "deviceTypeId";
      } else return;
      loadFilter();
    });
    $("groupingConfirm").addEventListener("click", submitFilter);
    // Выпадающие списки фильтра: открыть один, щелчок мимо — закрыть; «Любые» — снять всё
    $("modalGrouping").addEventListener("click", (e) => {
      const toggle = e.target.closest("[data-ms-toggle]");
      const clear = e.target.closest("[data-ms-clear]");
      if (toggle) {
        if (filt.open === toggle.dataset.msToggle) return;
        filt.open = toggle.dataset.msToggle;
        filt.q = {};
        filt.focusSearch = true;
      } else if (clear) {
        const [i, key] = clear.dataset.msClear.split(":");
        filt.filter.any[Number(i)][key] = [];
        return loadFilter();
      } else if (e.target.closest("[data-cond-add]")) {
        filt.filter.any.push(blankCond());
        return loadFilter();
      } else if (e.target.closest("[data-cond-remove]")) {
        filt.filter.any.splice(Number(e.target.closest("[data-cond-remove]").dataset.condRemove), 1);
        filt.open = null;
        return loadFilter();
      } else if (!e.target.closest(".mselect") && filt.open) {
        filt.open = null;
        filt.q = {};
      }
      else return;
      renderFilter();
    });
    // Набор в поле списка — без запроса к серверу: прячет неподходящие варианты
    $("groupingRows").addEventListener("input", (e) => {
      const input = e.target.closest("[data-ms-toggle]");
      if (!input) return;
      filt.q[input.dataset.msToggle] = input.value;
      if (filt.open === input.dataset.msToggle) return comboNarrow(input);
      filt.open = input.dataset.msToggle;
      filt.focusSearch = true;
      renderFilter();
    });
    $("groupingRows").addEventListener("keydown", (e) =>
      comboKey(e, () => {
        filt.open = null;
        filt.q = {};
        renderFilter();
      })
    );
    $("selBar").addEventListener("click", (e) => {
      if (e.target.closest("[data-sel-clear]")) return clearSelection();
      const b = e.target.closest("[data-sel-do]");
      if (!b) return;
      if (b.getAttribute("aria-disabled") === "true") return toast(b.title, "error");
      selectionDo(b.dataset.selDo);
    });
    $("dialogFields").addEventListener("change", (e) => {
      const input = e.target.closest && e.target.closest("[data-files]");
      if (input) return addDialogFiles(input);
      refreshDialogFields();
    });
    // «Кому передать»: щелчок по полю открывает список, набор отбирает по подстроке, щелчок мимо — закрывает
    $("dialogFields").addEventListener("click", (e) => {
      const combo = e.target.closest("[data-target-combo]");
      const pick = e.target.closest("[data-target-pick]");
      if (pick) return pickTarget(combo.dataset.targetCombo, pick.dataset.targetPick);
      if (combo && e.target.closest("[data-target-input]") && !state.dialog.combo.open) openTargetCombo(combo.dataset.targetCombo);
    });
    $("dialogFields").addEventListener("input", (e) => {
      const typed = e.target.closest("textarea[data-field]");
      if (typed && typed.value.trim()) fieldError(typed.dataset.field, "");
      const input = e.target.closest("[data-target-input]");
      if (!input) return;
      // Набранный текст — не выбор (BUG-43): набор снимает выбор, адресат — только щелчком или Enter
      input.parentElement.querySelector("[data-field]").value = "";
      if (!state.dialog.combo.open) return openTargetCombo(input.dataset.targetInput, input.value);
      narrowTargets(input);
    });
    $("dialogFields").addEventListener("keydown", targetKey);
    // Фокус ушёл из поля (Tab, щелчок в другое поле) — список закрывается (BUG-44). Проверка — после
    // перерисовки: поле перерисовывается и возвращает себе фокус. Щелчок по варианту фокус не забирает
    $("dialogFields").addEventListener("mousedown", (e) => {
      if (e.target.closest(".target-combo .mselect-menu")) e.preventDefault();
    });
    $("dialogFields").addEventListener("focusout", () =>
      setTimeout(() => {
        const open = state.dialog && state.dialog.combo.open && $("dialogFields").querySelector("[data-target-combo].open");
        if (open && !open.contains(document.activeElement)) closeTargetCombo(open.dataset.targetCombo);
      })
    );
    $("modalDialog").addEventListener("click", (e) => {
      const open = state.dialog && state.dialog.combo.open && $("dialogFields").querySelector("[data-target-combo].open");
      // Поле перерисовывается по щелчку: щелчок по уже убранному элементу — не «мимо»
      if (open && e.target.isConnected && !e.target.closest("[data-target-combo]")) closeTargetCombo(open.dataset.targetCombo);
    });
    $("groupsCollapseAll").addEventListener("click", () => {
      if (state.openGroups.size) state.openGroups.clear();
      else store.tree.forEach((n) => state.openGroups.add(n.guid));
      renderGroups();
    });
    document.addEventListener("keydown", onKey);
  }

  /* ===== Выборка (§11): правила выборки применяет сервер (/incidents/selection) ===== */

  async function pickSelection(body, message) {
    let res;
    try {
      res = await api.post("/operator/incidents/selection", Object.assign(queueQuery(), body));
    } catch (err) {
      toast(problemText(err), "error");
      return;
    }
    if (!res.incidentGuids.length) {
      toast(t("Нет инцидентов для выборки"), "error");
      return;
    }
    selectOnly(res.incidentGuids);
    state.selectedId = res.incidentGuids[0];
    toast(message(res));
    await updateSelection();
    await reload();
  }

  function selectAllVisible() {
    return pickSelection({ mode: "all_in_filter" }, (res) =>
      res.truncated
        ? t("Выбрано {n} из {max}", { n: res.incidentGuids.length, max: LIMITS.maxBulk })
        : t("Выбрано инцидентов: {n}", { n: res.incidentGuids.length })
    );
  }

  function clearSelection() {
    dropSelection();
    renderEvents();
  }

  /* ===== Выборка и объединение (§11) =====
     Панель над очередью — действия, доступные всей выборке (их решает сервер: /incidents/selection).
     «Взять в работу» — одним инцидентом: основной выбирает сервер, остальные станут привязанными */

  function linkedChip(e) {
    if (!e.linkedCount) return "";
    const text = t("+{n, plural, one {# инцидент} few {# инцидента} other {# инцидентов}}", { n: e.linkedCount });
    return `<span class="chip linked" data-work-tab="linked" title="${te("Объединено с этим инцидентом: {n}", { n: e.linkedCount })}"><span class="material-symbols-outlined" aria-hidden="true">link</span>${escapeHtml(text)}</span>`;
  }

  /* ===== Тревога: соседи — другие службы того же события (§7, ARCH-15) =====
     Не привязка (§11): соседей не объединяют и не отсоединяют, поэтому и пометка своя, не .chip.linked */

  // «тревога INC-1847» после номера — только если номер тревоги не свой (В17): у первого инцидента события он совпадает
  function alarmTag(e) {
    if (!e.alarmNumber || e.alarmNumber === e.number) return "";
    return ` · <span class="event-alarm">${te("тревога {n}", { n: e.alarmNumber })}</span>`;
  }

  // «Событие: ещё N» — видимые незакрытые соседи (siblingCount от сервера). Подсказка — номера и бейджи соседей:
  // в строке очереди их нет, они в карточке (alarm.siblings) и подгружаются при первом наведении
  function siblingChip(e) {
    if (!e.siblingCount) return "";
    return `<span class="chip sibling" data-siblings="${escapeHtml(e.guid)}" title="${te("Тревога {alarm}: другие службы того же события — {n}", {
      alarm: e.alarmNumber,
      n: e.siblingCount,
    })}"><span class="material-symbols-outlined" aria-hidden="true">diversity_3</span>${te("событие: ещё {n}", { n: e.siblingCount })}</span>`;
  }
  const doneState = (id) => Boolean(STATES[id]) && STATES[id].category === "done";
  const siblingLine = (s) => `${s.number} — ${scenarioTitle(s)} · ${badgeView(s).text}`;
  async function siblingTip(chip) {
    if (chip.dataset.tip) return;
    chip.dataset.tip = "1";
    const card = await api.get(incPath(chip.dataset.siblings)).catch(() => null);
    if (!card || !card.alarm || !chip.isConnected) return;
    const open = card.alarm.siblings.filter((s) => !doneState(s.state));
    chip.title = [t("Тревога {alarm}", { alarm: card.alarm.number })].concat(open.map(siblingLine)).join("\n");
  }

  // Блок «По этому событию» над шагами (В15): статус тревоги и соседи строками — номер, служба, бейдж, владелец,
  // результат. Кнопок действий нет: номер — «Посмотреть», карточка соседа на просмотр. Соседей нет — блока нет
  // Окна плановых работ, пересекающиеся с инцидентом (§14.12, ТЗ-21): идут работы — оператор закрывает «Плановой проверкой»
  // Название устройства и группы окна — по дереву групп очереди (store.tree); не нашлось — id
  function treeName(id, device) {
    let found = null;
    const walk = (nodes) =>
      (nodes || []).forEach((n) => {
        if (found) return;
        if (!device && (n.guid || n.id) === id) found = n.name;
        if (device) (n.devices || []).forEach((d) => (!found && (d.guid || d.id || d) === id ? (found = d.name || null) : null));
        walk(n.children);
      });
    walk(store.tree);
    return found || id;
  }
  const deviceName = (id) => treeName(id, true);
  const groupName = (id) => treeName(id, false);
  function maintenanceBlock(ev) {
    const ws = ev.maintenanceWindows || [];
    if (!ws.length && !ev.maintenanceWindowId) return "";
    const rows = ws.map((w) => `<li class="alarm-sib"><span class="alarm-what">${asData(w.description || "—")}</span><span class="alarm-who">${escapeHtml(fmtWhen(w.startsAt))} – ${escapeHtml(fmtWhen(w.endsAt))}</span></li>`).join("");
    return `<section class="alarm-block" id="maintenanceBlock" aria-label="${te("Плановые работы")}">
      <div class="alarm-head"><span class="material-symbols-outlined" aria-hidden="true">engineering</span><strong>${te("Плановые работы")}</strong><span>${te(
        ev.maintenanceWindowId ? "Инцидент создан в окне работ" : "Устройство в окне работ на время события"
      )}</span></div>
      <ul class="alarm-sibs">${rows}</ul>
    </section>`;
  }
  function alarmBlock(ev) {
    const a = ev.alarm;
    if (!a || !a.siblings.length) return "";
    const status = a.status === "open" ? t("открыта") : a.allFalseAlarm ? t("ложная") : t("закрыта");
    const view = navDef("view");
    const rows = a.siblings
      .map((s) => {
        const b = badgeView(s);
        const who = s.owner && actorName(s.owner) !== b.text ? `<span class="alarm-who">${escapeHtml(actorName(s.owner))}</span>` : "";
        const result = s.closeResultLabel ? `<span class="alarm-who">${escapeHtml(t(s.closeResultLabel))}</span>` : "";
        return `<li class="alarm-sib">
          <span class="alarm-what"><button type="button" class="alarm-num" data-sibling="${escapeHtml(s.guid)}" data-number="${escapeHtml(s.number)}" title="${escapeHtml(
          lbl(view)
        )}">${escapeHtml(s.number)}</button> — ${escapeHtml(scenarioTitle(s))}</span>
          <span class="badge ${b.cls}">${escapeHtml(b.text)}</span>${who}${result}
        </li>`;
      })
      .join("");
    return `<section class="alarm-block" id="alarmBlock" aria-label="${te("По этому событию")}">
      <div class="alarm-head"><span class="material-symbols-outlined" aria-hidden="true">diversity_3</span><strong>${te("По этому событию")}</strong><span>${te(
        "Тревога {alarm} · {status}",
        { alarm: a.number, status }
      )}</span></div>
      <ul class="alarm-sibs">${rows}</ul>
    </section>`;
  }

  // Номер соседа — «Посмотреть» (§6.3, §7): то же действие машины, что значок в очереди, по строке соседа из очереди.
  // Привязанного к другому инциденту в списках нет — он открывается в карточке своего основного (§11.4)
  async function openSibling(guid, number) {
    const page = await api.get("/operator/incidents", { filter: "all", search: number, pageSize: 100 }).catch(() => null);
    const row = page && page.items.find((x) => x.guid === guid);
    if (!row) {
      toast(t("{id} сейчас не открыть на просмотр", { id: number }), "error");
      return;
    }
    await openCard("view", row);
  }

  // Вкладки над сценарием: привязанных много — им своё место, а не блок над шагами
  function workTabs(ev, tab) {
    if (!ev.linkedCount) return "";
    const b = (id, label) =>
      `<button type="button" class="work-tab ${tab === id ? "on" : ""}" role="tab" aria-selected="${tab === id}" data-work-tab="${id}">${label}</button>`;
    return `<div class="work-tabs" role="tablist">${b("scenario", te("Сценарий"))}${b(
      "linked",
      `${te("Привязанные инциденты")} <span class="work-tab-n">${ev.linkedCount}</span>`
    )}</div>`;
  }

  // Привязанные инциденты основного (§11): постранично, «Отсоединить» у каждого и «Отсоединить все»
  function linkedPanel(ev) {
    const page = store.linked && store.linked.guid === ev.guid ? store.linked : null;
    const list = page ? page.items : [];
    if (!list.length) return `<div class="empty">${te("Привязанных инцидентов нет")}</div>`;
    const total = page.total;
    // «Отсоединить все» — тот же переход ко всем разом; доступность и причина — как у первого привязанного
    const first = list.map((m) => (m.actions || []).find((a) => a.id === "detach")).find(Boolean);
    const all =
      first && total > 1
        ? `<button type="button" class="btn outline small" data-detach-all ${first.enabled ? "" : `aria-disabled="true" title="${escapeHtml(actionWhy(first) || "")}"`}>${te(
            "Отсоединить все"
          )}</button>`
        : "";
    const start = (state.linkedPage - 1) * LINKED_PAGE;
    const step = (to, icon, label, off) =>
      `<button type="button" class="pager-btn" data-lnk-page="${to}" title="${label}" aria-label="${label}" ${off ? "disabled" : ""}><span class="material-symbols-outlined">${icon}</span></button>`;
    const pager =
      total > LINKED_PAGE
        ? `<span class="lnk-pager"><span class="pager-info">${te("{a}–{b} из {n}", { a: start + 1, b: start + list.length, n: total })}</span>${step(
            state.linkedPage - 1,
            "chevron_left",
            t("Предыдущая страница"),
            state.linkedPage === 1
          )}${step(state.linkedPage + 1, "chevron_right", t("Следующая страница"), start + list.length >= total)}</span>`
        : "";
    return `<div class="lnk-head"><span>${te("Привязано: {n}", { n: total })}</span>${pager}${all}</div>
      <div class="lnk-members">${list
        .map((m) => {
          const b = badgeView(m);
          const d = (m.actions || []).find((a) => a.id === "detach");
          const off = d && !d.enabled ? `aria-disabled="true" title="${escapeHtml(actionWhy(d) || "")}"` : `title="${escapeHtml(d ? lbl(transitionDef(d.id)) : "")}"`;
          const found = foundLinked(ev.guid).some((x) => x.guid === m.guid);
          return `<div class="lnk-member ${found ? "found" : ""}">
            <span class="lnk-num">${escapeHtml(m.number)}</span>
            <span class="lnk-where">${te(m.eventType.name)} · ${escapeHtml(sourceName(m))}</span>
            <time>${fmtTime(m.occurredAt)}</time>
            <span class="badge ${b.cls}">${escapeHtml(b.text)}</span>
            ${d ? `<button type="button" class="btn ghost small" data-detach="${escapeHtml(m.guid)}" data-number="${escapeHtml(m.number)}" ${off}>${escapeHtml(lbl(transitionDef(d.id)))}</button>` : "<span></span>"}
          </div>`;
        })
        .join("")}</div>`;
  }

  // Действия выборки — переходы машины с bulk.allowed; недоступное — бледное с причиной
  function renderSelectionBar() {
    const bar = $("selBar");
    const n = state.checked.size;
    bar.hidden = !n;
    if (!n) {
      bar.innerHTML = "";
      return;
    }
    // Что относится к отмеченным — по серверу (visible); недоступное кому-то — бледное, причина в подсказке и по клику
    const acts = ((store.selection && store.selection.actions) || []).filter((a) => a.kind === "transition" && a.bulkAllowed && a.visible);
    bar.innerHTML =
      `<span class="sel-count">${te("Отмечено: {n}", { n })}</span>` +
      acts
        .map(
          (a) =>
            `<button type="button" class="btn ${escapeHtml(a.style)} small" data-sel-do="${escapeHtml(a.id)}" ${
              a.enabled ? "" : 'aria-disabled="true"'
            } title="${escapeHtml(a.enabled ? actionLabel(a) : a.reason || actionLabel(a))}">${escapeHtml(actionLabel(a))}</button>`
        )
        .join("") +
      `<button type="button" class="btn ghost small sel-clear" data-sel-clear title="${te("Снять выделение")}">${te("Снять")}</button>`;
  }

  async function selectionDo(id) {
    if ((transitionDef(id).bulk || {}).mode === "merge") return takeAsOne();
    // Действие над всеми отмеченными: форма — одна на всех, её варианты — те, что подходят всей выборке, от сервера
    // (действие выборки, ARCH-08 в14); отмеченного может не быть на странице (BUG-78). Одно отмеченное — переход
    // одиночный: нет на странице — карточка с сервера для формы, а сверяется то, что оператор видел на момент отметки
    // (снимок выборки, §14.1, RULE-142), — изменённое после отметки сервер не тронет
    const first = [...state.checked][0];
    const act = ((store.selection && store.selection.actions) || []).find((a) => a.id === id) || null;
    const row =
      [...store.page.items, ...store.block.items].find((e) => state.checked.has(e.guid)) ||
      (state.checked.size === 1 ? await api.get(`/operator/incidents/${enc(first)}`) : { guid: first });
    const mark = state.checked.size === 1 && checkedSeen.get(first);
    const ev = Object.assign({}, row, { actions: act ? [act] : [] }, mark ? { seenAtMark: mark } : {});
    trigger(id, ev, "queue", [...state.checked]);
  }

  // «Взять в работу» на выборке — как одно: основного выбирает сервер, остальные — его привязанные
  async function takeAsOne() {
    const n = state.checked.size;
    let res;
    try {
      res = await api.post("/operator/incidents/merge", { incidentGuids: [...state.checked], expected: expectedOf([...state.checked]), idempotencyKey: newKey() });
    } catch (err) {
      toast(problemText(err), "error");
      // Изменились после отметки: причину оператор увидел, повтор — по нынешнему снимку (BUG-106)
      if (err && err.problem && err.problem.code === "INCIDENT_CHANGED") {
        checkedSeen.clear();
        await updateSelection();
      }
      return;
    }
    toast(n > 1 ? t("Взято в работу как одно: {id} и ещё {n}", { id: res.incident.number, n: n - 1 }) : t("Взято в работу: {id}", { id: res.incident.number }));
    // Куда дальше — из машины (ui.navigate объединения): карточка основного на его текущем шаге сценария
    const merge = WORKFLOW.transitions.find((x) => (x.bulk || {}).mode === "merge");
    state.selectedId = res.incident.guid;
    dropSelection();
    state.jump = true;
    navigate(merge.ui.navigate);
    await reload();
  }

  /* ===== «Выделить по фильтру» из дерева (§11) =====
     Узел (или все события) и условия через «ИЛИ»: тип устройства, события, устройства; пустое —
     любые. Варианты и сколько подходит считает сервер (POST /incidents/filter) */

  // Кнопка у узла дерева и у «Все события»
  function filterButtons(guid) {
    const b = (mode, icon, title) =>
      `<button type="button" class="node-group-btn" data-filter="${mode}" data-node="${escapeHtml(guid)}" title="${te(title)}" aria-label="${te(
        title
      )}"><span class="material-symbols-outlined">${icon}</span></button>`;
    return b("select", "checklist", "Выделить по фильтру");
  }

  // Условие фильтра: тип устройства (один или любой), события, устройства; условия — через «ИЛИ»
  const blankCond = () => ({ deviceTypeId: null, eventTypeIds: [], deviceGuids: [] });
  // open — какой выпадающий список раскрыт («номер условия:поле»); q — строка поиска в каждом
  const filt = { node: null, filter: { any: [] }, view: null, open: null, q: {} };

  async function openFilter(guid) {
    const node = guid === "all" ? null : findNode(store.tree, guid);
    Object.assign(filt, { node, filter: { any: [blankCond()] }, view: null, open: null, q: {}, same: false, scenario: null });
    $("modalGrouping").hidden = false;
    await loadFilter();
  }

  const filterNodeName = () => (filt.node ? t(filt.node.name) : t("Все устройства"));

  async function loadFilter() {
    try {
      filt.view = await api.post("/operator/incidents/filter", {
        sourceGroupGuid: filt.node ? filt.node.guid : null,
        filter: filt.filter,
        // Как над очередью: фильтр «Открытые / Мои / …» — тот же
        queueFilter: state.filter,
        // «Одинаковый сценарий» — необязательно; какой — выбранный, иначе сервер берёт самый частый
        sameScenario: filt.same,
        scenarioGuid: filt.same ? filt.scenario : null,
      });
    } catch (err) {
      $("modalGrouping").hidden = true;
      toast(problemText(err), "error");
      return;
    }
    filt.scenario = filt.view.scenarioGuid;
    renderFilter();
  }

  // Список фильтра — выпадающий: закрытый показывает выбранное, открытый — варианты с числами.
  // single — один вариант или «Любой» (тип устройства), иначе галочки
  function filterSelect(i, key, title, options, picked, single, noAny) {
    const id = `${i}:${key}`;
    const label = (v) => {
      const o = options.find((x) => x.id === v);
      return o ? t(o.label) : v;
    };
    const any = single ? t("Любой") : t("Любые");
    const open = filt.open === id;
    const q = filt.q[id] || "";
    const opt = (o) => {
      // «Любой» (id пустой) отмечен, когда ничего не выбрано
      const on = o.id === "" ? !picked.length : picked.includes(o.id);
      const hide = comboHit(t(o.label), q) ? "" : "hidden";
      const input = single
        ? `<input type="radio" name="f${escapeHtml(id)}" data-fkey="${id}" value="${escapeHtml(o.id)}" ${on ? "checked" : ""} />`
        : `<input type="checkbox" data-fkey="${id}" value="${escapeHtml(o.id)}" ${on ? "checked" : ""} />`;
      // Ноль — выбрать нечего: вариант бледный и не нажимается (выбранный раньше — снять можно)
      const none = o.count === 0 && !on;
      return `<label class="mselect-opt ${none ? "off" : ""}" ${hide}>${none ? input.replace(" />", " disabled />") : input}<span>${te(o.label)}</span><em>${o.count}</em></label>`;
    };
    const menu = open
      ? `<div class="mselect-menu">${single && !noAny ? opt({ id: "", label: "Любой", count: "" }) : ""}${options.map(opt).join("")}${comboNone(
          options.some((o) => comboHit(t(o.label), q))
        )}${!single && picked.length ? `<button type="button" class="btn ghost small" data-ms-clear="${id}">${te("Любые")}</button>` : ""}</div>`
      : "";
    return `<div class="filter-row">
      <span class="filter-title">${escapeHtml(title)}</span>
      <div class="mselect ${open ? "open" : ""}">
        ${comboField("data-ms-toggle", id, open, q, picked, label, any)}
        ${menu}
      </div>
    </div>`;
  }

  function filterConditions() {
    const conds = filt.filter.any;
    return (
      conds
        .map((c, i) => {
          const o = filt.view.options.conditions[i] || { deviceTypes: [], eventTypes: [], devices: [] };
          return `<div class="filter-cond">
            <div class="filter-cond-head"><b>${te("Условие {n}", { n: i + 1 })}</b>${
              conds.length > 1
                ? `<button type="button" class="btn ghost small" data-cond-remove="${i}"><span class="material-symbols-outlined">close</span>${te("Убрать")}</button>`
                : ""
            }</div>
            ${filterSelect(i, "deviceTypeId", t("Тип устройства"), o.deviceTypes, c.deviceTypeId ? [c.deviceTypeId] : [], true)}
            ${filterSelect(i, "eventTypeIds", t("Тип события"), o.eventTypes, c.eventTypeIds)}
            ${filterSelect(i, "deviceGuids", t("Устройства"), o.devices, c.deviceGuids)}
          </div>`;
        })
        .join(`<div class="filter-or">${te("ИЛИ")}</div>`) +
      `<button type="button" class="btn ghost small filter-add" data-cond-add><span class="material-symbols-outlined">add</span>${te("ИЛИ")}</button>`
    );
  }

  // «Одинаковый сценарий» — необязательно: только события одного сценария, тогда «Взять в работу»
  // на выделенных доступна. Сценарии — подходящих под условия, с числами
  function sameScenarioRow() {
    const v = filt.view;
    const box = `<label class="filter-same"><input type="checkbox" data-same ${filt.same ? "checked" : ""} /><span>${te("Одинаковый сценарий")}</span></label>`;
    if (!filt.same) return box;
    return box + filterSelect("s", "scenario", t("Сценарий"), v.options.scenarios, v.scenarioGuid ? [v.scenarioGuid] : [], true, true);
  }

  function renderFilter() {
    const v = filt.view;
    // Откуда берутся события: узел дерева и фильтр очереди — тот же, что над очередью
    $("groupingIntro").textContent = t("«{name}», «{filter}»: подходящие инциденты со всех страниц будут отмечены. Дальше — действие на панели выборки.", {
      name: filterNodeName(),
      filter: lbl(WORKFLOW.queueFilters.find((f) => f.id === state.filter)),
    });

    $("groupingBy").innerHTML = "";
    // «Одинаковый сценарий» — первым, над условиями
    $("groupingRows").innerHTML = sameScenarioRow() + filterConditions();
    // Раскрытый список — целиком в видимой части окна
    const opened = $("groupingRows").querySelector(".mselect.open");
    if (opened) opened.scrollIntoView({ block: "nearest" });
    if (filt.open && filt.focusSearch) comboFocus($("groupingRows").querySelector(`[data-ms-toggle="${filt.open}"]`));
    const hint = $("groupingHint");
    const confirm = $("groupingConfirm");
    hint.classList.toggle("warn", !v.count);
    hint.textContent = v.truncated
      ? t("Подходит: {n}. Будут отмечены первые {max} — предел выборки", { n: v.count, max: LIMITS.maxBulk })
      : v.excluded
        ? t("Подходит: {n} · не включены — их нельзя взять в работу: {x}", { n: v.count, x: v.excluded })
        : t("Подходит: {n}", { n: v.count });
    confirm.textContent = t("Выделить {n}", { n: v.incidentGuids.length });
    confirm.disabled = !v.count;
  }

  async function submitFilter() {
    // «Выделить»: подходящие отмечены — дальше панель выборки. Очередь — на узел окна, без типов и поиска:
    // на экране тот список, где отмечено (§11.1)
    $("modalGrouping").hidden = true;
    Object.assign(state, { groupId: filt.node ? filt.node.guid : "all", deviceTypes: [], eventTypes: [], scenarios: [], search: "", page: 1 });
    $("eventSearch").value = "";
    renderTypeLists();
    renderGroups();
    selectOnly(filt.view.incidentGuids);
    await updateSelection();
    toast(t("Выделено: {n}", { n: state.checked.size }));
    await reload();
  }

  // Горячих клавиш нет. Esc — обычное поведение окон: закрывает то, что сверху, по одному за нажатие —
  // меню, форму или окно, развёрнутые видео или карту, панель групп поверх узкого экрана, раскрытый журнал, а если
  // ничего не открыто — карточку, как «К очереди» (§13, RULE-87, RULE-91)
  function onKey(e) {
    if (e.key !== "Escape") return;
    // Список ошибок под плашкой итога (§22.6) — первым: он поверх всего
    if (!$("toastList").hidden) return toggleToastList(null);
    const openMenu = closeMenus();
    if (openMenu) return openMenu.querySelector("[aria-haspopup]").focus();
    if (state.dialog) return closeDialog();
    const openModal = document.querySelector(".modal:not([hidden])");
    if (openModal) return (openModal.hidden = true);
    if (state.full) {
      const btn = $(state.full === "video" ? "videoFull" : "mapFull");
      toggleFull(state.full);
      return btn.focus();
    }
    if (state.groupsOn && narrowQuery.matches) return closeDrawer();
    if (state.mode !== "work") return;
    if (state.logOpen) return closeLog();
    // Набранный в поле сценария ответ сохраняется при уходе из поля — как при нажатии «К очереди»
    if (document.activeElement && document.activeElement !== document.body) document.activeElement.blur();
    backToQueue();
  }

  /* ===== Меню справки (§7, RULE-49): справочник ссылок — общие и групп источника открытого инцидента ===== */

  // Демо-адреса набора открывают окна прототипа; настоящие — новой вкладкой
  const DEMO_DOCS = { regulation: "modalRegulation", contacts: "modalContacts", evacuation: "modalEvacuation", emergency: "modalEmergency" };
  async function renderHelpLinks() {
    const ev = selected();
    const links = await api.get("/operator/reference/help-links", ev ? { incidentGuid: ev.guid } : {}).catch(() => []);
    const item = (l) => {
      const demo = /^demo:doc\/(.+)$/.exec(l.url);
      const target = demo ? `data-doc="${DEMO_DOCS[demo[1]] || ""}"` : `data-url="${escapeHtml(l.url)}"`;
      return `<button type="button" class="menu-item" role="menuitem" ${target}>
        <span class="material-symbols-outlined">${escapeHtml(l.icon || (l.kind === "file" ? "description" : "public"))}</span>
        <span data-i18n-skip>${escapeHtml(l.title)}</span>
      </button>`;
    };
    // Без инцидента ответ администратору — весь справочник (для вкладки настроек): в меню — только общие.
    // Ссылки групп — разделом на группу, подпись — название группы; «не назначена» в меню не бывает
    const common = links.filter((l) => l.scope === "shared");
    const byGroup = new Map();
    (ev ? links.filter((l) => l.scope === "group") : []).forEach((l) => byGroup.set(l.groupGuid, (byGroup.get(l.groupGuid) || []).concat(l)));
    $("helpLinks").innerHTML =
      common.map(item).join("") +
      [...byGroup.values()]
        .map((list) => `<div class="menu-sep"></div><div class="menu-label" data-i18n-skip>${escapeHtml(list[0].groupName || "")}</div>${list.map(item).join("")}`)
        .join("");
  }

  /* ===== Звук (§21, план 87б) =====
     Звучать или нет — функция sound.js (IMSound.decideSound и др.) от события потока, раздела sound схемы, состояния
     оператора и «Только важного»; здесь только вызовы, вывод и шапка. Рецепты и вывод — sound-synth.js (IMSound.output).
     Повтор планируется на часах вывода вперёд (planRepeats, 120 с) и дополняется таймером раз в 5 с: свёрнутая вкладка
     с таймером раз в минуту не замолкает. В прототипе звучит каждая вкладка, без выбора ведущей (отступление §17). */
  const ONLY_IMPORTANT_KEY = "im-sound-only-important";
  const snd = {
    state: { sounding: [], attention: [] },
    // Расписание повтора верхнего: key — кто и с какого раза, anchor — от какого момента часов вывода, last — последний
    // запланированный момент, planned — { at, handle } на выводе out
    plan: null,
    volume: IMSound.loadVolume(),
    onlyUntil: null,
    agent: null,
  };
  try {
    const until = Number(localStorage.getItem(ONLY_IMPORTANT_KEY));
    snd.onlyUntil = until > Date.now() ? until : null;
  } catch (e) {
    snd.onlyUntil = null;
  }
  const soundOn = () => Boolean(WORKFLOW && WORKFLOW.sound && store.session);
  const soundOut = () => IMSound.output;
  const onlyImportant = () => snd.onlyUntil != null && Date.now() < snd.onlyUntil;
  const soundVolume = () => IMSound.effectiveVolume(snd.volume, WORKFLOW.sound.volumeFloor);
  const soundCtx = () => ({
    settings: WORKFLOW.sound,
    agentState: store.session.agentState,
    meGuid: store.session.operator.guid,
    onlyImportantUntil: snd.onlyUntil,
    now: Date.now(),
  });
  // Один звук сейчас — поверх повтора; до разблокировки не играет ничего: накопленное залпом не звучит (§21.5)
  function soundPlayNow(pattern) {
    const out = soundOut();
    if (out.ready()) out.play(pattern, out.now(), soundVolume());
  }
  function soundStopPlan() {
    if (snd.plan) snd.plan.planned.forEach((p) => snd.plan.out.stop(p.handle));
    snd.plan = null;
  }
  // Повтор только у верхнего (§21.2): сменился верхний — прежнее расписание снимается, новое — через шаг от сейчас
  function soundSchedule() {
    const out = soundOut();
    const top = soundOn() ? IMSound.topSounding(snd.state) : null;
    if (!top || !out.ready()) return soundStopPlan();
    const now = out.now();
    const key = `${top.guid}|${top.kind}|${top.since}|${top.cue.pattern}|${top.cue.repeatSec}`;
    if (!snd.plan || snd.plan.key !== key || snd.plan.out !== out) {
      soundStopPlan();
      snd.plan = { key, out, anchor: now, last: now, planned: [] };
    }
    const plan = snd.plan;
    plan.planned = plan.planned.filter((p) => p.at > now - 5);
    // Дополнить от последнего запланированного до «сейчас + 120 с»; шаг длиннее запаса — один момент вперёд
    if (plan.last - now >= 120) return;
    for (const at of IMSound.planRepeats(top, plan.last, now + 120 - plan.last)) {
      plan.planned.push({ at, handle: out.play(top.cue.pattern, at, soundVolume()) });
      plan.last = at;
    }
  }
  // Громкость сменилась: запланированное вперёд — заново с новой громкостью, ритм повтора тот же
  function soundReplan() {
    if (!snd.plan) return;
    const { key, out, anchor } = snd.plan;
    const top = IMSound.topSounding(snd.state);
    const step = top && top.cue.repeatSec > 0 ? top.cue.repeatSec : 0;
    // Последний прозвучавший момент того же ритма: следующий — через шаг от него, как и без смены громкости
    const last = step ? anchor + Math.floor((out.now() - anchor) / step) * step : out.now();
    soundStopPlan();
    snd.plan = { key, out, anchor, last, planned: [] };
    soundSchedule();
  }
  function soundUpdate() {
    soundSchedule();
    renderSound();
  }

  // Событие потока — до выхода по «своему» переходу: моё действие снимает звук (§21.2, «Снимает и моё действие»)
  function soundOnEvent(msg) {
    if (!soundOn() || msg.type === "stream.reset") return;
    // Идёт перечитывание очереди: событие может быть новее прочитанного — после restoreSound применить его ещё раз
    if (snd.pending) snd.pending.push(msg);
    const r = IMSound.decideSound(snd.state, msg, soundCtx());
    snd.state = r.state;
    if (r.play) {
      soundPlayNow(r.play.cue.pattern);
      soundNotify(msg.incident);
    }
    soundUpdate();
  }

  // Перечитанная очередь (§21.1): загрузка, переподключение, сброс потока, возврат в «Готов». keep — только
  // пересчитать звучащее (новая схема или справочник): заглушённое «Тихо» не возобновляется
  let soundRestoring = 0;
  async function soundRestore(keep) {
    if (!soundOn()) return;
    const run = ++soundRestoring;
    snd.pending = [];
    const queue = [];
    try {
      for (let page = 1; page <= 50; page++) {
        const res = await api.get("/operator/incidents", { filter: "open", page, pageSize: 200 });
        queue.push(...res.items);
        if (!res.items.length || page * 200 >= res.total) break;
      }
    } catch (err) {
      if (run === soundRestoring) snd.pending = null;
      return;
    }
    if (run !== soundRestoring || !soundOn()) return;
    noteIncidents(queue);
    let next = IMSound.restoreSound(queue, soundCtx());
    // События, пришедшие за время чтения, — поверх прочитанного, без звука: их звук уже сыграл на приходе.
    // Иначе взятый за это время инцидент вернулся бы в повтор из устаревшей очереди
    for (const msg of snd.pending) next = IMSound.decideSound(next, msg, soundCtx()).state;
    snd.pending = null;
    if (keep) {
      const was = new Set(snd.state.sounding.map((s) => s.guid));
      next.sounding = next.sounding.filter((s) => was.has(s.guid));
    }
    snd.state = next;
    soundUpdate();
  }

  // Состояние оператора сменилось (§21.3): вернулся в «Готов» — по перечитанной очереди, иначе — что он ещё слышит
  function soundSession() {
    if (!soundOn()) return;
    const now = store.session.agentState;
    const prev = snd.agent;
    snd.agent = now;
    if (!prev || prev === now) return;
    if (now === "ready") soundRestore();
    else {
      snd.state = IMSound.applyCtx(snd.state, soundCtx());
      soundSchedule();
    }
  }

  // Уведомление браузера, когда вкладка не видна (§21.6): «Пожарная тревога — Склад-2, Критический»; щелчок — к инциденту
  function soundNotify(inc) {
    if (!inc || !document.hidden || !("Notification" in window) || Notification.permission !== "granted") return;
    const pri = PRIORITIES[inc.priority];
    const where = inc.sourceGroup ? inc.sourceGroup.name : "";
    const what = [inc.eventType && inc.eventType.name, where].filter(Boolean).join(" — ");
    try {
      const note = new Notification(pri ? `${what}, ${inLang(pri.name)}` : what, { body: inc.number, tag: inc.guid });
      note.onclick = () => {
        window.focus();
        soundGo(inc.guid, inc.number);
        note.close();
      };
    } catch (e) {
      /* браузер не дал показать — звук всё равно звучит */
    }
  }

  // К строке звучащего (§21.4): в очереди — выделить и прокрутить; не на этой странице — открыть её страницу
  function soundGo(guid, number) {
    if (state.mode !== "queue") return toast(t("{id} ждёт в очереди", { id: number }));
    const rowOf = () => $("eventsList").querySelector(`[data-id="${CSS.escape(guid)}"]`);
    // Строку спрятал фильтр — тот же переход, что прежнее «Показать» (§22.3)
    if (!rowOf() && hiddenNow(guid)) return void showHidden(guid);
    state.selectedId = guid;
    if (rowOf()) {
      renderAll();
      rowOf().scrollIntoView({ block: "nearest" });
      return;
    }
    state.jump = true;
    reload().then(() => {
      if (!rowOf()) toast(t("{id} скрыт фильтром очереди", { id: number }));
    });
  }

  // Значок вкладки: обычный и «внимание» (красная точка); мигает, пока attention непуст (§21.6)
  const FAVICON = {
    calm: `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><path d="M16 2 28 9v14l-12 7L4 23V9z" fill="none" stroke="#1976d2" stroke-width="3"/></svg>')}`,
    alert: `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><path d="M16 2 28 9v14l-12 7L4 23V9z" fill="none" stroke="#1976d2" stroke-width="3"/><circle cx="23" cy="9" r="8" fill="#dc2626"/></svg>')}`,
  };
  function favicon() {
    let link = document.querySelector('link[rel="icon"]');
    if (!link) {
      link = document.createElement("link");
      link.rel = "icon";
      link.type = "image/svg+xml";
      link.href = FAVICON.calm;
      document.head.appendChild(link);
    }
    return link;
  }
  function blinkFavicon() {
    const link = favicon();
    const on = snd.state.attention.length > 0;
    link.dataset.blink = on ? "on" : "off";
    const next = on && link.dataset.state !== "alert" ? "alert" : "calm";
    if (link.dataset.state !== next) {
      link.dataset.state = next;
      link.href = FAVICON[next];
    }
  }

  // Заголовок вкладки «(N) …»: N — непринятые, которые повторяются до взятия, и «лично вам» (§21.6); «Тихо» не сбрасывает
  function syncTitle() {
    const n = snd.state.attention.length;
    document.title = (n ? `(${n}) ` : "") + t(STATIC.title);
  }

  const priorityName = (level) => (PRIORITIES[level] ? inLang(PRIORITIES[level].name) : String(level));
  function onlyUntilText() {
    const locale = (LANGS.find((l) => l.id === LANG) || LANGS[0]).locale;
    return new Date(snd.onlyUntil).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit", hour12: false });
  }

  // Шапка (§21.4): значок 🔊/🔉/🔇; пока что-то звучит — значок красный и пульсирует, рядом «Тихо», щелчок по значку — к самому
  // важному звучащему (soundGo). «Звук не включён · Включить звук» и «Только важное до … · Вернуть» — пункты строки
  // состояния поста (§21.5, §22.4)
  function soundingOf(guid) {
    return soundOn() && soundOut().ready() ? snd.state.sounding.find((s) => s.guid === guid) || null : null;
  }
  function renderSound() {
    syncTitle();
    if (!soundOn()) return;
    const ready = soundOut().ready();
    const important = onlyImportant();
    const top = ready ? IMSound.topSounding(snd.state) : null;
    const icon = !ready ? "🔇" : important && !top ? "🔉" : "🔊";
    const menuTitle = t(!ready ? "Звук не включён" : important ? "Только важное" : "Звук");
    const title = top ? `${rowSoundTip(top)} · ${t("показать в очереди")}` : menuTitle;
    $("soundIcon").textContent = icon;
    $("soundBtn").title = title;
    $("soundBtn").setAttribute("aria-label", title);
    $("soundBtn").dataset.sound = !ready ? "off" : important ? "important" : "on";
    $("soundBtn").dataset.ringing = top ? "on" : "off";
    if (top) {
      $("soundBtn").dataset.soundGo = top.guid;
      $("soundBtn").dataset.soundNumber = top.number;
    }
    $("soundQuiet").innerHTML = top ? `<button type="button" class="btn small outline" data-sound-silence>${te("Тихо")}</button>` : "";
    $("soundQuiet").hidden = !top;
    // Значок меню звука в полосе — только на телефоне, где значка в шапке нет (styles.css)
    $("soundBar").innerHTML = `<button type="button" class="icon-btn sound-bar-menu" data-sound-menu title="${escapeHtml(menuTitle)}" aria-label="${escapeHtml(menuTitle)}"><span aria-hidden="true">${!ready ? "🔇" : important ? "🔉" : "🔊"}</span></button>`;
    syncRowSound();
    if (!$("soundPop").hidden) renderSoundMenu();
    renderPost();
  }
  // Значки звучащих строк (§22.3) — без перерисовки очереди: звук меняется чаще строк
  function syncRowSound() {
    document.querySelectorAll("#eventsList [data-id]").forEach((row) => {
      const s = soundingOf(row.dataset.id);
      const mark = row.querySelector("[data-row-sound]");
      if (!s) return void (mark && mark.remove());
      const tip = rowSoundTip(s);
      if (mark) {
        mark.title = tip;
        mark.setAttribute("aria-label", tip);
        return;
      }
      const name = row.querySelector(".event-title strong, .inbox-top strong");
      if (name) name.insertAdjacentHTML("beforebegin", `<span class="row-sound" data-row-sound title="${escapeHtml(tip)}" aria-label="${escapeHtml(tip)}" role="img">🔊</span>`);
    });
  }

  // Меню звука открыть — и при звенящем значке (значок меню в полосе на телефоне): как кнопка меню, без перехода
  function openSoundMenu() {
    const pop = $("soundPop");
    const willOpen = pop.hidden;
    closeMenus();
    pop.hidden = !willOpen;
    $("soundBtn").setAttribute("aria-expanded", String(willOpen));
    if (willOpen) renderSoundMenu();
  }
  // Меню звука (§21.4): громкость не ниже порога схемы, «Проверить звук», «Только важное», разрешение уведомлений
  function renderSoundMenu() {
    const s = WORKFLOW.sound;
    const v = soundVolume();
    const notify = "Notification" in window && Notification.permission === "default";
    $("soundPop").innerHTML = `
      <div class="menu-label">${te("Звук")}</div>
      <label class="menu-field sound-volume"><span>${te("Громкость")}</span>
        <span class="sound-volume-row"><input type="range" id="soundVolume" min="${s.volumeFloor}" max="100" step="1" value="${v}" /><output id="soundVolumeOut">${v}%</output></span>
      </label>
      <button type="button" class="menu-item" role="menuitem" data-sound-test>▶ ${te("Проверить звук")}</button>
      <button type="button" class="menu-item" role="menuitem" data-sound-important>${onlyImportant() ? te("Вернуть весь звук") : te("Только важное — {n} мин", { n: s.muteMinutes })}</button>
      ${notify ? `<button type="button" class="menu-item" role="menuitem" data-sound-notify>${te("Разрешить уведомления")}</button>` : ""}
      <div class="menu-note">${te("Громкость не ниже {n}% — так настроено в схеме.", { n: s.volumeFloor })}</div>`;
  }

  // Включить звук: разблокировать вывод; с проверкой — сразу проверочный сигнал (§21.5)
  async function soundUnlock(check) {
    const out = soundOut();
    if (!out.ready()) await out.unlock();
    if (check) soundPlayNow(IMSound.TEST_PATTERN);
    soundUpdate();
  }
  // ▶ «Прослушать» в настройках: нажатие и есть разблокировка
  async function soundPreview(pattern) {
    if (!soundOut().ready()) await soundOut().unlock();
    soundPlayNow(pattern);
    renderSound();
  }
  function setOnlyImportant(on) {
    snd.onlyUntil = on ? Date.now() + WORKFLOW.sound.muteMinutes * 60000 : null;
    try {
      if (on) localStorage.setItem(ONLY_IMPORTANT_KEY, String(snd.onlyUntil));
      else localStorage.removeItem(ONLY_IMPORTANT_KEY);
    } catch (e) {
      /* хранилище недоступно — до перезагрузки */
    }
    snd.state = IMSound.applyCtx(snd.state, soundCtx());
    soundUpdate();
  }
  // Раз в 5 с: срок «Только важного» и дополнение расписания повтора
  function soundTick() {
    if (snd.onlyUntil != null && !onlyImportant()) {
      snd.onlyUntil = null;
      try {
        localStorage.removeItem(ONLY_IMPORTANT_KEY);
      } catch (e) {
        /* хранилище недоступно */
      }
      renderSound();
    }
    soundSchedule();
  }

  function bindSound() {
    // Любое нажатие на странице включает звук — без проверочного сигнала (§21.5)
    // Нажатие на кнопку, которая сама включает звук с проверкой (или ▶), — не здесь: перерисовка строки до click
    // заменила бы кнопку, и проверочный сигнал потерялся бы (§21.5)
    const firstPress = (e) => {
      if (soundOut().ready() || (e.target.closest && e.target.closest("[data-sound-enable], [data-sound-test], [data-sound-play]"))) return;
      soundUnlock(false);
    };
    document.addEventListener("pointerdown", firstPress, true);
    document.addEventListener("keydown", firstPress, true);
    // Кнопки звука — в строке «Звучит», в строке состояния поста и на вкладке «Система» колокольчика (§22.4)
    const soundClick = (e) => {
      if (e.target.closest("[data-sound-enable]")) return soundUnlock(true);
      // Значок меню в полосе звука на телефоне: то же меню, что у значка в шапке; щелчок не должен дойти до
      // «щелчок мимо меню закрывает»
      if (e.target.closest("[data-sound-menu]")) {
        e.stopPropagation();
        openSoundMenu();
        return;
      }
      if (e.target.closest("[data-sound-silence]")) {
        snd.state = IMSound.silence(snd.state);
        return soundUpdate();
      }
      if (e.target.closest("[data-sound-back]")) return setOnlyImportant(false);
    };
    $("soundBar").addEventListener("click", soundClick);
    $("soundQuiet").addEventListener("click", soundClick);
    // Звенящий значок — к самому важному звучащему, а не меню (§21.4): перехват до кнопки меню
    $("soundMenu").addEventListener(
      "click",
      (e) => {
        const btn = e.target.closest("#soundBtn");
        if (!btn || btn.dataset.ringing !== "on") return;
        e.stopPropagation();
        closeMenus();
        soundGo(btn.dataset.soundGo, btn.dataset.soundNumber);
      },
      true
    );
    $("postStatus").addEventListener("click", (e) => {
      if (e.target.closest("[data-post-open]")) return openBell("system");
      soundClick(e);
    });
    $("bellStates").addEventListener("click", soundClick);
    $("soundBtn").addEventListener("click", () => {
      if (!$("soundPop").hidden) renderSoundMenu();
    });
    $("soundPop").addEventListener("input", (e) => {
      if (e.target.id !== "soundVolume") return;
      snd.volume = IMSound.effectiveVolume(Number(e.target.value), WORKFLOW.sound.volumeFloor);
      if (Number(e.target.value) !== snd.volume) e.target.value = String(snd.volume);
      IMSound.saveVolume(snd.volume);
      $("soundVolumeOut").textContent = `${snd.volume}%`;
      soundReplan();
    });
    $("soundPop").addEventListener("click", (e) => {
      if (e.target.closest("[data-sound-test]")) return soundUnlock(true);
      if (e.target.closest("[data-sound-important]")) {
        closeMenus();
        return setOnlyImportant(!onlyImportant());
      }
      if (e.target.closest("[data-sound-notify]"))
        Promise.resolve(Notification.requestPermission())
          .catch(() => null)
          .then(() => renderSoundMenu());
    });
    setInterval(soundTick, 5000);
    // Вывод подменили (самопроверка): прежнее расписание — снять на прежнем выводе, дальше — на новом
    window.addEventListener("im-sound-output", () => {
      soundStopPlan();
      soundUpdate();
    });
    window.addEventListener("im-sound-tick", soundTick);
    // Перечитать очередь (самопроверка: событие во время перечитывания)
    window.addEventListener("im-sound-restore", () => soundRestore());
    // Значок вкладки мигает, пока есть непринятые (§21.6); таймер — для картинки, не для звука
    setInterval(blinkFavicon, 1000);
  }

  /* ===== Настройки администратора (§20, RULE-44): только просмотр ===== */

  // Вкладки и пути — из машины (adminSettings); данные МИ, которых нет в схеме, — запросами
  // из контракта. Здесь только показ: что настраивается и какое значение сейчас
  const adminState = { tab: null, data: {} };
  const settingAt = (path) =>
    path.split(".").reduce((cur, seg) => (cur == null ? cur : Array.isArray(cur) ? cur.find((x) => x && x.id === seg) : cur[seg]), WORKFLOW);
  // Число и единица — неразрывно: «90 с» не переносится посередине
  function fmtDuration(sec) {
    if (sec == null) return "—";
    const text = sec >= 3600 && sec % 3600 === 0 ? t("{n} ч", { n: sec / 3600 }) : sec >= 60 && sec % 60 === 0 ? t("{n} мин", { n: sec / 60 }) : t("{n} с", { n: sec });
    return text.replace(/ /g, "\u00a0");
  }
  // Машинное значение — подписью из машины (adminSettings.valueLabels — ключи каталога, §14.9), иначе как есть
  // Ключ — число уровня приоритета (нормативы по приоритету, §4): его название из справочника
  const word = (key) => (PRIORITIES[key] ? asData(inLang(PRIORITIES[key].name)) : te((WORKFLOW.adminSettings.valueLabels || {})[key] || key));
  // Адресат уровня и получатель оповещений (§8.3, §9) — вид и имя: «пользователь Петрова», «группа Дежурный ЦОД»;
  // название уровня бывает похоже на группу, а адресат — человек (BUG-124). Вид — targetKind; нет вида — сначала группа.
  // Люди — из «Людей поста» (все, кто заходил, и я, и давно не заходившие). Не нашёлся — «удалённый …» с id, но только
  // если его список прочитан: список не пришёл — «группа (id)», «пользователь (id)». Имя — данные, не переводится
  function personName(id) {
    if (store.session && id === store.session.operator.guid) return store.session.operator.name;
    const target = targetById(id);
    return (target && target.name) || id;
  }
  const named = (ru, name) => te(ru, { name: "\u0001" }).replace("\u0001", asData(name));
  function addressee(id, kind) {
    const groups = adminState.data.duty;
    const people = adminState.data.people;
    const group = kind === "user" ? null : (groups || []).find((g) => g.id === id);
    if (group) return named("группа {name}", group.name);
    const person = kind === "group" ? null : (people || []).find((p) => p.id === id);
    if (person) return named("пользователь {name}", person.name);
    if (kind === "user") return te(people ? "удалённый пользователь ({id})" : "пользователь ({id})", { id });
    if (!groups || !people) return te(kind === "group" ? "группа ({id})" : "адресат ({id})", { id });
    return te(kind === "group" ? "удалённая группа ({id})" : "неизвестный адресат ({id})", { id });
  }
  // nullKey — подпись пустого значения у строки настроек, например «без ограничения» (RULE-69)
  // targetKind — вид адресата строки «target» (alerts.targetKind)
  function fmtSetting(v, key, seconds, values, nullKey, targetKind) {
    const sec = seconds || /Sec$/.test(key);
    if (v == null) return nullKey ? te(nullKey) : "—";
    if (values && typeof v === "string" && values[v]) return te(values[v]);
    if (typeof v === "boolean") return te(v ? "да" : "нет");
    if (typeof v === "number") return /Min(utes)?$/.test(key) ? fmtDuration(v * 60) : sec ? fmtDuration(v) : String(v);
    // Адресат — id пользователя или дежурной группы (alerts.target, ARCH-07 в7)
    if (typeof v === "string") return key === "target" ? addressee(v, targetKind) : te(v);
    if (Array.isArray(v)) {
      if (!v.length) return te("нет");
      return v
        .map((x) => {
          if (typeof x !== "object") return fmtSetting(x, key, sec);
          // Уровень эскалации (§8.3): номер, название (текст организации) — адресат и норматив
          if (x.level != null)
            return `${te("Уровень {n}", { n: x.level })}${typeof x.name === "string" && x.name.trim() ? ` «${escapeHtml(t(x.name.trim()))}»` : ""}: ${addressee(String(x.target), x.targetKind)}, ${te("реакция {time}", { time: fmtDuration(x.reactionSec) })}`;
          if (x.sec != null) return `${Object.entries(x).filter(([k]) => k !== "sec").map(([k, val]) => `${word(k)} = ${word(String(val))}`).join(", ")}: ${fmtDuration(x.sec)}`;
          // Срок null — без срока; у причины со сроком из порогов молчания (deadlineFromIdle, «Нет связи») — так и сказать (BUG-119)
          const limit = x.deadlineFromIdle ? ` (${te("порог «в очередь» минус «отложить»")})` : x.maxMinutes != null ? ` (${fmtDuration(x.maxMinutes * 60)})` : "maxMinutes" in x ? ` (${te("без срока")})` : "";
          return escapeHtml(hasLbl(x, "label") ? lbl(x) : t(x.id)) + limit;
        })
        .join("<br>");
    }
    return Object.entries(v)
      .filter(([k]) => !k.startsWith("$"))
      .map(([k, val]) => `${word(k)}: ${fmtSetting(val, k, sec)}`)
      .join("<br>");
  }
  // Звук схемы (§21.2): звук по уровням справочника — строкой на уровень, как его услышит оператор (уровень без своей
  // строки — как ближайший ниже, cueForPriority), и звук «лично вам» и оповещения; ▶ «Прослушать» играет звук
  function cueCells(cue) {
    if (!cue || cue.repeat === "none") return [te("без звука"), "—"];
    const pattern = (WORKFLOW.sound.patterns || []).find((p) => p.id === cue.pattern);
    const name = pattern ? lbl(pattern) : cue.pattern;
    const play = `<button type="button" class="btn ghost small sound-play" data-sound-play="${escapeHtml(cue.pattern)}" title="${te("Прослушать")}" aria-label="${te("Прослушать: {what}", { what: name })}">▶</button>`;
    const repeat = cue.repeat === "until_taken" ? `${word("until_taken")}, ${te("каждые {n} с", { n: cue.repeatSec })}` : word(cue.repeat);
    return [`${escapeHtml(name)} ${play}`, repeat];
  }
  function soundSetting(path) {
    if (!WORKFLOW.sound || !/^sound\.(byPriority|personal|alert)$/.test(path)) return null;
    if (path !== "sound.byPriority") return cueCells(settingAt(path)).join(" · ");
    const rows = store.priorities
      .slice()
      .sort((a, b) => b.value - a.value)
      .map((p) => {
        const [sound, repeat] = cueCells(IMSound.cueForPriority(WORKFLOW.sound.byPriority, p.value));
        return `<tr data-sound-level="${p.value}"><td>${asData(inLang(p.name))} <span class="what">${p.value}</span></td><td>${sound}</td><td>${repeat}</td></tr>`;
      })
      .join("");
    return `<table class="doc-table sound-levels"><thead><tr><th>${te("Приоритет")}</th><th>${te("Звук")}</th><th>${te("Повтор")}</th></tr></thead><tbody>${rows}</tbody></table>`;
  }
  const sourcePath = (tab) => tab.source.split(" ")[1];
  // Названия и имена — данные, они не переводятся (§14.9)
  const asData = (text) => `<span data-i18n-skip>${escapeHtml(text)}</span>`;
  /* ===== Экран «Смена и статистика»: блок «Сейчас» (§23, план 90) ===== */

  // Вкладка — только с правом supervisor:view (§23). Данные — GET /operator/supervisor/now: при открытии, по смене
  // фильтра и опросом раз в shift.refreshSec машины, пока экран открыт (§23.2). Блок «За период» — часть Б плана 90
  const shiftState = { open: false, data: null, error: null, groups: [], group: "", sort: { key: "since", dir: -1 }, outOpen: false, shownAt: 0, loading: false, groupsKey: "", tableKey: "" };
  const shiftLocale = () => (LANGS.find((l) => l.id === LANG) || LANGS[0]).locale;
  // Время на экране — в поясе смены (§23): часы и минуты, не сегодняшнее по поясу смены — с датой
  function shiftTime(value, tz, withSec) {
    const opts = { timeZone: tz, hour12: false, hour: "2-digit", minute: "2-digit" };
    if (withSec) opts.second = "2-digit";
    const day = (ms) => new Date(ms).toLocaleDateString("en-CA", { timeZone: tz });
    if (day(Date.parse(value)) !== day(serverNow())) Object.assign(opts, { day: "2-digit", month: "2-digit" });
    return new Date(value).toLocaleString(shiftLocale(), opts);
  }
  const shiftClock = (value, tz) => new Date(value).toLocaleTimeString(shiftLocale(), { timeZone: tz, hour12: false, hour: "2-digit", minute: "2-digit" });
  // Сколько длится перерыв или сколько нет связи: минуты, от часа — часы и минуты
  function shiftLasts(ms) {
    const min = Math.max(0, Math.floor(ms / 60000));
    return min < 60 ? t("{n} мин", { n: min }) : t("{h} ч {m} мин", { h: Math.floor(min / 60), m: min % 60 });
  }
  // Реакция — минуты и секунды
  function shiftReaction(sec) {
    if (sec == null) return "—";
    const s = Math.round(sec);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }
  // Состояние строки: подписи — из машины (session.states); «Нет связи» — не состояние машины (§12.3, §23.2)
  // «Нет связи» — состояние строки SupervisorNowRow.state контракта, не причина удержания с тем же id
  const NO_LINK = "no_link"; // SupervisorNowRow.state
  const SHIFT_STATES = ["ready", "busy", "not_ready", NO_LINK, "offline"];
  function shiftStateLabel(id) {
    const def = WORKFLOW.session.states.find((s) => s.id === id);
    return def ? lbl(def) : t("Нет связи");
  }
  // Причина перерыва — по справочнику поста на языке интерфейса; нет в справочнике — как прислал сервер
  function shiftReason(r) {
    if (r.state !== "not_ready" || !r.reasonId) return null;
    const def = (WORKFLOW.session.breakReasons || []).find((x) => x.id === r.reasonId);
    return def ? lbl(def) : r.reasonLabel || r.reasonId;
  }
  // Столбцы таблицы (§23.2): все сортируются; text — по алфавиту без учёта регистра и «ё», остальные — по числу
  const SHIFT_COLS = [
    { key: "name", head: "Оператор", text: true, val: (r) => r.person.name },
    { key: "state", head: "Состояние", val: (r) => SHIFT_STATES.indexOf(r.state) },
    { key: "reason", head: "Причина", text: true, val: shiftReason },
    { key: "since", head: "С какого времени", val: (r) => (r.since ? Date.parse(r.since) : null) },
    { key: "breakOverdue", head: "Срок перерыва вышел", val: (r) => (r.breakOverdue == null ? null : Number(r.breakOverdue)) },
    { key: "groups", head: "Дежурные группы", text: true, val: (r) => (r.dutyGroups.length ? r.dutyGroups.map((g) => g.name).join(", ") : null) },
    { key: "inProgress", head: "В работе", num: true, val: (r) => r.inProgress },
    { key: "onHold", head: "Отложено", num: true, val: (r) => r.onHold },
    { key: "overdue", head: "Просрочено", num: true, val: (r) => r.overdue },
    { key: "closed", head: "Закрыл за смену", num: true, val: (r) => r.closedThisShift },
    { key: "median", head: "Медиана реакции", num: true, val: (r) => r.medianReactionSec },
  ];
  // Порядок строк: по выбранному столбцу, при равенстве — по имени; пустое значение — в конце при любом направлении
  function shiftSorted(rows) {
    const col = SHIFT_COLS.find((c) => c.key === shiftState.sort.key) || SHIFT_COLS[3];
    const coll = new Intl.Collator(LANG, { sensitivity: "base", numeric: true });
    const byName = (a, b) => coll.compare(a.person.name, b.person.name);
    return rows.slice().sort((a, b) => {
      const [x, y] = [col.val(a), col.val(b)];
      if (x == null || y == null) return x == null && y == null ? byName(a, b) : x == null ? 1 : -1;
      return (col.text ? coll.compare(x, y) : x - y) * shiftState.sort.dir || byName(a, b);
    });
  }
  function shiftRow(r, tz) {
    const groups = r.dutyGroups.map((g) => g.name).join(", ");
    // Подпись столбца у ячейки — для телефона: там строка таблицы — карточка, а заголовки — кнопки сортировки
    const at = (key) => `data-label="${te(SHIFT_COLS.find((c) => c.key === key).head)}"`;
    const n = (key, v, late) => `<td class="num${late && v ? " late" : ""}" ${at(key)}>${v}</td>`;
    return `<tr data-shift-person="${escapeHtml(r.person.id)}" data-shift-state="${r.state}" data-shift-since="${escapeHtml(r.since || "")}">
      <td>${asData(r.person.name)}</td>
      <td><span class="badge shift-state ${r.state}">${te(shiftStateLabel(r.state))}</span></td>
      <td class="shift-reason">${escapeHtml(shiftReason(r) || "")}</td>
      ${shiftSinceCell(r, tz, at("since"))}
      <td class="shift-overdue-break" ${at("breakOverdue")}>${r.breakOverdue == null ? "" : te(r.breakOverdue ? "да" : "нет")}</td>
      <td ${at("groups")}>${groups ? asData(groups) : "—"}</td>
      ${n("inProgress", r.inProgress)}${n("onHold", r.onHold)}${n("overdue", r.overdue, true)}${n("closed", r.closedThisShift)}
      <td class="num" ${at("median")}>${shiftReaction(r.medianReactionSec)}</td>
    </tr>`;
  }
  // «С какого времени» у перерыва и «нет связи» — с «сколько длится»; это единственный текст, что меняется между опросами
  function shiftSinceText(since, state, tz) {
    const away = state === "not_ready" || state === NO_LINK;
    return shiftTime(since, tz) + (away ? ` · ${shiftLasts(serverNow() - Date.parse(since))}` : "");
  }
  function shiftSinceCell(r, tz, label) {
    if (!r.since) return `<td ${label}>—</td>`;
    const away = r.state === "not_ready" || r.state === NO_LINK;
    return `<td class="${away ? "shift-away" : ""}" ${label}${away ? ` data-shift-tick="${r.state}"` : ""}>${escapeHtml(shiftSinceText(r.since, r.state, tz))}</td>`;
  }
  // Раз в 5 с — только «сколько длится»: таблица и список групп не перестраиваются, фокус и открытый список не теряются
  function tickShift() {
    const d = shiftState.data;
    if (!shiftState.open || !d) return;
    $("shiftTable").querySelectorAll("[data-shift-tick]").forEach((td) => {
      const since = td.closest("tr").dataset.shiftSince;
      td.textContent = shiftSinceText(since, td.dataset.shiftTick, d.shift.timeZone);
    });
  }
  function renderShift() {
    if (!shiftState.open) return;
    const d = shiftState.data;
    // Список групп — только когда он сам или язык сменились
    const groupsKey = JSON.stringify([LANG, shiftState.groups]);
    if (shiftState.groupsKey !== groupsKey) {
      shiftState.groupsKey = groupsKey;
      $("shiftGroup").innerHTML = [`<option value="">${te("Все дежурные группы")}</option>`]
        .concat(shiftState.groups.map((g) => `<option value="${escapeHtml(g.id)}" data-i18n-skip>${escapeHtml(g.name)}</option>`))
        .join("");
    }
    if ($("shiftGroup").value !== shiftState.group) $("shiftGroup").value = shiftState.group;
    $("shiftNote").textContent = shiftState.error || "";
    // Таблица — только при новых данных, сортировке, раскрытии вышедших или смене языка
    const tableKey = JSON.stringify([LANG, d && d.at, d && shiftState.group, shiftState.error, shiftState.sort, shiftState.outOpen]);
    if (shiftState.tableKey === tableKey) return tickShift();
    shiftState.tableKey = tableKey;
    if (!d) {
      $("shiftSpan").textContent = "";
      $("shiftUpdated").textContent = shiftState.error ? "" : t("Загрузка…");
      $("shiftSummary").innerHTML = "";
      $("shiftTable").innerHTML = "";
      return;
    }
    const tz = d.shift.timeZone;
    $("shiftSpan").textContent = t("смена {from}–{to}", { from: shiftClock(d.shift.from, tz), to: shiftClock(d.shift.to, tz) });
    $("shiftUpdated").textContent = t("обновлено {time} · само раз в {sec} с", { time: shiftTime(d.at, tz, true), sec: WORKFLOW.shift.refreshSec });
    const s = d.summary;
    const chip = (cls, label, v) => `<span class="shift-chip ${cls}${v ? "" : " zero"}" data-shift-sum="${cls}">${te(label)} <b>${v}</b></span>`;
    $("shiftSummary").innerHTML = [
      chip("present", "На месте", s.present),
      chip("not_ready", "На перерыве", s.onBreak),
      chip(NO_LINK, "Нет связи", s.noLink),
      chip("offline", "Вышли", s.signedOut),
      chip("unowned", "Ничьих в очереди", s.unowned),
      chip("overdue", "Просрочено всего", s.overdue),
    ].join("");
    const sort = shiftState.sort;
    const head = SHIFT_COLS.map((c) => {
      const on = c.key === sort.key;
      return `<th class="${c.num ? "num" : ""}" aria-sort="${on ? (sort.dir < 0 ? "descending" : "ascending") : "none"}"><button type="button" class="shift-sort${on ? " on" : ""}" data-shift-sort="${c.key}">${te(c.head)}<span aria-hidden="true">${on ? (sort.dir < 0 ? " ↓" : " ↑") : " ↕"}</span></button></th>`;
    }).join("");
    // Вышедшие — в конце; по умолчанию свёрнуты в одну строку: «Лебедев О. и ещё 2», закрыл за смену — сумма (§23.2)
    const rows = shiftSorted(d.operators);
    const here = rows.filter((r) => r.state !== "offline");
    const out = rows.filter((r) => r.state === "offline");
    let tail = "";
    if (out.length && shiftState.outOpen) {
      tail = out.map((r) => shiftRow(r, tz)).join("") + `<tr class="shift-out"><td colspan="${SHIFT_COLS.length}"><button type="button" class="btn ghost small" data-shift-out>${te("Свернуть вышедших")}</button></td></tr>`;
    } else if (out.length) {
      const who = out.length > 1 ? t("{name} и ещё {n}", { name: out[0].person.name, n: out.length - 1 }) : out[0].person.name;
      const closed = out.reduce((sum, r) => sum + r.closedThisShift, 0);
      tail = `<tr class="shift-out" data-shift-state="offline"><td><button type="button" class="shift-out-btn" data-shift-out data-i18n-skip title="${te("Показать вышедших")}">${escapeHtml(who)}</button></td>
        <td><span class="badge shift-state offline">${te("Вышли")}</span></td><td class="shift-reason"></td><td class="shift-wide">—</td><td class="shift-overdue-break"></td><td class="shift-wide">—</td>
        <td class="num shift-wide">—</td><td class="num shift-wide">—</td><td class="num shift-wide">—</td><td class="num" data-label="${te("Закрыл за смену")}">${closed}</td><td class="num shift-wide">—</td></tr>`;
    }
    $("shiftTable").innerHTML = `<thead><tr>${head}</tr></thead><tbody>${here.map((r) => shiftRow(r, tz)).join("")}${tail}</tbody>`;
  }
  async function loadShift() {
    if (shiftState.loading) return; // предыдущий запрос ещё не вернулся
    const group = shiftState.group;
    shiftState.loading = true;
    try {
      const data = await api.get(`/operator/supervisor/now${group ? `?dutyGroup=${enc(group)}` : ""}`);
      if (group !== shiftState.group) return void setTimeout(loadShift); // пока ждали ответ, фильтр сменили — спросить заново
      // Список групп фильтра — из ответа без фильтра: группы, в которые входит хоть один оператор
      if (!group) {
        const seen = new Map();
        data.operators.forEach((r) => r.dutyGroups.forEach((g) => seen.set(g.id, g)));
        shiftState.groups = [...seen.values()];
      }
      Object.assign(shiftState, { data, error: null });
    } catch (err) {
      shiftState.error = problemText(err);
    } finally {
      shiftState.loading = false;
    }
    shiftState.shownAt = Date.now();
    renderShift();
  }
  // Какой экран открыт: очередь или «Смена и статистика»; без права — вкладок нет, открыта очередь
  function renderScreen() {
    const allowed = can("supervisor:view");
    if (!allowed) shiftState.open = false;
    $("screenTabs").hidden = !allowed;
    $("screenTabs")
      .querySelectorAll("[data-screen]")
      .forEach((b) => {
        const on = (b.dataset.screen === "shift") === shiftState.open;
        b.classList.toggle("active", on);
        b.setAttribute("aria-selected", String(on));
      });
    // Телефон: своя кнопка в нижней навигации; открыт экран смены — разделы очереди не выделены
    $("navShift").hidden = !allowed;
    $("mobileNav")
      .querySelectorAll("button")
      .forEach((b) => {
        const on = b.dataset.screen === "shift" ? shiftState.open : !shiftState.open && b.dataset.view === state.mobileView;
        b.classList.toggle("active", on);
        if (on) b.setAttribute("aria-current", "page");
        else b.removeAttribute("aria-current");
      });
    $("workspace").hidden = shiftState.open;
    $("shiftScreen").hidden = !shiftState.open;
    document.body.dataset.screen = shiftState.open ? "shift" : "queue";
  }
  function showScreen(id) {
    const open = id === "shift" && can("supervisor:view");
    if (open === shiftState.open) return;
    shiftState.open = open;
    renderScreen();
    if (open) {
      renderShift();
      loadShift();
    }
  }
  function bindShift() {
    $("screenTabs").addEventListener("click", (e) => {
      const btn = e.target.closest("[data-screen]");
      if (btn) showScreen(btn.dataset.screen);
    });
    $("shiftGroup").addEventListener("change", (e) => {
      shiftState.group = e.target.value;
      shiftState.data = null;
      renderShift();
      loadShift();
    });
    $("shiftTable").addEventListener("click", (e) => {
      const sortBtn = e.target.closest("[data-shift-sort]");
      if (sortBtn) {
        const key = sortBtn.dataset.shiftSort;
        shiftState.sort = key === shiftState.sort.key ? { key, dir: -shiftState.sort.dir } : { key, dir: 1 };
        renderShift();
        const again = $("shiftTable").querySelector(`[data-shift-sort="${key}"]`); // таблица перестроена — фокус вернуть на ту же кнопку
        if (again) again.focus();
      }
      if (e.target.closest("[data-shift-out]")) {
        shiftState.outOpen = !shiftState.outOpen;
        renderShift();
        const again = $("shiftTable").querySelector("[data-shift-out]");
        if (again) again.focus();
      }
    });
    // Нижняя навигация телефона: «Смена» — к экрану смены, разделы очереди — к очереди
    $("mobileNav").addEventListener("click", (e) => {
      const btn = e.target.closest("button");
      if (btn) showScreen(btn.dataset.screen === "shift" ? "shift" : "queue");
    });
    // Опрос, пока экран открыт; между опросами — «сколько длится» по часам пульта
    setInterval(() => {
      if (!shiftState.open) return;
      if (Date.now() - shiftState.shownAt >= WORKFLOW.shift.refreshSec * 1000) loadShift();
      else tickShift();
    }, 5000);
  }

  async function openAdmin() {
    // Список групп или людей поста не пришёл — null: адресат тогда не «удалённый» (BUG-124)
    [adminState.data.duty, adminState.data.people] = await Promise.all([
      api.get("/operator/admin/duty-groups").catch(() => null),
      api.get("/operator/admin/people").catch(() => null),
    ]);
    adminState.tab = adminState.tab || WORKFLOW.adminSettings.tabs[0].id;
    $("modalAdmin").hidden = false;
    await renderAdmin();
  }
  async function renderAdmin() {
    const tabs = WORKFLOW.adminSettings.tabs;
    const tab = tabs.find((x) => x.id === adminState.tab) || tabs[0];
    $("adminTabs").innerHTML = tabs
      .map((x) => `<button type="button" role="tab" data-admin-tab="${x.id}" class="${x.id === tab.id ? "active" : ""}" aria-selected="${x.id === tab.id}">${escapeHtml(lbl(x))}</button>`)
      .join("");
    const note = escapeHtml(`${t("Правила")}: ${tab.rules}` + (hasLbl(tab, "what") ? `. ${lbl(tab, "what")}` : ""));
    const goto = tab.seeAlso ? ` <button type="button" class="btn ghost small" data-admin-goto="${tab.seeAlso}">${te("Посмотреть состояние")}</button>` : "";
    const refresh = tab.refreshSec ? ` <button type="button" class="btn ghost small" data-admin-refresh>${te("Обновить")}</button>` : "";
    $("adminNote").innerHTML = note + goto + refresh;
    adminState.shownAt = Date.now();
    const table = $("adminTable");
    table.className = tab.items ? "doc-table settings" : "doc-table";
    if (tab.items) {
      // Разделы объединённой вкладки (план 77): заголовок раздела строкой, настройки раздела — под ним; раздел без
      // настроек, с запросом (source), — вложенной таблицей своих данных
      const groups = tab.groups || [];
      // Список причин — по названию, как в формах оператора (§2.2)
      const reasons = (path, v) => (Array.isArray(v) && /^(reasonCatalogs\.[^.]+\.items|session\.breakReasons)$/.test(path) ? v.slice().sort(byName((x) => (hasLbl(x, "label") ? lbl(x) : t(x.id)))) : v);
      const itemRow = (item) =>
        `<tr><td>${escapeHtml(lbl(item))}<span class="what">${escapeHtml(lbl(item, "what"))}</span></td><td>${
          soundSetting(item.path) || fmtSetting(reasons(item.path, settingAt(item.path)), item.path.split(".").pop(), item.path.startsWith("timers."), item.values, item.nullKey, settingAt(`${item.path}Kind`))
        }</td></tr>`;
      const groupHead = (g) => `<tr class="admin-group" data-admin-group="${g.id}"><th colspan="2">${escapeHtml(lbl(g))}<span class="what">${escapeHtml(`${t("Правила")}: ${g.rules}`)}</span></th></tr>`;
      const body = groups.length
        ? (
            await Promise.all(
              groups.map(async (g) => {
                if (g.source) return `${groupHead(g)}<tr><td colspan="2"><table class="doc-table">${await sourceTable(g)}</table></td></tr>`;
                return groupHead(g) + tab.items.filter((i) => i.group === g.id).map(itemRow).join("");
              })
            )
          ).join("")
        : tab.items.map(itemRow).join("");
      if ((tabs.find((x) => x.id === adminState.tab) || tabs[0]) !== tab) return; // пока ждали запрос раздела, открыли другую вкладку
      table.innerHTML = `<thead><tr><th>${te("Настройка")}</th><th>${te("Сейчас")}</th></tr></thead><tbody>${body}</tbody>`;
      return;
    }
    if (!tab.source) {
      table.innerHTML = `<tbody><tr><td>${te("В прототипе запроса нет: эти данные МИ ещё не вынесены в контракт")}</td></tr></tbody>`;
      return;
    }
    const html = sourcePath(tab) === "/operator/admin/system-status" ? await systemStatusTable() : await sourceTable(tab);
    if ((tabs.find((x) => x.id === adminState.tab) || tabs[0]) !== tab) return; // пока ждали запрос, открыли другую вкладку
    table.innerHTML = html;
  }
  // Раздел «Состояние системы» (§14.11, §20): четыре блока строками «что — сейчас»; числа, которые прототип
  // не считает (demoFields), помечены «демо»
  async function systemStatusTable() {
    const s = await api.get("/operator/admin/system-status").catch((err) => ({ error: problemText(err) }));
    if (s.error) return `<tbody><tr><td>${escapeHtml(s.error)}</td></tr></tbody>`;
    const demo = new Set(s.demoFields || []);
    const mark = (path) => ([...demo].some((d) => path === d || path.startsWith(`${d}.`)) ? ` <span class="badge">${te("демо")}</span>` : "");
    const bytes = (n) => {
      if (n == null) return te("нет данных");
      const units = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
      let v = Math.abs(n);
      let i = 0;
      while (v >= 1024 && i < units.length - 1) {
        v /= 1024;
        i++;
      }
      return `${n < 0 ? "−" : ""}${v.toFixed(i ? 1 : 0)} ${te(units[i])}`;
    };
    const when = (v) => (v ? escapeHtml(fmtWhen(v)) : te("нет данных"));
    const row = (label, value, path, what) => `<tr><td>${te(label)}${what ? `<span class="what">${te(what)}</span>` : ""}</td><td>${value}${path ? mark(path) : ""}</td></tr>`;
    const head = (id, label, what) => `<tr class="admin-group" data-status-block="${id}"><th colspan="2">${te(label)}${what ? `<span class="what">${te(what)}</span>` : ""}</th></tr>`;
    const PART = { events: "События", incidents: "Инциденты", journal: "Журналы", comment_files: "Файлы комментариев", maintenance_windows: "Окна плановых работ", other: "Остальное" };
    const db = s.database;
    const r = s.retention;
    const p = r.lastPurge;
    const sv = s.server;
    const perHour = sv.eventsPerMinute.reduce((x, y) => x + y, 0);
    const body = [
      head("database", "База", "Общий для сервера: размер и диск — всех организаций"),
      row("Размер базы", bytes(db.bytes), "database"),
      row("Прирост за сутки", bytes(db.growthDayBytes), "database"),
      row("Прирост за неделю", bytes(db.growthWeekBytes), "database"),
      row("Свободно на диске", bytes(db.diskFreeBytes), "database"),
      row("Хватит при текущем приросте", db.daysLeft == null ? te("нет данных") : te("на {n} дн.", { n: db.daysLeft }), "database"),
      ...db.parts.map((x) => row(PART[x.name] || x.name, bytes(x.bytes), "database")),
      head("retention", "Хранение", "Очистка по сроку хранения — раз в час, только своей организации"),
      row("Последняя очистка", p ? `${when(p.at)}: ${te("инцидентов {i}, событий {e}, записей потока {s}", { i: p.incidents, e: p.events, s: p.streamEvents })}` : te("ещё не было"), "retention.lastPurge"),
      row("Следующая очистка", when(r.nextPurgeAt), "retention.nextPurgeAt"),
      row("Самое старое событие", when(r.oldestEventAt)),
      row("Самый старый инцидент", when(r.oldestIncidentAt)),
      row("Самая старая запись аудита", when(r.oldestAuditAt)),
      head("server", "Работа сервера"),
      row("Приём событий в минуту", te("сейчас {now}, за час {hour}, в среднем {avg}", { now: sv.eventsPerMinute[59], hour: perHour, avg: (perHour / 60).toFixed(1) }), "server.eventsPerMinute"),
      row("Операторов на связи", String(sv.operatorsOnline), "server.operatorsOnline"),
      row("Версия сервера", asData(sv.serverVersion), "server.serverVersion"),
      row("Версия машины", String(sv.workflowVersion), "server.workflowVersion"),
      row("Идут окна плановых работ", `${sv.maintenanceActive} <button type="button" class="btn ghost small" data-admin-goto="maintenance">${te("Открыть окна")}</button>`, "server.maintenanceActive"),
      row("Обновлено", when(s.at)),
    ].join("");
    return `<thead><tr><th>${te("Что")}</th><th>${te("Сейчас")}</th></tr></thead><tbody>${body}</tbody>`;
  }

  // Данные МИ вкладки или раздела с запросом (source): шапка и строки таблицы, ошибка — строкой
  async function sourceTable(tab) {
    const data = await api.get(sourcePath(tab)).catch((err) => ({ error: problemText(err) }));
    if (data.error) return `<tbody><tr><td>${escapeHtml(data.error)}</td></tr></tbody>`;
    const names = (list) => asData(list.map((x) => x.name).join(", ") || "—");
    const rows = {
      "/operator/admin/access-groups": () => [
        ["Группа доступа", "Роли", "Объекты"],
        data.map((a) => `<tr><td>${asData(a.name)}</td><td>${asData(a.roles.join(", "))}</td><td>${names(a.sourceGroups.concat(a.devices))}</td></tr>`),
      ],
      "/operator/admin/duty-groups": () => [
        ["Дежурная группа", "Роли", "Отдельно", "Состав сейчас"],
        data.map((g) => `<tr><td>${asData(g.name)}</td><td>${asData(g.roles.join(", ") || "—")}</td><td>${asData(g.members.map(personName).join(", ") || "—")}</td><td>${asData(g.memberIds.map(personName).join(", ") || "—")}</td></tr>`),
      ],
      "/operator/reference/help-links": () => [
        ["Ссылка", "Вид", "Группа"],
        // Область (§7): общая, группа устройств или «не назначена» — «выберите группу» с прежней площадкой
        data.map((l) => {
          const scope =
            l.scope === "group" ? asData(l.groupName || "—") : l.scope === "unassigned" ? `${te("выберите группу")}${l.legacySite ? `<span class="what">${asData(l.legacySite)}</span>` : ""}` : te("общая");
          return `<tr><td>${asData(l.title)}<span class="what">${escapeHtml(l.url)}</span></td><td>${te(l.kind === "file" ? "файл" : "веб-страница")}</td><td>${scope}</td></tr>`;
        }),
      ],
      // Приоритеты (§2.5): число, название и описание на языке оператора, цвет — квадратиком того же
      // цвета, что полоска очереди, и словом: цвет — не единственный способ его узнать (BUG-39)
      // Окна плановых работ (§14.12, ТЗ-21): что, где, когда, повтор и состояние
      "/operator/maintenance-windows": () => [
        ["Окно работ", "Где", "Когда", "Состояние"],
        data.map((w) => {
          const where = w.deviceGuid ? deviceName(w.deviceGuid) : groupName(w.sourceGroupGuid);
          const rec = w.recurrence ? te("Повтор: дни {days}, {from}–{to}", { days: w.recurrence.days.join(", "), from: w.recurrence.startTime, to: w.recurrence.endTime }) : te("Без повтора");
          const st = { planned: "Впереди", active: "Идёт", ended: "Закончилось" }[w.status];
          return `<tr><td>${asData(w.description || "—")}</td><td>${asData(where || "—")}</td><td>${asData(`${fmtWhen(w.startsAt)} – ${fmtWhen(w.endsAt)}, ${w.timeZone}`)}<span class="what">${rec}</span></td><td>${te(st)}</td></tr>`;
        }),
      ],
      "/operator/reference/priorities": () => [
        ["Число", "Приоритет", "Цвет"],
        data.map((p) => `<tr><td>${p.value}</td><td>${asData(inLang(p.name))}<span class="what">${asData(inLang(p.description))}</span></td><td><span class="event-pri swatch" data-color="${escapeHtml(p.color)}"></span> ${word(p.color)}</td></tr>`),
      ],
      "/operator/admin/camera-links": () => [
        ["Связь", "Устройства", "Камеры по порядку"],
        data.map((l) => `<tr><td>${asData(l.name)}</td><td>${names(l.devices)}</td><td>${names(l.cameras)}</td></tr>`),
      ],
      "/operator/reference/source-groups": () => {
        const out = [];
        const walk = (nodes, depth) =>
          nodes.forEach((n) => {
            out.push(`<tr><td style="padding-left:${10 + depth * 16}px">${asData(n.name)}</td><td>${n.devices.length}</td></tr>`);
            walk(n.children || [], depth + 1);
          });
        walk(data, 0);
        return [["Группа устройств", "Устройств"], out];
      },
    }[sourcePath(tab)];
    const [head, body] = rows();
    return `<thead><tr>${head.map((h) => `<th>${te(h)}</th>`).join("")}</tr></thead><tbody>${body.join("")}</tbody>`;
  }

  // Часы и обратный отсчёт — на клиенте по меткам времени (§4). Дедлайны ведёт сервер:
  // что сработало, он сообщает в потоке событий
  setInterval(() => {
    const stamp = nowStamp();
    $("clock").textContent = stamp;
    $("clock").dateTime = stamp;
    document.querySelectorAll("[data-due]").forEach((el) => {
      const left = Number(el.dataset.due) - serverNow();
      el.querySelector(".sla-t").textContent = fmtSla(left);
      el.classList.toggle("late", left < lateMs());
    });
    const ev = selected();
    if (ev) $("statusSla").textContent = statusTimerText(ev);
  }, 1000);

  // Поток событий сервера: чужие действия и автоматические переходы — уведомление и обновление
  function onServerEvent(msg) {
    const tid = msg.payload && msg.payload.transitionId;
    const id = msg.incident ? msg.incident.number : msg.incidentGuid;
    const who = (ref) => actorName(ref);
    const mine = msg.actor && msg.actor.id === (store.session && store.session.operator.guid);
    // Строка из потока собрана для меня (filters — для читающего): по ней — что прячет звучащее (§22.3)
    if (msg.incident) noteIncidents([msg.incident]);
    // Кто и каким переходом — для бледной строки, если инцидент из-за него ушёл из списка (§22.1, BUG-121)
    if (msg.incidentGuid && tid) noteMove(msg.incidentGuid, msg.actor, mine);
    // Чужое или автоматическое событие: строка, которая из-за него появится в очереди, — новая, её подсветить (§22.3)
    if (!mine && msg.incidentGuid) arrived.add(msg.incidentGuid);
    // Звук решается раньше выхода по своему переходу: моё действие снимает повтор (§21.2)
    soundOnEvent(msg);
    // Свой переход — без уведомления. О закрытом мной соседе сервер мне и не пишет — даже когда я в дежурной группе-адресате
    // (§6.1, решение 2026-10-29)
    // Окна работ изменились (ТЗ-21): полоса и значки дерева — по перечитанному списку, и после своей правки
    if (msg.type === "maintenance.windows_changed") return refreshMaintenance();
    if (mine && msg.type !== "incident.card_evicted") return;
    // История потока потеряна (Last-Event-ID нет у сервера): перечитать очередь, карточку и сессию (BUG-102)
    if (msg.type === "stream.reset") return reload().then(() => soundRestore());
    // Изменился справочник приоритетов: полоски, подписи, метка дерева — по нему (§2.5)
    if (msg.type === "reference.priorities_changed") {
      return loadPriorities()
        .then(() => reload())
        .then(() => soundRestore(true));
    }
    // Опубликована новая схема: подписи, кнопки, фильтры и порядок очереди — по ней (§14.6)
    if (msg.type === "workflow.schema_published") {
      return loadWorkflow().then(() => {
        renderTypeFilters();
        reload().then(() => soundRestore(true));
      });
    }
    // Чужое и автоматическое — не всплывает (§22.2, §22.6): запись в колокольчике; нужно действие — «Нужно действие»
    // (строка и так встанет в блок «Мне на принятие», §7), остальное — сведения
    const ref = { guid: msg.incidentGuid, number: msg.incident ? msg.incident.number : null };
    const kindOf = (p) => (p && p.addressedToMe ? "action" : "info");
    // Доступ к объекту пропал (§5): данных инцидента больше нет — только номер; карточка закрывается
    if (msg.type === "incident.access_lost") {
      notice(t("{id} вам больше не доступен: изменились группы доступа", { id: msg.payload.number }), { kind: "info" });
      if (state.selectedId === msg.incidentGuid) {
        state.selectedId = null;
        return backToQueue();
      }
    } else if (msg.type === "incident.card_evicted" && !mine && state.selectedId === msg.incidentGuid) {
      // Открытую карточку увели (§6.1, §6.2, §14.8, §22.7): почему — подпись перехода из машины; полоса в самой карточке
      // «{что}: {кто} — только просмотр», запись — и в колокольчике. Переход, о котором всем, кто видит инцидент, и так
      // скажет observerNotice, — без второй записи (BUG-105)
      const tr = transitionDef(tid);
      const obs = tr && tr.ui && tr.ui.observerNotice;
      const what = tr ? lbl(tr) : tid;
      state.evicted[msg.incidentGuid] = { who: msg.actor ? who(msg.actor) : "", what };
      if (!obs || obs.audience !== "observers") notice(t("{id}: карточка только для просмотра — {what}", { id, what }), Object.assign({ kind: "info" }, ref));
    } else if (msg.type === "incident.alert") {
      // Оповещение получателю оповещений (§9): что случилось — подпись перехода из машины
      // Группа правила не может принять (М1) — с названием группы (payload.groupName)
      const tr = transitionDef(tid);
      const what = tr ? lbl(tr) : tid;
      const group = msg.payload && msg.payload.groupName;
      notice(group ? t("Оповещение: {id} — {what}: «{group}»", { id, what, group }) : t("Оповещение: {id} — {what}", { id, what }), Object.assign({ kind: kindOf(msg.payload) }, ref));
    } else if (msg.type === "incident.sibling_closed") {
      // Сосед того же события закрыт «Ложной тревогой» (§6.1, ARCH-15): адресату моего инцидента — какой и чем
      const p = msg.payload;
      const item = WORKFLOW.reasonCatalogs.close_result.items.find((i) => i.id === p.closeResultId);
      notice(t("{n} того же события закрыт: {result}", { n: p.siblingNumber, result: item ? lbl(item) : p.closeResultId }), Object.assign({ kind: "info" }, ref));
    } else if (msg.type === "incident.transitioned" || (msg.type === "incident.created" && tid)) {
      // Что сказать о чужом или автоматическом переходе — в машине (ui.observerNotice, RULE-60, BUG-32):
      // observers — всем, кто видит инцидент; newAddressee — новому адресату, лично или его группе.
      // Появление (incident.created) — так же по переходу появления: у группы правила — как адресату передачи (§8.1, М1)
      const tr = transitionDef(tid);
      const obs = tr && tr.ui && tr.ui.observerNotice;
      const p = msg.payload;
      if (obs && (obs.audience === "observers" || (obs.audience === "newAddressee" && p.addressedToMe))) {
        notice(t(obs.key, { id, who: who(msg.actor), addressee: who(p.addressee), previousOwner: who(p.owner && p.owner.from) }), Object.assign({ kind: kindOf(p) }, ref));
      }
    }
    reload();
  }

  // Загрузка: схема, сессия, справочники — потом первая отрисовка
  async function loadWorkflow() {
    WORKFLOW = await api.get("/operator/workflow/active");
    STATES = Object.fromEntries(WORKFLOW.states.map((s) => [s.id, s]));
    LIMITS = WORKFLOW.limits;
  }

  // Справочник приоритетов (§2.5, RULE-68): справочник МИ, не схема. Уровни — по числу; первым —
  // самый срочный. Интерфейс не знает уровни ни по имени, ни по числу
  async function loadPriorities() {
    store.priorities = await api.get("/operator/reference/priorities");
    PRIORITIES = Object.fromEntries(store.priorities.map((p) => [p.value, p]));
  }
  // Название и описание — на языке оператора, без перевода — русские (§2.5, §14.9)
  const inLang = (text) => (text ? text[LANG] || text.ru || "" : "");

  async function boot() {
    await loadWorkflow();
    await loadPriorities();
    setInterval(() => heartbeat(true), WORKFLOW.session.heartbeatSec * 1000);
    const [eventTypes, scenarios, deviceTypes, targets] = await Promise.all([
      api.get("/operator/reference/event-types"),
      api.get("/operator/reference/scenarios"),
      api.get("/operator/reference/device-types"),
      api.get("/operator/transfer-targets"),
    ]);
    Object.assign(store, { eventTypes, scenarios, deviceTypes, targets });
    // Каталоги строк всех языков интерфейса (§14.9): язык переключается без новых запросов
    const catalogs = await Promise.all(LANGS.map((l) => api.get(`/operator/strings?locale=${enc(l.id)}`)));
    LANGS.forEach((l, i) => (CATALOGS[l.id] = catalogs[i].strings));
    collectStatic();
    bind();
    bindBell();
    bindShift();
    let savedTheme = "dark";
    let savedLang = "ru";
    try {
      savedTheme = localStorage.getItem("im-theme") || "dark";
      savedLang = localStorage.getItem("im-lang") || "ru";
    } catch (err) {
      savedTheme = "dark";
    }
    if (narrowQuery.matches) state.groupsOn = false;
    narrowQuery.addEventListener("change", (e) => {
      state.groupsOn = !e.matches;
      renderAll();
    });
    applyTheme(savedTheme);
    await reload();
    applyLang(savedLang);
    bindSound();
    snd.agent = store.session ? store.session.agentState : null;
    await soundRestore();
    api.subscribe(
      onServerEvent,
      () => {
        setConn("stream", true);
        reload().then(() => soundRestore());
      },
      () => setConn("stream", false)
    );
    renderHelpLinks();
  }

  boot();
})();
