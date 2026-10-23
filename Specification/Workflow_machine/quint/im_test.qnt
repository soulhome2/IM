// -*- mode: Bluespec; -*-
/* Сценарии для модели im.qnt: права и настройки заданы, шаги — по порядку, в конце — инварианты (inv).
   Переходы — те же, что в машине: manual(кто, переход, инцидент, форма, где), автоматические — fire(инцидент).

   Запуск: quint test im_test.qnt */
module im_test {
  import im.* from "./im"

  // Оба оператора со всеми правами и доступом ко всему; в дежурной группе g — b, группа h пустая.
  // Эскалация: уровень 1 — b, уровень 2 — группа; алерты — группе; лимитов нет
  pure val BASE: Config = {
    perms: Map("a" -> USED_PERMISSIONS, "b" -> USED_PERMISSIONS),
    access: Map("a" -> INCIDENTS, "b" -> INCIDENTS),
    members: Map(GROUP -> Set("b"), GROUP2 -> Set()),
  }
  pure val LEVELS = MACHINE_SETTINGS.escalation.levels
  pure val BASE_SETTINGS: Settings = { ...MACHINE_SETTINGS,
    escalation: { ...MACHINE_SETTINGS.escalation, enabled: true, onResolutionOverdue: "alert",
      levels: [{ ...LEVELS[0], targetKind: "user", target: "b" }, { ...LEVELS[1], targetKind: "group", target: GROUP }] },
    alerts: { ...MACHINE_SETTINGS.alerts, targetKind: "group", target: GROUP },
    limits: { ...MACHINE_SETTINGS.limits, maxActive: 0, maxOnHold: 0 },
  }
  pure def withLevel1(s: Settings, who: str): Settings =
    { ...s, escalation: { ...s.escalation, levels: [{ ...s.escalation.levels[0], target: who }, s.escalation.levels[1]] } }

  action initWith(c: Config, s: Settings): bool = all {
    cfg' = c,
    settings' = s,
    world' = { inc: INCIDENTS.mapBy(i => NO_INCIDENT), answers: INCIDENTS.mapBy(i => Set()) },
    clock' = START,
    agents' = OPERATORS.mapBy(a => "ready"),
    lastBeat' = OPERATORS.mapBy(a => START),
    link' = OPERATORS.mapBy(a => true),
    changedAt' = INCIDENTS.mapBy(i => 0),
    lastAction' = act0("init", "init", NOBODY, NOBODY),
    autoRun' = INCIDENTS.mapBy(i => 0),
  }
  action start = initWith(BASE, BASE_SETTINGS)

  pure val FORM: Form = { ...NO_FORM, comment: "c" }
  pure def surfaceOf(tid: str): str = if (tr(tid).surfaces.contains("card")) "card" else "queue"
  action act(a: str, tid: str, i: str): bool = manual(a, tid, i, FORM, surfaceOf(tid))
  action actF(a: str, tid: str, i: str, f: Form): bool = manual(a, tid, i, f, surfaceOf(tid))
  def ok(a: str, tid: str, i: str): bool = sees(a, i) and trOk(tid, ctx(a, a, FORM, surfaceOf(tid)), i)
  def okF(a: str, tid: str, i: str, f: Form): bool = sees(a, i) and trOk(tid, ctx(a, a, f, surfaceOf(tid)), i)
  pure def reason(r: str): Form = { ...FORM, reasonId: r }
  pure def result(r: str): Form = { ...FORM, resultId: r, causeId: if (CAUSE_FOR.keys().contains(r)) CAUSE_FOR.get(r) else "" }
  pure def target(t: str): Form = { ...FORM, targetId: t }

  // Часы — в момент; у кого связь есть, признак активности приходит и дальше, как в action time модели
  action jump(t: int): bool = all {
    clock' = t,
    lastBeat' = OPERATORS.mapBy(a => if (link.get(a) and agents.get(a) != "offline") t else lastBeat.get(a)),
    world' = world, cfg' = cfg, settings' = settings, agents' = agents, link' = link, changedAt' = changedAt,
    lastAction' = act0("time", "jump", NOBODY, NOBODY),
    autoRun' = autoRun,
  }
  def due(i: str, k: str): int = incOf(i).timers.get(k).due
  action expire(i: str, k: str): bool = jump(due(i, k) + GRACE_MS)
  action newFire(i: str): bool = create(i, "fire", 100)

