// -*- mode: Bluespec; -*-
/* Сценарии для модели im.qnt: права и настройки заданы, шаги — по порядку.
   В конце каждого сценария — инварианты модели (inv).

   Запуск: quint test im_test.qnt */
module im_test {
  import im.* from "./im"

  // Оба оператора со всеми правами и доступом ко всему; в дежурной группе — b.
  // Эскалация: уровень 1 — b, уровень 2 — группа (LEVELS в im.qnt)
  pure val BASE: Config = {
    perms: Map("a" -> PERMS, "b" -> PERMS),
    access: Map("a" -> INCIDENTS, "b" -> INCIDENTS),
    members: Set("b"),
    escalationEnabled: true,
    onResolutionOverdue: "alert",
    maxActive: 0,
    maxOnHold: 0,
  }

  action initWith(c: Config): bool = all {
    cfg' = c,
    inc' = INCIDENTS.mapBy(i => ABSENT),
    lastAction' = { name: "init", actor: NOBODY, incident: NOBODY },
  }

  pure def result(id: str): CloseResult =
    CLOSE_RESULTS.fold({ id: NOBODY, perm: NOBODY, from: Set(), ownerOnly: Set(), steps: false }, (acc, r) => if (r.id == id) r else acc)
  pure val RUNNING: Timer = { mode: Running, phase: Before }
  def x1 = inc.get("i1")
  def breachesOf(kind: str): int = x1.breaches.select(b => b.kind == kind).length()

  /* ===== 1. Основной цикл: взять, отложить, возобновить, закрыть, переоткрыть ===== */

  run mainCycleTest =
    initWith(BASE)
      .then(create("i1"))
      .then(claim("a", "i1"))
      .expect(x1.state == InProgress and x1.owner == "a" and x1.reaction == IDLE and x1.resolution == RUNNING)
      .then(hold("a", "i1", "patrol"))
      .expect(x1.state == OnHold and x1.holdReason == "patrol" and x1.hold == RUNNING and x1.resolution.mode == Paused)
      .then(resume("a", "i1"))
      .expect(x1.state == InProgress and x1.holdReason == NOBODY and x1.hold == IDLE and x1.resolution == RUNNING)
      .then(close("a", "i1", result("processed"), true))
      .expect(x1.state == Closed and x1.closedBy == "a" and x1.closeResult == "processed" and x1.resolution.mode == Paused)
      .then(reopen("a", "i1"))
      .expect(x1.state == InProgress and x1.owner == "a" and x1.closeResult == NOBODY and x1.resolution == RUNNING)
      .expect(inv)

  // Переоткрытие запускает норматив закрытия заново: истёкший до закрытия больше не истёкший (RULE-11)
  run reopenRestartsResolutionTest =
    initWith(BASE)
      .then(create("i1"))
      .then(claim("a", "i1"))
      .then(expireResolution("i1"))
      .then(resolutionOverdue("i1"))
      .then(close("a", "i1", result("false_alarm"), false))
      .then(reopen("a", "i1"))
      .expect(x1.resolution == RUNNING and breachesOf("resolution") == 1)
      .expect(inv)

  /* ===== 2. Эскалация по реакции до потолка (§8.3, RULE-84) ===== */

  run escalationToCeilingTest =
    initWith(BASE)
      .then(create("i1"))
      .then(expireReaction("i1"))
      .expect(not(claimOk("a", "i1")))  // переход по таймеру срочный — ручные ждут
      .then(autoEscalate("i1"))
      .expect(x1.state == Pending and x1.owner == "b" and x1.group == NOBODY and x1.level == 1 and x1.reaction == RUNNING)
      .then(expireReaction("i1"))
      .then(autoEscalate("i1"))
      .expect(x1.state == Pending and x1.owner == NOBODY and x1.group == GROUP and x1.level == 2 and x1.reaction == RUNNING)
      .then(expireReaction("i1"))
      .expect(not(autoEscalateOk("i1")))
      .then(escalationCeiling("i1"))
      .expect(x1.state == Pending and x1.level == 2 and x1.reaction == IDLE and breachesOf("reaction") == 1)
      // «Отклонить» остановленную реакцию не запускает…
      .then(reject("b", "i1"))
      .expect(x1.state == New and x1.reaction == IDLE)
      // …а «Передать» запускает (ifStopped)
      .then(transfer("a", "i1", "b"))
      .expect(x1.state == Pending and x1.owner == "b" and x1.reaction == RUNNING and x1.transfers == 1)
      .expect(inv)

  // Уровень 1 недоступен (у b нет права «Принимать») — пропускается, сразу группа (§8.3)
  run escalationSkipsLevelTest =
    initWith({ ...BASE, perms: Map("a" -> PERMS, "b" -> PERMS.exclude(Set("incident:accept"))), members: Set("a") })
      .then(create("i1"))
      .then(expireReaction("i1"))
      .then(autoEscalate("i1"))
      .expect(x1.owner == NOBODY and x1.group == GROUP and x1.level == 2)
      .expect(inv)

  // Эскалация выключена: истёкшая реакция — нарушение без передачи (RULE-40)
  run reactionOverdueWithoutEscalationTest =
    initWith({ ...BASE, escalationEnabled: false })
      .then(create("i1"))
      .then(expireReaction("i1"))
      .expect(not(autoEscalateOk("i1")))
      .then(reactionOverdue("i1"))
      .expect(x1.state == New and x1.reaction == IDLE and breachesOf("reaction") == 1)
      .expect(inv)

