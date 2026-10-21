// -*- mode: Bluespec; -*-
// Собрано скриптом tools/gen_quint.mjs из Specification/Workflow_machine/workflow_schema.v1.json и частей quint/src/.
// Руками не править: правится машина или часть в src/, затем сборка.
/* Машина состояний инцидента МИ — формальная модель на Quint (ARCH-07.6).

   Типы, значения настроек, определения, условия и эффекты переходов — из машины
   ../workflow_schema.v1.json, переводом её выражений CEL (CEL.md, «Перевод в Quint»): смысл правил
   записан один раз, и модель проверяет те же правила, что исполняет прототип. Руками — части src/:
   мир модели (world.qnt), ядро исполнения (core.qnt), инварианты (invariants.qnt).

   Мир маленький: 3 инцидента, 2 оператора, 1 дежурная группа. Время — целые миллисекунды, как в
   машине; часы идут действием окружения «время» к следующему событию — дедлайну, концу окна после
   дедлайна, порогу молчания, концу срока переоткрытия, — поэтому нормативы и сроки — значения машины.

   Запуск: quint run im.qnt --invariant inv */
module im {

  /* ===== Контекст перехода ===== */

  // Кто проверяет условия (me) и кто выполняет (actor), когда, форма, где спрашивают, инцидент до перехода
  type Ctx = { me: str, actor: str, now: int, deadline: int, form: Form, surface: str, before: Incident }
  // Инциденты и отвеченные шаги сценария: эффекты переходов меняют только это
  type World = { inc: str -> Incident, answers: str -> Set[str] }
  type Transition = { id: str, trigger: str, actor: str, from: Set[str], timer: str, idleSec: int, ownedByAgent: bool, surfaces: Set[str], bulkOnly: bool }
  // Последнее действие — с параметрами: по ним историю модели повторяют на исполнителе прототипа
  // (tools/check_quint_replay.mjs). others — набор объединения, prio и scenario — у появления
  type Action = { name: str, actor: str, incident: str, kind: str, form: Form, surface: str, others: List[str], prio: int, scenario: str }

  /* ===== Типы машины (cel.types) ===== */


  type Incident = { id: str, number: str, eventType: str, priority: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str }

  type Timer = { due: int, paused: bool, left: int, fired: int, since: int }

  type Breach = { kind: str, at: int, owner: str }

  type LeftGroup = { primaryId: str, linkedAt: int, at: int }

  type Form = { targetId: str, primaryId: str, resultId: str, reasonId: str, causeId: str, comment: str }

  type Limits = { maxActive: int, maxOnHold: int, maxBulk: int, reopenWindowMin: int, reopenResolutionSec: int }

  type SessionState = { id: str, readOnly: bool, readOnlyReasonKey: str }

  type Session = { states: List[SessionState], heartbeatSec: int, idleHoldSec: int, idleReleaseSec: int }

  type Escalation = { enabled: bool, levels: List[Level], maxLevel: int, onResolutionOverdue: str }

  type Level = { level: int, targetKind: str, target: str, reactionSec: int }

  type Alerts = { targetKind: str, target: str, noRecipientLog: str }

  type State = { id: str, category: str }

  type CloseResultItem = { id: str, labelKey: str, permission: str, fromStates: List[str], ownerOnlyInStates: List[str], surfaces: List[str], requiredStepSet: str, commentRequired: bool }

  type ScopeRule = { own: ScopeOwn }

  type ScopeOwn = { anyOf: List[ScopeCond] }

  type ScopeCond = { state: str, ownership: str }

  type TimerDef = { id: str, labelKey: str, defaultSec: int, byPriority: int -> int, overrides: List[Override], startsOnce: bool, pausable: bool, secFrom: str }

  type Override = { eventType: List[str], priority: List[int], sourceGroup: List[str], escalationLevel: List[int], sec: int }

  type HoldReason = { id: str, maxMinutes: int, setBy: str }

  type Settings = { limits: Limits, session: Session, escalation: Escalation, alerts: Alerts, states: List[State], closeResults: List[CloseResultItem], timerDefs: List[TimerDef], holdReasons: List[HoldReason] }


  /* ===== Настройки — значения машины (cel.settings) ===== */


