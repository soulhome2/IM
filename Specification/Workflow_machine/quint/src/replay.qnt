  /* ===== Доступность для сверки ядра (PROC-78) =====
     Только для tools/check_quint_replay.mjs: часть приклеивается к im.qnt во временной копии и в основную модель не
     входит — её прогоны не замедляются. avail после шага — что было доступно до него: кто, какой ручной переход, с
     каким инцидентом, на какой поверхности. Форма пустая — как кнопка у исполнителя (engine.availability): условия,
     которые смотрят в форму, при пустой форме проходят; значения полей проверяются при выполнении (formOk) */
  var avail: Set[(str, str, str, str)]
  pure val SURFACES: Set[str] = Set("queue", "card")
  def availNow: Set[(str, str, str, str)] =
    tuples(OPERATORS, MANUAL_IDS, INCIDENTS, SURFACES).filter(x => all {
      incOf(x._3).state != "",
      tr(x._2).surfaces.contains(x._4),
      sees(x._1, x._3),
      trOk(x._2, ctx(x._1, x._1, NO_FORM, x._4), x._3),
    })
  action initR = all { init, avail' = Set() }
  action initWorkR = all { initWork, avail' = Set() }
  action stepR = all { step, avail' = availNow }
  action stepWorkR = all { stepWork, avail' = availNow }
