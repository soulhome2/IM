(() => {

  /* ===== Языки =====
     Тексты состояний и переходов — переводимые лейблы, а не идентификаторы:
     переименование состояния не должно быть миграцией данных (§14.6).
     Ключ словаря — русская строка, значение — перевод. */

  const LANGS = [
    { id: "ru", label: "Русский", short: "RU", locale: "ru-RU" },
    { id: "en", label: "English", short: "EN", locale: "en-GB" },
    { id: "es", label: "Español", short: "ES", locale: "es-ES" },
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

  function t(ru, vars) {
    const table = DICT[LANG];
    let out = (table && table[ru]) || ru;
    if (vars) out = out.replace(/\{(\w+)\}/g, (m, key) => (key in vars ? String(vars[key]) : m));
    return out;
  }

  const te = (ru, vars) => escapeHtml(t(ru, vars));


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
          <text x="42" y="162">Коридор корпуса</text>
          <text x="42" y="212">Офис 1</text>
          <text x="220" y="212">Офис 2</text>
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
  // дойти до алерта и потери доступа. Самопроверке — тот же клиент API (PROC-12)
  const embedded = apiBase
    ? null
    : IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, colleagues: selftestRun ? false : window.IM_COLLEAGUES, testSupport: selftestRun });
  const api = IMApi.create(apiBase ? { baseUrl: apiBase } : { server: embedded });
  if (selftestRun && embedded) window.IM_SELFTEST_API = api;
  // Ответы встроенного сервера — самопроверке: она сверяет их со схемами openapi.json
  if (embedded) window.IM_RECORDED = embedded.recorded;
  const enc = encodeURIComponent;
  const incPath = (guid) => `/operator/incidents/${enc(guid)}`;

  // Схема workflow — из /operator/workflow/active: формы, клавиши, фильтры, справочники
  let WORKFLOW = null;
  let STATES = {};
  let LIMITS = {};

  // Последние ответы сервера. Своих данных у интерфейса нет: всё — из этих ответов
  const store = {
    session: null,
    page: { items: [], total: 0, page: 1, pageSize: PAGE_SIZE },
    counters: {},
    tree: [],
    eventTypes: [],
    deviceTypes: [],
    targets: [],
    card: null,
    selection: null,
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
    filter: "open",
    // Тип события и тип устройства — фильтры поверх выбранной группы (RULE-03)
    eventType: "all",
    deviceType: "all",
    search: "",
    selectedId: "INC-1847",
    checked: new Set(),
    // Шаг, который смотрит оператор в карточке на просмотр: курсор владельца не двигается
    viewStep: new Map(),
    videoMode: "archive",
    activeCam: null,
    full: null,
    dialog: null,
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
  const actorLabel = (id) => {
    const target = targetById(id);
    return target ? `${t(target.name)} · ${t(target.role)}` : t("Не назначен");
  };
  const defaultTarget = () => actorLabel(prefs().defaultTransferTargetId);
  const addresseeOf = (ev) => (ev && (ev.owner || ev.assignmentGroup)) || null;

  // Ответ сервера [шаблон, подстановки] → строка на языке интерфейса
  const say = (key, vars) => (key ? t(key, logVars(vars)) : "");
  const problemText = (err) => {
    const p = err && err.problem;
    if (!p) return t("Нет связи с сервером");
    return p.messageKey ? say(p.messageKey, p.messageVars) : t(p.message || "");
  };

  function nowStamp() {
    const locale = (LANGS.find((l) => l.id === LANG) || LANGS[0]).locale;
    return new Date().toLocaleTimeString(locale, { hour12: false });
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
    document.title = t(STATIC.title);
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
    renderEscalateDefault();
    renderTypeFilters();
    renderHotkeysHelp();
    renderAll();
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
    toast(btn.title || t("Действие недоступно"));
    return true;
  }

  function toast(text) {
    const el = document.createElement("div");
    el.className = "toast";
    el.textContent = text;
    $("toasts").appendChild(el);
    setTimeout(() => el.remove(), 3200);
  }

  /* ===== Загрузка с сервера ===== */

  function queueQuery() {
    return {
      filter: state.filter,
      search: state.search,
      sourceGroupGuid: state.groupId === "all" ? null : state.groupId,
      eventTypeGuid: state.eventType === "all" ? null : state.eventType,
      deviceTypeId: state.deviceType === "all" ? null : state.deviceType,
      page: state.page,
      pageSize: PAGE_SIZE,
      focusGuid: state.selectedId,
    };
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
      let [session, page, counters, tree] = await Promise.all([
        api.get("/operator/session"),
        api.get("/operator/incidents", queueQuery()),
        api.get("/operator/incidents/counters"),
        api.get("/operator/reference/source-groups"),
      ]);
      // После действия очередь открывается на странице с выбранным инцидентом
      if (jump && page.focusPage && page.focusPage !== page.page) {
        state.page = page.focusPage;
        page = await api.get("/operator/incidents", queueQuery());
      }
      Object.assign(store, { session, page, counters, tree });
      state.page = page.page;
      if (!state.openGroups.size && !state.treeSeen) {
        tree.forEach((n) => state.openGroups.add(n.guid));
        state.treeSeen = true;
      }
      // Если выбранное событие спрятал фильтр, поиск или другая группа, выделение
      // переходит на первое видимое: иначе видеомонитор и карта показывают чужую зону.
      if (state.mode === "queue" && focus && page.focusPage == null) {
        state.selectedId = page.items.length ? page.items[0].guid : null;
      }
      await loadCard();
      renderAll();
    })()
      .catch((err) => toast(problemText(err)))
      .finally(() => {
        loading = null;
        if (reloadAgain) {
          reloadAgain = false;
          reload();
        }
      });
    return loading;
  }

  async function loadCard() {
    const id = state.selectedId;
    store.card = id ? await api.get(incPath(id)).catch(() => null) : null;
    if (store.card) focusCameras(store.card);
    heartbeat();
  }

  // Признак активности оператора (§12.3) и какая карточка открыта (§9.3): раз в
  // session.heartbeatSec и сразу, как только открытая карточка сменилась. Без него сервер
  // через idleHoldSec отложит инцидент оператора с причиной «нет связи»
  let lastOpen = undefined;
  function heartbeat(always) {
    const open = state.selectedId || null;
    if (!always && open === lastOpen) return;
    lastOpen = open;
    api.post("/operator/session/heartbeat", { openIncidentGuid: open }).catch(() => {});
  }

  // Выделенное событие: в карточке и для видео — полная карточка, в очереди — строка
  function selected() {
    if (store.card && store.card.guid === state.selectedId) return store.card;
    return store.page.items.find((e) => e.guid === state.selectedId) || null;
  }

  /* ===== Сценарий: шаги и ответы приходят в карточке (ScenarioProgress) ===== */

  const STEP_KIND = { Checkbox: "checkbox", RadioButton: "radio", Select: "combo", Comment: "edit", Macros: "macros" };
  const stepKind = (step) => STEP_KIND[step.type] || "edit";
  const stepRequired = (step) => (step.requiredFor || []).includes("closing");
  const scenarioOf = (ev) => (ev && ev.scenario) || null;
  const stepsOf = (ev) => (scenarioOf(ev) ? scenarioOf(ev).steps : []);
  const answersOf = (ev) => (scenarioOf(ev) ? scenarioOf(ev).answers : {});
  const launchedOf = (ev) => (scenarioOf(ev) ? scenarioOf(ev).launchedMacros : []);
  const stepShort = (step) => step.view.short || step.title;

  function stepAnswerText(ev, step) {
    const kind = stepKind(step);
    const answers = answersOf(ev);
    if (kind === "checkbox") return answers[step.id] ? "Да" : "";
    if (kind === "macros") return launchedOf(ev).length ? `${launchedOf(ev).length} макрос` : "";
    return answers[step.id] || "";
  }

  // Заполнен ли шаг — проверка формы на клиенте; обязательность шагов сверяет и сервер
  function isStepValid(ev, step) {
    if (!stepRequired(step)) return true;
    const kind = stepKind(step);
    const answers = answersOf(ev);
    if (kind === "checkbox") return answers[step.id] === true;
    if (kind === "macros") return true;
    return Boolean(answers[step.id]);
  }

  function firstOpenStep(ev) {
    const steps = stepsOf(ev);
    const blocked = steps.findIndex((s) => stepRequired(s) && !isStepValid(ev, s));
    if (blocked !== -1) return blocked;
    const empty = steps.findIndex((s) => !stepAnswerText(ev, s));
    return empty === -1 ? steps.length - 1 : empty;
  }

  function canOpenStep(ev, index) {
    const steps = stepsOf(ev);
    if (index < 0 || index >= steps.length) return false;
    return steps.slice(0, index).every((s) => isStepValid(ev, s));
  }

  // Шаг на экране: у владельца — курсор сервера, на просмотре — свой, курсор владельца не трогаем
  function cursorOf(ev) {
    const steps = stepsOf(ev);
    if (!steps.length) return 0;
    if (ev.readOnly && state.viewStep.has(ev.guid)) return Math.min(state.viewStep.get(ev.guid), steps.length - 1);
    const i = steps.findIndex((s) => s.id === ev.scenario.cursorStepId);
    return i === -1 ? firstOpenStep(ev) : i;
  }

  function stepProgress(ev) {
    if (!ev) return { filled: 0, total: 0 };
    return scenarioOf(ev) ? ev.scenario.progress : ev.scenarioProgress;
  }

  async function goToStep(ev, index) {
    if (!canOpenStep(ev, index)) return;
    if (ev.readOnly) {
      state.viewStep.set(ev.guid, index);
      renderScenario();
      renderStatus();
      return;
    }
    try {
      ev.scenario = await api.put(`${incPath(ev.guid)}/scenario/cursor`, { stepId: stepsOf(ev)[index].id });
    } catch (err) {
      toast(problemText(err));
    }
    renderScenario();
    renderStatus();
  }

  // Версия записи, которую видел оператор (§14.1): изменился инцидент с тех пор — сервер ответит 412
  const ifMatch = (ev) => ({ "If-Match": `"${ev.version}"` });

  // Ответ из поля шага — на сервер (автосохранение, PATCH …/scenario/answers)
  async function saveAnswers(ev, answers) {
    if (!ev || ev.readOnly) return;
    Object.assign(ev.scenario.answers, answers);
    try {
      await api.patch(`${incPath(ev.guid)}/scenario/answers`, { answers }, ifMatch(ev));
    } catch (err) {
      toast(problemText(err));
    }
    // Ответы меняют доступность «Обработан», прогресс и версию записи — карточку заново
    await loadCard();
    renderScenario();
    renderStatus();
  }

  async function flushStepAnswer(ev) {
    const root = $("scenarioRoot");
    if (!root || !ev || ev.readOnly) return;
    const el = root.querySelector("textarea[data-ans]");
    if (!el || answersOf(ev)[el.dataset.ans] === el.value) return;
    await saveAnswers(ev, { [el.dataset.ans]: el.value });
  }

  async function goNextStep(ev) {
    await flushStepAnswer(ev);
    ev = selected();
    const steps = stepsOf(ev);
    const i = cursorOf(ev);
    const next = i + 1;
    if (next < steps.length && canOpenStep(ev, next)) return goToStep(ev, next);
    if (i < steps.length - 1) {
      renderScenario();
      renderStatus();
      return;
    }
    goToStep(ev, firstOpenStep(ev));
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
    const leftMs = timer.running && timer.dueAt ? Date.parse(timer.dueAt) - Date.now() : timer.remainingMs;
    return { kind: timer.id, label: timer.label, leftMs, running: timer.running, due: timer.running ? Date.parse(timer.dueAt) : null };
  }

  function badgeView(ev) {
    return { text: t(ev.badge.template || ev.badge.label, logVars(ev.badge.vars)), cls: ev.badge.style };
  }

  const holdLabel = (id) => {
    const item = WORKFLOW.reasonCatalogs.hold.items.find((r) => r.id === id);
    return t(item ? item.label : "Причина не указана");
  };
  const resultLabel = (ev) => t(ev.closeResultLabel || "");
  // Результат полной обработки — тот, что требует обязательных шагов сценария (requiredStepSet
  // в справочнике close_result машины, §2.2), а не названный по имени
  const fullyProcessed = (resultId) => {
    const item = WORKFLOW.reasonCatalogs.close_result.items.find((i) => i.id === resultId);
    return Boolean(item && item.requiredStepSet && item.requiredStepSet !== "none");
  };

  /* ===== Действия: какие кнопки доступны, считает сервер (AvailableAction) ===== */

  const transitionDef = (id) => WORKFLOW.transitions.find((x) => x.id === id) || null;
  const navDef = (id) => WORKFLOW.navActions.items.find((x) => x.id === id) || null;
  const isNav = (id) => Boolean(navDef(id));
  const actionOf = (ev, id) => (ev && ev.actions ? ev.actions.find((a) => a.id === id) : null) || null;
  const canDo = (id, ev) => Boolean(actionOf(ev, id) && actionOf(ev, id).enabled);
  const actionWhy = (a) => (a && a.reasonKey ? say(a.reasonKey, a.reasonVars) : "");

  function actionView(a) {
    const def = a.kind === "nav" ? navDef(a.id) : transitionDef(a.id);
    return {
      id: a.id,
      label: t(a.label),
      hint: a.enabled ? t((def && def.hint) || a.label) : actionWhy(a),
      style: a.style || "outline",
      disabled: !a.enabled,
      nav: a.kind === "nav",
    };
  }

  // Действие над выборкой — по ответу сервера на /incidents/selection (режимы bulk машины, §11)
  const selectionAction = (id) => (store.selection ? store.selection.actions.find((a) => a.id === id) : null) || null;
  const inSelection = (ev) => Boolean(ev) && state.checked.size >= 2 && state.checked.has(ev.guid);

  async function updateSelection() {
    if (state.checked.size < 2) {
      store.selection = null;
      return;
    }
    store.selection = await api.post("/operator/incidents/selection", { mode: "explicit", incidentGuids: [...state.checked] });
  }

  // Кому достанется действие: выборке, группе сценария или одному инциденту (§11)
  function actionTargets(id, ev) {
    if (inSelection(ev) && selectionAction(id) && selectionAction(id).enabled) return [...state.checked];
    const tr = transitionDef(id);
    const group = ev && ev.group;
    if (group && tr && tr.bulk && tr.bulk.allowed && group.members.length >= 2) return group.members.map((m) => m.guid);
    return ev ? [ev.guid] : [];
  }

  function bulkCopy(id, list) {
    const n = list.length;
    const oneGroup = list.every((e) => e.groupId && e.groupId === list[0].groupId);
    const table = {
      transfer: {
        title: t("Передать {n} инцидентов", { n }),
        note: t("Будут переданы {n} событий одному адресату. Одна причина на всю выборку.", { n }),
        confirm: t("Передать {n}", { n }),
        toast: (form) => t("Передано: {n} → {who}", { n, who: actorName(form.targetId) }),
      },
      close: {
        title: t("Закрыть {n} инцидентов", { n }),
        note: oneGroup
          ? t("Закроются все {n} инцидентов группы.", { n })
          : t("Будут закрыты {n} событий без сценария. Одна причина на всю выборку.", { n }),
        confirm: t("Закрыть {n}", { n }),
        toast: () => t("Закрыто: {n}", { n }),
      },
      hold: {
        title: t("Отложить {n} инцидентов", { n }),
        note: t("Будут отложены {n} инцидентов группы. Одна причина на всех.", { n }),
        confirm: t("Отложить {n}", { n }),
        toast: () => t("Отложено: {n}", { n }),
      },
      release: {
        title: t("Вернуть в очередь {n} инцидентов", { n }),
        note: t("В очередь вернутся {n} инцидентов группы.", { n }),
        confirm: t("Вернуть {n}", { n }),
        toast: () => t("Возвращено в очередь: {n}", { n }),
      },
      reject: {
        title: t("Отклонить {n} передач", { n }),
        note: t("В очередь вернутся {n} инцидентов. Одна причина на всех.", { n }),
        confirm: t("Отклонить {n}", { n }),
        toast: () => t("Отклонено: {n}", { n }),
      },
    };
    return table[id] || null;
  }

  function openBulkDialog(id, ev, guids, surface) {
    if (guids.length < 2) return false;
    openDialog(id, ev, surface);
    if (!state.dialog) return false;
    state.dialog.bulkIds = guids;
    const copy = bulkCopy(id, guids.map((guid) => ({ id: guid, groupId: ev.groupGuid })));
    if (copy) {
      $("dialogTitle").textContent = copy.title;
      $("dialogNote").textContent = copy.note;
      $("dialogNote").hidden = false;
      $("dialogConfirm").textContent = copy.confirm;
    }
    return true;
  }

  async function runBulk(id, guids, form, surface) {
    let res;
    try {
      res = await api.post(`/operator/incidents/transitions/${enc(id)}/bulk`, { incidentGuids: guids, formValues: form || {}, surface });
    } catch (err) {
      toast(problemText(err));
      return false;
    }
    if (!res.succeeded.length) {
      toast(res.failed.length ? problemText({ problem: res.failed[0].problem }) : t("Действие недоступно"));
      return false;
    }
    state.checked.clear();
    store.selection = null;
    const done = res.succeeded.map((e) => ({ id: e.guid, groupId: e.groupGuid }));
    const copy = bulkCopy(id, done);
    toast(copy && copy.toast ? copy.toast(form || {}) : t("Обработано: {n}", { n: done.length }));
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
  function queueActions(ev) {
    const views = ev.actions.map(actionView);
    if (!inSelection(ev)) return views;
    const why = t("Для этой выборки действие недоступно");
    return views.map((a) => {
      if (a.nav) return a;
      const sel = selectionAction(a.id);
      return sel && sel.enabled ? a : { ...a, disabled: true, hint: why };
    });
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
    transfer: (ev) => t("{id} передан → {who}", { id: ev.number, who: actorName(addresseeOf(ev)) }),
    takeover: (ev) => t("Перехвачен {id}", { id: ev.number }),
    close: (ev) => t(fullyProcessed(ev.closeResultId) ? "{id} закрыт" : "{id} закрыт без обработки", { id: ev.number }),
    reopen: (ev) => t("{id} переоткрыт", { id: ev.number }),
  };

  async function runTransition(id, ev, form, surface) {
    if (!ev) return false;
    let res;
    try {
      res = await api.post(`${incPath(ev.guid)}/transitions/${enc(id)}`, { expectedState: ev.state, formValues: form || {}, surface }, ifMatch(ev));
    } catch (err) {
      toast(problemText(err));
      await reload();
      return false;
    }
    state.selectedId = ev.guid;
    if (TOASTS[id]) toast(TOASTS[id](res.incident));
    if (state.checked.has(ev.guid)) state.checked.clear();
    store.selection = null;
    navigate(res.navigate);
    await reload();
    return true;
  }

  /* ===== Формы переходов: строятся по формам машины (forms) и вариантам из ответа сервера ===== */

  // Форма перерыва — не переход инцидента, а состояние оператора (§12): своя, по session машины
  const breakForm = () => ({
    id: "__break__",
    title: "Перерыв",
    confirmLabel: "Уйти на перерыв",
    style: "primary",
    note: t("Активный инцидент будет отложен системой. Новые события не назначаются."),
    fields: [
      {
        name: "reasonId",
        kind: "select",
        label: "Причина перерыва",
        required: true,
        options: WORKFLOW.session.breakReasons.map((r) => ({ id: r.id, label: r.label })),
      },
    ],
  });

  // Обязательность поля: required или requiredFrom "reasonCatalog:<справочник>.<признак>" —
  // признак позиции, выбранной в поле той же формы с source "reasonCatalog:<справочник>"
  function fieldRequired(form, field, values) {
    if (!field.requiredFrom) return Boolean(field.required);
    const [catalog, attr] = field.requiredFrom.replace("reasonCatalog:", "").split(".");
    const source = form.fields.find((x) => x.source === `reasonCatalog:${catalog}`);
    const items = (WORKFLOW.reasonCatalogs[catalog] || { items: [] }).items;
    const item = source ? items.find((i) => i.id === values[source.name]) : null;
    return Boolean(item && item[attr]);
  }

  const fieldVisible = (field, values) => !field.visibleWhen || field.visibleWhen.in.includes(values[field.visibleWhen.field]);

  // Подпись адресата передачи: ФИО · роль · не на смене · предвыбор (§8.1)
  function optionLabel(field, o) {
    if (field.source !== "transferTargets") return o.disabled && o.reason ? `${t(o.label)} — ${t(o.reason)}` : t(o.label);
    const parts = [`${t(o.label)} · ${t(o.role || "")}`];
    if (o.availabilityLabel) parts.push(t(o.availabilityLabel));
    if (o.id === prefs().defaultTransferTargetId) parts.push(t("предвыбор"));
    return parts.join(" · ");
  }

  function fieldHtml(field) {
    const box = `class="field" data-field-box="${field.name}"`;
    const label = `<span data-label-for="${field.name}">${escapeHtml(t(field.label))}</span>`;
    if (field.kind === "select") {
      const options = (field.options || [])
        .map((o) => `<option value="${escapeHtml(o.id)}" ${o.disabled ? "disabled" : ""}>${escapeHtml(optionLabel(field, o))}</option>`)
        .join("");
      // Подсказка списка — пустой вариант, который нельзя выбрать обратно (§2.2)
      const empty = field.placeholder ? `<option value="" disabled>${te(field.placeholder)}</option>` : "";
      const hint =
        field.source === "transferTargets"
          ? `<p class="field-hint">${te("Предвыбор — {who}. Меняется в меню оператора.", { who: defaultTarget() })}</p>`
          : "";
      return `<label ${box}>${label}<select data-field="${field.name}">${empty}${options}</select></label>${hint}`;
    }
    return `<label ${box}>${label}<textarea rows="3" data-field="${field.name}" placeholder="${escapeHtml(
      t(field.placeholder || "")
    )}"></textarea></label>`;
  }

  function dialogValues() {
    const values = {};
    $("dialogFields")
      .querySelectorAll("[data-field]")
      .forEach((el) => (values[el.dataset.field] = el.value.trim()));
    return values;
  }

  // Видимость зависимых полей и звёздочка обязательности — по выбранному значению (§2.2)
  function refreshDialogFields() {
    const open = state.dialog;
    if (!open) return;
    const values = dialogValues();
    open.form.fields.forEach((field) => {
      const visible = fieldVisible(field, values);
      const box = $("dialogFields").querySelector(`[data-field-box="${field.name}"]`);
      if (box) box.hidden = !visible;
      const label = $("dialogFields").querySelector(`[data-label-for="${field.name}"]`);
      if (label) label.textContent = t(field.label) + (visible && fieldRequired(open.form, field, values) ? " *" : "");
    });
  }

  function showForm(open, form) {
    state.dialog = Object.assign(open, { form });
    $("dialogTitle").textContent = t(form.title);
    $("dialogNote").textContent = form.note || "";
    $("dialogNote").hidden = !form.note;
    $("dialogFields").innerHTML = form.fields.map(fieldHtml).join("");
    form.fields.forEach((field) => {
      if (field.kind !== "select") return;
      const enabled = (field.options || []).filter((o) => !o.disabled);
      // Список с placeholder заполняется сам, только если выбирать не из чего или значение задала схема
      const fallback = field.placeholder ? (enabled.length === 1 ? enabled[0].id : "") : enabled[0] && enabled[0].id;
      const pick = enabled.some((o) => o.id === field.defaultValue) ? field.defaultValue : fallback;
      const el = $("dialogFields").querySelector(`[data-field="${field.name}"]`);
      if (el) el.value = pick || "";
    });
    refreshDialogFields();
    const confirm = $("dialogConfirm");
    confirm.textContent = t(form.confirmLabel);
    confirm.className = `btn ${form.style || "primary"}`;
    $("modalDialog").hidden = false;
    ($("dialogFields").querySelector("[data-field]") || confirm).focus();
  }

  // Форма — из машины (forms), варианты полей и пояснение — из ответа сервера (fieldOptions, formNote)
  function openDialog(id, ev, surface) {
    const tr = transitionDef(id);
    if (!tr || !tr.form || !ev) return;
    const a = actionOf(ev, id);
    if (!a || !a.enabled) {
      toast(actionWhy(a) || t("Действие «{name}» недоступно в текущем состоянии", { name: t(tr.label) }));
      return;
    }
    const def = WORKFLOW.forms.find((f) => f.id === tr.form);
    const fields = def.fields.map((field) => {
      const opts = (a.fieldOptions || {})[field.name];
      return Object.assign({}, field, opts ? { options: opts.options, defaultValue: opts.defaultValue } : {});
    });
    const note = a.formNote ? say(a.formNote.key, a.formNote.vars) : "";
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
    const missing = open.form.fields.find((f) => fieldVisible(f, values) && fieldRequired(open.form, f, values) && !values[f.name]);
    if (missing) {
      toast(t("Укажите причину — поле обязательно"));
      const el = $("dialogFields").querySelector(`[data-field="${missing.name}"]`);
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

  function closeDialog() {
    state.dialog = null;
    $("modalDialog").hidden = true;
  }

  // Переход либо спрашивает подробности в форме, либо выполняется сразу.
  function trigger(id, ev, surface) {
    if (!ev) return;
    if (inSelection(ev) && !isNav(id) && !(selectionAction(id) && selectionAction(id).enabled)) {
      toast(t("Для этой выборки действие недоступно"));
      return;
    }
    if (isNav(id)) return openCard(id, ev);
    const tr = transitionDef(id);
    if (!tr) return;
    const targets = actionTargets(id, ev);
    if (targets.length >= 2) {
      if (tr.bulk && tr.bulk.createsGroup) return groupProcess();
      if (tr.form) return openBulkDialog(id, ev, targets, surface);
      return runBulk(id, targets, {}, surface);
    }
    const a = actionOf(ev, id);
    if (!a || !a.enabled) {
      toast(actionWhy(a) || t("Действие «{name}» недоступно в текущем состоянии", { name: t(tr.label) }));
      return;
    }
    if (tr.form) return openDialog(id, ev, surface);
    return runTransition(id, ev, {}, surface);
  }

  function renderEscalateDefault() {
    const select = $("escalateDefault");
    select.innerHTML = store.targets
      .map((op) => `<option value="${escapeHtml(op.id)}">${escapeHtml(actorLabel(op.id))}</option>`)
      .join("");
    select.value = prefs().defaultTransferTargetId || "";
    $("autoLevels").textContent = WORKFLOW.escalation.levels
      .map((l) => t("ур. {lvl} — {who}", { lvl: l.level, who: actorName(l.targetRef.split(":")[1]) }))
      .join(", ");
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

  // Цепочка групп от корня до той, где стоит устройство события.
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

  // В дереве — группы и устройства с открытыми инцидентами
  const openDevices = (node) => (node.devices || []).filter((d) => d.counters && d.counters.open > 0);
  const badgeText = (node) => `${(node.children || []).length}/${openDevices(node).length}`;

  function nodeMatchesQuery(node, q, isDevice) {
    if (!q) return true;
    if (t(node.name).toLowerCase().includes(q)) return true;
    if (isDevice) return false;
    return (node.children || []).some((c) => nodeMatchesQuery(c, q)) || openDevices(node).some((d) => nodeMatchesQuery(d, q, true));
  }

  // Списки фильтров: по состоянию — из машины, типы событий и устройств — справочники сервера
  function renderTypeFilters() {
    $("eventFilter").innerHTML = WORKFLOW.queueFilters
      .map((f) => `<option value="${escapeHtml(f.id)}">${te(f.label)}</option>`)
      .join("");
    $("eventFilter").value = state.filter;
    $("eventTypeFilter").innerHTML = [`<option value="all">${te("Все типы событий")}</option>`]
      .concat(store.eventTypes.map((e) => `<option value="${escapeHtml(e.guid)}">${te(e.name)}</option>`))
      .join("");
    $("eventTypeFilter").value = state.eventType;
    $("deviceTypeFilter").innerHTML = [`<option value="all">${te("Все типы устройств")}</option>`]
      .concat(store.deviceTypes.map((d) => `<option value="${escapeHtml(d.id)}">${te(d.label)}</option>`))
      .join("");
    $("deviceTypeFilter").value = state.deviceType;
  }

  function treeItemHtml(item, isDevice, level, trace, q) {
    const kids = isDevice ? [] : (item.children || []).concat(openDevices(item));
    const hasKids = kids.length > 0;
    const icon = isDevice ? DEVICE_ICON[item.typeId] || "videocam" : "folder";
    const counters = item.counters || { open: 0, critical: 0 };
    const hidden = q && !nodeMatchesQuery(item, q, isDevice);
    const forceOpen = Boolean(q && hasKids && nodeMatchesQuery(item, q, isDevice));
    const open = forceOpen || state.openGroups.has(item.guid);
    const title = t(item.description || item.name);
    const traced = trace.ids.has(item.guid) ? (item.guid === trace.leaf ? "trace trace-leaf" : "trace") : "";
    const crit = counters.critical > 0;
    return `
          <li class="tree-node ${hasKids ? "has-children" : ""} ${open ? "open" : ""} ${
            state.groupId === item.guid ? "active" : ""
          } ${traced} ${isDevice ? "is-device" : ""} ${hidden ? "hidden" : ""} level-${level}"
              data-id="${escapeHtml(item.guid)}" data-type="${isDevice ? "device" : "group"}" role="treeitem">
            <div class="node-content" title="${escapeHtml(title)}">
              <span class="toggle-icon material-symbols-outlined">chevron_right</span>
              <span class="material-symbols-outlined">${icon}</span>
              <span class="node-text">${escapeHtml(t(item.name))}</span>
              ${
                !isDevice && hasKids
                  ? `<span class="tree-badge" title="${te("Подгрупп / устройств с открытыми инцидентами")}">${badgeText(item)}</span>`
                  : ""
              }
              ${
                counters.open
                  ? `<span class="tree-ev ${crit ? "crit" : ""}" title="${te("Открытых инцидентов{crit}", {
                      crit: crit ? t(", есть критический") : "",
                    })}">${counters.open}</span>`
                  : ""
              }
            </div>
            ${hasKids ? `<ul role="group">${renderTreeHtml(item, level + 1, trace)}</ul>` : ""}
          </li>`;
  }

  function renderTreeHtml(parent, level, trace) {
    const q = state.groupQuery.trim().toLowerCase();
    const groups = parent ? parent.children || [] : store.tree;
    const devices = parent ? openDevices(parent) : [];
    return groups
      .map((g) => treeItemHtml(g, false, level, trace, q))
      .concat(devices.map((d) => treeItemHtml(d, true, level, trace, q)))
      .join("");
  }

  let tracedEventId = null;

  // Группа выбранного события подсвечивается вместе с родителями и
  // раскрывается — но только при смене события, чтобы не мешать сворачиванию
  function traceGroups() {
    const ev = selected();
    const devices = ev && ev.devices ? ev.devices.map((d) => d.guid) : [];
    const path = groupPathForDevices(devices);
    const changed = (ev ? ev.guid : null) !== tracedEventId && Boolean(ev && ev.devices);
    if (changed) {
      tracedEventId = ev.guid;
      path.forEach((id) => state.openGroups.add(id));
    }
    return { ids: new Set(path), leaf: path[path.length - 1] || null, changed };
  }

  function renderGroups() {
    const trace = traceGroups();
    const collapseBtn = $("groupsCollapseAll");
    const expanded = state.openGroups.size > 0;
    collapseBtn.querySelector(".material-symbols-outlined").textContent = expanded ? "unfold_less" : "unfold_more";
    collapseBtn.title = t(expanded ? "Свернуть все группы" : "Развернуть все группы");

    const open = store.counters.open || 0;
    const crit = store.tree.some((n) => n.counters && n.counters.critical > 0);
    $("groupsList").innerHTML = `
      <li class="tree-node tree-all ${state.groupId === "all" ? "active" : ""}" data-id="all" data-type="group">
        <div class="node-content">
          <span class="toggle-icon material-symbols-outlined"></span>
          <span class="material-symbols-outlined">folder_open</span>
          <span class="node-text">${te("Все события")}</span>
          <span class="tree-ev ${crit ? "crit" : ""}">${open}</span>
        </div>
      </li>
      ${renderTreeHtml(null, 0, trace)}
    `;
    const q = state.groupQuery.trim();
    const visible = [...$("groupsList").querySelectorAll(".tree-node")].filter(
      (n) => n.dataset.id !== "all" && !n.classList.contains("hidden")
    );
    $("groupsEmpty").hidden = !q || visible.length > 0;
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

  // Обратный отсчёт: подпись зависит от того, какой норматив идёт (§4)
  function timerChip(ev, extra) {
    const view = timerView(ev.timer);
    if (!view) {
      return ev.slaBreached ? `<span class="event-sla late breached">${te("Норматив нарушен")}</span>` : "";
    }
    const late = view.running && view.leftMs < 120000;
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
    const cls = [extra || "event-sla", view.leftMs < 120000 ? "late" : ""].filter(Boolean).join(" ");
    const hint = t("Время до предельного срока удержания по причине");
    return `<span class="${cls}" data-hold-timer="${escapeHtml(ev.guid)}" data-due="${view.due}" title="${escapeHtml(hint)}">${te(
      "Удержание"
    )} <b class="sla-t">${fmtSla(view.leftMs)}</b></span>`;
  }

  // Чекбокс на любом событии очереди; смешанные типы можно набирать вручную (§11)
  const bulkEligible = (ev) => state.checked.has(ev.guid) || state.checked.size < LIMITS.maxBulk;
  const groupChip = (ev) =>
    ev.groupGuid
      ? `<span class="chip grp" title="${te("Группа из {n} событий в одной карточке", { n: ev.groupSize })}">${te("группа")}</span>`
      : "";

  function renderEvents() {
    const { items, total } = store.page;
    $("eventsCount").textContent = String(total);
    $("clearSelectionBtn").disabled = state.checked.size === 0;
    $("selectAllBtn").disabled = !items.some((e) => !isDone(e));
    const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    const start = (state.page - 1) * PAGE_SIZE;
    renderPager(total, pages, start, items.length);
    $("eventsList").innerHTML =
      items
        .map((e) => {
          const badge = badgeView(e);
          const prog = stepProgress(e);
          const acts = queueActions(e);
          const pickable = bulkEligible(e);
          return `
          <article class="event ${state.selectedId === e.guid ? "selected" : ""}" data-id="${escapeHtml(e.guid)}">
            <input class="pick" type="checkbox" data-check="${escapeHtml(e.guid)}" aria-label="${te("Выбрать {id}", {
              id: e.number,
            })}" ${state.checked.has(e.guid) ? "checked" : ""} ${pickable ? "" : "disabled"} />
            <div class="event-pri ${e.priority}"></div>
            <div class="event-main">
              <div class="event-title">
                <strong>${te(e.eventType.name)}</strong>
                <time>${fmtTime(e.occurredAt)}</time>
              </div>
              <div class="event-sub">${escapeHtml(e.number)} · ${te(e.site)} · ${te(e.location)}</div>
              <div class="event-foot">
                <span class="badge ${badge.cls}">${escapeHtml(badge.text)}</span>
                ${
                  e.escalationLevel
                    ? `<span class="chip lvl" title="${te("Уровень эскалации")}">${te("ур. {lvl}", { lvl: e.escalationLevel })}</span>`
                    : ""
                }
                ${timerChip(e)}
                ${holdChip(e)}
                ${groupChip(e)}
                ${prog.filled ? `<span class="event-prog">${te("Сценарий {a}/{b}", { a: prog.filled, b: prog.total })}</span>` : ""}
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
        })
        .join("") || `<div class="empty">${te("Нет событий в текущем фильтре")}</div>`;
  }

  const groupMembers = (ev) => (ev && ev.group ? ev.group.members : ev ? [ev] : []);

  function renderWorkHeader(ev) {
    if (!ev) {
      $("workTitle").textContent = t("Обработка");
      return;
    }
    const n = groupMembers(ev).length;
    $("workTitle").textContent =
      n > 1 ? `${ev.number} · ${t(ev.eventType.name)} · ${t("группа {n}", { n })}` : `${ev.number} · ${t(ev.eventType.name)}`;
  }

  function workNote(ev) {
    const mates = groupMembers(ev);
    if (mates.length > 1 && isMine(ev) && ev.state === "in_progress") {
      const ex = ev.group.exclude;
      return `<div class="work-note">${escapeHtml(
        t("В работе группа из {n}: {ids}. Один сценарий на всех.", {
          n: mates.length,
          ids: mates.map((e) => e.number).join(", "),
        })
      )} <button type="button" class="btn ghost small" data-exclude="${escapeHtml(ev.guid)}" ${
        ex.enabled ? "" : `aria-disabled="true" title="${escapeHtml(say(ex.reasonKey, ex.reasonVars))}"`
      }>${te("Исключить из группы")}</button></div>`;
    }
    if (isDone(ev)) {
      const why =
        ev.closeResultId && !fullyProcessed(ev.closeResultId) ? t("Инцидент закрыт: {why}.", { why: resultLabel(ev) }) : t("Инцидент закрыт.");
      const more = canDo("reopen", ev) ? t("Доступно переоткрытие.") : t("Карточка доступна только для просмотра.");
      return `<div class="work-note ok">${escapeHtml(`${why} ${more}`)}</div>`;
    }
    if (ev.state === "pending_acceptance" && isTarget(ev)) {
      return `<div class="work-note inbox">${te("Инцидент адресован вам, уровень {lvl}. Примите его или отклоните с указанием причины.", {
        lvl: ev.escalationLevel,
      })}</div>`;
    }
    if (!isMine(ev)) {
      const rights = canDo("takeover", ev)
        ? t("при необходимости перехватите")
        : canDo("transfer", ev)
          ? t("перехват недоступен по правам, можно передать")
          : t("перехват и передача недоступны по правам");
      const holder =
        ev.state === "pending_acceptance"
          ? t("Инцидент ожидает принятия: {who}.", { who: actorName(addresseeOf(ev)) })
          : t("Инцидент обрабатывает {who}.", { who: actorName(ev.owner) });
      // Имя вида «Петрова М.» уже кончается точкой — вторую не ставим
      const sentence = holder.replace(/\.\.$/, ".");
      return `<div class="work-note">${escapeHtml(`${sentence} ${t("Просмотр без изменений")} — ${rights}.`)}</div>`;
    }
    if (ev.state === "on_hold") {
      return `<div class="work-note">${te("Инцидент отложен: {why}. Норматив закрытия приостановлен.", {
        why: holdLabel(ev.holdReasonId),
      })}</div>`;
    }
    if (onBreak()) {
      return `<div class="work-note">${te("Вы на перерыве — изменения по сценарию недоступны.")}</div>`;
    }
    return "";
  }

  function renderScenario() {
    const ev = selected();
    const root = $("scenarioRoot");
    if (!ev || !ev.scenario) {
      root.innerHTML = `<div class="empty">${te("Инцидент не выбран")}</div>`;
      return;
    }
    const steps = stepsOf(ev);
    const prog = stepProgress(ev);
    const editable = !ev.readOnly;
    const acts = cardActions(ev);

    const i = cursorOf(ev);
    const step = steps[i];
    const last = i === steps.length - 1;
    const canNext = isStepValid(ev, step);
    // «Закрыть инцидент» в конце сценария — когда доступен результат полной обработки (§2.2)
    const close = actionOf(ev, "close");
    const results = close && close.fieldOptions && close.fieldOptions.resultId ? close.fieldOptions.resultId.options : [];
    const canClose = editable && Boolean(close && close.enabled) && results.some((r) => fullyProcessed(r.id) && !r.disabled);
    const incomplete = steps.findIndex((s) => stepRequired(s) && !isStepValid(ev, s));

    root.innerHTML = `
      <div class="work-doc">
        <div class="work-top">
          ${renderIncidentHead(ev, prog)}
          ${workNote(ev)}
          <ol class="crumbs ${editable ? "live" : ""}" aria-label="${te("Шаги сценария")}">
          ${steps
            .map((s, idx) => {
              const open = canOpenStep(ev, idx);
              const current = idx === i;
              const answer = stepAnswerText(ev, s);
              const nav = open && !current;
              return `
                <li class="crumb ${current ? "current" : ""} ${answer ? "done" : ""} ${open ? "" : "locked"} ${nav ? "nav" : ""}" ${
                  current ? 'aria-current="step"' : ""
                } ${nav ? `data-crumb="${idx}" role="button" tabindex="0"` : ""} title="${te(s.title)}">
                  <span class="crumb-track">
                    <span class="crumb-n">${idx + 1}</span>
                    <span class="crumb-line" aria-hidden="true"></span>
                  </span>
                  <span class="crumb-body">
                    <span class="crumb-name">${te(stepShort(s))}</span>
                    ${answer && !current ? `<span class="crumb-ans">${te(answer)}</span>` : ""}
                  </span>
                </li>
              `;
            })
            .join("")}
          </ol>
        </div>
        <div class="work-step">
          <div class="step-card">
            <div class="step-h">
              <strong>${te(step.title)}</strong>
              <span>${te("{i} из {n}", { i: i + 1, n: steps.length })}${stepRequired(step) ? "" : ` · ${te("необязательно")}`}</span>
            </div>
            ${renderStepControl(step, ev, editable)}
          </div>
        </div>
        <div class="work-bottom">
          ${
            acts.length
              ? `<div class="work-acts">${acts
                  .map(
                    (a) =>
                      `<button type="button" class="btn ${a.style}" data-do="${a.id}" data-ev="${escapeHtml(ev.guid)}" title="${escapeHtml(
                        a.hint
                      )}" ${a.disabled ? 'aria-disabled="true"' : ""}>${escapeHtml(a.label)}</button>`
                  )
                  .join("")}</div>`
              : ""
          }
          <div class="scenario-actions">
            <button type="button" class="btn ghost" id="stepBack" ${i === 0 ? "disabled" : ""}>${te("Назад")}</button>
            <div class="scenario-actions-end">
              ${
                editable
                  ? last && canClose
                    ? `<button type="button" class="btn primary" data-do="close" data-ev="${escapeHtml(ev.guid)}">${te("Закрыть инцидент")}</button>`
                    : `<button type="button" class="btn primary" id="stepNext" ${canNext ? "" : "disabled"}>${te(
                        last ? "К незаполненным" : "Далее"
                      )}</button>`
                  : !last && canOpenStep(ev, i + 1)
                    ? `<button type="button" class="btn outline" id="stepNext">${te("Далее")}</button>`
                    : ""
              }
            </div>
          </div>
          ${
            last && editable && !canClose && incomplete !== -1
              ? `<p class="step-hint">${te("Сначала шаг {n}: {name}", { n: incomplete + 1, name: t(stepShort(steps[incomplete])) })}</p>`
              : ""
          }
          ${renderLog(ev)}
        </div>
      </div>
    `;
  }

  function renderLog(ev) {
    const items = (ev.journal || []).slice(-4);
    if (!items.length) return "";
    return `
      <div class="log">
        <h4>${te("Журнал")}</h4>
        <ul>
          ${items
            .map((l) => `<li><b>${escapeHtml(fmtTime(l.at))}</b> · ${escapeHtml(actorName(l.actor))} — ${escapeHtml(journalText(l))}</li>`)
            .join("")}
        </ul>
      </div>
    `;
  }

  function renderIncidentHead(ev, prog) {
    const badge = badgeView(ev);
    return `
      <div class="incident-head">
        <div class="incident-kicker">
          <span>${escapeHtml(ev.number)}</span>
          <span class="badge ${badge.cls}">${escapeHtml(badge.text)}</span>
          ${ev.escalationLevel ? `<span class="chip lvl">${te("ур. {lvl}", { lvl: ev.escalationLevel })}</span>` : ""}
          ${timerChip(ev, "sla")}
          ${holdChip(ev, "sla")}
          ${
            ev.groupGuid
              ? `<span class="chip grp" title="${te("Группа из {n} событий в одной карточке", { n: ev.groupSize })}">${te("группа {n}", {
                  n: ev.groupSize,
                })}</span>`
              : ""
          }
        </div>
        <h3>${te(ev.eventType.name)}</h3>
        <div class="incident-meta">${te(ev.site)} · ${te(ev.location)}</div>
        <div class="progress"><i style="width:${prog.total ? Math.round((prog.filled / prog.total) * 100) : 0}%"></i></div>
      </div>
    `;
  }

  function renderStepControl(step, ev, enabled) {
    const dis = enabled ? "" : "disabled";
    const kind = stepKind(step);
    const answers = answersOf(ev);
    const view = step.view || {};
    if (kind === "checkbox") {
      const on = answers[step.id] === true;
      return `
        <button type="button" class="confirm-btn ${on ? "on" : ""}" data-confirm="${step.id}" ${dis}>
          <span class="material-symbols-outlined">${on ? "check_circle" : "radio_button_unchecked"}</span>
          ${te(on ? "Подтверждено" : "Подтвердить")}
        </button>
      `;
    }
    if (kind === "radio") {
      return `<div class="radios">${view.options
        .map(
          (o) =>
            `<label class="${answers[step.id] === o ? "picked" : ""}"><input type="radio" name="${step.id}" data-ans="${step.id}" value="${escapeHtml(
              o
            )}" ${answers[step.id] === o ? "checked" : ""} ${dis} /> ${te(o)}</label>`
        )
        .join("")}</div>`;
    }
    if (kind === "combo") {
      return `<select data-ans="${step.id}" ${dis}><option value="">${te("Выберите…")}</option>${view.options
        .map((o) => `<option value="${escapeHtml(o)}" ${answers[step.id] === o ? "selected" : ""}>${te(o)}</option>`)
        .join("")}</select>`;
    }
    if (kind === "edit") {
      return `<textarea rows="4" data-ans="${step.id}" placeholder="${te(view.placeholder || "Можно пропустить")}" ${dis}>${escapeHtml(
        answers[step.id] || ""
      )}</textarea>`;
    }
    if (kind === "macros") {
      return `<div class="macro-row">${view.buttons
        .map((b) => {
          const on = launchedOf(ev).includes(b);
          return `<button type="button" class="btn ${on ? "ok" : ""}" data-macro="${escapeHtml(b)}" ${dis}>${on ? `${te("Запущено")} · ` : ""}${te(b)}</button>`;
        })
        .join("")}</div>`;
    }
    return "";
  }

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
        <button type="button" class="cam-nav prev" data-cam-step="-1" title="${te("Предыдущая камера (←)")}" aria-label="${te(
              "Предыдущая камера"
            )}">
          <span class="material-symbols-outlined">chevron_left</span>
        </button>
        <button type="button" class="cam-nav next" data-cam-step="1" title="${te("Следующая камера (→)")}" aria-label="${te(
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
    $("statusQueue").textContent = t("В очереди: {n} · у меня: {a} из {max}, отложено: {h}", {
      n: store.counters.open || 0,
      a: usage.activeCount,
      max: LIMITS.maxActive,
      h: usage.onHoldCount,
    });
    if (!ev) {
      $("statusIncident").textContent = t("Очередь ожидает выбора события");
      $("statusSteps").textContent = "";
      $("statusSla").textContent = "";
      return;
    }
    const prog = stepProgress(ev);
    const badge = badgeView(ev);
    $("statusIncident").textContent =
      state.mode === "work" ? t("Карточка {id} · {badge}", { id: ev.number, badge: badge.text }) : `${ev.number} · ${badge.text}`;
    $("statusSteps").textContent =
      state.mode === "work" && ev.scenario
        ? t("Шаг {i} из {n}", { i: cursorOf(ev) + 1, n: prog.total })
        : t("Сценарий {a}/{b}", { a: prog.filled, b: prog.total });
    $("statusSla").textContent = statusTimerText(ev);
  }

  function statusTimerText(ev) {
    const view = timerView(ev.timer);
    if (!view) return ev.slaBreached ? t("Норматив нарушен") : "";
    if (!view.running) return t("{label} приостановлен: {time}", { label: t(view.label), time: fmtSla(view.leftMs) });
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
    renderGroups();
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
    $("navQueueCount").textContent = String(store.counters.open || 0);
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
      t("Свернуть видеомонитор (Esc)"),
      t("Развернуть видеомонитор на всю рабочую область")
    );
    syncToggle($("mapFull"), state.full === "map", "close_fullscreen", "open_in_full", t("Свернуть карту (Esc)"), t("Развернуть карту на всю рабочую область"));
    $("videoFull").disabled = mode === "map";
    $("mapFull").disabled = mode === "video";
    // Состояние оператора — отдельная машина состояний (§12.1): значение отдаёт сервер, подпись — машина
    const agent = store.session ? store.session.agentState : "ready";
    const agentDef = WORKFLOW.session.states.find((s) => s.id === agent) || {};
    $("dutyBadge").textContent = t(agentDef.label || agent);
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
      if (actionWhy(a)) toast(actionWhy(a));
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
      toast(t("Нет права уходить на перерыв"));
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
      toast(problemText(err));
    }
    await reload();
  }

  // Выход из МИ (§12.1): с подтверждением — свои в работе и отложенные сервер вернёт в очередь,
  // адресованные лично — дежурной группе или в очередь (owner_signed_out, addressee_signed_out_*).
  // Считаются инциденты фильтра «Мои», а не единицы лимита: группа сценария — не один (BUG-25)
  const signOutForm = (mine) => {
    const count = (stateId) => mine.filter((e) => e.state === stateId).length;
    return {
      id: "__signout__",
      title: "Выйти из МИ",
      confirmLabel: "Выйти",
      style: "danger",
      note: t("В работе: {active}, отложено: {held} — они вернутся в очередь. Адресованные вам и не принятые уйдут вашей дежурной группе или в очередь.", {
        active: count("in_progress"),
        held: count("on_hold"),
      }),
      fields: [],
    };
  };

  async function setPresence(agentState, done) {
    try {
      await api.put("/operator/session/agent-state", { agentState });
      toast(t(done));
    } catch (err) {
      toast(problemText(err));
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
      toast(t("Перерыв. Новые события не назначаются"));
    } catch (err) {
      toast(problemText(err));
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
  function requery() {
    state.page = 1;
    state.focus = true;
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
    $("backToQueue").addEventListener("click", () => backToQueue());
    $("eventFilter").addEventListener("change", (e) => {
      state.filter = e.target.value;
      requery();
    });
    [
      ["eventTypeFilter", "eventType"],
      ["deviceTypeFilter", "deviceType"],
    ].forEach(([id, key]) =>
      $(id).addEventListener("change", (e) => {
        state[key] = e.target.value;
        requery();
      })
    );
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
      renderGroups();
    });
    $("groupsList").addEventListener("click", (e) => {
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
      state.groupId = id;
      if (narrowQuery.matches) state.groupsOn = false;
      requery();
    });
    $("eventsList").addEventListener("click", async (e) => {
      const check = e.target.closest("[data-check]");
      if (check) {
        const id = check.dataset.check;
        if (state.checked.has(id)) state.checked.delete(id);
        else if (state.checked.size >= LIMITS.maxBulk) {
          toast(t("Не больше {max} событий в выборке", { max: LIMITS.maxBulk }));
          return;
        } else state.checked.add(id);
        await updateSelection();
        renderEvents();
        return;
      }
      const act = e.target.closest("[data-do]");
      if (act && explainIfOff(act)) return;
      if (act) {
        trigger(act.dataset.do, store.page.items.find((x) => x.guid === act.dataset.ev), "queue");
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
    $("scenarioRoot").addEventListener("input", (e) => {
      const ev = selected();
      if (!ev || ev.readOnly) return;
      const el = e.target.closest("textarea[data-ans]");
      if (!el) return;
      ev.scenario.answers[el.dataset.ans] = el.value;
      const next = $("stepNext");
      const step = stepsOf(ev)[cursorOf(ev)];
      if (next && step) next.disabled = !isStepValid(ev, step);
    });
    $("scenarioRoot").addEventListener("change", (e) => {
      const ev = selected();
      if (!ev || ev.readOnly) return;
      const el = e.target.closest("[data-ans]");
      if (!el) return;
      saveAnswers(ev, { [el.dataset.ans]: el.type === "checkbox" ? el.checked : el.value });
    });
    $("scenarioRoot").addEventListener("keydown", (e) => {
      if (e.key !== "Enter" && e.key !== " ") return;
      const crumb = e.target.closest("[data-crumb]");
      if (!crumb) return;
      e.preventDefault();
      e.stopPropagation();
      crumb.click();
    });
    $("scenarioRoot").addEventListener("click", async (e) => {
      const ev = selected();
      if (!ev) return;
      const exclude = e.target.closest("[data-exclude]");
      if (exclude && explainIfOff(exclude)) return;
      if (exclude) {
        try {
          await api.del(`/operator/incident-groups/${enc(ev.groupGuid)}/members/${enc(ev.guid)}`);
          toast(t("{id} исключён из группы", { id: ev.number }));
        } catch (err) {
          toast(problemText(err));
        }
        await reload();
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
        goToStep(ev, Number(crumb.dataset.crumb));
        return;
      }
      if (e.target.closest("#stepBack")) {
        goToStep(ev, cursorOf(ev) - 1);
        return;
      }
      if (e.target.closest("#stepNext")) {
        goNextStep(ev);
        return;
      }
      const confirm = e.target.closest("[data-confirm]");
      if (confirm && !ev.readOnly) {
        const id = confirm.dataset.confirm;
        saveAnswers(ev, { [id]: answersOf(ev)[id] !== true });
        return;
      }
      const macro = e.target.closest("[data-macro]");
      if (macro) {
        const name = macro.dataset.macro;
        try {
          await api.post(`${incPath(ev.guid)}/macros/${enc(name)}`, { stepId: stepsOf(ev)[cursorOf(ev)].id });
          toast(t("Макрос: {name}", { name: t(name) }));
        } catch (err) {
          toast(problemText(err));
        }
        await loadCard();
        renderScenario();
      }
    });
    $("selectAllBtn").addEventListener("click", () => selectAllVisible());
    $("selectSimilarBtn").addEventListener("click", () => selectSimilar());
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
        .get("/operator/incidents", { filter: "mine", pageSize: 1000 })
        .then((page) => showForm({ id: "__signout__" }, signOutForm(page.items)))
        .catch((err) => toast(problemText(err)));
    });
    $("signInBtn").addEventListener("click", () => setPresence("ready", "Вы вошли в МИ"));
    // Меню справки — по открытому инциденту: ссылки его площадки (§7)
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
    $("hotkeysBtn").addEventListener("click", () => {
      closeMenus();
      $("modalHotkeys").hidden = false;
    });
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
    $("escalateDefault").addEventListener("change", async (e) => {
      try {
        await api.patch("/operator/session/preferences", { defaultTransferTargetId: e.target.value });
      } catch (err) {
        toast(problemText(err));
      }
      store.session = await api.get("/operator/session");
      toast(t("Предвыбор адресата: {who}", { who: defaultTarget() }));
    });
    document.querySelectorAll("[data-close]").forEach((btn) => {
      btn.addEventListener("click", () => {
        if (btn.dataset.close === "modalDialog") closeDialog();
        else $(btn.dataset.close).hidden = true;
      });
    });
    $("dialogConfirm").addEventListener("click", submitDialog);
    $("dialogFields").addEventListener("change", refreshDialogFields);
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
      toast(problemText(err));
      return;
    }
    if (!res.incidentGuids.length) {
      toast(t(body.mode === "same_type_new" ? "Нет новых событий для выборки" : "Нет событий для выборки"));
      return;
    }
    state.checked = new Set(res.incidentGuids);
    state.selectedId = res.incidentGuids[0];
    toast(message(res));
    await updateSelection();
    await reload();
  }

  function selectAllVisible() {
    return pickSelection({ mode: "all_in_filter" }, (res) =>
      res.truncated
        ? t("Выбрано {n} из {max}", { n: res.incidentGuids.length, max: LIMITS.maxBulk })
        : t("Выбрано событий: {n}", { n: res.incidentGuids.length })
    );
  }

  function selectSimilar() {
    const anchor = [...state.checked][0] || state.selectedId;
    return pickSelection({ mode: "same_type_new", anchorIncidentGuid: anchor }, (res) =>
      t("Выбрано однотипных: {n}", { n: res.incidentGuids.length })
    );
  }

  function clearSelection() {
    state.checked.clear();
    store.selection = null;
    renderEvents();
  }

  // «Обработать как одно» (§11): группу создаёт сервер по grouping машины
  async function groupProcess() {
    if (state.checked.size < 2) return;
    let group;
    try {
      group = await api.post("/operator/incident-groups", { incidentGuids: [...state.checked] });
    } catch (err) {
      toast(problemText(err));
      return;
    }
    state.selectedId = group.members[0].guid;
    state.checked.clear();
    store.selection = null;
    toast(t("Группа из {n} событий в одной карточке", { n: group.members.length }));
    state.mode = "work";
    state.mobileView = "card";
    await reload();
  }

  function onKey(e) {
    const hotkey = WORKFLOW.hotkeys.find((h) => h.key === keyName(e));
    if (!hotkey) return;
    const target = e.target instanceof Element ? e.target : null;
    const inInput = target && target.matches("input, textarea, select");
    if (inInput && !hotkey.worksInInput) return;
    const onControl = target && target.matches("button, a[href], summary, [role='button']");
    if (onControl && (e.key === "Enter" || e.key === " ")) return;
    const modalOpen = Boolean(state.dialog) || Boolean(document.querySelector(".modal:not([hidden])"));
    if (modalOpen && !hotkey.worksInModal) return;
    runHotkey(hotkey, e);
  }

  // Esc разбирается по цепочке машины: форма → полный экран → панель групп → к очереди (§13.1).
  // Срабатывает первое звено, которому есть что закрыть.

  const ESCAPE_STEPS = {
    close_form: () => {
      const openMenu = closeMenus();
      if (openMenu) {
        openMenu.querySelector("[aria-haspopup]").focus();
        return true;
      }
      if (state.dialog) {
        closeDialog();
        return true;
      }
      const openModal = document.querySelector(".modal:not([hidden])");
      if (!openModal) return false;
      openModal.hidden = true;
      return true;
    },
    exit_fullscreen: () => {
      if (!state.full) return false;
      toggleFull(state.full);
      return true;
    },
    close_groups_panel: () => {
      if (!(state.groupsOn && narrowQuery.matches)) return false;
      closeDrawer();
      return true;
    },
    back_to_queue: () => {
      if (state.mode !== "work") return false;
      backToQueue();
      return true;
    },
  };

  // Справка по клавишам — из машины: подряд идущие клавиши с одной подписью — одна строка
  // («←» «→», «1–4»). Внизу — какие клавиши работают в полях ввода и при открытом окне (§13)

  const KEY_GLYPH = { ArrowLeft: "←", ArrowRight: "→" };
  const kbdHtml = (key) =>
    key
      .split("+")
      .map((part) => `<kbd>${escapeHtml(KEY_GLYPH[part] || part)}</kbd>`)
      .join("+");
  /* ===== Меню справки (§7, RULE-49): справочник ссылок — общие и площадки открытого инцидента ===== */

  // Демо-адреса набора открывают окна прототипа; настоящие — новой вкладкой
  const DEMO_DOCS = { regulation: "modalRegulation", contacts: "modalContacts", evacuation: "modalEvacuation", emergency: "modalEmergency" };
  async function renderHelpLinks() {
    const ev = selected();
    const links = await api.get("/operator/reference/help-links", ev && ev.site ? { site: ev.site } : {}).catch(() => []);
    const item = (l) => {
      const hotkey = WORKFLOW.hotkeys.find((h) => h.action === `docs:${l.id}`);
      const demo = /^demo:doc\/(.+)$/.exec(l.url);
      const target = demo ? `data-doc="${DEMO_DOCS[demo[1]] || ""}"` : `data-url="${escapeHtml(l.url)}"`;
      return `<button type="button" class="menu-item" role="menuitem" ${target}>
        <span class="material-symbols-outlined">${escapeHtml(l.icon || (l.kind === "file" ? "description" : "public"))}</span>
        <span data-i18n-skip>${escapeHtml(l.title)}</span>${hotkey ? kbdHtml(hotkey.key) : ""}
      </button>`;
    };
    const common = links.filter((l) => !l.site);
    const site = links.filter((l) => l.site);
    $("helpLinks").innerHTML =
      common.map(item).join("") +
      (site.length ? `<div class="menu-sep"></div><div class="menu-label" data-i18n-skip>${escapeHtml(site[0].site)}</div>${site.map(item).join("")}` : "");
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
  // Машинное значение — подписью из машины (adminSettings.valueLabels), иначе как есть
  const word = (key) => te((WORKFLOW.adminSettings.valueLabels || {})[key] || key);
  function personName(id) {
    if (store.session && id === store.session.operator.guid) return store.session.operator.name;
    const group = (adminState.data.duty || []).find((g) => g.id === id);
    const target = targetById(id);
    return (group && group.name) || (target && target.name) || id;
  }
  function fmtSetting(v, key, seconds, values) {
    const sec = seconds || /Sec$/.test(key);
    if (v == null) return "—";
    if (values && typeof v === "string" && values[v]) return te(values[v]);
    if (typeof v === "boolean") return te(v ? "да" : "нет");
    if (typeof v === "number") return /Min(utes)?$/.test(key) ? fmtDuration(v * 60) : sec ? fmtDuration(v) : String(v);
    if (typeof v === "string") return /^(user|group):/.test(v) ? asData(personName(v.split(":")[1])) : te(v);
    if (Array.isArray(v)) {
      if (!v.length) return te("нет");
      return v
        .map((x) => {
          if (typeof x !== "object") return fmtSetting(x, key, sec);
          if (x.key && x.label) return `${kbdHtml(x.key)} ${te(x.label)}`;
          if (x.level != null) return `${te("Уровень {n}", { n: x.level })}: ${asData(personName(String(x.targetRef).split(":")[1]))}, ${te("реакция {time}", { time: fmtDuration(x.reactionSec) })}`;
          if (x.sec != null) return `${Object.entries(x).filter(([k]) => k !== "sec").map(([k, val]) => `${word(k)} = ${word(String(val))}`).join(", ")}: ${fmtDuration(x.sec)}`;
          const limit = x.maxMinutes != null ? ` (${fmtDuration(x.maxMinutes * 60)})` : "";
          return te(x.label || x.id) + limit;
        })
        .join("<br>");
    }
    return Object.entries(v)
      .filter(([k]) => !k.startsWith("$"))
      .map(([k, val]) => `${word(k)}: ${fmtSetting(val, k, sec)}`)
      .join("<br>");
  }
  const sourcePath = (tab) => tab.source.split(" ")[1];
  // Названия и имена — данные, они не переводятся (§14.9)
  const asData = (text) => `<span data-i18n-skip>${escapeHtml(text)}</span>`;
  async function openAdmin() {
    adminState.data.duty = await api.get("/operator/admin/duty-groups").catch(() => []);
    adminState.tab = adminState.tab || WORKFLOW.adminSettings.tabs[0].id;
    $("modalAdmin").hidden = false;
    await renderAdmin();
  }
  async function renderAdmin() {
    const tabs = WORKFLOW.adminSettings.tabs;
    const tab = tabs.find((x) => x.id === adminState.tab) || tabs[0];
    $("adminTabs").innerHTML = tabs
      .map((x) => `<button type="button" role="tab" data-admin-tab="${x.id}" class="${x.id === tab.id ? "active" : ""}" aria-selected="${x.id === tab.id}">${te(x.label)}</button>`)
      .join("");
    $("adminNote").textContent = `${t("Правила")}: ${tab.rules}` + (tab.what ? `. ${t(tab.what)}` : "");
    const table = $("adminTable");
    table.className = tab.items ? "doc-table settings" : "doc-table";
    if (tab.items) {
      table.innerHTML =
        `<thead><tr><th>${te("Настройка")}</th><th>${te("Сейчас")}</th></tr></thead><tbody>` +
        tab.items
          .map((item) => `<tr><td>${te(item.label)}<span class="what">${te(item.what)}</span></td><td>${fmtSetting(settingAt(item.path), item.path.split(".").pop(), item.path.startsWith("timers."), item.values)}</td></tr>`)
          .join("") +
        "</tbody>";
      return;
    }
    if (!tab.source) {
      table.innerHTML = `<tbody><tr><td>${te("В прототипе запроса нет: эти данные МИ ещё не вынесены в контракт")}</td></tr></tbody>`;
      return;
    }
    const data = await api.get(sourcePath(tab)).catch((err) => ({ error: problemText(err) }));
    if (data.error) {
      table.innerHTML = `<tbody><tr><td>${escapeHtml(data.error)}</td></tr></tbody>`;
      return;
    }
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
        ["Ссылка", "Вид", "Площадка"],
        data.map((l) => `<tr><td>${asData(l.title)}<span class="what">${escapeHtml(l.url)}</span></td><td>${te(l.kind === "file" ? "файл" : "веб-страница")}</td><td>${l.site ? asData(l.site) : te("общая")}</td></tr>`),
      ],
      "/operator/admin/camera-links": () => [
        ["Устройство", "Камеры по порядку"],
        data.map((l) => `<tr><td>${asData(l.device.name)}</td><td>${asData(l.cameras.map((c) => c.name).join(", ") || "—")}</td></tr>`),
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
    table.innerHTML = `<thead><tr>${head.map((h) => `<th>${te(h)}</th>`).join("")}</tr></thead><tbody>${body.join("")}</tbody>`;
  }

  function renderHotkeysHelp() {
    const rows = [];
    WORKFLOW.hotkeys.forEach((h) => {
      const last = rows[rows.length - 1];
      if (last && last.label === h.label) last.keys.push(h.key);
      else rows.push({ label: h.label, keys: [h.key] });
    });
    $("hotkeysTable").innerHTML = rows
      .map((r) => {
        const digits = r.keys.length > 2 && r.keys.every((k) => /^\d$/.test(k));
        const keys = digits ? `${kbdHtml(r.keys[0])}–${kbdHtml(r.keys[r.keys.length - 1])}` : r.keys.map(kbdHtml).join(" ");
        return `<tr><td>${keys}</td><td>${te(r.label)}</td></tr>`;
      })
      .join("");
    const list = (pick) => WORKFLOW.hotkeys.filter(pick).map((h) => h.key).join(", ");
    $("hotkeysNote").textContent = [
      t("В полях ввода работают только {keys}.", { keys: list((h) => h.worksInInput) }),
      t("При открытом окне — только {keys}.", { keys: list((h) => h.worksInModal) }),
      t("Набор можно будет задавать «под себя» в настройках оператора."),
    ].join(" ");
  }

  // Имя клавиши в записи машины: «N», «Shift+A», «Ctrl+K», «Enter», «ArrowLeft», «?», «Esc».
  // Shift пишется только у букв: «?» набирается с Shift, но это своя клавиша

  function keyName(e) {
    const base = e.key === "Escape" ? "Esc" : e.key.length === 1 ? e.key.toUpperCase() : e.key;
    if (e.ctrlKey || e.metaKey) return `Ctrl+${base}`;
    return e.shiftKey && /^[A-ZА-ЯЁ]$/.test(base) ? `Shift+${base}` : base;
  }

  // Горячие клавиши — из машины (§13): клавиша только вызывает действие, право проверяет переход

  // Горячие клавиши — из машины (§13): клавиша только вызывает действие, право проверяет сервер
  async function runHotkey(hotkey, e) {
    const [kind, name] = hotkey.action.split(":");
    const ev = selected();
    const surface = state.mode === "work" ? "card" : "queue";
    if (hotkey.action === "escape_chain") {
      hotkey.chain.some((stepId) => ESCAPE_STEPS[stepId] && ESCAPE_STEPS[stepId]());
      return;
    }
    if (kind === "docs" && name === "regulation") {
      e.preventDefault();
      closeMenus();
      showModal("modalRegulation");
      return;
    }
    if (kind === "transition") {
      if (hotkey.scope === "next_new") {
        const open = await api.get("/operator/incidents", { filter: "open", pageSize: 1000 });
        const next = open.items.find((x) => canDo(name, x));
        if (next) trigger(name, next, "queue");
        return;
      }
      trigger(name, ev, surface);
    } else if (kind === "form" && name === "open" && state.mode === "work") {
      trigger(hotkey.action.split(":")[2], ev, "card");
    } else if (kind === "group") {
      groupProcess();
    } else if (kind === "selection") {
      e.preventDefault();
      if (name === "same_type") selectSimilar();
      else if (state.checked.size) clearSelection();
    } else if (kind === "session") {
      $("breakBtn").click();
    } else if (kind === "docs" && name === "hotkeys") {
      $("modalHotkeys").hidden = !$("modalHotkeys").hidden;
    } else if (kind === "media") {
      if (name === "camera_prev") stepCamera(-1);
      else if (name === "camera_next") stepCamera(1);
      else if (name === "camera_select") {
        const cam = camerasOf(cardOfSelected())[hotkey.args[0] - 1];
        if (cam) {
          state.activeCam = cam;
          renderVideo();
          renderMap();
        }
      }
    }
  }

  // Часы и обратный отсчёт — на клиенте по меткам времени (§4). Дедлайны ведёт сервер:
  // что сработало, он сообщает в потоке событий
  setInterval(() => {
    const stamp = nowStamp();
    $("clock").textContent = stamp;
    $("clock").dateTime = stamp;
    document.querySelectorAll("[data-due]").forEach((el) => {
      const left = Number(el.dataset.due) - Date.now();
      el.querySelector(".sla-t").textContent = fmtSla(left);
      el.classList.toggle("late", left < 120000);
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
    if (mine && msg.type !== "incident.card_evicted") return;
    // Доступ к объекту пропал (§5): данных инцидента больше нет — только номер; карточка закрывается
    if (msg.type === "incident.access_lost") {
      toast(t("{id} вам больше не доступен: изменились группы доступа", { id: msg.payload.number }));
      if (state.selectedId === msg.incidentGuid) {
        state.selectedId = null;
        return backToQueue();
      }
    } else if (msg.type === "incident.alert") {
      // Алерт получателю алертов (§9): что случилось — подпись перехода из машины
      const tr = transitionDef(tid);
      toast(t("Алерт: {id} — {what}", { id, what: tr ? t(tr.label) : tid }));
    } else if (msg.type === "incident.auto_escalated") {
      toast(t("Автоэскалация {id} → {who}", { id, who: who(msg.payload.addressee) }));
    } else if (tid === "claim") {
      toast(t("{id} взял в работу {who}", { id, who: who(msg.actor) }));
    } else if (tid === "transfer" && msg.payload.addressee && msg.payload.addressee.id === store.session.operator.guid) {
      toast(t("{who} передал {id} вам", { who: who(msg.actor), id }));
    } else if (tid === "system_hold_idle") {
      toast(t("Нет связи с {who} — {id} отложен системой", { who: who(msg.payload.previousOwner), id }));
    }
    reload();
  }

  // Загрузка: схема, сессия, справочники — потом первая отрисовка
  async function boot() {
    WORKFLOW = await api.get("/operator/workflow/active");
    STATES = Object.fromEntries(WORKFLOW.states.map((s) => [s.id, s]));
    LIMITS = WORKFLOW.limits;
    setInterval(() => heartbeat(true), WORKFLOW.session.heartbeatSec * 1000);
    const [eventTypes, deviceTypes, targets] = await Promise.all([
      api.get("/operator/reference/event-types"),
      api.get("/operator/reference/device-types"),
      api.get("/operator/transfer-targets"),
    ]);
    Object.assign(store, { eventTypes, deviceTypes, targets });
    collectStatic();
    bind();
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
    api.subscribe(onServerEvent);
    renderHelpLinks();
  }

  boot();
})();