  def x1 = incOf("i1")
  def x2 = incOf("i2")
  def x3 = incOf("i3")
  pure def breachesOf(x: Incident, kind: str): int = x.breaches.select(b => b.kind == kind).length()
  def resolutionOf(x: Incident): Timer = x.timers.get("resolution")
  def reactionOf(x: Incident): Timer = x.timers.get("reaction")

  /* ===== 1. Основной цикл ===== */

  run mainCycleTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .expect(x1.state == "in_progress" and x1.owner == "a" and not(runs(reactionOf(x1))) and runs(resolutionOf(x1)))
      .then(actF("a", "hold", "i1", reason("patrol")))
      .expect(x1.state == "on_hold" and x1.holdReasonId == "patrol" and runs(x1.timers.get("hold")) and resolutionOf(x1).paused)
      .then(act("a", "resume", "i1"))
      .expect(x1.state == "in_progress" and x1.holdReasonId == "" and not(runs(x1.timers.get("hold"))) and runs(resolutionOf(x1)))
      .then(answer("a", "i1", "s1"))
      .then(answer("a", "i1", "s2"))
      .then(actF("a", "close", "i1", result("processed")))
      .expect(x1.state == "closed" and x1.closedBy == "a" and x1.closeResultId == "processed" and not(runs(resolutionOf(x1))))
      .then(act("a", "reopen", "i1"))
      .expect(x1.state == "in_progress" and x1.owner == "a" and x1.closeResultId == "" and runs(resolutionOf(x1)))
      .expect(inv)

  // Переоткрытие запускает норматив закрытия заново (RULE-11)
  run reopenRestartsResolutionTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .then(expire("i1", "resolution"))
      .then(fire("i1"))
      .expect(lastAction.name == "resolution_overdue" and breachesOf(x1, "resolution") == 1)
      .then(actF("a", "close", "i1", result("false_alarm")))
      .then(act("a", "reopen", "i1"))
      .expect(runs(resolutionOf(x1)) and due("i1", "resolution") > clock and breachesOf(x1, "resolution") == 1)
      .expect(inv)

  /* ===== 2. Эскалация (§8.3) ===== */

  // В группе уровня 2 — и a: иначе принять в ней мог бы только b, у кого инцидент уже есть (RULE-93)
  run escalationToCeilingTest =
    initWith({ ...BASE, members: Map(GROUP -> Set("a", "b"), GROUP2 -> Set()) }, BASE_SETTINGS)
      .then(newFire("i1"))
      .then(expire("i1", "reaction"))
      .expect(urgent)
      .then(fire("i1"))
      .expect(lastAction.name == "auto_escalate" and x1.state == "pending_acceptance" and x1.owner == "b" and x1.escalationLevel == 1 and runs(reactionOf(x1)))
      .then(expire("i1", "reaction"))
      .then(fire("i1"))
      .expect(x1.owner == "" and x1.assignmentGroup == GROUP and x1.escalationLevel == 2 and runs(reactionOf(x1)))
      .then(expire("i1", "reaction"))
      .then(fire("i1"))
      .expect(lastAction.name == "escalation_ceiling" and not(runs(reactionOf(x1))) and breachesOf(x1, "reaction") == 1)
      // «Отклонить» остановленную реакцию не запускает, «Передать» — запускает (ifStopped)
      .then(act("b", "reject", "i1"))
      .expect(x1.state == "new" and not(runs(reactionOf(x1))))
      .then(actF("a", "transfer", "i1", target("b")))
      .expect(x1.state == "pending_acceptance" and x1.owner == "b" and runs(reactionOf(x1)) and x1.transferCount == 1)
      .expect(inv)

  // RULE-93: уровень, адресат которого уже держит инцидент, пропускается
  run escalationSkipsCurrentAddresseeTest =
    initWith({ ...BASE, members: Map(GROUP -> Set("a", "b"), GROUP2 -> Set()) }, BASE_SETTINGS)
      .then(newFire("i1"))
      .then(actF("a", "transfer", "i1", target("b")))
      .then(expire("i1", "reaction"))
      .then(fire("i1"))
      .expect(lastAction.name == "auto_escalate" and x1.assignmentGroup == GROUP and x1.escalationLevel == 2)
      .expect(inv)

  // RULE-93: группа, где принять может только тот, у кого инцидент уже есть, — тоже пропускается
  run escalationGroupOnlyAddresseeTest =
    start
      .then(newFire("i1"))
      .then(actF("a", "transfer", "i1", target("b")))
      .then(expire("i1", "reaction"))
      .then(fire("i1"))
      .expect(lastAction.name == "escalation_ceiling" and x1.owner == "b" and breachesOf(x1, "reaction") == 1)
      .expect(inv)

