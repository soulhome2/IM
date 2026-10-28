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

  type Override = { eventType: List[str], priority: List[int], sourceGroup: List[str], scenario: List[str], sec: int }

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
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overridesBy: ["eventType", "priority", "sourceGroup", "scenario"], overrides: [{ eventType: [], priority: [100], sourceGroup: [], scenario: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], scenario: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], scenario: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], scenario: [], sec: 1800 }], keepsLeft: true, startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overridesBy: ["eventType", "priority", "sourceGroup", "scenario"], overrides: [], keepsLeft: false, startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overridesBy: [], overrides: [], keepsLeft: false, startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
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

  // §11.1, ARCH-15 (В8). Основной выборки для действия со scope: primaryScenario — чей сценарий закрывается: основной по §11.3 (mergePrimary), а если его нет (отмечены только отложенные, ожидающие принятия, чужие) — из всех отмеченных самый срочный, у равных — появившийся раньше, у совсем равных — первый по порядку выборки (по возрастанию номера, как у mergePrimary). Списком из одного или пустым (выборка пуста)

  def bulkPrimary(xs: List[Incident], who: str): List[Incident] =
    { val p_16 = mergePrimary(xs, who)  (if ((p_16.length() > 0)) p_16 else { val top_17 = xs.select(e_18 => xs.foldl(true, (acc, k_19) => acc and (k_19.priority <= e_18.priority)))  { val first_20 = top_17.select(e_21 => top_17.foldl(true, (acc, k_22) => acc and (e_21.occurredAt <= k_22.occurredAt)))  (if ((first_20.length() > 0)) [first_20[0]] else []) } }) }

  // §8.1, §12. Человек на месте: его состояние — не «только просмотр» (перерыв, вышел)

  def onDuty(who: str): bool =
    not(settings.session.states.foldl(false, (acc, s_23) => acc or ((s_23.id == agentState(who)) and s_23.readOnly)))

  // §9. Кто получит уведомление: человек или участники дежурной группы — на месте и с доступом к объекту инцидента

  def recipients(whom: str, x: Incident): List[str] =
    (if (isGroup(whom)) members(whom) else [whom]).select(m_24 => (onDuty(m_24) and access(m_24, x)))

  // Таймер идёт: дедлайн есть и ещё не сработал (на потолке эскалации реакции — уже сработал)

  def timerRuns(x: Incident, id: str): bool =
    ((x.timers.get(id).due != 0) and (x.timers.get(id).fired != x.timers.get(id).due))

  // Закрыт без результата или результатом полной обработки (finish)

  def closedFinished(x: Incident): bool =
    ((x.closeResultId == "") or settings.closeResults.foldl(false, (acc, i_25) => acc or ((i_25.id == x.closeResultId) and i_25.finish)))

  // §8.3. Адресован автоэскалацией: адресат — адресат текущего уровня. Уровень после ручной передачи остаётся (RULE-76), но адресат уже другой

  def escalatedTo(x: Incident): bool =
    ((x.escalationLevel > 0) and settings.escalation.levels.foldl(false, (acc, l_26) => acc or ((l_26.level == x.escalationLevel) and (l_26.target == addressee(x)))))

  def isDone(x: Incident): bool =
    settings.states.foldl(false, (acc, s_27) => acc or ((s_27.id == x.state) and (s_27.category == "done")))

  // §5, §7, ARCH-15. Закрыт «Ложной тревогой». Тревога ложная, когда так закрыты сам инцидент и все его соседи, видимые смотрящему (alarm.allFalseAlarm карточки). Определение — для сервера и бэкенда, переходы его не используют

  def closedFalseAlarm(x: Incident): bool =
    (isDone(x) and (x.closeResultId == "false_alarm"))

  // Инцидент по id — списком из одного или пустым

  def byId(xs: List[Incident], id: str): List[Incident] =
    xs.select(e_28 => (e_28.id == id))

  // §5, §8.1. Доступ к объекту: человеку — по его ролям, группе — хотя бы у одного участника

  def hasAccess(who: str, x: Incident): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_29) => acc or access(m_29, x)) else (isOperator(who) and access(who, x)))

  def canAcceptPerson(m: str, x: Incident): bool =
    (can(m, "incident:accept") and access(m, x))

  // §8.1. Может ли принять: право «Принимать» и доступ к объекту; группа — если хотя бы один участник, кроме except: у него инцидент уже есть (RULE-93)

  def canAccept(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_30) => acc or ((m_30 != except) and canAcceptPerson(m_30, x))) else canAcceptPerson(who, x))

  // §8.1. Дежурная группа человека — первая, в которую он входит

  def dutyGroupOf(who: str): str =
    { val gs_31 = dutyGroups.select(g_32 => members(g_32).foldl(false, (acc, y33) => acc or y33 == who))  (if ((gs_31.length() > 0)) gs_31[0] else "") }

  // §12.1. Человек вошёл в МИ: на месте или на перерыве, но не вышел (RULE-100)

  def signedIn(who: str): bool =
    (agentState(who) != "offline")

  // §8.3, RULE-100. Адресат уровня эскалации может принять сейчас: как canAccept, и принимающий не вышел из МИ; вышедшему человеку инцидент уйдёт его дежурной группе (addressee_signed_out_to_group) — уровень доступен, если в ней кто-то, кроме except, не вышел и может принять. Перерыв не мешает (§12.1)

  def canAcceptNow(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_34) => acc or (((m_34 != except) and signedIn(m_34)) and canAcceptPerson(m_34, x))) else (canAcceptPerson(who, x) and (signedIn(who) or { val g_35 = dutyGroupOf(who)  ((g_35 != "") and members(g_35).foldl(false, (acc, m_36) => acc or ((((m_36 != except) and (m_36 != who)) and signedIn(m_36)) and canAcceptPerson(m_36, x)))) })))

  // §8.3. Уровни автоэскалации выше текущего и не выше потолка, адресат которых может принять сейчас (canAcceptNow, RULE-100); уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)

  def nextLevels(x: Incident): List[Level] =
    settings.escalation.levels.select(l_37 => ((((l_37.level > x.escalationLevel) and (l_37.level <= settings.escalation.maxLevel)) and (l_37.target != addressee(x))) and canAcceptNow(l_37.target, x, x.owner)))

  // §2.2. Результаты закрытия, которые этот оператор может выбрать для инцидента

  def closeOptions(who: str, x: Incident, surface: str): List[CloseResultItem] =
    settings.closeResults.select(i_38 => (((can(who, i_38.permission) and i_38.fromStates.foldl(false, (acc, y39) => acc or y39 == x.state)) and not((i_38.ownerOnlyInStates.foldl(false, (acc, y40) => acc or y40 == x.state) and (x.owner != who)))) and (((surface == "") or (i_38.surfaces.length() == 0)) or i_38.surfaces.foldl(false, (acc, y41) => acc or y41 == surface))))

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
    { val ls_42 = nextLevels(x)  ls_42.select(l_43 => ls_42.foldl(true, (acc, k_44) => acc and (l_43.level <= k_44.level))) }

  def levelUpTarget(x: Incident): str =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].target else "")

  def levelUpNumber(x: Incident): int =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].level else 0)

  def timerDef(id: str): TimerDef =
    settings.timerDefs.select(t_45 => (t_45.id == id))[0]

  // Сколько условий у строки overrides: чем больше, тем строка специфичнее

  def overrideKeys(o: Override): int =
    (((o.eventType.length() + o.priority.length()) + o.sourceGroup.length()) + o.scenario.length())

  // §4, правило 2. Старшинство строки уточнения: сначала число условий, при равном числе строка со сценарием старше (решение 2026-10-28)

  def overrideRank(o: Override): int =
    ((overrideKeys(o) * 2) + o.scenario.length())

  def overrideMatches(x: Incident, o: Override): bool =
    (((((o.eventType.length() == 0) or (o.eventType[0] == x.eventType)) and ((o.priority.length() == 0) or (o.priority[0] == x.priority))) and ((o.sourceGroup.length() == 0) or inSourceGroup(x, o.sourceGroup[0]))) and ((o.scenario.length() == 0) or (o.scenario[0] == x.scenario)))

  // §4, правило 2. Строка уточнения учитывается, только если все её признаки — из overridesBy таймера (ARCH-11)

  def overrideAllowed(t: TimerDef, o: Override): bool =
    (((((o.eventType.length() == 0) or t.overridesBy.foldl(false, (acc, y46) => acc or y46 == "eventType")) and ((o.priority.length() == 0) or t.overridesBy.foldl(false, (acc, y47) => acc or y47 == "priority"))) and ((o.sourceGroup.length() == 0) or t.overridesBy.foldl(false, (acc, y48) => acc or y48 == "sourceGroup"))) and ((o.scenario.length() == 0) or t.overridesBy.foldl(false, (acc, y49) => acc or y49 == "scenario")))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (больше условий; при равном числе — со сценарием; при равных и этом — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_50 = t.overrides.select(o_51 => (overrideAllowed(t, o_51) and overrideMatches(x, o_51)))  (if ((ms_50.length() > 0)) ms_50.select(o_52 => ms_50.foldl(true, (acc, k_53) => acc and (overrideRank(k_53) <= overrideRank(o_52))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold). У причины с deadlineFromIdle («Нет связи») — порог возврата в очередь минус порог удержания, не меньше 0: срок причины и возврат по молчанию совпадают при любых порогах (RULE-118, RULE-129, RULE-132). Причины нет — -1, срок не ставится. Срок у причины обязателен, кроме deadlineFromIdle (§4, правило 7; RULE-135, check_machine.py): ветка «maxMinutes пуст» — подстраховка

  def holdSec(x: Incident): int =
    { val rs_54 = settings.holdReasons.select(r_55 => (r_55.id == x.holdReasonId))  (if ((rs_54.length() == 0)) (0 - 1) else (if (rs_54[0].deadlineFromIdle) (if ((settings.session.idleReleaseSec > settings.session.idleHoldSec)) (settings.session.idleReleaseSec - settings.session.idleHoldSec) else 0) else (if ((rs_54[0].maxMinutes.length() > 0)) (rs_54[0].maxMinutes[0] * 60) else (0 - 1)))) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_56 = settings.escalation.levels.select(l_57 => (l_57.level == x.escalationLevel))  (if ((ls_56.length() > 0)) ls_56[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_58 = x.timers.get(id)  (if ((t_58.due != 0)) (if (((t_58.due - now) > 0)) (t_58.due - now) else 0) else (if (t_58.paused) t_58.left else (0 - 1))) }

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
    { val ks_59 = r.conditions.select(c_60 => conditionMatches(c_60, e)).foldl([], (acc, c_61) => acc.append(conditionRank(c_61)))  (if ((ks_59.length() == 0)) (0 - 1) else ks_59.select(k_62 => ks_59.foldl(true, (acc, j_63) => acc and (j_63 <= k_62)))[0]) }

  // §14.5, ARCH-15. Правило подошло событию: у него есть сценарий и подошло хоть одно условие. Правило без сценария в выборе не участвует

  def ruleMatches(r: Rule, e: Event): bool =
    ((r.scenarios.length() > 0) and r.conditions.foldl(false, (acc, c_64) => acc or conditionMatches(c_64, e)))

  // §14.5, ARCH-15 (решение пользователя 2026-10-28). Правило a старше b для события — строго: точнее условие; при равной точности — выше приоритет; при равном приоритете — раньше создано. Полное равенство — ни одно не старше: решает порядок списка правил

  def ruleBeats(a: Rule, b: Rule, e: Event): bool =
    { val ra_65 = ruleRank(a, e)  { val rb_66 = ruleRank(b, e)  ((ra_65 > rb_66) or ((ra_65 == rb_66) and ((a.priority > b.priority) or ((a.priority == b.priority) and (a.createdAt < b.createdAt))))) } }

  // §14.5, ARCH-15. Правило-победитель сценария s для события: из подошедших правил с этим сценарием — те, кого не старше ни одно; сервер берёт первое по порядку списка. От него приоритет и ruleGuid инцидента

  def ruleFor(rules: List[Rule], e: Event, s: str): List[Rule] =
    { val ms_67 = rules.select(r_68 => (ruleMatches(r_68, e) and r_68.scenarios.foldl(false, (acc, y69) => acc or y69 == s)))  ms_67.select(r_70 => not(ms_67.foldl(false, (acc, o_71) => acc or ruleBeats(o_71, r_70, e)))) }

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_72 => (e_72.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_73 => ((e_73.id != p.id) and inGroupAt(e_73, p, at)))

  // §14.5, ARCH-15. Соседи — инциденты того же события, кроме самого x: другие службы той же тревоги. Не привязка §11: у каждого свой владелец, сроки и закрытие

  def siblingsOf(incidents: List[Incident], x: Incident): List[Incident] =
    incidents.select(s_74 => (((x.eventGuid != "") and (s_74.eventGuid == x.eventGuid)) and (s_74.id != x.id)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w75 = if (not(timerDef(timerId).pausable)) {
      val sec_76 = timerSec(w0.inc.get(iid), timerId, "")
      val w77 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_76 < 0)) 0 else (c.now + (sec_76 * 1000))) }) }) }
      val w78 = { ...w77, inc: w77.inc.set(iid, { ...w77.inc.get(iid), timers: w77.inc.get(iid).timers.set(timerId, { ...w77.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w78
    } else {
      val w79 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_80 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w81 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_80 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_80)) }) }) }
      val w82 = { ...w81, inc: w81.inc.set(iid, { ...w81.inc.get(iid), timers: w81.inc.get(iid).timers.set(timerId, { ...w81.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w83 = { ...w82, inc: w82.inc.set(iid, { ...w82.inc.get(iid), timers: w82.inc.get(iid).timers.set(timerId, { ...w82.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w83
    } else w0
      w79
    }
    w75
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w84 = if (not(timerDef(timerId).pausable)) {
      val w85 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w86 = { ...w85, inc: w85.inc.set(iid, { ...w85.inc.get(iid), timers: w85.inc.get(iid).timers.set(timerId, { ...w85.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w86
    } else {
      val w87 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w88 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w89 = { ...w88, inc: w88.inc.set(iid, { ...w88.inc.get(iid), timers: w88.inc.get(iid).timers.set(timerId, { ...w88.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w90 = { ...w89, inc: w89.inc.set(iid, { ...w89.inc.get(iid), timers: w89.inc.get(iid).timers.set(timerId, { ...w89.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w90
    } else w0
      w87
    }
    w84
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_91 = ""
    val w92 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_91 }) }
    w92
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_93 = ""
    val w94 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_93 }) }
    w94
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_95 = 0
    val w96 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_95 }) }
    w96
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w97 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w98 = if (timerDef("reaction").startsOnce) {
      val w99 = ec_resumeTimer(w0, c, iid, "reaction")
      w99
    } else {
      val w100 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w101 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w102 = { ...w101, inc: w101.inc.set(iid, { ...w101.inc.get(iid), timers: w101.inc.get(iid).timers.set("reaction", { ...w101.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w103 = { ...w102, inc: w102.inc.set(iid, { ...w102.inc.get(iid), timers: w102.inc.get(iid).timers.set("reaction", { ...w102.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w103
    } else {
      val sec_104 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w105 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_104 < 0)) 0 else (c.now + (sec_104 * 1000))) }) }) }
      val w106 = { ...w105, inc: w105.inc.set(iid, { ...w105.inc.get(iid), timers: w105.inc.get(iid).timers.set("reaction", { ...w105.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w107 = { ...w106, inc: w106.inc.set(iid, { ...w106.inc.get(iid), timers: w106.inc.get(iid).timers.set("reaction", { ...w106.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w108 = { ...w107, inc: w107.inc.set(iid, { ...w107.inc.get(iid), timers: w107.inc.get(iid).timers.set("reaction", { ...w107.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w108
    }
      w100
    }
      w98
    }
    w97
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
    not(settings.session.states.foldl(false, (acc, s_109) => acc or ((s_109.id == agentState(c.me)) and s_109.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_110 = c.actor
    val w111 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_110 }) }
    w111
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w112 = if (timerDef("reaction").startsOnce) {
      val w113 = ec_pauseTimer(w0, c, iid, "reaction")
      w113
    } else {
      val w114 = if (false) {
      val w115 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w116 = { ...w115, inc: w115.inc.set(iid, { ...w115.inc.get(iid), timers: w115.inc.get(iid).timers.set("reaction", { ...w115.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w117 = { ...w116, inc: w116.inc.set(iid, { ...w116.inc.get(iid), timers: w116.inc.get(iid).timers.set("reaction", { ...w116.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w118 = { ...w117, inc: w117.inc.set(iid, { ...w117.inc.get(iid), timers: w117.inc.get(iid).timers.set("reaction", { ...w117.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w118
    } else {
      val w119 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_120 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w121 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_120) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w122 = { ...w121, inc: w121.inc.set(iid, { ...w121.inc.get(iid), timers: w121.inc.get(iid).timers.set("reaction", { ...w121.inc.get(iid).timers.get("reaction"), paused: keep_120 }) }) }
      val w123 = { ...w122, inc: w122.inc.set(iid, { ...w122.inc.get(iid), timers: w122.inc.get(iid).timers.set("reaction", { ...w122.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w124 = { ...w123, inc: w123.inc.set(iid, { ...w123.inc.get(iid), timers: w123.inc.get(iid).timers.set("reaction", { ...w123.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w124
    }
      w119
    }
      w114
    }
    w112
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w125 = if (not(timerDef("resolution").pausable)) {
      val sec_126 = timerSec(w0.inc.get(iid), "resolution", "")
      val w127 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_126 < 0)) 0 else (c.now + (sec_126 * 1000))) }) }) }
      val w128 = { ...w127, inc: w127.inc.set(iid, { ...w127.inc.get(iid), timers: w127.inc.get(iid).timers.set("resolution", { ...w127.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w128
    } else {
      val w129 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_130 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w131 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_130 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_130)) }) }) }
      val w132 = { ...w131, inc: w131.inc.set(iid, { ...w131.inc.get(iid), timers: w131.inc.get(iid).timers.set("resolution", { ...w131.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w133 = { ...w132, inc: w132.inc.set(iid, { ...w132.inc.get(iid), timers: w132.inc.get(iid).timers.set("resolution", { ...w132.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w133
    } else w0
      w129
    }
    w125
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
    not(settings.session.states.foldl(false, (acc, s_134) => acc or ((s_134.id == agentState(c.me)) and s_134.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_135 = c.actor
    val w136 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_135 }) }
    w136
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_137 = ""
    val w138 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_137 }) }
    w138
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w139 = if (timerDef("reaction").startsOnce) {
      val w140 = ec_pauseTimer(w0, c, iid, "reaction")
      w140
    } else {
      val w141 = if (false) {
      val w142 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w143 = { ...w142, inc: w142.inc.set(iid, { ...w142.inc.get(iid), timers: w142.inc.get(iid).timers.set("reaction", { ...w142.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w144 = { ...w143, inc: w143.inc.set(iid, { ...w143.inc.get(iid), timers: w143.inc.get(iid).timers.set("reaction", { ...w143.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w145 = { ...w144, inc: w144.inc.set(iid, { ...w144.inc.get(iid), timers: w144.inc.get(iid).timers.set("reaction", { ...w144.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w145
    } else {
      val w146 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_147 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w148 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_147) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w149 = { ...w148, inc: w148.inc.set(iid, { ...w148.inc.get(iid), timers: w148.inc.get(iid).timers.set("reaction", { ...w148.inc.get(iid).timers.get("reaction"), paused: keep_147 }) }) }
      val w150 = { ...w149, inc: w149.inc.set(iid, { ...w149.inc.get(iid), timers: w149.inc.get(iid).timers.set("reaction", { ...w149.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w151 = { ...w150, inc: w150.inc.set(iid, { ...w150.inc.get(iid), timers: w150.inc.get(iid).timers.set("reaction", { ...w150.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w151
    }
      w146
    }
      w141
    }
    w139
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w152 = if (not(timerDef("resolution").pausable)) {
      val sec_153 = timerSec(w0.inc.get(iid), "resolution", "")
      val w154 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_153 < 0)) 0 else (c.now + (sec_153 * 1000))) }) }) }
      val w155 = { ...w154, inc: w154.inc.set(iid, { ...w154.inc.get(iid), timers: w154.inc.get(iid).timers.set("resolution", { ...w154.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w155
    } else {
      val w156 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_157 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w158 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_157 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_157)) }) }) }
      val w159 = { ...w158, inc: w158.inc.set(iid, { ...w158.inc.get(iid), timers: w158.inc.get(iid).timers.set("resolution", { ...w158.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w160 = { ...w159, inc: w159.inc.set(iid, { ...w159.inc.get(iid), timers: w159.inc.get(iid).timers.set("resolution", { ...w159.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w160
    } else w0
      w156
    }
    w152
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
    not(settings.session.states.foldl(false, (acc, s_161) => acc or ((s_161.id == agentState(c.me)) and s_161.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_162 = ""
    val w163 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_162 }) }
    w163
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_164 = ""
    val w165 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_164 }) }
    w165
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
    not(settings.session.states.foldl(false, (acc, s_166) => acc or ((s_166.id == agentState(c.me)) and s_166.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_167 = c.form.reasonId
    val w168 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_167 }) }
    w168
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w169 = if (not(timerDef("resolution").pausable)) {
      val w170 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w171 = { ...w170, inc: w170.inc.set(iid, { ...w170.inc.get(iid), timers: w170.inc.get(iid).timers.set("resolution", { ...w170.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w171
    } else {
      val w172 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w173 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w174 = { ...w173, inc: w173.inc.set(iid, { ...w173.inc.get(iid), timers: w173.inc.get(iid).timers.set("resolution", { ...w173.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w175 = { ...w174, inc: w174.inc.set(iid, { ...w174.inc.get(iid), timers: w174.inc.get(iid).timers.set("resolution", { ...w174.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w175
    } else w0
      w172
    }
    w169
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w176 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w177 = if (timerDef("hold").startsOnce) {
      val w178 = ec_resumeTimer(w0, c, iid, "hold")
      w178
    } else {
      val w179 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w180 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w181 = { ...w180, inc: w180.inc.set(iid, { ...w180.inc.get(iid), timers: w180.inc.get(iid).timers.set("hold", { ...w180.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w182 = { ...w181, inc: w181.inc.set(iid, { ...w181.inc.get(iid), timers: w181.inc.get(iid).timers.set("hold", { ...w181.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w182
    } else {
      val sec_183 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w184 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_183 < 0)) 0 else (c.now + (sec_183 * 1000))) }) }) }
      val w185 = { ...w184, inc: w184.inc.set(iid, { ...w184.inc.get(iid), timers: w184.inc.get(iid).timers.set("hold", { ...w184.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w186 = { ...w185, inc: w185.inc.set(iid, { ...w185.inc.get(iid), timers: w185.inc.get(iid).timers.set("hold", { ...w185.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w187 = { ...w186, inc: w186.inc.set(iid, { ...w186.inc.get(iid), timers: w186.inc.get(iid).timers.set("hold", { ...w186.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w187
    }
      w179
    }
      w177
    }
    w176
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
    not(settings.session.states.foldl(false, (acc, s_188) => acc or ((s_188.id == agentState(c.me)) and s_188.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w189 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w189
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w190 = if (timerDef("hold").startsOnce) {
      val w191 = ec_pauseTimer(w0, c, iid, "hold")
      w191
    } else {
      val w192 = if (false) {
      val w193 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w194 = { ...w193, inc: w193.inc.set(iid, { ...w193.inc.get(iid), timers: w193.inc.get(iid).timers.set("hold", { ...w193.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w195 = { ...w194, inc: w194.inc.set(iid, { ...w194.inc.get(iid), timers: w194.inc.get(iid).timers.set("hold", { ...w194.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w196 = { ...w195, inc: w195.inc.set(iid, { ...w195.inc.get(iid), timers: w195.inc.get(iid).timers.set("hold", { ...w195.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w196
    } else {
      val w197 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_198 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w199 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_198) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w200 = { ...w199, inc: w199.inc.set(iid, { ...w199.inc.get(iid), timers: w199.inc.get(iid).timers.set("hold", { ...w199.inc.get(iid).timers.get("hold"), paused: keep_198 }) }) }
      val w201 = { ...w200, inc: w200.inc.set(iid, { ...w200.inc.get(iid), timers: w200.inc.get(iid).timers.set("hold", { ...w200.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w202 = { ...w201, inc: w201.inc.set(iid, { ...w201.inc.get(iid), timers: w201.inc.get(iid).timers.set("hold", { ...w201.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w202
    }
      w197
    }
      w192
    }
    w190
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w203 = if (not(timerDef("resolution").pausable)) {
      val sec_204 = timerSec(w0.inc.get(iid), "resolution", "")
      val w205 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_204 < 0)) 0 else (c.now + (sec_204 * 1000))) }) }) }
      val w206 = { ...w205, inc: w205.inc.set(iid, { ...w205.inc.get(iid), timers: w205.inc.get(iid).timers.set("resolution", { ...w205.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w206
    } else {
      val w207 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_208 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w209 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_208 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_208)) }) }) }
      val w210 = { ...w209, inc: w209.inc.set(iid, { ...w209.inc.get(iid), timers: w209.inc.get(iid).timers.set("resolution", { ...w209.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w211 = { ...w210, inc: w210.inc.set(iid, { ...w210.inc.get(iid), timers: w210.inc.get(iid).timers.set("resolution", { ...w210.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w211
    } else w0
      w207
    }
    w203
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
    not(settings.session.states.foldl(false, (acc, s_212) => acc or ((s_212.id == agentState(c.me)) and s_212.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_213 = ""
    val w214 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_213 }) }
    w214
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w215 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w215
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w216 = if (not(timerDef("resolution").pausable)) {
      val w217 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w218 = { ...w217, inc: w217.inc.set(iid, { ...w217.inc.get(iid), timers: w217.inc.get(iid).timers.set("resolution", { ...w217.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w218
    } else {
      val w219 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w220 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w221 = { ...w220, inc: w220.inc.set(iid, { ...w220.inc.get(iid), timers: w220.inc.get(iid).timers.set("resolution", { ...w220.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w222 = { ...w221, inc: w221.inc.set(iid, { ...w221.inc.get(iid), timers: w221.inc.get(iid).timers.set("resolution", { ...w221.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w222
    } else w0
      w219
    }
    w216
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w223 = if (timerDef("hold").startsOnce) {
      val w224 = ec_pauseTimer(w0, c, iid, "hold")
      w224
    } else {
      val w225 = if (false) {
      val w226 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w227 = { ...w226, inc: w226.inc.set(iid, { ...w226.inc.get(iid), timers: w226.inc.get(iid).timers.set("hold", { ...w226.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w228 = { ...w227, inc: w227.inc.set(iid, { ...w227.inc.get(iid), timers: w227.inc.get(iid).timers.set("hold", { ...w227.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w229 = { ...w228, inc: w228.inc.set(iid, { ...w228.inc.get(iid), timers: w228.inc.get(iid).timers.set("hold", { ...w228.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w229
    } else {
      val w230 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_231 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w232 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_231) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w233 = { ...w232, inc: w232.inc.set(iid, { ...w232.inc.get(iid), timers: w232.inc.get(iid).timers.set("hold", { ...w232.inc.get(iid).timers.get("hold"), paused: keep_231 }) }) }
      val w234 = { ...w233, inc: w233.inc.set(iid, { ...w233.inc.get(iid), timers: w233.inc.get(iid).timers.set("hold", { ...w233.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w235 = { ...w234, inc: w234.inc.set(iid, { ...w234.inc.get(iid), timers: w234.inc.get(iid).timers.set("hold", { ...w234.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w235
    }
      w230
    }
      w225
    }
    w223
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w236 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w237 = if (timerDef("reaction").startsOnce) {
      val w238 = ec_resumeTimer(w0, c, iid, "reaction")
      w238
    } else {
      val w239 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w240 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w241 = { ...w240, inc: w240.inc.set(iid, { ...w240.inc.get(iid), timers: w240.inc.get(iid).timers.set("reaction", { ...w240.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w242 = { ...w241, inc: w241.inc.set(iid, { ...w241.inc.get(iid), timers: w241.inc.get(iid).timers.set("reaction", { ...w241.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w242
    } else {
      val sec_243 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w244 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_243 < 0)) 0 else (c.now + (sec_243 * 1000))) }) }) }
      val w245 = { ...w244, inc: w244.inc.set(iid, { ...w244.inc.get(iid), timers: w244.inc.get(iid).timers.set("reaction", { ...w244.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w246 = { ...w245, inc: w245.inc.set(iid, { ...w245.inc.get(iid), timers: w245.inc.get(iid).timers.set("reaction", { ...w245.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w247 = { ...w246, inc: w246.inc.set(iid, { ...w246.inc.get(iid), timers: w246.inc.get(iid).timers.set("reaction", { ...w246.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w247
    }
      w239
    }
      w237
    }
    w236
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
    not(settings.session.states.foldl(false, (acc, s_248) => acc or ((s_248.id == agentState(c.me)) and s_248.readOnly))),
    transferTargets.foldl(false, (acc, t_249) => acc or (offersTransferTo(c.me, t_249, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_250) => acc and (isDone(e_250) or hasAccess(t_249, e_250))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_251) => acc and (isDone(e_251) or hasAccess(c.form.targetId, e_251)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_252 = personOf(c.form.targetId)
    val w253 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_252 }) }
    w253
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_254 = groupOf(c.form.targetId)
    val w255 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_254 }) }
    w255
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w256 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w256
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w257 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w257
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w258 = if (not(timerDef("resolution").pausable)) {
      val w259 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w260 = { ...w259, inc: w259.inc.set(iid, { ...w259.inc.get(iid), timers: w259.inc.get(iid).timers.set("resolution", { ...w259.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w260
    } else {
      val w261 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w262 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w263 = { ...w262, inc: w262.inc.set(iid, { ...w262.inc.get(iid), timers: w262.inc.get(iid).timers.set("resolution", { ...w262.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w264 = { ...w263, inc: w263.inc.set(iid, { ...w263.inc.get(iid), timers: w263.inc.get(iid).timers.set("resolution", { ...w263.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w264
    } else w0
      w261
    }
    w258
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w265 = if (timerDef("hold").startsOnce) {
      val w266 = ec_pauseTimer(w0, c, iid, "hold")
      w266
    } else {
      val w267 = if (false) {
      val w268 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w269 = { ...w268, inc: w268.inc.set(iid, { ...w268.inc.get(iid), timers: w268.inc.get(iid).timers.set("hold", { ...w268.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w270 = { ...w269, inc: w269.inc.set(iid, { ...w269.inc.get(iid), timers: w269.inc.get(iid).timers.set("hold", { ...w269.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w271 = { ...w270, inc: w270.inc.set(iid, { ...w270.inc.get(iid), timers: w270.inc.get(iid).timers.set("hold", { ...w270.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w271
    } else {
      val w272 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_273 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w274 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_273) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w275 = { ...w274, inc: w274.inc.set(iid, { ...w274.inc.get(iid), timers: w274.inc.get(iid).timers.set("hold", { ...w274.inc.get(iid).timers.get("hold"), paused: keep_273 }) }) }
      val w276 = { ...w275, inc: w275.inc.set(iid, { ...w275.inc.get(iid), timers: w275.inc.get(iid).timers.set("hold", { ...w275.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w277 = { ...w276, inc: w276.inc.set(iid, { ...w276.inc.get(iid), timers: w276.inc.get(iid).timers.set("hold", { ...w276.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w277
    }
      w272
    }
      w267
    }
    w265
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w278 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w279 = if (timerDef("reaction").startsOnce) {
      val w280 = ec_resumeTimer(w0, c, iid, "reaction")
      w280
    } else {
      val w281 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w282 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w283 = { ...w282, inc: w282.inc.set(iid, { ...w282.inc.get(iid), timers: w282.inc.get(iid).timers.set("reaction", { ...w282.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w284 = { ...w283, inc: w283.inc.set(iid, { ...w283.inc.get(iid), timers: w283.inc.get(iid).timers.set("reaction", { ...w283.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w284
    } else {
      val sec_285 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w286 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_285 < 0)) 0 else (c.now + (sec_285 * 1000))) }) }) }
      val w287 = { ...w286, inc: w286.inc.set(iid, { ...w286.inc.get(iid), timers: w286.inc.get(iid).timers.set("reaction", { ...w286.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w288 = { ...w287, inc: w287.inc.set(iid, { ...w287.inc.get(iid), timers: w287.inc.get(iid).timers.set("reaction", { ...w287.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w289 = { ...w288, inc: w288.inc.set(iid, { ...w288.inc.get(iid), timers: w288.inc.get(iid).timers.set("reaction", { ...w288.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w289
    }
      w281
    }
      w279
    }
    w278
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_290 = c.before.owner
    val w291 = if (((whom_290 != "") and (whom_290 != c.actor))) w0 else w0
    w291
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_292 = addressee(w0.inc.get(iid))
    val w293 = if (((whom_292 != "") and (whom_292 != c.actor))) w0 else w0
    w293
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
    not(settings.session.states.foldl(false, (acc, s_294) => acc or ((s_294.id == agentState(c.me)) and s_294.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_295 = c.actor
    val w296 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_295 }) }
    w296
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_297 = ""
    val w298 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_297 }) }
    w298
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w299 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w299
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w300 = if (timerDef("reaction").startsOnce) {
      val w301 = ec_pauseTimer(w0, c, iid, "reaction")
      w301
    } else {
      val w302 = if (false) {
      val w303 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w304 = { ...w303, inc: w303.inc.set(iid, { ...w303.inc.get(iid), timers: w303.inc.get(iid).timers.set("reaction", { ...w303.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w305 = { ...w304, inc: w304.inc.set(iid, { ...w304.inc.get(iid), timers: w304.inc.get(iid).timers.set("reaction", { ...w304.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w306 = { ...w305, inc: w305.inc.set(iid, { ...w305.inc.get(iid), timers: w305.inc.get(iid).timers.set("reaction", { ...w305.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w306
    } else {
      val w307 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_308 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w309 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_308) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w310 = { ...w309, inc: w309.inc.set(iid, { ...w309.inc.get(iid), timers: w309.inc.get(iid).timers.set("reaction", { ...w309.inc.get(iid).timers.get("reaction"), paused: keep_308 }) }) }
      val w311 = { ...w310, inc: w310.inc.set(iid, { ...w310.inc.get(iid), timers: w310.inc.get(iid).timers.set("reaction", { ...w310.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w312 = { ...w311, inc: w311.inc.set(iid, { ...w311.inc.get(iid), timers: w311.inc.get(iid).timers.set("reaction", { ...w311.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w312
    }
      w307
    }
      w302
    }
    w300
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w313 = if (timerDef("hold").startsOnce) {
      val w314 = ec_pauseTimer(w0, c, iid, "hold")
      w314
    } else {
      val w315 = if (false) {
      val w316 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w317 = { ...w316, inc: w316.inc.set(iid, { ...w316.inc.get(iid), timers: w316.inc.get(iid).timers.set("hold", { ...w316.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w318 = { ...w317, inc: w317.inc.set(iid, { ...w317.inc.get(iid), timers: w317.inc.get(iid).timers.set("hold", { ...w317.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w319 = { ...w318, inc: w318.inc.set(iid, { ...w318.inc.get(iid), timers: w318.inc.get(iid).timers.set("hold", { ...w318.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w319
    } else {
      val w320 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_321 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w322 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_321) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w323 = { ...w322, inc: w322.inc.set(iid, { ...w322.inc.get(iid), timers: w322.inc.get(iid).timers.set("hold", { ...w322.inc.get(iid).timers.get("hold"), paused: keep_321 }) }) }
      val w324 = { ...w323, inc: w323.inc.set(iid, { ...w323.inc.get(iid), timers: w323.inc.get(iid).timers.set("hold", { ...w323.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w325 = { ...w324, inc: w324.inc.set(iid, { ...w324.inc.get(iid), timers: w324.inc.get(iid).timers.set("hold", { ...w324.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w325
    }
      w320
    }
      w315
    }
    w313
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w326 = if (not(timerDef("resolution").pausable)) {
      val sec_327 = timerSec(w0.inc.get(iid), "resolution", "")
      val w328 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_327 < 0)) 0 else (c.now + (sec_327 * 1000))) }) }) }
      val w329 = { ...w328, inc: w328.inc.set(iid, { ...w328.inc.get(iid), timers: w328.inc.get(iid).timers.set("resolution", { ...w328.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w329
    } else {
      val w330 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_331 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w332 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_331 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_331)) }) }) }
      val w333 = { ...w332, inc: w332.inc.set(iid, { ...w332.inc.get(iid), timers: w332.inc.get(iid).timers.set("resolution", { ...w332.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w334 = { ...w333, inc: w333.inc.set(iid, { ...w333.inc.get(iid), timers: w333.inc.get(iid).timers.set("resolution", { ...w333.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w334
    } else w0
      w330
    }
    w326
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
    val whom_335 = c.before.owner
    val w336 = if (((whom_335 != "") and (whom_335 != c.actor))) w0 else w0
    w336
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
    not(settings.session.states.foldl(false, (acc, s_337) => acc or ((s_337.id == agentState(c.me)) and s_337.readOnly))),
    { val os_338 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_338.foldl(false, (acc, o_339) => acc or ((o_339.id == c.form.resultId) and stepsOk(o_339, world.inc.get(iid)))) else os_338.foldl(false, (acc, o_340) => acc or stepsOk(o_340, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_341 = c.actor
    val w342 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_341 }) }
    w342
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_343 = ""
    val w344 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_343 }) }
    w344
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_345 = c.actor
    val w346 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_345 }) }
    w346
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_347 = c.now
    val w348 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_347 }) }
    w348
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_349 = c.form.resultId
    val w350 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_349 }) }
    w350
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_351 = c.form.causeId
    val w352 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_351 }) }
    w352
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_353 = c.form.comment
    val w354 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_353 }) }
    w354
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w355 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w355
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w356 = if (timerDef("reaction").startsOnce) {
      val w357 = ec_pauseTimer(w0, c, iid, "reaction")
      w357
    } else {
      val w358 = if (true) {
      val w359 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w360 = { ...w359, inc: w359.inc.set(iid, { ...w359.inc.get(iid), timers: w359.inc.get(iid).timers.set("reaction", { ...w359.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w361 = { ...w360, inc: w360.inc.set(iid, { ...w360.inc.get(iid), timers: w360.inc.get(iid).timers.set("reaction", { ...w360.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w362 = { ...w361, inc: w361.inc.set(iid, { ...w361.inc.get(iid), timers: w361.inc.get(iid).timers.set("reaction", { ...w361.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w362
    } else {
      val w363 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_364 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w365 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_364) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w366 = { ...w365, inc: w365.inc.set(iid, { ...w365.inc.get(iid), timers: w365.inc.get(iid).timers.set("reaction", { ...w365.inc.get(iid).timers.get("reaction"), paused: keep_364 }) }) }
      val w367 = { ...w366, inc: w366.inc.set(iid, { ...w366.inc.get(iid), timers: w366.inc.get(iid).timers.set("reaction", { ...w366.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w368 = { ...w367, inc: w367.inc.set(iid, { ...w367.inc.get(iid), timers: w367.inc.get(iid).timers.set("reaction", { ...w367.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w368
    }
      w363
    }
      w358
    }
    w356
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
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

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w376 = if (timerDef("hold").startsOnce) {
      val w377 = ec_pauseTimer(w0, c, iid, "hold")
      w377
    } else {
      val w378 = if (false) {
      val w379 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w380 = { ...w379, inc: w379.inc.set(iid, { ...w379.inc.get(iid), timers: w379.inc.get(iid).timers.set("hold", { ...w379.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w381 = { ...w380, inc: w380.inc.set(iid, { ...w380.inc.get(iid), timers: w380.inc.get(iid).timers.set("hold", { ...w380.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w382 = { ...w381, inc: w381.inc.set(iid, { ...w381.inc.get(iid), timers: w381.inc.get(iid).timers.set("hold", { ...w381.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w382
    } else {
      val w383 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_384 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w385 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_384) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w386 = { ...w385, inc: w385.inc.set(iid, { ...w385.inc.get(iid), timers: w385.inc.get(iid).timers.set("hold", { ...w385.inc.get(iid).timers.get("hold"), paused: keep_384 }) }) }
      val w387 = { ...w386, inc: w386.inc.set(iid, { ...w386.inc.get(iid), timers: w386.inc.get(iid).timers.set("hold", { ...w386.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w388 = { ...w387, inc: w387.inc.set(iid, { ...w387.inc.get(iid), timers: w387.inc.get(iid).timers.set("hold", { ...w387.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w388
    }
      w383
    }
      w378
    }
    w376
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {
    val w389 = if (["false_alarm"].foldl(false, (acc, y390) => acc or y390 == c.form.resultId)) {
      val w391 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_396 => not(isDone(x_396))).foldl([], (acc, x394) => acc.append(x394.id)).foldl(w0, (wf392, sId393) => {
      val w395 = if (((addressee(wf392.inc.get(sId393)) != "") and (addressee(wf392.inc.get(sId393)) != c.actor))) wf392 else wf392
      w395
    })
      w391
    } else w0
    w389
  }

  def e_close_13(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_14(w0: World, c: Ctx, iid: str): World = {

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
    val w15 = e_close_14(w14, c1, iid)
    w15
  }

  // reopen: manual → in_progress

  def ok_reopen(c: Ctx, iid: str): bool = all {
    Set("closed").contains(world.inc.get(iid).state),
    can(c.me, "incident:reopen"),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_397) => acc or ((s_397.id == agentState(c.me)) and s_397.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_398 = c.actor
    val w399 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_398 }) }
    w399
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w400 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_401 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w402 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w403 = { ...w402, inc: w402.inc.set(iid, { ...w402.inc.get(iid), linkedTo: "" }) }
      val w404 = { ...w403, inc: w403.inc.set(iid, { ...w403.inc.get(iid), linkedAt: 0 }) }
      val w405 = if (((ps_401.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w404 else w404
      val w406 = if (("workflow.journal.linked_reopened" != "")) {
      val w407 = ps_401.foldl([], (acc, x410) => acc.append(x410.id)).foldl(w405, (wf408, pId409) => wf408)
      w407
    } else w405
      w406
    } else {
      val w411 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w412 = { ...w411, inc: w411.inc.set(iid, { ...w411.inc.get(iid), linkedAt: 0 }) }
      w412
    }
    w400
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_413 = ""
    val w414 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_413 }) }
    w414
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_415 = ""
    val w416 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_415 }) }
    w416
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_417 = ""
    val w418 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_417 }) }
    w418
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_419 = 0
    val w420 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_419 }) }
    w420
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_421 = ""
    val w422 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_421 }) }
    w422
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val sec_423 = settings.limits.reopenResolutionSec
    val w424 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_423 > 0)) sec_423 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w425 = { ...w424, inc: w424.inc.set(iid, { ...w424.inc.get(iid), timers: w424.inc.get(iid).timers.set("resolution", { ...w424.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w426 = { ...w425, inc: w425.inc.set(iid, { ...w425.inc.get(iid), timers: w425.inc.get(iid).timers.set("resolution", { ...w425.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w426
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val w427 = if (timerDef("reaction").startsOnce) {
      val w428 = ec_pauseTimer(w0, c, iid, "reaction")
      w428
    } else {
      val w429 = if (true) {
      val w430 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w431 = { ...w430, inc: w430.inc.set(iid, { ...w430.inc.get(iid), timers: w430.inc.get(iid).timers.set("reaction", { ...w430.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w432 = { ...w431, inc: w431.inc.set(iid, { ...w431.inc.get(iid), timers: w431.inc.get(iid).timers.set("reaction", { ...w431.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w433 = { ...w432, inc: w432.inc.set(iid, { ...w432.inc.get(iid), timers: w432.inc.get(iid).timers.set("reaction", { ...w432.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w433
    } else {
      val w434 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_435 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w436 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_435) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w437 = { ...w436, inc: w436.inc.set(iid, { ...w436.inc.get(iid), timers: w436.inc.get(iid).timers.set("reaction", { ...w436.inc.get(iid).timers.get("reaction"), paused: keep_435 }) }) }
      val w438 = { ...w437, inc: w437.inc.set(iid, { ...w437.inc.get(iid), timers: w437.inc.get(iid).timers.set("reaction", { ...w437.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w439 = { ...w438, inc: w438.inc.set(iid, { ...w438.inc.get(iid), timers: w438.inc.get(iid).timers.set("reaction", { ...w438.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w439
    }
      w434
    }
      w429
    }
    w427
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
    { val t_440 = world.inc.get(iid).timers.get("reaction")  (((t_440.due != 0) and (t_440.due <= c.now)) and (t_440.fired != t_440.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_441 = personOf(levelUpTarget(c.before))
    val w442 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_441 }) }
    w442
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_443 = groupOf(levelUpTarget(c.before))
    val w444 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_443 }) }
    w444
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_445 = levelUpNumber(c.before)
    val w446 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_445 }) }
    w446
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w447 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w447
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w448 = if (not(timerDef("resolution").pausable)) {
      val w449 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w450 = { ...w449, inc: w449.inc.set(iid, { ...w449.inc.get(iid), timers: w449.inc.get(iid).timers.set("resolution", { ...w449.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w450
    } else {
      val w451 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w452 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w453 = { ...w452, inc: w452.inc.set(iid, { ...w452.inc.get(iid), timers: w452.inc.get(iid).timers.set("resolution", { ...w452.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w454 = { ...w453, inc: w453.inc.set(iid, { ...w453.inc.get(iid), timers: w453.inc.get(iid).timers.set("resolution", { ...w453.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w454
    } else w0
      w451
    }
    w448
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w455 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w456 = if (timerDef("reaction").startsOnce) {
      val w457 = ec_resumeTimer(w0, c, iid, "reaction")
      w457
    } else {
      val w458 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w459 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w460 = { ...w459, inc: w459.inc.set(iid, { ...w459.inc.get(iid), timers: w459.inc.get(iid).timers.set("reaction", { ...w459.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w461 = { ...w460, inc: w460.inc.set(iid, { ...w460.inc.get(iid), timers: w460.inc.get(iid).timers.set("reaction", { ...w460.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w461
    } else {
      val sec_462 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w463 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_462 < 0)) 0 else (c.now + (sec_462 * 1000))) }) }) }
      val w464 = { ...w463, inc: w463.inc.set(iid, { ...w463.inc.get(iid), timers: w463.inc.get(iid).timers.set("reaction", { ...w463.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w465 = { ...w464, inc: w464.inc.set(iid, { ...w464.inc.get(iid), timers: w464.inc.get(iid).timers.set("reaction", { ...w464.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w466 = { ...w465, inc: w465.inc.set(iid, { ...w465.inc.get(iid), timers: w465.inc.get(iid).timers.set("reaction", { ...w465.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w466
    }
      w458
    }
      w456
    }
    w455
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_467 = addressee(w0.inc.get(iid))
    val w468 = if (((whom_467 != "") and (whom_467 != c.actor))) w0 else w0
    w468
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
    { val t_469 = world.inc.get(iid).timers.get("reaction")  (((t_469.due != 0) and (t_469.due <= c.now)) and (t_469.fired != t_469.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_470 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w471 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_470) }) }
    val w472 = { ...w471, inc: w471.inc.set(iid, { ...w471.inc.get(iid), slaBreached: true }) }
    val w473 = groupMembersAt(incs(w0), w472.inc.get(iid), c.deadline).foldl([], (acc, x476) => acc.append(x476.id)).foldl(w472, (wf474, eId475) => {
      val w477 = { ...wf474, inc: wf474.inc.set(eId475, { ...wf474.inc.get(eId475), breaches: wf474.inc.get(eId475).breaches.append(breach_470) }) }
      val w478 = { ...w477, inc: w477.inc.set(eId475, { ...w477.inc.get(eId475), slaBreached: true }) }
      w478
    })
    w473
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w479 = if (timerDef("reaction").startsOnce) {
      val w480 = ec_pauseTimer(w0, c, iid, "reaction")
      w480
    } else {
      val w481 = if (false) {
      val w482 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w483 = { ...w482, inc: w482.inc.set(iid, { ...w482.inc.get(iid), timers: w482.inc.get(iid).timers.set("reaction", { ...w482.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w484 = { ...w483, inc: w483.inc.set(iid, { ...w483.inc.get(iid), timers: w483.inc.get(iid).timers.set("reaction", { ...w483.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w485 = { ...w484, inc: w484.inc.set(iid, { ...w484.inc.get(iid), timers: w484.inc.get(iid).timers.set("reaction", { ...w484.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w485
    } else {
      val w486 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_487 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w488 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_487) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w489 = { ...w488, inc: w488.inc.set(iid, { ...w488.inc.get(iid), timers: w488.inc.get(iid).timers.set("reaction", { ...w488.inc.get(iid).timers.get("reaction"), paused: keep_487 }) }) }
      val w490 = { ...w489, inc: w489.inc.set(iid, { ...w489.inc.get(iid), timers: w489.inc.get(iid).timers.set("reaction", { ...w489.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w491 = { ...w490, inc: w490.inc.set(iid, { ...w490.inc.get(iid), timers: w490.inc.get(iid).timers.set("reaction", { ...w490.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w491
    }
      w486
    }
      w481
    }
    w479
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_492 = settings.alerts.target
    val w493 = if (((whom_492 != "") and (whom_492 != c.actor))) w0 else w0
    w493
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
    { val t_494 = world.inc.get(iid).timers.get("reaction")  (((t_494.due != 0) and (t_494.due <= c.now)) and (t_494.fired != t_494.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_495 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w496 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_495) }) }
    val w497 = { ...w496, inc: w496.inc.set(iid, { ...w496.inc.get(iid), slaBreached: true }) }
    val w498 = groupMembersAt(incs(w0), w497.inc.get(iid), c.deadline).foldl([], (acc, x501) => acc.append(x501.id)).foldl(w497, (wf499, eId500) => {
      val w502 = { ...wf499, inc: wf499.inc.set(eId500, { ...wf499.inc.get(eId500), breaches: wf499.inc.get(eId500).breaches.append(breach_495) }) }
      val w503 = { ...w502, inc: w502.inc.set(eId500, { ...w502.inc.get(eId500), slaBreached: true }) }
      w503
    })
    w498
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w504 = if (timerDef("reaction").startsOnce) {
      val w505 = ec_pauseTimer(w0, c, iid, "reaction")
      w505
    } else {
      val w506 = if (false) {
      val w507 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w508 = { ...w507, inc: w507.inc.set(iid, { ...w507.inc.get(iid), timers: w507.inc.get(iid).timers.set("reaction", { ...w507.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w509 = { ...w508, inc: w508.inc.set(iid, { ...w508.inc.get(iid), timers: w508.inc.get(iid).timers.set("reaction", { ...w508.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w510 = { ...w509, inc: w509.inc.set(iid, { ...w509.inc.get(iid), timers: w509.inc.get(iid).timers.set("reaction", { ...w509.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w510
    } else {
      val w511 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_512 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w513 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_512) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w514 = { ...w513, inc: w513.inc.set(iid, { ...w513.inc.get(iid), timers: w513.inc.get(iid).timers.set("reaction", { ...w513.inc.get(iid).timers.get("reaction"), paused: keep_512 }) }) }
      val w515 = { ...w514, inc: w514.inc.set(iid, { ...w514.inc.get(iid), timers: w514.inc.get(iid).timers.set("reaction", { ...w514.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w516 = { ...w515, inc: w515.inc.set(iid, { ...w515.inc.get(iid), timers: w515.inc.get(iid).timers.set("reaction", { ...w515.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w516
    }
      w511
    }
      w506
    }
    w504
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_517 = settings.alerts.target
    val w518 = if (((whom_517 != "") and (whom_517 != c.actor))) w0 else w0
    w518
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
    { val t_519 = world.inc.get(iid).timers.get("resolution")  (((t_519.due != 0) and (t_519.due <= c.now)) and (t_519.fired != t_519.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_520 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w521 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_520) }) }
    val w522 = { ...w521, inc: w521.inc.set(iid, { ...w521.inc.get(iid), slaBreached: true }) }
    val w523 = groupMembersAt(incs(w0), w522.inc.get(iid), c.deadline).foldl([], (acc, x526) => acc.append(x526.id)).foldl(w522, (wf524, eId525) => {
      val w527 = { ...wf524, inc: wf524.inc.set(eId525, { ...wf524.inc.get(eId525), breaches: wf524.inc.get(eId525).breaches.append(breach_520) }) }
      val w528 = { ...w527, inc: w527.inc.set(eId525, { ...w527.inc.get(eId525), slaBreached: true }) }
      w528
    })
    w523
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_529 = settings.alerts.target
    val w530 = if (((whom_529 != "") and (whom_529 != c.actor))) w0 else w0
    w530
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
    { val t_531 = world.inc.get(iid).timers.get("resolution")  (((t_531.due != 0) and (t_531.due <= c.now)) and (t_531.fired != t_531.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_532 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w533 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_532) }) }
    val w534 = { ...w533, inc: w533.inc.set(iid, { ...w533.inc.get(iid), slaBreached: true }) }
    val w535 = groupMembersAt(incs(w0), w534.inc.get(iid), c.deadline).foldl([], (acc, x538) => acc.append(x538.id)).foldl(w534, (wf536, eId537) => {
      val w539 = { ...wf536, inc: wf536.inc.set(eId537, { ...wf536.inc.get(eId537), breaches: wf536.inc.get(eId537).breaches.append(breach_532) }) }
      val w540 = { ...w539, inc: w539.inc.set(eId537, { ...w539.inc.get(eId537), slaBreached: true }) }
      w540
    })
    w535
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_541 = personOf(levelUpTarget(c.before))
    val w542 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_541 }) }
    w542
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_543 = groupOf(levelUpTarget(c.before))
    val w544 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_543 }) }
    w544
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_545 = levelUpNumber(c.before)
    val w546 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_545 }) }
    w546
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w547 = if (not(timerDef("resolution").pausable)) {
      val w548 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w549 = { ...w548, inc: w548.inc.set(iid, { ...w548.inc.get(iid), timers: w548.inc.get(iid).timers.set("resolution", { ...w548.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w549
    } else {
      val w550 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w551 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w552 = { ...w551, inc: w551.inc.set(iid, { ...w551.inc.get(iid), timers: w551.inc.get(iid).timers.set("resolution", { ...w551.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w553 = { ...w552, inc: w552.inc.set(iid, { ...w552.inc.get(iid), timers: w552.inc.get(iid).timers.set("resolution", { ...w552.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w553
    } else w0
      w550
    }
    w547
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w554 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w555 = if (timerDef("reaction").startsOnce) {
      val w556 = ec_resumeTimer(w0, c, iid, "reaction")
      w556
    } else {
      val w557 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w558 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w559 = { ...w558, inc: w558.inc.set(iid, { ...w558.inc.get(iid), timers: w558.inc.get(iid).timers.set("reaction", { ...w558.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w560 = { ...w559, inc: w559.inc.set(iid, { ...w559.inc.get(iid), timers: w559.inc.get(iid).timers.set("reaction", { ...w559.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w560
    } else {
      val sec_561 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w562 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_561 < 0)) 0 else (c.now + (sec_561 * 1000))) }) }) }
      val w563 = { ...w562, inc: w562.inc.set(iid, { ...w562.inc.get(iid), timers: w562.inc.get(iid).timers.set("reaction", { ...w562.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w564 = { ...w563, inc: w563.inc.set(iid, { ...w563.inc.get(iid), timers: w563.inc.get(iid).timers.set("reaction", { ...w563.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w565 = { ...w564, inc: w564.inc.set(iid, { ...w564.inc.get(iid), timers: w564.inc.get(iid).timers.set("reaction", { ...w564.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w565
    }
      w557
    }
      w555
    }
    w554
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_566 = c.before.owner
    val w567 = if (((whom_566 != "") and (whom_566 != c.actor))) w0 else w0
    w567
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_568 = addressee(w0.inc.get(iid))
    val w569 = if (((whom_568 != "") and (whom_568 != c.actor))) w0 else w0
    w569
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
    { val t_570 = world.inc.get(iid).timers.get("resolution")  (((t_570.due != 0) and (t_570.due <= c.now)) and (t_570.fired != t_570.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_571 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w572 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_571) }) }
    val w573 = { ...w572, inc: w572.inc.set(iid, { ...w572.inc.get(iid), slaBreached: true }) }
    val w574 = groupMembersAt(incs(w0), w573.inc.get(iid), c.deadline).foldl([], (acc, x577) => acc.append(x577.id)).foldl(w573, (wf575, eId576) => {
      val w578 = { ...wf575, inc: wf575.inc.set(eId576, { ...wf575.inc.get(eId576), breaches: wf575.inc.get(eId576).breaches.append(breach_571) }) }
      val w579 = { ...w578, inc: w578.inc.set(eId576, { ...w578.inc.get(eId576), slaBreached: true }) }
      w579
    })
    w574
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_580 = settings.alerts.target
    val w581 = if (((whom_580 != "") and (whom_580 != c.actor))) w0 else w0
    w581
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
    { val t_582 = world.inc.get(iid).timers.get("hold")  (((t_582.due != 0) and (t_582.due <= c.now)) and (t_582.fired != t_582.due)) },
    not(["break", "no_link"].foldl(false, (acc, y583) => acc or y583 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_584 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w585 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_584) }) }
    val w586 = { ...w585, inc: w585.inc.set(iid, { ...w585.inc.get(iid), slaBreached: true }) }
    val w587 = groupMembersAt(incs(w0), w586.inc.get(iid), c.deadline).foldl([], (acc, x590) => acc.append(x590.id)).foldl(w586, (wf588, eId589) => {
      val w591 = { ...wf588, inc: wf588.inc.set(eId589, { ...wf588.inc.get(eId589), breaches: wf588.inc.get(eId589).breaches.append(breach_584) }) }
      val w592 = { ...w591, inc: w591.inc.set(eId589, { ...w591.inc.get(eId589), slaBreached: true }) }
      w592
    })
    w587
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_593 = settings.alerts.target
    val w594 = if (((whom_593 != "") and (whom_593 != c.actor))) w0 else w0
    w594
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
    { val t_595 = world.inc.get(iid).timers.get("hold")  (((t_595.due != 0) and (t_595.due <= c.now)) and (t_595.fired != t_595.due)) },
    ["break"].foldl(false, (acc, y596) => acc or y596 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_597 = ""
    val w598 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_597 }) }
    w598
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w599 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w599
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w600 = if (timerDef("hold").startsOnce) {
      val w601 = ec_pauseTimer(w0, c, iid, "hold")
      w601
    } else {
      val w602 = if (false) {
      val w603 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w604 = { ...w603, inc: w603.inc.set(iid, { ...w603.inc.get(iid), timers: w603.inc.get(iid).timers.set("hold", { ...w603.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w605 = { ...w604, inc: w604.inc.set(iid, { ...w604.inc.get(iid), timers: w604.inc.get(iid).timers.set("hold", { ...w604.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w606 = { ...w605, inc: w605.inc.set(iid, { ...w605.inc.get(iid), timers: w605.inc.get(iid).timers.set("hold", { ...w605.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w606
    } else {
      val w607 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_608 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w609 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_608) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w610 = { ...w609, inc: w609.inc.set(iid, { ...w609.inc.get(iid), timers: w609.inc.get(iid).timers.set("hold", { ...w609.inc.get(iid).timers.get("hold"), paused: keep_608 }) }) }
      val w611 = { ...w610, inc: w610.inc.set(iid, { ...w610.inc.get(iid), timers: w610.inc.get(iid).timers.set("hold", { ...w610.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w612 = { ...w611, inc: w611.inc.set(iid, { ...w611.inc.get(iid), timers: w611.inc.get(iid).timers.set("hold", { ...w611.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w612
    }
      w607
    }
      w602
    }
    w600
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
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

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w620 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w621 = if (timerDef("reaction").startsOnce) {
      val w622 = ec_resumeTimer(w0, c, iid, "reaction")
      w622
    } else {
      val w623 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w624 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w625 = { ...w624, inc: w624.inc.set(iid, { ...w624.inc.get(iid), timers: w624.inc.get(iid).timers.set("reaction", { ...w624.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w626 = { ...w625, inc: w625.inc.set(iid, { ...w625.inc.get(iid), timers: w625.inc.get(iid).timers.set("reaction", { ...w625.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w626
    } else {
      val sec_627 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w628 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_627 < 0)) 0 else (c.now + (sec_627 * 1000))) }) }) }
      val w629 = { ...w628, inc: w628.inc.set(iid, { ...w628.inc.get(iid), timers: w628.inc.get(iid).timers.set("reaction", { ...w628.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w630 = { ...w629, inc: w629.inc.set(iid, { ...w629.inc.get(iid), timers: w629.inc.get(iid).timers.set("reaction", { ...w629.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w631 = { ...w630, inc: w630.inc.set(iid, { ...w630.inc.get(iid), timers: w630.inc.get(iid).timers.set("reaction", { ...w630.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w631
    }
      w623
    }
      w621
    }
    w620
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
    val reason_632 = "break"
    val w633 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_632 }) }
    w633
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w634 = if (not(timerDef("resolution").pausable)) {
      val w635 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w636 = { ...w635, inc: w635.inc.set(iid, { ...w635.inc.get(iid), timers: w635.inc.get(iid).timers.set("resolution", { ...w635.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w636
    } else {
      val w637 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w638 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w639 = { ...w638, inc: w638.inc.set(iid, { ...w638.inc.get(iid), timers: w638.inc.get(iid).timers.set("resolution", { ...w638.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w640 = { ...w639, inc: w639.inc.set(iid, { ...w639.inc.get(iid), timers: w639.inc.get(iid).timers.set("resolution", { ...w639.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w640
    } else w0
      w637
    }
    w634
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w641 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w642 = if (timerDef("hold").startsOnce) {
      val w643 = ec_resumeTimer(w0, c, iid, "hold")
      w643
    } else {
      val w644 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w645 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w646 = { ...w645, inc: w645.inc.set(iid, { ...w645.inc.get(iid), timers: w645.inc.get(iid).timers.set("hold", { ...w645.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w647 = { ...w646, inc: w646.inc.set(iid, { ...w646.inc.get(iid), timers: w646.inc.get(iid).timers.set("hold", { ...w646.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w647
    } else {
      val sec_648 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w649 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_648 < 0)) 0 else (c.now + (sec_648 * 1000))) }) }) }
      val w650 = { ...w649, inc: w649.inc.set(iid, { ...w649.inc.get(iid), timers: w649.inc.get(iid).timers.set("hold", { ...w649.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w651 = { ...w650, inc: w650.inc.set(iid, { ...w650.inc.get(iid), timers: w650.inc.get(iid).timers.set("hold", { ...w650.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w652 = { ...w651, inc: w651.inc.set(iid, { ...w651.inc.get(iid), timers: w651.inc.get(iid).timers.set("hold", { ...w651.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w652
    }
      w644
    }
      w642
    }
    w641
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
    val reason_653 = "no_link"
    val w654 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_653 }) }
    w654
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w655 = if (not(timerDef("resolution").pausable)) {
      val w656 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w657 = { ...w656, inc: w656.inc.set(iid, { ...w656.inc.get(iid), timers: w656.inc.get(iid).timers.set("resolution", { ...w656.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w657
    } else {
      val w658 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w659 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w660 = { ...w659, inc: w659.inc.set(iid, { ...w659.inc.get(iid), timers: w659.inc.get(iid).timers.set("resolution", { ...w659.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w661 = { ...w660, inc: w660.inc.set(iid, { ...w660.inc.get(iid), timers: w660.inc.get(iid).timers.set("resolution", { ...w660.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w661
    } else w0
      w658
    }
    w655
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w662 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w663 = if (timerDef("hold").startsOnce) {
      val w664 = ec_resumeTimer(w0, c, iid, "hold")
      w664
    } else {
      val w665 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w666 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w667 = { ...w666, inc: w666.inc.set(iid, { ...w666.inc.get(iid), timers: w666.inc.get(iid).timers.set("hold", { ...w666.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w668 = { ...w667, inc: w667.inc.set(iid, { ...w667.inc.get(iid), timers: w667.inc.get(iid).timers.set("hold", { ...w667.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w668
    } else {
      val sec_669 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w670 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_669 < 0)) 0 else (c.now + (sec_669 * 1000))) }) }) }
      val w671 = { ...w670, inc: w670.inc.set(iid, { ...w670.inc.get(iid), timers: w670.inc.get(iid).timers.set("hold", { ...w670.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w672 = { ...w671, inc: w671.inc.set(iid, { ...w671.inc.get(iid), timers: w671.inc.get(iid).timers.set("hold", { ...w671.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w673 = { ...w672, inc: w672.inc.set(iid, { ...w672.inc.get(iid), timers: w672.inc.get(iid).timers.set("hold", { ...w672.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w673
    }
      w665
    }
      w663
    }
    w662
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_674 = settings.alerts.target
    val w675 = if (((whom_674 != "") and (whom_674 != c.actor))) w0 else w0
    w675
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
    ["break", "no_link"].foldl(false, (acc, y676) => acc or y676 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_677 = ""
    val w678 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_677 }) }
    w678
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w679 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w679
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w680 = if (timerDef("hold").startsOnce) {
      val w681 = ec_pauseTimer(w0, c, iid, "hold")
      w681
    } else {
      val w682 = if (false) {
      val w683 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w684 = { ...w683, inc: w683.inc.set(iid, { ...w683.inc.get(iid), timers: w683.inc.get(iid).timers.set("hold", { ...w683.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w685 = { ...w684, inc: w684.inc.set(iid, { ...w684.inc.get(iid), timers: w684.inc.get(iid).timers.set("hold", { ...w684.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w686 = { ...w685, inc: w685.inc.set(iid, { ...w685.inc.get(iid), timers: w685.inc.get(iid).timers.set("hold", { ...w685.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w686
    } else {
      val w687 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_688 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w689 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_688) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w690 = { ...w689, inc: w689.inc.set(iid, { ...w689.inc.get(iid), timers: w689.inc.get(iid).timers.set("hold", { ...w689.inc.get(iid).timers.get("hold"), paused: keep_688 }) }) }
      val w691 = { ...w690, inc: w690.inc.set(iid, { ...w690.inc.get(iid), timers: w690.inc.get(iid).timers.set("hold", { ...w690.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w692 = { ...w691, inc: w691.inc.set(iid, { ...w691.inc.get(iid), timers: w691.inc.get(iid).timers.set("hold", { ...w691.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w692
    }
      w687
    }
      w682
    }
    w680
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w693 = if (not(timerDef("resolution").pausable)) {
      val w694 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w695 = { ...w694, inc: w694.inc.set(iid, { ...w694.inc.get(iid), timers: w694.inc.get(iid).timers.set("resolution", { ...w694.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w695
    } else {
      val w696 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w697 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w698 = { ...w697, inc: w697.inc.set(iid, { ...w697.inc.get(iid), timers: w697.inc.get(iid).timers.set("resolution", { ...w697.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w699 = { ...w698, inc: w698.inc.set(iid, { ...w698.inc.get(iid), timers: w698.inc.get(iid).timers.set("resolution", { ...w698.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w699
    } else w0
      w696
    }
    w693
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w700 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w701 = if (timerDef("reaction").startsOnce) {
      val w702 = ec_resumeTimer(w0, c, iid, "reaction")
      w702
    } else {
      val w703 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w704 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w705 = { ...w704, inc: w704.inc.set(iid, { ...w704.inc.get(iid), timers: w704.inc.get(iid).timers.set("reaction", { ...w704.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w706 = { ...w705, inc: w705.inc.set(iid, { ...w705.inc.get(iid), timers: w705.inc.get(iid).timers.set("reaction", { ...w705.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w706
    } else {
      val sec_707 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w708 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_707 < 0)) 0 else (c.now + (sec_707 * 1000))) }) }) }
      val w709 = { ...w708, inc: w708.inc.set(iid, { ...w708.inc.get(iid), timers: w708.inc.get(iid).timers.set("reaction", { ...w708.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w710 = { ...w709, inc: w709.inc.set(iid, { ...w709.inc.get(iid), timers: w709.inc.get(iid).timers.set("reaction", { ...w709.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w711 = { ...w710, inc: w710.inc.set(iid, { ...w710.inc.get(iid), timers: w710.inc.get(iid).timers.set("reaction", { ...w710.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w711
    }
      w703
    }
      w701
    }
    w700
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
    { val t_712 = world.inc.get(iid).timers.get("hold")  (((t_712.due != 0) and (t_712.due <= c.now)) and (t_712.fired != t_712.due)) },
    ["no_link"].foldl(false, (acc, y713) => acc or y713 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_714 = ""
    val w715 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_714 }) }
    w715
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w716 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w716
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w717 = if (timerDef("hold").startsOnce) {
      val w718 = ec_pauseTimer(w0, c, iid, "hold")
      w718
    } else {
      val w719 = if (false) {
      val w720 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w721 = { ...w720, inc: w720.inc.set(iid, { ...w720.inc.get(iid), timers: w720.inc.get(iid).timers.set("hold", { ...w720.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w722 = { ...w721, inc: w721.inc.set(iid, { ...w721.inc.get(iid), timers: w721.inc.get(iid).timers.set("hold", { ...w721.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w723 = { ...w722, inc: w722.inc.set(iid, { ...w722.inc.get(iid), timers: w722.inc.get(iid).timers.set("hold", { ...w722.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w723
    } else {
      val w724 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_725 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w726 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_725) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w727 = { ...w726, inc: w726.inc.set(iid, { ...w726.inc.get(iid), timers: w726.inc.get(iid).timers.set("hold", { ...w726.inc.get(iid).timers.get("hold"), paused: keep_725 }) }) }
      val w728 = { ...w727, inc: w727.inc.set(iid, { ...w727.inc.get(iid), timers: w727.inc.get(iid).timers.set("hold", { ...w727.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w729 = { ...w728, inc: w728.inc.set(iid, { ...w728.inc.get(iid), timers: w728.inc.get(iid).timers.set("hold", { ...w728.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w729
    }
      w724
    }
      w719
    }
    w717
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w730 = if (not(timerDef("resolution").pausable)) {
      val w731 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w732 = { ...w731, inc: w731.inc.set(iid, { ...w731.inc.get(iid), timers: w731.inc.get(iid).timers.set("resolution", { ...w731.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w732
    } else {
      val w733 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w734 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w735 = { ...w734, inc: w734.inc.set(iid, { ...w734.inc.get(iid), timers: w734.inc.get(iid).timers.set("resolution", { ...w734.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w736 = { ...w735, inc: w735.inc.set(iid, { ...w735.inc.get(iid), timers: w735.inc.get(iid).timers.set("resolution", { ...w735.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w736
    } else w0
      w733
    }
    w730
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w737 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w738 = if (timerDef("reaction").startsOnce) {
      val w739 = ec_resumeTimer(w0, c, iid, "reaction")
      w739
    } else {
      val w740 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w741 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w742 = { ...w741, inc: w741.inc.set(iid, { ...w741.inc.get(iid), timers: w741.inc.get(iid).timers.set("reaction", { ...w741.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w743 = { ...w742, inc: w742.inc.set(iid, { ...w742.inc.get(iid), timers: w742.inc.get(iid).timers.set("reaction", { ...w742.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w743
    } else {
      val sec_744 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w745 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_744 < 0)) 0 else (c.now + (sec_744 * 1000))) }) }) }
      val w746 = { ...w745, inc: w745.inc.set(iid, { ...w745.inc.get(iid), timers: w745.inc.get(iid).timers.set("reaction", { ...w745.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w747 = { ...w746, inc: w746.inc.set(iid, { ...w746.inc.get(iid), timers: w746.inc.get(iid).timers.set("reaction", { ...w746.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w748 = { ...w747, inc: w747.inc.set(iid, { ...w747.inc.get(iid), timers: w747.inc.get(iid).timers.set("reaction", { ...w747.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w748
    }
      w740
    }
      w738
    }
    w737
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
    val group_749 = dutyGroupOf(w0.inc.get(iid).owner)
    val w750 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_749 }) }
    w750
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_751 = ""
    val w752 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_751 }) }
    w752
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_753 = addressee(w0.inc.get(iid))
    val w754 = if (((whom_753 != "") and (whom_753 != c.actor))) w0 else w0
    w754
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
    val who_755 = ""
    val w756 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_755 }) }
    w756
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
    val who_757 = ""
    val w758 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_757 }) }
    w758
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w759 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w759
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w760 = if (timerDef("hold").startsOnce) {
      val w761 = ec_pauseTimer(w0, c, iid, "hold")
      w761
    } else {
      val w762 = if (false) {
      val w763 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w764 = { ...w763, inc: w763.inc.set(iid, { ...w763.inc.get(iid), timers: w763.inc.get(iid).timers.set("hold", { ...w763.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w765 = { ...w764, inc: w764.inc.set(iid, { ...w764.inc.get(iid), timers: w764.inc.get(iid).timers.set("hold", { ...w764.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w766 = { ...w765, inc: w765.inc.set(iid, { ...w765.inc.get(iid), timers: w765.inc.get(iid).timers.set("hold", { ...w765.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w766
    } else {
      val w767 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_768 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w769 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_768) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w770 = { ...w769, inc: w769.inc.set(iid, { ...w769.inc.get(iid), timers: w769.inc.get(iid).timers.set("hold", { ...w769.inc.get(iid).timers.get("hold"), paused: keep_768 }) }) }
      val w771 = { ...w770, inc: w770.inc.set(iid, { ...w770.inc.get(iid), timers: w770.inc.get(iid).timers.set("hold", { ...w770.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w772 = { ...w771, inc: w771.inc.set(iid, { ...w771.inc.get(iid), timers: w771.inc.get(iid).timers.set("hold", { ...w771.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w772
    }
      w767
    }
      w762
    }
    w760
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w773 = if (not(timerDef("resolution").pausable)) {
      val w774 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w775 = { ...w774, inc: w774.inc.set(iid, { ...w774.inc.get(iid), timers: w774.inc.get(iid).timers.set("resolution", { ...w774.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w775
    } else {
      val w776 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w777 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w778 = { ...w777, inc: w777.inc.set(iid, { ...w777.inc.get(iid), timers: w777.inc.get(iid).timers.set("resolution", { ...w777.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w779 = { ...w778, inc: w778.inc.set(iid, { ...w778.inc.get(iid), timers: w778.inc.get(iid).timers.set("resolution", { ...w778.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w779
    } else w0
      w776
    }
    w773
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w780 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w781 = if (timerDef("reaction").startsOnce) {
      val w782 = ec_resumeTimer(w0, c, iid, "reaction")
      w782
    } else {
      val w783 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w784 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w785 = { ...w784, inc: w784.inc.set(iid, { ...w784.inc.get(iid), timers: w784.inc.get(iid).timers.set("reaction", { ...w784.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w786 = { ...w785, inc: w785.inc.set(iid, { ...w785.inc.get(iid), timers: w785.inc.get(iid).timers.set("reaction", { ...w785.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w786
    } else {
      val sec_787 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w788 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_787 < 0)) 0 else (c.now + (sec_787 * 1000))) }) }) }
      val w789 = { ...w788, inc: w788.inc.set(iid, { ...w788.inc.get(iid), timers: w788.inc.get(iid).timers.set("reaction", { ...w788.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w790 = { ...w789, inc: w789.inc.set(iid, { ...w789.inc.get(iid), timers: w789.inc.get(iid).timers.set("reaction", { ...w789.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w791 = { ...w790, inc: w790.inc.set(iid, { ...w790.inc.get(iid), timers: w790.inc.get(iid).timers.set("reaction", { ...w790.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w791
    }
      w783
    }
      w781
    }
    w780
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
    val who_792 = ""
    val w793 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_792 }) }
    w793
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_794 = ""
    val w795 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_794 }) }
    w795
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w796 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w796
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w797 = if (timerDef("hold").startsOnce) {
      val w798 = ec_pauseTimer(w0, c, iid, "hold")
      w798
    } else {
      val w799 = if (false) {
      val w800 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w801 = { ...w800, inc: w800.inc.set(iid, { ...w800.inc.get(iid), timers: w800.inc.get(iid).timers.set("hold", { ...w800.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w802 = { ...w801, inc: w801.inc.set(iid, { ...w801.inc.get(iid), timers: w801.inc.get(iid).timers.set("hold", { ...w801.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w803 = { ...w802, inc: w802.inc.set(iid, { ...w802.inc.get(iid), timers: w802.inc.get(iid).timers.set("hold", { ...w802.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w803
    } else {
      val w804 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_805 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w806 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_805) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w807 = { ...w806, inc: w806.inc.set(iid, { ...w806.inc.get(iid), timers: w806.inc.get(iid).timers.set("hold", { ...w806.inc.get(iid).timers.get("hold"), paused: keep_805 }) }) }
      val w808 = { ...w807, inc: w807.inc.set(iid, { ...w807.inc.get(iid), timers: w807.inc.get(iid).timers.set("hold", { ...w807.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w809 = { ...w808, inc: w808.inc.set(iid, { ...w808.inc.get(iid), timers: w808.inc.get(iid).timers.set("hold", { ...w808.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w809
    }
      w804
    }
      w799
    }
    w797
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w810 = if (not(timerDef("resolution").pausable)) {
      val w811 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w812 = { ...w811, inc: w811.inc.set(iid, { ...w811.inc.get(iid), timers: w811.inc.get(iid).timers.set("resolution", { ...w811.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w812
    } else {
      val w813 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w814 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w815 = { ...w814, inc: w814.inc.set(iid, { ...w814.inc.get(iid), timers: w814.inc.get(iid).timers.set("resolution", { ...w814.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w816 = { ...w815, inc: w815.inc.set(iid, { ...w815.inc.get(iid), timers: w815.inc.get(iid).timers.set("resolution", { ...w815.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w816
    } else w0
      w813
    }
    w810
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w817 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w818 = if (timerDef("reaction").startsOnce) {
      val w819 = ec_resumeTimer(w0, c, iid, "reaction")
      w819
    } else {
      val w820 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w821 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w822 = { ...w821, inc: w821.inc.set(iid, { ...w821.inc.get(iid), timers: w821.inc.get(iid).timers.set("reaction", { ...w821.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w823 = { ...w822, inc: w822.inc.set(iid, { ...w822.inc.get(iid), timers: w822.inc.get(iid).timers.set("reaction", { ...w822.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w823
    } else {
      val sec_824 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w825 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_824 < 0)) 0 else (c.now + (sec_824 * 1000))) }) }) }
      val w826 = { ...w825, inc: w825.inc.set(iid, { ...w825.inc.get(iid), timers: w825.inc.get(iid).timers.set("reaction", { ...w825.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w827 = { ...w826, inc: w826.inc.set(iid, { ...w826.inc.get(iid), timers: w826.inc.get(iid).timers.set("reaction", { ...w826.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w828 = { ...w827, inc: w827.inc.set(iid, { ...w827.inc.get(iid), timers: w827.inc.get(iid).timers.set("reaction", { ...w827.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w828
    }
      w820
    }
      w818
    }
    w817
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_829 = settings.alerts.target
    val w830 = if (((whom_829 != "") and (whom_829 != c.actor))) w0 else w0
    w830
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
    val who_831 = ""
    val w832 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_831 }) }
    w832
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_833 = ""
    val w834 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_833 }) }
    w834
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w835 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w836 = if (timerDef("reaction").startsOnce) {
      val w837 = ec_resumeTimer(w0, c, iid, "reaction")
      w837
    } else {
      val w838 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w839 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w840 = { ...w839, inc: w839.inc.set(iid, { ...w839.inc.get(iid), timers: w839.inc.get(iid).timers.set("reaction", { ...w839.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w841 = { ...w840, inc: w840.inc.set(iid, { ...w840.inc.get(iid), timers: w840.inc.get(iid).timers.set("reaction", { ...w840.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w841
    } else {
      val sec_842 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w843 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_842 < 0)) 0 else (c.now + (sec_842 * 1000))) }) }) }
      val w844 = { ...w843, inc: w843.inc.set(iid, { ...w843.inc.get(iid), timers: w843.inc.get(iid).timers.set("reaction", { ...w843.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w845 = { ...w844, inc: w844.inc.set(iid, { ...w844.inc.get(iid), timers: w844.inc.get(iid).timers.set("reaction", { ...w844.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w846 = { ...w845, inc: w845.inc.set(iid, { ...w845.inc.get(iid), timers: w845.inc.get(iid).timers.set("reaction", { ...w845.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w846
    }
      w838
    }
      w836
    }
    w835
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_847 = settings.alerts.target
    val w848 = if (((whom_847 != "") and (whom_847 != c.actor))) w0 else w0
    w848
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
    not(settings.session.states.foldl(false, (acc, s_849) => acc or ((s_849.id == agentState(c.me)) and s_849.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_850 = incidentById(incs(world), c.form.primaryId)  ((((ps_850.length() > 0) and (ps_850[0].id != world.inc.get(iid).id)) and (ps_850[0].linkedTo == "")) and ((ps_850[0].state == "new") or ((ps_850[0].state == "in_progress") and (ps_850[0].owner == c.me)))) },
    { val ps_851 = incidentById(incs(world), c.form.primaryId)  ((ps_851.length() > 0) and (ps_851[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w852 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w852
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_853 = incidentById(incs(w0), c.form.primaryId)
    val w854 = if ((ps_853.length() > 0)) {
      val w855 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_862 => not(isDone(e_862))).foldl([], (acc, x858) => acc.append(x858.id)).foldl(w0, (wf856, cId857) => {
      val w859 = { ...wf856, inc: wf856.inc.set(cId857, { ...wf856.inc.get(cId857), leftGroup: { primaryId: wf856.inc.get(cId857).linkedTo, linkedAt: wf856.inc.get(cId857).linkedAt, at: c.now } }) }
      val w860 = { ...w859, inc: w859.inc.set(cId857, { ...w859.inc.get(cId857), linkedTo: ps_853[0].id }) }
      val w861 = { ...w860, inc: w860.inc.set(cId857, { ...w860.inc.get(cId857), linkedAt: c.now }) }
      w861
    })
      w855
    } else w0
    w854
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_863 = c.form.primaryId
    val w864 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_863 }) }
    val w865 = { ...w864, inc: w864.inc.set(iid, { ...w864.inc.get(iid), linkedAt: c.now }) }
    w865
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_866 = ""
    val w867 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_866 }) }
    w867
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_868 = ""
    val w869 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_868 }) }
    w869
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w870 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w870
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w871 = if (timerDef("reaction").startsOnce) {
      val w872 = ec_pauseTimer(w0, c, iid, "reaction")
      w872
    } else {
      val w873 = if (false) {
      val w874 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w875 = { ...w874, inc: w874.inc.set(iid, { ...w874.inc.get(iid), timers: w874.inc.get(iid).timers.set("reaction", { ...w874.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w876 = { ...w875, inc: w875.inc.set(iid, { ...w875.inc.get(iid), timers: w875.inc.get(iid).timers.set("reaction", { ...w875.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w877 = { ...w876, inc: w876.inc.set(iid, { ...w876.inc.get(iid), timers: w876.inc.get(iid).timers.set("reaction", { ...w876.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w877
    } else {
      val w878 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_879 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w880 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_879) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w881 = { ...w880, inc: w880.inc.set(iid, { ...w880.inc.get(iid), timers: w880.inc.get(iid).timers.set("reaction", { ...w880.inc.get(iid).timers.get("reaction"), paused: keep_879 }) }) }
      val w882 = { ...w881, inc: w881.inc.set(iid, { ...w881.inc.get(iid), timers: w881.inc.get(iid).timers.set("reaction", { ...w881.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w883 = { ...w882, inc: w882.inc.set(iid, { ...w882.inc.get(iid), timers: w882.inc.get(iid).timers.set("reaction", { ...w882.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w883
    }
      w878
    }
      w873
    }
    w871
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w884 = if (not(timerDef("resolution").pausable)) {
      val w885 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w886 = { ...w885, inc: w885.inc.set(iid, { ...w885.inc.get(iid), timers: w885.inc.get(iid).timers.set("resolution", { ...w885.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w886
    } else {
      val w887 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w888 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w889 = { ...w888, inc: w888.inc.set(iid, { ...w888.inc.get(iid), timers: w888.inc.get(iid).timers.set("resolution", { ...w888.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w890 = { ...w889, inc: w889.inc.set(iid, { ...w889.inc.get(iid), timers: w889.inc.get(iid).timers.set("resolution", { ...w889.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w890
    } else w0
      w887
    }
    w884
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_891 = incidentById(incs(w0), c.form.primaryId)
    val w892 = if (((((ps_891.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_891[0], "resolution", c.now)))) {
      val t_893 = ps_891[0].timers.get("resolution")
      val left_894 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_895 = (if ((t_893.due != 0)) (t_893.due - c.now) else (if (t_893.paused) t_893.left else (timerSec(ps_891[0], "resolution", "") * 1000)))
      val w896 = if ((left_894 < was_895)) {
      val w897 = ps_891.foldl([], (acc, x900) => acc.append(x900.id)).foldl(w0, (wf898, pId899) => {
      val w901 = if ((t_893.due != 0)) {
      val w902 = { ...wf898, inc: wf898.inc.set(pId899, { ...wf898.inc.get(pId899), timers: wf898.inc.get(pId899).timers.set("resolution", { ...wf898.inc.get(pId899).timers.get("resolution"), due: (c.now + left_894) }) }) }
      w902
    } else {
      val w903 = { ...wf898, inc: wf898.inc.set(pId899, { ...wf898.inc.get(pId899), timers: wf898.inc.get(pId899).timers.set("resolution", { ...wf898.inc.get(pId899).timers.get("resolution"), left: left_894 }) }) }
      val w904 = { ...w903, inc: w903.inc.set(pId899, { ...w903.inc.get(pId899), timers: w903.inc.get(pId899).timers.set("resolution", { ...w903.inc.get(pId899).timers.get("resolution"), paused: true }) }) }
      w904
    }
      w901
    })
      w897
    } else w0
      w896
    } else w0
    w892
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w905 = if (timerDef("hold").startsOnce) {
      val w906 = ec_pauseTimer(w0, c, iid, "hold")
      w906
    } else {
      val w907 = if (false) {
      val w908 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w909 = { ...w908, inc: w908.inc.set(iid, { ...w908.inc.get(iid), timers: w908.inc.get(iid).timers.set("hold", { ...w908.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w910 = { ...w909, inc: w909.inc.set(iid, { ...w909.inc.get(iid), timers: w909.inc.get(iid).timers.set("hold", { ...w909.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w911 = { ...w910, inc: w910.inc.set(iid, { ...w910.inc.get(iid), timers: w910.inc.get(iid).timers.set("hold", { ...w910.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w911
    } else {
      val w912 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_913 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w914 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_913) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w915 = { ...w914, inc: w914.inc.set(iid, { ...w914.inc.get(iid), timers: w914.inc.get(iid).timers.set("hold", { ...w914.inc.get(iid).timers.get("hold"), paused: keep_913 }) }) }
      val w916 = { ...w915, inc: w915.inc.set(iid, { ...w915.inc.get(iid), timers: w915.inc.get(iid).timers.set("hold", { ...w915.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w917 = { ...w916, inc: w916.inc.set(iid, { ...w916.inc.get(iid), timers: w916.inc.get(iid).timers.set("hold", { ...w916.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w917
    }
      w912
    }
      w907
    }
    w905
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
    not(settings.session.states.foldl(false, (acc, s_918) => acc or ((s_918.id == agentState(c.me)) and s_918.readOnly))),
    { val ps_919 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_919.length() > 0) and ((ownership(c.me, ps_919[0]) == "owner") or unowned(ps_919[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_920 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w921 = if (((ps_920.length() > 0) and (leftOf(ps_920[0], "resolution", c.now) >= 0))) {
      val w922 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w923 = { ...w922, inc: w922.inc.set(iid, { ...w922.inc.get(iid), timers: w922.inc.get(iid).timers.set("resolution", { ...w922.inc.get(iid).timers.get("resolution"), left: leftOf(ps_920[0], "resolution", c.now) }) }) }
      val w924 = { ...w923, inc: w923.inc.set(iid, { ...w923.inc.get(iid), timers: w923.inc.get(iid).timers.set("resolution", { ...w923.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w925 = if ((leftOf(ps_920[0], "resolution", c.now) == 0)) {
      val w926 = { ...w924, inc: w924.inc.set(iid, { ...w924.inc.get(iid), timers: w924.inc.get(iid).timers.set("resolution", { ...w924.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_920[0], "resolution", c.now)) ps_920[0].timers.get("resolution").fired else ps_920[0].timers.get("resolution").due) }) }) }
      w926
    } else w924
      w925
    } else w0
    w921
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w927 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_928 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w929 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w930 = { ...w929, inc: w929.inc.set(iid, { ...w929.inc.get(iid), linkedTo: "" }) }
      val w931 = { ...w930, inc: w930.inc.set(iid, { ...w930.inc.get(iid), linkedAt: 0 }) }
      val w932 = if (((ps_928.length() > 0) and ("" != ""))) w931 else w931
      val w933 = if (("" != "")) {
      val w934 = ps_928.foldl([], (acc, x937) => acc.append(x937.id)).foldl(w932, (wf935, pId936) => wf935)
      w934
    } else w932
      w933
    } else {
      val w938 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w939 = { ...w938, inc: w938.inc.set(iid, { ...w938.inc.get(iid), linkedAt: 0 }) }
      w939
    }
    w927
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w940 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w941 = if (timerDef("reaction").startsOnce) {
      val w942 = ec_resumeTimer(w0, c, iid, "reaction")
      w942
    } else {
      val w943 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w944 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w945 = { ...w944, inc: w944.inc.set(iid, { ...w944.inc.get(iid), timers: w944.inc.get(iid).timers.set("reaction", { ...w944.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w946 = { ...w945, inc: w945.inc.set(iid, { ...w945.inc.get(iid), timers: w945.inc.get(iid).timers.set("reaction", { ...w945.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w946
    } else {
      val sec_947 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w948 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_947 < 0)) 0 else (c.now + (sec_947 * 1000))) }) }) }
      val w949 = { ...w948, inc: w948.inc.set(iid, { ...w948.inc.get(iid), timers: w948.inc.get(iid).timers.set("reaction", { ...w948.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w950 = { ...w949, inc: w949.inc.set(iid, { ...w949.inc.get(iid), timers: w949.inc.get(iid).timers.set("reaction", { ...w949.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w951 = { ...w950, inc: w950.inc.set(iid, { ...w950.inc.get(iid), timers: w950.inc.get(iid).timers.set("reaction", { ...w950.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w951
    }
      w943
    }
      w941
    }
    w940
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
    { val ps_952 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_952.length() > 0) and isDone(ps_952[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_953 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w954 = if ((ps_953.length() > 0)) {
      val w955 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_953[0].closeResultId }) }
      val w956 = { ...w955, inc: w955.inc.set(iid, { ...w955.inc.get(iid), closeCauseId: ps_953[0].closeCauseId }) }
      val w957 = { ...w956, inc: w956.inc.set(iid, { ...w956.inc.get(iid), result: ps_953[0].result }) }
      val w958 = { ...w957, inc: w957.inc.set(iid, { ...w957.inc.get(iid), closedBy: ps_953[0].closedBy }) }
      val w959 = { ...w958, inc: w958.inc.set(iid, { ...w958.inc.get(iid), owner: ps_953[0].closedBy }) }
      w959
    } else w0
    w954
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w960 = if (not(timerDef("resolution").pausable)) {
      val w961 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w962 = { ...w961, inc: w961.inc.set(iid, { ...w961.inc.get(iid), timers: w961.inc.get(iid).timers.set("resolution", { ...w961.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w962
    } else {
      val w963 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w964 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w965 = { ...w964, inc: w964.inc.set(iid, { ...w964.inc.get(iid), timers: w964.inc.get(iid).timers.set("resolution", { ...w964.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w966 = { ...w965, inc: w965.inc.set(iid, { ...w965.inc.get(iid), timers: w965.inc.get(iid).timers.set("resolution", { ...w965.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w966
    } else w0
      w963
    }
    w960
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_967 = c.now
    val w968 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_967 }) }
    w968
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
    { val ps_969 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_970 = (if (((ps_969.length() > 0) and not(isDone(ps_969[0])))) addressee(ps_969[0]) else "")  ((who_970 != "") and (hasAccess(who_970, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_971 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w972 = if (((ps_971.length() > 0) and (leftOf(ps_971[0], "resolution", c.now) >= 0))) {
      val w973 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w974 = { ...w973, inc: w973.inc.set(iid, { ...w973.inc.get(iid), timers: w973.inc.get(iid).timers.set("resolution", { ...w973.inc.get(iid).timers.get("resolution"), left: leftOf(ps_971[0], "resolution", c.now) }) }) }
      val w975 = { ...w974, inc: w974.inc.set(iid, { ...w974.inc.get(iid), timers: w974.inc.get(iid).timers.set("resolution", { ...w974.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w976 = if ((leftOf(ps_971[0], "resolution", c.now) == 0)) {
      val w977 = { ...w975, inc: w975.inc.set(iid, { ...w975.inc.get(iid), timers: w975.inc.get(iid).timers.set("resolution", { ...w975.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_971[0], "resolution", c.now)) ps_971[0].timers.get("resolution").fired else ps_971[0].timers.get("resolution").due) }) }) }
      w977
    } else w975
      w976
    } else w0
    w972
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w978 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_979 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w980 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w981 = { ...w980, inc: w980.inc.set(iid, { ...w980.inc.get(iid), linkedTo: "" }) }
      val w982 = { ...w981, inc: w981.inc.set(iid, { ...w981.inc.get(iid), linkedAt: 0 }) }
      val w983 = if (((ps_979.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w982 else w982
      val w984 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w985 = ps_979.foldl([], (acc, x988) => acc.append(x988.id)).foldl(w983, (wf986, pId987) => wf986)
      w985
    } else w983
      w984
    } else {
      val w989 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w990 = { ...w989, inc: w989.inc.set(iid, { ...w989.inc.get(iid), linkedAt: 0 }) }
      w990
    }
    w978
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w991 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w992 = if (timerDef("reaction").startsOnce) {
      val w993 = ec_resumeTimer(w0, c, iid, "reaction")
      w993
    } else {
      val w994 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w995 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w996 = { ...w995, inc: w995.inc.set(iid, { ...w995.inc.get(iid), timers: w995.inc.get(iid).timers.set("reaction", { ...w995.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w997 = { ...w996, inc: w996.inc.set(iid, { ...w996.inc.get(iid), timers: w996.inc.get(iid).timers.set("reaction", { ...w996.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w997
    } else {
      val sec_998 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w999 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_998 < 0)) 0 else (c.now + (sec_998 * 1000))) }) }) }
      val w1000 = { ...w999, inc: w999.inc.set(iid, { ...w999.inc.get(iid), timers: w999.inc.get(iid).timers.set("reaction", { ...w999.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1001 = { ...w1000, inc: w1000.inc.set(iid, { ...w1000.inc.get(iid), timers: w1000.inc.get(iid).timers.set("reaction", { ...w1000.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1002 = { ...w1001, inc: w1001.inc.set(iid, { ...w1001.inc.get(iid), timers: w1001.inc.get(iid).timers.set("reaction", { ...w1001.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1002
    }
      w994
    }
      w992
    }
    w991
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_1003 = settings.alerts.target
    val w1004 = if (((whom_1003 != "") and (whom_1003 != c.actor))) w0 else w0
    w1004
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
      settings.holdReasons.foldl(false, (acc, r_1005) => acc or ((r_1005.id == c.form.reasonId) and (r_1005.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_1006) => acc and (isDone(e_1006) or hasAccess(c.form.targetId, e_1006))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_1007) => acc or (i_1007.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_1008) => acc or ((i_1008.id == c.form.resultId) and stepsOk(i_1008, world.inc.get(iid)))),
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
    ["in_progress"].foldl(false, (acc, y1009) => acc or y1009 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_1010) => acc or ((s_1010.id == agentState(c.me)) and s_1010.readOnly))),
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
