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
  // (tools/check_quint_replay.mjs). others — набор объединения, prio, scenario и event — у появления
  type Action = { name: str, actor: str, incident: str, kind: str, form: Form, surface: str, others: List[str], prio: int, scenario: str, event: str }

  /* ===== Типы машины (cel.types) ===== */


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str, eventGuid: str }

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

  type TimerDef = { id: str, labelKey: str, defaultSec: int, byPriority: int -> int, overridesBy: List[str], overrides: List[Override], keepsLeft: bool, startsOnce: bool, pausable: bool, secFrom: str }

  type Override = { eventType: List[str], priority: List[int], sourceGroup: List[str], sec: int }

  type HoldReason = { id: str, maxMinutes: List[int], setBy: str, deadlineFromIdle: bool }

  type Event = { guid: str, eventType: str, device: str, deviceType: str }

  type Condition = { eventType: List[str], device: List[str], deviceType: List[str], group: List[str] }

  type Rule = { guid: str, priority: int, createdAt: int, scenarios: List[str], conditions: List[Condition] }

  type Settings = { limits: Limits, session: Session, escalation: Escalation, alerts: Alerts, states: List[State], closeResults: List[CloseResultItem], timerDefs: List[TimerDef], holdReasons: List[HoldReason] }


  /* ===== Настройки — значения машины (cel.settings) ===== */


  pure val MACHINE_SETTINGS: Settings = {
    limits: { maxActive: 0, maxOnHold: 5, maxBulk: 0, reopenWindowMin: 1440, reopenResolutionSec: 0 },
    session: { states: [{ id: "ready", readOnly: false, readOnlyReasonKey: "" }, { id: "busy", readOnly: false, readOnlyReasonKey: "" }, { id: "not_ready", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.not_ready" }, { id: "offline", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.offline" }], heartbeatSec: 30, idleHoldSec: 300, idleReleaseSec: 1200 },
    escalation: { enabled: true, levels: [{ level: 1, targetKind: "user", target: "petrova", reactionSec: 120 }, { level: 2, targetKind: "user", target: "noc", reactionSec: 90 }], maxLevel: 2, onResolutionOverdue: "alert" },
    alerts: { targetKind: "group", target: "grp-leads", noRecipientLog: "workflow.journal.alert_no_recipient" },
    states: [{ id: "new", category: "pending" }, { id: "pending_acceptance", category: "pending" }, { id: "in_progress", category: "active" }, { id: "on_hold", category: "active" }, { id: "closed", category: "done" }, { id: "linked", category: "linked" }],
    closeResults: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "closing", commentRequired: false, finish: true }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", permission: "incident:close:unprocessed", fromStates: ["new", "pending_acceptance", "in_progress", "on_hold"], ownerOnlyInStates: ["in_progress", "on_hold"], surfaces: ["queue", "card"], requiredStepSet: "none", commentRequired: true, finish: false }],
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overridesBy: ["eventType", "priority", "sourceGroup"], overrides: [{ eventType: [], priority: [100], sourceGroup: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], sec: 1800 }], keepsLeft: true, startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overridesBy: ["eventType", "priority", "sourceGroup"], overrides: [], keepsLeft: false, startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overridesBy: [], overrides: [], keepsLeft: false, startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
    holdReasons: [{ id: "third_party", maxMinutes: [30], setBy: "operator", deadlineFromIdle: false }, { id: "patrol", maxMinutes: [45], setBy: "operator", deadlineFromIdle: false }, { id: "no_data", maxMinutes: [60], setBy: "operator", deadlineFromIdle: false }, { id: "break", maxMinutes: [30], setBy: "system", deadlineFromIdle: false }, { id: "no_link", maxMinutes: [], setBy: "system", deadlineFromIdle: true }],
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

  pure val TYPICAL_PERMISSION_SETS: Set[Set[str]] = Set(Set("incident:claim", "incident:accept", "incident:hold", "incident:release", "incident:close", "incident:transfer:own", "incident:bulk", "incident:run_action", "agent:set_not_ready"), Set("incident:claim", "incident:accept", "incident:hold", "incident:release", "incident:close", "incident:close:unprocessed", "incident:reopen", "incident:transfer:own", "incident:transfer:any", "incident:reassign", "incident:bulk", "incident:run_action", "agent:set_not_ready"))

  pure val STEP_RESULT_IDS: Set[str] = Set("processed")

  pure val STEP_RESULT_CLOSE_IDS: Set[str] = Set("close")

  pure val EXIT_RULE: { appliesTo: Set[str], requiresAnyOf: Set[str], requiresAnyOfWithHoldLimit: Set[str], disables: Set[str] } = { appliesTo: Set("incident:claim", "incident:accept"), requiresAnyOf: Set("incident:hold", "incident:release", "incident:close"), requiresAnyOfWithHoldLimit: Set("incident:release", "incident:close"), disables: Set("incident:claim", "incident:accept") }

  pure val USED_PERMISSIONS: Set[str] = Set("agent:set_not_ready", "incident:accept", "incident:bulk", "incident:claim", "incident:close", "incident:close:unprocessed", "incident:hold", "incident:reassign", "incident:release", "incident:reopen", "incident:run_action", "incident:transfer:any", "incident:transfer:own")

  pure val TIMER_IDS: Set[str] = Set("reaction", "resolution", "hold")

  pure val NO_TIMER: Timer = { due: 0, paused: false, left: 0, fired: 0, since: 0 }

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "", eventGuid: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

  pure val NO_FORM: Form = { targetId: "", primaryId: "", resultId: "", reasonId: "", causeId: "", comment: "" }

  pure val CAUSE_FOR: str -> str = Map("mass" -> "power")

  /* ===== Определения машины (cel.definitions) ===== */


  // §8.1. Адресат: владелец-человек, а пока группа не приняла — сама группа

  def addressee(x: Incident): str =
    (if ((x.owner != "")) x.owner else x.assignmentGroup)

  def unowned(x: Incident): bool =
    ((x.owner == "") and (x.assignmentGroup == ""))

  // §8.1, §10.1 (RULE-107). Кому форма «Передать» предлагает инцидент: не себе и не своей группе, не текущему адресату, тому, кто может принять, и не вышедшему, чья дежурная группа — своя: передача ему сразу ушла бы этой группе, то есть вернулась бы себе — как запрет «на себя» у автоэскалации (RULE-93)

  def offersTransferTo(who: str, t: str, x: Incident): bool =
    (((not(isSelf(who, t)) and (t != addressee(x))) and canAccept(t, x, "")) and not(((isOperator(t) and (agentState(t) == "offline")) and isSelf(who, dutyGroupOf(t)))))

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

  // §4. Срок удержания, с — по причине (secFrom таймера hold). У причины с deadlineFromIdle («Нет связи») — порог возврата в очередь минус порог удержания, не меньше 0: срок причины и возврат по молчанию совпадают при любых порогах (RULE-118, RULE-129, RULE-132). Причины нет — -1, срок не ставится. Срок у причины обязателен, кроме deadlineFromIdle (§4, правило 7; RULE-135, check_machine.py): ветка «maxMinutes пуст» — подстраховка

  def holdSec(x: Incident): int =
    { val rs_46 = settings.holdReasons.select(r_47 => (r_47.id == x.holdReasonId))  (if ((rs_46.length() == 0)) (0 - 1) else (if (rs_46[0].deadlineFromIdle) (if ((settings.session.idleReleaseSec > settings.session.idleHoldSec)) (settings.session.idleReleaseSec - settings.session.idleHoldSec) else 0) else (if ((rs_46[0].maxMinutes.length() > 0)) (rs_46[0].maxMinutes[0] * 60) else (0 - 1)))) }

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

  // §14.5, ARCH-15. Условие правила подошло событию: каждое заданное поле совпало (поля условия соединены «и»); группа — устройство-источник в ней или во вложенной

  def conditionMatches(c: Condition, e: Event): bool =
    (((((c.eventType.length() == 0) or (c.eventType[0] == e.eventType)) and ((c.device.length() == 0) or (c.device[0] == e.device))) and ((c.deviceType.length() == 0) or (c.deviceType[0] == e.deviceType))) and ((c.group.length() == 0) or deviceInGroup(e.device, c.group[0])))

  // §14.5, ARCH-15. Точность условия — по самому точному его полю: устройство 3000, тип устройства 2000, группа 1000 плюс глубина группы в дереве; только тип события — 0 (тип ранга не добавляет)

  def conditionRank(c: Condition): int =
    (if ((c.device.length() > 0)) 3000 else (if ((c.deviceType.length() > 0)) 2000 else (if ((c.group.length() > 0)) (1000 + groupDepth(c.group[0])) else 0)))

  // §14.5, ARCH-15. Точность правила для события — наибольшая из подошедших условий (условия соединены «или»); не подошло ни одно — -1

  def ruleRank(r: Rule, e: Event): int =
    { val ks_51 = r.conditions.select(c_52 => conditionMatches(c_52, e)).foldl([], (acc, c_53) => acc.append(conditionRank(c_53)))  (if ((ks_51.length() == 0)) (0 - 1) else ks_51.select(k_54 => ks_51.foldl(true, (acc, j_55) => acc and (j_55 <= k_54)))[0]) }

  // §14.5, ARCH-15. Правило подошло событию: у него есть сценарий и подошло хоть одно условие. Правило без сценария в выборе не участвует

  def ruleMatches(r: Rule, e: Event): bool =
    ((r.scenarios.length() > 0) and r.conditions.foldl(false, (acc, c_56) => acc or conditionMatches(c_56, e)))

  // §14.5, ARCH-15 (решение пользователя 2026-10-28). Правило a старше b для события — строго: точнее условие; при равной точности — выше приоритет; при равном приоритете — раньше создано. Полное равенство — ни одно не старше: решает порядок списка правил

  def ruleBeats(a: Rule, b: Rule, e: Event): bool =
    { val ra_57 = ruleRank(a, e)  { val rb_58 = ruleRank(b, e)  ((ra_57 > rb_58) or ((ra_57 == rb_58) and ((a.priority > b.priority) or ((a.priority == b.priority) and (a.createdAt < b.createdAt))))) } }

  // §14.5, ARCH-15. Правило-победитель сценария s для события: из подошедших правил с этим сценарием — те, кого не старше ни одно; сервер берёт первое по порядку списка. От него приоритет и ruleGuid инцидента

  def ruleFor(rules: List[Rule], e: Event, s: str): List[Rule] =
    { val ms_59 = rules.select(r_60 => (ruleMatches(r_60, e) and r_60.scenarios.foldl(false, (acc, y61) => acc or y61 == s)))  ms_59.select(r_62 => not(ms_59.foldl(false, (acc, o_63) => acc or ruleBeats(o_63, r_62, e)))) }

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_64 => (e_64.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_65 => ((e_65.id != p.id) and inGroupAt(e_65, p, at)))

  // §14.5, ARCH-15. Соседи — инциденты того же события, кроме самого x: другие службы той же тревоги. Не привязка §11: у каждого свой владелец, сроки и закрытие

  def siblingsOf(incidents: List[Incident], x: Incident): List[Incident] =
    incidents.select(s_66 => (((x.eventGuid != "") and (s_66.eventGuid == x.eventGuid)) and (s_66.id != x.id)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w67 = if (not(timerDef(timerId).pausable)) {
      val sec_68 = timerSec(w0.inc.get(iid), timerId, "")
      val w69 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_68 < 0)) 0 else (c.now + (sec_68 * 1000))) }) }) }
      val w70 = { ...w69, inc: w69.inc.set(iid, { ...w69.inc.get(iid), timers: w69.inc.get(iid).timers.set(timerId, { ...w69.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w70
    } else {
      val w71 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_72 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w73 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_72 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_72)) }) }) }
      val w74 = { ...w73, inc: w73.inc.set(iid, { ...w73.inc.get(iid), timers: w73.inc.get(iid).timers.set(timerId, { ...w73.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w75 = { ...w74, inc: w74.inc.set(iid, { ...w74.inc.get(iid), timers: w74.inc.get(iid).timers.set(timerId, { ...w74.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w75
    } else w0
      w71
    }
    w67
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w76 = if (not(timerDef(timerId).pausable)) {
      val w77 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w78 = { ...w77, inc: w77.inc.set(iid, { ...w77.inc.get(iid), timers: w77.inc.get(iid).timers.set(timerId, { ...w77.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w78
    } else {
      val w79 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w80 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w81 = { ...w80, inc: w80.inc.set(iid, { ...w80.inc.get(iid), timers: w80.inc.get(iid).timers.set(timerId, { ...w80.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w82 = { ...w81, inc: w81.inc.set(iid, { ...w81.inc.get(iid), timers: w81.inc.get(iid).timers.set(timerId, { ...w81.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w82
    } else w0
      w79
    }
    w76
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_83 = ""
    val w84 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_83 }) }
    w84
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_85 = ""
    val w86 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_85 }) }
    w86
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_87 = 0
    val w88 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_87 }) }
    w88
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w89 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w90 = if (timerDef("reaction").startsOnce) {
      val w91 = ec_resumeTimer(w0, c, iid, "reaction")
      w91
    } else {
      val w92 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w93 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w94 = { ...w93, inc: w93.inc.set(iid, { ...w93.inc.get(iid), timers: w93.inc.get(iid).timers.set("reaction", { ...w93.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w95 = { ...w94, inc: w94.inc.set(iid, { ...w94.inc.get(iid), timers: w94.inc.get(iid).timers.set("reaction", { ...w94.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w95
    } else {
      val sec_96 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w97 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_96 < 0)) 0 else (c.now + (sec_96 * 1000))) }) }) }
      val w98 = { ...w97, inc: w97.inc.set(iid, { ...w97.inc.get(iid), timers: w97.inc.get(iid).timers.set("reaction", { ...w97.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w99 = { ...w98, inc: w98.inc.set(iid, { ...w98.inc.get(iid), timers: w98.inc.get(iid).timers.set("reaction", { ...w98.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w100 = { ...w99, inc: w99.inc.set(iid, { ...w99.inc.get(iid), timers: w99.inc.get(iid).timers.set("reaction", { ...w99.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w100
    }
      w92
    }
      w90
    }
    w89
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
    not(settings.session.states.foldl(false, (acc, s_101) => acc or ((s_101.id == agentState(c.me)) and s_101.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_102 = c.actor
    val w103 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_102 }) }
    w103
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w104 = if (timerDef("reaction").startsOnce) {
      val w105 = ec_pauseTimer(w0, c, iid, "reaction")
      w105
    } else {
      val w106 = if (false) {
      val w107 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w108 = { ...w107, inc: w107.inc.set(iid, { ...w107.inc.get(iid), timers: w107.inc.get(iid).timers.set("reaction", { ...w107.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w109 = { ...w108, inc: w108.inc.set(iid, { ...w108.inc.get(iid), timers: w108.inc.get(iid).timers.set("reaction", { ...w108.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w110 = { ...w109, inc: w109.inc.set(iid, { ...w109.inc.get(iid), timers: w109.inc.get(iid).timers.set("reaction", { ...w109.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w110
    } else {
      val w111 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_112 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w113 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_112) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w114 = { ...w113, inc: w113.inc.set(iid, { ...w113.inc.get(iid), timers: w113.inc.get(iid).timers.set("reaction", { ...w113.inc.get(iid).timers.get("reaction"), paused: keep_112 }) }) }
      val w115 = { ...w114, inc: w114.inc.set(iid, { ...w114.inc.get(iid), timers: w114.inc.get(iid).timers.set("reaction", { ...w114.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w116 = { ...w115, inc: w115.inc.set(iid, { ...w115.inc.get(iid), timers: w115.inc.get(iid).timers.set("reaction", { ...w115.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w116
    }
      w111
    }
      w106
    }
    w104
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w117 = if (not(timerDef("resolution").pausable)) {
      val sec_118 = timerSec(w0.inc.get(iid), "resolution", "")
      val w119 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_118 < 0)) 0 else (c.now + (sec_118 * 1000))) }) }) }
      val w120 = { ...w119, inc: w119.inc.set(iid, { ...w119.inc.get(iid), timers: w119.inc.get(iid).timers.set("resolution", { ...w119.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w120
    } else {
      val w121 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_122 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w123 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_122 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_122)) }) }) }
      val w124 = { ...w123, inc: w123.inc.set(iid, { ...w123.inc.get(iid), timers: w123.inc.get(iid).timers.set("resolution", { ...w123.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w125 = { ...w124, inc: w124.inc.set(iid, { ...w124.inc.get(iid), timers: w124.inc.get(iid).timers.set("resolution", { ...w124.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w125
    } else w0
      w121
    }
    w117
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
    not(settings.session.states.foldl(false, (acc, s_126) => acc or ((s_126.id == agentState(c.me)) and s_126.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_127 = c.actor
    val w128 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_127 }) }
    w128
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_129 = ""
    val w130 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_129 }) }
    w130
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w131 = if (timerDef("reaction").startsOnce) {
      val w132 = ec_pauseTimer(w0, c, iid, "reaction")
      w132
    } else {
      val w133 = if (false) {
      val w134 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w135 = { ...w134, inc: w134.inc.set(iid, { ...w134.inc.get(iid), timers: w134.inc.get(iid).timers.set("reaction", { ...w134.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w136 = { ...w135, inc: w135.inc.set(iid, { ...w135.inc.get(iid), timers: w135.inc.get(iid).timers.set("reaction", { ...w135.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w137 = { ...w136, inc: w136.inc.set(iid, { ...w136.inc.get(iid), timers: w136.inc.get(iid).timers.set("reaction", { ...w136.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w137
    } else {
      val w138 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_139 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w140 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_139) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w141 = { ...w140, inc: w140.inc.set(iid, { ...w140.inc.get(iid), timers: w140.inc.get(iid).timers.set("reaction", { ...w140.inc.get(iid).timers.get("reaction"), paused: keep_139 }) }) }
      val w142 = { ...w141, inc: w141.inc.set(iid, { ...w141.inc.get(iid), timers: w141.inc.get(iid).timers.set("reaction", { ...w141.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w143 = { ...w142, inc: w142.inc.set(iid, { ...w142.inc.get(iid), timers: w142.inc.get(iid).timers.set("reaction", { ...w142.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w143
    }
      w138
    }
      w133
    }
    w131
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w144 = if (not(timerDef("resolution").pausable)) {
      val sec_145 = timerSec(w0.inc.get(iid), "resolution", "")
      val w146 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_145 < 0)) 0 else (c.now + (sec_145 * 1000))) }) }) }
      val w147 = { ...w146, inc: w146.inc.set(iid, { ...w146.inc.get(iid), timers: w146.inc.get(iid).timers.set("resolution", { ...w146.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w147
    } else {
      val w148 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_149 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w150 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_149 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_149)) }) }) }
      val w151 = { ...w150, inc: w150.inc.set(iid, { ...w150.inc.get(iid), timers: w150.inc.get(iid).timers.set("resolution", { ...w150.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w152 = { ...w151, inc: w151.inc.set(iid, { ...w151.inc.get(iid), timers: w151.inc.get(iid).timers.set("resolution", { ...w151.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w152
    } else w0
      w148
    }
    w144
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
    not(settings.session.states.foldl(false, (acc, s_153) => acc or ((s_153.id == agentState(c.me)) and s_153.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_154 = ""
    val w155 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_154 }) }
    w155
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_156 = ""
    val w157 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_156 }) }
    w157
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
    not(settings.session.states.foldl(false, (acc, s_158) => acc or ((s_158.id == agentState(c.me)) and s_158.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_159 = c.form.reasonId
    val w160 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_159 }) }
    w160
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w161 = if (not(timerDef("resolution").pausable)) {
      val w162 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w163 = { ...w162, inc: w162.inc.set(iid, { ...w162.inc.get(iid), timers: w162.inc.get(iid).timers.set("resolution", { ...w162.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w163
    } else {
      val w164 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w165 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w166 = { ...w165, inc: w165.inc.set(iid, { ...w165.inc.get(iid), timers: w165.inc.get(iid).timers.set("resolution", { ...w165.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w167 = { ...w166, inc: w166.inc.set(iid, { ...w166.inc.get(iid), timers: w166.inc.get(iid).timers.set("resolution", { ...w166.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w167
    } else w0
      w164
    }
    w161
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w168 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w169 = if (timerDef("hold").startsOnce) {
      val w170 = ec_resumeTimer(w0, c, iid, "hold")
      w170
    } else {
      val w171 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w172 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w173 = { ...w172, inc: w172.inc.set(iid, { ...w172.inc.get(iid), timers: w172.inc.get(iid).timers.set("hold", { ...w172.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w174 = { ...w173, inc: w173.inc.set(iid, { ...w173.inc.get(iid), timers: w173.inc.get(iid).timers.set("hold", { ...w173.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w174
    } else {
      val sec_175 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w176 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_175 < 0)) 0 else (c.now + (sec_175 * 1000))) }) }) }
      val w177 = { ...w176, inc: w176.inc.set(iid, { ...w176.inc.get(iid), timers: w176.inc.get(iid).timers.set("hold", { ...w176.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w178 = { ...w177, inc: w177.inc.set(iid, { ...w177.inc.get(iid), timers: w177.inc.get(iid).timers.set("hold", { ...w177.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w179 = { ...w178, inc: w178.inc.set(iid, { ...w178.inc.get(iid), timers: w178.inc.get(iid).timers.set("hold", { ...w178.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w179
    }
      w171
    }
      w169
    }
    w168
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
    not(settings.session.states.foldl(false, (acc, s_180) => acc or ((s_180.id == agentState(c.me)) and s_180.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w181 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w181
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w182 = if (timerDef("hold").startsOnce) {
      val w183 = ec_pauseTimer(w0, c, iid, "hold")
      w183
    } else {
      val w184 = if (false) {
      val w185 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w186 = { ...w185, inc: w185.inc.set(iid, { ...w185.inc.get(iid), timers: w185.inc.get(iid).timers.set("hold", { ...w185.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w187 = { ...w186, inc: w186.inc.set(iid, { ...w186.inc.get(iid), timers: w186.inc.get(iid).timers.set("hold", { ...w186.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w188 = { ...w187, inc: w187.inc.set(iid, { ...w187.inc.get(iid), timers: w187.inc.get(iid).timers.set("hold", { ...w187.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w188
    } else {
      val w189 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_190 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w191 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_190) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w192 = { ...w191, inc: w191.inc.set(iid, { ...w191.inc.get(iid), timers: w191.inc.get(iid).timers.set("hold", { ...w191.inc.get(iid).timers.get("hold"), paused: keep_190 }) }) }
      val w193 = { ...w192, inc: w192.inc.set(iid, { ...w192.inc.get(iid), timers: w192.inc.get(iid).timers.set("hold", { ...w192.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w194 = { ...w193, inc: w193.inc.set(iid, { ...w193.inc.get(iid), timers: w193.inc.get(iid).timers.set("hold", { ...w193.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w194
    }
      w189
    }
      w184
    }
    w182
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w195 = if (not(timerDef("resolution").pausable)) {
      val sec_196 = timerSec(w0.inc.get(iid), "resolution", "")
      val w197 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_196 < 0)) 0 else (c.now + (sec_196 * 1000))) }) }) }
      val w198 = { ...w197, inc: w197.inc.set(iid, { ...w197.inc.get(iid), timers: w197.inc.get(iid).timers.set("resolution", { ...w197.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w198
    } else {
      val w199 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_200 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w201 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_200 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_200)) }) }) }
      val w202 = { ...w201, inc: w201.inc.set(iid, { ...w201.inc.get(iid), timers: w201.inc.get(iid).timers.set("resolution", { ...w201.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w203 = { ...w202, inc: w202.inc.set(iid, { ...w202.inc.get(iid), timers: w202.inc.get(iid).timers.set("resolution", { ...w202.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w203
    } else w0
      w199
    }
    w195
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
    not(settings.session.states.foldl(false, (acc, s_204) => acc or ((s_204.id == agentState(c.me)) and s_204.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_205 = ""
    val w206 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_205 }) }
    w206
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w207 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w207
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w208 = if (not(timerDef("resolution").pausable)) {
      val w209 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w210 = { ...w209, inc: w209.inc.set(iid, { ...w209.inc.get(iid), timers: w209.inc.get(iid).timers.set("resolution", { ...w209.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w210
    } else {
      val w211 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w212 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w213 = { ...w212, inc: w212.inc.set(iid, { ...w212.inc.get(iid), timers: w212.inc.get(iid).timers.set("resolution", { ...w212.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w214 = { ...w213, inc: w213.inc.set(iid, { ...w213.inc.get(iid), timers: w213.inc.get(iid).timers.set("resolution", { ...w213.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w214
    } else w0
      w211
    }
    w208
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w215 = if (timerDef("hold").startsOnce) {
      val w216 = ec_pauseTimer(w0, c, iid, "hold")
      w216
    } else {
      val w217 = if (false) {
      val w218 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w219 = { ...w218, inc: w218.inc.set(iid, { ...w218.inc.get(iid), timers: w218.inc.get(iid).timers.set("hold", { ...w218.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w220 = { ...w219, inc: w219.inc.set(iid, { ...w219.inc.get(iid), timers: w219.inc.get(iid).timers.set("hold", { ...w219.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w221 = { ...w220, inc: w220.inc.set(iid, { ...w220.inc.get(iid), timers: w220.inc.get(iid).timers.set("hold", { ...w220.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w221
    } else {
      val w222 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_223 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w224 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_223) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w225 = { ...w224, inc: w224.inc.set(iid, { ...w224.inc.get(iid), timers: w224.inc.get(iid).timers.set("hold", { ...w224.inc.get(iid).timers.get("hold"), paused: keep_223 }) }) }
      val w226 = { ...w225, inc: w225.inc.set(iid, { ...w225.inc.get(iid), timers: w225.inc.get(iid).timers.set("hold", { ...w225.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w227 = { ...w226, inc: w226.inc.set(iid, { ...w226.inc.get(iid), timers: w226.inc.get(iid).timers.set("hold", { ...w226.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w227
    }
      w222
    }
      w217
    }
    w215
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w228 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w229 = if (timerDef("reaction").startsOnce) {
      val w230 = ec_resumeTimer(w0, c, iid, "reaction")
      w230
    } else {
      val w231 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w232 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w233 = { ...w232, inc: w232.inc.set(iid, { ...w232.inc.get(iid), timers: w232.inc.get(iid).timers.set("reaction", { ...w232.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w234 = { ...w233, inc: w233.inc.set(iid, { ...w233.inc.get(iid), timers: w233.inc.get(iid).timers.set("reaction", { ...w233.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w234
    } else {
      val sec_235 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w236 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_235 < 0)) 0 else (c.now + (sec_235 * 1000))) }) }) }
      val w237 = { ...w236, inc: w236.inc.set(iid, { ...w236.inc.get(iid), timers: w236.inc.get(iid).timers.set("reaction", { ...w236.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w238 = { ...w237, inc: w237.inc.set(iid, { ...w237.inc.get(iid), timers: w237.inc.get(iid).timers.set("reaction", { ...w237.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w239 = { ...w238, inc: w238.inc.set(iid, { ...w238.inc.get(iid), timers: w238.inc.get(iid).timers.set("reaction", { ...w238.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w239
    }
      w231
    }
      w229
    }
    w228
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
    not(settings.session.states.foldl(false, (acc, s_240) => acc or ((s_240.id == agentState(c.me)) and s_240.readOnly))),
    transferTargets.foldl(false, (acc, t_241) => acc or (offersTransferTo(c.me, t_241, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_242) => acc and (isDone(e_242) or hasAccess(t_241, e_242))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_243) => acc and (isDone(e_243) or hasAccess(c.form.targetId, e_243)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_244 = personOf(c.form.targetId)
    val w245 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_244 }) }
    w245
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_246 = groupOf(c.form.targetId)
    val w247 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_246 }) }
    w247
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w248 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w248
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w249 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w249
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w250 = if (not(timerDef("resolution").pausable)) {
      val w251 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w252 = { ...w251, inc: w251.inc.set(iid, { ...w251.inc.get(iid), timers: w251.inc.get(iid).timers.set("resolution", { ...w251.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w252
    } else {
      val w253 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w254 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w255 = { ...w254, inc: w254.inc.set(iid, { ...w254.inc.get(iid), timers: w254.inc.get(iid).timers.set("resolution", { ...w254.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w256 = { ...w255, inc: w255.inc.set(iid, { ...w255.inc.get(iid), timers: w255.inc.get(iid).timers.set("resolution", { ...w255.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w256
    } else w0
      w253
    }
    w250
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w257 = if (timerDef("hold").startsOnce) {
      val w258 = ec_pauseTimer(w0, c, iid, "hold")
      w258
    } else {
      val w259 = if (false) {
      val w260 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w261 = { ...w260, inc: w260.inc.set(iid, { ...w260.inc.get(iid), timers: w260.inc.get(iid).timers.set("hold", { ...w260.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w262 = { ...w261, inc: w261.inc.set(iid, { ...w261.inc.get(iid), timers: w261.inc.get(iid).timers.set("hold", { ...w261.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w263 = { ...w262, inc: w262.inc.set(iid, { ...w262.inc.get(iid), timers: w262.inc.get(iid).timers.set("hold", { ...w262.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w263
    } else {
      val w264 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_265 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w266 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_265) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w267 = { ...w266, inc: w266.inc.set(iid, { ...w266.inc.get(iid), timers: w266.inc.get(iid).timers.set("hold", { ...w266.inc.get(iid).timers.get("hold"), paused: keep_265 }) }) }
      val w268 = { ...w267, inc: w267.inc.set(iid, { ...w267.inc.get(iid), timers: w267.inc.get(iid).timers.set("hold", { ...w267.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w269 = { ...w268, inc: w268.inc.set(iid, { ...w268.inc.get(iid), timers: w268.inc.get(iid).timers.set("hold", { ...w268.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w269
    }
      w264
    }
      w259
    }
    w257
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w270 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w271 = if (timerDef("reaction").startsOnce) {
      val w272 = ec_resumeTimer(w0, c, iid, "reaction")
      w272
    } else {
      val w273 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w274 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w275 = { ...w274, inc: w274.inc.set(iid, { ...w274.inc.get(iid), timers: w274.inc.get(iid).timers.set("reaction", { ...w274.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w276 = { ...w275, inc: w275.inc.set(iid, { ...w275.inc.get(iid), timers: w275.inc.get(iid).timers.set("reaction", { ...w275.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w276
    } else {
      val sec_277 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w278 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_277 < 0)) 0 else (c.now + (sec_277 * 1000))) }) }) }
      val w279 = { ...w278, inc: w278.inc.set(iid, { ...w278.inc.get(iid), timers: w278.inc.get(iid).timers.set("reaction", { ...w278.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w280 = { ...w279, inc: w279.inc.set(iid, { ...w279.inc.get(iid), timers: w279.inc.get(iid).timers.set("reaction", { ...w279.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w281 = { ...w280, inc: w280.inc.set(iid, { ...w280.inc.get(iid), timers: w280.inc.get(iid).timers.set("reaction", { ...w280.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w281
    }
      w273
    }
      w271
    }
    w270
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_282 = c.before.owner
    val w283 = if (((whom_282 != "") and (whom_282 != c.actor))) w0 else w0
    w283
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_284 = addressee(w0.inc.get(iid))
    val w285 = if (((whom_284 != "") and (whom_284 != c.actor))) w0 else w0
    w285
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
    not(settings.session.states.foldl(false, (acc, s_286) => acc or ((s_286.id == agentState(c.me)) and s_286.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_287 = c.actor
    val w288 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_287 }) }
    w288
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_289 = ""
    val w290 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_289 }) }
    w290
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w291 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w291
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w292 = if (timerDef("reaction").startsOnce) {
      val w293 = ec_pauseTimer(w0, c, iid, "reaction")
      w293
    } else {
      val w294 = if (false) {
      val w295 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("reaction", { ...w295.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w297 = { ...w296, inc: w296.inc.set(iid, { ...w296.inc.get(iid), timers: w296.inc.get(iid).timers.set("reaction", { ...w296.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w298 = { ...w297, inc: w297.inc.set(iid, { ...w297.inc.get(iid), timers: w297.inc.get(iid).timers.set("reaction", { ...w297.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w298
    } else {
      val w299 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_300 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w301 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_300) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w302 = { ...w301, inc: w301.inc.set(iid, { ...w301.inc.get(iid), timers: w301.inc.get(iid).timers.set("reaction", { ...w301.inc.get(iid).timers.get("reaction"), paused: keep_300 }) }) }
      val w303 = { ...w302, inc: w302.inc.set(iid, { ...w302.inc.get(iid), timers: w302.inc.get(iid).timers.set("reaction", { ...w302.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w304 = { ...w303, inc: w303.inc.set(iid, { ...w303.inc.get(iid), timers: w303.inc.get(iid).timers.set("reaction", { ...w303.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w304
    }
      w299
    }
      w294
    }
    w292
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w305 = if (timerDef("hold").startsOnce) {
      val w306 = ec_pauseTimer(w0, c, iid, "hold")
      w306
    } else {
      val w307 = if (false) {
      val w308 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w309 = { ...w308, inc: w308.inc.set(iid, { ...w308.inc.get(iid), timers: w308.inc.get(iid).timers.set("hold", { ...w308.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w310 = { ...w309, inc: w309.inc.set(iid, { ...w309.inc.get(iid), timers: w309.inc.get(iid).timers.set("hold", { ...w309.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w311 = { ...w310, inc: w310.inc.set(iid, { ...w310.inc.get(iid), timers: w310.inc.get(iid).timers.set("hold", { ...w310.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w311
    } else {
      val w312 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_313 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w314 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_313) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w315 = { ...w314, inc: w314.inc.set(iid, { ...w314.inc.get(iid), timers: w314.inc.get(iid).timers.set("hold", { ...w314.inc.get(iid).timers.get("hold"), paused: keep_313 }) }) }
      val w316 = { ...w315, inc: w315.inc.set(iid, { ...w315.inc.get(iid), timers: w315.inc.get(iid).timers.set("hold", { ...w315.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w317 = { ...w316, inc: w316.inc.set(iid, { ...w316.inc.get(iid), timers: w316.inc.get(iid).timers.set("hold", { ...w316.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w317
    }
      w312
    }
      w307
    }
    w305
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w318 = if (not(timerDef("resolution").pausable)) {
      val sec_319 = timerSec(w0.inc.get(iid), "resolution", "")
      val w320 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_319 < 0)) 0 else (c.now + (sec_319 * 1000))) }) }) }
      val w321 = { ...w320, inc: w320.inc.set(iid, { ...w320.inc.get(iid), timers: w320.inc.get(iid).timers.set("resolution", { ...w320.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w321
    } else {
      val w322 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_323 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w324 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_323 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_323)) }) }) }
      val w325 = { ...w324, inc: w324.inc.set(iid, { ...w324.inc.get(iid), timers: w324.inc.get(iid).timers.set("resolution", { ...w324.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w326 = { ...w325, inc: w325.inc.set(iid, { ...w325.inc.get(iid), timers: w325.inc.get(iid).timers.set("resolution", { ...w325.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w326
    } else w0
      w322
    }
    w318
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
    val whom_327 = c.before.owner
    val w328 = if (((whom_327 != "") and (whom_327 != c.actor))) w0 else w0
    w328
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
    not(settings.session.states.foldl(false, (acc, s_329) => acc or ((s_329.id == agentState(c.me)) and s_329.readOnly))),
    { val os_330 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_330.foldl(false, (acc, o_331) => acc or ((o_331.id == c.form.resultId) and stepsOk(o_331, world.inc.get(iid)))) else os_330.foldl(false, (acc, o_332) => acc or stepsOk(o_332, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_333 = c.actor
    val w334 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_333 }) }
    w334
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_335 = ""
    val w336 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_335 }) }
    w336
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_337 = c.actor
    val w338 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_337 }) }
    w338
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_339 = c.now
    val w340 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_339 }) }
    w340
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_341 = c.form.resultId
    val w342 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_341 }) }
    w342
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_343 = c.form.causeId
    val w344 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_343 }) }
    w344
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_345 = c.form.comment
    val w346 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_345 }) }
    w346
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w347 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w347
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w348 = if (timerDef("reaction").startsOnce) {
      val w349 = ec_pauseTimer(w0, c, iid, "reaction")
      w349
    } else {
      val w350 = if (true) {
      val w351 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w352 = { ...w351, inc: w351.inc.set(iid, { ...w351.inc.get(iid), timers: w351.inc.get(iid).timers.set("reaction", { ...w351.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w353 = { ...w352, inc: w352.inc.set(iid, { ...w352.inc.get(iid), timers: w352.inc.get(iid).timers.set("reaction", { ...w352.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w354 = { ...w353, inc: w353.inc.set(iid, { ...w353.inc.get(iid), timers: w353.inc.get(iid).timers.set("reaction", { ...w353.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w354
    } else {
      val w355 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_356 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w357 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_356) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w358 = { ...w357, inc: w357.inc.set(iid, { ...w357.inc.get(iid), timers: w357.inc.get(iid).timers.set("reaction", { ...w357.inc.get(iid).timers.get("reaction"), paused: keep_356 }) }) }
      val w359 = { ...w358, inc: w358.inc.set(iid, { ...w358.inc.get(iid), timers: w358.inc.get(iid).timers.set("reaction", { ...w358.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w360 = { ...w359, inc: w359.inc.set(iid, { ...w359.inc.get(iid), timers: w359.inc.get(iid).timers.set("reaction", { ...w359.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w360
    }
      w355
    }
      w350
    }
    w348
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w361 = if (not(timerDef("resolution").pausable)) {
      val w362 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w363 = { ...w362, inc: w362.inc.set(iid, { ...w362.inc.get(iid), timers: w362.inc.get(iid).timers.set("resolution", { ...w362.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w363
    } else {
      val w364 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w365 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w366 = { ...w365, inc: w365.inc.set(iid, { ...w365.inc.get(iid), timers: w365.inc.get(iid).timers.set("resolution", { ...w365.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w367 = { ...w366, inc: w366.inc.set(iid, { ...w366.inc.get(iid), timers: w366.inc.get(iid).timers.set("resolution", { ...w366.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w367
    } else w0
      w364
    }
    w361
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w368 = if (timerDef("hold").startsOnce) {
      val w369 = ec_pauseTimer(w0, c, iid, "hold")
      w369
    } else {
      val w370 = if (false) {
      val w371 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w372 = { ...w371, inc: w371.inc.set(iid, { ...w371.inc.get(iid), timers: w371.inc.get(iid).timers.set("hold", { ...w371.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w373 = { ...w372, inc: w372.inc.set(iid, { ...w372.inc.get(iid), timers: w372.inc.get(iid).timers.set("hold", { ...w372.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w374 = { ...w373, inc: w373.inc.set(iid, { ...w373.inc.get(iid), timers: w373.inc.get(iid).timers.set("hold", { ...w373.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w374
    } else {
      val w375 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_376 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w377 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_376) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w378 = { ...w377, inc: w377.inc.set(iid, { ...w377.inc.get(iid), timers: w377.inc.get(iid).timers.set("hold", { ...w377.inc.get(iid).timers.get("hold"), paused: keep_376 }) }) }
      val w379 = { ...w378, inc: w378.inc.set(iid, { ...w378.inc.get(iid), timers: w378.inc.get(iid).timers.set("hold", { ...w378.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w380 = { ...w379, inc: w379.inc.set(iid, { ...w379.inc.get(iid), timers: w379.inc.get(iid).timers.set("hold", { ...w379.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w380
    }
      w375
    }
      w370
    }
    w368
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
    not(settings.session.states.foldl(false, (acc, s_381) => acc or ((s_381.id == agentState(c.me)) and s_381.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_382 = c.actor
    val w383 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_382 }) }
    w383
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w384 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_385 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w386 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w387 = { ...w386, inc: w386.inc.set(iid, { ...w386.inc.get(iid), linkedTo: "" }) }
      val w388 = { ...w387, inc: w387.inc.set(iid, { ...w387.inc.get(iid), linkedAt: 0 }) }
      val w389 = if (((ps_385.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w388 else w388
      val w390 = if (("workflow.journal.linked_reopened" != "")) {
      val w391 = ps_385.foldl([], (acc, x394) => acc.append(x394.id)).foldl(w389, (wf392, pId393) => wf392)
      w391
    } else w389
      w390
    } else {
      val w395 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w396 = { ...w395, inc: w395.inc.set(iid, { ...w395.inc.get(iid), linkedAt: 0 }) }
      w396
    }
    w384
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_397 = ""
    val w398 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_397 }) }
    w398
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_399 = ""
    val w400 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_399 }) }
    w400
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_401 = ""
    val w402 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_401 }) }
    w402
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_403 = 0
    val w404 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_403 }) }
    w404
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_405 = ""
    val w406 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_405 }) }
    w406
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val sec_407 = settings.limits.reopenResolutionSec
    val w408 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_407 > 0)) sec_407 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w409 = { ...w408, inc: w408.inc.set(iid, { ...w408.inc.get(iid), timers: w408.inc.get(iid).timers.set("resolution", { ...w408.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w410 = { ...w409, inc: w409.inc.set(iid, { ...w409.inc.get(iid), timers: w409.inc.get(iid).timers.set("resolution", { ...w409.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w410
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val w411 = if (timerDef("reaction").startsOnce) {
      val w412 = ec_pauseTimer(w0, c, iid, "reaction")
      w412
    } else {
      val w413 = if (true) {
      val w414 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w415 = { ...w414, inc: w414.inc.set(iid, { ...w414.inc.get(iid), timers: w414.inc.get(iid).timers.set("reaction", { ...w414.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w416 = { ...w415, inc: w415.inc.set(iid, { ...w415.inc.get(iid), timers: w415.inc.get(iid).timers.set("reaction", { ...w415.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w417 = { ...w416, inc: w416.inc.set(iid, { ...w416.inc.get(iid), timers: w416.inc.get(iid).timers.set("reaction", { ...w416.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w417
    } else {
      val w418 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_419 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w420 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_419) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w421 = { ...w420, inc: w420.inc.set(iid, { ...w420.inc.get(iid), timers: w420.inc.get(iid).timers.set("reaction", { ...w420.inc.get(iid).timers.get("reaction"), paused: keep_419 }) }) }
      val w422 = { ...w421, inc: w421.inc.set(iid, { ...w421.inc.get(iid), timers: w421.inc.get(iid).timers.set("reaction", { ...w421.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w423 = { ...w422, inc: w422.inc.set(iid, { ...w422.inc.get(iid), timers: w422.inc.get(iid).timers.set("reaction", { ...w422.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w423
    }
      w418
    }
      w413
    }
    w411
  }

  def e_reopen_10(w0: World, c: Ctx, iid: str): World = {

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
    val w8 = e_reopen_7(w7, c1, iid)
    val w9 = e_reopen_8(w8, c1, iid)
    val w10 = e_reopen_9(w9, c1, iid)
    val w11 = e_reopen_10(w10, c1, iid)
    w11
  }

  // auto_escalate: timer → pending_acceptance

  def ok_auto_escalate(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == true),
    { val t_424 = world.inc.get(iid).timers.get("reaction")  (((t_424.due != 0) and (t_424.due <= c.now)) and (t_424.fired != t_424.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_425 = personOf(levelUpTarget(c.before))
    val w426 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_425 }) }
    w426
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_427 = groupOf(levelUpTarget(c.before))
    val w428 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_427 }) }
    w428
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_429 = levelUpNumber(c.before)
    val w430 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_429 }) }
    w430
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w431 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w431
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w432 = if (not(timerDef("resolution").pausable)) {
      val w433 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w434 = { ...w433, inc: w433.inc.set(iid, { ...w433.inc.get(iid), timers: w433.inc.get(iid).timers.set("resolution", { ...w433.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w434
    } else {
      val w435 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w436 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w437 = { ...w436, inc: w436.inc.set(iid, { ...w436.inc.get(iid), timers: w436.inc.get(iid).timers.set("resolution", { ...w436.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w438 = { ...w437, inc: w437.inc.set(iid, { ...w437.inc.get(iid), timers: w437.inc.get(iid).timers.set("resolution", { ...w437.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w438
    } else w0
      w435
    }
    w432
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w439 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w440 = if (timerDef("reaction").startsOnce) {
      val w441 = ec_resumeTimer(w0, c, iid, "reaction")
      w441
    } else {
      val w442 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w443 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w444 = { ...w443, inc: w443.inc.set(iid, { ...w443.inc.get(iid), timers: w443.inc.get(iid).timers.set("reaction", { ...w443.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w445 = { ...w444, inc: w444.inc.set(iid, { ...w444.inc.get(iid), timers: w444.inc.get(iid).timers.set("reaction", { ...w444.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w445
    } else {
      val sec_446 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w447 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_446 < 0)) 0 else (c.now + (sec_446 * 1000))) }) }) }
      val w448 = { ...w447, inc: w447.inc.set(iid, { ...w447.inc.get(iid), timers: w447.inc.get(iid).timers.set("reaction", { ...w447.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w449 = { ...w448, inc: w448.inc.set(iid, { ...w448.inc.get(iid), timers: w448.inc.get(iid).timers.set("reaction", { ...w448.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w450 = { ...w449, inc: w449.inc.set(iid, { ...w449.inc.get(iid), timers: w449.inc.get(iid).timers.set("reaction", { ...w449.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w450
    }
      w442
    }
      w440
    }
    w439
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_451 = addressee(w0.inc.get(iid))
    val w452 = if (((whom_451 != "") and (whom_451 != c.actor))) w0 else w0
    w452
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
    { val t_453 = world.inc.get(iid).timers.get("reaction")  (((t_453.due != 0) and (t_453.due <= c.now)) and (t_453.fired != t_453.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_454 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w455 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_454) }) }
    val w456 = { ...w455, inc: w455.inc.set(iid, { ...w455.inc.get(iid), slaBreached: true }) }
    val w457 = groupMembersAt(incs(w0), w456.inc.get(iid), c.deadline).foldl([], (acc, x460) => acc.append(x460.id)).foldl(w456, (wf458, eId459) => {
      val w461 = { ...wf458, inc: wf458.inc.set(eId459, { ...wf458.inc.get(eId459), breaches: wf458.inc.get(eId459).breaches.append(breach_454) }) }
      val w462 = { ...w461, inc: w461.inc.set(eId459, { ...w461.inc.get(eId459), slaBreached: true }) }
      w462
    })
    w457
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w463 = if (timerDef("reaction").startsOnce) {
      val w464 = ec_pauseTimer(w0, c, iid, "reaction")
      w464
    } else {
      val w465 = if (false) {
      val w466 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w467 = { ...w466, inc: w466.inc.set(iid, { ...w466.inc.get(iid), timers: w466.inc.get(iid).timers.set("reaction", { ...w466.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w468 = { ...w467, inc: w467.inc.set(iid, { ...w467.inc.get(iid), timers: w467.inc.get(iid).timers.set("reaction", { ...w467.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w469 = { ...w468, inc: w468.inc.set(iid, { ...w468.inc.get(iid), timers: w468.inc.get(iid).timers.set("reaction", { ...w468.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w469
    } else {
      val w470 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_471 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w472 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_471) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w473 = { ...w472, inc: w472.inc.set(iid, { ...w472.inc.get(iid), timers: w472.inc.get(iid).timers.set("reaction", { ...w472.inc.get(iid).timers.get("reaction"), paused: keep_471 }) }) }
      val w474 = { ...w473, inc: w473.inc.set(iid, { ...w473.inc.get(iid), timers: w473.inc.get(iid).timers.set("reaction", { ...w473.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w475 = { ...w474, inc: w474.inc.set(iid, { ...w474.inc.get(iid), timers: w474.inc.get(iid).timers.set("reaction", { ...w474.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w475
    }
      w470
    }
      w465
    }
    w463
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_476 = settings.alerts.target
    val w477 = if (((whom_476 != "") and (whom_476 != c.actor))) w0 else w0
    w477
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
    { val t_478 = world.inc.get(iid).timers.get("reaction")  (((t_478.due != 0) and (t_478.due <= c.now)) and (t_478.fired != t_478.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_479 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w480 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_479) }) }
    val w481 = { ...w480, inc: w480.inc.set(iid, { ...w480.inc.get(iid), slaBreached: true }) }
    val w482 = groupMembersAt(incs(w0), w481.inc.get(iid), c.deadline).foldl([], (acc, x485) => acc.append(x485.id)).foldl(w481, (wf483, eId484) => {
      val w486 = { ...wf483, inc: wf483.inc.set(eId484, { ...wf483.inc.get(eId484), breaches: wf483.inc.get(eId484).breaches.append(breach_479) }) }
      val w487 = { ...w486, inc: w486.inc.set(eId484, { ...w486.inc.get(eId484), slaBreached: true }) }
      w487
    })
    w482
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w488 = if (timerDef("reaction").startsOnce) {
      val w489 = ec_pauseTimer(w0, c, iid, "reaction")
      w489
    } else {
      val w490 = if (false) {
      val w491 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w492 = { ...w491, inc: w491.inc.set(iid, { ...w491.inc.get(iid), timers: w491.inc.get(iid).timers.set("reaction", { ...w491.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w493 = { ...w492, inc: w492.inc.set(iid, { ...w492.inc.get(iid), timers: w492.inc.get(iid).timers.set("reaction", { ...w492.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w494 = { ...w493, inc: w493.inc.set(iid, { ...w493.inc.get(iid), timers: w493.inc.get(iid).timers.set("reaction", { ...w493.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w494
    } else {
      val w495 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_496 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w497 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_496) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w498 = { ...w497, inc: w497.inc.set(iid, { ...w497.inc.get(iid), timers: w497.inc.get(iid).timers.set("reaction", { ...w497.inc.get(iid).timers.get("reaction"), paused: keep_496 }) }) }
      val w499 = { ...w498, inc: w498.inc.set(iid, { ...w498.inc.get(iid), timers: w498.inc.get(iid).timers.set("reaction", { ...w498.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w500 = { ...w499, inc: w499.inc.set(iid, { ...w499.inc.get(iid), timers: w499.inc.get(iid).timers.set("reaction", { ...w499.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w500
    }
      w495
    }
      w490
    }
    w488
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_501 = settings.alerts.target
    val w502 = if (((whom_501 != "") and (whom_501 != c.actor))) w0 else w0
    w502
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
    { val t_503 = world.inc.get(iid).timers.get("resolution")  (((t_503.due != 0) and (t_503.due <= c.now)) and (t_503.fired != t_503.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_504 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w505 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_504) }) }
    val w506 = { ...w505, inc: w505.inc.set(iid, { ...w505.inc.get(iid), slaBreached: true }) }
    val w507 = groupMembersAt(incs(w0), w506.inc.get(iid), c.deadline).foldl([], (acc, x510) => acc.append(x510.id)).foldl(w506, (wf508, eId509) => {
      val w511 = { ...wf508, inc: wf508.inc.set(eId509, { ...wf508.inc.get(eId509), breaches: wf508.inc.get(eId509).breaches.append(breach_504) }) }
      val w512 = { ...w511, inc: w511.inc.set(eId509, { ...w511.inc.get(eId509), slaBreached: true }) }
      w512
    })
    w507
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_513 = settings.alerts.target
    val w514 = if (((whom_513 != "") and (whom_513 != c.actor))) w0 else w0
    w514
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
    { val t_515 = world.inc.get(iid).timers.get("resolution")  (((t_515.due != 0) and (t_515.due <= c.now)) and (t_515.fired != t_515.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_516 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w517 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_516) }) }
    val w518 = { ...w517, inc: w517.inc.set(iid, { ...w517.inc.get(iid), slaBreached: true }) }
    val w519 = groupMembersAt(incs(w0), w518.inc.get(iid), c.deadline).foldl([], (acc, x522) => acc.append(x522.id)).foldl(w518, (wf520, eId521) => {
      val w523 = { ...wf520, inc: wf520.inc.set(eId521, { ...wf520.inc.get(eId521), breaches: wf520.inc.get(eId521).breaches.append(breach_516) }) }
      val w524 = { ...w523, inc: w523.inc.set(eId521, { ...w523.inc.get(eId521), slaBreached: true }) }
      w524
    })
    w519
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_525 = personOf(levelUpTarget(c.before))
    val w526 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_525 }) }
    w526
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_527 = groupOf(levelUpTarget(c.before))
    val w528 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_527 }) }
    w528
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_529 = levelUpNumber(c.before)
    val w530 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_529 }) }
    w530
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w531 = if (not(timerDef("resolution").pausable)) {
      val w532 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w533 = { ...w532, inc: w532.inc.set(iid, { ...w532.inc.get(iid), timers: w532.inc.get(iid).timers.set("resolution", { ...w532.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w533
    } else {
      val w534 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w535 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w536 = { ...w535, inc: w535.inc.set(iid, { ...w535.inc.get(iid), timers: w535.inc.get(iid).timers.set("resolution", { ...w535.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w537 = { ...w536, inc: w536.inc.set(iid, { ...w536.inc.get(iid), timers: w536.inc.get(iid).timers.set("resolution", { ...w536.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w537
    } else w0
      w534
    }
    w531
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w538 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w539 = if (timerDef("reaction").startsOnce) {
      val w540 = ec_resumeTimer(w0, c, iid, "reaction")
      w540
    } else {
      val w541 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w542 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w543 = { ...w542, inc: w542.inc.set(iid, { ...w542.inc.get(iid), timers: w542.inc.get(iid).timers.set("reaction", { ...w542.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w544 = { ...w543, inc: w543.inc.set(iid, { ...w543.inc.get(iid), timers: w543.inc.get(iid).timers.set("reaction", { ...w543.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w544
    } else {
      val sec_545 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w546 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_545 < 0)) 0 else (c.now + (sec_545 * 1000))) }) }) }
      val w547 = { ...w546, inc: w546.inc.set(iid, { ...w546.inc.get(iid), timers: w546.inc.get(iid).timers.set("reaction", { ...w546.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w548 = { ...w547, inc: w547.inc.set(iid, { ...w547.inc.get(iid), timers: w547.inc.get(iid).timers.set("reaction", { ...w547.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w549 = { ...w548, inc: w548.inc.set(iid, { ...w548.inc.get(iid), timers: w548.inc.get(iid).timers.set("reaction", { ...w548.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w549
    }
      w541
    }
      w539
    }
    w538
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_550 = c.before.owner
    val w551 = if (((whom_550 != "") and (whom_550 != c.actor))) w0 else w0
    w551
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_552 = addressee(w0.inc.get(iid))
    val w553 = if (((whom_552 != "") and (whom_552 != c.actor))) w0 else w0
    w553
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
    { val t_554 = world.inc.get(iid).timers.get("resolution")  (((t_554.due != 0) and (t_554.due <= c.now)) and (t_554.fired != t_554.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_555 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w556 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_555) }) }
    val w557 = { ...w556, inc: w556.inc.set(iid, { ...w556.inc.get(iid), slaBreached: true }) }
    val w558 = groupMembersAt(incs(w0), w557.inc.get(iid), c.deadline).foldl([], (acc, x561) => acc.append(x561.id)).foldl(w557, (wf559, eId560) => {
      val w562 = { ...wf559, inc: wf559.inc.set(eId560, { ...wf559.inc.get(eId560), breaches: wf559.inc.get(eId560).breaches.append(breach_555) }) }
      val w563 = { ...w562, inc: w562.inc.set(eId560, { ...w562.inc.get(eId560), slaBreached: true }) }
      w563
    })
    w558
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_564 = settings.alerts.target
    val w565 = if (((whom_564 != "") and (whom_564 != c.actor))) w0 else w0
    w565
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
    { val t_566 = world.inc.get(iid).timers.get("hold")  (((t_566.due != 0) and (t_566.due <= c.now)) and (t_566.fired != t_566.due)) },
    not(["break", "no_link"].foldl(false, (acc, y567) => acc or y567 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_568 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w569 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_568) }) }
    val w570 = { ...w569, inc: w569.inc.set(iid, { ...w569.inc.get(iid), slaBreached: true }) }
    val w571 = groupMembersAt(incs(w0), w570.inc.get(iid), c.deadline).foldl([], (acc, x574) => acc.append(x574.id)).foldl(w570, (wf572, eId573) => {
      val w575 = { ...wf572, inc: wf572.inc.set(eId573, { ...wf572.inc.get(eId573), breaches: wf572.inc.get(eId573).breaches.append(breach_568) }) }
      val w576 = { ...w575, inc: w575.inc.set(eId573, { ...w575.inc.get(eId573), slaBreached: true }) }
      w576
    })
    w571
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_577 = settings.alerts.target
    val w578 = if (((whom_577 != "") and (whom_577 != c.actor))) w0 else w0
    w578
  }

  def apply_hold_overdue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_hold_overdue_0(w0, c1, iid)
    val w2 = e_hold_overdue_1(w1, c1, iid)
    val w3 = e_hold_overdue_2(w2, c1, iid)
    w3
  }

  // break_hold_release: timer → new

  def ok_break_hold_release(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    { val t_579 = world.inc.get(iid).timers.get("hold")  (((t_579.due != 0) and (t_579.due <= c.now)) and (t_579.fired != t_579.due)) },
    ["break"].foldl(false, (acc, y580) => acc or y580 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_581 = ""
    val w582 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_581 }) }
    w582
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w583 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w583
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w584 = if (timerDef("hold").startsOnce) {
      val w585 = ec_pauseTimer(w0, c, iid, "hold")
      w585
    } else {
      val w586 = if (false) {
      val w587 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w588 = { ...w587, inc: w587.inc.set(iid, { ...w587.inc.get(iid), timers: w587.inc.get(iid).timers.set("hold", { ...w587.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w589 = { ...w588, inc: w588.inc.set(iid, { ...w588.inc.get(iid), timers: w588.inc.get(iid).timers.set("hold", { ...w588.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w590 = { ...w589, inc: w589.inc.set(iid, { ...w589.inc.get(iid), timers: w589.inc.get(iid).timers.set("hold", { ...w589.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w590
    } else {
      val w591 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_592 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w593 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_592) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w594 = { ...w593, inc: w593.inc.set(iid, { ...w593.inc.get(iid), timers: w593.inc.get(iid).timers.set("hold", { ...w593.inc.get(iid).timers.get("hold"), paused: keep_592 }) }) }
      val w595 = { ...w594, inc: w594.inc.set(iid, { ...w594.inc.get(iid), timers: w594.inc.get(iid).timers.set("hold", { ...w594.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w596 = { ...w595, inc: w595.inc.set(iid, { ...w595.inc.get(iid), timers: w595.inc.get(iid).timers.set("hold", { ...w595.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w596
    }
      w591
    }
      w586
    }
    w584
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w597 = if (not(timerDef("resolution").pausable)) {
      val w598 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w599 = { ...w598, inc: w598.inc.set(iid, { ...w598.inc.get(iid), timers: w598.inc.get(iid).timers.set("resolution", { ...w598.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w599
    } else {
      val w600 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w601 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w602 = { ...w601, inc: w601.inc.set(iid, { ...w601.inc.get(iid), timers: w601.inc.get(iid).timers.set("resolution", { ...w601.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w603 = { ...w602, inc: w602.inc.set(iid, { ...w602.inc.get(iid), timers: w602.inc.get(iid).timers.set("resolution", { ...w602.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w603
    } else w0
      w600
    }
    w597
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w604 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w605 = if (timerDef("reaction").startsOnce) {
      val w606 = ec_resumeTimer(w0, c, iid, "reaction")
      w606
    } else {
      val w607 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w608 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w609 = { ...w608, inc: w608.inc.set(iid, { ...w608.inc.get(iid), timers: w608.inc.get(iid).timers.set("reaction", { ...w608.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w610 = { ...w609, inc: w609.inc.set(iid, { ...w609.inc.get(iid), timers: w609.inc.get(iid).timers.set("reaction", { ...w609.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w610
    } else {
      val sec_611 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w612 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_611 < 0)) 0 else (c.now + (sec_611 * 1000))) }) }) }
      val w613 = { ...w612, inc: w612.inc.set(iid, { ...w612.inc.get(iid), timers: w612.inc.get(iid).timers.set("reaction", { ...w612.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w614 = { ...w613, inc: w613.inc.set(iid, { ...w613.inc.get(iid), timers: w613.inc.get(iid).timers.set("reaction", { ...w613.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w615 = { ...w614, inc: w614.inc.set(iid, { ...w614.inc.get(iid), timers: w614.inc.get(iid).timers.set("reaction", { ...w614.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w615
    }
      w607
    }
      w605
    }
    w604
  }

  def e_break_hold_release_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_break_hold_release_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_break_hold_release(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_break_hold_release_0(ws, c1, iid)
    val w2 = e_break_hold_release_1(w1, c1, iid)
    val w3 = e_break_hold_release_2(w2, c1, iid)
    val w4 = e_break_hold_release_3(w3, c1, iid)
    val w5 = e_break_hold_release_4(w4, c1, iid)
    val w6 = e_break_hold_release_5(w5, c1, iid)
    val w7 = e_break_hold_release_6(w6, c1, iid)
    w7
  }

  // system_hold_break: system → on_hold

  def ok_system_hold_break(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (agentState(c.me) == "not_ready"),
  }

  def e_system_hold_break_0(w0: World, c: Ctx, iid: str): World = {
    val reason_616 = "break"
    val w617 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_616 }) }
    w617
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w618 = if (not(timerDef("resolution").pausable)) {
      val w619 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w620 = { ...w619, inc: w619.inc.set(iid, { ...w619.inc.get(iid), timers: w619.inc.get(iid).timers.set("resolution", { ...w619.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w620
    } else {
      val w621 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w622 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w623 = { ...w622, inc: w622.inc.set(iid, { ...w622.inc.get(iid), timers: w622.inc.get(iid).timers.set("resolution", { ...w622.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w624 = { ...w623, inc: w623.inc.set(iid, { ...w623.inc.get(iid), timers: w623.inc.get(iid).timers.set("resolution", { ...w623.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w624
    } else w0
      w621
    }
    w618
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w625 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w626 = if (timerDef("hold").startsOnce) {
      val w627 = ec_resumeTimer(w0, c, iid, "hold")
      w627
    } else {
      val w628 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w629 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w630 = { ...w629, inc: w629.inc.set(iid, { ...w629.inc.get(iid), timers: w629.inc.get(iid).timers.set("hold", { ...w629.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w631 = { ...w630, inc: w630.inc.set(iid, { ...w630.inc.get(iid), timers: w630.inc.get(iid).timers.set("hold", { ...w630.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w631
    } else {
      val sec_632 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w633 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_632 < 0)) 0 else (c.now + (sec_632 * 1000))) }) }) }
      val w634 = { ...w633, inc: w633.inc.set(iid, { ...w633.inc.get(iid), timers: w633.inc.get(iid).timers.set("hold", { ...w633.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w635 = { ...w634, inc: w634.inc.set(iid, { ...w634.inc.get(iid), timers: w634.inc.get(iid).timers.set("hold", { ...w634.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w636 = { ...w635, inc: w635.inc.set(iid, { ...w635.inc.get(iid), timers: w635.inc.get(iid).timers.set("hold", { ...w635.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w636
    }
      w628
    }
      w626
    }
    w625
  }

  def e_system_hold_break_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_system_hold_break(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "on_hold" }) }
    val w1 = e_system_hold_break_0(ws, c1, iid)
    val w2 = e_system_hold_break_1(w1, c1, iid)
    val w3 = e_system_hold_break_2(w2, c1, iid)
    val w4 = e_system_hold_break_3(w3, c1, iid)
    w4
  }

  // system_hold_idle: system → on_hold

  def ok_system_hold_idle(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (idleSec(c.me) >= settings.session.idleHoldSec),
  }

  def e_system_hold_idle_0(w0: World, c: Ctx, iid: str): World = {
    val reason_637 = "no_link"
    val w638 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_637 }) }
    w638
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w639 = if (not(timerDef("resolution").pausable)) {
      val w640 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w641 = { ...w640, inc: w640.inc.set(iid, { ...w640.inc.get(iid), timers: w640.inc.get(iid).timers.set("resolution", { ...w640.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w641
    } else {
      val w642 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w643 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w644 = { ...w643, inc: w643.inc.set(iid, { ...w643.inc.get(iid), timers: w643.inc.get(iid).timers.set("resolution", { ...w643.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w645 = { ...w644, inc: w644.inc.set(iid, { ...w644.inc.get(iid), timers: w644.inc.get(iid).timers.set("resolution", { ...w644.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w645
    } else w0
      w642
    }
    w639
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w646 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w647 = if (timerDef("hold").startsOnce) {
      val w648 = ec_resumeTimer(w0, c, iid, "hold")
      w648
    } else {
      val w649 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w650 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w651 = { ...w650, inc: w650.inc.set(iid, { ...w650.inc.get(iid), timers: w650.inc.get(iid).timers.set("hold", { ...w650.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w652 = { ...w651, inc: w651.inc.set(iid, { ...w651.inc.get(iid), timers: w651.inc.get(iid).timers.set("hold", { ...w651.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w652
    } else {
      val sec_653 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w654 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_653 < 0)) 0 else (c.now + (sec_653 * 1000))) }) }) }
      val w655 = { ...w654, inc: w654.inc.set(iid, { ...w654.inc.get(iid), timers: w654.inc.get(iid).timers.set("hold", { ...w654.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w656 = { ...w655, inc: w655.inc.set(iid, { ...w655.inc.get(iid), timers: w655.inc.get(iid).timers.set("hold", { ...w655.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w657 = { ...w656, inc: w656.inc.set(iid, { ...w656.inc.get(iid), timers: w656.inc.get(iid).timers.set("hold", { ...w656.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w657
    }
      w649
    }
      w647
    }
    w646
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_658 = settings.alerts.target
    val w659 = if (((whom_658 != "") and (whom_658 != c.actor))) w0 else w0
    w659
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
    ["break", "no_link"].foldl(false, (acc, y660) => acc or y660 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_661 = ""
    val w662 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_661 }) }
    w662
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w663 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w663
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w664 = if (timerDef("hold").startsOnce) {
      val w665 = ec_pauseTimer(w0, c, iid, "hold")
      w665
    } else {
      val w666 = if (false) {
      val w667 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w668 = { ...w667, inc: w667.inc.set(iid, { ...w667.inc.get(iid), timers: w667.inc.get(iid).timers.set("hold", { ...w667.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w669 = { ...w668, inc: w668.inc.set(iid, { ...w668.inc.get(iid), timers: w668.inc.get(iid).timers.set("hold", { ...w668.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w670 = { ...w669, inc: w669.inc.set(iid, { ...w669.inc.get(iid), timers: w669.inc.get(iid).timers.set("hold", { ...w669.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w670
    } else {
      val w671 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_672 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w673 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_672) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w674 = { ...w673, inc: w673.inc.set(iid, { ...w673.inc.get(iid), timers: w673.inc.get(iid).timers.set("hold", { ...w673.inc.get(iid).timers.get("hold"), paused: keep_672 }) }) }
      val w675 = { ...w674, inc: w674.inc.set(iid, { ...w674.inc.get(iid), timers: w674.inc.get(iid).timers.set("hold", { ...w674.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w676 = { ...w675, inc: w675.inc.set(iid, { ...w675.inc.get(iid), timers: w675.inc.get(iid).timers.set("hold", { ...w675.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w676
    }
      w671
    }
      w666
    }
    w664
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w677 = if (not(timerDef("resolution").pausable)) {
      val w678 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w679 = { ...w678, inc: w678.inc.set(iid, { ...w678.inc.get(iid), timers: w678.inc.get(iid).timers.set("resolution", { ...w678.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w679
    } else {
      val w680 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w681 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w682 = { ...w681, inc: w681.inc.set(iid, { ...w681.inc.get(iid), timers: w681.inc.get(iid).timers.set("resolution", { ...w681.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w683 = { ...w682, inc: w682.inc.set(iid, { ...w682.inc.get(iid), timers: w682.inc.get(iid).timers.set("resolution", { ...w682.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w683
    } else w0
      w680
    }
    w677
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w684 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w685 = if (timerDef("reaction").startsOnce) {
      val w686 = ec_resumeTimer(w0, c, iid, "reaction")
      w686
    } else {
      val w687 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w688 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w689 = { ...w688, inc: w688.inc.set(iid, { ...w688.inc.get(iid), timers: w688.inc.get(iid).timers.set("reaction", { ...w688.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w690 = { ...w689, inc: w689.inc.set(iid, { ...w689.inc.get(iid), timers: w689.inc.get(iid).timers.set("reaction", { ...w689.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w690
    } else {
      val sec_691 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w692 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_691 < 0)) 0 else (c.now + (sec_691 * 1000))) }) }) }
      val w693 = { ...w692, inc: w692.inc.set(iid, { ...w692.inc.get(iid), timers: w692.inc.get(iid).timers.set("reaction", { ...w692.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w694 = { ...w693, inc: w693.inc.set(iid, { ...w693.inc.get(iid), timers: w693.inc.get(iid).timers.set("reaction", { ...w693.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w695 = { ...w694, inc: w694.inc.set(iid, { ...w694.inc.get(iid), timers: w694.inc.get(iid).timers.set("reaction", { ...w694.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w695
    }
      w687
    }
      w685
    }
    w684
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

  // no_link_hold_release: timer → new

  def ok_no_link_hold_release(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    { val t_696 = world.inc.get(iid).timers.get("hold")  (((t_696.due != 0) and (t_696.due <= c.now)) and (t_696.fired != t_696.due)) },
    ["no_link"].foldl(false, (acc, y697) => acc or y697 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_698 = ""
    val w699 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_698 }) }
    w699
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w700 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w700
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w701 = if (timerDef("hold").startsOnce) {
      val w702 = ec_pauseTimer(w0, c, iid, "hold")
      w702
    } else {
      val w703 = if (false) {
      val w704 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w705 = { ...w704, inc: w704.inc.set(iid, { ...w704.inc.get(iid), timers: w704.inc.get(iid).timers.set("hold", { ...w704.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w706 = { ...w705, inc: w705.inc.set(iid, { ...w705.inc.get(iid), timers: w705.inc.get(iid).timers.set("hold", { ...w705.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w707 = { ...w706, inc: w706.inc.set(iid, { ...w706.inc.get(iid), timers: w706.inc.get(iid).timers.set("hold", { ...w706.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w707
    } else {
      val w708 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_709 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w710 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_709) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w711 = { ...w710, inc: w710.inc.set(iid, { ...w710.inc.get(iid), timers: w710.inc.get(iid).timers.set("hold", { ...w710.inc.get(iid).timers.get("hold"), paused: keep_709 }) }) }
      val w712 = { ...w711, inc: w711.inc.set(iid, { ...w711.inc.get(iid), timers: w711.inc.get(iid).timers.set("hold", { ...w711.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w713 = { ...w712, inc: w712.inc.set(iid, { ...w712.inc.get(iid), timers: w712.inc.get(iid).timers.set("hold", { ...w712.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w713
    }
      w708
    }
      w703
    }
    w701
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w714 = if (not(timerDef("resolution").pausable)) {
      val w715 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w716 = { ...w715, inc: w715.inc.set(iid, { ...w715.inc.get(iid), timers: w715.inc.get(iid).timers.set("resolution", { ...w715.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w716
    } else {
      val w717 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w718 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w719 = { ...w718, inc: w718.inc.set(iid, { ...w718.inc.get(iid), timers: w718.inc.get(iid).timers.set("resolution", { ...w718.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w720 = { ...w719, inc: w719.inc.set(iid, { ...w719.inc.get(iid), timers: w719.inc.get(iid).timers.set("resolution", { ...w719.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w720
    } else w0
      w717
    }
    w714
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w721 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w722 = if (timerDef("reaction").startsOnce) {
      val w723 = ec_resumeTimer(w0, c, iid, "reaction")
      w723
    } else {
      val w724 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w725 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w726 = { ...w725, inc: w725.inc.set(iid, { ...w725.inc.get(iid), timers: w725.inc.get(iid).timers.set("reaction", { ...w725.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w727 = { ...w726, inc: w726.inc.set(iid, { ...w726.inc.get(iid), timers: w726.inc.get(iid).timers.set("reaction", { ...w726.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w727
    } else {
      val sec_728 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w729 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_728 < 0)) 0 else (c.now + (sec_728 * 1000))) }) }) }
      val w730 = { ...w729, inc: w729.inc.set(iid, { ...w729.inc.get(iid), timers: w729.inc.get(iid).timers.set("reaction", { ...w729.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w731 = { ...w730, inc: w730.inc.set(iid, { ...w730.inc.get(iid), timers: w730.inc.get(iid).timers.set("reaction", { ...w730.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w732 = { ...w731, inc: w731.inc.set(iid, { ...w731.inc.get(iid), timers: w731.inc.get(iid).timers.set("reaction", { ...w731.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w732
    }
      w724
    }
      w722
    }
    w721
  }

  def e_no_link_hold_release_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_no_link_hold_release_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_no_link_hold_release(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_no_link_hold_release_0(ws, c1, iid)
    val w2 = e_no_link_hold_release_1(w1, c1, iid)
    val w3 = e_no_link_hold_release_2(w2, c1, iid)
    val w4 = e_no_link_hold_release_3(w3, c1, iid)
    val w5 = e_no_link_hold_release_4(w4, c1, iid)
    val w6 = e_no_link_hold_release_5(w5, c1, iid)
    val w7 = e_no_link_hold_release_6(w6, c1, iid)
    w7
  }

  // addressee_signed_out_to_group: system → pending_acceptance

  def ok_addressee_signed_out_to_group(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    (agentState(c.me) == "offline"),
    (((world.inc.get(iid).owner != "") and (dutyGroupOf(world.inc.get(iid).owner) != "")) == true),
  }

  def e_addressee_signed_out_to_group_0(w0: World, c: Ctx, iid: str): World = {
    val group_733 = dutyGroupOf(w0.inc.get(iid).owner)
    val w734 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_733 }) }
    w734
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_735 = ""
    val w736 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_735 }) }
    w736
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_737 = addressee(w0.inc.get(iid))
    val w738 = if (((whom_737 != "") and (whom_737 != c.actor))) w0 else w0
    w738
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
    val who_739 = ""
    val w740 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_739 }) }
    w740
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
    val who_741 = ""
    val w742 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_741 }) }
    w742
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w743 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w743
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w744 = if (timerDef("hold").startsOnce) {
      val w745 = ec_pauseTimer(w0, c, iid, "hold")
      w745
    } else {
      val w746 = if (false) {
      val w747 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w748 = { ...w747, inc: w747.inc.set(iid, { ...w747.inc.get(iid), timers: w747.inc.get(iid).timers.set("hold", { ...w747.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w749 = { ...w748, inc: w748.inc.set(iid, { ...w748.inc.get(iid), timers: w748.inc.get(iid).timers.set("hold", { ...w748.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w750 = { ...w749, inc: w749.inc.set(iid, { ...w749.inc.get(iid), timers: w749.inc.get(iid).timers.set("hold", { ...w749.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w750
    } else {
      val w751 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_752 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w753 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_752) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w754 = { ...w753, inc: w753.inc.set(iid, { ...w753.inc.get(iid), timers: w753.inc.get(iid).timers.set("hold", { ...w753.inc.get(iid).timers.get("hold"), paused: keep_752 }) }) }
      val w755 = { ...w754, inc: w754.inc.set(iid, { ...w754.inc.get(iid), timers: w754.inc.get(iid).timers.set("hold", { ...w754.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w756 = { ...w755, inc: w755.inc.set(iid, { ...w755.inc.get(iid), timers: w755.inc.get(iid).timers.set("hold", { ...w755.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w756
    }
      w751
    }
      w746
    }
    w744
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w757 = if (not(timerDef("resolution").pausable)) {
      val w758 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w759 = { ...w758, inc: w758.inc.set(iid, { ...w758.inc.get(iid), timers: w758.inc.get(iid).timers.set("resolution", { ...w758.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w759
    } else {
      val w760 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w761 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w762 = { ...w761, inc: w761.inc.set(iid, { ...w761.inc.get(iid), timers: w761.inc.get(iid).timers.set("resolution", { ...w761.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w763 = { ...w762, inc: w762.inc.set(iid, { ...w762.inc.get(iid), timers: w762.inc.get(iid).timers.set("resolution", { ...w762.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w763
    } else w0
      w760
    }
    w757
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w764 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w765 = if (timerDef("reaction").startsOnce) {
      val w766 = ec_resumeTimer(w0, c, iid, "reaction")
      w766
    } else {
      val w767 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w768 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w769 = { ...w768, inc: w768.inc.set(iid, { ...w768.inc.get(iid), timers: w768.inc.get(iid).timers.set("reaction", { ...w768.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w770 = { ...w769, inc: w769.inc.set(iid, { ...w769.inc.get(iid), timers: w769.inc.get(iid).timers.set("reaction", { ...w769.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w770
    } else {
      val sec_771 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w772 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_771 < 0)) 0 else (c.now + (sec_771 * 1000))) }) }) }
      val w773 = { ...w772, inc: w772.inc.set(iid, { ...w772.inc.get(iid), timers: w772.inc.get(iid).timers.set("reaction", { ...w772.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w774 = { ...w773, inc: w773.inc.set(iid, { ...w773.inc.get(iid), timers: w773.inc.get(iid).timers.set("reaction", { ...w773.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w775 = { ...w774, inc: w774.inc.set(iid, { ...w774.inc.get(iid), timers: w774.inc.get(iid).timers.set("reaction", { ...w774.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w775
    }
      w767
    }
      w765
    }
    w764
  }

  def e_owner_signed_out_5(w0: World, c: Ctx, iid: str): World = {

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
    w6
  }

  // addressee_lost_access: system → new

  def ok_addressee_lost_access(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    ((addressee(world.inc.get(iid)) != "") and (hasAccess(addressee(world.inc.get(iid)), world.inc.get(iid)) == false)),
  }

  def e_addressee_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val who_776 = ""
    val w777 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_776 }) }
    w777
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_778 = ""
    val w779 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_778 }) }
    w779
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w780 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w780
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w781 = if (timerDef("hold").startsOnce) {
      val w782 = ec_pauseTimer(w0, c, iid, "hold")
      w782
    } else {
      val w783 = if (false) {
      val w784 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w785 = { ...w784, inc: w784.inc.set(iid, { ...w784.inc.get(iid), timers: w784.inc.get(iid).timers.set("hold", { ...w784.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w786 = { ...w785, inc: w785.inc.set(iid, { ...w785.inc.get(iid), timers: w785.inc.get(iid).timers.set("hold", { ...w785.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w787 = { ...w786, inc: w786.inc.set(iid, { ...w786.inc.get(iid), timers: w786.inc.get(iid).timers.set("hold", { ...w786.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w787
    } else {
      val w788 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_789 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w790 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_789) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w791 = { ...w790, inc: w790.inc.set(iid, { ...w790.inc.get(iid), timers: w790.inc.get(iid).timers.set("hold", { ...w790.inc.get(iid).timers.get("hold"), paused: keep_789 }) }) }
      val w792 = { ...w791, inc: w791.inc.set(iid, { ...w791.inc.get(iid), timers: w791.inc.get(iid).timers.set("hold", { ...w791.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w793 = { ...w792, inc: w792.inc.set(iid, { ...w792.inc.get(iid), timers: w792.inc.get(iid).timers.set("hold", { ...w792.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w793
    }
      w788
    }
      w783
    }
    w781
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w794 = if (not(timerDef("resolution").pausable)) {
      val w795 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w796 = { ...w795, inc: w795.inc.set(iid, { ...w795.inc.get(iid), timers: w795.inc.get(iid).timers.set("resolution", { ...w795.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w796
    } else {
      val w797 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w798 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w799 = { ...w798, inc: w798.inc.set(iid, { ...w798.inc.get(iid), timers: w798.inc.get(iid).timers.set("resolution", { ...w798.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w800 = { ...w799, inc: w799.inc.set(iid, { ...w799.inc.get(iid), timers: w799.inc.get(iid).timers.set("resolution", { ...w799.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w800
    } else w0
      w797
    }
    w794
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w801 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w802 = if (timerDef("reaction").startsOnce) {
      val w803 = ec_resumeTimer(w0, c, iid, "reaction")
      w803
    } else {
      val w804 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w805 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w806 = { ...w805, inc: w805.inc.set(iid, { ...w805.inc.get(iid), timers: w805.inc.get(iid).timers.set("reaction", { ...w805.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w807 = { ...w806, inc: w806.inc.set(iid, { ...w806.inc.get(iid), timers: w806.inc.get(iid).timers.set("reaction", { ...w806.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w807
    } else {
      val sec_808 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w809 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_808 < 0)) 0 else (c.now + (sec_808 * 1000))) }) }) }
      val w810 = { ...w809, inc: w809.inc.set(iid, { ...w809.inc.get(iid), timers: w809.inc.get(iid).timers.set("reaction", { ...w809.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w811 = { ...w810, inc: w810.inc.set(iid, { ...w810.inc.get(iid), timers: w810.inc.get(iid).timers.set("reaction", { ...w810.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w812 = { ...w811, inc: w811.inc.set(iid, { ...w811.inc.get(iid), timers: w811.inc.get(iid).timers.set("reaction", { ...w811.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w812
    }
      w804
    }
      w802
    }
    w801
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_813 = settings.alerts.target
    val w814 = if (((whom_813 != "") and (whom_813 != c.actor))) w0 else w0
    w814
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
    val who_815 = ""
    val w816 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_815 }) }
    w816
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_817 = ""
    val w818 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_817 }) }
    w818
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w819 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w820 = if (timerDef("reaction").startsOnce) {
      val w821 = ec_resumeTimer(w0, c, iid, "reaction")
      w821
    } else {
      val w822 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w823 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w824 = { ...w823, inc: w823.inc.set(iid, { ...w823.inc.get(iid), timers: w823.inc.get(iid).timers.set("reaction", { ...w823.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w825 = { ...w824, inc: w824.inc.set(iid, { ...w824.inc.get(iid), timers: w824.inc.get(iid).timers.set("reaction", { ...w824.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w825
    } else {
      val sec_826 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w827 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_826 < 0)) 0 else (c.now + (sec_826 * 1000))) }) }) }
      val w828 = { ...w827, inc: w827.inc.set(iid, { ...w827.inc.get(iid), timers: w827.inc.get(iid).timers.set("reaction", { ...w827.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w829 = { ...w828, inc: w828.inc.set(iid, { ...w828.inc.get(iid), timers: w828.inc.get(iid).timers.set("reaction", { ...w828.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w830 = { ...w829, inc: w829.inc.set(iid, { ...w829.inc.get(iid), timers: w829.inc.get(iid).timers.set("reaction", { ...w829.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w830
    }
      w822
    }
      w820
    }
    w819
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_831 = settings.alerts.target
    val w832 = if (((whom_831 != "") and (whom_831 != c.actor))) w0 else w0
    w832
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
    not(settings.session.states.foldl(false, (acc, s_833) => acc or ((s_833.id == agentState(c.me)) and s_833.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_834 = incidentById(incs(world), c.form.primaryId)  ((((ps_834.length() > 0) and (ps_834[0].id != world.inc.get(iid).id)) and (ps_834[0].linkedTo == "")) and ((ps_834[0].state == "new") or ((ps_834[0].state == "in_progress") and (ps_834[0].owner == c.me)))) },
    { val ps_835 = incidentById(incs(world), c.form.primaryId)  ((ps_835.length() > 0) and (ps_835[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w836 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w836
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_837 = incidentById(incs(w0), c.form.primaryId)
    val w838 = if ((ps_837.length() > 0)) {
      val w839 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_846 => not(isDone(e_846))).foldl([], (acc, x842) => acc.append(x842.id)).foldl(w0, (wf840, cId841) => {
      val w843 = { ...wf840, inc: wf840.inc.set(cId841, { ...wf840.inc.get(cId841), leftGroup: { primaryId: wf840.inc.get(cId841).linkedTo, linkedAt: wf840.inc.get(cId841).linkedAt, at: c.now } }) }
      val w844 = { ...w843, inc: w843.inc.set(cId841, { ...w843.inc.get(cId841), linkedTo: ps_837[0].id }) }
      val w845 = { ...w844, inc: w844.inc.set(cId841, { ...w844.inc.get(cId841), linkedAt: c.now }) }
      w845
    })
      w839
    } else w0
    w838
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_847 = c.form.primaryId
    val w848 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_847 }) }
    val w849 = { ...w848, inc: w848.inc.set(iid, { ...w848.inc.get(iid), linkedAt: c.now }) }
    w849
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_850 = ""
    val w851 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_850 }) }
    w851
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_852 = ""
    val w853 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_852 }) }
    w853
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w854 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w854
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w855 = if (timerDef("reaction").startsOnce) {
      val w856 = ec_pauseTimer(w0, c, iid, "reaction")
      w856
    } else {
      val w857 = if (false) {
      val w858 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w859 = { ...w858, inc: w858.inc.set(iid, { ...w858.inc.get(iid), timers: w858.inc.get(iid).timers.set("reaction", { ...w858.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w860 = { ...w859, inc: w859.inc.set(iid, { ...w859.inc.get(iid), timers: w859.inc.get(iid).timers.set("reaction", { ...w859.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w861 = { ...w860, inc: w860.inc.set(iid, { ...w860.inc.get(iid), timers: w860.inc.get(iid).timers.set("reaction", { ...w860.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w861
    } else {
      val w862 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_863 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w864 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_863) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w865 = { ...w864, inc: w864.inc.set(iid, { ...w864.inc.get(iid), timers: w864.inc.get(iid).timers.set("reaction", { ...w864.inc.get(iid).timers.get("reaction"), paused: keep_863 }) }) }
      val w866 = { ...w865, inc: w865.inc.set(iid, { ...w865.inc.get(iid), timers: w865.inc.get(iid).timers.set("reaction", { ...w865.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w867 = { ...w866, inc: w866.inc.set(iid, { ...w866.inc.get(iid), timers: w866.inc.get(iid).timers.set("reaction", { ...w866.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w867
    }
      w862
    }
      w857
    }
    w855
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w868 = if (not(timerDef("resolution").pausable)) {
      val w869 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w870 = { ...w869, inc: w869.inc.set(iid, { ...w869.inc.get(iid), timers: w869.inc.get(iid).timers.set("resolution", { ...w869.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w870
    } else {
      val w871 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w872 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w873 = { ...w872, inc: w872.inc.set(iid, { ...w872.inc.get(iid), timers: w872.inc.get(iid).timers.set("resolution", { ...w872.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w874 = { ...w873, inc: w873.inc.set(iid, { ...w873.inc.get(iid), timers: w873.inc.get(iid).timers.set("resolution", { ...w873.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w874
    } else w0
      w871
    }
    w868
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_875 = incidentById(incs(w0), c.form.primaryId)
    val w876 = if (((((ps_875.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_875[0], "resolution", c.now)))) {
      val t_877 = ps_875[0].timers.get("resolution")
      val left_878 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_879 = (if ((t_877.due != 0)) (t_877.due - c.now) else (if (t_877.paused) t_877.left else (timerSec(ps_875[0], "resolution", "") * 1000)))
      val w880 = if ((left_878 < was_879)) {
      val w881 = ps_875.foldl([], (acc, x884) => acc.append(x884.id)).foldl(w0, (wf882, pId883) => {
      val w885 = if ((t_877.due != 0)) {
      val w886 = { ...wf882, inc: wf882.inc.set(pId883, { ...wf882.inc.get(pId883), timers: wf882.inc.get(pId883).timers.set("resolution", { ...wf882.inc.get(pId883).timers.get("resolution"), due: (c.now + left_878) }) }) }
      w886
    } else {
      val w887 = { ...wf882, inc: wf882.inc.set(pId883, { ...wf882.inc.get(pId883), timers: wf882.inc.get(pId883).timers.set("resolution", { ...wf882.inc.get(pId883).timers.get("resolution"), left: left_878 }) }) }
      val w888 = { ...w887, inc: w887.inc.set(pId883, { ...w887.inc.get(pId883), timers: w887.inc.get(pId883).timers.set("resolution", { ...w887.inc.get(pId883).timers.get("resolution"), paused: true }) }) }
      w888
    }
      w885
    })
      w881
    } else w0
      w880
    } else w0
    w876
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w889 = if (timerDef("hold").startsOnce) {
      val w890 = ec_pauseTimer(w0, c, iid, "hold")
      w890
    } else {
      val w891 = if (false) {
      val w892 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w893 = { ...w892, inc: w892.inc.set(iid, { ...w892.inc.get(iid), timers: w892.inc.get(iid).timers.set("hold", { ...w892.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w894 = { ...w893, inc: w893.inc.set(iid, { ...w893.inc.get(iid), timers: w893.inc.get(iid).timers.set("hold", { ...w893.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w895 = { ...w894, inc: w894.inc.set(iid, { ...w894.inc.get(iid), timers: w894.inc.get(iid).timers.set("hold", { ...w894.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w895
    } else {
      val w896 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_897 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w898 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_897) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w899 = { ...w898, inc: w898.inc.set(iid, { ...w898.inc.get(iid), timers: w898.inc.get(iid).timers.set("hold", { ...w898.inc.get(iid).timers.get("hold"), paused: keep_897 }) }) }
      val w900 = { ...w899, inc: w899.inc.set(iid, { ...w899.inc.get(iid), timers: w899.inc.get(iid).timers.set("hold", { ...w899.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w901 = { ...w900, inc: w900.inc.set(iid, { ...w900.inc.get(iid), timers: w900.inc.get(iid).timers.set("hold", { ...w900.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w901
    }
      w896
    }
      w891
    }
    w889
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
    not(settings.session.states.foldl(false, (acc, s_902) => acc or ((s_902.id == agentState(c.me)) and s_902.readOnly))),
    { val ps_903 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_903.length() > 0) and ((ownership(c.me, ps_903[0]) == "owner") or unowned(ps_903[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_904 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w905 = if (((ps_904.length() > 0) and (leftOf(ps_904[0], "resolution", c.now) >= 0))) {
      val w906 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w907 = { ...w906, inc: w906.inc.set(iid, { ...w906.inc.get(iid), timers: w906.inc.get(iid).timers.set("resolution", { ...w906.inc.get(iid).timers.get("resolution"), left: leftOf(ps_904[0], "resolution", c.now) }) }) }
      val w908 = { ...w907, inc: w907.inc.set(iid, { ...w907.inc.get(iid), timers: w907.inc.get(iid).timers.set("resolution", { ...w907.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w909 = if ((leftOf(ps_904[0], "resolution", c.now) == 0)) {
      val w910 = { ...w908, inc: w908.inc.set(iid, { ...w908.inc.get(iid), timers: w908.inc.get(iid).timers.set("resolution", { ...w908.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_904[0], "resolution", c.now)) ps_904[0].timers.get("resolution").fired else ps_904[0].timers.get("resolution").due) }) }) }
      w910
    } else w908
      w909
    } else w0
    w905
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w911 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_912 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w913 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w914 = { ...w913, inc: w913.inc.set(iid, { ...w913.inc.get(iid), linkedTo: "" }) }
      val w915 = { ...w914, inc: w914.inc.set(iid, { ...w914.inc.get(iid), linkedAt: 0 }) }
      val w916 = if (((ps_912.length() > 0) and ("" != ""))) w915 else w915
      val w917 = if (("" != "")) {
      val w918 = ps_912.foldl([], (acc, x921) => acc.append(x921.id)).foldl(w916, (wf919, pId920) => wf919)
      w918
    } else w916
      w917
    } else {
      val w922 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w923 = { ...w922, inc: w922.inc.set(iid, { ...w922.inc.get(iid), linkedAt: 0 }) }
      w923
    }
    w911
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w924 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w925 = if (timerDef("reaction").startsOnce) {
      val w926 = ec_resumeTimer(w0, c, iid, "reaction")
      w926
    } else {
      val w927 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w928 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w929 = { ...w928, inc: w928.inc.set(iid, { ...w928.inc.get(iid), timers: w928.inc.get(iid).timers.set("reaction", { ...w928.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w930 = { ...w929, inc: w929.inc.set(iid, { ...w929.inc.get(iid), timers: w929.inc.get(iid).timers.set("reaction", { ...w929.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w930
    } else {
      val sec_931 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w932 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_931 < 0)) 0 else (c.now + (sec_931 * 1000))) }) }) }
      val w933 = { ...w932, inc: w932.inc.set(iid, { ...w932.inc.get(iid), timers: w932.inc.get(iid).timers.set("reaction", { ...w932.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w934 = { ...w933, inc: w933.inc.set(iid, { ...w933.inc.get(iid), timers: w933.inc.get(iid).timers.set("reaction", { ...w933.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w935 = { ...w934, inc: w934.inc.set(iid, { ...w934.inc.get(iid), timers: w934.inc.get(iid).timers.set("reaction", { ...w934.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w935
    }
      w927
    }
      w925
    }
    w924
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
    { val ps_936 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_936.length() > 0) and isDone(ps_936[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_937 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w938 = if ((ps_937.length() > 0)) {
      val w939 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_937[0].closeResultId }) }
      val w940 = { ...w939, inc: w939.inc.set(iid, { ...w939.inc.get(iid), closeCauseId: ps_937[0].closeCauseId }) }
      val w941 = { ...w940, inc: w940.inc.set(iid, { ...w940.inc.get(iid), result: ps_937[0].result }) }
      val w942 = { ...w941, inc: w941.inc.set(iid, { ...w941.inc.get(iid), closedBy: ps_937[0].closedBy }) }
      val w943 = { ...w942, inc: w942.inc.set(iid, { ...w942.inc.get(iid), owner: ps_937[0].closedBy }) }
      w943
    } else w0
    w938
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w944 = if (not(timerDef("resolution").pausable)) {
      val w945 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w946 = { ...w945, inc: w945.inc.set(iid, { ...w945.inc.get(iid), timers: w945.inc.get(iid).timers.set("resolution", { ...w945.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w946
    } else {
      val w947 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w948 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w949 = { ...w948, inc: w948.inc.set(iid, { ...w948.inc.get(iid), timers: w948.inc.get(iid).timers.set("resolution", { ...w948.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w950 = { ...w949, inc: w949.inc.set(iid, { ...w949.inc.get(iid), timers: w949.inc.get(iid).timers.set("resolution", { ...w949.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w950
    } else w0
      w947
    }
    w944
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_951 = c.now
    val w952 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_951 }) }
    w952
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
    { val ps_953 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_954 = (if (((ps_953.length() > 0) and not(isDone(ps_953[0])))) addressee(ps_953[0]) else "")  ((who_954 != "") and (hasAccess(who_954, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_955 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w956 = if (((ps_955.length() > 0) and (leftOf(ps_955[0], "resolution", c.now) >= 0))) {
      val w957 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w958 = { ...w957, inc: w957.inc.set(iid, { ...w957.inc.get(iid), timers: w957.inc.get(iid).timers.set("resolution", { ...w957.inc.get(iid).timers.get("resolution"), left: leftOf(ps_955[0], "resolution", c.now) }) }) }
      val w959 = { ...w958, inc: w958.inc.set(iid, { ...w958.inc.get(iid), timers: w958.inc.get(iid).timers.set("resolution", { ...w958.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w960 = if ((leftOf(ps_955[0], "resolution", c.now) == 0)) {
      val w961 = { ...w959, inc: w959.inc.set(iid, { ...w959.inc.get(iid), timers: w959.inc.get(iid).timers.set("resolution", { ...w959.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_955[0], "resolution", c.now)) ps_955[0].timers.get("resolution").fired else ps_955[0].timers.get("resolution").due) }) }) }
      w961
    } else w959
      w960
    } else w0
    w956
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w962 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_963 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w964 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w965 = { ...w964, inc: w964.inc.set(iid, { ...w964.inc.get(iid), linkedTo: "" }) }
      val w966 = { ...w965, inc: w965.inc.set(iid, { ...w965.inc.get(iid), linkedAt: 0 }) }
      val w967 = if (((ps_963.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w966 else w966
      val w968 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w969 = ps_963.foldl([], (acc, x972) => acc.append(x972.id)).foldl(w967, (wf970, pId971) => wf970)
      w969
    } else w967
      w968
    } else {
      val w973 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w974 = { ...w973, inc: w973.inc.set(iid, { ...w973.inc.get(iid), linkedAt: 0 }) }
      w974
    }
    w962
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w975 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w976 = if (timerDef("reaction").startsOnce) {
      val w977 = ec_resumeTimer(w0, c, iid, "reaction")
      w977
    } else {
      val w978 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w979 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w980 = { ...w979, inc: w979.inc.set(iid, { ...w979.inc.get(iid), timers: w979.inc.get(iid).timers.set("reaction", { ...w979.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w981 = { ...w980, inc: w980.inc.set(iid, { ...w980.inc.get(iid), timers: w980.inc.get(iid).timers.set("reaction", { ...w980.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w981
    } else {
      val sec_982 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w983 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_982 < 0)) 0 else (c.now + (sec_982 * 1000))) }) }) }
      val w984 = { ...w983, inc: w983.inc.set(iid, { ...w983.inc.get(iid), timers: w983.inc.get(iid).timers.set("reaction", { ...w983.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w985 = { ...w984, inc: w984.inc.set(iid, { ...w984.inc.get(iid), timers: w984.inc.get(iid).timers.set("reaction", { ...w984.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w986 = { ...w985, inc: w985.inc.set(iid, { ...w985.inc.get(iid), timers: w985.inc.get(iid).timers.set("reaction", { ...w985.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w986
    }
      w978
    }
      w976
    }
    w975
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_987 = settings.alerts.target
    val w988 = if (((whom_987 != "") and (whom_987 != c.actor))) w0 else w0
    w988
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
      settings.holdReasons.foldl(false, (acc, r_989) => acc or ((r_989.id == c.form.reasonId) and (r_989.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_990) => acc and (isDone(e_990) or hasAccess(c.form.targetId, e_990))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_991) => acc or (i_991.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_992) => acc or ((i_992.id == c.form.resultId) and stepsOk(i_992, world.inc.get(iid)))),
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
    else if (tid == "break_hold_release") ok_break_hold_release(c, iid)
    else if (tid == "system_hold_break") ok_system_hold_break(c, iid)
    else if (tid == "system_hold_idle") ok_system_hold_idle(c, iid)
    else if (tid == "system_release_idle") ok_system_release_idle(c, iid)
    else if (tid == "no_link_hold_release") ok_no_link_hold_release(c, iid)
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
    else if (tid == "break_hold_release") apply_break_hold_release(c, iid, w)
    else if (tid == "system_hold_break") apply_system_hold_break(c, iid, w)
    else if (tid == "system_hold_idle") apply_system_hold_idle(c, iid, w)
    else if (tid == "system_release_idle") apply_system_release_idle(c, iid, w)
    else if (tid == "no_link_hold_release") apply_no_link_hold_release(c, iid, w)
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
    { id: "break_hold_release", trigger: "timer", actor: "system", from: Set("on_hold"), timer: "hold", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "system_hold_break", trigger: "system", actor: "system", from: Set("in_progress"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "system_hold_idle", trigger: "system", actor: "system", from: Set("in_progress"), timer: "", idleSec: MACHINE_SETTINGS.session.idleHoldSec, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "system_release_idle", trigger: "system", actor: "system", from: Set("on_hold"), timer: "", idleSec: MACHINE_SETTINGS.session.idleReleaseSec, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "no_link_hold_release", trigger: "timer", actor: "system", from: Set("on_hold"), timer: "hold", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
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
  val reached_break_hold_release = lastAction.name == "break_hold_release"
  val reached_system_hold_break = lastAction.name == "system_hold_break"
  val reached_system_hold_idle = lastAction.name == "system_hold_idle"
  val reached_system_release_idle = lastAction.name == "system_release_idle"
  val reached_no_link_hold_release = lastAction.name == "no_link_hold_release"
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
    ["in_progress"].foldl(false, (acc, y993) => acc or y993 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_994) => acc or ((s_994.id == agentState(c.me)) and s_994.readOnly))),
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
  // Две дежурные группы: уровень 2 эскалации — не та группа, куда уходит вышедший адресат уровня 1, — так
  // ветка «вышел — его группе» отличима от «пропустить уровень» (RULE-100, PROC-50). Порядок — как у машины
  pure val GROUP = "g"
  pure val GROUP2 = "h"
  pure val GROUP_LIST: List[str] = [GROUP, GROUP2]
  pure val GROUPS: Set[str] = Set(GROUP, GROUP2)
  pure val TARGETS: Set[str] = OPERATORS.union(GROUPS)
  // Сценарий без графа (§14.5): два сценария, у каждого два шага по порядку; пройден — отвечены оба (набор closing)
  pure val SCENARIOS: Set[str] = Set("fire", "water")
  pure val STEPS: Set[str] = Set("s1", "s2")
  // Сценарий модели — линейный: s1, затем s2, он финальный. Ответ — только на следующий неотвеченный шаг, поэтому
  // ответы — начало пути, и перенос объединением (shareAnswers) даёт то же, что настоящий перенос «по пути до
  // разрыва» (scenario.js, share); сверка ядра повторяет ответы и переносы на настоящем исполнителе (Р9 б, PROC-79)
  pure val STEP_ORDER: List[str] = ["s1", "s2"]
  // События (§14.5, ARCH-15): у инцидента — своё событие или общее ev0, выбор из двух. Так бывают и соседи — инциденты
  // общего события разных сценариев, — и три инцидента одного сценария, все с разными событиями: без них нет двух
  // привязанных к одному основному (premise_twoLinked), а при двух событиях на всех их быть не может. Выбор правила по
  // событию — вне модели: инцидент появляется сразу с событием и сценарием, модель проверяет ключ «событие +
  // сценарий» (intake.uniqueKey машины)
  pure val OWN_EVENT: str -> str = Map("i1" -> "ev1", "i2" -> "ev2", "i3" -> "ev3")
  pure val SHARED_EVENT = "ev0"
  pure def eventsFor(i: str): Set[str] = Set(OWN_EVENT.get(i), SHARED_EVENT)
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
  // Состояние до последнего шага — для свойств права на действие и двух соседних состояний (PROC-73). Пишет каждое
  // действие: prev' = snapshot; после init — само начальное состояние
  type Before = { world: World, cfg: Config, agents: str -> str, lastBeat: str -> int, link: str -> bool, clock: int }
  var prev: Before
  def snapshot: Before = { world: world, cfg: cfg, agents: agents, lastBeat: lastBeat, link: link, clock: clock }

  /* ===== Факты мира (cel.world машины) ===== */

  // Право действует, если набор прав проходит §10.3: с «Взять» или «Принять» нужен хотя бы один выход из карточки,
  // иначе эти права не действуют (EXIT_RULE из машины, PROC-73). Проверка при входе — в модели действует всегда.
  // При заданном лимите отложенных «Отложить» выходом не считается: лимит может его закрыть (RULE-136)
  pure def exitsFor(holdLimited: bool): Set[str] = if (holdLimited) EXIT_RULE.requiresAnyOfWithHoldLimit else EXIT_RULE.requiresAnyOf
  pure def permsAct(ps: Set[str], perm: str, holdLimited: bool): bool = all {
    ps.contains(perm),
    not(EXIT_RULE.disables.contains(perm) and EXIT_RULE.appliesTo.exists(p => ps.contains(p)) and not(exitsFor(holdLimited).exists(p => ps.contains(p)))),
  }
  def holdLimited: bool = settings.limits.maxOnHold > 0
  def can(who: str, perm: str): bool = OPERATORS.contains(who) and permsAct(cfg.perms.get(who), perm, holdLimited)
  def access(who: str, x: Incident): bool = OPERATORS.contains(who) and cfg.access.get(who).contains(x.id)
  def isOperator(id: str): bool = OPERATORS.contains(id)
  def isGroup(id: str): bool = GROUPS.contains(id)
  def members(g: str): List[str] = if (isGroup(g)) OPERATOR_LIST.select(m => cfg.members.get(g).contains(m)) else []
  def dutyGroups: List[str] = GROUP_LIST
  // Кому вообще можно передавать: люди и дежурные группы (§8.1, BUG-85)
  def transferTargets: List[str] = OPERATOR_LIST.concat(GROUP_LIST)
  // Групп устройств в модели нет: строк overrides по sourceGroup в машине тоже нет
  def inSourceGroup(x: Incident, g: str): bool = false
  // Условия правил по группе (§14.5, ARCH-15): групп устройств в модели нет — устройство ни в одной, глубина 0
  def deviceInGroup(d: str, g: str): bool = false
  def groupDepth(g: str): int = 0
  def agentState(who: str): str = if (OPERATORS.contains(who)) agents.get(who) else "offline"
  def idleSec(who: str): int = if (OPERATORS.contains(who)) (clock - lastBeat.get(who)) / 1000 else 0
  def nextStep(i: str): str = STEP_ORDER.foldl("", (n, s) => if (n == "" and not(world.answers.get(i).contains(s))) s else n)
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
    { name: name, actor: actor, incident: i, kind: kind, form: NO_FORM, surface: "", others: [], prio: 0, scenario: "", event: "" }

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
    prev' = snapshot,
    // Автоматический переход — ещё один подряд; любое другое действие счёт сбрасывает (П3)
    autoRun' = if (a.kind == "auto") autoRun.set(a.incident, autoRun.get(a.incident) + 1) else INCIDENTS.mapBy(j => 0),
  }

  /* ===== Появление инцидента (переход с trigger event) ===== */

  // Инцидент события ev со сценарием sc (§14.5, ARCH-15). Правило уже выбрано — от него сценарий и приоритет; сам
  // выбор правила по событию — вне модели. Ключ intake.uniqueKey машины — событие + сценарий: второго инцидента того
  // же сценария на событие нет, повтор события и пересекающиеся правила его не дают
  def createOk(i: str, ev: str, sc: str): bool = all {
    incOf(i).state == "",
    not(INCIDENTS.exists(j => incOf(j).state != "" and incOf(j).eventGuid == ev and incOf(j).scenario == sc)),
  }
  action create(i: str, ev: str, sc: str, prio: int): bool = {
    val t = ofTrigger("event")[0]
    val w0 = { ...world,
      inc: world.inc.set(i, { ...NO_INCIDENT, id: i, number: i, eventType: "fire", priority: prio, occurredAt: clock, scenario: sc, eventGuid: ev }),
      answers: world.answers.set(i, Set()) }
    all {
      createOk(i, ev, sc),
      commit({ ...act0("create", t.id, DISPATCHER, i), prio: prio, scenario: sc, event: ev }, trApply(t.id, ctx(DISPATCHER, DISPATCHER, NO_FORM, ""), i, w0)),
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
  // Основного выбирает сервер по mergePrimary машины (§11, ARCH-08 в1); назвать его клиент не может (RULE-101)
  action mergeAuto(a: str, sel: Set[str]): bool = {
    val ps = mergePrimary(IDS.select(j => sel.contains(j)).foldl([], (acc, j) => acc.append(incOf(j))), a)
    all { ps.length() == 1, mergeAs("merge_auto", a, ps[0].id, sel.exclude(Set(ps[0].id))) }
  }
  // Для сценариев: объединение, в котором сервер выбирает основным именно p
  action merge(a: str, p: str, others: Set[str]): bool = {
    val sel = others.union(Set(p))
    val ps = mergePrimary(IDS.select(j => sel.contains(j)).foldl([], (acc, j) => acc.append(incOf(j))), a)
    all { ps.length() == 1, ps[0].id == p, mergeAs("merge_auto", a, p, others.exclude(Set(p))) }
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
      prev' = snapshot,
      autoRun' = autoRun,
    }
  }

  action agent(a: str, name: str, state: str, beat: bool): bool = all {
    agents' = agents.set(a, state),
    lastBeat' = if (beat) lastBeat.set(a, clock) else lastBeat,
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
    prev' = snapshot,
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
    prev' = snapshot,
    autoRun' = INCIDENTS.mapBy(j => 0),
  }
  action restoreLink(a: str): bool = all {
    not(link.get(a)),
    link' = link.set(a, true),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, changedAt' = changedAt,
    lastAction' = act0("env", "restore_link", a, NOBODY),
    prev' = snapshot,
    autoRun' = INCIDENTS.mapBy(j => 0),
  }

  // Запрос оператора, который ничего не изменил, — отказанный переход, подсчёт выборки: тоже признак активности.
  // Любой запрос, кроме чтения (§12.3, BUG-76 а), RULE-112); нужна связь
  action request(a: str): bool = all {
    link.get(a),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", "request", a, NOBODY),
    prev' = snapshot,
    autoRun' = INCIDENTS.mapBy(j => 0),
  }

  // Сменились роли (§5): доступ к объекту инцидента, право «Принимать»
  action roles(a: str, name: str, c: Config): bool = all {
    cfg' = c,
    world' = world, settings' = settings, clock' = clock, agents' = agents, lastBeat' = lastBeat, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
    prev' = snapshot,
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

  // Ответ на шаг сценария (§10.4): кто может — scenarioEdit машины; шаг — следующий неотвеченный (линейный сценарий)
  action answer(a: str, i: str, st: str): bool = all {
    sees(a, i),
    scenarioEditOk(ctx(a, a, NO_FORM, "card"), i),
    st != "",
    st == nextStep(i),
    commit(act0("env", "answer", a, i), { ...world, answers: world.answers.set(i, world.answers.get(i).union(Set(st))) }),
  }

  /* ===== Начало и шаг =====
     Два профиля (PROC-72). Широкий — init и step: права, доступ и группы любые, роли меняются на ходу.
     «Смена» — initWork: типовые наборы прав валидатора, доступ ко всем инцидентам, в группе g оба; шаг
     stepWork — без смены ролей и пустых запросов, ответ на шаг сценария и закрытие с результатом, которому нужен
     пройденный сценарий, выпадают чаще. Редкие переходы и посылки инвариантов набирают историй в «смене»,
     переходы по доступу и праву «Принимать» — в широком (tools/check_quint_coverage.mjs) */

  action init = {
    nondet perms = OPERATORS.setOfMaps(USED_PERMISSIONS.powerset()).oneOf()
    nondet access = OPERATORS.setOfMaps(INCIDENTS.powerset()).oneOf()
    nondet grp = OPERATORS.powerset().oneOf()
    initFrom(perms, access, grp)
  }
  action initWork = {
    nondet perms = OPERATORS.setOfMaps(TYPICAL_PERMISSION_SETS).oneOf()
    initFrom(perms, OPERATORS.mapBy(a => INCIDENTS), OPERATORS)
  }
  // Уровень эскалации с адресатом t: вид — по адресату (человек или дежурная группа)
  pure def levelTo(l: Level, n: int, t: str): Level = { ...l, level: n, targetKind: if (GROUPS.contains(t)) "group" else "user", target: t }
  action initFrom(perms: str -> Set[str], access: str -> Set[str], grp: Set[str]): bool = {
    nondet grp2 = OPERATORS.powerset().oneOf()
    // Настройки, от которых зависят ветки автоматических переходов, — из машины (BRANCH_SETTINGS, PROC-43)
    nondet branch = BRANCH_SETTINGS.oneOf()
    nondet maxActive = Set(0, 1).oneOf()
    nondet maxOnHold = Set(0, 1).oneOf()
    // Состав уровней эскалации и потолок (§8.3, PROC-74): два или три уровня, адресат каждого — любой человек или
    // дежурная группа модели, потолок — от 1 до числа уровней; третий уровень — с нормативом второго
    nondet t1 = TARGETS.oneOf()
    nondet t2 = TARGETS.oneOf()
    nondet t3 = TARGETS.oneOf()
    nondet three = Set(false, true).oneOf()
    nondet starts = OPERATORS.setOfMaps(AGENT_STARTS).oneOf()
    val levels = MACHINE_SETTINGS.escalation.levels
    val chosen = [levelTo(levels[0], 1, t1), levelTo(levels[1], 2, t2)].concat(if (three) [levelTo(levels[1], 3, t3)] else [])
    nondet maxLevel = 1.to(chosen.length()).oneOf()
    val c = { perms: perms, access: access, members: Map(GROUP -> grp, GROUP2 -> grp2) }
    val w = { inc: INCIDENTS.mapBy(i => NO_INCIDENT), answers: INCIDENTS.mapBy(i => Set()) }
    all {
      cfg' = c,
      // Настройки — значения машины; перебираются ветки автоматики (withBranches), лимиты и состав уровней
      // эскалации, люди — люди модели; алерты — группе g
      settings' = withBranches({ ...MACHINE_SETTINGS,
        escalation: { ...MACHINE_SETTINGS.escalation, levels: chosen, maxLevel: maxLevel },
        alerts: { ...MACHINE_SETTINGS.alerts, targetKind: "group", target: GROUP },
        limits: { ...MACHINE_SETTINGS.limits, maxActive: maxActive, maxOnHold: maxOnHold },
      }, branch),
      world' = w,
      clock' = START,
      // Оператор — ещё не вошёл (начальное машины) или уже вошёл (RULE-99)
      agents' = starts,
      lastBeat' = OPERATORS.mapBy(a => START),
      link' = OPERATORS.mapBy(a => true),
      changedAt' = INCIDENTS.mapBy(i => 0),
      lastAction' = act0("init", "init", NOBODY, NOBODY),
      autoRun' = INCIDENTS.mapBy(i => 0),
      prev' = { world: w, cfg: c, agents: starts, lastBeat: OPERATORS.mapBy(a => START), link: OPERATORS.mapBy(a => true), clock: START },
    }
  }

  pure val MANUAL_IDS: Set[str] = ofTrigger("manual").foldl(Set(), (s, t) => if (t.bulkOnly) s else s.union(Set(t.id)))
  def pendingAuto: Set[str] = INCIDENTS.filter(i => nextAuto(i).length() > 0)
  action step = if (pendingAuto.size() > 0) fireAny else stepFree
  action stepWork = if (pendingAuto.size() > 0) fireAny else stepFreeWork
  action fireAny = {
    nondet j = pendingAuto.oneOf()
    fire(j)
  }
  action stepFree = {
    nondet i = INCIDENTS.oneOf()
    nondet a = OPERATORS.oneOf()
    any {
      createAny(i),
      manualAny(a, i, MANUAL_IDS, CLOSE_RESULT_IDS),
      mergeAny(a),
      time,
      agentMoveAny(a),
      loseLink(a),
      restoreLink(a),
      request(a),
      toggleAccess(a, i),
      toggleAccept(a),
      answerAny(a, i),
    }
  }
  action stepFreeWork = {
    nondet i = INCIDENTS.oneOf()
    nondet a = OPERATORS.oneOf()
    any {
      createAny(i),
      manualAny(a, i, MANUAL_IDS, CLOSE_RESULT_IDS),
      mergeAny(a),
      time,
      agentMoveAny(a),
      loseLink(a),
      restoreLink(a),
      // Ответ — двумя ветками, закрытие по пройденному сценарию — своей: иначе путь «ответы → закрыть» почти
      // не выпадает (замер PROC-72: 0 историй из 3000, с этими ветками — 27)
      answerAny(a, i),
      answerAny(a, i),
      manualAny(a, i, STEP_RESULT_CLOSE_IDS, STEP_RESULT_IDS),
    }
  }
  action createAny(i: str): bool = {
    nondet ev = eventsFor(i).oneOf()
    nondet sc = SCENARIOS.oneOf()
    nondet prio = PRIORITIES.oneOf()
    create(i, ev, sc, prio)
  }
  action manualAny(a: str, i: str, tids: Set[str], results: Set[str]): bool = {
    nondet tid = tids.oneOf()
    nondet target = TARGETS.oneOf()
    nondet reason = HOLD_REASONS_BY_OPERATOR.oneOf()
    nondet result = results.oneOf()
    nondet surface = tr(tid).surfaces.oneOf()
    val form = { ...NO_FORM, targetId: target, reasonId: reason, resultId: result,
      causeId: if (CAUSE_FOR.keys().contains(result)) CAUSE_FOR.get(result) else "", comment: "c" }
    manual(a, tid, i, form, surface)
  }
  action mergeAny(a: str): bool = {
    nondet sel = INCIDENTS.powerset().oneOf()
    mergeAuto(a, sel)
  }
  action agentMoveAny(a: str): bool = {
    nondet m = AGENT_MOVES.oneOf()
    agentMove(a, m.id)
  }
  action answerAny(a: str, i: str): bool = answer(a, i, nextStep(i))

  /* ===== Инварианты =====
     quint run im.qnt --invariant inv; каждый можно проверить отдельно — имена ниже.
     Инварианты пишутся руками и нарочно другими словами, чем правила машины: совпади они с машиной
     дословно, они бы ничего не проверяли. */

  pure val OPEN: Set[str] = Set("new", "pending_acceptance", "in_progress", "on_hold")
  pure def runs(t: Timer): bool = t.due != 0
  def isDueT(t: Timer): bool = t.due != 0 and t.due <= clock and t.fired != t.due
  pure def hasBreach(x: Incident, kind: str): bool = x.breaches.select(b => b.kind == kind).length() > 0
  def primaryOf(x: Incident): Incident = if (INCIDENTS.contains(x.linkedTo)) incOf(x.linkedTo) else NO_INCIDENT
  // Сейчас выполнится один из названных автоматических переходов этого инцидента — тот, что исправляет состояние
  // (PROC-73): не любой готовый, иначе случайно готовый таймер прикрыл бы запрещённое состояние
  def fixReady(i: str, names: Set[str]): bool = AUTO.foldl(false, (acc, t) => acc or (names.contains(t.id) and autoReady(t, i)))

  // 1. Владелец по состоянию (§2.1)
  val ownerByState = INCIDENTS.forall(i => {
    val x = incOf(i)
    val s = x.state
    if (s == "new" or s == "linked") x.owner == NOBODY and x.assignmentGroup == NOBODY
    else if (s == "pending_acceptance")
      (OPERATORS.contains(x.owner) and x.assignmentGroup == NOBODY) or (x.owner == NOBODY and GROUPS.contains(x.assignmentGroup))
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
      // Срок удержания у причины есть всегда (§4, правило 7; RULE-135) — идёт он или уже нарушен, проверяет holdBounded
      else if (s == "on_hold") not(runs(z)) and z.paused and not(runs(r))
      else if (s == "closed") not(runs(r)) and not(runs(z)) and not(runs(h))
      // Свой норматив закрытия привязанного на паузе: у группы один срок — срок основного (RULE-97)
      else if (s == "linked") not(runs(r)) and not(runs(h)) and not(runs(z))
      else true,
    }
  })

  // 3б. Удержание не бесконечно (§4, правило 7; RULE-118): у отложенного идёт срок удержания или уже записано
  //     нарушение удержания — иначе отложенный лежал бы без срока, пока его не тронет человек
  val holdBounded = INCIDENTS.forall(i => {
    val x = incOf(i)
    x.state == "on_hold" implies (runs(x.timers.get("hold")) or hasBreach(x, "hold"))
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
  //    Закрытие снимается «Переоткрыть» целиком: время, закрывший и комментарий — только у закрытого (RULE-103)
  val closeResultIffClosed = INCIDENTS.forall(i => {
    val x = incOf(i)
    val closed = x.state == "closed"
    all { (x.closeResultId != NOBODY) iff closed, (x.closedAt != 0) iff closed, (x.closedBy != NOBODY) iff closed, closed or x.result == "" }
  })

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
    x.state == "pending_acceptance" implies (mayAccept(who, x) or fixReady(i, Set("addressee_cannot_accept", "addressee_lost_access")))
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
      OPEN.contains(p.state) or (p.state == "closed" and fixReady(i, Set("close_linked"))),
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
      Set("pending_acceptance", "in_progress", "on_hold").contains(x.state) implies (reach(who, x) or fixReady(i, Set("addressee_lost_access"))),
      (x.state == "linked" and p.state != "closed" and pwho != NOBODY) implies (reach(pwho, x) or fixReady(i, Set("linked_lost_access")) or fixReady(x.linkedTo, Set("addressee_lost_access"))),
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
      (Set("pending_acceptance", "in_progress", "on_hold").contains(x.state) and agentState(x.owner) == "offline" and OPERATORS.contains(x.owner))
        implies fixReady(i, Set("owner_signed_out", "addressee_signed_out_to_group", "addressee_signed_out_to_queue")),
      (x.state == "in_progress" and agentState(x.owner) == "not_ready") implies fixReady(i, Set("system_hold_break")),
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
  //     idleReleaseSec — сейчас уходит в очередь (PROC-45); отложенный оператором молчание в очередь не возвращает —
  //     причина по справочнику, а не по условию перехода (PROC-87)
  val silentOwnerHandled = INCIDENTS.forall(i => {
    val x = incOf(i)
    val idle = if (OPERATORS.contains(x.owner) and agentState(x.owner) != "offline") idleSec(x.owner) else 0
    all {
      (x.state == "in_progress" and idle >= settings.session.idleHoldSec) implies fixReady(i, Set("system_hold_idle")),
      (x.state == "on_hold" and x.holdReasonId != NOBODY and not(HOLD_REASONS_BY_OPERATOR.contains(x.holdReasonId)) and idle >= settings.session.idleReleaseSec) implies fixReady(i, Set("system_release_idle")),
      (lastAction.incident == i and lastAction.name == "system_release_idle") implies not(HOLD_REASONS_BY_OPERATOR.contains(before(i).holdReasonId)),
    }
  })

  // 14. П3. Без людей автоматика конечна: подряд, только со временем, у инцидента — не больше AUTO_BOUND
  //     автоматических переходов; эскалация упирается в потолок, круга нет. Самая длинная цепочка — около 8,
  //     например resolution_overdue → system_hold_idle → hold_overdue → system_release_idle → auto_escalate → …
  //     → escalation_ceiling; при пределе 3 модель находит нарушение — у предела есть запас, но не лишний (PROC-45)
  pure val AUTO_BOUND = 10
  val autoBounded = INCIDENTS.forall(i => autoRun.get(i) <= AUTO_BOUND)

  // 20. Право на действие (§6.1, §2.2, §10.1, правило 2; PROC-73): ручной переход и объединение сделал тот, у
  //     кого до шага (prev) были право и условие, — оператор на месте, видел инцидент, а дальше по переходу
  def hadPerm(a: str, p: str): bool = prev.cfg.perms.get(a).contains(p)
  def hadAccess(a: str, i: str): bool = prev.cfg.access.get(a).contains(i)
  // Адресат — я или дежурная группа, где я состою (§8.1)
  def wasAddressee(a: str, x: Incident): bool =
    x.owner == a or (GROUPS.contains(x.assignmentGroup) and prev.cfg.members.get(x.assignmentGroup).contains(a))
  def rightFor(a: str, tid: str, x0: Incident, x: Incident): bool =
    if (tid == "claim") x0.state == "new" and hadPerm(a, "incident:claim")
    else if (tid == "accept") x0.state == "pending_acceptance" and wasAddressee(a, x0) and hadPerm(a, "incident:accept")
    else if (tid == "reject") x0.state == "pending_acceptance" and wasAddressee(a, x0) and hadPerm(a, "incident:release")
    else if (tid == "hold") x0.state == "in_progress" and x0.owner == a and hadPerm(a, "incident:hold")
    else if (tid == "resume") x0.state == "on_hold" and x0.owner == a and hadPerm(a, "incident:claim")
    else if (tid == "release") Set("in_progress", "on_hold").contains(x0.state) and x0.owner == a and hadPerm(a, "incident:release")
    // Передать (§5): своё — новый, мой или адресованный мне или моей группе — правом own, остальное — правом any
    else if (tid == "transfer")
      if (x0.state == "new" or x0.owner == a or (x0.state == "pending_acceptance" and wasAddressee(a, x0))) hadPerm(a, "incident:transfer:own")
      else hadPerm(a, "incident:transfer:any")
    else if (tid == "takeover") not(wasAddressee(a, x0)) and hadPerm(a, "incident:reassign") and hadPerm(a, "incident:claim")
    // Закрыть (§2.2): «Массовый сбой» — своим правом и ещё из «Новое» и «Ожидает принятия», остальные — из «В
    // работе»; в работе и отложенный — только свой
    else if (tid == "close") all {
      if (x.closeResultId == "mass") hadPerm(a, "incident:close:unprocessed") else hadPerm(a, "incident:close") and x0.state == "in_progress",
      Set("in_progress", "on_hold").contains(x0.state) implies x0.owner == a,
    }
    else if (tid == "reopen") all {
      x0.state == "closed",
      prev.clock - x0.closedAt <= settings.limits.reopenWindowMin * 60000,
      hadPerm(a, "incident:reopen"),
      hadPerm(a, "incident:claim"),
    }
    // Отсоединить (§11.4, RULE-78): я веду основной — он мой, в работе или отложен, — или основной новый и ничей;
    // у основного «Ожидает принятия» — только после «Принять»
    else if (tid == "detach") {
      val p0 = prev.world.inc.get(x0.linkedTo)
      x0.state == "linked" and ((p0.state == "new" and p0.owner == NOBODY and p0.assignmentGroup == NOBODY)
        or (Set("in_progress", "on_hold").contains(p0.state) and p0.owner == a))
    }
    else true
  // 21. Свойства двух соседних состояний (PROC-73): инцидент сейчас и до шага (prev)
  def before(i: str): Incident = prev.world.inc.get(i)

  //     а) Передачей и отклонением реакцию не продлить (§6.1, RULE-82, RULE-83): после «Передать» из «Новое» и
  //        «Ожидает принятия», «Отклонить» и ухода вышедшего адресата срок реакции прежний, если она шла.
  //        Остановленную потолком или нарушением «Передать» запускает заново, «Отклонить» — нет (RULE-84).
  //        «Вернуть в очередь», выход владельца и «Отсоединить» продолжают реакцию с остатка, запомненного при взятии
  //        или объединении: цикл «взял — вернул» эскалацию не откладывает (RULE-104, RULE-121, RULE-128; PROC-84)
  val reactionNotExtended = {
    val la = lastAction
    val r0 = before(la.incident).timers.get("reaction")
    val r = incOf(la.incident).timers.get("reaction")
    val keeps = (la.name == "transfer" and Set("new", "pending_acceptance").contains(before(la.incident).state))
      or Set("reject", "addressee_signed_out_to_group", "addressee_signed_out_to_queue").contains(la.name)
    INCIDENTS.contains(la.incident) implies all {
      (keeps and runs(r0)) implies r.due == r0.due,
      (la.name == "reject" and not(runs(r0))) implies not(runs(r)),
      (Set("release", "owner_signed_out", "detach").contains(la.name) and r0.paused and r0.left > 0) implies r.due == clock + r0.left,
    }
  }

  //     а2) Срок группы — самый ранний (§11.4, RULE-97; PROC-84): после объединения остаток норматива закрытия основного —
  //        наименьший из своего и неотработанных остатков объединённых; новый основной берётся с полного норматива, но
  //        не позже их. Наступивший срок основного (окно, нарушение) — по правилам окна, здесь не проверяется
  pure def remOf(z: Timer, now: int): int = if (z.due != 0) (if (z.due > now) z.due - now else 0) else if (z.paused) z.left else -1
  val groupDeadlineEarliest = {
    val la = lastAction
    val p0 = remOf(before(la.incident).timers.get("resolution"), clock)
    val p = remOf(incOf(la.incident).timers.get("resolution"), clock)
    val others = la.others.foldl([], (acc, o) => {
      val r = remOf(before(o).timers.get("resolution"), clock)
      if (r > 0) acc.append(r) else acc
    })
    val least = others.foldl(-1, (m, r) => if (m < 0 or r < m) r else m)
    Set("merge", "merge_auto").contains(la.kind) implies {
      if (p0 > 0) p == (if (least > 0 and least < p0) least else p0)
      else if (p0 < 0) p > 0 and (least > 0 implies p <= least)
      else true
    }
  }

  //     а2б) Вышедший из группы уносит срок группы (§11.4, §6.2; PROC-91): после «Отсоединить» и потери доступа
  //        (linked_lost_access) норматив закрытия на паузе с остатком основного на этот момент — не со своим прежним
  //        и не с полным: иначе взятый позже получил бы срок длиннее группы
  val leftGroupKeepsGroupDeadline = {
    val la = lastAction
    val z = incOf(la.incident).timers.get("resolution")
    val r = remOf(before(before(la.incident).linkedTo).timers.get("resolution"), clock)
    (INCIDENTS.contains(la.incident) and Set("detach", "linked_lost_access").contains(la.name) and r >= 0)
      implies (z.paused and z.due == 0 and z.left == r)
  }

  //     а3) Закрытый не меняется, пока его самого не переоткрыли (§2.1, §6.1; PROC-84): ни связь, ни сроки, ни владелец.
  //        Нарушение дописаться может: отсоединённый в окне после срока группы и закрытый в нём — был в группе в момент
  //        срока и получает её нарушение (BUG-73); что нарушения только дописываются — breachesKept
  val closedKept = INCIDENTS.forall(i =>
    (before(i).state == "closed" and not(lastAction.name == "reopen" and lastAction.incident == i))
      implies { ...incOf(i), breaches: before(i).breaches, slaBreached: before(i).slaBreached } == before(i))

  //     а4) Срок удержания — по причине (§4, правило 7; RULE-129, RULE-132; PROC-84): при входе в «Отложен» срок — сейчас
  //        плюс срок причины; у «Нет связи» (deadlineFromIdle) — порог возврата в очередь минус порог удержания, не
  //        меньше 0: срок причины и возврат по молчанию совпадают; причина без срока — срок не идёт
  val holdDeadlineByReason = INCIDENTS.forall(i => {
    val x = incOf(i)
    val h = x.timers.get("hold")
    val rs = settings.holdReasons.select(r => r.id == x.holdReasonId)
    val s = settings.session
    val sec = if (rs.length() == 0) -1
      else if (rs[0].deadlineFromIdle) (if (s.idleReleaseSec > s.idleHoldSec) s.idleReleaseSec - s.idleHoldSec else 0)
      else if (rs[0].maxMinutes.length() > 0) rs[0].maxMinutes[0] * 60
      else -1
    (before(i).state != "on_hold" and x.state == "on_hold") implies (if (sec >= 0) h.due == clock + sec * 1000 else not(runs(h)))
  })

  //     а5) Перерыв — только из «Готов» (§12.2; PROC-84): «Занят» в модели — тот же «Готов»; из «Вышел» — сначала вход
  val breakFromReady = (lastAction.kind == "env" and lastAction.name == "break")
    implies (prev.agents.get(lastAction.actor) == "ready" and agents.get(lastAction.actor) == "not_ready")

  //     а6) Норматив реакции уровня (§8.3, RULE-76; PROC-86): после автоэскалации реакция идёт с нормативом того
  //        уровня, на который инцидент поднялся, — по списку уровней, а не через levelNorm машины
  val escalationReactionNorm = {
    val la = lastAction
    val x = incOf(la.incident)
    val ls = settings.escalation.levels.select(l => l.level == x.escalationLevel)
    (INCIDENTS.contains(la.incident) and Set("auto_escalate", "resolution_escalate").contains(la.name))
      implies (ls.length() > 0 and x.timers.get("reaction").due == clock + ls[0].reactionSec * 1000)
  }

  //     б) Уровень эскалации меняет только эскалация этого инцидента, и только вверх (§8.3)
  val levelOnlyByEscalation = INCIDENTS.forall(i => {
    val l0 = before(i).escalationLevel
    val l = incOf(i).escalationLevel
    l != l0 implies all {
      lastAction.incident == i,
      Set("auto_escalate", "resolution_escalate").contains(lastAction.name),
      l > l0,
    }
  })

  //     в) Нарушения не стираются (§6.1, «Переоткрыть»; §10.1): записанные остаются в том же порядке, новые — в конец
  val breachesKept = INCIDENTS.forall(i => {
    val b0 = before(i).breaches
    val b = incOf(i).breaches
    if (b.length() >= b0.length()) b.slice(0, b0.length()) == b0 else false
  })

  //     г) Остаток норматива закрытия сохраняется (§4): «Отложить» запоминает, сколько осталось, «Возобновить»
  //        продолжает с того же остатка. Отработанный норматив (RULE-50) — другой случай, его здесь нет
  val resolutionLeftKept = {
    val la = lastAction
    val z0 = before(la.incident).timers.get("resolution")
    val z = incOf(la.incident).timers.get("resolution")
    INCIDENTS.contains(la.incident) implies all {
      (la.name == "hold" and runs(z0)) implies (z.paused and z.left == (if (z0.due > clock) z0.due - clock else 0)),
      (la.name == "resume" and z0.paused and z0.left > 0) implies z.due == clock + z0.left,
    }
  }

  //     д) Действие не создаёт состояния, которое система тут же исправляет (Р5 б): после ручного перехода и
  //        объединения у этого инцидента не готов ни один исправляющий системный переход
  pure val FIXERS: Set[str] = Set("addressee_cannot_accept", "addressee_lost_access", "close_linked", "linked_lost_access",
    "owner_signed_out", "addressee_signed_out_to_group", "addressee_signed_out_to_queue", "system_hold_break",
    "system_hold_idle", "system_release_idle")
  //        Исключения — по правилам: «Передать» вышедшему можно, инцидент сразу уходит его группе или в очередь
  //        (§8.1, «Адресат вышел»; RULE-47)
  pure def fixExpected(tid: str): Set[str] =
    if (tid == "transfer") Set("addressee_signed_out_to_group", "addressee_signed_out_to_queue") else Set()
  val noFixAfterAction =
    Set("manual", "merge", "merge_auto").contains(lastAction.kind)
      implies not(fixReady(lastAction.incident, FIXERS.exclude(fixExpected(lastAction.name))))

  // 22. Выход есть (§10.3; PROC-73): у «В работе», чей владелец на месте, видит инцидент и имеет право хотя бы на
  //     один выход, доступен хотя бы один выход из карточки — «Отложить», «Вернуть в очередь» или «Закрыть»
  pure def exitForm(reason: str, result: str): Form = { ...NO_FORM, reasonId: reason, resultId: result,
    causeId: if (CAUSE_FOR.keys().contains(result)) CAUSE_FOR.get(result) else "", comment: "c" }
  def exitOk(a: str, tid: str, i: str, f: Form): bool =
    tr(tid).surfaces.exists(s => trOk(tid, ctx(a, a, f, s), i) and formOk(tid, ctx(a, a, f, s), i))
  val exitExists = INCIDENTS.forall(i => {
    val x = incOf(i)
    val a = x.owner
    // Право на выход — по §10.3: при заданном лимите отложенных «Отложить» не в счёт (RULE-136)
    (x.state == "in_progress" and OPERATORS.contains(a) and agentState(a) == "ready" and sees(a, i)
      and exitsFor(holdLimited).exists(p => can(a, p))) implies or {
      HOLD_REASONS_BY_OPERATOR.exists(r => exitOk(a, "hold", i, exitForm(r, ""))),
      HOLD_REASONS_BY_OPERATOR.exists(r => exitOk(a, "release", i, exitForm(r, ""))),
      CLOSE_RESULT_IDS.exists(r => exitOk(a, "close", i, exitForm("", r))),
    }
  })

  // 23. Системный переход — только по делу (PROC-84): исправляющий переход сделан, только если до шага (prev) было что
  //     исправлять — адресат без доступа, не может принять, вышел; владелец вышел или на перерыве. Доступ и право
  //     принять у дежурной группы — у кого-то из участников (§5, §8.1)
  def hadPermOf(m: str, p: str): bool = permsAct(prev.cfg.perms.get(m), p, holdLimited)
  def reachedBefore(who: str, i: str): bool =
    if (GROUPS.contains(who)) prev.cfg.members.get(who).exists(m => hadAccess(m, i)) else OPERATORS.contains(who) and hadAccess(who, i)
  def couldAcceptBefore(who: str, i: str): bool =
    if (GROUPS.contains(who)) prev.cfg.members.get(who).exists(m => hadPermOf(m, "incident:accept") and hadAccess(m, i))
    else OPERATORS.contains(who) and hadPermOf(who, "incident:accept") and hadAccess(who, i)
  val systemOnlyWhenDue = {
    val la = lastAction
    val x0 = before(la.incident)
    val who = if (x0.owner != NOBODY) x0.owner else x0.assignmentGroup
    la.kind == "auto" implies (
      if (la.name == "addressee_lost_access") not(reachedBefore(who, la.incident))
      else if (la.name == "addressee_cannot_accept") not(couldAcceptBefore(who, la.incident))
      else if (la.name == "owner_signed_out") prev.agents.get(x0.owner) == "offline"
      else if (Set("addressee_signed_out_to_group", "addressee_signed_out_to_queue").contains(la.name)) OPERATORS.contains(x0.owner) and prev.agents.get(x0.owner) == "offline"
      else if (la.name == "system_hold_break") prev.agents.get(x0.owner) == "not_ready"
      else true
    )
  }

  val actionRights = {
    val la = lastAction
    val a = la.actor
    val x0 = prev.world.inc.get(la.incident)
    // Объединение (§11.3): право на выборку, каждый — ничей или мой, у каждого доступ
    val mergeOk = hadPerm(a, "incident:bulk") and la.others.foldl(true, (ok, o) => ok and hadAccess(a, o) and
      Set(NOBODY, a).contains(prev.world.inc.get(o).owner)) and Set(NOBODY, a).contains(x0.owner)
    Set("manual", "merge", "merge_auto").contains(la.kind) implies all {
      prev.agents.get(a) == "ready",
      hadAccess(a, la.incident),
      if (la.kind == "manual") rightFor(a, la.name, x0, incOf(la.incident)) else mergeOk,
    }
  }

  // 24. Ключ «событие + сценарий» (§14.5, ARCH-15; oneIncidentPerEventScenario машины): у двух появившихся инцидентов
  //     одного события сценарии разные — повтор события и пересекающиеся правила второго инцидента сценария не дают
  val eventScenarioUnique = INCIDENTS.forall(i => INCIDENTS.forall(j => {
    val x = incOf(i)
    val y = incOf(j)
    (i != j and x.state != "" and y.state != "" and x.eventGuid == y.eventGuid) implies x.scenario != y.scenario
  }))

  // 25. Соседи — не привязка §11 (§14.5): у привязанного событие другое, чем у основного. Следствие linkedSameScenario
  //     и eventScenarioUnique — страховка на случай, если одно из них ослабнет
  val siblingsNotLinked = INCIDENTS.forall(i => incOf(i).linkedTo != NOBODY implies incOf(i).eventGuid != primaryOf(incOf(i)).eventGuid)

  val inv = all {
    ownerByState,
    holdReasonIffOnHold,
    timersByState,
    holdBounded,
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
    actionRights,
    reactionNotExtended,
    groupDeadlineEarliest,
    leftGroupKeepsGroupDeadline,
    systemOnlyWhenDue,
    closedKept,
    holdDeadlineByReason,
    breakFromReady,
    escalationReactionNorm,
    levelOnlyByEscalation,
    breachesKept,
    resolutionLeftKept,
    noFixAfterAction,
    exitExists,
    eventScenarioUnique,
    siblingsNotLinked,
  }

  /* ===== Свидетели посылок (PROC-72) =====
     Посылка инварианта выполнилась — иначе он в прогоне ничего не проверяет. Вместе с reached_<переход> их
     считает tools/check_quint_coverage.mjs: каждый — не меньше чем в 20 историях */

  // processedOnlyFinished: закрыт своим «Закрыть» с результатом «Обработан»
  val premise_processedClosed = INCIDENTS.exists(i => incOf(i).state == "closed" and incOf(i).closeResultId == "processed" and incOf(i).linkedTo == NOBODY)
  // holdBounded, вторая ветка: отложенный с записанным нарушением удержания
  val premise_holdBreach = INCIDENTS.exists(i => incOf(i).state == "on_hold" and hasBreach(incOf(i), "hold"))
  // Два привязанных к одному основному (linkedShape, linkedSharesBreaches, linkedSameScenario)
  val premise_twoLinked = INCIDENTS.exists(p => INCIDENTS.filter(i => incOf(i).linkedTo == p).size() >= 2)
  // Соседи — два появившихся инцидента одного события (eventScenarioUnique)
  val premise_siblings = INCIDENTS.exists(i => INCIDENTS.exists(j => i != j and incOf(i).state != "" and incOf(j).state != "" and incOf(i).eventGuid == incOf(j).eventGuid))
}
