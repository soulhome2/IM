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

  pure val AGENT_STARTS: Set[str] = Set("offline", "ready")


  // Настройки, от которых зависят ветки автоматических переходов, — все сочетания (PROC-43)

  type Branches = { escalation_enabled: bool, escalation_onResolutionOverdue: str }

  pure val BRANCH_SETTINGS: Set[Branches] = Set(
    { escalation_enabled: true, escalation_onResolutionOverdue: "alert" },
    { escalation_enabled: true, escalation_onResolutionOverdue: "escalate" },
    { escalation_enabled: false, escalation_onResolutionOverdue: "alert" },
    { escalation_enabled: false, escalation_onResolutionOverdue: "escalate" }
  )

  pure def withBranches(s: Settings, b: Branches): Settings = { ...s, escalation: { ...s.escalation, enabled: b.escalation_enabled, onResolutionOverdue: b.escalation_onResolutionOverdue } }

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

  // §11. Основной при «Взять в работу» на выборке, если его не назвал оператор: свой в работе, иначе новый; из них — самый срочный, у равных — появившийся раньше, у совсем равных — первый по порядку выборки: сервер передаёт её по возрастанию номера, а не в порядке отметки (строки в CEL и Quint не упорядочиваются). Списком из одного или пустым

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

  // §12.1. Человек вошёл в МИ: на месте или на перерыве, но не вышел (RULE-100)

  def signedIn(who: str): bool =
    (agentState(who) != "offline")

  // §8.3, RULE-100. Адресат уровня эскалации может принять сейчас: как canAccept, и принимающий не вышел из МИ; вышедшему человеку инцидент уйдёт его дежурной группе (addressee_signed_out_to_group) — уровень доступен, если в ней кто-то, кроме except, не вышел и может принять. Перерыв не мешает (§12.1)

  def canAcceptNow(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_27) => acc or (((m_27 != except) and signedIn(m_27)) and canAcceptPerson(m_27, x))) else (canAcceptPerson(who, x) and (signedIn(who) or { val g_28 = dutyGroupOf(who)  ((g_28 != "") and members(g_28).foldl(false, (acc, m_29) => acc or ((((m_29 != except) and (m_29 != who)) and signedIn(m_29)) and canAcceptPerson(m_29, x)))) })))

  // §8.3. Уровни автоэскалации выше текущего и не выше потолка, адресат которых может принять сейчас (canAcceptNow, RULE-100); уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)

  def nextLevels(x: Incident): List[Level] =
    settings.escalation.levels.select(l_30 => ((((l_30.level > x.escalationLevel) and (l_30.level <= settings.escalation.maxLevel)) and (l_30.target != addressee(x))) and canAcceptNow(l_30.target, x, x.owner)))

  // §2.2. Результаты закрытия, которые этот оператор может выбрать для инцидента

  def closeOptions(who: str, x: Incident, surface: str): List[CloseResultItem] =
    settings.closeResults.select(i_31 => (((can(who, i_31.permission) and i_31.fromStates.foldl(false, (acc, y32) => acc or y32 == x.state)) and not((i_31.ownerOnlyInStates.foldl(false, (acc, y33) => acc or y33 == x.state) and (x.owner != who)))) and (((surface == "") or (i_31.surfaces.length() == 0)) or i_31.surfaces.foldl(false, (acc, y34) => acc or y34 == surface))))

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
    { val ls_35 = nextLevels(x)  ls_35.select(l_36 => ls_35.foldl(true, (acc, k_37) => acc and (l_36.level <= k_37.level))) }

  def levelUpTarget(x: Incident): str =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].target else "")

  def levelUpNumber(x: Incident): int =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].level else 0)

  def timerDef(id: str): TimerDef =
    settings.timerDefs.select(t_38 => (t_38.id == id))[0]

  // Сколько условий у строки overrides: чем больше, тем строка специфичнее

  def overrideKeys(o: Override): int =
    (((o.eventType.length() + o.priority.length()) + o.sourceGroup.length()) + o.escalationLevel.length())

  def overrideMatches(x: Incident, o: Override): bool =
    (((((o.eventType.length() == 0) or (o.eventType[0] == x.eventType)) and ((o.priority.length() == 0) or (o.priority[0] == x.priority))) and ((o.sourceGroup.length() == 0) or inSourceGroup(x, o.sourceGroup[0]))) and ((o.escalationLevel.length() == 0) or (o.escalationLevel[0] == x.escalationLevel)))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (при равных — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_39 = t.overrides.select(o_40 => overrideMatches(x, o_40))  (if ((ms_39.length() > 0)) ms_39.select(o_41 => ms_39.foldl(true, (acc, k_42) => acc and (overrideKeys(k_42) <= overrideKeys(o_41))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold); причины нет — -1, срок не ставится

  def holdSec(x: Incident): int =
    { val rs_43 = settings.holdReasons.select(r_44 => (r_44.id == x.holdReasonId))  (if ((rs_43.length() > 0)) (rs_43[0].maxMinutes * 60) else (0 - 1)) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_45 = settings.escalation.levels.select(l_46 => (l_46.level == x.escalationLevel))  (if ((ls_45.length() > 0)) ls_45[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_47 = x.timers.get(id)  (if ((t_47.due != 0)) (if (((t_47.due - now) > 0)) (t_47.due - now) else 0) else (if (t_47.paused) t_47.left else (0 - 1))) }

  // RULE-50. Норматив нарушен и отработан: остатка нет, дедлайн сработал

  def spent(x: Incident, id: str, now: int): bool =
    ((leftOf(x, id, now) == 0) and (x.timers.get(id).fired != 0))

  // §11.4, BUG-73, BUG-75. Был в группе основного p в момент at: открытый привязанный, присоединённый не позже, или вышедший не раньше

  def inGroupAt(e: Incident, p: Incident, at: int): bool =
    ((((e.linkedTo == p.id) and not(isDone(e))) and (e.linkedAt <= at)) or (((e.leftGroup.primaryId == p.id) and (e.leftGroup.linkedAt <= at)) and (e.leftGroup.at >= at)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w48 = if (not(timerDef(timerId).pausable)) {
      val sec_49 = timerSec(w0.inc.get(iid), timerId, "")
      val w50 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_49 < 0)) 0 else (c.now + (sec_49 * 1000))) }) }) }
      val w51 = { ...w50, inc: w50.inc.set(iid, { ...w50.inc.get(iid), timers: w50.inc.get(iid).timers.set(timerId, { ...w50.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w51
    } else {
      val w52 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_53 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w54 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_53 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_53)) }) }) }
      val w55 = { ...w54, inc: w54.inc.set(iid, { ...w54.inc.get(iid), timers: w54.inc.get(iid).timers.set(timerId, { ...w54.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w56 = { ...w55, inc: w55.inc.set(iid, { ...w55.inc.get(iid), timers: w55.inc.get(iid).timers.set(timerId, { ...w55.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w56
    } else w0
      w52
    }
    w48
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w57 = if (not(timerDef(timerId).pausable)) {
      val w58 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w59 = { ...w58, inc: w58.inc.set(iid, { ...w58.inc.get(iid), timers: w58.inc.get(iid).timers.set(timerId, { ...w58.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w59
    } else {
      val w60 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w61 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w62 = { ...w61, inc: w61.inc.set(iid, { ...w61.inc.get(iid), timers: w61.inc.get(iid).timers.set(timerId, { ...w61.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w63 = { ...w62, inc: w62.inc.set(iid, { ...w62.inc.get(iid), timers: w62.inc.get(iid).timers.set(timerId, { ...w62.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w63
    } else w0
      w60
    }
    w57
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_64 = ""
    val w65 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_64 }) }
    w65
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_66 = ""
    val w67 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_66 }) }
    w67
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_68 = 0
    val w69 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_68 }) }
    w69
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w70 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w71 = if (timerDef("reaction").startsOnce) {
      val w72 = ec_resumeTimer(w0, c, iid, "reaction")
      w72
    } else {
      val sec_73 = timerSec(w0.inc.get(iid), "reaction", "")
      val w74 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_73 < 0)) 0 else (c.now + (sec_73 * 1000))) }) }) }
      val w75 = { ...w74, inc: w74.inc.set(iid, { ...w74.inc.get(iid), timers: w74.inc.get(iid).timers.set("reaction", { ...w74.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w75
    }
      w71
    }
    w70
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
    not(settings.session.states.foldl(false, (acc, s_76) => acc or ((s_76.id == agentState(c.me)) and s_76.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_77 = c.actor
    val w78 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_77 }) }
    w78
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w79 = if (timerDef("reaction").startsOnce) {
      val w80 = ec_pauseTimer(w0, c, iid, "reaction")
      w80
    } else {
      val w81 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w82 = { ...w81, inc: w81.inc.set(iid, { ...w81.inc.get(iid), timers: w81.inc.get(iid).timers.set("reaction", { ...w81.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w82
    }
    w79
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w83 = if (not(timerDef("resolution").pausable)) {
      val sec_84 = timerSec(w0.inc.get(iid), "resolution", "")
      val w85 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_84 < 0)) 0 else (c.now + (sec_84 * 1000))) }) }) }
      val w86 = { ...w85, inc: w85.inc.set(iid, { ...w85.inc.get(iid), timers: w85.inc.get(iid).timers.set("resolution", { ...w85.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w86
    } else {
      val w87 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_88 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w89 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_88 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_88)) }) }) }
      val w90 = { ...w89, inc: w89.inc.set(iid, { ...w89.inc.get(iid), timers: w89.inc.get(iid).timers.set("resolution", { ...w89.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w91 = { ...w90, inc: w90.inc.set(iid, { ...w90.inc.get(iid), timers: w90.inc.get(iid).timers.set("resolution", { ...w90.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w91
    } else w0
      w87
    }
    w83
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
    not(settings.session.states.foldl(false, (acc, s_92) => acc or ((s_92.id == agentState(c.me)) and s_92.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_93 = c.actor
    val w94 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_93 }) }
    w94
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_95 = ""
    val w96 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_95 }) }
    w96
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w97 = if (timerDef("reaction").startsOnce) {
      val w98 = ec_pauseTimer(w0, c, iid, "reaction")
      w98
    } else {
      val w99 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w100 = { ...w99, inc: w99.inc.set(iid, { ...w99.inc.get(iid), timers: w99.inc.get(iid).timers.set("reaction", { ...w99.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w100
    }
    w97
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w101 = if (not(timerDef("resolution").pausable)) {
      val sec_102 = timerSec(w0.inc.get(iid), "resolution", "")
      val w103 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_102 < 0)) 0 else (c.now + (sec_102 * 1000))) }) }) }
      val w104 = { ...w103, inc: w103.inc.set(iid, { ...w103.inc.get(iid), timers: w103.inc.get(iid).timers.set("resolution", { ...w103.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w104
    } else {
      val w105 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_106 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w107 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_106 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_106)) }) }) }
      val w108 = { ...w107, inc: w107.inc.set(iid, { ...w107.inc.get(iid), timers: w107.inc.get(iid).timers.set("resolution", { ...w107.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w109 = { ...w108, inc: w108.inc.set(iid, { ...w108.inc.get(iid), timers: w108.inc.get(iid).timers.set("resolution", { ...w108.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w109
    } else w0
      w105
    }
    w101
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
    not(settings.session.states.foldl(false, (acc, s_110) => acc or ((s_110.id == agentState(c.me)) and s_110.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_111 = ""
    val w112 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_111 }) }
    w112
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_113 = ""
    val w114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_113 }) }
    w114
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
    not(settings.session.states.foldl(false, (acc, s_115) => acc or ((s_115.id == agentState(c.me)) and s_115.readOnly))),
    ((settings.limits.maxOnHold == 0) or (mineIn(incs(world), c.me, "on_hold", world.inc.get(iid).id).length() < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_116 = c.form.reasonId
    val w117 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_116 }) }
    w117
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w118 = if (not(timerDef("resolution").pausable)) {
      val w119 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w120 = { ...w119, inc: w119.inc.set(iid, { ...w119.inc.get(iid), timers: w119.inc.get(iid).timers.set("resolution", { ...w119.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w120
    } else {
      val w121 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w122 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w123 = { ...w122, inc: w122.inc.set(iid, { ...w122.inc.get(iid), timers: w122.inc.get(iid).timers.set("resolution", { ...w122.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w124 = { ...w123, inc: w123.inc.set(iid, { ...w123.inc.get(iid), timers: w123.inc.get(iid).timers.set("resolution", { ...w123.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w124
    } else w0
      w121
    }
    w118
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w125 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w126 = if (timerDef("hold").startsOnce) {
      val w127 = ec_resumeTimer(w0, c, iid, "hold")
      w127
    } else {
      val sec_128 = timerSec(w0.inc.get(iid), "hold", "")
      val w129 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_128 < 0)) 0 else (c.now + (sec_128 * 1000))) }) }) }
      val w130 = { ...w129, inc: w129.inc.set(iid, { ...w129.inc.get(iid), timers: w129.inc.get(iid).timers.set("hold", { ...w129.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w130
    }
      w126
    }
    w125
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
    not(settings.session.states.foldl(false, (acc, s_131) => acc or ((s_131.id == agentState(c.me)) and s_131.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w132 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w132
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w133 = if (timerDef("hold").startsOnce) {
      val w134 = ec_pauseTimer(w0, c, iid, "hold")
      w134
    } else {
      val w135 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w136 = { ...w135, inc: w135.inc.set(iid, { ...w135.inc.get(iid), timers: w135.inc.get(iid).timers.set("hold", { ...w135.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w136
    }
    w133
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w137 = if (not(timerDef("resolution").pausable)) {
      val sec_138 = timerSec(w0.inc.get(iid), "resolution", "")
      val w139 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_138 < 0)) 0 else (c.now + (sec_138 * 1000))) }) }) }
      val w140 = { ...w139, inc: w139.inc.set(iid, { ...w139.inc.get(iid), timers: w139.inc.get(iid).timers.set("resolution", { ...w139.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w140
    } else {
      val w141 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_142 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w143 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_142 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_142)) }) }) }
      val w144 = { ...w143, inc: w143.inc.set(iid, { ...w143.inc.get(iid), timers: w143.inc.get(iid).timers.set("resolution", { ...w143.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w145 = { ...w144, inc: w144.inc.set(iid, { ...w144.inc.get(iid), timers: w144.inc.get(iid).timers.set("resolution", { ...w144.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w145
    } else w0
      w141
    }
    w137
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
    not(settings.session.states.foldl(false, (acc, s_146) => acc or ((s_146.id == agentState(c.me)) and s_146.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_147 = ""
    val w148 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_147 }) }
    w148
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w149 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w149
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w150 = if (not(timerDef("resolution").pausable)) {
      val w151 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w152 = { ...w151, inc: w151.inc.set(iid, { ...w151.inc.get(iid), timers: w151.inc.get(iid).timers.set("resolution", { ...w151.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w152
    } else {
      val w153 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w154 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w155 = { ...w154, inc: w154.inc.set(iid, { ...w154.inc.get(iid), timers: w154.inc.get(iid).timers.set("resolution", { ...w154.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w156 = { ...w155, inc: w155.inc.set(iid, { ...w155.inc.get(iid), timers: w155.inc.get(iid).timers.set("resolution", { ...w155.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w156
    } else w0
      w153
    }
    w150
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w157 = if (timerDef("hold").startsOnce) {
      val w158 = ec_pauseTimer(w0, c, iid, "hold")
      w158
    } else {
      val w159 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w160 = { ...w159, inc: w159.inc.set(iid, { ...w159.inc.get(iid), timers: w159.inc.get(iid).timers.set("hold", { ...w159.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w160
    }
    w157
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w161 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w162 = if (timerDef("reaction").startsOnce) {
      val w163 = ec_resumeTimer(w0, c, iid, "reaction")
      w163
    } else {
      val sec_164 = timerSec(w0.inc.get(iid), "reaction", "")
      val w165 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_164 < 0)) 0 else (c.now + (sec_164 * 1000))) }) }) }
      val w166 = { ...w165, inc: w165.inc.set(iid, { ...w165.inc.get(iid), timers: w165.inc.get(iid).timers.set("reaction", { ...w165.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w166
    }
      w162
    }
    w161
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
    not(settings.session.states.foldl(false, (acc, s_167) => acc or ((s_167.id == agentState(c.me)) and s_167.readOnly))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or incs(world).foldl(true, (acc, e_168) => acc and (((e_168.linkedTo != world.inc.get(iid).id) or isDone(e_168)) or hasAccess(c.form.targetId, e_168)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_169 = personOf(c.form.targetId)
    val w170 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_169 }) }
    w170
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_171 = groupOf(c.form.targetId)
    val w172 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_171 }) }
    w172
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w173 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w173
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w174 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w174
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w175 = if (not(timerDef("resolution").pausable)) {
      val w176 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w177 = { ...w176, inc: w176.inc.set(iid, { ...w176.inc.get(iid), timers: w176.inc.get(iid).timers.set("resolution", { ...w176.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w177
    } else {
      val w178 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w179 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w180 = { ...w179, inc: w179.inc.set(iid, { ...w179.inc.get(iid), timers: w179.inc.get(iid).timers.set("resolution", { ...w179.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w181 = { ...w180, inc: w180.inc.set(iid, { ...w180.inc.get(iid), timers: w180.inc.get(iid).timers.set("resolution", { ...w180.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w181
    } else w0
      w178
    }
    w175
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w182 = if (timerDef("hold").startsOnce) {
      val w183 = ec_pauseTimer(w0, c, iid, "hold")
      w183
    } else {
      val w184 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w185 = { ...w184, inc: w184.inc.set(iid, { ...w184.inc.get(iid), timers: w184.inc.get(iid).timers.set("hold", { ...w184.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w185
    }
    w182
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w186 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w187 = if (timerDef("reaction").startsOnce) {
      val w188 = ec_resumeTimer(w0, c, iid, "reaction")
      w188
    } else {
      val sec_189 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w190 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_189 < 0)) 0 else (c.now + (sec_189 * 1000))) }) }) }
      val w191 = { ...w190, inc: w190.inc.set(iid, { ...w190.inc.get(iid), timers: w190.inc.get(iid).timers.set("reaction", { ...w190.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w191
    }
      w187
    }
    w186
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_192 = c.before.owner
    val w193 = if (((whom_192 != "") and (whom_192 != c.actor))) w0 else w0
    w193
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_194 = addressee(w0.inc.get(iid))
    val w195 = if (((whom_194 != "") and (whom_194 != c.actor))) w0 else w0
    w195
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
    not(settings.session.states.foldl(false, (acc, s_196) => acc or ((s_196.id == agentState(c.me)) and s_196.readOnly))),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_197 = c.actor
    val w198 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_197 }) }
    w198
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_199 = ""
    val w200 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_199 }) }
    w200
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w201 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w201
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w202 = if (timerDef("reaction").startsOnce) {
      val w203 = ec_pauseTimer(w0, c, iid, "reaction")
      w203
    } else {
      val w204 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w205 = { ...w204, inc: w204.inc.set(iid, { ...w204.inc.get(iid), timers: w204.inc.get(iid).timers.set("reaction", { ...w204.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w205
    }
    w202
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w206 = if (timerDef("hold").startsOnce) {
      val w207 = ec_pauseTimer(w0, c, iid, "hold")
      w207
    } else {
      val w208 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w209 = { ...w208, inc: w208.inc.set(iid, { ...w208.inc.get(iid), timers: w208.inc.get(iid).timers.set("hold", { ...w208.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w209
    }
    w206
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w210 = if (not(timerDef("resolution").pausable)) {
      val sec_211 = timerSec(w0.inc.get(iid), "resolution", "")
      val w212 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_211 < 0)) 0 else (c.now + (sec_211 * 1000))) }) }) }
      val w213 = { ...w212, inc: w212.inc.set(iid, { ...w212.inc.get(iid), timers: w212.inc.get(iid).timers.set("resolution", { ...w212.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w213
    } else {
      val w214 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_215 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w216 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_215 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_215)) }) }) }
      val w217 = { ...w216, inc: w216.inc.set(iid, { ...w216.inc.get(iid), timers: w216.inc.get(iid).timers.set("resolution", { ...w216.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w218 = { ...w217, inc: w217.inc.set(iid, { ...w217.inc.get(iid), timers: w217.inc.get(iid).timers.set("resolution", { ...w217.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w218
    } else w0
      w214
    }
    w210
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
    val whom_219 = c.before.owner
    val w220 = if (((whom_219 != "") and (whom_219 != c.actor))) w0 else w0
    w220
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
    not(settings.session.states.foldl(false, (acc, s_221) => acc or ((s_221.id == agentState(c.me)) and s_221.readOnly))),
    { val os_222 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_222.foldl(false, (acc, o_223) => acc or ((o_223.id == c.form.resultId) and stepsOk(o_223, world.inc.get(iid)))) else os_222.foldl(false, (acc, o_224) => acc or stepsOk(o_224, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_225 = c.actor
    val w226 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_225 }) }
    w226
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_227 = ""
    val w228 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_227 }) }
    w228
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_229 = c.actor
    val w230 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_229 }) }
    w230
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_231 = c.now
    val w232 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_231 }) }
    w232
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_233 = c.form.resultId
    val w234 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_233 }) }
    w234
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_235 = c.form.causeId
    val w236 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_235 }) }
    w236
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_237 = c.form.comment
    val w238 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_237 }) }
    w238
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w239 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w239
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w240 = if (timerDef("reaction").startsOnce) {
      val w241 = ec_pauseTimer(w0, c, iid, "reaction")
      w241
    } else {
      val w242 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w243 = { ...w242, inc: w242.inc.set(iid, { ...w242.inc.get(iid), timers: w242.inc.get(iid).timers.set("reaction", { ...w242.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w243
    }
    w240
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w244 = if (not(timerDef("resolution").pausable)) {
      val w245 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w246 = { ...w245, inc: w245.inc.set(iid, { ...w245.inc.get(iid), timers: w245.inc.get(iid).timers.set("resolution", { ...w245.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w246
    } else {
      val w247 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w248 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w249 = { ...w248, inc: w248.inc.set(iid, { ...w248.inc.get(iid), timers: w248.inc.get(iid).timers.set("resolution", { ...w248.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w250 = { ...w249, inc: w249.inc.set(iid, { ...w249.inc.get(iid), timers: w249.inc.get(iid).timers.set("resolution", { ...w249.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w250
    } else w0
      w247
    }
    w244
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w251 = if (timerDef("hold").startsOnce) {
      val w252 = ec_pauseTimer(w0, c, iid, "hold")
      w252
    } else {
      val w253 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("hold", { ...w253.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w254
    }
    w251
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
    not(settings.session.states.foldl(false, (acc, s_255) => acc or ((s_255.id == agentState(c.me)) and s_255.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (mineIn(incs(world), c.me, "in_progress", world.inc.get(iid).id).length() < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_256 = c.actor
    val w257 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_256 }) }
    w257
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w258 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_259 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w260 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w261 = { ...w260, inc: w260.inc.set(iid, { ...w260.inc.get(iid), linkedTo: "" }) }
      val w262 = { ...w261, inc: w261.inc.set(iid, { ...w261.inc.get(iid), linkedAt: 0 }) }
      val w263 = if (((ps_259.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w262 else w262
      val w264 = if (("workflow.journal.linked_reopened" != "")) {
      val w265 = ps_259.foldl([], (acc, x268) => acc.append(x268.id)).foldl(w263, (wf266, pId267) => wf266)
      w265
    } else w263
      w264
    } else {
      val w269 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w270 = { ...w269, inc: w269.inc.set(iid, { ...w269.inc.get(iid), linkedAt: 0 }) }
      w270
    }
    w258
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_271 = ""
    val w272 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_271 }) }
    w272
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_273 = ""
    val w274 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_273 }) }
    w274
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val sec_275 = settings.limits.reopenResolutionSec
    val w276 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_275 > 0)) sec_275 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w277 = { ...w276, inc: w276.inc.set(iid, { ...w276.inc.get(iid), timers: w276.inc.get(iid).timers.set("resolution", { ...w276.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w278 = { ...w277, inc: w277.inc.set(iid, { ...w277.inc.get(iid), timers: w277.inc.get(iid).timers.set("resolution", { ...w277.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w278
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
    { val t_279 = world.inc.get(iid).timers.get("reaction")  (((t_279.due != 0) and (t_279.due <= c.now)) and (t_279.fired != t_279.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_280 = personOf(levelUpTarget(c.before))
    val w281 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_280 }) }
    w281
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_282 = groupOf(levelUpTarget(c.before))
    val w283 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_282 }) }
    w283
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_284 = levelUpNumber(c.before)
    val w285 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_284 }) }
    w285
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w286 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w286
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w287 = if (not(timerDef("resolution").pausable)) {
      val w288 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w289 = { ...w288, inc: w288.inc.set(iid, { ...w288.inc.get(iid), timers: w288.inc.get(iid).timers.set("resolution", { ...w288.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w289
    } else {
      val w290 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w291 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w292 = { ...w291, inc: w291.inc.set(iid, { ...w291.inc.get(iid), timers: w291.inc.get(iid).timers.set("resolution", { ...w291.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w293 = { ...w292, inc: w292.inc.set(iid, { ...w292.inc.get(iid), timers: w292.inc.get(iid).timers.set("resolution", { ...w292.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w293
    } else w0
      w290
    }
    w287
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w294 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w295 = if (timerDef("reaction").startsOnce) {
      val w296 = ec_resumeTimer(w0, c, iid, "reaction")
      w296
    } else {
      val sec_297 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w298 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_297 < 0)) 0 else (c.now + (sec_297 * 1000))) }) }) }
      val w299 = { ...w298, inc: w298.inc.set(iid, { ...w298.inc.get(iid), timers: w298.inc.get(iid).timers.set("reaction", { ...w298.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w299
    }
      w295
    }
    w294
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_300 = addressee(w0.inc.get(iid))
    val w301 = if (((whom_300 != "") and (whom_300 != c.actor))) w0 else w0
    w301
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
    { val t_302 = world.inc.get(iid).timers.get("reaction")  (((t_302.due != 0) and (t_302.due <= c.now)) and (t_302.fired != t_302.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_303 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w304 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_303) }) }
    val w305 = { ...w304, inc: w304.inc.set(iid, { ...w304.inc.get(iid), slaBreached: true }) }
    val w306 = incs(w0).select(e_312 => ((e_312.id != w305.inc.get(iid).id) and inGroupAt(e_312, w305.inc.get(iid), c.deadline))).foldl([], (acc, x309) => acc.append(x309.id)).foldl(w305, (wf307, eId308) => {
      val w310 = { ...wf307, inc: wf307.inc.set(eId308, { ...wf307.inc.get(eId308), breaches: wf307.inc.get(eId308).breaches.append(breach_303) }) }
      val w311 = { ...w310, inc: w310.inc.set(eId308, { ...w310.inc.get(eId308), slaBreached: true }) }
      w311
    })
    w306
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w313 = if (timerDef("reaction").startsOnce) {
      val w314 = ec_pauseTimer(w0, c, iid, "reaction")
      w314
    } else {
      val w315 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w316 = { ...w315, inc: w315.inc.set(iid, { ...w315.inc.get(iid), timers: w315.inc.get(iid).timers.set("reaction", { ...w315.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w316
    }
    w313
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_317 = settings.alerts.target
    val w318 = if (((whom_317 != "") and (whom_317 != c.actor))) w0 else w0
    w318
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
    { val t_319 = world.inc.get(iid).timers.get("reaction")  (((t_319.due != 0) and (t_319.due <= c.now)) and (t_319.fired != t_319.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_320 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w321 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_320) }) }
    val w322 = { ...w321, inc: w321.inc.set(iid, { ...w321.inc.get(iid), slaBreached: true }) }
    val w323 = incs(w0).select(e_329 => ((e_329.id != w322.inc.get(iid).id) and inGroupAt(e_329, w322.inc.get(iid), c.deadline))).foldl([], (acc, x326) => acc.append(x326.id)).foldl(w322, (wf324, eId325) => {
      val w327 = { ...wf324, inc: wf324.inc.set(eId325, { ...wf324.inc.get(eId325), breaches: wf324.inc.get(eId325).breaches.append(breach_320) }) }
      val w328 = { ...w327, inc: w327.inc.set(eId325, { ...w327.inc.get(eId325), slaBreached: true }) }
      w328
    })
    w323
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w330 = if (timerDef("reaction").startsOnce) {
      val w331 = ec_pauseTimer(w0, c, iid, "reaction")
      w331
    } else {
      val w332 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w333 = { ...w332, inc: w332.inc.set(iid, { ...w332.inc.get(iid), timers: w332.inc.get(iid).timers.set("reaction", { ...w332.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w333
    }
    w330
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_334 = settings.alerts.target
    val w335 = if (((whom_334 != "") and (whom_334 != c.actor))) w0 else w0
    w335
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
    { val t_336 = world.inc.get(iid).timers.get("resolution")  (((t_336.due != 0) and (t_336.due <= c.now)) and (t_336.fired != t_336.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_337 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w338 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_337) }) }
    val w339 = { ...w338, inc: w338.inc.set(iid, { ...w338.inc.get(iid), slaBreached: true }) }
    val w340 = incs(w0).select(e_346 => ((e_346.id != w339.inc.get(iid).id) and inGroupAt(e_346, w339.inc.get(iid), c.deadline))).foldl([], (acc, x343) => acc.append(x343.id)).foldl(w339, (wf341, eId342) => {
      val w344 = { ...wf341, inc: wf341.inc.set(eId342, { ...wf341.inc.get(eId342), breaches: wf341.inc.get(eId342).breaches.append(breach_337) }) }
      val w345 = { ...w344, inc: w344.inc.set(eId342, { ...w344.inc.get(eId342), slaBreached: true }) }
      w345
    })
    w340
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_347 = settings.alerts.target
    val w348 = if (((whom_347 != "") and (whom_347 != c.actor))) w0 else w0
    w348
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
    { val t_349 = world.inc.get(iid).timers.get("resolution")  (((t_349.due != 0) and (t_349.due <= c.now)) and (t_349.fired != t_349.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_350 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w351 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_350) }) }
    val w352 = { ...w351, inc: w351.inc.set(iid, { ...w351.inc.get(iid), slaBreached: true }) }
    val w353 = incs(w0).select(e_359 => ((e_359.id != w352.inc.get(iid).id) and inGroupAt(e_359, w352.inc.get(iid), c.deadline))).foldl([], (acc, x356) => acc.append(x356.id)).foldl(w352, (wf354, eId355) => {
      val w357 = { ...wf354, inc: wf354.inc.set(eId355, { ...wf354.inc.get(eId355), breaches: wf354.inc.get(eId355).breaches.append(breach_350) }) }
      val w358 = { ...w357, inc: w357.inc.set(eId355, { ...w357.inc.get(eId355), slaBreached: true }) }
      w358
    })
    w353
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_360 = personOf(levelUpTarget(c.before))
    val w361 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_360 }) }
    w361
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_362 = groupOf(levelUpTarget(c.before))
    val w363 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_362 }) }
    w363
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_364 = levelUpNumber(c.before)
    val w365 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_364 }) }
    w365
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w366 = if (not(timerDef("resolution").pausable)) {
      val w367 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w368 = { ...w367, inc: w367.inc.set(iid, { ...w367.inc.get(iid), timers: w367.inc.get(iid).timers.set("resolution", { ...w367.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w368
    } else {
      val w369 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w370 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w371 = { ...w370, inc: w370.inc.set(iid, { ...w370.inc.get(iid), timers: w370.inc.get(iid).timers.set("resolution", { ...w370.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w372 = { ...w371, inc: w371.inc.set(iid, { ...w371.inc.get(iid), timers: w371.inc.get(iid).timers.set("resolution", { ...w371.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w372
    } else w0
      w369
    }
    w366
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w373 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w374 = if (timerDef("reaction").startsOnce) {
      val w375 = ec_resumeTimer(w0, c, iid, "reaction")
      w375
    } else {
      val sec_376 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w377 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_376 < 0)) 0 else (c.now + (sec_376 * 1000))) }) }) }
      val w378 = { ...w377, inc: w377.inc.set(iid, { ...w377.inc.get(iid), timers: w377.inc.get(iid).timers.set("reaction", { ...w377.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w378
    }
      w374
    }
    w373
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_379 = c.before.owner
    val w380 = if (((whom_379 != "") and (whom_379 != c.actor))) w0 else w0
    w380
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_381 = addressee(w0.inc.get(iid))
    val w382 = if (((whom_381 != "") and (whom_381 != c.actor))) w0 else w0
    w382
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
    { val t_383 = world.inc.get(iid).timers.get("resolution")  (((t_383.due != 0) and (t_383.due <= c.now)) and (t_383.fired != t_383.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_384 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w385 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_384) }) }
    val w386 = { ...w385, inc: w385.inc.set(iid, { ...w385.inc.get(iid), slaBreached: true }) }
    val w387 = incs(w0).select(e_393 => ((e_393.id != w386.inc.get(iid).id) and inGroupAt(e_393, w386.inc.get(iid), c.deadline))).foldl([], (acc, x390) => acc.append(x390.id)).foldl(w386, (wf388, eId389) => {
      val w391 = { ...wf388, inc: wf388.inc.set(eId389, { ...wf388.inc.get(eId389), breaches: wf388.inc.get(eId389).breaches.append(breach_384) }) }
      val w392 = { ...w391, inc: w391.inc.set(eId389, { ...w391.inc.get(eId389), slaBreached: true }) }
      w392
    })
    w387
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_394 = settings.alerts.target
    val w395 = if (((whom_394 != "") and (whom_394 != c.actor))) w0 else w0
    w395
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
    { val t_396 = world.inc.get(iid).timers.get("hold")  (((t_396.due != 0) and (t_396.due <= c.now)) and (t_396.fired != t_396.due)) },
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_397 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w398 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_397) }) }
    val w399 = { ...w398, inc: w398.inc.set(iid, { ...w398.inc.get(iid), slaBreached: true }) }
    val w400 = incs(w0).select(e_406 => ((e_406.id != w399.inc.get(iid).id) and inGroupAt(e_406, w399.inc.get(iid), c.deadline))).foldl([], (acc, x403) => acc.append(x403.id)).foldl(w399, (wf401, eId402) => {
      val w404 = { ...wf401, inc: wf401.inc.set(eId402, { ...wf401.inc.get(eId402), breaches: wf401.inc.get(eId402).breaches.append(breach_397) }) }
      val w405 = { ...w404, inc: w404.inc.set(eId402, { ...w404.inc.get(eId402), slaBreached: true }) }
      w405
    })
    w400
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_407 = settings.alerts.target
    val w408 = if (((whom_407 != "") and (whom_407 != c.actor))) w0 else w0
    w408
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
    val reason_409 = "break"
    val w410 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_409 }) }
    w410
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w411 = if (not(timerDef("resolution").pausable)) {
      val w412 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w413 = { ...w412, inc: w412.inc.set(iid, { ...w412.inc.get(iid), timers: w412.inc.get(iid).timers.set("resolution", { ...w412.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w413
    } else {
      val w414 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w415 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w416 = { ...w415, inc: w415.inc.set(iid, { ...w415.inc.get(iid), timers: w415.inc.get(iid).timers.set("resolution", { ...w415.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w417 = { ...w416, inc: w416.inc.set(iid, { ...w416.inc.get(iid), timers: w416.inc.get(iid).timers.set("resolution", { ...w416.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w417
    } else w0
      w414
    }
    w411
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w418 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w419 = if (timerDef("hold").startsOnce) {
      val w420 = ec_resumeTimer(w0, c, iid, "hold")
      w420
    } else {
      val sec_421 = timerSec(w0.inc.get(iid), "hold", "")
      val w422 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_421 < 0)) 0 else (c.now + (sec_421 * 1000))) }) }) }
      val w423 = { ...w422, inc: w422.inc.set(iid, { ...w422.inc.get(iid), timers: w422.inc.get(iid).timers.set("hold", { ...w422.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w423
    }
      w419
    }
    w418
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
    val reason_424 = "no_link"
    val w425 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_424 }) }
    w425
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w426 = if (not(timerDef("resolution").pausable)) {
      val w427 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w428 = { ...w427, inc: w427.inc.set(iid, { ...w427.inc.get(iid), timers: w427.inc.get(iid).timers.set("resolution", { ...w427.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w428
    } else {
      val w429 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w430 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w431 = { ...w430, inc: w430.inc.set(iid, { ...w430.inc.get(iid), timers: w430.inc.get(iid).timers.set("resolution", { ...w430.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w432 = { ...w431, inc: w431.inc.set(iid, { ...w431.inc.get(iid), timers: w431.inc.get(iid).timers.set("resolution", { ...w431.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w432
    } else w0
      w429
    }
    w426
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w433 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w434 = if (timerDef("hold").startsOnce) {
      val w435 = ec_resumeTimer(w0, c, iid, "hold")
      w435
    } else {
      val sec_436 = timerSec(w0.inc.get(iid), "hold", "")
      val w437 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_436 < 0)) 0 else (c.now + (sec_436 * 1000))) }) }) }
      val w438 = { ...w437, inc: w437.inc.set(iid, { ...w437.inc.get(iid), timers: w437.inc.get(iid).timers.set("hold", { ...w437.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w438
    }
      w434
    }
    w433
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_439 = settings.alerts.target
    val w440 = if (((whom_439 != "") and (whom_439 != c.actor))) w0 else w0
    w440
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
    ["break", "no_link"].foldl(false, (acc, y441) => acc or y441 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_442 = ""
    val w443 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_442 }) }
    w443
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w444 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w444
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w445 = if (timerDef("hold").startsOnce) {
      val w446 = ec_pauseTimer(w0, c, iid, "hold")
      w446
    } else {
      val w447 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w448 = { ...w447, inc: w447.inc.set(iid, { ...w447.inc.get(iid), timers: w447.inc.get(iid).timers.set("hold", { ...w447.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w448
    }
    w445
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w449 = if (not(timerDef("resolution").pausable)) {
      val w450 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w451 = { ...w450, inc: w450.inc.set(iid, { ...w450.inc.get(iid), timers: w450.inc.get(iid).timers.set("resolution", { ...w450.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w451
    } else {
      val w452 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w453 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w454 = { ...w453, inc: w453.inc.set(iid, { ...w453.inc.get(iid), timers: w453.inc.get(iid).timers.set("resolution", { ...w453.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w455 = { ...w454, inc: w454.inc.set(iid, { ...w454.inc.get(iid), timers: w454.inc.get(iid).timers.set("resolution", { ...w454.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w455
    } else w0
      w452
    }
    w449
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w456 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w457 = if (timerDef("reaction").startsOnce) {
      val w458 = ec_resumeTimer(w0, c, iid, "reaction")
      w458
    } else {
      val sec_459 = timerSec(w0.inc.get(iid), "reaction", "")
      val w460 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_459 < 0)) 0 else (c.now + (sec_459 * 1000))) }) }) }
      val w461 = { ...w460, inc: w460.inc.set(iid, { ...w460.inc.get(iid), timers: w460.inc.get(iid).timers.set("reaction", { ...w460.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w461
    }
      w457
    }
    w456
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
    val group_462 = dutyGroupOf(w0.inc.get(iid).owner)
    val w463 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_462 }) }
    w463
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_464 = ""
    val w465 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_464 }) }
    w465
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_466 = addressee(w0.inc.get(iid))
    val w467 = if (((whom_466 != "") and (whom_466 != c.actor))) w0 else w0
    w467
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
    val who_468 = ""
    val w469 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_468 }) }
    w469
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
    val who_470 = ""
    val w471 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_470 }) }
    w471
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w472 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w472
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w473 = if (timerDef("hold").startsOnce) {
      val w474 = ec_pauseTimer(w0, c, iid, "hold")
      w474
    } else {
      val w475 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w476 = { ...w475, inc: w475.inc.set(iid, { ...w475.inc.get(iid), timers: w475.inc.get(iid).timers.set("hold", { ...w475.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w476
    }
    w473
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w477 = if (not(timerDef("resolution").pausable)) {
      val w478 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w479 = { ...w478, inc: w478.inc.set(iid, { ...w478.inc.get(iid), timers: w478.inc.get(iid).timers.set("resolution", { ...w478.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w479
    } else {
      val w480 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w481 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w482 = { ...w481, inc: w481.inc.set(iid, { ...w481.inc.get(iid), timers: w481.inc.get(iid).timers.set("resolution", { ...w481.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w483 = { ...w482, inc: w482.inc.set(iid, { ...w482.inc.get(iid), timers: w482.inc.get(iid).timers.set("resolution", { ...w482.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w483
    } else w0
      w480
    }
    w477
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w484 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w485 = if (timerDef("reaction").startsOnce) {
      val w486 = ec_resumeTimer(w0, c, iid, "reaction")
      w486
    } else {
      val sec_487 = timerSec(w0.inc.get(iid), "reaction", "")
      val w488 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_487 < 0)) 0 else (c.now + (sec_487 * 1000))) }) }) }
      val w489 = { ...w488, inc: w488.inc.set(iid, { ...w488.inc.get(iid), timers: w488.inc.get(iid).timers.set("reaction", { ...w488.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w489
    }
      w485
    }
    w484
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
    val who_490 = ""
    val w491 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_490 }) }
    w491
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_492 = ""
    val w493 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_492 }) }
    w493
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w494 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w494
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w495 = if (timerDef("hold").startsOnce) {
      val w496 = ec_pauseTimer(w0, c, iid, "hold")
      w496
    } else {
      val w497 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w498 = { ...w497, inc: w497.inc.set(iid, { ...w497.inc.get(iid), timers: w497.inc.get(iid).timers.set("hold", { ...w497.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w498
    }
    w495
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w499 = if (not(timerDef("resolution").pausable)) {
      val w500 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w501 = { ...w500, inc: w500.inc.set(iid, { ...w500.inc.get(iid), timers: w500.inc.get(iid).timers.set("resolution", { ...w500.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w501
    } else {
      val w502 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w503 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w504 = { ...w503, inc: w503.inc.set(iid, { ...w503.inc.get(iid), timers: w503.inc.get(iid).timers.set("resolution", { ...w503.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w505 = { ...w504, inc: w504.inc.set(iid, { ...w504.inc.get(iid), timers: w504.inc.get(iid).timers.set("resolution", { ...w504.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w505
    } else w0
      w502
    }
    w499
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w506 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w507 = if (timerDef("reaction").startsOnce) {
      val w508 = ec_resumeTimer(w0, c, iid, "reaction")
      w508
    } else {
      val sec_509 = timerSec(w0.inc.get(iid), "reaction", "")
      val w510 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_509 < 0)) 0 else (c.now + (sec_509 * 1000))) }) }) }
      val w511 = { ...w510, inc: w510.inc.set(iid, { ...w510.inc.get(iid), timers: w510.inc.get(iid).timers.set("reaction", { ...w510.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w511
    }
      w507
    }
    w506
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_512 = settings.alerts.target
    val w513 = if (((whom_512 != "") and (whom_512 != c.actor))) w0 else w0
    w513
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
    val who_514 = ""
    val w515 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_514 }) }
    w515
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_516 = ""
    val w517 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_516 }) }
    w517
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w518 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w519 = if (timerDef("reaction").startsOnce) {
      val w520 = ec_resumeTimer(w0, c, iid, "reaction")
      w520
    } else {
      val sec_521 = timerSec(w0.inc.get(iid), "reaction", "")
      val w522 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_521 < 0)) 0 else (c.now + (sec_521 * 1000))) }) }) }
      val w523 = { ...w522, inc: w522.inc.set(iid, { ...w522.inc.get(iid), timers: w522.inc.get(iid).timers.set("reaction", { ...w522.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w523
    }
      w519
    }
    w518
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_524 = settings.alerts.target
    val w525 = if (((whom_524 != "") and (whom_524 != c.actor))) w0 else w0
    w525
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
    not(settings.session.states.foldl(false, (acc, s_526) => acc or ((s_526.id == agentState(c.me)) and s_526.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_527 = byId(incs(world), c.form.primaryId)  ((((ps_527.length() > 0) and (ps_527[0].id != world.inc.get(iid).id)) and (ps_527[0].linkedTo == "")) and ((ps_527[0].state == "new") or ((ps_527[0].state == "in_progress") and (ps_527[0].owner == c.me)))) },
    { val ps_528 = byId(incs(world), c.form.primaryId)  ((ps_528.length() > 0) and (ps_528[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w529 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w529
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_530 = byId(incs(w0), c.form.primaryId)
    val w531 = if ((ps_530.length() > 0)) {
      val w532 = incs(w0).select(e_539 => ((e_539.linkedTo == w0.inc.get(iid).id) and not(isDone(e_539)))).foldl([], (acc, x535) => acc.append(x535.id)).foldl(w0, (wf533, cId534) => {
      val w536 = { ...wf533, inc: wf533.inc.set(cId534, { ...wf533.inc.get(cId534), leftGroup: { primaryId: wf533.inc.get(cId534).linkedTo, linkedAt: wf533.inc.get(cId534).linkedAt, at: c.now } }) }
      val w537 = { ...w536, inc: w536.inc.set(cId534, { ...w536.inc.get(cId534), linkedTo: ps_530[0].id }) }
      val w538 = { ...w537, inc: w537.inc.set(cId534, { ...w537.inc.get(cId534), linkedAt: c.now }) }
      w538
    })
      w532
    } else w0
    w531
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_540 = c.form.primaryId
    val w541 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_540 }) }
    val w542 = { ...w541, inc: w541.inc.set(iid, { ...w541.inc.get(iid), linkedAt: c.now }) }
    w542
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_543 = ""
    val w544 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_543 }) }
    w544
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_545 = ""
    val w546 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_545 }) }
    w546
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w547 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w547
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w548 = if (timerDef("reaction").startsOnce) {
      val w549 = ec_pauseTimer(w0, c, iid, "reaction")
      w549
    } else {
      val w550 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w551 = { ...w550, inc: w550.inc.set(iid, { ...w550.inc.get(iid), timers: w550.inc.get(iid).timers.set("reaction", { ...w550.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w551
    }
    w548
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w552 = if (not(timerDef("resolution").pausable)) {
      val w553 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w554 = { ...w553, inc: w553.inc.set(iid, { ...w553.inc.get(iid), timers: w553.inc.get(iid).timers.set("resolution", { ...w553.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w554
    } else {
      val w555 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w556 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w557 = { ...w556, inc: w556.inc.set(iid, { ...w556.inc.get(iid), timers: w556.inc.get(iid).timers.set("resolution", { ...w556.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w558 = { ...w557, inc: w557.inc.set(iid, { ...w557.inc.get(iid), timers: w557.inc.get(iid).timers.set("resolution", { ...w557.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w558
    } else w0
      w555
    }
    w552
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_559 = byId(incs(w0), c.form.primaryId)
    val w560 = if (((((ps_559.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_559[0], "resolution", c.now)))) {
      val t_561 = ps_559[0].timers.get("resolution")
      val left_562 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_563 = (if ((t_561.due != 0)) (t_561.due - c.now) else (if (t_561.paused) t_561.left else (timerSec(ps_559[0], "resolution", "") * 1000)))
      val w564 = if ((left_562 < was_563)) {
      val w565 = ps_559.foldl([], (acc, x568) => acc.append(x568.id)).foldl(w0, (wf566, pId567) => {
      val w569 = if ((t_561.due != 0)) {
      val w570 = { ...wf566, inc: wf566.inc.set(pId567, { ...wf566.inc.get(pId567), timers: wf566.inc.get(pId567).timers.set("resolution", { ...wf566.inc.get(pId567).timers.get("resolution"), due: (c.now + left_562) }) }) }
      w570
    } else {
      val w571 = { ...wf566, inc: wf566.inc.set(pId567, { ...wf566.inc.get(pId567), timers: wf566.inc.get(pId567).timers.set("resolution", { ...wf566.inc.get(pId567).timers.get("resolution"), left: left_562 }) }) }
      val w572 = { ...w571, inc: w571.inc.set(pId567, { ...w571.inc.get(pId567), timers: w571.inc.get(pId567).timers.set("resolution", { ...w571.inc.get(pId567).timers.get("resolution"), paused: true }) }) }
      w572
    }
      w569
    })
      w565
    } else w0
      w564
    } else w0
    w560
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w573 = if (timerDef("hold").startsOnce) {
      val w574 = ec_pauseTimer(w0, c, iid, "hold")
      w574
    } else {
      val w575 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w576 = { ...w575, inc: w575.inc.set(iid, { ...w575.inc.get(iid), timers: w575.inc.get(iid).timers.set("hold", { ...w575.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w576
    }
    w573
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
    not(settings.session.states.foldl(false, (acc, s_577) => acc or ((s_577.id == agentState(c.me)) and s_577.readOnly))),
    { val ps_578 = byId(incs(world), world.inc.get(iid).linkedTo)  ((ps_578.length() > 0) and ((ownership(c.me, ps_578[0]) == "owner") or unowned(ps_578[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_579 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w580 = if (((ps_579.length() > 0) and (leftOf(ps_579[0], "resolution", c.now) >= 0))) {
      val w581 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w582 = { ...w581, inc: w581.inc.set(iid, { ...w581.inc.get(iid), timers: w581.inc.get(iid).timers.set("resolution", { ...w581.inc.get(iid).timers.get("resolution"), left: leftOf(ps_579[0], "resolution", c.now) }) }) }
      val w583 = { ...w582, inc: w582.inc.set(iid, { ...w582.inc.get(iid), timers: w582.inc.get(iid).timers.set("resolution", { ...w582.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w584 = if ((leftOf(ps_579[0], "resolution", c.now) == 0)) {
      val w585 = { ...w583, inc: w583.inc.set(iid, { ...w583.inc.get(iid), timers: w583.inc.get(iid).timers.set("resolution", { ...w583.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_579[0], "resolution", c.now)) ps_579[0].timers.get("resolution").fired else ps_579[0].timers.get("resolution").due) }) }) }
      w585
    } else w583
      w584
    } else w0
    w580
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w586 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_587 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w588 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w589 = { ...w588, inc: w588.inc.set(iid, { ...w588.inc.get(iid), linkedTo: "" }) }
      val w590 = { ...w589, inc: w589.inc.set(iid, { ...w589.inc.get(iid), linkedAt: 0 }) }
      val w591 = if (((ps_587.length() > 0) and ("" != ""))) w590 else w590
      val w592 = if (("" != "")) {
      val w593 = ps_587.foldl([], (acc, x596) => acc.append(x596.id)).foldl(w591, (wf594, pId595) => wf594)
      w593
    } else w591
      w592
    } else {
      val w597 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w598 = { ...w597, inc: w597.inc.set(iid, { ...w597.inc.get(iid), linkedAt: 0 }) }
      w598
    }
    w586
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w599 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w600 = if (timerDef("reaction").startsOnce) {
      val w601 = ec_resumeTimer(w0, c, iid, "reaction")
      w601
    } else {
      val sec_602 = timerSec(w0.inc.get(iid), "reaction", "")
      val w603 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_602 < 0)) 0 else (c.now + (sec_602 * 1000))) }) }) }
      val w604 = { ...w603, inc: w603.inc.set(iid, { ...w603.inc.get(iid), timers: w603.inc.get(iid).timers.set("reaction", { ...w603.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w604
    }
      w600
    }
    w599
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
    { val ps_605 = byId(incs(world), world.inc.get(iid).linkedTo)  ((ps_605.length() > 0) and isDone(ps_605[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_606 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w607 = if ((ps_606.length() > 0)) {
      val w608 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_606[0].closeResultId }) }
      val w609 = { ...w608, inc: w608.inc.set(iid, { ...w608.inc.get(iid), closeCauseId: ps_606[0].closeCauseId }) }
      val w610 = { ...w609, inc: w609.inc.set(iid, { ...w609.inc.get(iid), result: ps_606[0].result }) }
      val w611 = { ...w610, inc: w610.inc.set(iid, { ...w610.inc.get(iid), closedBy: ps_606[0].closedBy }) }
      val w612 = { ...w611, inc: w611.inc.set(iid, { ...w611.inc.get(iid), owner: ps_606[0].closedBy }) }
      w612
    } else w0
    w607
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w613 = if (not(timerDef("resolution").pausable)) {
      val w614 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w615 = { ...w614, inc: w614.inc.set(iid, { ...w614.inc.get(iid), timers: w614.inc.get(iid).timers.set("resolution", { ...w614.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w615
    } else {
      val w616 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w617 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w618 = { ...w617, inc: w617.inc.set(iid, { ...w617.inc.get(iid), timers: w617.inc.get(iid).timers.set("resolution", { ...w617.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w619 = { ...w618, inc: w618.inc.set(iid, { ...w618.inc.get(iid), timers: w618.inc.get(iid).timers.set("resolution", { ...w618.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w619
    } else w0
      w616
    }
    w613
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_620 = c.now
    val w621 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_620 }) }
    w621
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
    { val ps_622 = byId(incs(world), world.inc.get(iid).linkedTo)  { val who_623 = (if (((ps_622.length() > 0) and not(isDone(ps_622[0])))) addressee(ps_622[0]) else "")  ((who_623 != "") and (hasAccess(who_623, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_624 = byId(incs(w0), w0.inc.get(iid).linkedTo)
    val w625 = if (((ps_624.length() > 0) and (leftOf(ps_624[0], "resolution", c.now) >= 0))) {
      val w626 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w627 = { ...w626, inc: w626.inc.set(iid, { ...w626.inc.get(iid), timers: w626.inc.get(iid).timers.set("resolution", { ...w626.inc.get(iid).timers.get("resolution"), left: leftOf(ps_624[0], "resolution", c.now) }) }) }
      val w628 = { ...w627, inc: w627.inc.set(iid, { ...w627.inc.get(iid), timers: w627.inc.get(iid).timers.set("resolution", { ...w627.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w629 = if ((leftOf(ps_624[0], "resolution", c.now) == 0)) {
      val w630 = { ...w628, inc: w628.inc.set(iid, { ...w628.inc.get(iid), timers: w628.inc.get(iid).timers.set("resolution", { ...w628.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_624[0], "resolution", c.now)) ps_624[0].timers.get("resolution").fired else ps_624[0].timers.get("resolution").due) }) }) }
      w630
    } else w628
      w629
    } else w0
    w625
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w631 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_632 = byId(incs(w0), w0.inc.get(iid).linkedTo)
      val w633 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w634 = { ...w633, inc: w633.inc.set(iid, { ...w633.inc.get(iid), linkedTo: "" }) }
      val w635 = { ...w634, inc: w634.inc.set(iid, { ...w634.inc.get(iid), linkedAt: 0 }) }
      val w636 = if (((ps_632.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w635 else w635
      val w637 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w638 = ps_632.foldl([], (acc, x641) => acc.append(x641.id)).foldl(w636, (wf639, pId640) => wf639)
      w638
    } else w636
      w637
    } else {
      val w642 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w643 = { ...w642, inc: w642.inc.set(iid, { ...w642.inc.get(iid), linkedAt: 0 }) }
      w643
    }
    w631
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w644 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w645 = if (timerDef("reaction").startsOnce) {
      val w646 = ec_resumeTimer(w0, c, iid, "reaction")
      w646
    } else {
      val sec_647 = timerSec(w0.inc.get(iid), "reaction", "")
      val w648 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_647 < 0)) 0 else (c.now + (sec_647 * 1000))) }) }) }
      val w649 = { ...w648, inc: w648.inc.set(iid, { ...w648.inc.get(iid), timers: w648.inc.get(iid).timers.set("reaction", { ...w648.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w649
    }
      w645
    }
    w644
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_650 = settings.alerts.target
    val w651 = if (((whom_650 != "") and (whom_650 != c.actor))) w0 else w0
    w651
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

  def form_hold(c: Ctx, iid: str): bool = all {
    c.form.reasonId == "" or all {
      Set("third_party", "patrol", "no_data", "break", "no_link").contains(c.form.reasonId),
      settings.holdReasons.foldl(false, (acc, r_652) => acc or ((r_652.id == c.form.reasonId) and (r_652.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      ((not(isSelf(c.me, c.form.targetId)) and (c.form.targetId != addressee(world.inc.get(iid)))) and canAccept(c.form.targetId, world.inc.get(iid), "")),
      incs(world).foldl(true, (acc, e_653) => acc and (((e_653.linkedTo != world.inc.get(iid).id) or isDone(e_653)) or hasAccess(c.form.targetId, e_653))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_654) => acc or (i_654.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_655) => acc or ((i_655.id == c.form.resultId) and stepsOk(i_655, world.inc.get(iid)))),
    },
    c.form.causeId == "" or all {
      (c.form.resultId == "mass"),
      Set("power", "link", "mass_fault", "known").contains(c.form.causeId),
    },
  }

  def formOk(tid: str, c: Ctx, iid: str): bool =
    if (tid == "hold") form_hold(c, iid)
    else if (tid == "transfer") form_transfer(c, iid)
    else if (tid == "close") form_close(c, iid)
    else true

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
    ["in_progress"].foldl(false, (acc, y656) => acc or y656 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_657) => acc or ((s_657.id == agentState(c.me)) and s_657.readOnly))),
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
  // Сколько автоматических переходов у инцидента подряд — без действий людей и окружения, только со временем (П3, PROC-45)
  var autoRun: str -> int

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
    // Автоматический переход — ещё один подряд; любое другое действие счёт сбрасывает (П3)
    autoRun' = if (a.kind == "auto") autoRun.set(a.incident, autoRun.get(a.incident) + 1) else INCIDENTS.mapBy(j => 0),
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
      // Значения полей-списков — по правилам формы машины, как проверяет сервер (ARCH-09)
      formOk(tid, c, i),
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
      autoRun' = autoRun,
    }
  }

  action agent(a: str, name: str, state: str, beat: bool): bool = all {
    agents' = agents.set(a, state),
    lastBeat' = if (beat) lastBeat.set(a, clock) else lastBeat,
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
    autoRun' = INCIDENTS.mapBy(j => 0),
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
    autoRun' = INCIDENTS.mapBy(j => 0),
  }
  action restoreLink(a: str): bool = all {
    not(link.get(a)),
    link' = link.set(a, true),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, changedAt' = changedAt,
    lastAction' = act0("env", "restore_link", a, NOBODY),
    autoRun' = INCIDENTS.mapBy(j => 0),
  }

  // Запрос оператора, который ничего не изменил, — отказанный переход, подсчёт выборки: тоже признак активности.
  // Любой запрос, кроме чтения (§12.3, BUG-76 а), RULE-112); нужна связь
  action request(a: str): bool = all {
    link.get(a),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", "request", a, NOBODY),
    autoRun' = INCIDENTS.mapBy(j => 0),
  }

  // Сменились роли (§5): доступ к объекту инцидента, право «Принимать»
  action roles(a: str, name: str, c: Config): bool = all {
    cfg' = c,
    world' = world, settings' = settings, clock' = clock, agents' = agents, lastBeat' = lastBeat, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
    autoRun' = INCIDENTS.mapBy(j => 0),
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
    // Настройки, от которых зависят ветки автоматических переходов, — из машины (BRANCH_SETTINGS, PROC-43)
    nondet branch = BRANCH_SETTINGS.oneOf()
    nondet maxActive = Set(0, 1).oneOf()
    nondet maxOnHold = Set(0, 1).oneOf()
    nondet level1 = OPERATORS.oneOf()
    nondet starts = OPERATORS.setOfMaps(AGENT_STARTS).oneOf()
    val levels = MACHINE_SETTINGS.escalation.levels
    all {
      cfg' = { perms: perms, access: access, members: Map(GROUP -> grp) },
      // Настройки — значения машины; перебираются ветки автоматики (withBranches) и лимиты, люди — люди модели:
      // уровень 1 — человек, уровень 2 — дежурная группа, алерты — группе
      settings' = withBranches({ ...MACHINE_SETTINGS,
        escalation: { ...MACHINE_SETTINGS.escalation,
          levels: [{ ...levels[0], targetKind: "user", target: level1 }, { ...levels[1], targetKind: "group", target: GROUP }] },
        alerts: { ...MACHINE_SETTINGS.alerts, targetKind: "group", target: GROUP },
        limits: { ...MACHINE_SETTINGS.limits, maxActive: maxActive, maxOnHold: maxOnHold },
      }, branch),
      world' = { inc: INCIDENTS.mapBy(i => NO_INCIDENT), answers: INCIDENTS.mapBy(i => Set()) },
      clock' = START,
      // Оператор — ещё не вошёл (начальное машины) или уже вошёл (RULE-99)
      agents' = starts,
      lastBeat' = OPERATORS.mapBy(a => START),
      link' = OPERATORS.mapBy(a => true),
      changedAt' = INCIDENTS.mapBy(i => 0),
      lastAction' = act0("init", "init", NOBODY, NOBODY),
      autoRun' = INCIDENTS.mapBy(i => 0),
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
      request(a),
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
    // Закрытый — у того, кто закрыл; закрытый вместе с основным (close_linked) — у закрывшего основной (BUG-89)
    else if (s == "closed")
      OPERATORS.contains(x.closedBy) and x.assignmentGroup == NOBODY and x.owner == x.closedBy
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

  // 11. Эскалация не отдаёт инцидент туда, где принять сейчас некому: вышедшему человеку, у которого в дежурной
  //     группе никто не на месте, кто может принять, и группе, где вышли все, кто может принять (§8.3, RULE-100)
  def presentAcceptor(m: str, x: Incident): bool =
    agentState(m) != "offline" and m != x.owner and can(m, "incident:accept") and access(m, x)
  def escalatesToNobody(tid: str, i: str): bool = {
    val x = incOf(i)
    val t = levelUpTarget(x)
    val g = dutyGroupOf(t)
    val nobody =
      if (isGroup(t)) not(cfg.members.get(t).exists(m => presentAcceptor(m, x)))
      else agentState(t) == "offline" and not(g != "" and cfg.members.get(g).exists(m => m != t and presentAcceptor(m, x)))
    autoReady(tr(tid), i) and t != "" and nobody
  }
  val autoEscalateToSomeone = INCIDENTS.forall(i => not(escalatesToNobody("auto_escalate", i)))
  val resolutionEscalateToSomeone = INCIDENTS.forall(i => not(escalatesToNobody("resolution_escalate", i)))

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

  // 12. П1. Наступивший дедлайн обработан не позже окна после него: часы не уходят за дедлайн + graceSec, пока
  //     срабатывание не выполнено — ни реакция, ни удержание не висят просроченными без нарушения (§4, §10.1, PROC-45)
  val deadlineFiredInWindow = INCIDENTS.forall(i => TIMER_IDS.forall(k => {
    val t = incOf(i).timers.get(k)
    isDueT(t) implies clock <= t.due + GRACE_MS
  }))

  // 13. П2. Молчащий владелец, который не вышел (§12.3): «В работе» при молчании от idleHoldSec — сейчас
  //     откладывается; отложенный системой (причины, которые оператор сам не выбирает) при молчании от
  //     idleReleaseSec — сейчас уходит в очередь (PROC-45)
  val silentOwnerHandled = INCIDENTS.forall(i => {
    val x = incOf(i)
    val idle = if (OPERATORS.contains(x.owner) and agentState(x.owner) != "offline") idleSec(x.owner) else 0
    all {
      (x.state == "in_progress" and idle >= settings.session.idleHoldSec) implies autoPending(i),
      (x.state == "on_hold" and x.holdReasonId != NOBODY and not(HOLD_REASONS_BY_OPERATOR.contains(x.holdReasonId)) and idle >= settings.session.idleReleaseSec) implies autoPending(i),
    }
  })

  // 14. П3. Без людей автоматика конечна: подряд, только со временем, у инцидента — не больше AUTO_BOUND
  //     автоматических переходов; эскалация упирается в потолок, круга нет. Самая длинная цепочка — около 8,
  //     например resolution_overdue → system_hold_idle → hold_overdue → system_release_idle → auto_escalate → …
  //     → escalation_ceiling; при пределе 3 модель находит нарушение — у предела есть запас, но не лишний (PROC-45)
  pure val AUTO_BOUND = 10
  val autoBounded = INCIDENTS.forall(i => autoRun.get(i) <= AUTO_BOUND)

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
    autoEscalateToSomeone,
    resolutionEscalateToSomeone,
    linkedShape,
    openNotLinked,
    resolutionBreachHasOwner,
    linkedSharesBreaches,
    noIncidentWithoutAccess,
    autoNotRepeated,
    linkedSameScenario,
    processedOnlyFinished,
    agentStateRespected,
    deadlineFiredInWindow,
    silentOwnerHandled,
    autoBounded,
  }
}