  // RULE-100: уровень вышедшего адресата, у которого в дежурной группе принять некому (у a группы нет), пропускается
  run escalationSkipsSignedOutTest =
    initWith(BASE, withLevel1(BASE_SETTINGS, "a"))
      .then(signOut("a"))
      .then(newFire("i1"))
      .then(expire("i1", "reaction"))
      .then(fire("i1"))
      .expect(lastAction.name == "auto_escalate" and x1.owner == "" and x1.assignmentGroup == GROUP and x1.escalationLevel == 2)
      .expect(inv)

  // RULE-100, ветка дежурной группы (PROC-50): адресат уровня 1 вышел, но в его группе g есть кому принять, —
  // уровень не пропускается: эскалация отдаёт ему, и инцидент сразу уходит группе g, а не группе уровня 2 (h)
  run escalationSignedOutToOwnGroupTest =
    initWith({ ...BASE, members: Map(GROUP -> Set("a", "b"), GROUP2 -> Set("b")) },
      { ...BASE_SETTINGS, escalation: { ...BASE_SETTINGS.escalation,
        levels: [{ ...LEVELS[0], targetKind: "user", target: "a" }, { ...LEVELS[1], targetKind: "group", target: GROUP2 }] } })
      .then(signOut("a"))
      .then(newFire("i1"))
      .then(expire("i1", "reaction"))
      .then(fire("i1"))
      .expect(lastAction.name == "auto_escalate" and x1.owner == "a" and x1.escalationLevel == 1)
      .then(fire("i1"))
      .expect(lastAction.name == "addressee_signed_out_to_group" and x1.owner == "" and x1.assignmentGroup == GROUP and x1.escalationLevel == 1)
      .expect(inv)

  // RULE-93 по нормативу закрытия: уровень 1 — сам владелец, пропущен
  run resolutionEscalateSkipsOwnerTest =
    initWith({ ...BASE, members: Map(GROUP -> Set("a", "b"), GROUP2 -> Set()) },
      withLevel1({ ...BASE_SETTINGS, escalation: { ...BASE_SETTINGS.escalation, onResolutionOverdue: "escalate" } }, "a"))
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .then(expire("i1", "resolution"))
      .then(fire("i1"))
      .expect(lastAction.name == "resolution_escalate" and x1.assignmentGroup == GROUP and x1.escalationLevel == 2 and breachesOf(x1, "resolution") == 1)
      .expect(inv)

  // Сработавший норматив закрытия второй раз не срабатывает: возврат в работу — с прежним дедлайном (RULE-50)
  run resolutionFiresOnceTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .then(expire("i1", "resolution"))
      .then(fire("i1"))
      .then(act("a", "release", "i1"))
      .then(act("a", "claim", "i1"))
      .expect(not(urgent) and breachesOf(x1, "resolution") == 1 and resolutionOf(x1).due == resolutionOf(x1).fired)
      .expect(inv)

  /* ===== 3. Права и лимиты ===== */

  run targetCannotTakeoverTest =
    start
      .then(newFire("i1"))
      .then(actF("a", "transfer", "i1", target("b")))
      .expect(not(ok("b", "takeover", "i1")) and ok("b", "accept", "i1"))
      .expect(inv)

  // Себе и своей дежурной группе не передают (§10.1)
  run transferToOwnGroupForbiddenTest =
    start
      .then(newFire("i1"))
      .expect(not(okF("b", "transfer", "i1", target(GROUP))) and not(okF("b", "transfer", "i1", target("b"))) and okF("a", "transfer", "i1", target(GROUP)))
      .expect(inv)

  // «Обработан» — только у пройденного сценария (§14.5)
  run processedNeedsStepsTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .expect(not(okF("a", "close", "i1", result("processed"))) and okF("a", "close", "i1", result("false_alarm")))
      .then(answer("a", "i1", "s1"))
      .then(answer("a", "i1", "s2"))
      .expect(okF("a", "close", "i1", result("processed")))
      .expect(inv)

  run massCloseFromNewTest =
    start
      .then(newFire("i1"))
      .then(actF("a", "close", "i1", result("mass")))
      .expect(x1.state == "closed" and x1.closeResultId == "mass")
      .expect(inv)