  /* ===== 3. Остаток норматива закрытия (RULE-07, RULE-50) ===== */

  run resolutionFiresOnceTest =
    initWith(BASE)
      .then(create("i1"))
      .then(claim("a", "i1"))
      .then(expireResolution("i1"))
      .then(resolutionOverdue("i1"))
      .expect(breachesOf("resolution") == 1 and x1.resolution == { mode: Running, phase: Fired })
      .then(release("a", "i1"))
      .expect(x1.state == New and x1.resolution == { mode: Paused, phase: Fired } and x1.reaction == RUNNING)
      .then(claim("b", "i1"))
      // взятие продолжает с остатка: срок прежний, отработанный, повторно не срабатывает
      .expect(x1.resolution == { mode: Running, phase: Fired })
      .expect(not(resolutionOverdueOk("i1")))
      .expect(not(expireResolutionOk("i1")))
      .expect(breachesOf("resolution") == 1)
      .expect(inv)

  // Пауза до дедлайна сохраняет остаток: удержание не сдвигает и не обнуляет срок
  run holdPausesResolutionTest =
    initWith(BASE)
      .then(create("i1"))
      .then(claim("a", "i1"))
      .then(hold("a", "i1", "no_data"))
      .expect(not(expireResolutionOk("i1")))  // на паузе дедлайн не наступает
      .then(expireHold("i1"))
      .then(holdOverdue("i1"))
      .expect(breachesOf("hold") == 1 and x1.state == OnHold)
      .then(resume("a", "i1"))
      .expect(x1.resolution == RUNNING and x1.hold == IDLE)
      .expect(inv)

  /* ===== 4. Эскалация по нормативу закрытия (§9, RULE-27) ===== */

  run resolutionEscalateTest =
    initWith({ ...BASE, onResolutionOverdue: "escalate" })
      .then(create("i1"))
      .then(claim("a", "i1"))
      .then(expireResolution("i1"))
      .expect(not(resolutionOverdueOk("i1")))
      .then(resolutionEscalate("i1"))
      .expect(all {
        x1.state == Pending,
        x1.owner == "b",
        x1.level == 1,
        x1.breaches == [{ kind: "resolution", who: "a" }],
        x1.resolution == { mode: Paused, phase: Fired },
        x1.reaction == RUNNING,
      })
      .expect(inv)

  /* ===== 5. Запреты ===== */

  // Адресат принимает, а не перехватывает (BUG-60); посторонний с правом — перехватывает
  run targetCannotTakeoverTest =
    initWith(BASE)
      .then(create("i1"))
      .then(transfer("a", "i1", "b"))
      .expect(not(takeoverOk("b", "i1")))
      .expect(not(acceptOk("a", "i1")))
      .then(takeover("a", "i1"))
      .expect(x1.state == InProgress and x1.owner == "a")
      .expect(inv)

  // Участник группы ей не передаёт (targetIsNotSelf); не участник — передаёт
  run transferToOwnGroupForbiddenTest =
    initWith(BASE)
      .then(create("i1"))
      .expect(not(transferOk("b", "i1", GROUP)))
      .expect(not(transferOk("a", "i1", "a")))
      .then(transfer("a", "i1", GROUP))
      .expect(x1.state == Pending and x1.group == GROUP and x1.owner == NOBODY)
      .then(accept("b", "i1"))
      .expect(x1.state == InProgress and x1.owner == "b" and x1.group == NOBODY)
      .expect(inv)

  // «Обработан» — только владельцем и с заполненными шагами
  run processedNeedsStepsTest =
    initWith(BASE)
      .then(create("i1"))
      .then(claim("a", "i1"))
      .expect(not(closeOk("a", "i1", result("processed"), false)))
      .expect(not(closeOk("b", "i1", result("processed"), true)))
      .then(close("a", "i1", result("processed"), true))
      .expect(x1.state == Closed and x1.closeResult == "processed")
      .expect(inv)

  // «Массовый сбой» из «Новое» — только с incident:close:unprocessed; закрывший становится владельцем
  run massCloseFromNewTest =
    initWith({ ...BASE, perms: Map("a" -> PERMS.exclude(Set("incident:close:unprocessed")), "b" -> PERMS) })
      .then(create("i1"))
      .expect(not(closeOk("a", "i1", result("mass"), false)))
      .expect(not(closeOk("b", "i1", result("false_alarm"), false)))
      .then(close("b", "i1", result("mass"), false))
      .expect(x1.state == Closed and x1.owner == "b" and x1.closedBy == "b" and x1.resolution == IDLE)
      .expect(inv)

  // Лимит отложенных — только у ручного «Отложить» (§10.2)
  run holdLimitTest =
    initWith({ ...BASE, maxOnHold: 1 })
      .then(create("i1"))
      .then(create("i2"))
      .then(claim("a", "i1"))
      .then(claim("a", "i2"))
      .then(hold("a", "i1", "patrol"))
      .expect(not(holdOk("a", "i2")))
      .then(release("a", "i1"))
      .then(hold("a", "i2", "patrol"))
      .expect(inv)
}
