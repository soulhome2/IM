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


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str }

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

  type CloseResultItem = { id: str, labelKey: str, permission: str, fromStates: List[str], ownerOnlyInStates: List[str], surfaces: List[str], requiredStepSet: str, commentRequired: bool, finish: bool }

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
    closeResults: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "closing", commentRequired: false, finish: true }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", permission: "incident:close:unprocessed", fromStates: ["new", "pending_acceptance", "in_progress", "on_hold"], ownerOnlyInStates: ["in_progress", "on_hold"], surfaces: ["queue", "card"], requiredStepSet: "none", commentRequired: true, finish: false }],
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overrides: [{ eventType: [], priority: [100], sourceGroup: [], escalationLevel: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], escalationLevel: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], escalationLevel: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], escalationLevel: [], sec: 1800 }], startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overrides: [], startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overrides: [], startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
    holdReasons: [{ id: "third_party", maxMinutes: 30, setBy: "operator" }, { id: "patrol", maxMinutes: 45, setBy: "operator" }, { id: "no_data", maxMinutes: 60, setBy: "operator" }, { id: "break", maxMinutes: 30, setBy: "system" }, { id: "no_link", maxMinutes: 20, setBy: "system" }],
  }

  pure val STATES: Set[str] = Set("new", "pending_acceptance", "in_progress", "on_hold", "closed", "linked")

  pure val AGENT_MOVES: Set[{ id: str, from: Set[str], to: str, permission: str }] = Set({ id: "break", from: Set("ready"), to: "not_ready", permission: "agent:set_not_ready" }, { id: "back", from: Set("not_ready"), to: "ready", permission: "" }, { id: "sign_out", from: Set("ready", "not_ready"), to: "offline", permission: "" }, { id: "sign_in", from: Set("offline"), to: "ready", permission: "" })

  pure val HOLD_REASONS_BY_OPERATOR: Set[str] = Set("third_party", "patrol", "no_data")

  pure val CLOSE_RESULT_IDS: Set[str] = Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass")

  pure val USED_PERMISSIONS: Set[str] = Set("agent:set_not_ready", "incident:accept", "incident:bulk", "incident:claim", "incident:close", "incident:close:unprocessed", "incident:hold", "incident:reassign", "incident:release", "incident:reopen", "incident:run_action", "incident:transfer:any", "incident:transfer:own")

  pure val TIMER_IDS: Set[str] = Set("reaction", "resolution", "hold")

  pure val NO_TIMER: Timer = { due: 0, paused: false, left: 0, fired: 0, since: 0 }

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

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

  // §11. Основной при «Взять в работу» на выборке, если его не назвал оператор: свой в работе, иначе новый; из них — самый срочный, у равных — появившийся раньше, у совсем равных — первый по порядку выборки. Списком из одного или пустым

  def mergePrimary(xs: List[Incident], who: str): List[Incident] =
    { val mine_6 = xs.select(e_7 => ((e_7.state == "in_progress") and (e_7.owner == who)))  { val c_8 = (if ((mine_6.length() > 0)) mine_6 else xs.select(e_9 => (e_9.state == "new")))  { val top_10 = c_8.select(e_11 => c_8.foldl(true, (acc, k_12) => acc and (k_12.priority <= e_11.priority)))  { val first_13 = top_10.select(e_14 => top_10.foldl(true, (acc, k_15) => acc and (e_14.occurredAt <= k_15.occurredAt)))  (if ((first_13.length() > 0)) [first_13[0]] else []) } } } }

  // §8.1, §12. Человек на месте: его состояние — не «только просмотр» (перерыв, вышел)

  def onDuty(who: str): bool =
    not(settings.session.states.foldl(false, (acc, s_16) => acc or ((s_16.id == agentState(who)) and s_16.readOnly)))

  // §9. Кто получит уведомление: человек или участники дежурной группы — на месте и с доступом к объекту инцидента

  def recipients(whom: str, x: Incident): List[str] =
    (if (isGroup(whom)) members(whom) else [whom]).select(m_17 => (onDuty(m_17) and access(m_17, x)))

  // Таймер идёт: дедлайн есть и ещё не сработал (на потолке эскалации реакции — уже сработал)

  def timerRuns(x: Incident, id: str): bool =
    ((x.timers.get(id).due != 0) and (x.timers.get(id).fired != x.timers.get(id).due))

  // Закрыт без результата или результатом полной обработки (finish)

  def closedFinished(x: Incident): bool =
    ((x.closeResultId == "") or settings.closeResults.foldl(false, (acc, i_18) => acc or ((i_18.id == x.closeResultId) and i_18.finish)))

  // §8.3. Адресован автоэскалацией: адресат — адресат текущего уровня. Уровень после ручной передачи остаётся (RULE-76), но адресат уже другой

  def escalatedTo(x: Incident): bool =
    ((x.escalationLevel > 0) and settings.escalation.levels.foldl(false, (acc, l_19) => acc or ((l_19.level == x.escalationLevel) and (l_19.target == addressee(x)))))

  def isDone(x: Incident): bool =
    settings.states.foldl(false, (acc, s_20) => acc or ((s_20.id == x.state) and (s_20.category == "done")))

  // Инцидент по id — списком из одного или пустым

  def byId(xs: List[Incident], id: str): List[Incident] =
    xs.select(e_21 => (e_21.id == id))

  // §5, §8.1. Доступ к объекту: человеку — по его ролям, группе — хотя бы у одного участника

  def hasAccess(who: str, x: Incident): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_22) => acc or access(m_22, x)) else (isOperator(who) and access(who, x)))

  def canAcceptPerson(m: str, x: Incident): bool =
    (can(m, "incident:accept") and access(m, x))

  // §8.1. Может ли принять: право «Принимать» и доступ к объекту; группа — если хотя бы один участник, кроме except: у него инцидент уже есть (RULE-93)

  def canAccept(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_23) => acc or ((m_23 != except) and canAcceptPerson(m_23, x))) else canAcceptPerson(who, x))

  // §8.1. Дежурная группа человека — первая, в которую он входит

  def dutyGroupOf(who: str): str =
    { val gs_24 = dutyGroups.select(g_25 => members(g_25).foldl(false, (acc, y26) => acc or y26 == who))  (if ((gs_24.length() > 0)) gs_24[0] else "") }

  // §8.3. Уровни автоэскалации выше текущего и не выше потолка, адресат которых может принять; уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)

  def nextLevels(x: Incident): List[Level] =
    settings.escalation.levels.select(l_27 => ((((l_27.level > x.escalationLevel) and (l_27.level <= settings.escalation.maxLevel)) and (l_27.target != addressee(x))) and canAccept(l_27.target, x, x.owner)))

  // §2.2. Результаты закрытия, которые этот оператор может выбрать для инцидента

  def closeOptions(who: str, x: Incident, surface: str): List[CloseResultItem] =
    settings.closeResults.select(i_28 => (((can(who, i_28.permission) and i_28.fromStates.foldl(false, (acc, y29) => acc or y29 == x.state)) and not((i_28.ownerOnlyInStates.foldl(false, (acc, y30) => acc or y30 == x.state) and (x.owner != who)))) and (((surface == "") or (i_28.surfaces.length() == 0)) or i_28.surfaces.foldl(false, (acc, y31) => acc or y31 == surface))))

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
    { val ls_32 = nextLevels(x)  ls_32.select(l_33 => ls_32.foldl(true, (acc, k_34) => acc and (l_33.level <= k_34.level))) }

  def levelUpTarget(x: Incident): str =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].target else "")

  def levelUpNumber(x: Incident): int =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].level else 0)

  def timerDef(id: str): TimerDef =
    settings.timerDefs.select(t_35 => (t_35.id == id))[0]

  // Сколько условий у строки overrides: чем больше, тем строка специфичнее

  def overrideKeys(o: Override): int =
    (((o.eventType.length() + o.priority.length()) + o.sourceGroup.length()) + o.escalationLevel.length())

  def overrideMatches(x: Incident, o: Override): bool =
    (((((o.eventType.length() == 0) or (o.eventType[0] == x.eventType)) and ((o.priority.length() == 0) or (o.priority[0] == x.priority))) and ((o.sourceGroup.length() == 0) or inSourceGroup(x, o.sourceGroup[0]))) and ((o.escalationLevel.length() == 0) or (o.escalationLevel[0] == x.escalationLevel)))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (при равных — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_36 = t.overrides.select(o_37 => overrideMatches(x, o_37))  (if ((ms_36.length() > 0)) ms_36.select(o_38 => ms_36.foldl(true, (acc, k_39) => acc and (overrideKeys(k_39) <= overrideKeys(o_38))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold); причины нет — -1, срок не ставится

  def holdSec(x: Incident): int =
    { val rs_40 = settings.holdReasons.select(r_41 => (r_41.id == x.holdReasonId))  (if ((rs_40.length() > 0)) (rs_40[0].maxMinutes * 60) else (0 - 1)) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_42 = settings.escalation.levels.select(l_43 => (l_43.level == x.escalationLevel))  (if ((ls_42.length() > 0)) ls_42[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_44 = x.timers.get(id)  (if ((t_44.due != 0)) (if (((t_44.due - now) > 0)) (t_44.due - now) else 0) else (if (t_44.paused) t_44.left else (0 - 1))) }

  // RULE-50. Норматив нарушен и отработан: остатка нет, дедлайн сработал

  def spent(x: Incident, id: str, now: int): bool =
    ((leftOf(x, id, now) == 0) and (x.timers.get(id).fired != 0))

  // §11.4, BUG-73, BUG-75. Был в группе основного p в момент at: открытый привязанный, присоединённый не позже, или вышедший не раньше

  def inGroupAt(e: Incident, p: Incident, at: int): bool =
    ((((e.linkedTo == p.id) and not(isDone(e))) and (e.linkedAt <= at)) or (((e.leftGroup.primaryId == p.id) and (e.leftGroup.linkedAt <= at)) and (e.leftGroup.at >= at)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w45 = if (not(timerDef(timerId).pausable)) {
      val sec_46 = timerSec(w0.inc.get(iid), timerId, "")
      val w47 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_46 < 0)) 0 else (c.now + (sec_46 * 1000))) }) }) }
      val w48 = { ...w47, inc: w47.inc.set(iid, { ...w47.inc.get(iid), timers: w47.inc.get(iid).timers.set(timerId, { ...w47.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w48
    } else {
      val w49 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_50 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w51 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_50 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_50)) }) }) }
      val w52 = { ...w51, inc: w51.inc.set(iid, { ...w51.inc.get(iid), timers: w51.inc.get(iid).timers.set(timerId, { ...w51.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w53 = { ...w52, inc: w52.inc.set(iid, { ...w52.inc.get(iid), timers: w52.inc.get(iid).timers.set(timerId, { ...w52.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w53
    } else w0
      w49
    }
    w45
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w54 = if (not(timerDef(timerId).pausable)) {
      val w55 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w56 = { ...w55, inc: w55.inc.set(iid, { ...w55.inc.get(iid), timers: w55.inc.get(iid).timers.set(timerId, { ...w55.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w56
    } else {
      val w57 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w58 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w59 = { ...w58, inc: w58.inc.set(iid, { ...w58.inc.get(iid), timers: w58.inc.get(iid).timers.set(timerId, { ...w58.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w60 = { ...w59, inc: w59.inc.set(iid, { ...w59.inc.get(iid), timers: w59.inc.get(iid).timers.set(timerId, { ...w59.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w60
    } else w0
      w57
    }
    w54
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_61 = ""
    val w62 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_61 }) }
    w62
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_63 = ""
    val w64 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_63 }) }
    w64
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_65 = 0
    val w66 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_65 }) }
    w66
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w67 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w68 = if (timerDef("reaction").startsOnce) {
      val w69 = ec_resumeTimer(w0, c, iid, "reaction")
      w69
    } else {
      val sec_70 = timerSec(w0.inc.get(iid), "reaction", "")
      val w71 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_70 < 0)) 0 else (c.now + (sec_70 * 1000))) }) }) }
      val w72 = { ...w71, inc: w71.inc.set(iid, { ...w71.inc.get(iid), timers: w71.inc.get(iid).timers.set("reaction", { ...w71.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w72
    }
      w68
    }
    w67
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
    not(settings.session.states.foldl(false, (acc, s_73) => acc or ((s_73.id == agentState(c.me)) and s_73.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_74 = c.actor
    val w75 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_74 }) }
    w75
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w76 = if (timerDef("reaction").startsOnce) {
      val w77 = ec_pauseTimer(w0, c, iid, "reaction")
      w77
    } else {
      val w78 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w79 = { ...w78, inc: w78.inc.set(iid, { ...w78.inc.get(iid), timers: w78.inc.get(iid).timers.set("reaction", { ...w78.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w79
    }
    w76
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w80 = if (not(timerDef("resolution").pausable)) {
      val sec_81 = timerSec(w0.inc.get(iid), "resolution", "")
      val w82 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_81 < 0)) 0 else (c.now + (sec_81 * 1000))) }) }) }
      val w83 = { ...w82, inc: w82.inc.set(iid, { ...w82.inc.get(iid), timers: w82.inc.get(iid).timers.set("resolution", { ...w82.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w83
    } else {
      val w84 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_85 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w86 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_85 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_85)) }) }) }
      val w87 = { ...w86, inc: w86.inc.set(iid, { ...w86.inc.get(iid), timers: w86.inc.get(iid).timers.set("resolution", { ...w86.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w88 = { ...w87, inc: w87.inc.set(iid, { ...w87.inc.get(iid), timers: w87.inc.get(iid).timers.set("resolution", { ...w87.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w88
    } else w0
      w84
    }
    w80
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
    not(settings.session.states.foldl(false, (acc, s_89) => acc or ((s_89.id == agentState(c.me)) and s_89.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_90 = c.actor
    val w91 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_90 }) }
    w91
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_92 = ""
    val w93 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_92 }) }
    w93
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w94 = if (timerDef("reaction").startsOnce) {
      val w95 = ec_pauseTimer(w0, c, iid, "reaction")
      w95
    } else {
      val w96 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w97 = { ...w96, inc: w96.inc.set(iid, { ...w96.inc.get(iid), timers: w96.inc.get(iid).timers.set("reaction", { ...w96.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w97
    }
    w94
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w98 = if (not(timerDef("resolution").pausable)) {
      val sec_99 = timerSec(w0.inc.get(iid), "resolution", "")
      val w100 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_99 < 0)) 0 else (c.now + (sec_99 * 1000))) }) }) }
      val w101 = { ...w100, inc: w100.inc.set(iid, { ...w100.inc.get(iid), timers: w100.inc.get(iid).timers.set("resolution", { ...w100.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w101
    } else {
      val w102 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_103 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w104 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_103 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_103)) }) }) }
      val w105 = { ...w104, inc: w104.inc.set(iid, { ...w104.inc.get(iid), timers: w104.inc.get(iid).timers.set("resolution", { ...w104.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w106 = { ...w105, inc: w105.inc.set(iid, { ...w105.inc.get(iid), timers: w105.inc.get(iid).timers.set("resolution", { ...w105.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w106
    } else w0
      w102
    }
    w98
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
    not(settings.session.states.foldl(false, (acc, s_107) => acc or ((s_107.id == agentState(c.me)) and s_107.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_108 = ""
    val w109 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_108 }) }
    w109
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_110 = ""
    val w111 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_110 }) }
    w111
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
    not(settings.session.states.foldl(false, (acc, s_112) => acc or ((s_112.id == agentState(c.me)) and s_112.readOnly))),
    ((settings.limits.maxOnHold == 0) or (mineIn(incs(world), c.me, "on_hold", world.inc.get(iid).id).length() < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_113 = c.form.reasonId
    val w114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_113 }) }
    w114
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w115 = if (not(timerDef("resolution").pausable)) {
      val w116 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w117 = { ...w116, inc: w116.inc.set(iid, { ...w116.inc.get(iid), timers: w116.inc.get(iid).timers.set("resolution", { ...w116.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w117
    } else {
      val w118 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w119 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w120 = { ...w119, inc: w119.inc.set(iid, { ...w119.inc.get(iid), timers: w119.inc.get(iid).timers.set("resolution", { ...w119.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w121 = { ...w120, inc: w120.inc.set(iid, { ...w120.inc.get(iid), timers: w120.inc.get(iid).timers.set("resolution", { ...w120.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w121
    } else w0
      w118
    }
    w115
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w122 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w123 = if (timerDef("hold").startsOnce) {
      val w124 = ec_resumeTimer(w0, c, iid, "hold")
      w124
    } else {
      val sec_125 = timerSec(w0.inc.get(iid), "hold", "")
      val w126 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_125 < 0)) 0 else (c.now + (sec_125 * 1000))) }) }) }
      val w127 = { ...w126, inc: w126.inc.set(iid, { ...w126.inc.get(iid), timers: w126.inc.get(iid).timers.set("hold", { ...w126.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w127
    }
      w123
    }
    w122
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
    not(settings.session.states.foldl(false, (acc, s_128) => acc or ((s_128.id == agentState(c.me)) and s_128.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w129 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w129
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w130 = if (timerDef("hold").startsOnce) {
      val w131 = ec_pauseTimer(w0, c, iid, "hold")
      w131
    } else {
      val w132 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w133 = { ...w132, inc: w132.inc.set(iid, { ...w132.inc.get(iid), timers: w132.inc.get(iid).timers.set("hold", { ...w132.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w133
    }
    w130
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w134 = if (not(timerDef("resolution").pausable)) {
      val sec_135 = timerSec(w0.inc.get(iid), "resolution", "")
      val w136 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_135 < 0)) 0 else (c.now + (sec_135 * 1000))) }) }) }
      val w137 = { ...w136, inc: w136.inc.set(iid, { ...w136.inc.get(iid), timers: w136.inc.get(iid).timers.set("resolution", { ...w136.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w137
    } else {
      val w138 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_139 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w140 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_139 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_139)) }) }) }
      val w141 = { ...w140, inc: w140.inc.set(iid, { ...w140.inc.get(iid), timers: w140.inc.get(iid).timers.set("resolution", { ...w140.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w142 = { ...w141, inc: w141.inc.set(iid, { ...w141.inc.get(iid), timers: w141.inc.get(iid).timers.set("resolution", { ...w141.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w142
    } else w0
      w138
    }
    w134
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
    not(settings.session.states.foldl(false, (acc, s_143) => acc or ((s_143.id == agentState(c.me)) and s_143.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_144 = ""
    val w145 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_144 }) }
    w145
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w146 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w146
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w147 = if (not(timerDef("resolution").pausable)) {
      val w148 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w149 = { ...w148, inc: w148.inc.set(iid, { ...w148.inc.get(iid), timers: w148.inc.get(iid).timers.set("resolution", { ...w148.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w149
    } else {
      val w150 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w151 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w152 = { ...w151, inc: w151.inc.set(iid, { ...w151.inc.get(iid), timers: w151.inc.get(iid).timers.set("resolution", { ...w151.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w153 = { ...w152, inc: w152.inc.set(iid, { ...w152.inc.get(iid), timers: w152.inc.get(iid).timers.set("resolution", { ...w152.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w153
    } else w0
      w150
    }
    w147
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w154 = if (timerDef("hold").startsOnce) {
      val w155 = ec_pauseTimer(w0, c, iid, "hold")
      w155
    } else {
      val w156 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w157 = { ...w156, inc: w156.inc.set(iid, { ...w156.inc.get(iid), timers: w156.inc.get(iid).timers.set("hold", { ...w156.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w157
    }
    w154
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w158 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w159 = if (timerDef("reaction").startsOnce) {
      val w160 = ec_resumeTimer(w0, c, iid, "reaction")
      w160
    } else {
      val sec_161 = timerSec(w0.inc.get(iid), "reaction", "")
      val w162 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_161 < 0)) 0 else (c.now + (sec_161 * 1000))) }) }) }
      val w163 = { ...w162, inc: w162.inc.set(iid, { ...w162.inc.get(iid), timers: w162.inc.get(iid).timers.set("reaction", { ...w162.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w163
    }
      w159
    }
    w158
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
    not(settings.session.states.foldl(false, (acc, s_164) => acc or ((s_164.id == agentState(c.me)) and s_164.readOnly))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or incs(world).foldl(true, (acc, e_165) => acc and (((e_165.linkedTo != world.inc.get(iid).id) or isDone(e_165)) or hasAccess(c.form.targetId, e_165)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_166 = personOf(c.form.targetId)
    val w167 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_166 }) }
    w167
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_168 = groupOf(c.form.targetId)
    val w169 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_168 }) }
    w169
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w170 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w170
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w171 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w171
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w172 = if (not(timerDef("resolution").pausable)) {
      val w173 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w174 = { ...w173, inc: w173.inc.set(iid, { ...w173.inc.get(iid), timers: w173.inc.get(iid).timers.set("resolution", { ...w173.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w174
    } else {
      val w175 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w176 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w177 = { ...w176, inc: w176.inc.set(iid, { ...w176.inc.get(iid), timers: w176.inc.get(iid).timers.set("resolution", { ...w176.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w178 = { ...w177, inc: w177.inc.set(iid, { ...w177.inc.get(iid), timers: w177.inc.get(iid).timers.set("resolution", { ...w177.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w178
    } else w0
      w175
    }
    w172
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w179 = if (timerDef("hold").startsOnce) {
      val w180 = ec_pauseTimer(w0, c, iid, "hold")
      w180
    } else {
      val w181 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w182 = { ...w181, inc: w181.inc.set(iid, { ...w181.inc.get(iid), timers: w181.inc.get(iid).timers.set("hold", { ...w181.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w182
    }
    w179
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w183 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w184 = if (timerDef("reaction").startsOnce) {
      val w185 = ec_resumeTimer(w0, c, iid, "reaction")
      w185
    } else {
      val sec_186 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w187 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_186 < 0)) 0 else (c.now + (sec_186 * 1000))) }) }) }
      val w188 = { ...w187, inc: w187.inc.set(iid, { ...w187.inc.get(iid), timers: w187.inc.get(iid).timers.set("reaction", { ...w187.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w188
    }
      w184
    }
    w183
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_189 = c.before.owner
    val w190 = if (((whom_189 != "") and (whom_189 != c.actor))) w0 else w0
    w190
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_191 = addressee(w0.inc.get(iid))
    val w192 = if (((whom_191 != "") and (whom_191 != c.actor))) w0 else w0
    w192
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
    not(settings.session.states.foldl(false, (acc, s_193) => acc or ((s_193.id == agentState(c.me)) and s_193.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_194 = c.actor
    val w195 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_194 }) }
    w195
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_196 = ""
    val w197 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_196 }) }
    w197
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w198 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w198
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w199 = if (timerDef("reaction").startsOnce) {
      val w200 = ec_pauseTimer(w0, c, iid, "reaction")
      w200
    } else {
      val w201 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w202 = { ...w201, inc: w201.inc.set(iid, { ...w201.inc.get(iid), timers: w201.inc.get(iid).timers.set("reaction", { ...w201.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w202
    }
    w199
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w203 = if (timerDef("hold").startsOnce) {
      val w204 = ec_pauseTimer(w0, c, iid, "hold")
      w204
    } else {
      val w205 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w206 = { ...w205, inc: w205.inc.set(iid, { ...w205.inc.get(iid), timers: w205.inc.get(iid).timers.set("hold", { ...w205.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w206
    }
    w203
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w207 = if (not(timerDef("resolution").pausable)) {
      val sec_208 = timerSec(w0.inc.get(iid), "resolution", "")
      val w209 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_208 < 0)) 0 else (c.now + (sec_208 * 1000))) }) }) }
      val w210 = { ...w209, inc: w209.inc.set(iid, { ...w209.inc.get(iid), timers: w209.inc.get(iid).timers.set("resolution", { ...w209.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w210
    } else {
      val w211 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_212 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w213 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_212 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_212)) }) }) }
      val w214 = { ...w213, inc: w213.inc.set(iid, { ...w213.inc.get(iid), timers: w213.inc.get(iid).timers.set("resolution", { ...w213.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w215 = { ...w214, inc: w214.inc.set(iid, { ...w214.inc.get(iid), timers: w214.inc.get(iid).timers.set("resolution", { ...w214.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w215
    } else w0
      w211
    }
    w207
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
    val whom_216 = c.before.owner
    val w217 = if (((whom_216 != "") and (whom_216 != c.actor))) w0 else w0
    w217
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
    not(settings.session.states.foldl(false, (acc, s_218) => acc or ((s_218.id == agentState(c.me)) and s_218.readOnly))),
    { val os_219 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_219.foldl(false, (acc, o_220) => acc or ((o_220.id == c.form.resultId) and stepsOk(o_220, world.inc.get(iid)))) else os_219.foldl(false, (acc, o_221) => acc or stepsOk(o_221, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_222 = c.actor
    val w223 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_222 }) }
    w223
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_224 = ""
    val w225 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_224 }) }
    w225
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_226 = c.actor
    val w227 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_226 }) }
    w227
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_228 = c.now
    val w229 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_228 }) }
    w229
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_230 = c.form.resultId
    val w231 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_230 }) }
    w231
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_232 = c.form.causeId
    val w233 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_232 }) }
    w233
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_234 = c.form.comment
    val w235 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_234 }) }
    w235
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w236 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w236
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w237 = if (timerDef("reaction").startsOnce) {
      val w238 = ec_pauseTimer(w0, c, iid, "reaction")
      w238
    } else {
      val w239 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w240 = { ...w239, inc: w239.inc.set(iid, { ...w239.inc.get(iid), timers: w239.inc.get(iid).timers.set("reaction", { ...w239.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w240
    }
    w237
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w241 = if (not(timerDef("resolution").pausable)) {
      val w242 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w243 = { ...w242, inc: w242.inc.set(iid, { ...w242.inc.get(iid), timers: w242.inc.get(iid).timers.set("resolution", { ...w242.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w243
    } else {
      val w244 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w245 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w246 = { ...w245, inc: w245.inc.set(iid, { ...w245.inc.get(iid), timers: w245.inc.get(iid).timers.set("resolution", { ...w245.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w247 = { ...w246, inc: w246.inc.set(iid, { ...w246.inc.get(iid), timers: w246.inc.get(iid).timers.set("resolution", { ...w246.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w247
    } else w0
      w244
    }
    w241
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w248 = if (timerDef("hold").startsOnce) {
      val w249 = ec_pauseTimer(w0, c, iid, "hold")
      w249
    } else {
      val w250 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w251 = { ...w250, inc: w250.inc.set(iid, { ...w250.inc.get(iid), timers: w250.inc.get(iid).timers.set("hold", { ...w250.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w251
    }
    w248
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
    not(settings.session.states.foldl(false, (acc, s_252) => acc or ((s_252.id == agentState(c.me)) and s_252.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_253 = c.actor
    val w254 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_253 }) }
    w254
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w255 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_256 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w257 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w258 = { ...w257, inc: w257.inc.set(iid, { ...w257.inc.get(iid), linkedTo: "" }) }
      val w259 = { ...w258, inc: w258.inc.set(iid, { ...w258.inc.get(iid), linkedAt: 0 }) }
      val w260 = if (((ps_256.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w259 else w259
      val w261 = if (("workflow.journal.linked_reopened" != "")) {
      val w262 = ps_256.foldl([], (acc, x265) => acc.append(x265.id)).foldl(w260, (wf263, pId264) => wf263)
      w262
    } else w260
      w261
    } else {
      val w266 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w267 = { ...w266, inc: w266.inc.set(iid, { ...w266.inc.get(iid), linkedAt: 0 }) }
      w267
    }
    w255
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_268 = ""
    val w269 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_268 }) }
    w269
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_270 = ""
    val w271 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_270 }) }
    w271
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val sec_272 = settings.limits.reopenResolutionSec
    val w273 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_272 > 0)) sec_272 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w274 = { ...w273, inc: w273.inc.set(iid, { ...w273.inc.get(iid), timers: w273.inc.get(iid).timers.set("resolution", { ...w273.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w275 = { ...w274, inc: w274.inc.set(iid, { ...w274.inc.get(iid), timers: w274.inc.get(iid).timers.set("resolution", { ...w274.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w275
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
    { val t_276 = world.inc.get(iid).timers.get("reaction")  (((t_276.due != 0) and (t_276.due <= c.now)) and (t_276.fired != t_276.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_277 = personOf(levelUpTarget(c.before))
    val w278 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_277 }) }
    w278
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_279 = groupOf(levelUpTarget(c.before))
    val w280 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_279 }) }
    w280
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_281 = levelUpNumber(c.before)
    val w282 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_281 }) }
    w282
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w283 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w283
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w284 = if (not(timerDef("resolution").pausable)) {
      val w285 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w286 = { ...w285, inc: w285.inc.set(iid, { ...w285.inc.get(iid), timers: w285.inc.get(iid).timers.set("resolution", { ...w285.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w286
    } else {
      val w287 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w288 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w289 = { ...w288, inc: w288.inc.set(iid, { ...w288.inc.get(iid), timers: w288.inc.get(iid).timers.set("resolution", { ...w288.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w290 = { ...w289, inc: w289.inc.set(iid, { ...w289.inc.get(iid), timers: w289.inc.get(iid).timers.set("resolution", { ...w289.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w290
    } else w0
      w287
    }
    w284
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w291 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w292 = if (timerDef("reaction").startsOnce) {
      val w293 = ec_resumeTimer(w0, c, iid, "reaction")
      w293
    } else {
      val sec_294 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w295 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_294 < 0)) 0 else (c.now + (sec_294 * 1000))) }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("reaction", { ...w295.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w296
    }
      w292
    }
    w291
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_297 = addressee(w0.inc.get(iid))
    val w298 = if (((whom_297 != "") and (whom_297 != c.actor))) w0 else w0
    w298
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
    { val t_299 = world.inc.get(iid).timers.get("reaction")  (((t_299.due != 0) and (t_299.due <= c.now)) and (t_299.fired != t_299.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_300 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w301 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_300) }) }
    val w302 = { ...w301, inc: w301.inc.set(iid, { ...w301.inc.get(iid), slaBreached: true }) }
    val w303 = incs(w0).select(e_309 => ((e_309.id != w302.inc.get(iid).id) and inGroupAt(e_309, w302.inc.get(iid), c.deadline))).foldl([], (acc, x306) => acc.append(x306.id)).foldl(w302, (wf304, eId305) => {
      val w307 = { ...wf304, inc: wf304.inc.set(eId305, { ...wf304.inc.get(eId305), breaches: wf304.inc.get(eId305).breaches.append(breach_300) }) }
      val w308 = { ...w307, inc: w307.inc.set(eId305, { ...w307.inc.get(eId305), slaBreached: true }) }
      w308
    })
    w303
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w310 = if (timerDef("reaction").startsOnce) {
      val w311 = ec_pauseTimer(w0, c, iid, "reaction")
      w311
    } else {
      val w312 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w313 = { ...w312, inc: w312.inc.set(iid, { ...w312.inc.get(iid), timers: w312.inc.get(iid).timers.set("reaction", { ...w312.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w313
    }
    w310
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_314 = settings.alerts.target
    val w315 = if (((whom_314 != "") and (whom_314 != c.actor))) w0 else w0
    w315
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
    { val t_316 = world.inc.get(iid).timers.get("reaction")  (((t_316.due != 0) and (t_316.due <= c.now)) and (t_316.fired != t_316.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_317 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w318 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_317) }) }
    val w319 = { ...w318, inc: w318.inc.set(iid, { ...w318.inc.get(iid), slaBreached: true }) }
    val w320 = incs(w0).select(e_326 => ((e_326.id != w319.inc.get(iid).id) and inGroupAt(e_326, w319.inc.get(iid), c.deadline))).foldl([], (acc, x323) => acc.append(x323.id)).foldl(w319, (wf321, eId322) => {
      val w324 = { ...wf321, inc: wf321.inc.set(eId322, { ...wf321.inc.get(eId322), breaches: wf321.inc.get(eId322).breaches.append(breach_317) }) }
      val w325 = { ...w324, inc: w324.inc.set(eId322, { ...w324.inc.get(eId322), slaBreached: true }) }
      w325
    })
    w320
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w327 = if (timerDef("reaction").startsOnce) {
      val w328 = ec_pauseTimer(w0, c, iid, "reaction")
      w328
    } else {
      val w329 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w330 = { ...w329, inc: w329.inc.set(iid, { ...w329.inc.get(iid), timers: w329.inc.get(iid).timers.set("reaction", { ...w329.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w330
    }
    w327
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_331 = settings.alerts.target
    val w332 = if (((whom_331 != "") and (whom_331 != c.actor))) w0 else w0
    w332
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
    { val t_333 = world.inc.get(iid).timers.get("resolution")  (((t_333.due != 0) and (t_333.due <= c.now)) and (t_333.fired != t_333.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_334 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w335 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_334) }) }
    val w336 = { ...w335, inc: w335.inc.set(iid, { ...w335.inc.get(iid), slaBreached: true }) }
    val w337 = incs(w0).select(e_343 => ((e_343.id != w336.inc.get(iid).id) and inGroupAt(e_343, w336.inc.get(iid), c.deadline))).foldl([], (acc, x340) => acc.append(x340.id)).foldl(w336, (wf338, eId339) => {
      val w341 = { ...wf338, inc: wf338.inc.set(eId339, { ...wf338.inc.get(eId339), breaches: wf338.inc.get(eId339).breaches.append(breach_334) }) }
      val w342 = { ...w341, inc: w341.inc.set(eId339, { ...w341.inc.get(eId339), slaBreached: true }) }
      w342
    })
    w337
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_344 = settings.alerts.target
    val w345 = if (((whom_344 != "") and (whom_344 != c.actor))) w0 else w0
    w345
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
    { val t_346 = world.inc.get(iid).timers.get("resolution")  (((t_346.due != 0) and (t_346.due <= c.now)) and (t_346.fired != t_346.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_347 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w348 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_347) }) }
    val w349 = { ...w348, inc: w348.inc.set(iid, { ...w348.inc.get(iid), slaBreached: true }) }
    val w350 = incs(w0).select(e_356 => ((e_356.id != w349.inc.get(iid).id) and inGroupAt(e_356, w349.inc.get(iid), c.deadline))).foldl([], (acc, x353) => acc.append(x353.id)).foldl(w349, (wf351, eId352) => {
      val w354 = { ...wf351, inc: wf351.inc.set(eId352, { ...wf351.inc.get(eId352), breaches: wf351.inc.get(eId352).breaches.append(breach_347) }) }
      val w355 = { ...w354, inc: w354.inc.set(eId352, { ...w354.inc.get(eId352), slaBreached: true }) }
      w355
    })
    w350
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_357 = personOf(levelUpTarget(c.before))
    val w358 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_357 }) }
    w358
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_359 = groupOf(levelUpTarget(c.before))
    val w360 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_359 }) }
    w360
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_361 = levelUpNumber(c.before)
    val w362 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_361 }) }
    w362
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w363 = if (not(timerDef("resolution").pausable)) {
      val w364 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w365 = { ...w364, inc: w364.inc.set(iid, { ...w364.inc.get(iid), timers: w364.inc.get(iid).timers.set("resolution", { ...w364.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w365
    } else {
      val w366 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w367 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w368 = { ...w367, inc: w367.inc.set(iid, { ...w367.inc.get(iid), timers: w367.inc.get(iid).timers.set("resolution", { ...w367.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w369 = { ...w368, inc: w368.inc.set(iid, { ...w368.inc.get(iid), timers: w368.inc.get(iid).timers.set("resolution", { ...w368.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w369
    } else w0
      w366
    }
    w363
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w370 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w371 = if (timerDef("reaction").startsOnce) {
      val w372 = ec_resumeTimer(w0, c, iid, "reaction")
      w372
    } else {
      val sec_373 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w374 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_373 < 0)) 0 else (c.now + (sec_373 * 1000))) }) }) }
      val w375 = { ...w374, inc: w374.inc.set(iid, { ...w374.inc.get(iid), timers: w374.inc.get(iid).timers.set("reaction", { ...w374.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w375
    }
      w371
    }
    w370
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_376 = c.before.owner
    val w377 = if (((whom_376 != "") and (whom_376 != c.actor))) w0 else w0
    w377
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_378 = addressee(w0.inc.get(iid))
    val w379 = if (((whom_378 != "") and (whom_378 != c.actor))) w0 else w0
    w379
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
    { val t_380 = world.inc.get(iid).timers.get("resolution")  (((t_380.due != 0) and (t_380.due <= c.now)) and (t_380.fired != t_380.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_381 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w382 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_381) }) }
    val w383 = { ...w382, inc: w382.inc.set(iid, { ...w382.inc.get(iid), slaBreached: true }) }
    val w384 = incs(w0).select(e_390 => ((e_390.id != w383.inc.get(iid).id) and inGroupAt(e_390, w383.inc.get(iid), c.deadline))).foldl([], (acc, x387) => acc.append(x387.id)).foldl(w383, (wf385, eId386) => {
      val w388 = { ...wf385, inc: wf385.inc.set(eId386, { ...wf385.inc.get(eId386), breaches: wf385.inc.get(eId386).breaches.append(breach_381) }) }
      val w389 = { ...w388, inc: w388.inc.set(eId386, { ...w388.inc.get(eId386), slaBreached: true }) }
      w389
    })
    w384
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_391 = settings.alerts.target
    val w392 = if (((whom_391 != "") and (whom_391 != c.actor))) w0 else w0
    w392
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
    { val t_393 = world.inc.get(iid).timers.get("hold")  (((t_393.due != 0) and (t_393.due <= c.now)) and (t_393.fired != t_393.due)) },
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_394 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w395 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_394) }) }
    val w396 = { ...w395, inc: w395.inc.set(iid, { ...w395.inc.get(iid), slaBreached: true }) }
    val w397 = incs(w0).select(e_403 => ((e_403.id != w396.inc.get(iid).id) and inGroupAt(e_403, w396.inc.get(iid), c.deadline))).foldl([], (acc, x400) => acc.append(x400.id)).foldl(w396, (wf398, eId399) => {
      val w401 = { ...wf398, inc: wf398.inc.set(eId399, { ...wf398.inc.get(eId399), breaches: wf398.inc.get(eId399).breaches.append(breach_394) }) }
      val w402 = { ...w401, inc: w401.inc.set(eId399, { ...w401.inc.get(eId399), slaBreached: true }) }
      w402
    })
    w397
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_404 = settings.alerts.target
    val w405 = if (((whom_404 != "") and (whom_404 != c.actor))) w0 else w0
    w405
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
    val reason_406 = "break"
    val w407 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_406 }) }
    w407
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w408 = if (not(timerDef("resolution").pausable)) {
      val w409 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w410 = { ...w409, inc: w409.inc.set(iid, { ...w409.inc.get(iid), timers: w409.inc.get(iid).timers.set("resolution", { ...w409.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w410
    } else {
      val w411 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w412 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w413 = { ...w412, inc: w412.inc.set(iid, { ...w412.inc.get(iid), timers: w412.inc.get(iid).timers.set("resolution", { ...w412.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w414 = { ...w413, inc: w413.inc.set(iid, { ...w413.inc.get(iid), timers: w413.inc.get(iid).timers.set("resolution", { ...w413.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w414
    } else w0
      w411
    }
    w408
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w415 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w416 = if (timerDef("hold").startsOnce) {
      val w417 = ec_resumeTimer(w0, c, iid, "hold")
      w417
    } else {
      val sec_418 = timerSec(w0.inc.get(iid), "hold", "")
      val w419 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_418 < 0)) 0 else (c.now + (sec_418 * 1000))) }) }) }
      val w420 = { ...w419, inc: w419.inc.set(iid, { ...w419.inc.get(iid), timers: w419.inc.get(iid).timers.set("hold", { ...w419.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w420
    }
      w416
    }
    w415
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
    val reason_421 = "no_link"
    val w422 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_421 }) }
    w422
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w423 = if (not(timerDef("resolution").pausable)) {
      val w424 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w425 = { ...w424, inc: w424.inc.set(iid, { ...w424.inc.get(iid), timers: w424.inc.get(iid).timers.set("resolution", { ...w424.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w425
    } else {
      val w426 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w427 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w428 = { ...w427, inc: w427.inc.set(iid, { ...w427.inc.get(iid), timers: w427.inc.get(iid).timers.set("resolution", { ...w427.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w429 = { ...w428, inc: w428.inc.set(iid, { ...w428.inc.get(iid), timers: w428.inc.get(iid).timers.set("resolution", { ...w428.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w429
    } else w0
      w426
    }
    w423
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w430 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w431 = if (timerDef("hold").startsOnce) {
      val w432 = ec_resumeTimer(w0, c, iid, "hold")
      w432
    } else {
      val sec_433 = timerSec(w0.inc.get(iid), "hold", "")
      val w434 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_433 < 0)) 0 else (c.now + (sec_433 * 1000))) }) }) }
      val w435 = { ...w434, inc: w434.inc.set(iid, { ...w434.inc.get(iid), timers: w434.inc.get(iid).timers.set("hold", { ...w434.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w435
    }
      w431
    }
    w430
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_436 = settings.alerts.target
    val w437 = if (((whom_436 != "") and (whom_436 != c.actor))) w0 else w0
    w437
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
    ["break", "no_link"].foldl(false, (acc, y438) => acc or y438 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_439 = ""
    val w440 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_439 }) }
    w440
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w441 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w441
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
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

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
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

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
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
    val group_459 = dutyGroupOf(w0.inc.get(iid).owner)
    val w460 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_459 }) }
    w460
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_461 = ""
    val w462 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_461 }) }
    w462
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_463 = addressee(w0.inc.get(iid))
    val w464 = if (((whom_463 != "") and (whom_463 != c.actor))) w0 else w0
    w464
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
    val who_465 = ""
    val w466 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_465 }) }
    w466
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
    val who_467 = ""
    val w468 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_467 }) }
    w468
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w469 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w469
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w470 = if (timerDef("hold").startsOnce) {
      val w471 = ec_pauseTimer(w0, c, iid, "hold")
      w471
    } else {
      val w472 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w473 = { ...w472, inc: w472.inc.set(iid, { ...w472.inc.get(iid), timers: w472.inc.get(iid).timers.set("hold", { ...w472.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w473
    }
    w470
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w474 = if (not(timerDef("resolution").pausable)) {
      val w475 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w476 = { ...w475, inc: w475.inc.set(iid, { ...w475.inc.get(iid), timers: w475.inc.get(iid).timers.set("resolution", { ...w475.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w476
    } else {
      val w477 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w478 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w479 = { ...w478, inc: w478.inc.set(iid, { ...w478.inc.get(iid), timers: w478.inc.get(iid).timers.set("resolution", { ...w478.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w480 = { ...w479, inc: w479.inc.set(iid, { ...w479.inc.get(iid), timers: w479.inc.get(iid).timers.set("resolution", { ...w479.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w480
    } else w0
      w477
    }
    w474
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w481 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w482 = if (timerDef("reaction").startsOnce) {
      val w483 = ec_resumeTimer(w0, c, iid, "reaction")
      w483
    } else {
      val sec_484 = timerSec(w0.inc.get(iid), "reaction", "")
      val w485 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_484 < 0)) 0 else (c.now + (sec_484 * 1000))) }) }) }
      val w486 = { ...w485, inc: w485.inc.set(iid, { ...w485.inc.get(iid), timers: w485.inc.get(iid).timers.set("reaction", { ...w485.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w486
    }
      w482
    }
    w481
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
    val who_487 = ""
    val w488 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_487 }) }
    w488
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_489 = ""
    val w490 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_489 }) }
    w490
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w491 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w491
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w492 = if (timerDef("hold").startsOnce) {
      val w493 = ec_pauseTimer(w0, c, iid, "hold")
      w493
    } else {
      val w494 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w495 = { ...w494, inc: w494.inc.set(iid, { ...w494.inc.get(iid), timers: w494.inc.get(iid).timers.set("hold", { ...w494.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w495
    }
    w492
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w496 = if (not(timerDef("resolution").pausable)) {
      val w497 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w498 = { ...w497, inc: w497.inc.set(iid, { ...w497.inc.get(iid), timers: w497.inc.get(iid).timers.set("resolution", { ...w497.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w498
    } else {
      val w499 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w500 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w501 = { ...w500, inc: w500.inc.set(iid, { ...w500.inc.get(iid), timers: w500.inc.get(iid).timers.set("resolution", { ...w500.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w502 = { ...w501, inc: w501.inc.set(iid, { ...w501.inc.get(iid), timers: w501.inc.get(iid).timers.set("resolution", { ...w501.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w502
    } else w0
      w499
    }
    w496
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w503 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w504 = if (timerDef("reaction").startsOnce) {
      val w505 = ec_resumeTimer(w0, c, iid, "reaction")
      w505
    } else {
      val sec_506 = timerSec(w0.inc.get(iid), "reaction", "")
      val w507 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_506 < 0)) 0 else (c.now + (sec_506 * 1000))) }) }) }
      val w508 = { ...w507, inc: w507.inc.set(iid, { ...w507.inc.get(iid), timers: w507.inc.get(iid).timers.set("reaction", { ...w507.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w508
    }
      w504
    }
    w503
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_509 = settings.alerts.target
    val w510 = if (((whom_509 != "") and (whom_509 != c.actor))) w0 else w0
    w510
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
    val who_511 = ""
    val w512 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_511 }) }
    w512
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_513 = ""
    val w514 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_513 }) }
    w514
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w515 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w516 = if (timerDef("reaction").startsOnce) {
      val w517 = ec_resumeTimer(w0, c, iid, "reaction")
      w517
    } else {
      val sec_518 = timerSec(w0.inc.get(iid), "reaction", "")
      val w519 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_518 < 0)) 0 else (c.now + (sec_518 * 1000))) }) }) }
      val w520 = { ...w519, inc: w519.inc.set(iid, { ...w519.inc.get(iid), timers: w519.inc.get(iid).timers.set("reaction", { ...w519.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w520
    }
      w516
    }
    w515
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_521 = settings.alerts.target
    val w522 = if (((whom_521 != "") and (whom_521 != c.actor))) w0 else w0
    w522
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
    not(settings.session.states.foldl(false, (acc, s_523) => acc or ((s_523.id == agentState(c.me)) and s_523.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_524 = byId(incs(world), c.form.primaryId)  ((((ps_524.length() > 0) and (ps_524[0].id != world.inc.get(iid).id)) and (ps_524[0].linkedTo == "")) and ((ps_524[0].state == "new") or ((ps_524[0].state == "in_progress") and (ps_524[0].owner == c.me)))) },
    { val ps_525 = byId(incs(world), c.form.primaryId)  ((ps_525.length() > 0) and (ps_525[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w526 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w526
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_527 = byId(incs(w0), c.form.primaryId)
    val w528 = if ((ps_527.length() > 0)) {
      val w529 = incs(w0).select(e_536 => ((e_536.linkedTo == w0.inc.get(iid).id) and not(isDone(e_536)))).foldl([], (acc, x532) => acc.append(x532.id)).foldl(w0, (wf530, cId531) => {
      val w533 = { ...wf530, inc: wf530.inc.set(cId531, { ...wf530.inc.get(cId531), leftGroup: { primaryId: wf530.inc.get(cId531).linkedTo, linkedAt: wf530.inc.get(cId531).linkedAt, at: c.now } }) }
      val w534 = { ...w533, inc: w533.inc.set(cId531, { ...w533.inc.get(cId531), linkedTo: ps_527[0].id }) }
      val w535 = { ...w534, inc: w534.inc.set(cId531, { ...w534.inc.get(cId531), linkedAt: c.now }) }
      w535
    })
      w529
    } else w0
    w528
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_537 = c.form.primaryId
    val w538 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_537 }) }
    val w539 = { ...w538, inc: w538.inc.set(iid, { ...w538.inc.get(iid), linkedAt: c.now }) }
    w539
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_540 = ""
    val w541 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_540 }) }
    w541
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_542 = ""
    val w543 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_542 }) }
    w543
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w544 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w544
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w545 = if (timerDef("reaction").startsOnce) {
      val w546 = ec_pauseTimer(w0, c, iid, "reaction")
      w546
    } else {
      val w547 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w548 = { ...w547, inc: w547.inc.set(iid, { ...w547.inc.get(iid), timers: w547.inc.get(iid).timers.set("reaction", { ...w547.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w548
    }
    w545
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w549 = if (not(timerDef("resolution").pausable)) {
      val w550 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w551 = { ...w550, inc: w550.inc.set(iid, { ...w550.inc.get(iid), timers: w550.inc.get(iid).timers.set("resolution", { ...w550.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w551
    } else {
      val w552 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w553 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w554 = { ...w553, inc: w553.inc.set(iid, { ...w553.inc.get(iid), timers: w553.inc.get(iid).timers.set("resolution", { ...w553.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w555 = { ...w554, inc: w554.inc.set(iid, { ...w554.inc.get(iid), timers: w554.inc.get(iid).timers.set("resolution", { ...w554.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w555
    } else w0
      w552
    }
    w549
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_556 = byId(incs(w0), c.form.primaryId)
    val w557 = if (((((ps_556.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_556[0], "resolution", c.now)))) {
      val t_558 = ps_556[0].timers.get("resolution")
      val left_559 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_560 = (if ((t_558.due != 0)) (t_558.due - c.now) else (if (t_558.paused) t_558.left else (timerSec(ps_556[0], "resolution", "") * 1000)))
      val w561 = if ((left_559 < was_560)) {
      val w562 = ps_556.foldl([], (acc, x565) => acc.append(x565.id)).foldl(w0, (wf563, pId564) => {
      val w566 = if ((t_558.due != 0)) {
      val w567 = { ...wf563, inc: wf563.inc.set(pId564, { ...wf563.inc.get(pId564), timers: wf563.inc.get(pId564).timers.set("resolution", { ...wf563.inc.get(pId564).timers.get("resolution"), due: (c.now + left_559) }) }) }
      w567
    } else {
      val w568 = { ...wf563, inc: wf563.inc.set(pId564, { ...wf563.inc.get(pId564), timers: wf563.inc.get(pId564).timers.set("resolution", { ...wf563.inc.get(pId564).timers.get("resolution"), left: left_559 }) }) }
      val w569 = { ...w568, inc: w568.inc.set(pId564, { ...w568.inc.get(pId564), timers: w568.inc.get(pId564).timers.set("resolution", { ...w568.inc.get(pId564).timers.get("resolution"), paused: true }) }) }
      w569
    }
      w566
    })
      w562
    } else w0
      w561
    } else w0
    w557
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w570 = if (timerDef("hold").startsOnce) {
      val w571 = ec_pauseTimer(w0, c, iid, "hold")
      w571
    } else {
      val w572 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w573 = { ...w572, inc: w572.inc.set(iid, { ...w572.inc.get(iid), timers: w572.inc.get(iid).timers.set("hold", { ...w572.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w573
    }
    w570
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
    not(settings.session.states.foldl(false, (acc, s_574) => acc or ((s_574.id == agentState(c.me)) and s_574.readOnly))),
    { val ps_575 = byId(incs(world), world.inc.get(iid).linkedTo)  ((ps_575.length() > 0) and ((ownership(c.me, ps_575[0]) == "owner") or unowned(ps_575[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_576 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w577 = if (((ps_576.length() > 0) and (leftOf(ps_576[0], "resolution", c.now) >= 0))) {
      val w578 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w579 = { ...w578, inc: w578.inc.set(iid, { ...w578.inc.get(iid), timers: w578.inc.get(iid).timers.set("resolution", { ...w578.inc.get(iid).timers.get("resolution"), left: leftOf(ps_576[0], "resolution", c.now) }) }) }
      val w580 = { ...w579, inc: w579.inc.set(iid, { ...w579.inc.get(iid), timers: w579.inc.get(iid).timers.set("resolution", { ...w579.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w581 = if ((leftOf(ps_576[0], "resolution", c.now) == 0)) {
      val w582 = { ...w580, inc: w580.inc.set(iid, { ...w580.inc.get(iid), timers: w580.inc.get(iid).timers.set("resolution", { ...w580.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_576[0], "resolution", c.now)) ps_576[0].timers.get("resolution").fired else ps_576[0].timers.get("resolution").due) }) }) }
      w582
    } else w580
      w581
    } else w0
    w577
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w583 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_584 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w585 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w586 = { ...w585, inc: w585.inc.set(iid, { ...w585.inc.get(iid), linkedTo: "" }) }
      val w587 = { ...w586, inc: w586.inc.set(iid, { ...w586.inc.get(iid), linkedAt: 0 }) }
      val w588 = if (((ps_584.length() > 0) and ("" != ""))) w587 else w587
      val w589 = if (("" != "")) {
      val w590 = ps_584.foldl([], (acc, x593) => acc.append(x593.id)).foldl(w588, (wf591, pId592) => wf591)
      w590
    } else w588
      w589
    } else {
      val w594 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w595 = { ...w594, inc: w594.inc.set(iid, { ...w594.inc.get(iid), linkedAt: 0 }) }
      w595
    }
    w583
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w596 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w597 = if (timerDef("reaction").startsOnce) {
      val w598 = ec_resumeTimer(w0, c, iid, "reaction")
      w598
    } else {
      val sec_599 = timerSec(w0.inc.get(iid), "reaction", "")
      val w600 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_599 < 0)) 0 else (c.now + (sec_599 * 1000))) }) }) }
      val w601 = { ...w600, inc: w600.inc.set(iid, { ...w600.inc.get(iid), timers: w600.inc.get(iid).timers.set("reaction", { ...w600.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w601
    }
      w597
    }
    w596
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
    { val ps_602 = byId(incs(world), world.inc.get(iid).linkedTo)  ((ps_602.length() > 0) and isDone(ps_602[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_603 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w604 = if ((ps_603.length() > 0)) {
      val w605 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_603[0].closeResultId }) }
      val w606 = { ...w605, inc: w605.inc.set(iid, { ...w605.inc.get(iid), closeCauseId: ps_603[0].closeCauseId }) }
      val w607 = { ...w606, inc: w606.inc.set(iid, { ...w606.inc.get(iid), result: ps_603[0].result }) }
      val w608 = { ...w607, inc: w607.inc.set(iid, { ...w607.inc.get(iid), closedBy: ps_603[0].closedBy }) }
      w608
    } else w0
    w604
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w609 = if (not(timerDef("resolution").pausable)) {
      val w610 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w611 = { ...w610, inc: w610.inc.set(iid, { ...w610.inc.get(iid), timers: w610.inc.get(iid).timers.set("resolution", { ...w610.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w611
    } else {
      val w612 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w613 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w614 = { ...w613, inc: w613.inc.set(iid, { ...w613.inc.get(iid), timers: w613.inc.get(iid).timers.set("resolution", { ...w613.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w615 = { ...w614, inc: w614.inc.set(iid, { ...w614.inc.get(iid), timers: w614.inc.get(iid).timers.set("resolution", { ...w614.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w615
    } else w0
      w612
    }
    w609
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_616 = c.now
    val w617 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_616 }) }
    w617
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
    { val ps_618 = byId(incs(world), world.inc.get(iid).linkedTo)  { val who_619 = (if (((ps_618.length() > 0) and not(isDone(ps_618[0])))) addressee(ps_618[0]) else "")  ((who_619 != "") and (hasAccess(who_619, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_620 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w621 = if (((ps_620.length() > 0) and (leftOf(ps_620[0], "resolution", c.now) >= 0))) {
      val w622 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w623 = { ...w622, inc: w622.inc.set(iid, { ...w622.inc.get(iid), timers: w622.inc.get(iid).timers.set("resolution", { ...w622.inc.get(iid).timers.get("resolution"), left: leftOf(ps_620[0], "resolution", c.now) }) }) }
      val w624 = { ...w623, inc: w623.inc.set(iid, { ...w623.inc.get(iid), timers: w623.inc.get(iid).timers.set("resolution", { ...w623.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w625 = if ((leftOf(ps_620[0], "resolution", c.now) == 0)) {
      val w626 = { ...w624, inc: w624.inc.set(iid, { ...w624.inc.get(iid), timers: w624.inc.get(iid).timers.set("resolution", { ...w624.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_620[0], "resolution", c.now)) ps_620[0].timers.get("resolution").fired else ps_620[0].timers.get("resolution").due) }) }) }
      w626
    } else w624
      w625
    } else w0
    w621
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w627 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_628 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w629 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w630 = { ...w629, inc: w629.inc.set(iid, { ...w629.inc.get(iid), linkedTo: "" }) }
      val w631 = { ...w630, inc: w630.inc.set(iid, { ...w630.inc.get(iid), linkedAt: 0 }) }
      val w632 = if (((ps_628.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w631 else w631
      val w633 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w634 = ps_628.foldl([], (acc, x637) => acc.append(x637.id)).foldl(w632, (wf635, pId636) => wf635)
      w634
    } else w632
      w633
    } else {
      val w638 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w639 = { ...w638, inc: w638.inc.set(iid, { ...w638.inc.get(iid), linkedAt: 0 }) }
      w639
    }
    w627
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w640 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w641 = if (timerDef("reaction").startsOnce) {
      val w642 = ec_resumeTimer(w0, c, iid, "reaction")
      w642
    } else {
      val sec_643 = timerSec(w0.inc.get(iid), "reaction", "")
      val w644 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_643 < 0)) 0 else (c.now + (sec_643 * 1000))) }) }) }
      val w645 = { ...w644, inc: w644.inc.set(iid, { ...w644.inc.get(iid), timers: w644.inc.get(iid).timers.set("reaction", { ...w644.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w645
    }
      w641
    }
    w640
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_646 = settings.alerts.target
    val w647 = if (((whom_646 != "") and (whom_646 != c.actor))) w0 else w0
    w647
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
    ["in_progress"].foldl(false, (acc, y648) => acc or y648 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_649) => acc or ((s_649.id == agentState(c.me)) and s_649.readOnly))),
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
    lastBeat' = if (OPERATORS.contains(a.actor) and (a.kind == "manual" or a.kind == "merge" or a.kind == "merge_auto" or a.name == "answer")) lastBeat.set(a.actor, clock) else lastBeat,
    cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, link' = link,
    lastAction' = a,
  }

  /* ===== Появление инцидента (переход с trigger event) ===== */

  action create(i: str, sc: str, prio: int): bool = {
    val t = ofTrigger("event")[0]
    val w0 = { ...world,
      inc: world.inc.set(i, { ...NO_INCIDENT, id: i, number: i, eventType: "fire", priority: prio, occurredAt: clock, scenario: sc }),
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

  // kind — merge: основного назвал оператор (primaryGuid); merge_auto — основного выбрал сервер
  action mergeAs(kind: str, a: str, p: str, others: Set[str]): bool = {
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
      commit({ ...act0(kind, MERGE, a, p), others: list }, w5),
    }
  }
  action merge(a: str, p: str, others: Set[str]): bool = mergeAs("merge", a, p, others)
  // Основного не назвали — сервер выбирает по mergePrimary машины (§11, ARCH-08 в1)
  action mergeAuto(a: str, sel: Set[str]): bool = {
    val ps = mergePrimary(IDS.select(j => sel.contains(j)).foldl([], (acc, j) => acc.append(incOf(j))), a)
    all { ps.length() == 1, mergeAs("merge_auto", a, ps[0].id, sel.exclude(Set(ps[0].id))) }
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
  // Смена состояния оператора — переход session.transitions машины (AGENT_MOVES, ARCH-08 в4): откуда, куда, право
  // у состояния, куда переходят. На перерыве и после выхода — только просмотр (agentReady машины)
  pure def agentMoveOf(id: str): { id: str, from: Set[str], to: str, permission: str } =
    AGENT_MOVES.fold({ id: "", from: Set(), to: "", permission: "" }, (acc, m) => if (m.id == id) m else acc)
  action agentMove(a: str, id: str): bool = {
    val m = agentMoveOf(id)
    all {
      m.from.contains(agents.get(a)),
      m.permission == "" or can(a, m.permission),
      agent(a, m.id, m.to, true),
    }
  }
  action goOnBreak(a: str): bool = agentMove(a, "break")
  action backFromBreak(a: str): bool = agentMove(a, "back")
  action signOut(a: str): bool = agentMove(a, "sign_out")
  action signIn(a: str): bool = agentMove(a, "sign_in")
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
      {
        nondet sel = INCIDENTS.powerset().oneOf()
        mergeAuto(a, sel)
      },
      time,
      {
        nondet m = AGENT_MOVES.oneOf()
        agentMove(a, m.id)
      },
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
