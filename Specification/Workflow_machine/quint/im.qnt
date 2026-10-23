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

  type TimerDef = { id: str, labelKey: str, defaultSec: int, byPriority: int -> int, overridesBy: List[str], overrides: List[Override], startsOnce: bool, pausable: bool, secFrom: str }

  type Override = { eventType: List[str], priority: List[int], sourceGroup: List[str], sec: int }

  type HoldReason = { id: str, maxMinutes: List[int], setBy: str }

  type Settings = { limits: Limits, session: Session, escalation: Escalation, alerts: Alerts, states: List[State], closeResults: List[CloseResultItem], timerDefs: List[TimerDef], holdReasons: List[HoldReason] }


  /* ===== Настройки — значения машины (cel.settings) ===== */


  pure val MACHINE_SETTINGS: Settings = {
    limits: { maxActive: 0, maxOnHold: 5, maxBulk: 0, reopenWindowMin: 1440, reopenResolutionSec: 0 },
    session: { states: [{ id: "ready", readOnly: false, readOnlyReasonKey: "" }, { id: "busy", readOnly: false, readOnlyReasonKey: "" }, { id: "not_ready", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.not_ready" }, { id: "offline", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.offline" }], heartbeatSec: 30, idleHoldSec: 300, idleReleaseSec: 1200 },
    escalation: { enabled: true, levels: [{ level: 1, targetKind: "user", target: "petrova", reactionSec: 120 }, { level: 2, targetKind: "user", target: "noc", reactionSec: 90 }], maxLevel: 2, onResolutionOverdue: "alert" },
    alerts: { targetKind: "group", target: "grp-leads", noRecipientLog: "workflow.journal.alert_no_recipient" },
    states: [{ id: "new", category: "pending" }, { id: "pending_acceptance", category: "pending" }, { id: "in_progress", category: "active" }, { id: "on_hold", category: "active" }, { id: "closed", category: "done" }, { id: "linked", category: "linked" }],
    closeResults: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "closing", commentRequired: false, finish: true }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", permission: "incident:close:unprocessed", fromStates: ["new", "pending_acceptance", "in_progress", "on_hold"], ownerOnlyInStates: ["in_progress", "on_hold"], surfaces: ["queue", "card"], requiredStepSet: "none", commentRequired: true, finish: false }],
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overridesBy: ["eventType", "priority", "sourceGroup"], overrides: [{ eventType: [], priority: [100], sourceGroup: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], sec: 1800 }], startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overridesBy: ["eventType", "priority", "sourceGroup"], overrides: [], startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overridesBy: [], overrides: [], startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
    holdReasons: [{ id: "third_party", maxMinutes: [30], setBy: "operator" }, { id: "patrol", maxMinutes: [45], setBy: "operator" }, { id: "no_data", maxMinutes: [60], setBy: "operator" }, { id: "break", maxMinutes: [30], setBy: "system" }, { id: "no_link", maxMinutes: [], setBy: "system" }],
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
    ((o.eventType.length() + o.priority.length()) + o.sourceGroup.length())

  def overrideMatches(x: Incident, o: Override): bool =
    ((((o.eventType.length() == 0) or (o.eventType[0] == x.eventType)) and ((o.priority.length() == 0) or (o.priority[0] == x.priority))) and ((o.sourceGroup.length() == 0) or inSourceGroup(x, o.sourceGroup[0])))

  // §4, правило 2. Строка уточнения учитывается, только если все её признаки — из overridesBy таймера (ARCH-11)

  def overrideAllowed(t: TimerDef, o: Override): bool =
    ((((o.eventType.length() == 0) or t.overridesBy.foldl(false, (acc, y39) => acc or y39 == "eventType")) and ((o.priority.length() == 0) or t.overridesBy.foldl(false, (acc, y40) => acc or y40 == "priority"))) and ((o.sourceGroup.length() == 0) or t.overridesBy.foldl(false, (acc, y41) => acc or y41 == "sourceGroup")))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (при равных — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_42 = t.overrides.select(o_43 => (overrideAllowed(t, o_43) and overrideMatches(x, o_43)))  (if ((ms_42.length() > 0)) ms_42.select(o_44 => ms_42.foldl(true, (acc, k_45) => acc and (overrideKeys(k_45) <= overrideKeys(o_44))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold); причины нет или у неё нет срока (maxMinutes: null, RULE-116) — -1, срок не ставится

  def holdSec(x: Incident): int =
    { val rs_46 = settings.holdReasons.select(r_47 => (r_47.id == x.holdReasonId))  (if (((rs_46.length() > 0) and (rs_46[0].maxMinutes.length() > 0))) (rs_46[0].maxMinutes[0] * 60) else (0 - 1)) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_48 = settings.escalation.levels.select(l_49 => (l_49.level == x.escalationLevel))  (if ((ls_48.length() > 0)) ls_48[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_50 = x.timers.get(id)  (if ((t_50.due != 0)) (if (((t_50.due - now) > 0)) (t_50.due - now) else 0) else (if (t_50.paused) t_50.left else (0 - 1))) }

  // RULE-50. Норматив нарушен и отработан: остатка нет, дедлайн сработал

  def spent(x: Incident, id: str, now: int): bool =
    ((leftOf(x, id, now) == 0) and (x.timers.get(id).fired != 0))

  // §11.4, BUG-73, BUG-75. Был в группе основного p в момент at: открытый привязанный, присоединённый не позже, или вышедший не раньше

  def inGroupAt(e: Incident, p: Incident, at: int): bool =
    ((((e.linkedTo == p.id) and not(isDone(e))) and (e.linkedAt <= at)) or (((e.leftGroup.primaryId == p.id) and (e.leftGroup.linkedAt <= at)) and (e.leftGroup.at >= at)))

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_51 => (e_51.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_52 => ((e_52.id != p.id) and inGroupAt(e_52, p, at)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w53 = if (not(timerDef(timerId).pausable)) {
      val sec_54 = timerSec(w0.inc.get(iid), timerId, "")
      val w55 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_54 < 0)) 0 else (c.now + (sec_54 * 1000))) }) }) }
      val w56 = { ...w55, inc: w55.inc.set(iid, { ...w55.inc.get(iid), timers: w55.inc.get(iid).timers.set(timerId, { ...w55.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w56
    } else {
      val w57 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_58 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w59 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_58 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_58)) }) }) }
      val w60 = { ...w59, inc: w59.inc.set(iid, { ...w59.inc.get(iid), timers: w59.inc.get(iid).timers.set(timerId, { ...w59.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w61 = { ...w60, inc: w60.inc.set(iid, { ...w60.inc.get(iid), timers: w60.inc.get(iid).timers.set(timerId, { ...w60.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w61
    } else w0
      w57
    }
    w53
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w62 = if (not(timerDef(timerId).pausable)) {
      val w63 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w64 = { ...w63, inc: w63.inc.set(iid, { ...w63.inc.get(iid), timers: w63.inc.get(iid).timers.set(timerId, { ...w63.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w64
    } else {
      val w65 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w66 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w67 = { ...w66, inc: w66.inc.set(iid, { ...w66.inc.get(iid), timers: w66.inc.get(iid).timers.set(timerId, { ...w66.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w68 = { ...w67, inc: w67.inc.set(iid, { ...w67.inc.get(iid), timers: w67.inc.get(iid).timers.set(timerId, { ...w67.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w68
    } else w0
      w65
    }
    w62
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_69 = ""
    val w70 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_69 }) }
    w70
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_71 = ""
    val w72 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_71 }) }
    w72
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_73 = 0
    val w74 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_73 }) }
    w74
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w75 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w76 = if (timerDef("reaction").startsOnce) {
      val w77 = ec_resumeTimer(w0, c, iid, "reaction")
      w77
    } else {
      val sec_78 = timerSec(w0.inc.get(iid), "reaction", "")
      val w79 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_78 < 0)) 0 else (c.now + (sec_78 * 1000))) }) }) }
      val w80 = { ...w79, inc: w79.inc.set(iid, { ...w79.inc.get(iid), timers: w79.inc.get(iid).timers.set("reaction", { ...w79.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w80
    }
      w76
    }
    w75
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
    not(settings.session.states.foldl(false, (acc, s_81) => acc or ((s_81.id == agentState(c.me)) and s_81.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_82 = c.actor
    val w83 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_82 }) }
    w83
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w84 = if (timerDef("reaction").startsOnce) {
      val w85 = ec_pauseTimer(w0, c, iid, "reaction")
      w85
    } else {
      val w86 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w87 = { ...w86, inc: w86.inc.set(iid, { ...w86.inc.get(iid), timers: w86.inc.get(iid).timers.set("reaction", { ...w86.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w87
    }
    w84
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w88 = if (not(timerDef("resolution").pausable)) {
      val sec_89 = timerSec(w0.inc.get(iid), "resolution", "")
      val w90 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_89 < 0)) 0 else (c.now + (sec_89 * 1000))) }) }) }
      val w91 = { ...w90, inc: w90.inc.set(iid, { ...w90.inc.get(iid), timers: w90.inc.get(iid).timers.set("resolution", { ...w90.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w91
    } else {
      val w92 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_93 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w94 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_93 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_93)) }) }) }
      val w95 = { ...w94, inc: w94.inc.set(iid, { ...w94.inc.get(iid), timers: w94.inc.get(iid).timers.set("resolution", { ...w94.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w96 = { ...w95, inc: w95.inc.set(iid, { ...w95.inc.get(iid), timers: w95.inc.get(iid).timers.set("resolution", { ...w95.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w96
    } else w0
      w92
    }
    w88
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
    not(settings.session.states.foldl(false, (acc, s_97) => acc or ((s_97.id == agentState(c.me)) and s_97.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_98 = c.actor
    val w99 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_98 }) }
    w99
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_100 = ""
    val w101 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_100 }) }
    w101
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w102 = if (timerDef("reaction").startsOnce) {
      val w103 = ec_pauseTimer(w0, c, iid, "reaction")
      w103
    } else {
      val w104 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w105 = { ...w104, inc: w104.inc.set(iid, { ...w104.inc.get(iid), timers: w104.inc.get(iid).timers.set("reaction", { ...w104.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w105
    }
    w102
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w106 = if (not(timerDef("resolution").pausable)) {
      val sec_107 = timerSec(w0.inc.get(iid), "resolution", "")
      val w108 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_107 < 0)) 0 else (c.now + (sec_107 * 1000))) }) }) }
      val w109 = { ...w108, inc: w108.inc.set(iid, { ...w108.inc.get(iid), timers: w108.inc.get(iid).timers.set("resolution", { ...w108.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w109
    } else {
      val w110 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_111 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w112 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_111 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_111)) }) }) }
      val w113 = { ...w112, inc: w112.inc.set(iid, { ...w112.inc.get(iid), timers: w112.inc.get(iid).timers.set("resolution", { ...w112.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w114 = { ...w113, inc: w113.inc.set(iid, { ...w113.inc.get(iid), timers: w113.inc.get(iid).timers.set("resolution", { ...w113.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w114
    } else w0
      w110
    }
    w106
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
    not(settings.session.states.foldl(false, (acc, s_115) => acc or ((s_115.id == agentState(c.me)) and s_115.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_116 = ""
    val w117 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_116 }) }
    w117
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_118 = ""
    val w119 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_118 }) }
    w119
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
    not(settings.session.states.foldl(false, (acc, s_120) => acc or ((s_120.id == agentState(c.me)) and s_120.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_121 = c.form.reasonId
    val w122 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_121 }) }
    w122
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w123 = if (not(timerDef("resolution").pausable)) {
      val w124 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w125 = { ...w124, inc: w124.inc.set(iid, { ...w124.inc.get(iid), timers: w124.inc.get(iid).timers.set("resolution", { ...w124.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w125
    } else {
      val w126 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w127 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w128 = { ...w127, inc: w127.inc.set(iid, { ...w127.inc.get(iid), timers: w127.inc.get(iid).timers.set("resolution", { ...w127.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w129 = { ...w128, inc: w128.inc.set(iid, { ...w128.inc.get(iid), timers: w128.inc.get(iid).timers.set("resolution", { ...w128.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w129
    } else w0
      w126
    }
    w123
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w130 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w131 = if (timerDef("hold").startsOnce) {
      val w132 = ec_resumeTimer(w0, c, iid, "hold")
      w132
    } else {
      val sec_133 = timerSec(w0.inc.get(iid), "hold", "")
      val w134 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_133 < 0)) 0 else (c.now + (sec_133 * 1000))) }) }) }
      val w135 = { ...w134, inc: w134.inc.set(iid, { ...w134.inc.get(iid), timers: w134.inc.get(iid).timers.set("hold", { ...w134.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w135
    }
      w131
    }
    w130
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
    not(settings.session.states.foldl(false, (acc, s_136) => acc or ((s_136.id == agentState(c.me)) and s_136.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w137 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w137
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w138 = if (timerDef("hold").startsOnce) {
      val w139 = ec_pauseTimer(w0, c, iid, "hold")
      w139
    } else {
      val w140 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w141 = { ...w140, inc: w140.inc.set(iid, { ...w140.inc.get(iid), timers: w140.inc.get(iid).timers.set("hold", { ...w140.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w141
    }
    w138
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w142 = if (not(timerDef("resolution").pausable)) {
      val sec_143 = timerSec(w0.inc.get(iid), "resolution", "")
      val w144 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_143 < 0)) 0 else (c.now + (sec_143 * 1000))) }) }) }
      val w145 = { ...w144, inc: w144.inc.set(iid, { ...w144.inc.get(iid), timers: w144.inc.get(iid).timers.set("resolution", { ...w144.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w145
    } else {
      val w146 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_147 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w148 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_147 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_147)) }) }) }
      val w149 = { ...w148, inc: w148.inc.set(iid, { ...w148.inc.get(iid), timers: w148.inc.get(iid).timers.set("resolution", { ...w148.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w150 = { ...w149, inc: w149.inc.set(iid, { ...w149.inc.get(iid), timers: w149.inc.get(iid).timers.set("resolution", { ...w149.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w150
    } else w0
      w146
    }
    w142
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
    not(settings.session.states.foldl(false, (acc, s_151) => acc or ((s_151.id == agentState(c.me)) and s_151.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_152 = ""
    val w153 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_152 }) }
    w153
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w154 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w154
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w155 = if (not(timerDef("resolution").pausable)) {
      val w156 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w157 = { ...w156, inc: w156.inc.set(iid, { ...w156.inc.get(iid), timers: w156.inc.get(iid).timers.set("resolution", { ...w156.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w157
    } else {
      val w158 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w159 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w160 = { ...w159, inc: w159.inc.set(iid, { ...w159.inc.get(iid), timers: w159.inc.get(iid).timers.set("resolution", { ...w159.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w161 = { ...w160, inc: w160.inc.set(iid, { ...w160.inc.get(iid), timers: w160.inc.get(iid).timers.set("resolution", { ...w160.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w161
    } else w0
      w158
    }
    w155
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w162 = if (timerDef("hold").startsOnce) {
      val w163 = ec_pauseTimer(w0, c, iid, "hold")
      w163
    } else {
      val w164 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w165 = { ...w164, inc: w164.inc.set(iid, { ...w164.inc.get(iid), timers: w164.inc.get(iid).timers.set("hold", { ...w164.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w165
    }
    w162
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w166 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w167 = if (timerDef("reaction").startsOnce) {
      val w168 = ec_resumeTimer(w0, c, iid, "reaction")
      w168
    } else {
      val sec_169 = timerSec(w0.inc.get(iid), "reaction", "")
      val w170 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_169 < 0)) 0 else (c.now + (sec_169 * 1000))) }) }) }
      val w171 = { ...w170, inc: w170.inc.set(iid, { ...w170.inc.get(iid), timers: w170.inc.get(iid).timers.set("reaction", { ...w170.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w171
    }
      w167
    }
    w166
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
    not(settings.session.states.foldl(false, (acc, s_172) => acc or ((s_172.id == agentState(c.me)) and s_172.readOnly))),
    transferTargets.foldl(false, (acc, t_173) => acc or (((not(isSelf(c.me, t_173)) and (t_173 != addressee(world.inc.get(iid)))) and canAccept(t_173, world.inc.get(iid), "")) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_174) => acc and (isDone(e_174) or hasAccess(t_173, e_174))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_175) => acc and (isDone(e_175) or hasAccess(c.form.targetId, e_175)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_176 = personOf(c.form.targetId)
    val w177 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_176 }) }
    w177
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_178 = groupOf(c.form.targetId)
    val w179 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_178 }) }
    w179
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w180 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w180
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w181 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w181
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w182 = if (not(timerDef("resolution").pausable)) {
      val w183 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w184 = { ...w183, inc: w183.inc.set(iid, { ...w183.inc.get(iid), timers: w183.inc.get(iid).timers.set("resolution", { ...w183.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w184
    } else {
      val w185 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w186 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w187 = { ...w186, inc: w186.inc.set(iid, { ...w186.inc.get(iid), timers: w186.inc.get(iid).timers.set("resolution", { ...w186.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w188 = { ...w187, inc: w187.inc.set(iid, { ...w187.inc.get(iid), timers: w187.inc.get(iid).timers.set("resolution", { ...w187.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w188
    } else w0
      w185
    }
    w182
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w189 = if (timerDef("hold").startsOnce) {
      val w190 = ec_pauseTimer(w0, c, iid, "hold")
      w190
    } else {
      val w191 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w192 = { ...w191, inc: w191.inc.set(iid, { ...w191.inc.get(iid), timers: w191.inc.get(iid).timers.set("hold", { ...w191.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w192
    }
    w189
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w193 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w194 = if (timerDef("reaction").startsOnce) {
      val w195 = ec_resumeTimer(w0, c, iid, "reaction")
      w195
    } else {
      val sec_196 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w197 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_196 < 0)) 0 else (c.now + (sec_196 * 1000))) }) }) }
      val w198 = { ...w197, inc: w197.inc.set(iid, { ...w197.inc.get(iid), timers: w197.inc.get(iid).timers.set("reaction", { ...w197.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w198
    }
      w194
    }
    w193
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_199 = c.before.owner
    val w200 = if (((whom_199 != "") and (whom_199 != c.actor))) w0 else w0
    w200
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_201 = addressee(w0.inc.get(iid))
    val w202 = if (((whom_201 != "") and (whom_201 != c.actor))) w0 else w0
    w202
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
    not(settings.session.states.foldl(false, (acc, s_203) => acc or ((s_203.id == agentState(c.me)) and s_203.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_204 = c.actor
    val w205 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_204 }) }
    w205
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_206 = ""
    val w207 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_206 }) }
    w207
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w208 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w208
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w209 = if (timerDef("reaction").startsOnce) {
      val w210 = ec_pauseTimer(w0, c, iid, "reaction")
      w210
    } else {
      val w211 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w212 = { ...w211, inc: w211.inc.set(iid, { ...w211.inc.get(iid), timers: w211.inc.get(iid).timers.set("reaction", { ...w211.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w212
    }
    w209
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w213 = if (timerDef("hold").startsOnce) {
      val w214 = ec_pauseTimer(w0, c, iid, "hold")
      w214
    } else {
      val w215 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w216 = { ...w215, inc: w215.inc.set(iid, { ...w215.inc.get(iid), timers: w215.inc.get(iid).timers.set("hold", { ...w215.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w216
    }
    w213
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w217 = if (not(timerDef("resolution").pausable)) {
      val sec_218 = timerSec(w0.inc.get(iid), "resolution", "")
      val w219 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_218 < 0)) 0 else (c.now + (sec_218 * 1000))) }) }) }
      val w220 = { ...w219, inc: w219.inc.set(iid, { ...w219.inc.get(iid), timers: w219.inc.get(iid).timers.set("resolution", { ...w219.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w220
    } else {
      val w221 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_222 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w223 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_222 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_222)) }) }) }
      val w224 = { ...w223, inc: w223.inc.set(iid, { ...w223.inc.get(iid), timers: w223.inc.get(iid).timers.set("resolution", { ...w223.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w225 = { ...w224, inc: w224.inc.set(iid, { ...w224.inc.get(iid), timers: w224.inc.get(iid).timers.set("resolution", { ...w224.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w225
    } else w0
      w221
    }
    w217
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
    val whom_226 = c.before.owner
    val w227 = if (((whom_226 != "") and (whom_226 != c.actor))) w0 else w0
    w227
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
    not(settings.session.states.foldl(false, (acc, s_228) => acc or ((s_228.id == agentState(c.me)) and s_228.readOnly))),
    { val os_229 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_229.foldl(false, (acc, o_230) => acc or ((o_230.id == c.form.resultId) and stepsOk(o_230, world.inc.get(iid)))) else os_229.foldl(false, (acc, o_231) => acc or stepsOk(o_231, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_232 = c.actor
    val w233 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_232 }) }
    w233
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_234 = ""
    val w235 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_234 }) }
    w235
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_236 = c.actor
    val w237 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_236 }) }
    w237
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_238 = c.now
    val w239 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_238 }) }
    w239
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_240 = c.form.resultId
    val w241 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_240 }) }
    w241
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_242 = c.form.causeId
    val w243 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_242 }) }
    w243
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_244 = c.form.comment
    val w245 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_244 }) }
    w245
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w246 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w246
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w247 = if (timerDef("reaction").startsOnce) {
      val w248 = ec_pauseTimer(w0, c, iid, "reaction")
      w248
    } else {
      val w249 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w250 = { ...w249, inc: w249.inc.set(iid, { ...w249.inc.get(iid), timers: w249.inc.get(iid).timers.set("reaction", { ...w249.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w250
    }
    w247
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w251 = if (not(timerDef("resolution").pausable)) {
      val w252 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w253 = { ...w252, inc: w252.inc.set(iid, { ...w252.inc.get(iid), timers: w252.inc.get(iid).timers.set("resolution", { ...w252.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w253
    } else {
      val w254 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w255 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w256 = { ...w255, inc: w255.inc.set(iid, { ...w255.inc.get(iid), timers: w255.inc.get(iid).timers.set("resolution", { ...w255.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w257 = { ...w256, inc: w256.inc.set(iid, { ...w256.inc.get(iid), timers: w256.inc.get(iid).timers.set("resolution", { ...w256.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w257
    } else w0
      w254
    }
    w251
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w258 = if (timerDef("hold").startsOnce) {
      val w259 = ec_pauseTimer(w0, c, iid, "hold")
      w259
    } else {
      val w260 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w261 = { ...w260, inc: w260.inc.set(iid, { ...w260.inc.get(iid), timers: w260.inc.get(iid).timers.set("hold", { ...w260.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w261
    }
    w258
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
    not(settings.session.states.foldl(false, (acc, s_262) => acc or ((s_262.id == agentState(c.me)) and s_262.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_263 = c.actor
    val w264 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_263 }) }
    w264
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w265 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_266 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w267 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w268 = { ...w267, inc: w267.inc.set(iid, { ...w267.inc.get(iid), linkedTo: "" }) }
      val w269 = { ...w268, inc: w268.inc.set(iid, { ...w268.inc.get(iid), linkedAt: 0 }) }
      val w270 = if (((ps_266.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w269 else w269
      val w271 = if (("workflow.journal.linked_reopened" != "")) {
      val w272 = ps_266.foldl([], (acc, x275) => acc.append(x275.id)).foldl(w270, (wf273, pId274) => wf273)
      w272
    } else w270
      w271
    } else {
      val w276 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w277 = { ...w276, inc: w276.inc.set(iid, { ...w276.inc.get(iid), linkedAt: 0 }) }
      w277
    }
    w265
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_278 = ""
    val w279 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_278 }) }
    w279
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_280 = ""
    val w281 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_280 }) }
    w281
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val sec_282 = settings.limits.reopenResolutionSec
    val w283 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_282 > 0)) sec_282 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w284 = { ...w283, inc: w283.inc.set(iid, { ...w283.inc.get(iid), timers: w283.inc.get(iid).timers.set("resolution", { ...w283.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w285 = { ...w284, inc: w284.inc.set(iid, { ...w284.inc.get(iid), timers: w284.inc.get(iid).timers.set("resolution", { ...w284.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w285
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
    { val t_286 = world.inc.get(iid).timers.get("reaction")  (((t_286.due != 0) and (t_286.due <= c.now)) and (t_286.fired != t_286.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_287 = personOf(levelUpTarget(c.before))
    val w288 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_287 }) }
    w288
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_289 = groupOf(levelUpTarget(c.before))
    val w290 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_289 }) }
    w290
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_291 = levelUpNumber(c.before)
    val w292 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_291 }) }
    w292
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w293 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w293
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w294 = if (not(timerDef("resolution").pausable)) {
      val w295 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("resolution", { ...w295.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w296
    } else {
      val w297 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w298 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w299 = { ...w298, inc: w298.inc.set(iid, { ...w298.inc.get(iid), timers: w298.inc.get(iid).timers.set("resolution", { ...w298.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w300 = { ...w299, inc: w299.inc.set(iid, { ...w299.inc.get(iid), timers: w299.inc.get(iid).timers.set("resolution", { ...w299.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w300
    } else w0
      w297
    }
    w294
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w301 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w302 = if (timerDef("reaction").startsOnce) {
      val w303 = ec_resumeTimer(w0, c, iid, "reaction")
      w303
    } else {
      val sec_304 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w305 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_304 < 0)) 0 else (c.now + (sec_304 * 1000))) }) }) }
      val w306 = { ...w305, inc: w305.inc.set(iid, { ...w305.inc.get(iid), timers: w305.inc.get(iid).timers.set("reaction", { ...w305.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w306
    }
      w302
    }
    w301
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_307 = addressee(w0.inc.get(iid))
    val w308 = if (((whom_307 != "") and (whom_307 != c.actor))) w0 else w0
    w308
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
    { val t_309 = world.inc.get(iid).timers.get("reaction")  (((t_309.due != 0) and (t_309.due <= c.now)) and (t_309.fired != t_309.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_310 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w311 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_310) }) }
    val w312 = { ...w311, inc: w311.inc.set(iid, { ...w311.inc.get(iid), slaBreached: true }) }
    val w313 = groupMembersAt(incs(w0), w312.inc.get(iid), c.deadline).foldl([], (acc, x316) => acc.append(x316.id)).foldl(w312, (wf314, eId315) => {
      val w317 = { ...wf314, inc: wf314.inc.set(eId315, { ...wf314.inc.get(eId315), breaches: wf314.inc.get(eId315).breaches.append(breach_310) }) }
      val w318 = { ...w317, inc: w317.inc.set(eId315, { ...w317.inc.get(eId315), slaBreached: true }) }
      w318
    })
    w313
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w319 = if (timerDef("reaction").startsOnce) {
      val w320 = ec_pauseTimer(w0, c, iid, "reaction")
      w320
    } else {
      val w321 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w322 = { ...w321, inc: w321.inc.set(iid, { ...w321.inc.get(iid), timers: w321.inc.get(iid).timers.set("reaction", { ...w321.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w322
    }
    w319
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_323 = settings.alerts.target
    val w324 = if (((whom_323 != "") and (whom_323 != c.actor))) w0 else w0
    w324
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
    { val t_325 = world.inc.get(iid).timers.get("reaction")  (((t_325.due != 0) and (t_325.due <= c.now)) and (t_325.fired != t_325.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_326 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w327 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_326) }) }
    val w328 = { ...w327, inc: w327.inc.set(iid, { ...w327.inc.get(iid), slaBreached: true }) }
    val w329 = groupMembersAt(incs(w0), w328.inc.get(iid), c.deadline).foldl([], (acc, x332) => acc.append(x332.id)).foldl(w328, (wf330, eId331) => {
      val w333 = { ...wf330, inc: wf330.inc.set(eId331, { ...wf330.inc.get(eId331), breaches: wf330.inc.get(eId331).breaches.append(breach_326) }) }
      val w334 = { ...w333, inc: w333.inc.set(eId331, { ...w333.inc.get(eId331), slaBreached: true }) }
      w334
    })
    w329
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w335 = if (timerDef("reaction").startsOnce) {
      val w336 = ec_pauseTimer(w0, c, iid, "reaction")
      w336
    } else {
      val w337 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w338 = { ...w337, inc: w337.inc.set(iid, { ...w337.inc.get(iid), timers: w337.inc.get(iid).timers.set("reaction", { ...w337.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w338
    }
    w335
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_339 = settings.alerts.target
    val w340 = if (((whom_339 != "") and (whom_339 != c.actor))) w0 else w0
    w340
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
    { val t_341 = world.inc.get(iid).timers.get("resolution")  (((t_341.due != 0) and (t_341.due <= c.now)) and (t_341.fired != t_341.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_342 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w343 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_342) }) }
    val w344 = { ...w343, inc: w343.inc.set(iid, { ...w343.inc.get(iid), slaBreached: true }) }
    val w345 = groupMembersAt(incs(w0), w344.inc.get(iid), c.deadline).foldl([], (acc, x348) => acc.append(x348.id)).foldl(w344, (wf346, eId347) => {
      val w349 = { ...wf346, inc: wf346.inc.set(eId347, { ...wf346.inc.get(eId347), breaches: wf346.inc.get(eId347).breaches.append(breach_342) }) }
      val w350 = { ...w349, inc: w349.inc.set(eId347, { ...w349.inc.get(eId347), slaBreached: true }) }
      w350
    })
    w345
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_351 = settings.alerts.target
    val w352 = if (((whom_351 != "") and (whom_351 != c.actor))) w0 else w0
    w352
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
    { val t_353 = world.inc.get(iid).timers.get("resolution")  (((t_353.due != 0) and (t_353.due <= c.now)) and (t_353.fired != t_353.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_354 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w355 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_354) }) }
    val w356 = { ...w355, inc: w355.inc.set(iid, { ...w355.inc.get(iid), slaBreached: true }) }
    val w357 = groupMembersAt(incs(w0), w356.inc.get(iid), c.deadline).foldl([], (acc, x360) => acc.append(x360.id)).foldl(w356, (wf358, eId359) => {
      val w361 = { ...wf358, inc: wf358.inc.set(eId359, { ...wf358.inc.get(eId359), breaches: wf358.inc.get(eId359).breaches.append(breach_354) }) }
      val w362 = { ...w361, inc: w361.inc.set(eId359, { ...w361.inc.get(eId359), slaBreached: true }) }
      w362
    })
    w357
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_363 = personOf(levelUpTarget(c.before))
    val w364 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_363 }) }
    w364
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_365 = groupOf(levelUpTarget(c.before))
    val w366 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_365 }) }
    w366
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_367 = levelUpNumber(c.before)
    val w368 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_367 }) }
    w368
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w369 = if (not(timerDef("resolution").pausable)) {
      val w370 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w371 = { ...w370, inc: w370.inc.set(iid, { ...w370.inc.get(iid), timers: w370.inc.get(iid).timers.set("resolution", { ...w370.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w371
    } else {
      val w372 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w373 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w374 = { ...w373, inc: w373.inc.set(iid, { ...w373.inc.get(iid), timers: w373.inc.get(iid).timers.set("resolution", { ...w373.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w375 = { ...w374, inc: w374.inc.set(iid, { ...w374.inc.get(iid), timers: w374.inc.get(iid).timers.set("resolution", { ...w374.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w375
    } else w0
      w372
    }
    w369
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w376 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w377 = if (timerDef("reaction").startsOnce) {
      val w378 = ec_resumeTimer(w0, c, iid, "reaction")
      w378
    } else {
      val sec_379 = timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel")
      val w380 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_379 < 0)) 0 else (c.now + (sec_379 * 1000))) }) }) }
      val w381 = { ...w380, inc: w380.inc.set(iid, { ...w380.inc.get(iid), timers: w380.inc.get(iid).timers.set("reaction", { ...w380.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w381
    }
      w377
    }
    w376
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_382 = c.before.owner
    val w383 = if (((whom_382 != "") and (whom_382 != c.actor))) w0 else w0
    w383
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_384 = addressee(w0.inc.get(iid))
    val w385 = if (((whom_384 != "") and (whom_384 != c.actor))) w0 else w0
    w385
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
    { val t_386 = world.inc.get(iid).timers.get("resolution")  (((t_386.due != 0) and (t_386.due <= c.now)) and (t_386.fired != t_386.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_387 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w388 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_387) }) }
    val w389 = { ...w388, inc: w388.inc.set(iid, { ...w388.inc.get(iid), slaBreached: true }) }
    val w390 = groupMembersAt(incs(w0), w389.inc.get(iid), c.deadline).foldl([], (acc, x393) => acc.append(x393.id)).foldl(w389, (wf391, eId392) => {
      val w394 = { ...wf391, inc: wf391.inc.set(eId392, { ...wf391.inc.get(eId392), breaches: wf391.inc.get(eId392).breaches.append(breach_387) }) }
      val w395 = { ...w394, inc: w394.inc.set(eId392, { ...w394.inc.get(eId392), slaBreached: true }) }
      w395
    })
    w390
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_396 = settings.alerts.target
    val w397 = if (((whom_396 != "") and (whom_396 != c.actor))) w0 else w0
    w397
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
    { val t_398 = world.inc.get(iid).timers.get("hold")  (((t_398.due != 0) and (t_398.due <= c.now)) and (t_398.fired != t_398.due)) },
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_399 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w400 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_399) }) }
    val w401 = { ...w400, inc: w400.inc.set(iid, { ...w400.inc.get(iid), slaBreached: true }) }
    val w402 = groupMembersAt(incs(w0), w401.inc.get(iid), c.deadline).foldl([], (acc, x405) => acc.append(x405.id)).foldl(w401, (wf403, eId404) => {
      val w406 = { ...wf403, inc: wf403.inc.set(eId404, { ...wf403.inc.get(eId404), breaches: wf403.inc.get(eId404).breaches.append(breach_399) }) }
      val w407 = { ...w406, inc: w406.inc.set(eId404, { ...w406.inc.get(eId404), slaBreached: true }) }
      w407
    })
    w402
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_408 = settings.alerts.target
    val w409 = if (((whom_408 != "") and (whom_408 != c.actor))) w0 else w0
    w409
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
    val reason_410 = "break"
    val w411 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_410 }) }
    w411
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w412 = if (not(timerDef("resolution").pausable)) {
      val w413 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w414 = { ...w413, inc: w413.inc.set(iid, { ...w413.inc.get(iid), timers: w413.inc.get(iid).timers.set("resolution", { ...w413.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w414
    } else {
      val w415 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w416 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w417 = { ...w416, inc: w416.inc.set(iid, { ...w416.inc.get(iid), timers: w416.inc.get(iid).timers.set("resolution", { ...w416.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w418 = { ...w417, inc: w417.inc.set(iid, { ...w417.inc.get(iid), timers: w417.inc.get(iid).timers.set("resolution", { ...w417.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w418
    } else w0
      w415
    }
    w412
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w419 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w420 = if (timerDef("hold").startsOnce) {
      val w421 = ec_resumeTimer(w0, c, iid, "hold")
      w421
    } else {
      val sec_422 = timerSec(w0.inc.get(iid), "hold", "")
      val w423 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_422 < 0)) 0 else (c.now + (sec_422 * 1000))) }) }) }
      val w424 = { ...w423, inc: w423.inc.set(iid, { ...w423.inc.get(iid), timers: w423.inc.get(iid).timers.set("hold", { ...w423.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w424
    }
      w420
    }
    w419
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
    val reason_425 = "no_link"
    val w426 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_425 }) }
    w426
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w427 = if (not(timerDef("resolution").pausable)) {
      val w428 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w429 = { ...w428, inc: w428.inc.set(iid, { ...w428.inc.get(iid), timers: w428.inc.get(iid).timers.set("resolution", { ...w428.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w429
    } else {
      val w430 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w431 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w432 = { ...w431, inc: w431.inc.set(iid, { ...w431.inc.get(iid), timers: w431.inc.get(iid).timers.set("resolution", { ...w431.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w433 = { ...w432, inc: w432.inc.set(iid, { ...w432.inc.get(iid), timers: w432.inc.get(iid).timers.set("resolution", { ...w432.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w433
    } else w0
      w430
    }
    w427
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w434 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w435 = if (timerDef("hold").startsOnce) {
      val w436 = ec_resumeTimer(w0, c, iid, "hold")
      w436
    } else {
      val sec_437 = timerSec(w0.inc.get(iid), "hold", "")
      val w438 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_437 < 0)) 0 else (c.now + (sec_437 * 1000))) }) }) }
      val w439 = { ...w438, inc: w438.inc.set(iid, { ...w438.inc.get(iid), timers: w438.inc.get(iid).timers.set("hold", { ...w438.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      w439
    }
      w435
    }
    w434
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_440 = settings.alerts.target
    val w441 = if (((whom_440 != "") and (whom_440 != c.actor))) w0 else w0
    w441
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
    ["break", "no_link"].foldl(false, (acc, y442) => acc or y442 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_443 = ""
    val w444 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_443 }) }
    w444
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w445 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w445
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w446 = if (timerDef("hold").startsOnce) {
      val w447 = ec_pauseTimer(w0, c, iid, "hold")
      w447
    } else {
      val w448 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w449 = { ...w448, inc: w448.inc.set(iid, { ...w448.inc.get(iid), timers: w448.inc.get(iid).timers.set("hold", { ...w448.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w449
    }
    w446
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w450 = if (not(timerDef("resolution").pausable)) {
      val w451 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w452 = { ...w451, inc: w451.inc.set(iid, { ...w451.inc.get(iid), timers: w451.inc.get(iid).timers.set("resolution", { ...w451.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w452
    } else {
      val w453 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w454 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w455 = { ...w454, inc: w454.inc.set(iid, { ...w454.inc.get(iid), timers: w454.inc.get(iid).timers.set("resolution", { ...w454.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w456 = { ...w455, inc: w455.inc.set(iid, { ...w455.inc.get(iid), timers: w455.inc.get(iid).timers.set("resolution", { ...w455.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w456
    } else w0
      w453
    }
    w450
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w457 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w458 = if (timerDef("reaction").startsOnce) {
      val w459 = ec_resumeTimer(w0, c, iid, "reaction")
      w459
    } else {
      val sec_460 = timerSec(w0.inc.get(iid), "reaction", "")
      val w461 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_460 < 0)) 0 else (c.now + (sec_460 * 1000))) }) }) }
      val w462 = { ...w461, inc: w461.inc.set(iid, { ...w461.inc.get(iid), timers: w461.inc.get(iid).timers.set("reaction", { ...w461.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w462
    }
      w458
    }
    w457
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
    val group_463 = dutyGroupOf(w0.inc.get(iid).owner)
    val w464 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_463 }) }
    w464
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_465 = ""
    val w466 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_465 }) }
    w466
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_467 = addressee(w0.inc.get(iid))
    val w468 = if (((whom_467 != "") and (whom_467 != c.actor))) w0 else w0
    w468
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
    val who_469 = ""
    val w470 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_469 }) }
    w470
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
    val who_471 = ""
    val w472 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_471 }) }
    w472
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w473 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w473
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w474 = if (timerDef("hold").startsOnce) {
      val w475 = ec_pauseTimer(w0, c, iid, "hold")
      w475
    } else {
      val w476 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w477 = { ...w476, inc: w476.inc.set(iid, { ...w476.inc.get(iid), timers: w476.inc.get(iid).timers.set("hold", { ...w476.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w477
    }
    w474
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w478 = if (not(timerDef("resolution").pausable)) {
      val w479 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w480 = { ...w479, inc: w479.inc.set(iid, { ...w479.inc.get(iid), timers: w479.inc.get(iid).timers.set("resolution", { ...w479.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w480
    } else {
      val w481 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w482 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w483 = { ...w482, inc: w482.inc.set(iid, { ...w482.inc.get(iid), timers: w482.inc.get(iid).timers.set("resolution", { ...w482.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w484 = { ...w483, inc: w483.inc.set(iid, { ...w483.inc.get(iid), timers: w483.inc.get(iid).timers.set("resolution", { ...w483.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w484
    } else w0
      w481
    }
    w478
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
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
    val who_491 = ""
    val w492 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_491 }) }
    w492
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_493 = ""
    val w494 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_493 }) }
    w494
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w495 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w495
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w496 = if (timerDef("hold").startsOnce) {
      val w497 = ec_pauseTimer(w0, c, iid, "hold")
      w497
    } else {
      val w498 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w499 = { ...w498, inc: w498.inc.set(iid, { ...w498.inc.get(iid), timers: w498.inc.get(iid).timers.set("hold", { ...w498.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w499
    }
    w496
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w500 = if (not(timerDef("resolution").pausable)) {
      val w501 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w502 = { ...w501, inc: w501.inc.set(iid, { ...w501.inc.get(iid), timers: w501.inc.get(iid).timers.set("resolution", { ...w501.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w502
    } else {
      val w503 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w504 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w505 = { ...w504, inc: w504.inc.set(iid, { ...w504.inc.get(iid), timers: w504.inc.get(iid).timers.set("resolution", { ...w504.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w506 = { ...w505, inc: w505.inc.set(iid, { ...w505.inc.get(iid), timers: w505.inc.get(iid).timers.set("resolution", { ...w505.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w506
    } else w0
      w503
    }
    w500
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w507 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w508 = if (timerDef("reaction").startsOnce) {
      val w509 = ec_resumeTimer(w0, c, iid, "reaction")
      w509
    } else {
      val sec_510 = timerSec(w0.inc.get(iid), "reaction", "")
      val w511 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_510 < 0)) 0 else (c.now + (sec_510 * 1000))) }) }) }
      val w512 = { ...w511, inc: w511.inc.set(iid, { ...w511.inc.get(iid), timers: w511.inc.get(iid).timers.set("reaction", { ...w511.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w512
    }
      w508
    }
    w507
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_513 = settings.alerts.target
    val w514 = if (((whom_513 != "") and (whom_513 != c.actor))) w0 else w0
    w514
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
    val who_515 = ""
    val w516 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_515 }) }
    w516
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_517 = ""
    val w518 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_517 }) }
    w518
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w519 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w520 = if (timerDef("reaction").startsOnce) {
      val w521 = ec_resumeTimer(w0, c, iid, "reaction")
      w521
    } else {
      val sec_522 = timerSec(w0.inc.get(iid), "reaction", "")
      val w523 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_522 < 0)) 0 else (c.now + (sec_522 * 1000))) }) }) }
      val w524 = { ...w523, inc: w523.inc.set(iid, { ...w523.inc.get(iid), timers: w523.inc.get(iid).timers.set("reaction", { ...w523.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w524
    }
      w520
    }
    w519
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_525 = settings.alerts.target
    val w526 = if (((whom_525 != "") and (whom_525 != c.actor))) w0 else w0
    w526
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
    not(settings.session.states.foldl(false, (acc, s_527) => acc or ((s_527.id == agentState(c.me)) and s_527.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_528 = incidentById(incs(world), c.form.primaryId)  ((((ps_528.length() > 0) and (ps_528[0].id != world.inc.get(iid).id)) and (ps_528[0].linkedTo == "")) and ((ps_528[0].state == "new") or ((ps_528[0].state == "in_progress") and (ps_528[0].owner == c.me)))) },
    { val ps_529 = incidentById(incs(world), c.form.primaryId)  ((ps_529.length() > 0) and (ps_529[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w530 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w530
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_531 = incidentById(incs(w0), c.form.primaryId)
    val w532 = if ((ps_531.length() > 0)) {
      val w533 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_540 => not(isDone(e_540))).foldl([], (acc, x536) => acc.append(x536.id)).foldl(w0, (wf534, cId535) => {
      val w537 = { ...wf534, inc: wf534.inc.set(cId535, { ...wf534.inc.get(cId535), leftGroup: { primaryId: wf534.inc.get(cId535).linkedTo, linkedAt: wf534.inc.get(cId535).linkedAt, at: c.now } }) }
      val w538 = { ...w537, inc: w537.inc.set(cId535, { ...w537.inc.get(cId535), linkedTo: ps_531[0].id }) }
      val w539 = { ...w538, inc: w538.inc.set(cId535, { ...w538.inc.get(cId535), linkedAt: c.now }) }
      w539
    })
      w533
    } else w0
    w532
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_541 = c.form.primaryId
    val w542 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_541 }) }
    val w543 = { ...w542, inc: w542.inc.set(iid, { ...w542.inc.get(iid), linkedAt: c.now }) }
    w543
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_544 = ""
    val w545 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_544 }) }
    w545
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_546 = ""
    val w547 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_546 }) }
    w547
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w548 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w548
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w549 = if (timerDef("reaction").startsOnce) {
      val w550 = ec_pauseTimer(w0, c, iid, "reaction")
      w550
    } else {
      val w551 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w552 = { ...w551, inc: w551.inc.set(iid, { ...w551.inc.get(iid), timers: w551.inc.get(iid).timers.set("reaction", { ...w551.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w552
    }
    w549
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w553 = if (not(timerDef("resolution").pausable)) {
      val w554 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w555 = { ...w554, inc: w554.inc.set(iid, { ...w554.inc.get(iid), timers: w554.inc.get(iid).timers.set("resolution", { ...w554.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w555
    } else {
      val w556 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w557 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w558 = { ...w557, inc: w557.inc.set(iid, { ...w557.inc.get(iid), timers: w557.inc.get(iid).timers.set("resolution", { ...w557.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w559 = { ...w558, inc: w558.inc.set(iid, { ...w558.inc.get(iid), timers: w558.inc.get(iid).timers.set("resolution", { ...w558.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w559
    } else w0
      w556
    }
    w553
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_560 = incidentById(incs(w0), c.form.primaryId)
    val w561 = if (((((ps_560.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_560[0], "resolution", c.now)))) {
      val t_562 = ps_560[0].timers.get("resolution")
      val left_563 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_564 = (if ((t_562.due != 0)) (t_562.due - c.now) else (if (t_562.paused) t_562.left else (timerSec(ps_560[0], "resolution", "") * 1000)))
      val w565 = if ((left_563 < was_564)) {
      val w566 = ps_560.foldl([], (acc, x569) => acc.append(x569.id)).foldl(w0, (wf567, pId568) => {
      val w570 = if ((t_562.due != 0)) {
      val w571 = { ...wf567, inc: wf567.inc.set(pId568, { ...wf567.inc.get(pId568), timers: wf567.inc.get(pId568).timers.set("resolution", { ...wf567.inc.get(pId568).timers.get("resolution"), due: (c.now + left_563) }) }) }
      w571
    } else {
      val w572 = { ...wf567, inc: wf567.inc.set(pId568, { ...wf567.inc.get(pId568), timers: wf567.inc.get(pId568).timers.set("resolution", { ...wf567.inc.get(pId568).timers.get("resolution"), left: left_563 }) }) }
      val w573 = { ...w572, inc: w572.inc.set(pId568, { ...w572.inc.get(pId568), timers: w572.inc.get(pId568).timers.set("resolution", { ...w572.inc.get(pId568).timers.get("resolution"), paused: true }) }) }
      w573
    }
      w570
    })
      w566
    } else w0
      w565
    } else w0
    w561
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w574 = if (timerDef("hold").startsOnce) {
      val w575 = ec_pauseTimer(w0, c, iid, "hold")
      w575
    } else {
      val w576 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w577 = { ...w576, inc: w576.inc.set(iid, { ...w576.inc.get(iid), timers: w576.inc.get(iid).timers.set("hold", { ...w576.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w577
    }
    w574
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
    not(settings.session.states.foldl(false, (acc, s_578) => acc or ((s_578.id == agentState(c.me)) and s_578.readOnly))),
    { val ps_579 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_579.length() > 0) and ((ownership(c.me, ps_579[0]) == "owner") or unowned(ps_579[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_580 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w581 = if (((ps_580.length() > 0) and (leftOf(ps_580[0], "resolution", c.now) >= 0))) {
      val w582 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w583 = { ...w582, inc: w582.inc.set(iid, { ...w582.inc.get(iid), timers: w582.inc.get(iid).timers.set("resolution", { ...w582.inc.get(iid).timers.get("resolution"), left: leftOf(ps_580[0], "resolution", c.now) }) }) }
      val w584 = { ...w583, inc: w583.inc.set(iid, { ...w583.inc.get(iid), timers: w583.inc.get(iid).timers.set("resolution", { ...w583.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w585 = if ((leftOf(ps_580[0], "resolution", c.now) == 0)) {
      val w586 = { ...w584, inc: w584.inc.set(iid, { ...w584.inc.get(iid), timers: w584.inc.get(iid).timers.set("resolution", { ...w584.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_580[0], "resolution", c.now)) ps_580[0].timers.get("resolution").fired else ps_580[0].timers.get("resolution").due) }) }) }
      w586
    } else w584
      w585
    } else w0
    w581
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w587 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_588 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w589 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w590 = { ...w589, inc: w589.inc.set(iid, { ...w589.inc.get(iid), linkedTo: "" }) }
      val w591 = { ...w590, inc: w590.inc.set(iid, { ...w590.inc.get(iid), linkedAt: 0 }) }
      val w592 = if (((ps_588.length() > 0) and ("" != ""))) w591 else w591
      val w593 = if (("" != "")) {
      val w594 = ps_588.foldl([], (acc, x597) => acc.append(x597.id)).foldl(w592, (wf595, pId596) => wf595)
      w594
    } else w592
      w593
    } else {
      val w598 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w599 = { ...w598, inc: w598.inc.set(iid, { ...w598.inc.get(iid), linkedAt: 0 }) }
      w599
    }
    w587
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w600 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w601 = if (timerDef("reaction").startsOnce) {
      val w602 = ec_resumeTimer(w0, c, iid, "reaction")
      w602
    } else {
      val sec_603 = timerSec(w0.inc.get(iid), "reaction", "")
      val w604 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_603 < 0)) 0 else (c.now + (sec_603 * 1000))) }) }) }
      val w605 = { ...w604, inc: w604.inc.set(iid, { ...w604.inc.get(iid), timers: w604.inc.get(iid).timers.set("reaction", { ...w604.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w605
    }
      w601
    }
    w600
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
    { val ps_606 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_606.length() > 0) and isDone(ps_606[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_607 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w608 = if ((ps_607.length() > 0)) {
      val w609 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_607[0].closeResultId }) }
      val w610 = { ...w609, inc: w609.inc.set(iid, { ...w609.inc.get(iid), closeCauseId: ps_607[0].closeCauseId }) }
      val w611 = { ...w610, inc: w610.inc.set(iid, { ...w610.inc.get(iid), result: ps_607[0].result }) }
      val w612 = { ...w611, inc: w611.inc.set(iid, { ...w611.inc.get(iid), closedBy: ps_607[0].closedBy }) }
      val w613 = { ...w612, inc: w612.inc.set(iid, { ...w612.inc.get(iid), owner: ps_607[0].closedBy }) }
      w613
    } else w0
    w608
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w614 = if (not(timerDef("resolution").pausable)) {
      val w615 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w616 = { ...w615, inc: w615.inc.set(iid, { ...w615.inc.get(iid), timers: w615.inc.get(iid).timers.set("resolution", { ...w615.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w616
    } else {
      val w617 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w618 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w619 = { ...w618, inc: w618.inc.set(iid, { ...w618.inc.get(iid), timers: w618.inc.get(iid).timers.set("resolution", { ...w618.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w620 = { ...w619, inc: w619.inc.set(iid, { ...w619.inc.get(iid), timers: w619.inc.get(iid).timers.set("resolution", { ...w619.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w620
    } else w0
      w617
    }
    w614
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_621 = c.now
    val w622 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_621 }) }
    w622
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
    { val ps_623 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_624 = (if (((ps_623.length() > 0) and not(isDone(ps_623[0])))) addressee(ps_623[0]) else "")  ((who_624 != "") and (hasAccess(who_624, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_625 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w626 = if (((ps_625.length() > 0) and (leftOf(ps_625[0], "resolution", c.now) >= 0))) {
      val w627 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w628 = { ...w627, inc: w627.inc.set(iid, { ...w627.inc.get(iid), timers: w627.inc.get(iid).timers.set("resolution", { ...w627.inc.get(iid).timers.get("resolution"), left: leftOf(ps_625[0], "resolution", c.now) }) }) }
      val w629 = { ...w628, inc: w628.inc.set(iid, { ...w628.inc.get(iid), timers: w628.inc.get(iid).timers.set("resolution", { ...w628.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w630 = if ((leftOf(ps_625[0], "resolution", c.now) == 0)) {
      val w631 = { ...w629, inc: w629.inc.set(iid, { ...w629.inc.get(iid), timers: w629.inc.get(iid).timers.set("resolution", { ...w629.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_625[0], "resolution", c.now)) ps_625[0].timers.get("resolution").fired else ps_625[0].timers.get("resolution").due) }) }) }
      w631
    } else w629
      w630
    } else w0
    w626
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w632 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_633 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w634 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w635 = { ...w634, inc: w634.inc.set(iid, { ...w634.inc.get(iid), linkedTo: "" }) }
      val w636 = { ...w635, inc: w635.inc.set(iid, { ...w635.inc.get(iid), linkedAt: 0 }) }
      val w637 = if (((ps_633.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w636 else w636
      val w638 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w639 = ps_633.foldl([], (acc, x642) => acc.append(x642.id)).foldl(w637, (wf640, pId641) => wf640)
      w639
    } else w637
      w638
    } else {
      val w643 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w644 = { ...w643, inc: w643.inc.set(iid, { ...w643.inc.get(iid), linkedAt: 0 }) }
      w644
    }
    w632
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w645 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w646 = if (timerDef("reaction").startsOnce) {
      val w647 = ec_resumeTimer(w0, c, iid, "reaction")
      w647
    } else {
      val sec_648 = timerSec(w0.inc.get(iid), "reaction", "")
      val w649 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_648 < 0)) 0 else (c.now + (sec_648 * 1000))) }) }) }
      val w650 = { ...w649, inc: w649.inc.set(iid, { ...w649.inc.get(iid), timers: w649.inc.get(iid).timers.set("reaction", { ...w649.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      w650
    }
      w646
    }
    w645
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_651 = settings.alerts.target
    val w652 = if (((whom_651 != "") and (whom_651 != c.actor))) w0 else w0
    w652
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
      settings.holdReasons.foldl(false, (acc, r_653) => acc or ((r_653.id == c.form.reasonId) and (r_653.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      ((not(isSelf(c.me, c.form.targetId)) and (c.form.targetId != addressee(world.inc.get(iid)))) and canAccept(c.form.targetId, world.inc.get(iid), "")),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_654) => acc and (isDone(e_654) or hasAccess(c.form.targetId, e_654))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_655) => acc or (i_655.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_656) => acc or ((i_656.id == c.form.resultId) and stepsOk(i_656, world.inc.get(iid)))),
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
    ["in_progress"].foldl(false, (acc, y657) => acc or y657 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_658) => acc or ((s_658.id == agentState(c.me)) and s_658.readOnly))),
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
  // Кому вообще можно передавать: люди и дежурная группа (§8.1, BUG-85)
  def transferTargets: List[str] = OPERATOR_LIST.concat([GROUP])
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
      // Срок удержания идёт, только если он у причины есть: у «нет связи» его нет (RULE-116)
      else if (s == "on_hold") (runs(h) iff holdSec(x) >= 0) and not(runs(z)) and z.paused and not(runs(r))
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
  def countOwned(a: str, s: str): int = INCIDENTS.filter(j => incOf(j).state == s and incOf(j).owner == a).size()
  def countManualHeld(a: str): int =
    INCIDENTS.filter(j => incOf(j).state == "on_hold" and incOf(j).owner == a and HOLD_REASONS_BY_OPERATOR.contains(incOf(j).holdReasonId)).size()
  val limitsRespected = OPERATORS.forall(a => all {
    settings.limits.maxActive == 0 or countOwned(a, "in_progress") <= settings.limits.maxActive,
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