  pure val MACHINE_SETTINGS: Settings = {
    limits: { maxActive: 0, maxOnHold: 5, maxBulk: 0, reopenWindowMin: 1440, reopenResolutionSec: 0 },
    session: { states: [{ id: "ready", readOnly: false, readOnlyReasonKey: "" }, { id: "busy", readOnly: false, readOnlyReasonKey: "" }, { id: "not_ready", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.not_ready" }, { id: "offline", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.offline" }], heartbeatSec: 30, idleHoldSec: 300, idleReleaseSec: 1200 },
    escalation: { enabled: true, levels: [{ level: 1, targetKind: "user", target: "petrova", reactionSec: 120 }, { level: 2, targetKind: "user", target: "noc", reactionSec: 90 }], maxLevel: 2, onResolutionOverdue: "alert" },
    alerts: { targetKind: "group", target: "grp-leads", noRecipientLog: "workflow.journal.alert_no_recipient" },
    states: [{ id: "new", category: "pending" }, { id: "pending_acceptance", category: "pending" }, { id: "in_progress", category: "active" }, { id: "on_hold", category: "active" }, { id: "closed", category: "done" }, { id: "linked", category: "linked" }],
    closeResults: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "closing", commentRequired: false }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", permission: "incident:close:unprocessed", fromStates: ["new", "pending_acceptance", "in_progress", "on_hold"], ownerOnlyInStates: ["in_progress", "on_hold"], surfaces: ["queue", "card"], requiredStepSet: "none", commentRequired: true }],
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overrides: [{ eventType: [], priority: [100], sourceGroup: [], escalationLevel: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], escalationLevel: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], escalationLevel: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], escalationLevel: [], sec: 1800 }], startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overrides: [], startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overrides: [], startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
    holdReasons: [{ id: "third_party", maxMinutes: 30, setBy: "operator" }, { id: "patrol", maxMinutes: 45, setBy: "operator" }, { id: "no_data", maxMinutes: 60, setBy: "operator" }, { id: "break", maxMinutes: 30, setBy: "system" }, { id: "no_link", maxMinutes: 20, setBy: "system" }],
  }

  pure val STATES: Set[str] = Set("new", "pending_acceptance", "in_progress", "on_hold", "closed", "linked")

  pure val HOLD_REASONS_BY_OPERATOR: Set[str] = Set("third_party", "patrol", "no_data")

  pure val CLOSE_RESULT_IDS: Set[str] = Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass")

  pure val USED_PERMISSIONS: Set[str] = Set("agent:set_not_ready", "incident:accept", "incident:bulk", "incident:claim", "incident:close", "incident:close:unprocessed", "incident:hold", "incident:reassign", "incident:release", "incident:reopen", "incident:run_action", "incident:transfer:any", "incident:transfer:own")

  pure val TIMER_IDS: Set[str] = Set("reaction", "resolution", "hold")

  pure val NO_TIMER: Timer = { due: 0, paused: false, left: 0, fired: 0, since: 0 }

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

  pure val NO_FORM: Form = { targetId: "", primaryId: "", resultId: "", reasonId: "", causeId: "", comment: "" }

  pure val CAUSE_FOR: str -> str = Map("mass" -> "power")

  /* ===== Определения машины (cel.definitions) ===== */


  // §8.1. Адресат: владелец-человек, а пока группа не приняла — сама группа

  def addressee(x: Incident): str =
    (if ((x.owner != "")) x.owner else x.assignmentGroup)

  def unowned(x: Incident): bool =
    ((x.owner == "") and (x.assignmentGroup == ""))

  // §10.1. «Я» как адресат: сам оператор и дежурные группы, в которые он входит

  def isSelf(who: str, id: str): bool =
    ((id != "") and ((id == who) or (isGroup(id) and members(id).foldl(false, (acc, y1) => acc or y1 == who))))

  def isTarget(who: str, x: Incident): bool =
    isSelf(who, addressee(x))

  // §2.4. Отношение смотрящего к инциденту: ожидающий моего принятия — «мне адресован», даже если владельцем записан я (BUG-60)

  def ownership(who: str, x: Incident): str =
    (if (((x.state == "pending_acceptance") and isTarget(who, x))) "target" else (if ((x.owner == who)) "owner" else (if (isTarget(who, x)) "target" else "other")))

  // §10.2. Инциденты человека в состоянии, кроме одного — для лимитов; у привязанных владельца нет, в лимит они не входят

  def mineIn(xs: List[Incident], who: str, state: str, except: str): List[Incident] =
    xs.select(e_2 => (((e_2.state == state) and (e_2.owner == who)) and (e_2.id != except)))

  // Условие «отношение ко мне» в scopeRule: владелец — мой инцидент, адресат — адресованный мне

  def matchesOwnership(who: str, x: Incident, role: str): bool =
    (if ((role == "owner")) (x.owner == who) else (if ((role == "target")) isTarget(who, x) else (ownership(who, x) == role)))

  // §5. Область права own: выполнено хоть одно из scopeRule.own.anyOf

  def scopeOwn(who: str, x: Incident, r: ScopeRule): bool =
    r.own.anyOf.foldl(false, (acc, c_3) => acc or (if ((c_3.state != "")) (x.state == c_3.state) else ((c_3.ownership != "") and matchesOwnership(who, x, c_3.ownership))))

  // Категория состояния инцидента — одна из cats (stateCategories)

  def inCategory(x: Incident, cats: List[str]): bool =
    settings.states.foldl(false, (acc, s_4) => acc or ((s_4.id == x.state) and cats.foldl(false, (acc, y5) => acc or y5 == s_4.category)))

  def isDone(x: Incident): bool =
    settings.states.foldl(false, (acc, s_6) => acc or ((s_6.id == x.state) and (s_6.category == "done")))

  // Инцидент по id — списком из одного или пустым

  def byId(xs: List[Incident], id: str): List[Incident] =
    xs.select(e_7 => (e_7.id == id))

  // §5, §8.1. Доступ к объекту: человеку — по его ролям, группе — хотя бы у одного участника

  def hasAccess(who: str, x: Incident): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_8) => acc or access(m_8, x)) else (isOperator(who) and access(who, x)))

  def canAcceptPerson(m: str, x: Incident): bool =
    (can(m, "incident:accept") and access(m, x))

  // §8.1. Может ли принять: право «Принимать» и доступ к объекту; группа — если хотя бы один участник, кроме except: у него инцидент уже есть (RULE-93)

  def canAccept(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_9) => acc or ((m_9 != except) and canAcceptPerson(m_9, x))) else canAcceptPerson(who, x))

  // §8.1. Дежурная группа человека — первая, в которую он входит

  def dutyGroupOf(who: str): str =
    { val gs_10 = dutyGroups.select(g_11 => members(g_11).foldl(false, (acc, y12) => acc or y12 == who))  (if ((gs_10.length() > 0)) gs_10[0] else "") }

  // §8.3. Уровни автоэскалации выше текущего и не выше потолка, адресат которых может принять; уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)

  def nextLevels(x: Incident): List[Level] =
    settings.escalation.levels.select(l_13 => ((((l_13.level > x.escalationLevel) and (l_13.level <= settings.escalation.maxLevel)) and (l_13.target != addressee(x))) and canAccept(l_13.target, x, x.owner)))

  // §2.2. Результаты закрытия, которые этот оператор может выбрать для инцидента

  def closeOptions(who: str, x: Incident, surface: str): List[CloseResultItem] =
    settings.closeResults.select(i_14 => (((can(who, i_14.permission) and i_14.fromStates.foldl(false, (acc, y15) => acc or y15 == x.state)) and not((i_14.ownerOnlyInStates.foldl(false, (acc, y16) => acc or y16 == x.state) and (x.owner != who)))) and (((surface == "") or (i_14.surfaces.length() == 0)) or i_14.surfaces.foldl(false, (acc, y17) => acc or y17 == surface))))

  def stepsOk(i: CloseResultItem, x: Incident): bool =
    ((i.requiredStepSet == "none") or stepsFilled(x, i.requiredStepSet))

  // Адресат, если это человек, иначе пусто: так в owner попадает только человек

  def personOf(id: str): str =
    (if (((id != "") and not(isGroup(id)))) id else "")

  // Адресат, если это дежурная группа, иначе пусто: так группа попадает в assignmentGroup

  def groupOf(id: str): str =
    (if (((id != "") and isGroup(id))) id else "")

  // §8.3. Уровень, на который уходит инцидент: ближайший из nextLevels — списком из одного или пустым

  def levelUp(x: Incident): List[Level] =
    { val ls_18 = nextLevels(x)  ls_18.select(l_19 => ls_18.foldl(true, (acc, k_20) => acc and (l_19.level <= k_20.level))) }

  def levelUpTarget(x: Incident): str =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].target else "")

  def levelUpNumber(x: Incident): int =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].level else 0)

  def timerDef(id: str): TimerDef =
    settings.timerDefs.select(t_21 => (t_21.id == id))[0]

  // Сколько условий у строки overrides: чем больше, тем строка специфичнее

  def overrideKeys(o: Override): int =
    (((o.eventType.length() + o.priority.length()) + o.sourceGroup.length()) + o.escalationLevel.length())

  def overrideMatches(x: Incident, o: Override): bool =
    (((((o.eventType.length() == 0) or (o.eventType[0] == x.eventType)) and ((o.priority.length() == 0) or (o.priority[0] == x.priority))) and ((o.sourceGroup.length() == 0) or inSourceGroup(x, o.sourceGroup[0]))) and ((o.escalationLevel.length() == 0) or (o.escalationLevel[0] == x.escalationLevel)))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (при равных — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_22 = t.overrides.select(o_23 => overrideMatches(x, o_23))  (if ((ms_22.length() > 0)) ms_22.select(o_24 => ms_22.foldl(true, (acc, k_25) => acc and (overrideKeys(k_25) <= overrideKeys(o_24))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold); причины нет — -1, срок не ставится

  def holdSec(x: Incident): int =
    { val rs_26 = settings.holdReasons.select(r_27 => (r_27.id == x.holdReasonId))  (if ((rs_26.length() > 0)) (rs_26[0].maxMinutes * 60) else (0 - 1)) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_28 = settings.escalation.levels.select(l_29 => (l_29.level == x.escalationLevel))  (if ((ls_28.length() > 0)) ls_28[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_30 = x.timers.get(id)  (if ((t_30.due != 0)) (if (((t_30.due - now) > 0)) (t_30.due - now) else 0) else (if (t_30.paused) t_30.left else (0 - 1))) }

  // RULE-50. Норматив нарушен и отработан: остатка нет, дедлайн сработал

  def spent(x: Incident, id: str, now: int): bool =
    ((leftOf(x, id, now) == 0) and (x.timers.get(id).fired != 0))

  // §11.4, BUG-73, BUG-75. Был в группе основного p в момент at: открытый привязанный, присоединённый не позже, или вышедший не раньше

  def inGroupAt(e: Incident, p: Incident, at: int): bool =
    ((((e.linkedTo == p.id) and not(isDone(e))) and (e.linkedAt <= at)) or (((e.leftGroup.primaryId == p.id) and (e.leftGroup.linkedAt <= at)) and (e.leftGroup.at >= at)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w31 = if (not(timerDef(timerId).pausable)) {
      val sec_32 = timerSec(w0.inc.get(iid), timerId, "")
      val w33 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_32 < 0)) 0 else (c.now + (sec_32 * 1000))) }) }) }
      val w34 = { ...w33, inc: w33.inc.set(iid, { ...w33.inc.get(iid), timers: w33.inc.get(iid).timers.set(timerId, { ...w33.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w34
    } else {
      val w35 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_36 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w37 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_36 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_36)) }) }) }
      val w38 = { ...w37, inc: w37.inc.set(iid, { ...w37.inc.get(iid), timers: w37.inc.get(iid).timers.set(timerId, { ...w37.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w39 = { ...w38, inc: w38.inc.set(iid, { ...w38.inc.get(iid), timers: w38.inc.get(iid).timers.set(timerId, { ...w38.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w39
    } else w0
      w35
    }
    w31
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w40 = if (not(timerDef(timerId).pausable)) {
      val w41 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w42 = { ...w41, inc: w41.inc.set(iid, { ...w41.inc.get(iid), timers: w41.inc.get(iid).timers.set(timerId, { ...w41.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w42
    } else {
      val w43 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w44 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w45 = { ...w44, inc: w44.inc.set(iid, { ...w44.inc.get(iid), timers: w44.inc.get(iid).timers.set(timerId, { ...w44.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w46 = { ...w45, inc: w45.inc.set(iid, { ...w45.inc.get(iid), timers: w45.inc.get(iid).timers.set(timerId, { ...w45.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w46
    } else w0
      w43
    }
    w40
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_47 = ""
    val w48 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_47 }) }
    w48
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_49 = ""
    val w50 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_49 }) }
    w50
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_51 = 0
    val w52 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_51 }) }
    w52
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w53 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w54 = if (timerDef("reaction").startsOnce) {
      val w55 = ec_resumeTimer(w0, c, iid, "reaction")
      w55
    } else {
      val sec_56 = timerSec(w0.inc.get(iid), "reaction", "")
      val w57 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_56 < 0)) 0 else (c.now + (sec_56 * 1000))) }) }) }
      val w58 = { ...w57, inc: w57.inc.set(iid, { ...w57.inc.get(iid), timers: w57.inc.get(iid).timers.set("reaction", { ...w57.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w58
    }
      w54
    }
    w53
  }

  def e_create_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_create(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_create_0(ws, c1, iid)
    val w2 = e_create_1(w1, c1, iid)
    val w3 = e_create_2(w2, c1, iid)
    val w4 = e_create_3(w3, c1, iid)
    val w5 = e_create_4(w4, c1, iid)
    w5
  }

  // claim: manual → in_progress

  def ok_claim(c: Ctx, iid: str): bool = all {
    Set("new").contains(world.inc.get(iid).state),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_59) => acc or ((s_59.id == agentState(c.me)) and s_59.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_60 = c.actor
    val w61 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_60 }) }
    w61
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w62 = if (timerDef("reaction").startsOnce) {
      val w63 = ec_pauseTimer(w0, c, iid, "reaction")
      w63
    } else {
      val w64 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w65 = { ...w64, inc: w64.inc.set(iid, { ...w64.inc.get(iid), timers: w64.inc.get(iid).timers.set("reaction", { ...w64.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w65
    }
    w62
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w66 = if (not(timerDef("resolution").pausable)) {
      val sec_67 = timerSec(w0.inc.get(iid), "resolution", "")
      val w68 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_67 < 0)) 0 else (c.now + (sec_67 * 1000))) }) }) }
      val w69 = { ...w68, inc: w68.inc.set(iid, { ...w68.inc.get(iid), timers: w68.inc.get(iid).timers.set("resolution", { ...w68.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w69
    } else {
      val w70 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_71 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w72 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_71 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_71)) }) }) }
      val w73 = { ...w72, inc: w72.inc.set(iid, { ...w72.inc.get(iid), timers: w72.inc.get(iid).timers.set("resolution", { ...w72.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w74 = { ...w73, inc: w73.inc.set(iid, { ...w73.inc.get(iid), timers: w73.inc.get(iid).timers.set("resolution", { ...w73.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w74
    } else w0
      w70
    }
    w66
  }

  def e_claim_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_claim_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_claim(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_claim_0(ws, c1, iid)
    val w2 = e_claim_1(w1, c1, iid)
    val w3 = e_claim_2(w2, c1, iid)
    val w4 = e_claim_3(w3, c1, iid)
    val w5 = e_claim_4(w4, c1, iid)
    w5
  }

  // accept: manual → in_progress

  def ok_accept(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    can(c.me, "incident:accept"),
    isTarget(c.me, world.inc.get(iid)),
    not(settings.session.states.foldl(false, (acc, s_75) => acc or ((s_75.id == agentState(c.me)) and s_75.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_76 = c.actor
    val w77 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_76 }) }
    w77
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_78 = ""
    val w79 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_78 }) }
    w79
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w80 = if (timerDef("reaction").startsOnce) {
      val w81 = ec_pauseTimer(w0, c, iid, "reaction")
      w81
    } else {
      val w82 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w83 = { ...w82, inc: w82.inc.set(iid, { ...w82.inc.get(iid), timers: w82.inc.get(iid).timers.set("reaction", { ...w82.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w83
    }
    w80
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w84 = if (not(timerDef("resolution").pausable)) {
      val sec_85 = timerSec(w0.inc.get(iid), "resolution", "")
      val w86 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_85 < 0)) 0 else (c.now + (sec_85 * 1000))) }) }) }
      val w87 = { ...w86, inc: w86.inc.set(iid, { ...w86.inc.get(iid), timers: w86.inc.get(iid).timers.set("resolution", { ...w86.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w87
    } else {
      val w88 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_89 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w90 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_89 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_89)) }) }) }
      val w91 = { ...w90, inc: w90.inc.set(iid, { ...w90.inc.get(iid), timers: w90.inc.get(iid).timers.set("resolution", { ...w90.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w92 = { ...w91, inc: w91.inc.set(iid, { ...w91.inc.get(iid), timers: w91.inc.get(iid).timers.set("resolution", { ...w91.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w92
    } else w0
      w88
    }
    w84
  }

  def e_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_accept_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_accept(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_accept_0(ws, c1, iid)
    val w2 = e_accept_1(w1, c1, iid)
    val w3 = e_accept_2(w2, c1, iid)
    val w4 = e_accept_3(w3, c1, iid)
    val w5 = e_accept_4(w4, c1, iid)
    val w6 = e_accept_5(w5, c1, iid)
    w6
  }

  // reject: manual → new

  def ok_reject(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    can(c.me, "incident:release"),
    isTarget(c.me, world.inc.get(iid)),
    not(settings.session.states.foldl(false, (acc, s_93) => acc or ((s_93.id == agentState(c.me)) and s_93.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_94 = ""
    val w95 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_94 }) }
    w95
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_96 = ""
    val w97 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_96 }) }
    w97
  }

  def e_reject_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_reject(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_reject_0(ws, c1, iid)
    val w2 = e_reject_1(w1, c1, iid)
    val w3 = e_reject_2(w2, c1, iid)
    w3
  }

  // hold: manual → on_hold

  def ok_hold(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    can(c.me, "incident:hold"),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_98) => acc or ((s_98.id == agentState(c.me)) and s_98.readOnly))),
    ((settings.limits.maxOnHold == 0) or (mineIn(incs(world), c.me, "on_hold", world.inc.get(iid).id).length() < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_99 = c.form.reasonId
    val w100 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_99 }) }
    w100
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w101 = if (not(timerDef("resolution").pausable)) {
      val w102 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w103 = { ...w102, inc: w102.inc.set(iid, { ...w102.inc.get(iid), timers: w102.inc.get(iid).timers.set("resolution", { ...w102.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w103
    } else {
      val w104 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w105 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w106 = { ...w105, inc: w105.inc.set(iid, { ...w105.inc.get(iid), timers: w105.inc.get(iid).timers.set("resolution", { ...w105.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w107 = { ...w106, inc: w106.inc.set(iid, { ...w106.inc.get(iid), timers: w106.inc.get(iid).timers.set("resolution", { ...w106.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w107
    } else w0
      w104
    }
    w101
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w108 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w109 = if (timerDef("hold").startsOnce) {
      val w110 = ec_resumeTimer(w0, c, iid, "hold")
      w110
    } else {
      val sec_111 = timerSec(w0.inc.get(iid), "hold", "")
      val w112 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_111 < 0)) 0 else (c.now + (sec_111 * 1000))) }) }) }
      val w113 = { ...w112, inc: w112.inc.set(iid, { ...w112.inc.get(iid), timers: w112.inc.get(iid).timers.set("hold", { ...w112.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w113
    }
      w109
    }
    w108
  }

  def e_hold_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_hold(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "on_hold" }) }
    val w1 = e_hold_0(ws, c1, iid)
    val w2 = e_hold_1(w1, c1, iid)
    val w3 = e_hold_2(w2, c1, iid)
    val w4 = e_hold_3(w3, c1, iid)
    val w5 = e_hold_4(w4, c1, iid)
    w5
  }

  // resume: manual → in_progress

  def ok_resume(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:claim"),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_114) => acc or ((s_114.id == agentState(c.me)) and s_114.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w115 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w115
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w116 = if (timerDef("hold").startsOnce) {
      val w117 = ec_pauseTimer(w0, c, iid, "hold")
      w117
    } else {
      val w118 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w119 = { ...w118, inc: w118.inc.set(iid, { ...w118.inc.get(iid), timers: w118.inc.get(iid).timers.set("hold", { ...w118.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w119
    }
    w116
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w120 = if (not(timerDef("resolution").pausable)) {
      val sec_121 = timerSec(w0.inc.get(iid), "resolution", "")
      val w122 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_121 < 0)) 0 else (c.now + (sec_121 * 1000))) }) }) }
      val w123 = { ...w122, inc: w122.inc.set(iid, { ...w122.inc.get(iid), timers: w122.inc.get(iid).timers.set("resolution", { ...w122.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w123
    } else {
      val w124 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_125 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w126 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_125 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_125)) }) }) }
      val w127 = { ...w126, inc: w126.inc.set(iid, { ...w126.inc.get(iid), timers: w126.inc.get(iid).timers.set("resolution", { ...w126.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w128 = { ...w127, inc: w127.inc.set(iid, { ...w127.inc.get(iid), timers: w127.inc.get(iid).timers.set("resolution", { ...w127.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w128
    } else w0
      w124
    }
    w120
  }

  def e_resume_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resume_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_resume(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_resume_0(ws, c1, iid)
    val w2 = e_resume_1(w1, c1, iid)
    val w3 = e_resume_2(w2, c1, iid)
    val w4 = e_resume_3(w3, c1, iid)
    val w5 = e_resume_4(w4, c1, iid)
    w5
  }

  // release: manual → new

  def ok_release(c: Ctx, iid: str): bool = all {
    Set("in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:release"),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_129) => acc or ((s_129.id == agentState(c.me)) and s_129.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_130 = ""
    val w131 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_130 }) }
    w131
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w132 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w132
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w133 = if (not(timerDef("resolution").pausable)) {
      val w134 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w135 = { ...w134, inc: w134.inc.set(iid, { ...w134.inc.get(iid), timers: w134.inc.get(iid).timers.set("resolution", { ...w134.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w135
    } else {
      val w136 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w137 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w138 = { ...w137, inc: w137.inc.set(iid, { ...w137.inc.get(iid), timers: w137.inc.get(iid).timers.set("resolution", { ...w137.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w139 = { ...w138, inc: w138.inc.set(iid, { ...w138.inc.get(iid), timers: w138.inc.get(iid).timers.set("resolution", { ...w138.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w139
    } else w0
      w136
    }
    w133
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w140 = if (timerDef("hold").startsOnce) {
      val w141 = ec_pauseTimer(w0, c, iid, "hold")
      w141
    } else {
      val w142 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w143 = { ...w142, inc: w142.inc.set(iid, { ...w142.inc.get(iid), timers: w142.inc.get(iid).timers.set("hold", { ...w142.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w143
    }
    w140
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w144 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w145 = if (timerDef("reaction").startsOnce) {
      val w146 = ec_resumeTimer(w0, c, iid, "reaction")
      w146
    } else {
      val sec_147 = timerSec(w0.inc.get(iid), "reaction", "")
      val w148 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_147 < 0)) 0 else (c.now + (sec_147 * 1000))) }) }) }
      val w149 = { ...w148, inc: w148.inc.set(iid, { ...w148.inc.get(iid), timers: w148.inc.get(iid).timers.set("reaction", { ...w148.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w149
    }
      w145
    }
    w144
  }

  def e_release_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_release_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_release(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_release_0(ws, c1, iid)
    val w2 = e_release_1(w1, c1, iid)
    val w3 = e_release_2(w2, c1, iid)
    val w4 = e_release_3(w3, c1, iid)
    val w5 = e_release_4(w4, c1, iid)
    val w6 = e_release_5(w5, c1, iid)
    val w7 = e_release_6(w6, c1, iid)
    w7
  }

  // transfer: manual → pending_acceptance

  def ok_transfer(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, (if (scopeOwn(c.me, world.inc.get(iid), { own: { anyOf: [{ state: "new", ownership: "" }, { state: "", ownership: "owner" }, { state: "", ownership: "target" }] } })) "incident:transfer:own" else "incident:transfer:any")),
    not(settings.session.states.foldl(false, (acc, s_150) => acc or ((s_150.id == agentState(c.me)) and s_150.readOnly))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or incs(world).foldl(true, (acc, e_151) => acc and (((e_151.linkedTo != world.inc.get(iid).id) or isDone(e_151)) or hasAccess(c.form.targetId, e_151)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_152 = personOf(c.form.targetId)
    val w153 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_152 }) }
    w153
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_154 = groupOf(c.form.targetId)
    val w155 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_154 }) }
    w155
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w156 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w156
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w157 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w157
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w158 = if (not(timerDef("resolution").pausable)) {
      val w159 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w160 = { ...w159, inc: w159.inc.set(iid, { ...w159.inc.get(iid), timers: w159.inc.get(iid).timers.set("resolution", { ...w159.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w160
    } else {
      val w161 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w162 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w163 = { ...w162, inc: w162.inc.set(iid, { ...w162.inc.get(iid), timers: w162.inc.get(iid).timers.set("resolution", { ...w162.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w164 = { ...w163, inc: w163.inc.set(iid, { ...w163.inc.get(iid), timers: w163.inc.get(iid).timers.set("resolution", { ...w163.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w164
    } else w0
      w161
    }
    w158
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w165 = if (timerDef("hold").startsOnce) {
      val w166 = ec_pauseTimer(w0, c, iid, "hold")
      w166
    } else {
      val w167 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w168 = { ...w167, inc: w167.inc.set(iid, { ...w167.inc.get(iid), timers: w167.inc.get(iid).timers.set("hold", { ...w167.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w168
    }
    w165
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w169 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w170 = if (timerDef("reaction").startsOnce) {
      val w171 = ec_resumeTimer(w0, c, iid, "reaction")
      w171
    } else {
      val sec_172 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w173 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_172 < 0)) 0 else (c.now + (sec_172 * 1000))) }) }) }
      val w174 = { ...w173, inc: w173.inc.set(iid, { ...w173.inc.get(iid), timers: w173.inc.get(iid).timers.set("reaction", { ...w173.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w174
    }
      w170
    }
    w169
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_transfer(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_transfer_0(ws, c1, iid)
    val w2 = e_transfer_1(w1, c1, iid)
    val w3 = e_transfer_2(w2, c1, iid)
    val w4 = e_transfer_3(w3, c1, iid)
    val w5 = e_transfer_4(w4, c1, iid)
    val w6 = e_transfer_5(w5, c1, iid)
    val w7 = e_transfer_6(w6, c1, iid)
    val w8 = e_transfer_7(w7, c1, iid)
    val w9 = e_transfer_8(w8, c1, iid)
    val w10 = e_transfer_9(w9, c1, iid)
    val w11 = e_transfer_10(w10, c1, iid)
    w11
  }

  // takeover: manual → in_progress

  def ok_takeover(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:reassign"),
    can(c.me, "incident:claim"),
    (ownership(c.me, world.inc.get(iid)) != "owner"),
    (ownership(c.me, world.inc.get(iid)) != "target"),
    not(settings.session.states.foldl(false, (acc, s_175) => acc or ((s_175.id == agentState(c.me)) and s_175.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_176 = c.actor
    val w177 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_176 }) }
    w177
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_178 = ""
    val w179 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_178 }) }
    w179
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w180 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w180
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w181 = if (timerDef("reaction").startsOnce) {
      val w182 = ec_pauseTimer(w0, c, iid, "reaction")
      w182
    } else {
      val w183 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w184 = { ...w183, inc: w183.inc.set(iid, { ...w183.inc.get(iid), timers: w183.inc.get(iid).timers.set("reaction", { ...w183.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w184
    }
    w181
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w185 = if (timerDef("hold").startsOnce) {
      val w186 = ec_pauseTimer(w0, c, iid, "hold")
      w186
    } else {
      val w187 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w188 = { ...w187, inc: w187.inc.set(iid, { ...w187.inc.get(iid), timers: w187.inc.get(iid).timers.set("hold", { ...w187.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w188
    }
    w185
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w189 = if (not(timerDef("resolution").pausable)) {
      val sec_190 = timerSec(w0.inc.get(iid), "resolution", "")
      val w191 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_190 < 0)) 0 else (c.now + (sec_190 * 1000))) }) }) }
      val w192 = { ...w191, inc: w191.inc.set(iid, { ...w191.inc.get(iid), timers: w191.inc.get(iid).timers.set("resolution", { ...w191.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w192
    } else {
      val w193 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_194 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w195 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_194 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_194)) }) }) }
      val w196 = { ...w195, inc: w195.inc.set(iid, { ...w195.inc.get(iid), timers: w195.inc.get(iid).timers.set("resolution", { ...w195.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w197 = { ...w196, inc: w196.inc.set(iid, { ...w196.inc.get(iid), timers: w196.inc.get(iid).timers.set("resolution", { ...w196.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w197
    } else w0
      w193
    }
    w189
  }

  def e_takeover_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_9(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_takeover(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_takeover_0(ws, c1, iid)
    val w2 = e_takeover_1(w1, c1, iid)
    val w3 = e_takeover_2(w2, c1, iid)
    val w4 = e_takeover_3(w3, c1, iid)
    val w5 = e_takeover_4(w4, c1, iid)
    val w6 = e_takeover_5(w5, c1, iid)
    val w7 = e_takeover_6(w6, c1, iid)
    val w8 = e_takeover_7(w7, c1, iid)
    val w9 = e_takeover_8(w8, c1, iid)
    val w10 = e_takeover_9(w9, c1, iid)
    w10
  }

  // close: manual → closed

  def ok_close(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    not(settings.session.states.foldl(false, (acc, s_198) => acc or ((s_198.id == agentState(c.me)) and s_198.readOnly))),
    { val os_199 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_199.foldl(false, (acc, o_200) => acc or ((o_200.id == c.form.resultId) and stepsOk(o_200, world.inc.get(iid)))) else os_199.foldl(false, (acc, o_201) => acc or stepsOk(o_201, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_202 = c.actor
    val w203 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_202 }) }
    w203
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_204 = ""
    val w205 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_204 }) }
    w205
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_206 = c.actor
    val w207 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_206 }) }
    w207
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_208 = c.now
    val w209 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_208 }) }
    w209
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_210 = c.form.resultId
    val w211 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_210 }) }
    w211
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_212 = c.form.causeId
    val w213 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_212 }) }
    w213
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_214 = c.form.comment
    val w215 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_214 }) }
    w215
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w216 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w216
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w217 = if (timerDef("reaction").startsOnce) {
      val w218 = ec_pauseTimer(w0, c, iid, "reaction")
      w218
    } else {
      val w219 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w220 = { ...w219, inc: w219.inc.set(iid, { ...w219.inc.get(iid), timers: w219.inc.get(iid).timers.set("reaction", { ...w219.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w220
    }
    w217
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w221 = if (not(timerDef("resolution").pausable)) {
      val w222 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w223 = { ...w222, inc: w222.inc.set(iid, { ...w222.inc.get(iid), timers: w222.inc.get(iid).timers.set("resolution", { ...w222.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w223
    } else {
      val w224 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w225 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w226 = { ...w225, inc: w225.inc.set(iid, { ...w225.inc.get(iid), timers: w225.inc.get(iid).timers.set("resolution", { ...w225.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w227 = { ...w226, inc: w226.inc.set(iid, { ...w226.inc.get(iid), timers: w226.inc.get(iid).timers.set("resolution", { ...w226.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w227
    } else w0
      w224
    }
    w221
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w228 = if (timerDef("hold").startsOnce) {
      val w229 = ec_pauseTimer(w0, c, iid, "hold")
      w229
    } else {
      val w230 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w231 = { ...w230, inc: w230.inc.set(iid, { ...w230.inc.get(iid), timers: w230.inc.get(iid).timers.set("hold", { ...w230.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w231
    }
    w228
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_13(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_close(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "closed" }) }
    val w1 = e_close_0(ws, c1, iid)
    val w2 = e_close_1(w1, c1, iid)
    val w3 = e_close_2(w2, c1, iid)
    val w4 = e_close_3(w3, c1, iid)
    val w5 = e_close_4(w4, c1, iid)
    val w6 = e_close_5(w5, c1, iid)
    val w7 = e_close_6(w6, c1, iid)
    val w8 = e_close_7(w7, c1, iid)
    val w9 = e_close_8(w8, c1, iid)
    val w10 = e_close_9(w9, c1, iid)
    val w11 = e_close_10(w10, c1, iid)
    val w12 = e_close_11(w11, c1, iid)
    val w13 = e_close_12(w12, c1, iid)
    val w14 = e_close_13(w13, c1, iid)
    w14
  }

  // reopen: manual → in_progress

  def ok_reopen(c: Ctx, iid: str): bool = all {
    Set("closed").contains(world.inc.get(iid).state),
    can(c.me, "incident:reopen"),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_232) => acc or ((s_232.id == agentState(c.me)) and s_232.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_233 = c.actor
    val w234 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_233 }) }
    w234
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w235 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_236 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w237 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w238 = { ...w237, inc: w237.inc.set(iid, { ...w237.inc.get(iid), linkedTo: "" }) }
      val w239 = { ...w238, inc: w238.inc.set(iid, { ...w238.inc.get(iid), linkedAt: 0 }) }
      val w240 = if (((ps_236.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w239 else w239
      val w241 = if (("workflow.journal.linked_reopened" != "")) {
      val w242 = ps_236.foldl([], (acc, x245) => acc.append(x245.id)).foldl(w240, (wf243, pId244) => wf243)
      w242
    } else w240
      w241
    } else {
      val w246 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w247 = { ...w246, inc: w246.inc.set(iid, { ...w246.inc.get(iid), linkedAt: 0 }) }
      w247
    }
    w235
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_248 = ""
    val w249 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_248 }) }
    w249
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_250 = ""
    val w251 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_250 }) }
    w251
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val sec_252 = settings.limits.reopenResolutionSec
    val w253 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_252 > 0)) sec_252 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("resolution", { ...w253.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w255 = { ...w254, inc: w254.inc.set(iid, { ...w254.inc.get(iid), timers: w254.inc.get(iid).timers.set("resolution", { ...w254.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w255
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_reopen(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_reopen_0(ws, c1, iid)
    val w2 = e_reopen_1(w1, c1, iid)
    val w3 = e_reopen_2(w2, c1, iid)
    val w4 = e_reopen_3(w3, c1, iid)
    val w5 = e_reopen_4(w4, c1, iid)
    val w6 = e_reopen_5(w5, c1, iid)
    val w7 = e_reopen_6(w6, c1, iid)
    w7
  }

  // auto_escalate: timer → pending_acceptance

  def ok_auto_escalate(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == true),
    { val t_256 = world.inc.get(iid).timers.get("reaction")  (((t_256.due != 0) and (t_256.due <= c.now)) and (t_256.fired != t_256.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_257 = personOf(levelUpTarget(c.before))
    val w258 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_257 }) }
    w258
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_259 = groupOf(levelUpTarget(c.before))
    val w260 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_259 }) }
    w260
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_261 = levelUpNumber(c.before)
    val w262 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_261 }) }
    w262
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w263 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w263
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w264 = if (not(timerDef("resolution").pausable)) {
      val w265 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w266 = { ...w265, inc: w265.inc.set(iid, { ...w265.inc.get(iid), timers: w265.inc.get(iid).timers.set("resolution", { ...w265.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w266
    } else {
      val w267 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w268 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w269 = { ...w268, inc: w268.inc.set(iid, { ...w268.inc.get(iid), timers: w268.inc.get(iid).timers.set("resolution", { ...w268.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w270 = { ...w269, inc: w269.inc.set(iid, { ...w269.inc.get(iid), timers: w269.inc.get(iid).timers.set("resolution", { ...w269.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w270
    } else w0
      w267
    }
    w264
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w271 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w272 = if (timerDef("reaction").startsOnce) {
      val w273 = ec_resumeTimer(w0, c, iid, "reaction")
      w273
    } else {
      val sec_274 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w275 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_274 < 0)) 0 else (c.now + (sec_274 * 1000))) }) }) }
      val w276 = { ...w275, inc: w275.inc.set(iid, { ...w275.inc.get(iid), timers: w275.inc.get(iid).timers.set("reaction", { ...w275.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w276
    }
      w272
    }
    w271
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_auto_escalate(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_auto_escalate_0(ws, c1, iid)
    val w2 = e_auto_escalate_1(w1, c1, iid)
    val w3 = e_auto_escalate_2(w2, c1, iid)
    val w4 = e_auto_escalate_3(w3, c1, iid)
    val w5 = e_auto_escalate_4(w4, c1, iid)
    val w6 = e_auto_escalate_5(w5, c1, iid)
    val w7 = e_auto_escalate_6(w6, c1, iid)
    val w8 = e_auto_escalate_7(w7, c1, iid)
    val w9 = e_auto_escalate_8(w8, c1, iid)
    w9
  }

  // escalation_ceiling: timer

  def ok_escalation_ceiling(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == true),
    { val t_277 = world.inc.get(iid).timers.get("reaction")  (((t_277.due != 0) and (t_277.due <= c.now)) and (t_277.fired != t_277.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_278 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w279 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_278) }) }
    val w280 = { ...w279, inc: w279.inc.set(iid, { ...w279.inc.get(iid), slaBreached: true }) }
    val w281 = incs(w0).select(e_289 => ((e_289.id != w280.inc.get(iid).id) and inGroupAt(e_289, w280.inc.get(iid), c.deadline))).foldl([], (acc, x284) => acc.append(x284.id)).foldl(w280, (wf282, eId283) => {
      val w285 = { ...wf282, inc: wf282.inc.set(eId283, { ...wf282.inc.get(eId283), breaches: wf282.inc.get(eId283).breaches.append(breach_278) }) }
      val w286 = { ...w285, inc: w285.inc.set(eId283, { ...w285.inc.get(eId283), slaBreached: true }) }
      val w287 = if ((leftOf(w286.inc.get(eId283), "reaction", c.now) == 0)) {
      val w288 = { ...w286, inc: w286.inc.set(eId283, { ...w286.inc.get(eId283), timers: w286.inc.get(eId283).timers.set("reaction", { ...w286.inc.get(eId283).timers.get("reaction"), fired: c.deadline }) }) }
      w288
    } else w286
      w287
    })
    w281
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w290 = if (timerDef("reaction").startsOnce) {
      val w291 = ec_pauseTimer(w0, c, iid, "reaction")
      w291
    } else {
      val w292 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w293 = { ...w292, inc: w292.inc.set(iid, { ...w292.inc.get(iid), timers: w292.inc.get(iid).timers.set("reaction", { ...w292.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w293
    }
    w290
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_escalation_ceiling(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_escalation_ceiling_0(w0, c1, iid)
    val w2 = e_escalation_ceiling_1(w1, c1, iid)
    val w3 = e_escalation_ceiling_2(w2, c1, iid)
    val w4 = e_escalation_ceiling_3(w3, c1, iid)
    w4
  }

  // reaction_overdue: timer

  def ok_reaction_overdue(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == false),
    { val t_294 = world.inc.get(iid).timers.get("reaction")  (((t_294.due != 0) and (t_294.due <= c.now)) and (t_294.fired != t_294.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_295 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w296 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_295) }) }
    val w297 = { ...w296, inc: w296.inc.set(iid, { ...w296.inc.get(iid), slaBreached: true }) }
    val w298 = incs(w0).select(e_306 => ((e_306.id != w297.inc.get(iid).id) and inGroupAt(e_306, w297.inc.get(iid), c.deadline))).foldl([], (acc, x301) => acc.append(x301.id)).foldl(w297, (wf299, eId300) => {
      val w302 = { ...wf299, inc: wf299.inc.set(eId300, { ...wf299.inc.get(eId300), breaches: wf299.inc.get(eId300).breaches.append(breach_295) }) }
      val w303 = { ...w302, inc: w302.inc.set(eId300, { ...w302.inc.get(eId300), slaBreached: true }) }
      val w304 = if ((leftOf(w303.inc.get(eId300), "reaction", c.now) == 0)) {
      val w305 = { ...w303, inc: w303.inc.set(eId300, { ...w303.inc.get(eId300), timers: w303.inc.get(eId300).timers.set("reaction", { ...w303.inc.get(eId300).timers.get("reaction"), fired: c.deadline }) }) }
      w305
    } else w303
      w304
    })
    w298
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w307 = if (timerDef("reaction").startsOnce) {
      val w308 = ec_pauseTimer(w0, c, iid, "reaction")
      w308
    } else {
      val w309 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w310 = { ...w309, inc: w309.inc.set(iid, { ...w309.inc.get(iid), timers: w309.inc.get(iid).timers.set("reaction", { ...w309.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w310
    }
    w307
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_reaction_overdue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_reaction_overdue_0(w0, c1, iid)
    val w2 = e_reaction_overdue_1(w1, c1, iid)
    val w3 = e_reaction_overdue_2(w2, c1, iid)
    val w4 = e_reaction_overdue_3(w3, c1, iid)
    w4
  }

  // resolution_overdue: timer

  def ok_resolution_overdue(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    { val t_311 = world.inc.get(iid).timers.get("resolution")  (((t_311.due != 0) and (t_311.due <= c.now)) and (t_311.fired != t_311.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_312 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w313 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_312) }) }
    val w314 = { ...w313, inc: w313.inc.set(iid, { ...w313.inc.get(iid), slaBreached: true }) }
    val w315 = incs(w0).select(e_323 => ((e_323.id != w314.inc.get(iid).id) and inGroupAt(e_323, w314.inc.get(iid), c.deadline))).foldl([], (acc, x318) => acc.append(x318.id)).foldl(w314, (wf316, eId317) => {
      val w319 = { ...wf316, inc: wf316.inc.set(eId317, { ...wf316.inc.get(eId317), breaches: wf316.inc.get(eId317).breaches.append(breach_312) }) }
      val w320 = { ...w319, inc: w319.inc.set(eId317, { ...w319.inc.get(eId317), slaBreached: true }) }
      val w321 = if ((leftOf(w320.inc.get(eId317), "resolution", c.now) == 0)) {
      val w322 = { ...w320, inc: w320.inc.set(eId317, { ...w320.inc.get(eId317), timers: w320.inc.get(eId317).timers.set("resolution", { ...w320.inc.get(eId317).timers.get("resolution"), fired: c.deadline }) }) }
      w322
    } else w320
      w321
    })
    w315
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_resolution_overdue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_resolution_overdue_0(w0, c1, iid)
    val w2 = e_resolution_overdue_1(w1, c1, iid)
    val w3 = e_resolution_overdue_2(w2, c1, iid)
    w3
  }

  // resolution_escalate: timer → pending_acceptance

  def ok_resolution_escalate(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (settings.escalation.onResolutionOverdue == "escalate"),
    { val t_324 = world.inc.get(iid).timers.get("resolution")  (((t_324.due != 0) and (t_324.due <= c.now)) and (t_324.fired != t_324.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_325 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w326 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_325) }) }
    val w327 = { ...w326, inc: w326.inc.set(iid, { ...w326.inc.get(iid), slaBreached: true }) }
    val w328 = incs(w0).select(e_336 => ((e_336.id != w327.inc.get(iid).id) and inGroupAt(e_336, w327.inc.get(iid), c.deadline))).foldl([], (acc, x331) => acc.append(x331.id)).foldl(w327, (wf329, eId330) => {
      val w332 = { ...wf329, inc: wf329.inc.set(eId330, { ...wf329.inc.get(eId330), breaches: wf329.inc.get(eId330).breaches.append(breach_325) }) }
      val w333 = { ...w332, inc: w332.inc.set(eId330, { ...w332.inc.get(eId330), slaBreached: true }) }
      val w334 = if ((leftOf(w333.inc.get(eId330), "resolution", c.now) == 0)) {
      val w335 = { ...w333, inc: w333.inc.set(eId330, { ...w333.inc.get(eId330), timers: w333.inc.get(eId330).timers.set("resolution", { ...w333.inc.get(eId330).timers.get("resolution"), fired: c.deadline }) }) }
      w335
    } else w333
      w334
    })
    w328
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_337 = personOf(levelUpTarget(c.before))
    val w338 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_337 }) }
    w338
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_339 = groupOf(levelUpTarget(c.before))
    val w340 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_339 }) }
    w340
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_341 = levelUpNumber(c.before)
    val w342 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_341 }) }
    w342
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w343 = if (not(timerDef("resolution").pausable)) {
      val w344 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w345 = { ...w344, inc: w344.inc.set(iid, { ...w344.inc.get(iid), timers: w344.inc.get(iid).timers.set("resolution", { ...w344.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w345
    } else {
      val w346 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w347 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w348 = { ...w347, inc: w347.inc.set(iid, { ...w347.inc.get(iid), timers: w347.inc.get(iid).timers.set("resolution", { ...w347.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w349 = { ...w348, inc: w348.inc.set(iid, { ...w348.inc.get(iid), timers: w348.inc.get(iid).timers.set("resolution", { ...w348.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w349
    } else w0
      w346
    }
    w343
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w350 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w351 = if (timerDef("reaction").startsOnce) {
      val w352 = ec_resumeTimer(w0, c, iid, "reaction")
      w352
    } else {
      val sec_353 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w354 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_353 < 0)) 0 else (c.now + (sec_353 * 1000))) }) }) }
      val w355 = { ...w354, inc: w354.inc.set(iid, { ...w354.inc.get(iid), timers: w354.inc.get(iid).timers.set("reaction", { ...w354.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w355
    }
      w351
    }
    w350
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_resolution_escalate(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_resolution_escalate_0(ws, c1, iid)
    val w2 = e_resolution_escalate_1(w1, c1, iid)
    val w3 = e_resolution_escalate_2(w2, c1, iid)
    val w4 = e_resolution_escalate_3(w3, c1, iid)
    val w5 = e_resolution_escalate_4(w4, c1, iid)
    val w6 = e_resolution_escalate_5(w5, c1, iid)
    val w7 = e_resolution_escalate_6(w6, c1, iid)
    val w8 = e_resolution_escalate_7(w7, c1, iid)
    val w9 = e_resolution_escalate_8(w8, c1, iid)
    val w10 = e_resolution_escalate_9(w9, c1, iid)
    w10
  }

  // resolution_ceiling: timer

  def ok_resolution_ceiling(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (settings.escalation.onResolutionOverdue == "escalate"),
    { val t_356 = world.inc.get(iid).timers.get("resolution")  (((t_356.due != 0) and (t_356.due <= c.now)) and (t_356.fired != t_356.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_357 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w358 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_357) }) }
    val w359 = { ...w358, inc: w358.inc.set(iid, { ...w358.inc.get(iid), slaBreached: true }) }
    val w360 = incs(w0).select(e_368 => ((e_368.id != w359.inc.get(iid).id) and inGroupAt(e_368, w359.inc.get(iid), c.deadline))).foldl([], (acc, x363) => acc.append(x363.id)).foldl(w359, (wf361, eId362) => {
      val w364 = { ...wf361, inc: wf361.inc.set(eId362, { ...wf361.inc.get(eId362), breaches: wf361.inc.get(eId362).breaches.append(breach_357) }) }
      val w365 = { ...w364, inc: w364.inc.set(eId362, { ...w364.inc.get(eId362), slaBreached: true }) }
      val w366 = if ((leftOf(w365.inc.get(eId362), "resolution", c.now) == 0)) {
      val w367 = { ...w365, inc: w365.inc.set(eId362, { ...w365.inc.get(eId362), timers: w365.inc.get(eId362).timers.set("resolution", { ...w365.inc.get(eId362).timers.get("resolution"), fired: c.deadline }) }) }
      w367
    } else w365
      w366
    })
    w360
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_resolution_ceiling(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_resolution_ceiling_0(w0, c1, iid)
    val w2 = e_resolution_ceiling_1(w1, c1, iid)
    val w3 = e_resolution_ceiling_2(w2, c1, iid)
    w3
  }

  // hold_overdue: timer

  def ok_hold_overdue(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    { val t_369 = world.inc.get(iid).timers.get("hold")  (((t_369.due != 0) and (t_369.due <= c.now)) and (t_369.fired != t_369.due)) },
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_370 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w371 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_370) }) }
    val w372 = { ...w371, inc: w371.inc.set(iid, { ...w371.inc.get(iid), slaBreached: true }) }
    val w373 = incs(w0).select(e_381 => ((e_381.id != w372.inc.get(iid).id) and inGroupAt(e_381, w372.inc.get(iid), c.deadline))).foldl([], (acc, x376) => acc.append(x376.id)).foldl(w372, (wf374, eId375) => {
      val w377 = { ...wf374, inc: wf374.inc.set(eId375, { ...wf374.inc.get(eId375), breaches: wf374.inc.get(eId375).breaches.append(breach_370) }) }
      val w378 = { ...w377, inc: w377.inc.set(eId375, { ...w377.inc.get(eId375), slaBreached: true }) }
      val w379 = if ((leftOf(w378.inc.get(eId375), "hold", c.now) == 0)) {
      val w380 = { ...w378, inc: w378.inc.set(eId375, { ...w378.inc.get(eId375), timers: w378.inc.get(eId375).timers.set("hold", { ...w378.inc.get(eId375).timers.get("hold"), fired: c.deadline }) }) }
      w380
    } else w378
      w379
    })
    w373
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_hold_overdue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_hold_overdue_0(w0, c1, iid)
    val w2 = e_hold_overdue_1(w1, c1, iid)
    val w3 = e_hold_overdue_2(w2, c1, iid)
    w3
  }

  // system_hold_break: system → on_hold

  def ok_system_hold_break(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (agentState(c.me) == "not_ready"),
  }

  def e_system_hold_break_0(w0: World, c: Ctx, iid: str): World = {
    val reason_382 = "break"
    val w383 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_382 }) }
    w383
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w384 = if (not(timerDef("resolution").pausable)) {
      val w385 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w386 = { ...w385, inc: w385.inc.set(iid, { ...w385.inc.get(iid), timers: w385.inc.get(iid).timers.set("resolution", { ...w385.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w386
    } else {
      val w387 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w388 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w389 = { ...w388, inc: w388.inc.set(iid, { ...w388.inc.get(iid), timers: w388.inc.get(iid).timers.set("resolution", { ...w388.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w390 = { ...w389, inc: w389.inc.set(iid, { ...w389.inc.get(iid), timers: w389.inc.get(iid).timers.set("resolution", { ...w389.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w390
    } else w0
      w387
    }
    w384
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w391 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w392 = if (timerDef("hold").startsOnce) {
      val w393 = ec_resumeTimer(w0, c, iid, "hold")
      w393
    } else {
      val sec_394 = timerSec(w0.inc.get(iid), "hold", "")
      val w395 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_394 < 0)) 0 else (c.now + (sec_394 * 1000))) }) }) }
      val w396 = { ...w395, inc: w395.inc.set(iid, { ...w395.inc.get(iid), timers: w395.inc.get(iid).timers.set("hold", { ...w395.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w396
    }
      w392
    }
    w391
  }

  def e_system_hold_break_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_break_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_system_hold_break(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "on_hold" }) }
    val w1 = e_system_hold_break_0(ws, c1, iid)
    val w2 = e_system_hold_break_1(w1, c1, iid)
    val w3 = e_system_hold_break_2(w2, c1, iid)
    val w4 = e_system_hold_break_3(w3, c1, iid)
    val w5 = e_system_hold_break_4(w4, c1, iid)
    w5
  }

  // system_hold_idle: system → on_hold

  def ok_system_hold_idle(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (idleSec(c.me) >= settings.session.idleHoldSec),
  }

  def e_system_hold_idle_0(w0: World, c: Ctx, iid: str): World = {
    val reason_397 = "no_link"
    val w398 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_397 }) }
    w398
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w399 = if (not(timerDef("resolution").pausable)) {
      val w400 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w401 = { ...w400, inc: w400.inc.set(iid, { ...w400.inc.get(iid), timers: w400.inc.get(iid).timers.set("resolution", { ...w400.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w401
    } else {
      val w402 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w403 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w404 = { ...w403, inc: w403.inc.set(iid, { ...w403.inc.get(iid), timers: w403.inc.get(iid).timers.set("resolution", { ...w403.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w405 = { ...w404, inc: w404.inc.set(iid, { ...w404.inc.get(iid), timers: w404.inc.get(iid).timers.set("resolution", { ...w404.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w405
    } else w0
      w402
    }
    w399
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w406 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w407 = if (timerDef("hold").startsOnce) {
      val w408 = ec_resumeTimer(w0, c, iid, "hold")
      w408
    } else {
      val sec_409 = timerSec(w0.inc.get(iid), "hold", "")
      val w410 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_409 < 0)) 0 else (c.now + (sec_409 * 1000))) }) }) }
      val w411 = { ...w410, inc: w410.inc.set(iid, { ...w410.inc.get(iid), timers: w410.inc.get(iid).timers.set("hold", { ...w410.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w411
    }
      w407
    }
    w406
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_system_hold_idle(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "on_hold" }) }
    val w1 = e_system_hold_idle_0(ws, c1, iid)
    val w2 = e_system_hold_idle_1(w1, c1, iid)
    val w3 = e_system_hold_idle_2(w2, c1, iid)
    val w4 = e_system_hold_idle_3(w3, c1, iid)
    val w5 = e_system_hold_idle_4(w4, c1, iid)
    w5
  }

  // system_release_idle: system → new

  def ok_system_release_idle(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    (idleSec(c.me) >= settings.session.idleReleaseSec),
    ["break", "no_link"].foldl(false, (acc, y412) => acc or y412 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_413 = ""
    val w414 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_413 }) }
    w414
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w415 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w415
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w416 = if (timerDef("hold").startsOnce) {
      val w417 = ec_pauseTimer(w0, c, iid, "hold")
      w417
    } else {
      val w418 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w419 = { ...w418, inc: w418.inc.set(iid, { ...w418.inc.get(iid), timers: w418.inc.get(iid).timers.set("hold", { ...w418.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w419
    }
    w416
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w420 = if (not(timerDef("resolution").pausable)) {
      val w421 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w422 = { ...w421, inc: w421.inc.set(iid, { ...w421.inc.get(iid), timers: w421.inc.get(iid).timers.set("resolution", { ...w421.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w422
    } else {
      val w423 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w424 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w425 = { ...w424, inc: w424.inc.set(iid, { ...w424.inc.get(iid), timers: w424.inc.get(iid).timers.set("resolution", { ...w424.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w426 = { ...w425, inc: w425.inc.set(iid, { ...w425.inc.get(iid), timers: w425.inc.get(iid).timers.set("resolution", { ...w425.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w426
    } else w0
      w423
    }
    w420
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w427 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w428 = if (timerDef("reaction").startsOnce) {
      val w429 = ec_resumeTimer(w0, c, iid, "reaction")
      w429
    } else {
      val sec_430 = timerSec(w0.inc.get(iid), "reaction", "")
      val w431 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_430 < 0)) 0 else (c.now + (sec_430 * 1000))) }) }) }
      val w432 = { ...w431, inc: w431.inc.set(iid, { ...w431.inc.get(iid), timers: w431.inc.get(iid).timers.set("reaction", { ...w431.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w432
    }
      w428
    }
    w427
  }

  def e_system_release_idle_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_system_release_idle(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_system_release_idle_0(ws, c1, iid)
    val w2 = e_system_release_idle_1(w1, c1, iid)
    val w3 = e_system_release_idle_2(w2, c1, iid)
    val w4 = e_system_release_idle_3(w3, c1, iid)
    val w5 = e_system_release_idle_4(w4, c1, iid)
    val w6 = e_system_release_idle_5(w5, c1, iid)
    w6
  }

  // addressee_signed_out_to_group: system → pending_acceptance

  def ok_addressee_signed_out_to_group(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    (agentState(c.me) == "offline"),
    (((world.inc.get(iid).owner != "") and (dutyGroupOf(world.inc.get(iid).owner) != "")) == true),
  }

  def e_addressee_signed_out_to_group_0(w0: World, c: Ctx, iid: str): World = {
    val group_433 = dutyGroupOf(w0.inc.get(iid).owner)
    val w434 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_433 }) }
    w434
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_435 = ""
    val w436 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_435 }) }
    w436
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_addressee_signed_out_to_group(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_addressee_signed_out_to_group_0(ws, c1, iid)
    val w2 = e_addressee_signed_out_to_group_1(w1, c1, iid)
    val w3 = e_addressee_signed_out_to_group_2(w2, c1, iid)
    val w4 = e_addressee_signed_out_to_group_3(w3, c1, iid)
    w4
  }

  // addressee_signed_out_to_queue: system → new

  def ok_addressee_signed_out_to_queue(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    (agentState(c.me) == "offline"),
    (((world.inc.get(iid).owner != "") and (dutyGroupOf(world.inc.get(iid).owner) != "")) == false),
  }

  def e_addressee_signed_out_to_queue_0(w0: World, c: Ctx, iid: str): World = {
    val who_437 = ""
    val w438 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_437 }) }
    w438
  }

  def e_addressee_signed_out_to_queue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_addressee_signed_out_to_queue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_addressee_signed_out_to_queue_0(ws, c1, iid)
    val w2 = e_addressee_signed_out_to_queue_1(w1, c1, iid)
    w2
  }

  // owner_signed_out: system → new

  def ok_owner_signed_out(c: Ctx, iid: str): bool = all {
    Set("in_progress", "on_hold").contains(world.inc.get(iid).state),
    (agentState(c.me) == "offline"),
  }

  def e_owner_signed_out_0(w0: World, c: Ctx, iid: str): World = {
    val who_439 = ""
    val w440 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_439 }) }
    w440
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w441 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w441
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w442 = if (timerDef("hold").startsOnce) {
      val w443 = ec_pauseTimer(w0, c, iid, "hold")
      w443
    } else {
      val w444 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w445 = { ...w444, inc: w444.inc.set(iid, { ...w444.inc.get(iid), timers: w444.inc.get(iid).timers.set("hold", { ...w444.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w445
    }
    w442
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w446 = if (not(timerDef("resolution").pausable)) {
      val w447 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w448 = { ...w447, inc: w447.inc.set(iid, { ...w447.inc.get(iid), timers: w447.inc.get(iid).timers.set("resolution", { ...w447.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w448
    } else {
      val w449 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w450 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w451 = { ...w450, inc: w450.inc.set(iid, { ...w450.inc.get(iid), timers: w450.inc.get(iid).timers.set("resolution", { ...w450.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w452 = { ...w451, inc: w451.inc.set(iid, { ...w451.inc.get(iid), timers: w451.inc.get(iid).timers.set("resolution", { ...w451.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w452
    } else w0
      w449
    }
    w446
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w453 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w454 = if (timerDef("reaction").startsOnce) {
      val w455 = ec_resumeTimer(w0, c, iid, "reaction")
      w455
    } else {
      val sec_456 = timerSec(w0.inc.get(iid), "reaction", "")
      val w457 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_456 < 0)) 0 else (c.now + (sec_456 * 1000))) }) }) }
      val w458 = { ...w457, inc: w457.inc.set(iid, { ...w457.inc.get(iid), timers: w457.inc.get(iid).timers.set("reaction", { ...w457.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w458
    }
      w454
    }
    w453
  }

  def e_owner_signed_out_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_owner_signed_out_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_owner_signed_out(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_owner_signed_out_0(ws, c1, iid)
    val w2 = e_owner_signed_out_1(w1, c1, iid)
    val w3 = e_owner_signed_out_2(w2, c1, iid)
    val w4 = e_owner_signed_out_3(w3, c1, iid)
    val w5 = e_owner_signed_out_4(w4, c1, iid)
    val w6 = e_owner_signed_out_5(w5, c1, iid)
    val w7 = e_owner_signed_out_6(w6, c1, iid)
    w7
  }

  // addressee_lost_access: system → new

  def ok_addressee_lost_access(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    ((addressee(world.inc.get(iid)) != "") and (hasAccess(addressee(world.inc.get(iid)), world.inc.get(iid)) == false)),
  }

  def e_addressee_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val who_459 = ""
    val w460 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_459 }) }
    w460
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_461 = ""
    val w462 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_461 }) }
    w462
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w463 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w463
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w464 = if (timerDef("hold").startsOnce) {
      val w465 = ec_pauseTimer(w0, c, iid, "hold")
      w465
    } else {
      val w466 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w467 = { ...w466, inc: w466.inc.set(iid, { ...w466.inc.get(iid), timers: w466.inc.get(iid).timers.set("hold", { ...w466.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w467
    }
    w464
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w468 = if (not(timerDef("resolution").pausable)) {
      val w469 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w470 = { ...w469, inc: w469.inc.set(iid, { ...w469.inc.get(iid), timers: w469.inc.get(iid).timers.set("resolution", { ...w469.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w470
    } else {
      val w471 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w472 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w473 = { ...w472, inc: w472.inc.set(iid, { ...w472.inc.get(iid), timers: w472.inc.get(iid).timers.set("resolution", { ...w472.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w474 = { ...w473, inc: w473.inc.set(iid, { ...w473.inc.get(iid), timers: w473.inc.get(iid).timers.set("resolution", { ...w473.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w474
    } else w0
      w471
    }
    w468
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w475 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w476 = if (timerDef("reaction").startsOnce) {
      val w477 = ec_resumeTimer(w0, c, iid, "reaction")
      w477
    } else {
      val sec_478 = timerSec(w0.inc.get(iid), "reaction", "")
      val w479 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_478 < 0)) 0 else (c.now + (sec_478 * 1000))) }) }) }
      val w480 = { ...w479, inc: w479.inc.set(iid, { ...w479.inc.get(iid), timers: w479.inc.get(iid).timers.set("reaction", { ...w479.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w480
    }
      w476
    }
    w475
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_addressee_lost_access(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_addressee_lost_access_0(ws, c1, iid)
    val w2 = e_addressee_lost_access_1(w1, c1, iid)
    val w3 = e_addressee_lost_access_2(w2, c1, iid)
    val w4 = e_addressee_lost_access_3(w3, c1, iid)
    val w5 = e_addressee_lost_access_4(w4, c1, iid)
    val w6 = e_addressee_lost_access_5(w5, c1, iid)
    val w7 = e_addressee_lost_access_6(w6, c1, iid)
    val w8 = e_addressee_lost_access_7(w7, c1, iid)
    val w9 = e_addressee_lost_access_8(w8, c1, iid)
    w9
  }

  // addressee_cannot_accept: system → new

  def ok_addressee_cannot_accept(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    ((addressee(world.inc.get(iid)) != "") and (hasAccess(addressee(world.inc.get(iid)), world.inc.get(iid)) == true)),
    ((addressee(world.inc.get(iid)) != "") and (canAccept(addressee(world.inc.get(iid)), world.inc.get(iid), "") == false)),
  }

  def e_addressee_cannot_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_481 = ""
    val w482 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_481 }) }
    w482
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_483 = ""
    val w484 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_483 }) }
    w484
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w485 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w486 = if (timerDef("reaction").startsOnce) {
      val w487 = ec_resumeTimer(w0, c, iid, "reaction")
      w487
    } else {
      val sec_488 = timerSec(w0.inc.get(iid), "reaction", "")
      val w489 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_488 < 0)) 0 else (c.now + (sec_488 * 1000))) }) }) }
      val w490 = { ...w489, inc: w489.inc.set(iid, { ...w489.inc.get(iid), timers: w489.inc.get(iid).timers.set("reaction", { ...w489.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w490
    }
      w486
    }
    w485
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_addressee_cannot_accept(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_addressee_cannot_accept_0(ws, c1, iid)
    val w2 = e_addressee_cannot_accept_1(w1, c1, iid)
    val w3 = e_addressee_cannot_accept_2(w2, c1, iid)
    val w4 = e_addressee_cannot_accept_3(w3, c1, iid)
    val w5 = e_addressee_cannot_accept_4(w4, c1, iid)
    val w6 = e_addressee_cannot_accept_5(w5, c1, iid)
    w6
  }

  // merge: manual → linked

  def ok_merge(c: Ctx, iid: str): bool = all {
    Set("new", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:bulk"),
    not(settings.session.states.foldl(false, (acc, s_491) => acc or ((s_491.id == agentState(c.me)) and s_491.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_492 = byId(incs(world), c.form.primaryId)  ((((ps_492.length() > 0) and (ps_492[0].id != world.inc.get(iid).id)) and (ps_492[0].linkedTo == "")) and ((ps_492[0].state == "new") or ((ps_492[0].state == "in_progress") and (ps_492[0].owner == c.me)))) },
    { val ps_493 = byId(incs(world), c.form.primaryId)  ((ps_493.length() > 0) and (ps_493[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w494 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w494
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_495 = byId(incs(w0), c.form.primaryId)
    val w496 = if ((ps_495.length() > 0)) {
      val w497 = incs(w0).select(e_504 => ((e_504.linkedTo == w0.inc.get(iid).id) and not(isDone(e_504)))).foldl([], (acc, x500) => acc.append(x500.id)).foldl(w0, (wf498, cId499) => {
      val w501 = { ...wf498, inc: wf498.inc.set(cId499, { ...wf498.inc.get(cId499), leftGroup: { primaryId: wf498.inc.get(cId499).linkedTo, linkedAt: wf498.inc.get(cId499).linkedAt, at: c.now } }) }
      val w502 = { ...w501, inc: w501.inc.set(cId499, { ...w501.inc.get(cId499), linkedTo: ps_495[0].id }) }
      val w503 = { ...w502, inc: w502.inc.set(cId499, { ...w502.inc.get(cId499), linkedAt: c.now }) }
      w503
    })
      w497
    } else w0
    w496
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_505 = c.form.primaryId
    val w506 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_505 }) }
    val w507 = { ...w506, inc: w506.inc.set(iid, { ...w506.inc.get(iid), linkedAt: c.now }) }
    w507
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_508 = ""
    val w509 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_508 }) }
    w509
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_510 = ""
    val w511 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_510 }) }
    w511
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w512 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w512
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w513 = if (timerDef("reaction").startsOnce) {
      val w514 = ec_pauseTimer(w0, c, iid, "reaction")
      w514
    } else {
      val w515 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w516 = { ...w515, inc: w515.inc.set(iid, { ...w515.inc.get(iid), timers: w515.inc.get(iid).timers.set("reaction", { ...w515.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w516
    }
    w513
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w517 = if (not(timerDef("resolution").pausable)) {
      val w518 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w519 = { ...w518, inc: w518.inc.set(iid, { ...w518.inc.get(iid), timers: w518.inc.get(iid).timers.set("resolution", { ...w518.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w519
    } else {
      val w520 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w521 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w522 = { ...w521, inc: w521.inc.set(iid, { ...w521.inc.get(iid), timers: w521.inc.get(iid).timers.set("resolution", { ...w521.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w523 = { ...w522, inc: w522.inc.set(iid, { ...w522.inc.get(iid), timers: w522.inc.get(iid).timers.set("resolution", { ...w522.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w523
    } else w0
      w520
    }
    w517
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_524 = byId(incs(w0), c.form.primaryId)
    val w525 = if (((((ps_524.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_524[0], "resolution", c.now)))) {
      val t_526 = ps_524[0].timers.get("resolution")
      val left_527 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_528 = (if ((t_526.due != 0)) (t_526.due - c.now) else (if (t_526.paused) t_526.left else (timerSec(ps_524[0], "resolution", "") * 1000)))
      val w529 = if ((left_527 < was_528)) {
      val w530 = ps_524.foldl([], (acc, x533) => acc.append(x533.id)).foldl(w0, (wf531, pId532) => {
      val w534 = if ((t_526.due != 0)) {
      val w535 = { ...wf531, inc: wf531.inc.set(pId532, { ...wf531.inc.get(pId532), timers: wf531.inc.get(pId532).timers.set("resolution", { ...wf531.inc.get(pId532).timers.get("resolution"), due: (c.now + left_527) }) }) }
      w535
    } else {
      val w536 = { ...wf531, inc: wf531.inc.set(pId532, { ...wf531.inc.get(pId532), timers: wf531.inc.get(pId532).timers.set("resolution", { ...wf531.inc.get(pId532).timers.get("resolution"), left: left_527 }) }) }
      val w537 = { ...w536, inc: w536.inc.set(pId532, { ...w536.inc.get(pId532), timers: w536.inc.get(pId532).timers.set("resolution", { ...w536.inc.get(pId532).timers.get("resolution"), paused: true }) }) }
      w537
    }
      w534
    })
      w530
    } else w0
      w529
    } else w0
    w525
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w538 = if (timerDef("hold").startsOnce) {
      val w539 = ec_pauseTimer(w0, c, iid, "hold")
      w539
    } else {
      val w540 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w541 = { ...w540, inc: w540.inc.set(iid, { ...w540.inc.get(iid), timers: w540.inc.get(iid).timers.set("hold", { ...w540.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w541
    }
    w538
  }

  def e_merge_10(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_merge(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "linked" }) }
    val w1 = e_merge_0(ws, c1, iid)
    val w2 = e_merge_1(w1, c1, iid)
    val w3 = e_merge_2(w2, c1, iid)
    val w4 = e_merge_3(w3, c1, iid)
    val w5 = e_merge_4(w4, c1, iid)
    val w6 = e_merge_5(w5, c1, iid)
    val w7 = e_merge_6(w6, c1, iid)
    val w8 = e_merge_7(w7, c1, iid)
    val w9 = e_merge_8(w8, c1, iid)
    val w10 = e_merge_9(w9, c1, iid)
    val w11 = e_merge_10(w10, c1, iid)
    w11
  }

  // detach: manual → new

  def ok_detach(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    not(settings.session.states.foldl(false, (acc, s_542) => acc or ((s_542.id == agentState(c.me)) and s_542.readOnly))),
    { val ps_543 = byId(incs(world), world.inc.get(iid).linkedTo)  ((ps_543.length() > 0) and ((ownership(c.me, ps_543[0]) == "owner") or unowned(ps_543[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_544 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w545 = if (((ps_544.length() > 0) and (leftOf(ps_544[0], "resolution", c.now) >= 0))) {
      val w546 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w547 = { ...w546, inc: w546.inc.set(iid, { ...w546.inc.get(iid), timers: w546.inc.get(iid).timers.set("resolution", { ...w546.inc.get(iid).timers.get("resolution"), left: leftOf(ps_544[0], "resolution", c.now) }) }) }
      val w548 = { ...w547, inc: w547.inc.set(iid, { ...w547.inc.get(iid), timers: w547.inc.get(iid).timers.set("resolution", { ...w547.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w549 = if ((leftOf(ps_544[0], "resolution", c.now) == 0)) {
      val w550 = { ...w548, inc: w548.inc.set(iid, { ...w548.inc.get(iid), timers: w548.inc.get(iid).timers.set("resolution", { ...w548.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_544[0], "resolution", c.now)) ps_544[0].timers.get("resolution").fired else ps_544[0].timers.get("resolution").due) }) }) }
      w550
    } else w548
      w549
    } else w0
    w545
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w551 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_552 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w553 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w554 = { ...w553, inc: w553.inc.set(iid, { ...w553.inc.get(iid), linkedTo: "" }) }
      val w555 = { ...w554, inc: w554.inc.set(iid, { ...w554.inc.get(iid), linkedAt: 0 }) }
      val w556 = if (((ps_552.length() > 0) and ("" != ""))) w555 else w555
      val w557 = if (("" != "")) {
      val w558 = ps_552.foldl([], (acc, x561) => acc.append(x561.id)).foldl(w556, (wf559, pId560) => wf559)
      w558
    } else w556
      w557
    } else {
      val w562 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w563 = { ...w562, inc: w562.inc.set(iid, { ...w562.inc.get(iid), linkedAt: 0 }) }
      w563
    }
    w551
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w564 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w565 = if (timerDef("reaction").startsOnce) {
      val w566 = ec_resumeTimer(w0, c, iid, "reaction")
      w566
    } else {
      val sec_567 = timerSec(w0.inc.get(iid), "reaction", "")
      val w568 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_567 < 0)) 0 else (c.now + (sec_567 * 1000))) }) }) }
      val w569 = { ...w568, inc: w568.inc.set(iid, { ...w568.inc.get(iid), timers: w568.inc.get(iid).timers.set("reaction", { ...w568.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w569
    }
      w565
    }
    w564
  }

  def e_detach_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_detach(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_detach_0(ws, c1, iid)
    val w2 = e_detach_1(w1, c1, iid)
    val w3 = e_detach_2(w2, c1, iid)
    val w4 = e_detach_3(w3, c1, iid)
    val w5 = e_detach_4(w4, c1, iid)
    w5
  }

  // close_linked: system → closed

  def ok_close_linked(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    { val ps_570 = byId(incs(world), world.inc.get(iid).linkedTo)  ((ps_570.length() > 0) and isDone(ps_570[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_571 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w572 = if ((ps_571.length() > 0)) {
      val w573 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_571[0].closeResultId }) }
      val w574 = { ...w573, inc: w573.inc.set(iid, { ...w573.inc.get(iid), closeCauseId: ps_571[0].closeCauseId }) }
      val w575 = { ...w574, inc: w574.inc.set(iid, { ...w574.inc.get(iid), result: ps_571[0].result }) }
      val w576 = { ...w575, inc: w575.inc.set(iid, { ...w575.inc.get(iid), closedBy: ps_571[0].closedBy }) }
      w576
    } else w0
    w572
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w577 = if (not(timerDef("resolution").pausable)) {
      val w578 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w579 = { ...w578, inc: w578.inc.set(iid, { ...w578.inc.get(iid), timers: w578.inc.get(iid).timers.set("resolution", { ...w578.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w579
    } else {
      val w580 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w581 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w582 = { ...w581, inc: w581.inc.set(iid, { ...w581.inc.get(iid), timers: w581.inc.get(iid).timers.set("resolution", { ...w581.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w583 = { ...w582, inc: w582.inc.set(iid, { ...w582.inc.get(iid), timers: w582.inc.get(iid).timers.set("resolution", { ...w582.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w583
    } else w0
      w580
    }
    w577
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_584 = c.now
    val w585 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_584 }) }
    w585
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_close_linked(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "closed" }) }
    val w1 = e_close_linked_0(ws, c1, iid)
    val w2 = e_close_linked_1(w1, c1, iid)
    val w3 = e_close_linked_2(w2, c1, iid)
    val w4 = e_close_linked_3(w3, c1, iid)
    val w5 = e_close_linked_4(w4, c1, iid)
    w5
  }

  // linked_lost_access: system → new

  def ok_linked_lost_access(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    { val ps_586 = byId(incs(world), world.inc.get(iid).linkedTo)  { val who_587 = (if (((ps_586.length() > 0) and not(isDone(ps_586[0])))) addressee(ps_586[0]) else "")  ((who_587 != "") and (hasAccess(who_587, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_588 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w589 = if (((ps_588.length() > 0) and (leftOf(ps_588[0], "resolution", c.now) >= 0))) {
      val w590 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w591 = { ...w590, inc: w590.inc.set(iid, { ...w590.inc.get(iid), timers: w590.inc.get(iid).timers.set("resolution", { ...w590.inc.get(iid).timers.get("resolution"), left: leftOf(ps_588[0], "resolution", c.now) }) }) }
      val w592 = { ...w591, inc: w591.inc.set(iid, { ...w591.inc.get(iid), timers: w591.inc.get(iid).timers.set("resolution", { ...w591.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w593 = if ((leftOf(ps_588[0], "resolution", c.now) == 0)) {
      val w594 = { ...w592, inc: w592.inc.set(iid, { ...w592.inc.get(iid), timers: w592.inc.get(iid).timers.set("resolution", { ...w592.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_588[0], "resolution", c.now)) ps_588[0].timers.get("resolution").fired else ps_588[0].timers.get("resolution").due) }) }) }
      w594
    } else w592
      w593
    } else w0
    w589
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w595 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_596 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w597 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w598 = { ...w597, inc: w597.inc.set(iid, { ...w597.inc.get(iid), linkedTo: "" }) }
      val w599 = { ...w598, inc: w598.inc.set(iid, { ...w598.inc.get(iid), linkedAt: 0 }) }
      val w600 = if (((ps_596.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w599 else w599
      val w601 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w602 = ps_596.foldl([], (acc, x605) => acc.append(x605.id)).foldl(w600, (wf603, pId604) => wf603)
      w602
    } else w600
      w601
    } else {
      val w606 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w607 = { ...w606, inc: w606.inc.set(iid, { ...w606.inc.get(iid), linkedAt: 0 }) }
      w607
    }
    w595
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w608 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w609 = if (timerDef("reaction").startsOnce) {
      val w610 = ec_resumeTimer(w0, c, iid, "reaction")
      w610
    } else {
      val sec_611 = timerSec(w0.inc.get(iid), "reaction", "")
      val w612 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_611 < 0)) 0 else (c.now + (sec_611 * 1000))) }) }) }
      val w613 = { ...w612, inc: w612.inc.set(iid, { ...w612.inc.get(iid), timers: w612.inc.get(iid).timers.set("reaction", { ...w612.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w613
    }
      w609
    }
    w608
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_linked_lost_access(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_linked_lost_access_0(ws, c1, iid)
    val w2 = e_linked_lost_access_1(w1, c1, iid)
    val w3 = e_linked_lost_access_2(w2, c1, iid)
    val w4 = e_linked_lost_access_3(w3, c1, iid)
    val w5 = e_linked_lost_access_4(w4, c1, iid)
    w5
  }

  def trOk(tid: str, c: Ctx, iid: str): bool =
    if (tid == "create") ok_create(c, iid)
    else if (tid == "claim") ok_claim(c, iid)
    else if (tid == "accept") ok_accept(c, iid)
    else if (tid == "reject") ok_reject(c, iid)
    else if (tid == "hold") ok_hold(c, iid)
    else if (tid == "resume") ok_resume(c, iid)
    else if (tid == "release") ok_release(c, iid)
    else if (tid == "transfer") ok_transfer(c, iid)
    else if (tid == "takeover") ok_takeover(c, iid)
    else if (tid == "close") ok_close(c, iid)
    else if (tid == "reopen") ok_reopen(c, iid)
    else if (tid == "auto_escalate") ok_auto_escalate(c, iid)
    else if (tid == "escalation_ceiling") ok_escalation_ceiling(c, iid)
    else if (tid == "reaction_overdue") ok_reaction_overdue(c, iid)
    else if (tid == "resolution_overdue") ok_resolution_overdue(c, iid)
    else if (tid == "resolution_escalate") ok_resolution_escalate(c, iid)
    else if (tid == "resolution_ceiling") ok_resolution_ceiling(c, iid)
    else if (tid == "hold_overdue") ok_hold_overdue(c, iid)
    else if (tid == "system_hold_break") ok_system_hold_break(c, iid)
    else if (tid == "system_hold_idle") ok_system_hold_idle(c, iid)
    else if (tid == "system_release_idle") ok_system_release_idle(c, iid)
    else if (tid == "addressee_signed_out_to_group") ok_addressee_signed_out_to_group(c, iid)
    else if (tid == "addressee_signed_out_to_queue") ok_addressee_signed_out_to_queue(c, iid)
    else if (tid == "owner_signed_out") ok_owner_signed_out(c, iid)
    else if (tid == "addressee_lost_access") ok_addressee_lost_access(c, iid)
    else if (tid == "addressee_cannot_accept") ok_addressee_cannot_accept(c, iid)
    else if (tid == "merge") ok_merge(c, iid)
    else if (tid == "detach") ok_detach(c, iid)
    else if (tid == "close_linked") ok_close_linked(c, iid)
    else if (tid == "linked_lost_access") ok_linked_lost_access(c, iid)
    else false

  def trApply(tid: str, c: Ctx, iid: str, w: World): World =
    if (tid == "create") apply_create(c, iid, w)
    else if (tid == "claim") apply_claim(c, iid, w)
    else if (tid == "accept") apply_accept(c, iid, w)
    else if (tid == "reject") apply_reject(c, iid, w)
    else if (tid == "hold") apply_hold(c, iid, w)
    else if (tid == "resume") apply_resume(c, iid, w)
    else if (tid == "release") apply_release(c, iid, w)
    else if (tid == "transfer") apply_transfer(c, iid, w)
    else if (tid == "takeover") apply_takeover(c, iid, w)
    else if (tid == "close") apply_close(c, iid, w)
    else if (tid == "reopen") apply_reopen(c, iid, w)
    else if (tid == "auto_escalate") apply_auto_escalate(c, iid, w)
    else if (tid == "escalation_ceiling") apply_escalation_ceiling(c, iid, w)
    else if (tid == "reaction_overdue") apply_reaction_overdue(c, iid, w)
    else if (tid == "resolution_overdue") apply_resolution_overdue(c, iid, w)
    else if (tid == "resolution_escalate") apply_resolution_escalate(c, iid, w)
    else if (tid == "resolution_ceiling") apply_resolution_ceiling(c, iid, w)
    else if (tid == "hold_overdue") apply_hold_overdue(c, iid, w)
    else if (tid == "system_hold_break") apply_system_hold_break(c, iid, w)
    else if (tid == "system_hold_idle") apply_system_hold_idle(c, iid, w)
    else if (tid == "system_release_idle") apply_system_release_idle(c, iid, w)
    else if (tid == "addressee_signed_out_to_group") apply_addressee_signed_out_to_group(c, iid, w)
    else if (tid == "addressee_signed_out_to_queue") apply_addressee_signed_out_to_queue(c, iid, w)
    else if (tid == "owner_signed_out") apply_owner_signed_out(c, iid, w)
    else if (tid == "addressee_lost_access") apply_addressee_lost_access(c, iid, w)
    else if (tid == "addressee_cannot_accept") apply_addressee_cannot_accept(c, iid, w)
    else if (tid == "merge") apply_merge(c, iid, w)
    else if (tid == "detach") apply_detach(c, iid, w)
    else if (tid == "close_linked") apply_close_linked(c, iid, w)
    else if (tid == "linked_lost_access") apply_linked_lost_access(c, iid, w)
    else w

  pure val TRANSITIONS: List[Transition] = [
    { id: "create", trigger: "event", actor: "dispatcher", from: Set(), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "claim", trigger: "manual", actor: "dispatcher", from: Set("new"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "accept", trigger: "manual", actor: "dispatcher", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "reject", trigger: "manual", actor: "dispatcher", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "hold", trigger: "manual", actor: "dispatcher", from: Set("in_progress"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "resume", trigger: "manual", actor: "dispatcher", from: Set("on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "release", trigger: "manual", actor: "dispatcher", from: Set("in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "transfer", trigger: "manual", actor: "dispatcher", from: Set("new", "pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "takeover", trigger: "manual", actor: "dispatcher", from: Set("pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "close", trigger: "manual", actor: "dispatcher", from: Set("new", "pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "reopen", trigger: "manual", actor: "dispatcher", from: Set("closed"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "auto_escalate", trigger: "timer", actor: "dispatcher", from: Set("new", "pending_acceptance"), timer: "reaction", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "escalation_ceiling", trigger: "timer", actor: "dispatcher", from: Set("new", "pending_acceptance"), timer: "reaction", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "reaction_overdue", trigger: "timer", actor: "dispatcher", from: Set("new", "pending_acceptance"), timer: "reaction", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "resolution_overdue", trigger: "timer", actor: "dispatcher", from: Set("in_progress"), timer: "resolution", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "resolution_escalate", trigger: "timer", actor: "dispatcher", from: Set("in_progress"), timer: "resolution", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "resolution_ceiling", trigger: "timer", actor: "dispatcher", from: Set("in_progress"), timer: "resolution", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "hold_overdue", trigger: "timer", actor: "dispatcher", from: Set("on_hold"), timer: "hold", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "system_hold_break", trigger: "system", actor: "system", from: Set("in_progress"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "system_hold_idle", trigger: "system", actor: "system", from: Set("in_progress"), timer: "", idleSec: MACHINE_SETTINGS.session.idleHoldSec, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "system_release_idle", trigger: "system", actor: "system", from: Set("on_hold"), timer: "", idleSec: MACHINE_SETTINGS.session.idleReleaseSec, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "addressee_signed_out_to_group", trigger: "system", actor: "system", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "addressee_signed_out_to_queue", trigger: "system", actor: "system", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "owner_signed_out", trigger: "system", actor: "system", from: Set("in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "addressee_lost_access", trigger: "system", actor: "system", from: Set("pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "addressee_cannot_accept", trigger: "system", actor: "system", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "merge", trigger: "manual", actor: "dispatcher", from: Set("new", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: true },
    { id: "detach", trigger: "manual", actor: "dispatcher", from: Set("linked"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "close_linked", trigger: "system", actor: "system", from: Set("linked"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "linked_lost_access", trigger: "system", actor: "system", from: Set("linked"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
  ]

  def windowBreach(tid: str, c: Ctx, iid: str, w: World): World =
    if (tid == "escalation_ceiling") e_escalation_ceiling_0(w, c, iid)
    else if (tid == "reaction_overdue") e_reaction_overdue_0(w, c, iid)
    else if (tid == "resolution_overdue") e_resolution_overdue_0(w, c, iid)
    else if (tid == "resolution_escalate") e_resolution_escalate_0(w, c, iid)
    else if (tid == "resolution_ceiling") e_resolution_ceiling_0(w, c, iid)
    else if (tid == "hold_overdue") e_hold_overdue_0(w, c, iid)
    else w

  pure val CONTINUES_ON: str -> Set[str] = Map("reaction" -> Set("addressee_signed_out_to_group", "addressee_signed_out_to_queue", "transfer", "reject"), "resolution" -> Set(), "hold" -> Set())

  pure val GRACE_MS: int = 3000

  pure val TAKE_WITH: str = "claim"

  pure val MERGE: str = "merge"

  val reached_create = lastAction.name == "create"
  val reached_claim = lastAction.name == "claim"
  val reached_accept = lastAction.name == "accept"
  val reached_reject = lastAction.name == "reject"
  val reached_hold = lastAction.name == "hold"
  val reached_resume = lastAction.name == "resume"
  val reached_release = lastAction.name == "release"
  val reached_transfer = lastAction.name == "transfer"
  val reached_takeover = lastAction.name == "takeover"
  val reached_close = lastAction.name == "close"
  val reached_reopen = lastAction.name == "reopen"
  val reached_auto_escalate = lastAction.name == "auto_escalate"
  val reached_escalation_ceiling = lastAction.name == "escalation_ceiling"
  val reached_reaction_overdue = lastAction.name == "reaction_overdue"
  val reached_resolution_overdue = lastAction.name == "resolution_overdue"
  val reached_resolution_escalate = lastAction.name == "resolution_escalate"
  val reached_resolution_ceiling = lastAction.name == "resolution_ceiling"
  val reached_hold_overdue = lastAction.name == "hold_overdue"
  val reached_system_hold_break = lastAction.name == "system_hold_break"
  val reached_system_hold_idle = lastAction.name == "system_hold_idle"
  val reached_system_release_idle = lastAction.name == "system_release_idle"
  val reached_addressee_signed_out_to_group = lastAction.name == "addressee_signed_out_to_group"
  val reached_addressee_signed_out_to_queue = lastAction.name == "addressee_signed_out_to_queue"
  val reached_owner_signed_out = lastAction.name == "owner_signed_out"
  val reached_addressee_lost_access = lastAction.name == "addressee_lost_access"
  val reached_addressee_cannot_accept = lastAction.name == "addressee_cannot_accept"
  val reached_merge = lastAction.name == "merge"
  val reached_detach = lastAction.name == "detach"
  val reached_close_linked = lastAction.name == "close_linked"
  val reached_linked_lost_access = lastAction.name == "linked_lost_access"

  def scenarioEditOk(c: Ctx, iid: str): bool = all {
    ["in_progress"].foldl(false, (acc, y614) => acc or y614 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_615) => acc or ((s_615.id == agentState(c.me)) and s_615.readOnly))),
  }

  /* ===== Мир модели ===== */

  pure val NOBODY = ""
  pure val DISPATCHER = "dispatcher"
  pure val SYSTEM = "system"
  // Три: основной с привязанным объединяется с третьим — relinkToPrimary
  pure val IDS: List[str] = ["i1", "i2", "i3"]
  pure val INCIDENTS: Set[str] = Set("i1", "i2", "i3")
  pure val OPERATOR_LIST: List[str] = ["a", "b"]
  pure val OPERATORS: Set[str] = Set("a", "b")
  pure val GROUP = "g"
  pure val GROUPS: Set[str] = Set(GROUP)
  pure val TARGETS: Set[str] = OPERATORS.union(GROUPS)
  // Сценарий без графа (§14.5): два сценария, у каждого два шага; пройден — отвечены оба (набор closing)
  pure val SCENARIOS: Set[str] = Set("fire", "water")
  pure val STEPS: Set[str] = Set("s1", "s2")
  pure val PRIORITIES: Set[int] = Set(100, 50)
  // Часы с секунды: 0 у дедлайна и момента в машине — «нет»
  pure val START = 1000

  // Права и доступ выбираются при старте и меняются действием окружения «сменились роли» (§5)
  type Config = {
    perms: str -> Set[str],
    access: str -> Set[str],        // оператор → инциденты, к объектам которых у него доступ
    members: str -> Set[str],       // дежурная группа → участники
  }

  var cfg: Config
  var settings: Settings
  var world: World
  var clock: int
  // Состояние оператора (session машины): ready, not_ready (перерыв), offline (вышел); признак активности
  var agents: str -> str
  var lastBeat: str -> int
  // Связь интерфейса с сервером: пока есть, интерфейс сам присылает признак активности (heartbeatSec)
  var link: str -> bool
  // Момент последнего перехода инцидента — ядру: переход по молчанию не раньше него (RULE-48, BUG-76)
  var changedAt: str -> int
  var lastAction: Action

  /* ===== Факты мира (cel.world машины) ===== */

  def can(who: str, perm: str): bool = OPERATORS.contains(who) and cfg.perms.get(who).contains(perm)
  def access(who: str, x: Incident): bool = OPERATORS.contains(who) and cfg.access.get(who).contains(x.id)
  def isOperator(id: str): bool = OPERATORS.contains(id)
  def isGroup(id: str): bool = GROUPS.contains(id)
  def members(g: str): List[str] = if (isGroup(g)) OPERATOR_LIST.select(m => cfg.members.get(g).contains(m)) else []
  def dutyGroups: List[str] = [GROUP]
  // Групп устройств в модели нет: строк overrides по sourceGroup в машине тоже нет
  def inSourceGroup(x: Incident, g: str): bool = false
  def agentState(who: str): str = if (OPERATORS.contains(who)) agents.get(who) else "offline"
  def idleSec(who: str): int = if (OPERATORS.contains(who)) (clock - lastBeat.get(who)) / 1000 else 0
  def stepsFilled(x: Incident, setId: str): bool = setId == "none" or (setId == "closing" and world.answers.get(x.id) == STEPS)

  // Перенос ответов при объединении (действие мира shareAnswers): отвеченные шаги основного — с ответами привязанного
  pure def shareAnswers(w: World, src: str, dst: str): World =
    if (INCIDENTS.contains(dst)) { ...w, answers: w.answers.set(dst, w.answers.get(dst).union(w.answers.get(src))) } else w
  // Инциденты сервера по порядку — те, что появились
  pure def incs(w: World): List[Incident] = IDS.foldl([], (acc, j) => if (w.inc.get(j).state != "") acc.append(w.inc.get(j)) else acc)
  // Видимость (§5, invariants.actorSeesIncident): действует только тот, у кого доступ к объекту
  def sees(a: str, i: str): bool = cfg.access.get(a).contains(i)
  def incOf(i: str): Incident = world.inc.get(i)
  pure def act0(kind: str, name: str, actor: str, i: str): Action =
    { name: name, actor: actor, incident: i, kind: kind, form: NO_FORM, surface: "", others: [], prio: 0, scenario: "" }

  /* ===== Ядро исполнения (CEL.md, «Ядро исполнения») — как у исполнителя прототипа prototype/engine.js ===== */

  def ctx(me: str, actor: str, form: Form, surface: str): Ctx =
    { me: me, actor: actor, now: clock, deadline: clock, form: form, surface: surface, before: NO_INCIDENT }
  pure def tr(tid: str): Transition = TRANSITIONS.select(t => t.id == tid)[0]
  pure def ofTrigger(trigger: str): List[Transition] = TRANSITIONS.select(t => t.trigger == trigger)

  // Переход по таймеру и системный: от чьего имени условия — у scope incidents_owned_by_agent владелец
  // (его исполнитель), иначе actor перехода
  def autoCtx(t: Transition, i: str): Ctx = ctx(if (t.ownedByAgent) incOf(i).owner else t.actor, t.actor, NO_FORM, "")
  def autoReady(t: Transition, i: str): bool = all {
    incOf(i).state != "",
    not(t.ownedByAgent) or OPERATORS.contains(incOf(i).owner),
    trOk(t.id, autoCtx(t, i), i),
  }
  // Момент перехода (RULE-41): по таймеру — дедлайн, по молчанию — порог, системный без них — сейчас
  def moment(t: Transition, i: str): int =
    if (t.timer != "") incOf(i).timers.get(t.timer).due
    else if (t.idleSec > 0) {
      val m = lastBeat.get(incOf(i).owner) + t.idleSec * 1000
      if (m > changedAt.get(i)) m else changedAt.get(i)
    }
    else clock
  def systemReadyFor(i: str): bool = ofTrigger("system").foldl(false, (acc, t) => acc or autoReady(t, i))
  // Выполняется сейчас: системный — сразу; по таймеру — после окна manualWinsOverTimer, а при готовом
  // системном — сразу, первым, если наступил раньше (RULE-41, RULE-67)
  def eligible(t: Transition, i: str, sys: bool): bool = all {
    t.trigger == "timer" or t.trigger == "system",
    autoReady(t, i),
    moment(t, i) <= clock,
    t.trigger == "system" or sys or moment(t, i) + GRACE_MS <= clock,
  }
  // Первый из готовых: раньше момент, при равенстве — по порядку в машине
  def nextAuto(i: str): List[Transition] = {
    val sys = systemReadyFor(i)
    AUTO.foldl([], (best, t) =>
      if (not(eligible(t, i, sys))) best
      else if (best.length() == 0 or moment(t, i) < moment(best[0], i)) [t]
      else best)
  }
  pure val AUTO: List[Transition] = TRANSITIONS.select(t => t.trigger == "timer" or t.trigger == "system")
  // Сервер выполняет автоматические переходы сразу: пока такой есть, шаг — только он (step), ни ручных
  // действий, ни времени. Действия ниже этого не проверяют — их можно вызывать и сами по себе (сценарии)
  def urgent: bool = INCIDENTS.exists(i => nextAuto(i).length() > 0)

  // Окно после дедлайна (§10.1, правило 5; RULE-63): ручное действие отменяет готовый переход по таймеру,
  // если таймер после действия не продолжается (continuesOn, RULE-83); первым — с более ранним дедлайном
  def canceledBy(tid: str, i: str): List[Transition] =
    ofTrigger("timer").foldl([], (best, t) =>
      if (not(all {
        autoReady(t, i),
        moment(t, i) <= clock,
        clock < moment(t, i) + GRACE_MS,
        not(CONTINUES_ON.get(t.timer).contains(tid)),
      })) best
      else if (best.length() == 0 or moment(t, i) < moment(best[0], i)) [t]
      else best)
  pure def markFired(w: World, i: str, timer: str): World = {
    val x = w.inc.get(i)
    { ...w, inc: w.inc.set(i, { ...x, timers: x.timers.set(timer, { ...x.timers.get(timer), fired: x.timers.get(timer).due }) }) }
  }
  // До действия: срабатывание отмечено; после — нарушение отменённого перехода его же recordBreach,
  // на момент дедлайна и на адресата до действия
  def windowStart(canceled: List[Transition], i: str, w: World): World =
    if (canceled.length() > 0) markFired(w, i, canceled[0].timer) else w
  def windowEnd(canceled: List[Transition], i: str, before: Incident, w: World): World =
    if (canceled.length() > 0) {
      val t = canceled[0]
      windowBreach(t.id, { ...ctx(DISPATCHER, DISPATCHER, NO_FORM, ""), deadline: before.timers.get(t.timer).due, before: before }, i, w)
    } else w

  // Действие оператора — признак активности (§12.3, BUG-76): кто действует, тот не молчит
  action commit(a: Action, w: World): bool = all {
    world' = w,
    changedAt' = INCIDENTS.mapBy(j => if (w.inc.get(j) != world.inc.get(j)) clock else changedAt.get(j)),
    lastBeat' = if (OPERATORS.contains(a.actor) and (a.kind == "manual" or a.kind == "merge" or a.name == "answer")) lastBeat.set(a.actor, clock) else lastBeat,
    cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, link' = link,
    lastAction' = a,
  }

  /* ===== Появление инцидента (переход с trigger event) ===== */

  action create(i: str, sc: str, prio: int): bool = {
    val t = ofTrigger("event")[0]
    val w0 = { ...world,
      inc: world.inc.set(i, { ...NO_INCIDENT, id: i, number: i, eventType: "fire", priority: prio, scenario: sc }),
      answers: world.answers.set(i, Set()) }
    all {
      incOf(i).state == "",
      commit({ ...act0("create", t.id, DISPATCHER, i), prio: prio, scenario: sc }, trApply(t.id, ctx(DISPATCHER, DISPATCHER, NO_FORM, ""), i, w0)),
    }
  }

  /* ===== Ручное действие (§6.1): условия перехода, видимость, окно после дедлайна ===== */

  action manual(a: str, tid: str, i: str, form: Form, surface: str): bool = {
    val t = tr(tid)
    val c = ctx(a, a, form, surface)
    val canceled = canceledBy(tid, i)
    val before = incOf(i)
    all {
      t.trigger == "manual",
      not(t.bulkOnly),
      t.surfaces.contains(surface),
      sees(a, i),
      trOk(tid, c, i),
      commit({ ...act0("manual", tid, a, i), form: form, surface: surface }, windowEnd(canceled, i, before, trApply(tid, c, i, windowStart(canceled, i, world)))),
    }
  }

  /* ===== «Взять в работу» на выборке (§11): merge на каждом, кроме основного, и takeWith на основном ===== */

  action merge(a: str, p: str, others: Set[str]): bool = {
    val list = IDS.select(j => others.contains(j))
    val cm = ctx(a, a, { ...NO_FORM, primaryId: p }, "")
    val take = tr(TAKE_WITH)
    val taking = take.from.contains(incOf(p).state)
    val ct = ctx(a, a, NO_FORM, "")
    // Окна — у каждого объединяемого и у основного, если его берут (BUG-62): до всех эффектов
    val canceled = list.foldl(Map(), (m, o) => m.put(o, canceledBy(MERGE, o)))
    val pc = if (taking) canceledBy(TAKE_WITH, p) else []
    val before = world.inc
    val w1 = list.foldl(world, (w, o) => windowStart(canceled.get(o), o, w))
    val w2 = windowStart(pc, p, w1)
    val w3 = list.foldl(w2, (w, o) => trApply(MERGE, cm, o, w))
    val w4 = list.foldl(w3, (w, o) => windowEnd(canceled.get(o), o, before.get(o), w))
    val w5 = if (taking) windowEnd(pc, p, before.get(p), trApply(TAKE_WITH, ct, p, w4)) else w4
    all {
      list.length() > 0,
      not(others.contains(p)),
      sees(a, p),
      others.forall(o => sees(a, o)),
      others.forall(o => trOk(MERGE, cm, o)),
      not(taking) or trOk(TAKE_WITH, ct, p),
      commit({ ...act0("merge", MERGE, a, p), others: list }, w5),
    }
  }

  /* ===== Автоматические переходы: планировщик ===== */

  action fire(i: str): bool = {
    val nx = nextAuto(i)
    all {
      nx.length() > 0,
      {
        val t = nx[0]
        val due = if (t.timer != "") incOf(i).timers.get(t.timer).due else clock
        val w0 = if (t.timer != "") markFired(world, i, t.timer) else world
        commit(act0("auto", t.id, t.actor, i), trApply(t.id, { ...autoCtx(t, i), deadline: due }, i, w0))
      },
    }
  }

  /* ===== Окружение ===== */

  // Время — к следующему событию: дедлайн, миг после него (внутри окна), конец окна, порог молчания, конец срока
  // переоткрытия
  def events: Set[int] = INCIDENTS.filter(i => incOf(i).state != "").fold(Set(), (s, i) => {
    val x = incOf(i)
    val ds = TIMER_IDS.filter(k => x.timers.get(k).due != 0).map(k => x.timers.get(k).due)
    s.union(ds).union(ds.map(d => d + 1)).union(ds.map(d => d + GRACE_MS))
      .union(if (x.closedAt != 0) Set(x.closedAt + settings.limits.reopenWindowMin * 60000 + 1) else Set())
  }).union(OPERATORS.filter(o => agents.get(o) != "offline" and not(link.get(o))).fold(Set(), (s, o) =>
    s.union(Set(lastBeat.get(o) + settings.session.idleHoldSec * 1000, lastBeat.get(o) + settings.session.idleReleaseSec * 1000))))
  def futureEvents: Set[int] = events.filter(t => t > clock)
  action time: bool = {
    val nextAt = futureEvents.fold(clock, (m, t) => if (m == clock or t < m) t else m)
    all {
      futureEvents.size() > 0,
      world' = world, cfg' = cfg, settings' = settings, agents' = agents, link' = link, changedAt' = changedAt,
      // Пока связь есть, признак активности приходит и дальше
      lastBeat' = OPERATORS.mapBy(o => if (link.get(o) and agents.get(o) != "offline") nextAt else lastBeat.get(o)),
      clock' = nextAt,
      lastAction' = act0("time", "time", NOBODY, NOBODY),
    }
  }

  action agent(a: str, name: str, state: str, beat: bool): bool = all {
    agents' = agents.set(a, state),
    lastBeat' = if (beat) lastBeat.set(a, clock) else lastBeat,
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
  }
  // Перерыв — с правом agent:set_not_ready; на перерыве и после выхода — только просмотр (agentReady машины)
  action goOnBreak(a: str): bool = all { agents.get(a) == "ready", can(a, "agent:set_not_ready"), agent(a, "break", "not_ready", true) }
  action backFromBreak(a: str): bool = all { agents.get(a) == "not_ready", agent(a, "back", "ready", true) }
  action signOut(a: str): bool = all { agents.get(a) != "offline", agent(a, "sign_out", "offline", true) }
  action signIn(a: str): bool = all { agents.get(a) == "offline", agent(a, "sign_in", "ready", true) }
  // Пропала и вернулась связь (§12.3): без неё оператор молчит; вернулась — признак активности сразу
  action loseLink(a: str): bool = all {
    link.get(a),
    link' = link.set(a, false),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, lastBeat' = lastBeat, changedAt' = changedAt,
    lastAction' = act0("env", "lose_link", a, NOBODY),
  }
  action restoreLink(a: str): bool = all {
    not(link.get(a)),
    link' = link.set(a, true),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, changedAt' = changedAt,
    lastAction' = act0("env", "restore_link", a, NOBODY),
  }

  // Сменились роли (§5): доступ к объекту инцидента, право «Принимать»
  action roles(a: str, name: str, c: Config): bool = all {
    cfg' = c,
    world' = world, settings' = settings, clock' = clock, agents' = agents, lastBeat' = lastBeat, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
  }
  action toggleAccess(a: str, i: str): bool = {
    val s = cfg.access.get(a)
    roles(a, "toggle_access", { ...cfg, access: cfg.access.set(a, if (s.contains(i)) s.exclude(Set(i)) else s.union(Set(i))) })
  }
  action toggleAccept(a: str): bool = {
    val s = cfg.perms.get(a)
    roles(a, "toggle_accept", { ...cfg, perms: cfg.perms.set(a, if (s.contains("incident:accept")) s.exclude(Set("incident:accept")) else s.union(Set("incident:accept"))) })
  }

  // Ответ на шаг сценария (§10.4): кто может — scenarioEdit машины
  action answer(a: str, i: str, st: str): bool = all {
    sees(a, i),
    scenarioEditOk(ctx(a, a, NO_FORM, "card"), i),
    not(world.answers.get(i).contains(st)),
    commit(act0("env", "answer", a, i), { ...world, answers: world.answers.set(i, world.answers.get(i).union(Set(st))) }),
  }

  /* ===== Начало и шаг ===== */

  action init = {
    nondet perms = OPERATORS.setOfMaps(USED_PERMISSIONS.powerset()).oneOf()
    nondet access = OPERATORS.setOfMaps(INCIDENTS.powerset()).oneOf()
    nondet grp = OPERATORS.powerset().oneOf()
    nondet escOn = Set(true, false).oneOf()
    nondet overdue = Set("alert", "escalate").oneOf()
    nondet maxActive = Set(0, 1).oneOf()
    nondet maxOnHold = Set(0, 1).oneOf()
    nondet level1 = OPERATORS.oneOf()
    val levels = MACHINE_SETTINGS.escalation.levels
    all {
      cfg' = { perms: perms, access: access, members: Map(GROUP -> grp) },
      // Настройки — значения машины; перебираются переключатели и лимиты, люди — люди модели:
      // уровень 1 — человек, уровень 2 — дежурная группа, алерты — группе
      settings' = { ...MACHINE_SETTINGS,
        escalation: { ...MACHINE_SETTINGS.escalation, enabled: escOn, onResolutionOverdue: overdue,
          levels: [{ ...levels[0], targetKind: "user", target: level1 }, { ...levels[1], targetKind: "group", target: GROUP }] },
        alerts: { ...MACHINE_SETTINGS.alerts, targetKind: "group", target: GROUP },
        limits: { ...MACHINE_SETTINGS.limits, maxActive: maxActive, maxOnHold: maxOnHold },
      },
      world' = { inc: INCIDENTS.mapBy(i => NO_INCIDENT), answers: INCIDENTS.mapBy(i => Set()) },
      clock' = START,
      agents' = OPERATORS.mapBy(a => "ready"),
      lastBeat' = OPERATORS.mapBy(a => START),
      link' = OPERATORS.mapBy(a => true),
      changedAt' = INCIDENTS.mapBy(i => 0),
      lastAction' = act0("init", "init", NOBODY, NOBODY),
    }
  }

  pure val MANUAL_IDS: Set[str] = ofTrigger("manual").foldl(Set(), (s, t) => if (t.bulkOnly) s else s.union(Set(t.id)))
  action step = {
    val pending = INCIDENTS.filter(i => nextAuto(i).length() > 0)
    if (pending.size() > 0) {
      nondet j = pending.oneOf()
      fire(j)
    } else stepFree
  }
  action stepFree = {
    nondet i = INCIDENTS.oneOf()
    nondet a = OPERATORS.oneOf()
    any {
      {
        nondet sc = SCENARIOS.oneOf()
        nondet prio = PRIORITIES.oneOf()
        create(i, sc, prio)
      },
      {
        nondet tid = MANUAL_IDS.oneOf()
        nondet target = TARGETS.oneOf()
        nondet reason = HOLD_REASONS_BY_OPERATOR.oneOf()
        nondet result = CLOSE_RESULT_IDS.oneOf()
        nondet surface = tr(tid).surfaces.oneOf()
        val form = { ...NO_FORM, targetId: target, reasonId: reason, resultId: result,
          causeId: if (CAUSE_FOR.keys().contains(result)) CAUSE_FOR.get(result) else "", comment: "c" }
        manual(a, tid, i, form, surface)
      },
      {
        nondet p = INCIDENTS.oneOf()
        nondet others = INCIDENTS.powerset().oneOf()
        merge(a, p, others)
      },
      time,
      goOnBreak(a),
      backFromBreak(a),
      signOut(a),
      signIn(a),
      loseLink(a),
      restoreLink(a),
      toggleAccess(a, i),
      toggleAccept(a),
      {
        nondet st = STEPS.oneOf()
        answer(a, i, st)
      },
    }
  }

  /* ===== Инварианты =====
     quint run im.qnt --invariant inv; каждый можно проверить отдельно — имена ниже.
     Инварианты пишутся руками и нарочно другими словами, чем правила машины: совпади они с машиной
     дословно, они бы ничего не проверяли. */

  pure val OPEN: Set[str] = Set("new", "pending_acceptance", "in_progress", "on_hold")
  pure def runs(t: Timer): bool = t.due != 0
  def isDueT(t: Timer): bool = t.due != 0 and t.due <= clock and t.fired != t.due
  pure def hasBreach(x: Incident, kind: str): bool = x.breaches.select(b => b.kind == kind).length() > 0
  def primaryOf(x: Incident): Incident = if (INCIDENTS.contains(x.linkedTo)) incOf(x.linkedTo) else NO_INCIDENT
  // Сейчас выполнится автоматический переход этого инцидента — системный или по таймеру
  def autoPending(i: str): bool = AUTO.foldl(false, (acc, t) => acc or autoReady(t, i))

  // 1. Владелец по состоянию (§2.1)
  val ownerByState = INCIDENTS.forall(i => {
    val x = incOf(i)
    val s = x.state
    if (s == "new" or s == "linked") x.owner == NOBODY and x.assignmentGroup == NOBODY
    else if (s == "pending_acceptance")
      (OPERATORS.contains(x.owner) and x.assignmentGroup == NOBODY) or (x.owner == NOBODY and x.assignmentGroup == GROUP)
    else if (s == "in_progress" or s == "on_hold") OPERATORS.contains(x.owner) and x.assignmentGroup == NOBODY
    // Закрытый вместе с основным (close_linked) — без владельца, закрывший — закрывший основной
    else if (s == "closed")
      OPERATORS.contains(x.closedBy) and x.assignmentGroup == NOBODY
      and (x.owner == x.closedBy or (x.owner == NOBODY and x.linkedTo != NOBODY))
    else s == ""
  })

  // 2. Причина удержания задана ⇔ «Отложен»
  val holdReasonIffOnHold = INCIDENTS.forall(i => (incOf(i).holdReasonId != NOBODY) iff (incOf(i).state == "on_hold"))

  // 3. Таймеры по состоянию (startsOnEnter, stopsOnEnter, pausedInStates). Реакция в «Новое» и «Ожидает
  //    принятия» остановлена только после записанного нарушения (RULE-84); сработавшая реакция не идёт дальше;
  //    наступивший дедлайн норматива закрытия не уходит на паузу необработанным
  val timersByState = INCIDENTS.forall(i => {
    val x = incOf(i)
    val r = x.timers.get("reaction")
    val z = x.timers.get("resolution")
    val h = x.timers.get("hold")
    val s = x.state
    all {
      not(runs(r) and r.fired == r.due),
      if (s == "new" or s == "pending_acceptance") not(runs(h)) and not(runs(z)) and (runs(r) or hasBreach(x, "reaction"))
      else if (s == "in_progress") runs(z) and not(runs(r)) and not(runs(h))
      else if (s == "on_hold") runs(h) and not(runs(z)) and z.paused and not(runs(r))
      else if (s == "closed") not(runs(r)) and not(runs(z)) and not(runs(h))
      // Свой норматив закрытия привязанного на паузе: у группы один срок — срок основного (RULE-97)
      else if (s == "linked") not(runs(r)) and not(runs(h)) and not(runs(z))
      else true,
    }
  })

  // 3а. Наступивший дедлайн норматива закрытия не уходит на паузу необработанным: на паузе с остатком 0 —
  //     только отработанный (RULE-50); и у отсоединённого после наступившего срока группы (BUG-75)
  val dueNotPausedUnprocessed = INCIDENTS.forall(i => {
    val z = incOf(i).timers.get("resolution")
    not(z.paused and z.left == 0 and z.fired == 0)
  })

  // 4. Уровень эскалации в пределах (§8.3)
  val levelBounded = INCIDENTS.forall(i => incOf(i).escalationLevel >= 0 and incOf(i).escalationLevel <= settings.escalation.maxLevel)

  // 5. Результат закрытия задан ⇔ «Закрыто» (§2.2)
  val closeResultIffClosed = INCIDENTS.forall(i => (incOf(i).closeResultId != NOBODY) iff (incOf(i).state == "closed"))

  // 6. По инциденту готово не больше одного перехода по таймеру (§14.3)
  val timerTransitionsExclusive = INCIDENTS.forall(i => ofTrigger("timer").select(t => autoReady(t, i)).length() <= 1)

  // 7. Наступивший дедлайн идущего таймера кто-то обрабатывает — не теряется молча (§4, §9)
  val dueDeadlineHandled = INCIDENTS.forall(i => {
    val x = incOf(i)
    TIMER_IDS.exists(k => isDueT(x.timers.get(k))) implies ofTrigger("timer").foldl(false, (acc, t) => acc or autoReady(t, i))
  })

  // 8. Лимиты (§10.2): maxOnHold ограничивает только ручное «Отложить» — системные удержания откладывают и сверх
  def countMine(a: str, s: str): int = INCIDENTS.filter(j => incOf(j).state == s and incOf(j).owner == a).size()
  def countManualHeld(a: str): int =
    INCIDENTS.filter(j => incOf(j).state == "on_hold" and incOf(j).owner == a and HOLD_REASONS_BY_OPERATOR.contains(incOf(j).holdReasonId)).size()
  val limitsRespected = OPERATORS.forall(a => all {
    settings.limits.maxActive == 0 or countMine(a, "in_progress") <= settings.limits.maxActive,
    settings.limits.maxOnHold == 0 or countManualHeld(a) <= settings.limits.maxOnHold,
  })

  // 9. У ожидающего принятия адресат может принять (§8.1) — или его сейчас снимает системный переход: права меняются
  def mayAccept(who: str, x: Incident): bool =
    if (isGroup(who)) cfg.members.get(who).exists(m => can(m, "incident:accept") and access(m, x))
    else can(who, "incident:accept") and access(who, x)
  val pendingAddresseeCanAccept = INCIDENTS.forall(i => {
    val x = incOf(i)
    val who = if (x.owner != NOBODY) x.owner else x.assignmentGroup
    x.state == "pending_acceptance" implies (mayAccept(who, x) or autoPending(i))
  })

  // 10. Эскалация не адресует инцидент тому, у кого он уже есть: тому же человеку, той же группе или группе,
  //     где принять может только его владелец (§8.1, §8.3, RULE-93)
  def escalatesToCurrent(tid: str, i: str): bool = {
    val x = incOf(i)
    val who = if (x.owner != NOBODY) x.owner else x.assignmentGroup
    val t = levelUpTarget(x)
    autoReady(tr(tid), i) and (t == who or (isGroup(t) and not(cfg.members.get(t).exists(m => m != x.owner and can(m, "incident:accept") and access(m, x)))))
  }
  val autoEscalateNotToCurrentAddressee = INCIDENTS.forall(i => not(escalatesToCurrent("auto_escalate", i)))
  val resolutionEscalateNotToCurrentAddressee = INCIDENTS.forall(i => not(escalatesToCurrent("resolution_escalate", i)))

  // 11. Форма связи (§11.3, §11.4): у привязанного нет причины удержания и результата; основной — другой
  //     инцидент, сам не привязан и открыт; закрытый — привязанный сейчас закроется вместе с ним
  val linkedShape = INCIDENTS.forall(i => {
    val x = incOf(i)
    val p = primaryOf(x)
    x.state == "linked" implies all {
      x.holdReasonId == NOBODY,
      x.closeResultId == NOBODY,
      INCIDENTS.contains(x.linkedTo),
      x.linkedTo != i,
      OPEN.contains(p.state) or (p.state == "closed" and autoPending(i)),
    }
  })

  // 12. Открытый ни к чему не привязан: отсоединение и переоткрытие снимают связь (BUG-42)
  val openNotLinked = INCIDENTS.forall(i => OPEN.contains(incOf(i).state) implies incOf(i).linkedTo == NOBODY)

  // 13. У нарушения закрытия есть чьё: срок группы идёт, только пока основной кто-то ведёт (RULE-97)
  val resolutionBreachHasOwner = INCIDENTS.forall(i => incOf(i).breaches.select(b => b.kind == "resolution" and b.owner == NOBODY).length() == 0)

  // 14. Нарушения основного по срокам после присоединения — и у привязанного (§11.4, RULE-97, BUG-73)
  val linkedSharesBreaches = INCIDENTS.forall(i => {
    val x = incOf(i)
    x.state == "linked" implies primaryOf(x).breaches.select(b => b.at > x.linkedAt).foldl(true, (acc, b) =>
      acc and x.breaches.foldl(false, (f, y) => f or y == b))
  })

  // 15. Ни один инцидент не остаётся у того, у кого нет к нему доступа (§5, RULE-71): у адресата открытого —
  //     доступ к нему, у адресата основного — и к привязанным; иначе его сейчас снимает системный переход
  def reach(who: str, x: Incident): bool =
    if (isGroup(who)) cfg.members.get(who).exists(m => access(m, x)) else access(who, x)
  val noIncidentWithoutAccess = INCIDENTS.forall(i => {
    val x = incOf(i)
    val p = primaryOf(x)
    val who = if (x.owner != NOBODY) x.owner else x.assignmentGroup
    val pwho = if (p.owner != NOBODY) p.owner else p.assignmentGroup
    all {
      Set("pending_acceptance", "in_progress", "on_hold").contains(x.state) implies (reach(who, x) or autoPending(i)),
      (x.state == "linked" and p.state != "closed" and pwho != NOBODY) implies (reach(pwho, x) or autoPending(i) or autoPending(x.linkedTo)),
    }
  })

  // 16. Автоматический переход не повторяется сразу же: выполненный — больше не готов в тот же момент, иначе
  //     планировщик ходил бы по кругу, а время стояло
  val autoNotRepeated = INCIDENTS.forall(i => {
    val nx = nextAuto(i)
    not(nx.length() > 0 and lastAction.incident == i and lastAction.name == nx[0].id)
  })

  // 17. Привязанный — того же сценария, что основной (§11.3)
  val linkedSameScenario = INCIDENTS.forall(i => incOf(i).state == "linked" implies incOf(i).scenario == primaryOf(incOf(i)).scenario)

  // 18. «Обработан» своим «Закрыть» — только у пройденного сценария, в том числе за счёт ответов, перенесённых
  //     при объединении (§2.2, §14.5); закрытый вместе с основным берёт его результат (§11.4)
  val processedOnlyFinished = INCIDENTS.forall(i => {
    val x = incOf(i)
    (x.state == "closed" and x.closeResultId == "processed" and x.linkedTo == NOBODY) implies world.answers.get(i) == STEPS
  })

  // 19. Вышедший не держит ни своих, ни лично ему адресованных (§8.1, §12.1); на перерыве у оператора нет
  //     инцидентов «В работе» (§12.2) — или их сейчас снимает системный переход
  val agentStateRespected = INCIDENTS.forall(i => {
    val x = incOf(i)
    all {
      (Set("pending_acceptance", "in_progress", "on_hold").contains(x.state) and agentState(x.owner) == "offline" and OPERATORS.contains(x.owner)) implies autoPending(i),
      (x.state == "in_progress" and agentState(x.owner) == "not_ready") implies autoPending(i),
    }
  })

  val inv = all {
    ownerByState,
    holdReasonIffOnHold,
    timersByState,
    dueNotPausedUnprocessed,
    levelBounded,
    closeResultIffClosed,
    timerTransitionsExclusive,
    dueDeadlineHandled,
    limitsRespected,
    pendingAddresseeCanAccept,
    autoEscalateNotToCurrentAddressee,
    resolutionEscalateNotToCurrentAddressee,
    linkedShape,
    openNotLinked,
    resolutionBreachHasOwner,
    linkedSharesBreaches,
    noIncidentWithoutAccess,
    autoNotRepeated,
    linkedSameScenario,
    processedOnlyFinished,
    agentStateRespected,
  }
}