  // Лимит отложенных — только у ручного «Отложить» (§10.2)
  run holdLimitTest =
    initWith(BASE, { ...BASE_SETTINGS, limits: { ...BASE_SETTINGS.limits, maxOnHold: 1 } })
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i1"))
      .then(actF("a", "hold", "i1", reason("patrol")))
      .then(act("a", "claim", "i2"))
      .expect(not(okF("a", "hold", "i2", reason("patrol"))))
      .expect(inv)

  // Видимость (§5): без доступа к объекту — ничего
  run invisibleCannotActTest =
    initWith({ ...BASE, access: Map("a" -> Set(), "b" -> INCIDENTS) }, BASE_SETTINGS)
      .then(newFire("i1"))
      .expect(not(ok("a", "claim", "i1")) and ok("b", "claim", "i1"))
      .expect(inv)

  run answerRightsTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .expect(scenarioEditOk(ctx("a", "a", NO_FORM, "card"), "i1") and not(scenarioEditOk(ctx("b", "b", NO_FORM, "card"), "i1")))
      .expect(inv)

  /* ===== 4. Объединение и срок группы (§11, RULE-97) ===== */

  run mergeIntoMineTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i1"))
      .then(merge("a", "i1", Set("i2")))
      .expect(x2.state == "linked" and x2.linkedTo == "i1" and x2.owner == "" and not(runs(resolutionOf(x2))))
      .expect(inv)

  run mergeTakesNewPrimaryTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(merge("a", "i1", Set("i2")))
      .expect(x1.state == "in_progress" and x1.owner == "a" and x2.state == "linked" and x2.linkedTo == "i1")
      .expect(inv)

  // Основного не назвали — mergePrimary машины: свой в работе, иначе самый срочный, у равных — появившийся раньше
  run mergeAutoPicksUrgentTest =
    start
      .then(create("i1", "fire", 50))
      .then(newFire("i2"))
      .then(mergeAuto("a", Set("i1", "i2")))
      .expect(x2.state == "in_progress" and x1.state == "linked" and x1.linkedTo == "i2")
      .expect(inv)

  run mergeAutoPicksEarlierTest =
    start
      .then(newFire("i1"))
      .then(jump(clock + 1000))
      .then(newFire("i2"))
      .then(mergeAuto("a", Set("i1", "i2")))
      .expect(x1.state == "in_progress" and x2.state == "linked" and x2.linkedTo == "i1")
      .expect(inv)

  run mergeAutoPicksMineTest =
    start
      .then(newFire("i1"))
      .then(create("i2", "fire", 50))
      .then(act("a", "claim", "i2"))
      .then(mergeAuto("a", Set("i1", "i2")))
      .expect(x2.state == "in_progress" and x1.state == "linked" and x1.linkedTo == "i2")
      .expect(inv)

  // Привязанные объединяемого — новому основному: привязанного у привязанного не бывает
  run mergeRelinksTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(newFire("i3"))
      .then(merge("a", "i1", Set("i2")))
      // Основного выбирает сервер (RULE-101): свой в работе i1 отложен — основным станет новый i3
      .then(actF("a", "hold", "i1", reason("patrol")))
      .then(merge("a", "i3", Set("i1")))
      .expect(x1.linkedTo == "i3" and x2.linkedTo == "i3" and x2.leftGroup.primaryId == "i1")
      .expect(inv)

  // Всё или ничего: один из выборки нельзя — нельзя всю
  run mergeAllOrNothingTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(newFire("i3"))
      .then(actF("b", "transfer", "i3", target("a")))
      .expect(not(trOk(MERGE, ctx("a", "a", { ...NO_FORM, primaryId: "i1" }, ""), "i3")))
      .then(merge("a", "i1", Set("i2")))
      .expect(x3.state == "pending_acceptance")
      .expect(inv)

  run mergeDifferentScenarioTest =
    start
      .then(create("i1", "fire", 100))
      .then(create("i2", "water", 100))
      .expect(not(trOk(MERGE, ctx("a", "a", { ...NO_FORM, primaryId: "i1" }, ""), "i2")))
      .expect(inv)

  // Ответы привязанного — основному: «Обработан» доступен по перенесённым ответам
  run mergeAnswersFinishTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i2"))
      .then(answer("a", "i2", "s1"))
      .then(answer("a", "i2", "s2"))
      .then(act("a", "claim", "i1"))
      .then(merge("a", "i1", Set("i2")))
      .expect(world.answers.get("i1") == STEPS and okF("a", "close", "i1", result("processed")))
      .expect(inv)

  // Закрыли основной — привязанный закрывается вместе с ним его результатом (§11.4)
  run closeLinkedTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(merge("a", "i1", Set("i2")))
      .then(actF("a", "close", "i1", result("false_alarm")))
      .expect(urgent)
      .then(fire("i2"))
      .expect(lastAction.name == "close_linked" and x2.state == "closed" and x2.closeResultId == "false_alarm" and x2.closedBy == "a")
      .expect(inv)

  // У группы один срок: нарушение основного — и привязанному, на владельца основного (RULE-97)
  run groupBreachSharedTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i1"))
      .then(merge("a", "i1", Set("i2")))
      .then(expire("i1", "resolution"))
      .then(fire("i1"))
      .expect(breachesOf(x1, "resolution") == 1 and breachesOf(x2, "resolution") == 1 and x2.breaches[0].owner == "a")
      .expect(inv)

  // Группу никто не ведёт — срок стоит (RULE-97)
  run releasedGroupStopsTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i1"))
      .then(merge("a", "i1", Set("i2")))
      .then(act("a", "release", "i1"))
      .expect(not(runs(resolutionOf(x1))) and resolutionOf(x1).paused and not(runs(resolutionOf(x2))))
      .expect(inv)

  // Отсоединённый после нарушения группы — с отработанным сроком: при взятии второго нарушения нет (RULE-50)
  run detachAfterGroupBreachTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i1"))
      .then(merge("a", "i1", Set("i2")))
      .then(expire("i1", "resolution"))
      .then(fire("i1"))
      .then(act("a", "detach", "i2"))
      .then(act("b", "claim", "i2"))
      .expect(not(urgent) and breachesOf(x2, "resolution") == 1)
      .expect(inv)

  // BUG-73: отсоединённому в окне после срока группы нарушение группы записано — тем, кто был в группе в момент срока
  run detachInGroupWindowTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i1"))
      .then(merge("a", "i1", Set("i2")))
      .then(jump(due("i1", "resolution") + 1))
      .expect(not(urgent))
      .then(act("a", "detach", "i2"))
      .then(expire("i1", "resolution"))
      .then(fire("i1"))
      .expect(breachesOf(x1, "resolution") == 1 and breachesOf(x2, "resolution") == 1 and x2.state == "new")
      .expect(inv)

  // BUG-75: отсоединённый в окне после срока группы и взятый в нём же — одно нарушение, группы, на a; своего нет
  run detachClaimInGroupWindowTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i1"))
      .then(merge("a", "i1", Set("i2")))
      .then(jump(due("i1", "resolution") + 1))
      .then(act("a", "detach", "i2"))
      .expect(dueNotPausedUnprocessed)
      .then(act("b", "claim", "i2"))
      .then(expire("i1", "resolution"))
      .then(fire("i1"))
      .then(jump(clock + 1000))
      .expect(not(urgent) and breachesOf(x2, "resolution") == 1 and x2.breaches[0].owner == "a")
      .expect(inv)

  // BUG-75: отсоединённый ровно в миг срока группы — тоже в группе: нарушение группы ему записано, своего не будет
  run detachAtGroupDeadlineTest =
    start
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(act("a", "claim", "i1"))
      .then(merge("a", "i1", Set("i2")))
      .then(jump(due("i1", "resolution")))
      .then(act("a", "detach", "i2"))
      .then(expire("i1", "resolution"))
      .then(fire("i1"))
      .then(act("b", "claim", "i2"))
      .then(jump(clock + 10000))
      .expect(not(urgent) and breachesOf(x2, "resolution") == 1 and x2.breaches[0].owner == "a")
      .expect(inv)

  // Перехват основного тем, кто не видит привязанный: привязанный отсоединяется (§11.4, RULE-71)
  run takeoverLosesLinkedTest =
    initWith({ ...BASE, access: Map("a" -> INCIDENTS, "b" -> Set("i1")) }, BASE_SETTINGS)
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(merge("a", "i1", Set("i2")))
      .then(act("b", "takeover", "i1"))
      .expect(urgent)
      .then(fire("i2"))
      .expect(lastAction.name == "linked_lost_access" and x2.state == "new" and x2.linkedTo == "")
      .expect(inv)

  /* ===== 5. Состояние оператора (§12) и роли (§5) ===== */

  run breakHoldsWorkTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .then(goOnBreak("a"))
      .then(fire("i1"))
      .expect(lastAction.name == "system_hold_break" and x1.state == "on_hold" and x1.holdReasonId == "break")
      .expect(inv)

  run silenceHoldThenReleaseTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .then(loseLink("a"))
      .then(jump(lastBeat.get("a") + settings.session.idleHoldSec * 1000))
      .then(fire("i1"))
      .expect(lastAction.name == "system_hold_idle" and x1.holdReasonId == "no_link")
      .then(jump(lastBeat.get("a") + settings.session.idleReleaseSec * 1000))
      .then(fire("i1"))
      .expect(lastAction.name == "system_release_idle" and x1.state == "new")
      .expect(inv)

  // Действие — признак активности (§12.3, BUG-76): молчал дольше порога и взял — не отложен
  run actingIsNotSilentTest =
    start
      .then(newFire("i1"))
      .then(loseLink("a"))
      .then(jump(clock + settings.session.idleHoldSec * 1000 + 60000))
      .then(act("a", "claim", "i1"))
      .expect(not(urgent) and x1.state == "in_progress" and lastBeat.get("a") == clock)
      .expect(inv)

  run signOutReturnsWorkTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .then(signOut("a"))
      .then(fire("i1"))
      .expect(lastAction.name == "owner_signed_out" and x1.state == "new")
      .expect(inv)

  // Вышел адресат лично ему переданного: инцидент — его дежурной группе
  run signOutPendingTest =
    start
      .then(newFire("i1"))
      .then(actF("a", "transfer", "i1", target("b")))
      .then(signOut("b"))
      .then(fire("i1"))
      .expect(lastAction.name == "addressee_signed_out_to_group" and x1.assignmentGroup == GROUP and x1.owner == "")
      .expect(inv)

  run lostAccessInWorkTest =
    start
      .then(newFire("i1"))
      .then(act("a", "claim", "i1"))
      .then(toggleAccess("a", "i1"))
      .then(fire("i1"))
      .expect(lastAction.name == "addressee_lost_access" and x1.state == "new" and x1.owner == "")
      .expect(inv)

  run cannotAcceptTest =
    start
      .then(newFire("i1"))
      .then(actF("a", "transfer", "i1", target("b")))
      .then(toggleAccept("b"))
      .then(fire("i1"))
      .expect(lastAction.name == "addressee_cannot_accept" and x1.state == "new")
      .expect(inv)

  /* ===== 6. Ядро: окно после дедлайна (§10.1, RULE-63) ===== */

  // Без автоэскалации реакция по дедлайну записывает нарушение (reaction_overdue): его окно и проверяется
  pure val NO_ESCALATION: Settings = { ...BASE_SETTINGS, escalation: { ...BASE_SETTINGS.escalation, enabled: false } }

  // «Взять» в окне после дедлайна выигрывает у таймера, но нарушение записано (RULE-63)
  run windowClaimBreachTest =
    initWith(BASE, NO_ESCALATION)
      .then(newFire("i1"))
      .then(jump(due("i1", "reaction") + 1))
      .expect(not(urgent))
      .then(act("a", "claim", "i1"))
      .expect(x1.state == "in_progress" and x1.owner == "a" and breachesOf(x1, "reaction") == 1)
      // Нарушение — на момент дедлайна, а не взятия в окне (§10.1, правило 5; PROC-51): инцидент появился в START
      .expect(x1.breaches.select(b => b.kind == "reaction")[0].at == START + 1000 * timerSec(x1, "reaction", ""))
      .then(jump(clock + GRACE_MS))
      .expect(not(urgent))
      .expect(inv)

  // Переход по таймеру после окна датирует нарушение тоже дедлайном, а не моментом срабатывания (PROC-51)
  run timerBreachAtDeadlineTest =
    initWith(BASE, NO_ESCALATION)
      .then(newFire("i1"))
      .then(expire("i1", "reaction"))
      .then(fire("i1"))
      .expect(lastAction.name == "reaction_overdue" and breachesOf(x1, "reaction") == 1)
      .expect(x1.breaches[0].at == START + 1000 * timerSec(x1, "reaction", "") and clock > x1.breaches[0].at)
      .expect(inv)

  // «Взять в работу одним» в окне: основного берут — его нарушение тоже не теряется (BUG-62)
  run mergeWindowPrimaryBreachTest =
    initWith(BASE, NO_ESCALATION)
      .then(newFire("i1"))
      .then(newFire("i2"))
      .then(jump(due("i1", "reaction") + 1))
      .then(merge("a", "i1", Set("i2")))
      .expect(x1.state == "in_progress" and breachesOf(x1, "reaction") == 1 and breachesOf(x2, "reaction") == 1)
      .expect(inv)
}
