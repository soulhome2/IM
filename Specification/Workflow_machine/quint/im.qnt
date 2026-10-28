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

  // §11.1, ARCH-15 (В8). Основной выборки для действия со scope: primaryScenario («Закрыть без обработки») — чей сценарий закрывается: основной по §11.3 (mergePrimary), а если его нет (отмечены только отложенные, ожидающие принятия, чужие) — из отмеченных, которые этот оператор может закрыть из очереди (closeOptions и stepsOk — как у closeResultAllowed без выбранного результата; решение 2026-10-29), самый срочный, у равных — появившийся раньше, у совсем равных — первый по порядку выборки (по возрастанию номера, как у mergePrimary). Списком из одного или пустым (выборка пуста или закрыть нечего — действие недоступно)

  def bulkPrimary(xs: List[Incident], who: str): List[Incident] =
    { val p_16 = mergePrimary(xs, who)  (if ((p_16.length() > 0)) p_16 else { val ok_17 = xs.select(e_18 => closeOptions(who, e_18, "queue").foldl(false, (acc, o_19) => acc or stepsOk(o_19, e_18)))  { val top_20 = ok_17.select(e_21 => ok_17.foldl(true, (acc, k_22) => acc and (k_22.priority <= e_21.priority)))  { val first_23 = top_20.select(e_24 => top_20.foldl(true, (acc, k_25) => acc and (e_24.occurredAt <= k_25.occurredAt)))  (if ((first_23.length() > 0)) [first_23[0]] else []) } } }) }

  // §8.1, §12. Человек на месте: его состояние — не «только просмотр» (перерыв, вышел)

  def onDuty(who: str): bool =
    not(settings.session.states.foldl(false, (acc, s_26) => acc or ((s_26.id == agentState(who)) and s_26.readOnly)))

  // §9. Кто получит уведомление: человек или участники дежурной группы — на месте и с доступом к объекту инцидента

  def recipients(whom: str, x: Incident): List[str] =
    (if (isGroup(whom)) members(whom) else [whom]).select(m_27 => (onDuty(m_27) and access(m_27, x)))

  // Таймер идёт: дедлайн есть и ещё не сработал (на потолке эскалации реакции — уже сработал)

  def timerRuns(x: Incident, id: str): bool =
    ((x.timers.get(id).due != 0) and (x.timers.get(id).fired != x.timers.get(id).due))

  // Закрыт без результата или результатом полной обработки (finish)

  def closedFinished(x: Incident): bool =
    ((x.closeResultId == "") or settings.closeResults.foldl(false, (acc, i_28) => acc or ((i_28.id == x.closeResultId) and i_28.finish)))

  // §8.3. Адресован автоэскалацией: адресат — адресат текущего уровня. Уровень после ручной передачи остаётся (RULE-76), но адресат уже другой

  def escalatedTo(x: Incident): bool =
    ((x.escalationLevel > 0) and settings.escalation.levels.foldl(false, (acc, l_29) => acc or ((l_29.level == x.escalationLevel) and (l_29.target == addressee(x)))))

  def isDone(x: Incident): bool =
    settings.states.foldl(false, (acc, s_30) => acc or ((s_30.id == x.state) and (s_30.category == "done")))

  // §5, §7, ARCH-15. Закрыт «Ложной тревогой». Тревога ложная, когда так закрыты сам инцидент и все его соседи, видимые смотрящему (alarm.allFalseAlarm карточки). Определение — для сервера и бэкенда, переходы его не используют

  def closedFalseAlarm(x: Incident): bool =
    (isDone(x) and (x.closeResultId == "false_alarm"))

  // Инцидент по id — списком из одного или пустым

  def byId(xs: List[Incident], id: str): List[Incident] =
    xs.select(e_31 => (e_31.id == id))

  // §5, §8.1. Доступ к объекту: человеку — по его ролям, группе — хотя бы у одного участника

  def hasAccess(who: str, x: Incident): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_32) => acc or access(m_32, x)) else (isOperator(who) and access(who, x)))

  def canAcceptPerson(m: str, x: Incident): bool =
    (can(m, "incident:accept") and access(m, x))

  // §8.1. Может ли принять: право «Принимать» и доступ к объекту; группа — если хотя бы один участник, кроме except: у него инцидент уже есть (RULE-93)

  def canAccept(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_33) => acc or ((m_33 != except) and canAcceptPerson(m_33, x))) else canAcceptPerson(who, x))

  // §8.1. Дежурная группа человека — первая, в которую он входит

  def dutyGroupOf(who: str): str =
    { val gs_34 = dutyGroups.select(g_35 => members(g_35).foldl(false, (acc, y36) => acc or y36 == who))  (if ((gs_34.length() > 0)) gs_34[0] else "") }

  // §12.1. Человек вошёл в МИ: на месте или на перерыве, но не вышел (RULE-100)

  def signedIn(who: str): bool =
    (agentState(who) != "offline")

  // §8.3, RULE-100. Адресат уровня эскалации может принять сейчас: как canAccept, и принимающий не вышел из МИ; вышедшему человеку инцидент уйдёт его дежурной группе (addressee_signed_out_to_group) — уровень доступен, если в ней кто-то, кроме except, не вышел и может принять. Перерыв не мешает (§12.1)

  def canAcceptNow(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_37) => acc or (((m_37 != except) and signedIn(m_37)) and canAcceptPerson(m_37, x))) else (canAcceptPerson(who, x) and (signedIn(who) or { val g_38 = dutyGroupOf(who)  ((g_38 != "") and members(g_38).foldl(false, (acc, m_39) => acc or ((((m_39 != except) and (m_39 != who)) and signedIn(m_39)) and canAcceptPerson(m_39, x)))) })))

  // §8.3. Уровни автоэскалации выше текущего и не выше потолка, адресат которых может принять сейчас (canAcceptNow, RULE-100); уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)

  def nextLevels(x: Incident): List[Level] =
    settings.escalation.levels.select(l_40 => ((((l_40.level > x.escalationLevel) and (l_40.level <= settings.escalation.maxLevel)) and (l_40.target != addressee(x))) and canAcceptNow(l_40.target, x, x.owner)))

  // §2.2. Результаты закрытия, которые этот оператор может выбрать для инцидента

  def closeOptions(who: str, x: Incident, surface: str): List[CloseResultItem] =
    settings.closeResults.select(i_41 => (((can(who, i_41.permission) and i_41.fromStates.foldl(false, (acc, y42) => acc or y42 == x.state)) and not((i_41.ownerOnlyInStates.foldl(false, (acc, y43) => acc or y43 == x.state) and (x.owner != who)))) and (((surface == "") or (i_41.surfaces.length() == 0)) or i_41.surfaces.foldl(false, (acc, y44) => acc or y44 == surface))))

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
    { val ls_45 = nextLevels(x)  ls_45.select(l_46 => ls_45.foldl(true, (acc, k_47) => acc and (l_46.level <= k_47.level))) }

  def levelUpTarget(x: Incident): str =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].target else "")

  def levelUpNumber(x: Incident): int =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].level else 0)

  def timerDef(id: str): TimerDef =
    settings.timerDefs.select(t_48 => (t_48.id == id))[0]

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
    (((((o.eventType.length() == 0) or t.overridesBy.foldl(false, (acc, y49) => acc or y49 == "eventType")) and ((o.priority.length() == 0) or t.overridesBy.foldl(false, (acc, y50) => acc or y50 == "priority"))) and ((o.sourceGroup.length() == 0) or t.overridesBy.foldl(false, (acc, y51) => acc or y51 == "sourceGroup"))) and ((o.scenario.length() == 0) or t.overridesBy.foldl(false, (acc, y52) => acc or y52 == "scenario")))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (больше условий; при равном числе — со сценарием; при равных и этом — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_53 = t.overrides.select(o_54 => (overrideAllowed(t, o_54) and overrideMatches(x, o_54)))  (if ((ms_53.length() > 0)) ms_53.select(o_55 => ms_53.foldl(true, (acc, k_56) => acc and (overrideRank(k_56) <= overrideRank(o_55))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold). У причины с deadlineFromIdle («Нет связи») — порог возврата в очередь минус порог удержания, не меньше 0: срок причины и возврат по молчанию совпадают при любых порогах (RULE-118, RULE-129, RULE-132). Причины нет — -1, срок не ставится. Срок у причины обязателен, кроме deadlineFromIdle (§4, правило 7; RULE-135, check_machine.py): ветка «maxMinutes пуст» — подстраховка

  def holdSec(x: Incident): int =
    { val rs_57 = settings.holdReasons.select(r_58 => (r_58.id == x.holdReasonId))  (if ((rs_57.length() == 0)) (0 - 1) else (if (rs_57[0].deadlineFromIdle) (if ((settings.session.idleReleaseSec > settings.session.idleHoldSec)) (settings.session.idleReleaseSec - settings.session.idleHoldSec) else 0) else (if ((rs_57[0].maxMinutes.length() > 0)) (rs_57[0].maxMinutes[0] * 60) else (0 - 1)))) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_59 = settings.escalation.levels.select(l_60 => (l_60.level == x.escalationLevel))  (if ((ls_59.length() > 0)) ls_59[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_61 = x.timers.get(id)  (if ((t_61.due != 0)) (if (((t_61.due - now) > 0)) (t_61.due - now) else 0) else (if (t_61.paused) t_61.left else (0 - 1))) }

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
    { val ks_62 = r.conditions.select(c_63 => conditionMatches(c_63, e)).foldl([], (acc, c_64) => acc.append(conditionRank(c_64)))  (if ((ks_62.length() == 0)) (0 - 1) else ks_62.select(k_65 => ks_62.foldl(true, (acc, j_66) => acc and (j_66 <= k_65)))[0]) }

  // §14.5, ARCH-15. Правило подошло событию: у него есть сценарий и подошло хоть одно условие. Правило без сценария в выборе не участвует

  def ruleMatches(r: Rule, e: Event): bool =
    ((r.scenarios.length() > 0) and r.conditions.foldl(false, (acc, c_67) => acc or conditionMatches(c_67, e)))

  // §14.5, ARCH-15 (решение пользователя 2026-10-28). Правило a старше b для события — строго: точнее условие; при равной точности — выше приоритет; при равном приоритете — раньше создано. Полное равенство — ни одно не старше: решает порядок списка правил, а он задан intake.ruleOrder (по guid), не порядком строк в базе

  def ruleBeats(a: Rule, b: Rule, e: Event): bool =
    { val ra_68 = ruleRank(a, e)  { val rb_69 = ruleRank(b, e)  ((ra_68 > rb_69) or ((ra_68 == rb_69) and ((a.priority > b.priority) or ((a.priority == b.priority) and (a.createdAt < b.createdAt))))) } }

  // §14.5, ARCH-15. Правило-победитель сценария s для события: из подошедших правил с этим сценарием — те, кого не старше ни одно; сервер берёт первое по порядку списка — rules упорядочены по intake.ruleOrder. От него приоритет и ruleGuid инцидента

  def ruleFor(rules: List[Rule], e: Event, s: str): List[Rule] =
    { val ms_70 = rules.select(r_71 => (ruleMatches(r_71, e) and r_71.scenarios.foldl(false, (acc, y72) => acc or y72 == s)))  ms_70.select(r_73 => not(ms_70.foldl(false, (acc, o_74) => acc or ruleBeats(o_74, r_73, e)))) }

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_75 => (e_75.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_76 => ((e_76.id != p.id) and inGroupAt(e_76, p, at)))

  // §14.5, ARCH-15. Соседи — инциденты того же события, кроме самого x: другие службы той же тревоги. Не привязка §11: у каждого свой владелец, сроки и закрытие

  def siblingsOf(incidents: List[Incident], x: Incident): List[Incident] =
    incidents.select(s_77 => (((x.eventGuid != "") and (s_77.eventGuid == x.eventGuid)) and (s_77.id != x.id)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w78 = if (not(timerDef(timerId).pausable)) {
      val sec_79 = timerSec(w0.inc.get(iid), timerId, "")
      val w80 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_79 < 0)) 0 else (c.now + (sec_79 * 1000))) }) }) }
      val w81 = { ...w80, inc: w80.inc.set(iid, { ...w80.inc.get(iid), timers: w80.inc.get(iid).timers.set(timerId, { ...w80.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w81
    } else {
      val w82 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_83 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w84 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_83 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_83)) }) }) }
      val w85 = { ...w84, inc: w84.inc.set(iid, { ...w84.inc.get(iid), timers: w84.inc.get(iid).timers.set(timerId, { ...w84.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w86 = { ...w85, inc: w85.inc.set(iid, { ...w85.inc.get(iid), timers: w85.inc.get(iid).timers.set(timerId, { ...w85.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w86
    } else w0
      w82
    }
    w78
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w87 = if (not(timerDef(timerId).pausable)) {
      val w88 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w89 = { ...w88, inc: w88.inc.set(iid, { ...w88.inc.get(iid), timers: w88.inc.get(iid).timers.set(timerId, { ...w88.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w89
    } else {
      val w90 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w91 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w92 = { ...w91, inc: w91.inc.set(iid, { ...w91.inc.get(iid), timers: w91.inc.get(iid).timers.set(timerId, { ...w91.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w93 = { ...w92, inc: w92.inc.set(iid, { ...w92.inc.get(iid), timers: w92.inc.get(iid).timers.set(timerId, { ...w92.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w93
    } else w0
      w90
    }
    w87
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_94 = ""
    val w95 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_94 }) }
    w95
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_96 = ""
    val w97 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_96 }) }
    w97
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_98 = 0
    val w99 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_98 }) }
    w99
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w100 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w101 = if (timerDef("reaction").startsOnce) {
      val w102 = ec_resumeTimer(w0, c, iid, "reaction")
      w102
    } else {
      val w103 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w104 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w105 = { ...w104, inc: w104.inc.set(iid, { ...w104.inc.get(iid), timers: w104.inc.get(iid).timers.set("reaction", { ...w104.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w106 = { ...w105, inc: w105.inc.set(iid, { ...w105.inc.get(iid), timers: w105.inc.get(iid).timers.set("reaction", { ...w105.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w106
    } else {
      val sec_107 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w108 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_107 < 0)) 0 else (c.now + (sec_107 * 1000))) }) }) }
      val w109 = { ...w108, inc: w108.inc.set(iid, { ...w108.inc.get(iid), timers: w108.inc.get(iid).timers.set("reaction", { ...w108.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w110 = { ...w109, inc: w109.inc.set(iid, { ...w109.inc.get(iid), timers: w109.inc.get(iid).timers.set("reaction", { ...w109.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w111 = { ...w110, inc: w110.inc.set(iid, { ...w110.inc.get(iid), timers: w110.inc.get(iid).timers.set("reaction", { ...w110.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w111
    }
      w103
    }
      w101
    }
    w100
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
    not(settings.session.states.foldl(false, (acc, s_112) => acc or ((s_112.id == agentState(c.me)) and s_112.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_113 = c.actor
    val w114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_113 }) }
    w114
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w115 = if (timerDef("reaction").startsOnce) {
      val w116 = ec_pauseTimer(w0, c, iid, "reaction")
      w116
    } else {
      val w117 = if (false) {
      val w118 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w119 = { ...w118, inc: w118.inc.set(iid, { ...w118.inc.get(iid), timers: w118.inc.get(iid).timers.set("reaction", { ...w118.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w120 = { ...w119, inc: w119.inc.set(iid, { ...w119.inc.get(iid), timers: w119.inc.get(iid).timers.set("reaction", { ...w119.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w121 = { ...w120, inc: w120.inc.set(iid, { ...w120.inc.get(iid), timers: w120.inc.get(iid).timers.set("reaction", { ...w120.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w121
    } else {
      val w122 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_123 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w124 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_123) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w125 = { ...w124, inc: w124.inc.set(iid, { ...w124.inc.get(iid), timers: w124.inc.get(iid).timers.set("reaction", { ...w124.inc.get(iid).timers.get("reaction"), paused: keep_123 }) }) }
      val w126 = { ...w125, inc: w125.inc.set(iid, { ...w125.inc.get(iid), timers: w125.inc.get(iid).timers.set("reaction", { ...w125.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w127 = { ...w126, inc: w126.inc.set(iid, { ...w126.inc.get(iid), timers: w126.inc.get(iid).timers.set("reaction", { ...w126.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w127
    }
      w122
    }
      w117
    }
    w115
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w128 = if (not(timerDef("resolution").pausable)) {
      val sec_129 = timerSec(w0.inc.get(iid), "resolution", "")
      val w130 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_129 < 0)) 0 else (c.now + (sec_129 * 1000))) }) }) }
      val w131 = { ...w130, inc: w130.inc.set(iid, { ...w130.inc.get(iid), timers: w130.inc.get(iid).timers.set("resolution", { ...w130.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w131
    } else {
      val w132 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_133 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w134 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_133 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_133)) }) }) }
      val w135 = { ...w134, inc: w134.inc.set(iid, { ...w134.inc.get(iid), timers: w134.inc.get(iid).timers.set("resolution", { ...w134.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w136 = { ...w135, inc: w135.inc.set(iid, { ...w135.inc.get(iid), timers: w135.inc.get(iid).timers.set("resolution", { ...w135.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w136
    } else w0
      w132
    }
    w128
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
    not(settings.session.states.foldl(false, (acc, s_137) => acc or ((s_137.id == agentState(c.me)) and s_137.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_138 = c.actor
    val w139 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_138 }) }
    w139
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_140 = ""
    val w141 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_140 }) }
    w141
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w142 = if (timerDef("reaction").startsOnce) {
      val w143 = ec_pauseTimer(w0, c, iid, "reaction")
      w143
    } else {
      val w144 = if (false) {
      val w145 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w146 = { ...w145, inc: w145.inc.set(iid, { ...w145.inc.get(iid), timers: w145.inc.get(iid).timers.set("reaction", { ...w145.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w147 = { ...w146, inc: w146.inc.set(iid, { ...w146.inc.get(iid), timers: w146.inc.get(iid).timers.set("reaction", { ...w146.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w148 = { ...w147, inc: w147.inc.set(iid, { ...w147.inc.get(iid), timers: w147.inc.get(iid).timers.set("reaction", { ...w147.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w148
    } else {
      val w149 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_150 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w151 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_150) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w152 = { ...w151, inc: w151.inc.set(iid, { ...w151.inc.get(iid), timers: w151.inc.get(iid).timers.set("reaction", { ...w151.inc.get(iid).timers.get("reaction"), paused: keep_150 }) }) }
      val w153 = { ...w152, inc: w152.inc.set(iid, { ...w152.inc.get(iid), timers: w152.inc.get(iid).timers.set("reaction", { ...w152.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w154 = { ...w153, inc: w153.inc.set(iid, { ...w153.inc.get(iid), timers: w153.inc.get(iid).timers.set("reaction", { ...w153.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w154
    }
      w149
    }
      w144
    }
    w142
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w155 = if (not(timerDef("resolution").pausable)) {
      val sec_156 = timerSec(w0.inc.get(iid), "resolution", "")
      val w157 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_156 < 0)) 0 else (c.now + (sec_156 * 1000))) }) }) }
      val w158 = { ...w157, inc: w157.inc.set(iid, { ...w157.inc.get(iid), timers: w157.inc.get(iid).timers.set("resolution", { ...w157.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w158
    } else {
      val w159 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_160 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w161 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_160 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_160)) }) }) }
      val w162 = { ...w161, inc: w161.inc.set(iid, { ...w161.inc.get(iid), timers: w161.inc.get(iid).timers.set("resolution", { ...w161.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w163 = { ...w162, inc: w162.inc.set(iid, { ...w162.inc.get(iid), timers: w162.inc.get(iid).timers.set("resolution", { ...w162.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w163
    } else w0
      w159
    }
    w155
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
    not(settings.session.states.foldl(false, (acc, s_164) => acc or ((s_164.id == agentState(c.me)) and s_164.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_165 = ""
    val w166 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_165 }) }
    w166
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_167 = ""
    val w168 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_167 }) }
    w168
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
    not(settings.session.states.foldl(false, (acc, s_169) => acc or ((s_169.id == agentState(c.me)) and s_169.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_170 = c.form.reasonId
    val w171 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_170 }) }
    w171
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
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

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w179 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w180 = if (timerDef("hold").startsOnce) {
      val w181 = ec_resumeTimer(w0, c, iid, "hold")
      w181
    } else {
      val w182 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w183 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w184 = { ...w183, inc: w183.inc.set(iid, { ...w183.inc.get(iid), timers: w183.inc.get(iid).timers.set("hold", { ...w183.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w185 = { ...w184, inc: w184.inc.set(iid, { ...w184.inc.get(iid), timers: w184.inc.get(iid).timers.set("hold", { ...w184.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w185
    } else {
      val sec_186 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w187 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_186 < 0)) 0 else (c.now + (sec_186 * 1000))) }) }) }
      val w188 = { ...w187, inc: w187.inc.set(iid, { ...w187.inc.get(iid), timers: w187.inc.get(iid).timers.set("hold", { ...w187.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w189 = { ...w188, inc: w188.inc.set(iid, { ...w188.inc.get(iid), timers: w188.inc.get(iid).timers.set("hold", { ...w188.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w190 = { ...w189, inc: w189.inc.set(iid, { ...w189.inc.get(iid), timers: w189.inc.get(iid).timers.set("hold", { ...w189.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w190
    }
      w182
    }
      w180
    }
    w179
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
    not(settings.session.states.foldl(false, (acc, s_191) => acc or ((s_191.id == agentState(c.me)) and s_191.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w192 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w192
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w193 = if (timerDef("hold").startsOnce) {
      val w194 = ec_pauseTimer(w0, c, iid, "hold")
      w194
    } else {
      val w195 = if (false) {
      val w196 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w197 = { ...w196, inc: w196.inc.set(iid, { ...w196.inc.get(iid), timers: w196.inc.get(iid).timers.set("hold", { ...w196.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w198 = { ...w197, inc: w197.inc.set(iid, { ...w197.inc.get(iid), timers: w197.inc.get(iid).timers.set("hold", { ...w197.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w199 = { ...w198, inc: w198.inc.set(iid, { ...w198.inc.get(iid), timers: w198.inc.get(iid).timers.set("hold", { ...w198.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w199
    } else {
      val w200 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_201 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w202 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_201) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w203 = { ...w202, inc: w202.inc.set(iid, { ...w202.inc.get(iid), timers: w202.inc.get(iid).timers.set("hold", { ...w202.inc.get(iid).timers.get("hold"), paused: keep_201 }) }) }
      val w204 = { ...w203, inc: w203.inc.set(iid, { ...w203.inc.get(iid), timers: w203.inc.get(iid).timers.set("hold", { ...w203.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w205 = { ...w204, inc: w204.inc.set(iid, { ...w204.inc.get(iid), timers: w204.inc.get(iid).timers.set("hold", { ...w204.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w205
    }
      w200
    }
      w195
    }
    w193
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w206 = if (not(timerDef("resolution").pausable)) {
      val sec_207 = timerSec(w0.inc.get(iid), "resolution", "")
      val w208 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_207 < 0)) 0 else (c.now + (sec_207 * 1000))) }) }) }
      val w209 = { ...w208, inc: w208.inc.set(iid, { ...w208.inc.get(iid), timers: w208.inc.get(iid).timers.set("resolution", { ...w208.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w209
    } else {
      val w210 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_211 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w212 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_211 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_211)) }) }) }
      val w213 = { ...w212, inc: w212.inc.set(iid, { ...w212.inc.get(iid), timers: w212.inc.get(iid).timers.set("resolution", { ...w212.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w214 = { ...w213, inc: w213.inc.set(iid, { ...w213.inc.get(iid), timers: w213.inc.get(iid).timers.set("resolution", { ...w213.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w214
    } else w0
      w210
    }
    w206
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
    not(settings.session.states.foldl(false, (acc, s_215) => acc or ((s_215.id == agentState(c.me)) and s_215.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_216 = ""
    val w217 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_216 }) }
    w217
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w218 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w218
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w219 = if (not(timerDef("resolution").pausable)) {
      val w220 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w221 = { ...w220, inc: w220.inc.set(iid, { ...w220.inc.get(iid), timers: w220.inc.get(iid).timers.set("resolution", { ...w220.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w221
    } else {
      val w222 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w223 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w224 = { ...w223, inc: w223.inc.set(iid, { ...w223.inc.get(iid), timers: w223.inc.get(iid).timers.set("resolution", { ...w223.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w225 = { ...w224, inc: w224.inc.set(iid, { ...w224.inc.get(iid), timers: w224.inc.get(iid).timers.set("resolution", { ...w224.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w225
    } else w0
      w222
    }
    w219
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w226 = if (timerDef("hold").startsOnce) {
      val w227 = ec_pauseTimer(w0, c, iid, "hold")
      w227
    } else {
      val w228 = if (false) {
      val w229 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w230 = { ...w229, inc: w229.inc.set(iid, { ...w229.inc.get(iid), timers: w229.inc.get(iid).timers.set("hold", { ...w229.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w231 = { ...w230, inc: w230.inc.set(iid, { ...w230.inc.get(iid), timers: w230.inc.get(iid).timers.set("hold", { ...w230.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w232 = { ...w231, inc: w231.inc.set(iid, { ...w231.inc.get(iid), timers: w231.inc.get(iid).timers.set("hold", { ...w231.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w232
    } else {
      val w233 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_234 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w235 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_234) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w236 = { ...w235, inc: w235.inc.set(iid, { ...w235.inc.get(iid), timers: w235.inc.get(iid).timers.set("hold", { ...w235.inc.get(iid).timers.get("hold"), paused: keep_234 }) }) }
      val w237 = { ...w236, inc: w236.inc.set(iid, { ...w236.inc.get(iid), timers: w236.inc.get(iid).timers.set("hold", { ...w236.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w238 = { ...w237, inc: w237.inc.set(iid, { ...w237.inc.get(iid), timers: w237.inc.get(iid).timers.set("hold", { ...w237.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w238
    }
      w233
    }
      w228
    }
    w226
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w239 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w240 = if (timerDef("reaction").startsOnce) {
      val w241 = ec_resumeTimer(w0, c, iid, "reaction")
      w241
    } else {
      val w242 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w243 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w244 = { ...w243, inc: w243.inc.set(iid, { ...w243.inc.get(iid), timers: w243.inc.get(iid).timers.set("reaction", { ...w243.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w245 = { ...w244, inc: w244.inc.set(iid, { ...w244.inc.get(iid), timers: w244.inc.get(iid).timers.set("reaction", { ...w244.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w245
    } else {
      val sec_246 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w247 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_246 < 0)) 0 else (c.now + (sec_246 * 1000))) }) }) }
      val w248 = { ...w247, inc: w247.inc.set(iid, { ...w247.inc.get(iid), timers: w247.inc.get(iid).timers.set("reaction", { ...w247.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w249 = { ...w248, inc: w248.inc.set(iid, { ...w248.inc.get(iid), timers: w248.inc.get(iid).timers.set("reaction", { ...w248.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w250 = { ...w249, inc: w249.inc.set(iid, { ...w249.inc.get(iid), timers: w249.inc.get(iid).timers.set("reaction", { ...w249.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w250
    }
      w242
    }
      w240
    }
    w239
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
    not(settings.session.states.foldl(false, (acc, s_251) => acc or ((s_251.id == agentState(c.me)) and s_251.readOnly))),
    transferTargets.foldl(false, (acc, t_252) => acc or (offersTransferTo(c.me, t_252, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_253) => acc and (isDone(e_253) or hasAccess(t_252, e_253))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_254) => acc and (isDone(e_254) or hasAccess(c.form.targetId, e_254)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_255 = personOf(c.form.targetId)
    val w256 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_255 }) }
    w256
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_257 = groupOf(c.form.targetId)
    val w258 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_257 }) }
    w258
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w259 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w259
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w260 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w260
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w261 = if (not(timerDef("resolution").pausable)) {
      val w262 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w263 = { ...w262, inc: w262.inc.set(iid, { ...w262.inc.get(iid), timers: w262.inc.get(iid).timers.set("resolution", { ...w262.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w263
    } else {
      val w264 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w265 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w266 = { ...w265, inc: w265.inc.set(iid, { ...w265.inc.get(iid), timers: w265.inc.get(iid).timers.set("resolution", { ...w265.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w267 = { ...w266, inc: w266.inc.set(iid, { ...w266.inc.get(iid), timers: w266.inc.get(iid).timers.set("resolution", { ...w266.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w267
    } else w0
      w264
    }
    w261
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w268 = if (timerDef("hold").startsOnce) {
      val w269 = ec_pauseTimer(w0, c, iid, "hold")
      w269
    } else {
      val w270 = if (false) {
      val w271 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w272 = { ...w271, inc: w271.inc.set(iid, { ...w271.inc.get(iid), timers: w271.inc.get(iid).timers.set("hold", { ...w271.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w273 = { ...w272, inc: w272.inc.set(iid, { ...w272.inc.get(iid), timers: w272.inc.get(iid).timers.set("hold", { ...w272.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w274 = { ...w273, inc: w273.inc.set(iid, { ...w273.inc.get(iid), timers: w273.inc.get(iid).timers.set("hold", { ...w273.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w274
    } else {
      val w275 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_276 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w277 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_276) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w278 = { ...w277, inc: w277.inc.set(iid, { ...w277.inc.get(iid), timers: w277.inc.get(iid).timers.set("hold", { ...w277.inc.get(iid).timers.get("hold"), paused: keep_276 }) }) }
      val w279 = { ...w278, inc: w278.inc.set(iid, { ...w278.inc.get(iid), timers: w278.inc.get(iid).timers.set("hold", { ...w278.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w280 = { ...w279, inc: w279.inc.set(iid, { ...w279.inc.get(iid), timers: w279.inc.get(iid).timers.set("hold", { ...w279.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w280
    }
      w275
    }
      w270
    }
    w268
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w281 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w282 = if (timerDef("reaction").startsOnce) {
      val w283 = ec_resumeTimer(w0, c, iid, "reaction")
      w283
    } else {
      val w284 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w285 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w286 = { ...w285, inc: w285.inc.set(iid, { ...w285.inc.get(iid), timers: w285.inc.get(iid).timers.set("reaction", { ...w285.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w287 = { ...w286, inc: w286.inc.set(iid, { ...w286.inc.get(iid), timers: w286.inc.get(iid).timers.set("reaction", { ...w286.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w287
    } else {
      val sec_288 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w289 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_288 < 0)) 0 else (c.now + (sec_288 * 1000))) }) }) }
      val w290 = { ...w289, inc: w289.inc.set(iid, { ...w289.inc.get(iid), timers: w289.inc.get(iid).timers.set("reaction", { ...w289.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w291 = { ...w290, inc: w290.inc.set(iid, { ...w290.inc.get(iid), timers: w290.inc.get(iid).timers.set("reaction", { ...w290.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w292 = { ...w291, inc: w291.inc.set(iid, { ...w291.inc.get(iid), timers: w291.inc.get(iid).timers.set("reaction", { ...w291.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w292
    }
      w284
    }
      w282
    }
    w281
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_293 = c.before.owner
    val w294 = if (((whom_293 != "") and (whom_293 != c.actor))) w0 else w0
    w294
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_295 = addressee(w0.inc.get(iid))
    val w296 = if (((whom_295 != "") and (whom_295 != c.actor))) w0 else w0
    w296
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
    not(settings.session.states.foldl(false, (acc, s_297) => acc or ((s_297.id == agentState(c.me)) and s_297.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_298 = c.actor
    val w299 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_298 }) }
    w299
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_300 = ""
    val w301 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_300 }) }
    w301
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w302 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w302
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w303 = if (timerDef("reaction").startsOnce) {
      val w304 = ec_pauseTimer(w0, c, iid, "reaction")
      w304
    } else {
      val w305 = if (false) {
      val w306 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w307 = { ...w306, inc: w306.inc.set(iid, { ...w306.inc.get(iid), timers: w306.inc.get(iid).timers.set("reaction", { ...w306.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w308 = { ...w307, inc: w307.inc.set(iid, { ...w307.inc.get(iid), timers: w307.inc.get(iid).timers.set("reaction", { ...w307.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w309 = { ...w308, inc: w308.inc.set(iid, { ...w308.inc.get(iid), timers: w308.inc.get(iid).timers.set("reaction", { ...w308.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w309
    } else {
      val w310 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_311 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w312 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_311) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w313 = { ...w312, inc: w312.inc.set(iid, { ...w312.inc.get(iid), timers: w312.inc.get(iid).timers.set("reaction", { ...w312.inc.get(iid).timers.get("reaction"), paused: keep_311 }) }) }
      val w314 = { ...w313, inc: w313.inc.set(iid, { ...w313.inc.get(iid), timers: w313.inc.get(iid).timers.set("reaction", { ...w313.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w315 = { ...w314, inc: w314.inc.set(iid, { ...w314.inc.get(iid), timers: w314.inc.get(iid).timers.set("reaction", { ...w314.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w315
    }
      w310
    }
      w305
    }
    w303
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w316 = if (timerDef("hold").startsOnce) {
      val w317 = ec_pauseTimer(w0, c, iid, "hold")
      w317
    } else {
      val w318 = if (false) {
      val w319 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w320 = { ...w319, inc: w319.inc.set(iid, { ...w319.inc.get(iid), timers: w319.inc.get(iid).timers.set("hold", { ...w319.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w321 = { ...w320, inc: w320.inc.set(iid, { ...w320.inc.get(iid), timers: w320.inc.get(iid).timers.set("hold", { ...w320.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w322 = { ...w321, inc: w321.inc.set(iid, { ...w321.inc.get(iid), timers: w321.inc.get(iid).timers.set("hold", { ...w321.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w322
    } else {
      val w323 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_324 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w325 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_324) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w326 = { ...w325, inc: w325.inc.set(iid, { ...w325.inc.get(iid), timers: w325.inc.get(iid).timers.set("hold", { ...w325.inc.get(iid).timers.get("hold"), paused: keep_324 }) }) }
      val w327 = { ...w326, inc: w326.inc.set(iid, { ...w326.inc.get(iid), timers: w326.inc.get(iid).timers.set("hold", { ...w326.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w328 = { ...w327, inc: w327.inc.set(iid, { ...w327.inc.get(iid), timers: w327.inc.get(iid).timers.set("hold", { ...w327.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w328
    }
      w323
    }
      w318
    }
    w316
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w329 = if (not(timerDef("resolution").pausable)) {
      val sec_330 = timerSec(w0.inc.get(iid), "resolution", "")
      val w331 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_330 < 0)) 0 else (c.now + (sec_330 * 1000))) }) }) }
      val w332 = { ...w331, inc: w331.inc.set(iid, { ...w331.inc.get(iid), timers: w331.inc.get(iid).timers.set("resolution", { ...w331.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w332
    } else {
      val w333 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_334 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w335 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_334 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_334)) }) }) }
      val w336 = { ...w335, inc: w335.inc.set(iid, { ...w335.inc.get(iid), timers: w335.inc.get(iid).timers.set("resolution", { ...w335.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w337 = { ...w336, inc: w336.inc.set(iid, { ...w336.inc.get(iid), timers: w336.inc.get(iid).timers.set("resolution", { ...w336.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w337
    } else w0
      w333
    }
    w329
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
    val whom_338 = c.before.owner
    val w339 = if (((whom_338 != "") and (whom_338 != c.actor))) w0 else w0
    w339
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
    not(settings.session.states.foldl(false, (acc, s_340) => acc or ((s_340.id == agentState(c.me)) and s_340.readOnly))),
    { val os_341 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_341.foldl(false, (acc, o_342) => acc or ((o_342.id == c.form.resultId) and stepsOk(o_342, world.inc.get(iid)))) else os_341.foldl(false, (acc, o_343) => acc or stepsOk(o_343, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_344 = c.actor
    val w345 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_344 }) }
    w345
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_346 = ""
    val w347 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_346 }) }
    w347
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_348 = c.actor
    val w349 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_348 }) }
    w349
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_350 = c.now
    val w351 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_350 }) }
    w351
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_352 = c.form.resultId
    val w353 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_352 }) }
    w353
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_354 = c.form.causeId
    val w355 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_354 }) }
    w355
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_356 = c.form.comment
    val w357 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_356 }) }
    w357
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w358 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w358
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w359 = if (timerDef("reaction").startsOnce) {
      val w360 = ec_pauseTimer(w0, c, iid, "reaction")
      w360
    } else {
      val w361 = if (true) {
      val w362 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w363 = { ...w362, inc: w362.inc.set(iid, { ...w362.inc.get(iid), timers: w362.inc.get(iid).timers.set("reaction", { ...w362.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w364 = { ...w363, inc: w363.inc.set(iid, { ...w363.inc.get(iid), timers: w363.inc.get(iid).timers.set("reaction", { ...w363.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w365 = { ...w364, inc: w364.inc.set(iid, { ...w364.inc.get(iid), timers: w364.inc.get(iid).timers.set("reaction", { ...w364.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w365
    } else {
      val w366 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_367 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w368 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_367) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w369 = { ...w368, inc: w368.inc.set(iid, { ...w368.inc.get(iid), timers: w368.inc.get(iid).timers.set("reaction", { ...w368.inc.get(iid).timers.get("reaction"), paused: keep_367 }) }) }
      val w370 = { ...w369, inc: w369.inc.set(iid, { ...w369.inc.get(iid), timers: w369.inc.get(iid).timers.set("reaction", { ...w369.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w371 = { ...w370, inc: w370.inc.set(iid, { ...w370.inc.get(iid), timers: w370.inc.get(iid).timers.set("reaction", { ...w370.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w371
    }
      w366
    }
      w361
    }
    w359
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w372 = if (not(timerDef("resolution").pausable)) {
      val w373 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w374 = { ...w373, inc: w373.inc.set(iid, { ...w373.inc.get(iid), timers: w373.inc.get(iid).timers.set("resolution", { ...w373.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w374
    } else {
      val w375 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w376 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w377 = { ...w376, inc: w376.inc.set(iid, { ...w376.inc.get(iid), timers: w376.inc.get(iid).timers.set("resolution", { ...w376.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w378 = { ...w377, inc: w377.inc.set(iid, { ...w377.inc.get(iid), timers: w377.inc.get(iid).timers.set("resolution", { ...w377.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w378
    } else w0
      w375
    }
    w372
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w379 = if (timerDef("hold").startsOnce) {
      val w380 = ec_pauseTimer(w0, c, iid, "hold")
      w380
    } else {
      val w381 = if (false) {
      val w382 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w383 = { ...w382, inc: w382.inc.set(iid, { ...w382.inc.get(iid), timers: w382.inc.get(iid).timers.set("hold", { ...w382.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w384 = { ...w383, inc: w383.inc.set(iid, { ...w383.inc.get(iid), timers: w383.inc.get(iid).timers.set("hold", { ...w383.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w385 = { ...w384, inc: w384.inc.set(iid, { ...w384.inc.get(iid), timers: w384.inc.get(iid).timers.set("hold", { ...w384.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w385
    } else {
      val w386 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_387 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w388 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_387) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w389 = { ...w388, inc: w388.inc.set(iid, { ...w388.inc.get(iid), timers: w388.inc.get(iid).timers.set("hold", { ...w388.inc.get(iid).timers.get("hold"), paused: keep_387 }) }) }
      val w390 = { ...w389, inc: w389.inc.set(iid, { ...w389.inc.get(iid), timers: w389.inc.get(iid).timers.set("hold", { ...w389.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w391 = { ...w390, inc: w390.inc.set(iid, { ...w390.inc.get(iid), timers: w390.inc.get(iid).timers.set("hold", { ...w390.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w391
    }
      w386
    }
      w381
    }
    w379
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {
    val w392 = if (["false_alarm"].foldl(false, (acc, y393) => acc or y393 == w0.inc.get(iid).closeResultId)) {
      val w394 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_399 => not(isDone(x_399))).foldl([], (acc, x397) => acc.append(x397.id)).foldl(w0, (wf395, sId396) => {
      val w398 = if (((addressee(wf395.inc.get(sId396)) != "") and (addressee(wf395.inc.get(sId396)) != wf395.inc.get(iid).closedBy))) wf395 else wf395
      w398
    })
      w394
    } else w0
    w392
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
    not(settings.session.states.foldl(false, (acc, s_400) => acc or ((s_400.id == agentState(c.me)) and s_400.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_401 = c.actor
    val w402 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_401 }) }
    w402
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w403 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_404 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w405 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w406 = { ...w405, inc: w405.inc.set(iid, { ...w405.inc.get(iid), linkedTo: "" }) }
      val w407 = { ...w406, inc: w406.inc.set(iid, { ...w406.inc.get(iid), linkedAt: 0 }) }
      val w408 = if (((ps_404.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w407 else w407
      val w409 = if (("workflow.journal.linked_reopened" != "")) {
      val w410 = ps_404.foldl([], (acc, x413) => acc.append(x413.id)).foldl(w408, (wf411, pId412) => wf411)
      w410
    } else w408
      w409
    } else {
      val w414 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w415 = { ...w414, inc: w414.inc.set(iid, { ...w414.inc.get(iid), linkedAt: 0 }) }
      w415
    }
    w403
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_416 = ""
    val w417 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_416 }) }
    w417
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_418 = ""
    val w419 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_418 }) }
    w419
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_420 = ""
    val w421 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_420 }) }
    w421
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_422 = 0
    val w423 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_422 }) }
    w423
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_424 = ""
    val w425 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_424 }) }
    w425
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val sec_426 = settings.limits.reopenResolutionSec
    val w427 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_426 > 0)) sec_426 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w428 = { ...w427, inc: w427.inc.set(iid, { ...w427.inc.get(iid), timers: w427.inc.get(iid).timers.set("resolution", { ...w427.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w429 = { ...w428, inc: w428.inc.set(iid, { ...w428.inc.get(iid), timers: w428.inc.get(iid).timers.set("resolution", { ...w428.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w429
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val w430 = if (timerDef("reaction").startsOnce) {
      val w431 = ec_pauseTimer(w0, c, iid, "reaction")
      w431
    } else {
      val w432 = if (true) {
      val w433 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w434 = { ...w433, inc: w433.inc.set(iid, { ...w433.inc.get(iid), timers: w433.inc.get(iid).timers.set("reaction", { ...w433.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w435 = { ...w434, inc: w434.inc.set(iid, { ...w434.inc.get(iid), timers: w434.inc.get(iid).timers.set("reaction", { ...w434.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w436 = { ...w435, inc: w435.inc.set(iid, { ...w435.inc.get(iid), timers: w435.inc.get(iid).timers.set("reaction", { ...w435.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w436
    } else {
      val w437 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_438 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w439 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_438) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w440 = { ...w439, inc: w439.inc.set(iid, { ...w439.inc.get(iid), timers: w439.inc.get(iid).timers.set("reaction", { ...w439.inc.get(iid).timers.get("reaction"), paused: keep_438 }) }) }
      val w441 = { ...w440, inc: w440.inc.set(iid, { ...w440.inc.get(iid), timers: w440.inc.get(iid).timers.set("reaction", { ...w440.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w442 = { ...w441, inc: w441.inc.set(iid, { ...w441.inc.get(iid), timers: w441.inc.get(iid).timers.set("reaction", { ...w441.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w442
    }
      w437
    }
      w432
    }
    w430
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
    { val t_443 = world.inc.get(iid).timers.get("reaction")  (((t_443.due != 0) and (t_443.due <= c.now)) and (t_443.fired != t_443.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_444 = personOf(levelUpTarget(c.before))
    val w445 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_444 }) }
    w445
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_446 = groupOf(levelUpTarget(c.before))
    val w447 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_446 }) }
    w447
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_448 = levelUpNumber(c.before)
    val w449 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_448 }) }
    w449
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w450 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w450
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w451 = if (not(timerDef("resolution").pausable)) {
      val w452 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w453 = { ...w452, inc: w452.inc.set(iid, { ...w452.inc.get(iid), timers: w452.inc.get(iid).timers.set("resolution", { ...w452.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w453
    } else {
      val w454 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w455 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w456 = { ...w455, inc: w455.inc.set(iid, { ...w455.inc.get(iid), timers: w455.inc.get(iid).timers.set("resolution", { ...w455.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w457 = { ...w456, inc: w456.inc.set(iid, { ...w456.inc.get(iid), timers: w456.inc.get(iid).timers.set("resolution", { ...w456.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w457
    } else w0
      w454
    }
    w451
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w458 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w459 = if (timerDef("reaction").startsOnce) {
      val w460 = ec_resumeTimer(w0, c, iid, "reaction")
      w460
    } else {
      val w461 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w462 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w463 = { ...w462, inc: w462.inc.set(iid, { ...w462.inc.get(iid), timers: w462.inc.get(iid).timers.set("reaction", { ...w462.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w464 = { ...w463, inc: w463.inc.set(iid, { ...w463.inc.get(iid), timers: w463.inc.get(iid).timers.set("reaction", { ...w463.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w464
    } else {
      val sec_465 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w466 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_465 < 0)) 0 else (c.now + (sec_465 * 1000))) }) }) }
      val w467 = { ...w466, inc: w466.inc.set(iid, { ...w466.inc.get(iid), timers: w466.inc.get(iid).timers.set("reaction", { ...w466.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w468 = { ...w467, inc: w467.inc.set(iid, { ...w467.inc.get(iid), timers: w467.inc.get(iid).timers.set("reaction", { ...w467.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w469 = { ...w468, inc: w468.inc.set(iid, { ...w468.inc.get(iid), timers: w468.inc.get(iid).timers.set("reaction", { ...w468.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w469
    }
      w461
    }
      w459
    }
    w458
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_470 = addressee(w0.inc.get(iid))
    val w471 = if (((whom_470 != "") and (whom_470 != c.actor))) w0 else w0
    w471
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
    { val t_472 = world.inc.get(iid).timers.get("reaction")  (((t_472.due != 0) and (t_472.due <= c.now)) and (t_472.fired != t_472.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_473 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w474 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_473) }) }
    val w475 = { ...w474, inc: w474.inc.set(iid, { ...w474.inc.get(iid), slaBreached: true }) }
    val w476 = groupMembersAt(incs(w0), w475.inc.get(iid), c.deadline).foldl([], (acc, x479) => acc.append(x479.id)).foldl(w475, (wf477, eId478) => {
      val w480 = { ...wf477, inc: wf477.inc.set(eId478, { ...wf477.inc.get(eId478), breaches: wf477.inc.get(eId478).breaches.append(breach_473) }) }
      val w481 = { ...w480, inc: w480.inc.set(eId478, { ...w480.inc.get(eId478), slaBreached: true }) }
      w481
    })
    w476
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w482 = if (timerDef("reaction").startsOnce) {
      val w483 = ec_pauseTimer(w0, c, iid, "reaction")
      w483
    } else {
      val w484 = if (false) {
      val w485 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w486 = { ...w485, inc: w485.inc.set(iid, { ...w485.inc.get(iid), timers: w485.inc.get(iid).timers.set("reaction", { ...w485.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w487 = { ...w486, inc: w486.inc.set(iid, { ...w486.inc.get(iid), timers: w486.inc.get(iid).timers.set("reaction", { ...w486.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w488 = { ...w487, inc: w487.inc.set(iid, { ...w487.inc.get(iid), timers: w487.inc.get(iid).timers.set("reaction", { ...w487.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w488
    } else {
      val w489 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_490 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w491 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_490) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w492 = { ...w491, inc: w491.inc.set(iid, { ...w491.inc.get(iid), timers: w491.inc.get(iid).timers.set("reaction", { ...w491.inc.get(iid).timers.get("reaction"), paused: keep_490 }) }) }
      val w493 = { ...w492, inc: w492.inc.set(iid, { ...w492.inc.get(iid), timers: w492.inc.get(iid).timers.set("reaction", { ...w492.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w494 = { ...w493, inc: w493.inc.set(iid, { ...w493.inc.get(iid), timers: w493.inc.get(iid).timers.set("reaction", { ...w493.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w494
    }
      w489
    }
      w484
    }
    w482
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_495 = settings.alerts.target
    val w496 = if (((whom_495 != "") and (whom_495 != c.actor))) w0 else w0
    w496
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
    { val t_497 = world.inc.get(iid).timers.get("reaction")  (((t_497.due != 0) and (t_497.due <= c.now)) and (t_497.fired != t_497.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_498 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w499 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_498) }) }
    val w500 = { ...w499, inc: w499.inc.set(iid, { ...w499.inc.get(iid), slaBreached: true }) }
    val w501 = groupMembersAt(incs(w0), w500.inc.get(iid), c.deadline).foldl([], (acc, x504) => acc.append(x504.id)).foldl(w500, (wf502, eId503) => {
      val w505 = { ...wf502, inc: wf502.inc.set(eId503, { ...wf502.inc.get(eId503), breaches: wf502.inc.get(eId503).breaches.append(breach_498) }) }
      val w506 = { ...w505, inc: w505.inc.set(eId503, { ...w505.inc.get(eId503), slaBreached: true }) }
      w506
    })
    w501
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w507 = if (timerDef("reaction").startsOnce) {
      val w508 = ec_pauseTimer(w0, c, iid, "reaction")
      w508
    } else {
      val w509 = if (false) {
      val w510 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w511 = { ...w510, inc: w510.inc.set(iid, { ...w510.inc.get(iid), timers: w510.inc.get(iid).timers.set("reaction", { ...w510.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w512 = { ...w511, inc: w511.inc.set(iid, { ...w511.inc.get(iid), timers: w511.inc.get(iid).timers.set("reaction", { ...w511.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w513 = { ...w512, inc: w512.inc.set(iid, { ...w512.inc.get(iid), timers: w512.inc.get(iid).timers.set("reaction", { ...w512.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w513
    } else {
      val w514 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_515 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w516 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_515) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w517 = { ...w516, inc: w516.inc.set(iid, { ...w516.inc.get(iid), timers: w516.inc.get(iid).timers.set("reaction", { ...w516.inc.get(iid).timers.get("reaction"), paused: keep_515 }) }) }
      val w518 = { ...w517, inc: w517.inc.set(iid, { ...w517.inc.get(iid), timers: w517.inc.get(iid).timers.set("reaction", { ...w517.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w519 = { ...w518, inc: w518.inc.set(iid, { ...w518.inc.get(iid), timers: w518.inc.get(iid).timers.set("reaction", { ...w518.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w519
    }
      w514
    }
      w509
    }
    w507
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_520 = settings.alerts.target
    val w521 = if (((whom_520 != "") and (whom_520 != c.actor))) w0 else w0
    w521
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
    { val t_522 = world.inc.get(iid).timers.get("resolution")  (((t_522.due != 0) and (t_522.due <= c.now)) and (t_522.fired != t_522.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_523 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w524 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_523) }) }
    val w525 = { ...w524, inc: w524.inc.set(iid, { ...w524.inc.get(iid), slaBreached: true }) }
    val w526 = groupMembersAt(incs(w0), w525.inc.get(iid), c.deadline).foldl([], (acc, x529) => acc.append(x529.id)).foldl(w525, (wf527, eId528) => {
      val w530 = { ...wf527, inc: wf527.inc.set(eId528, { ...wf527.inc.get(eId528), breaches: wf527.inc.get(eId528).breaches.append(breach_523) }) }
      val w531 = { ...w530, inc: w530.inc.set(eId528, { ...w530.inc.get(eId528), slaBreached: true }) }
      w531
    })
    w526
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_532 = settings.alerts.target
    val w533 = if (((whom_532 != "") and (whom_532 != c.actor))) w0 else w0
    w533
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
    { val t_534 = world.inc.get(iid).timers.get("resolution")  (((t_534.due != 0) and (t_534.due <= c.now)) and (t_534.fired != t_534.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_535 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w536 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_535) }) }
    val w537 = { ...w536, inc: w536.inc.set(iid, { ...w536.inc.get(iid), slaBreached: true }) }
    val w538 = groupMembersAt(incs(w0), w537.inc.get(iid), c.deadline).foldl([], (acc, x541) => acc.append(x541.id)).foldl(w537, (wf539, eId540) => {
      val w542 = { ...wf539, inc: wf539.inc.set(eId540, { ...wf539.inc.get(eId540), breaches: wf539.inc.get(eId540).breaches.append(breach_535) }) }
      val w543 = { ...w542, inc: w542.inc.set(eId540, { ...w542.inc.get(eId540), slaBreached: true }) }
      w543
    })
    w538
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_544 = personOf(levelUpTarget(c.before))
    val w545 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_544 }) }
    w545
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_546 = groupOf(levelUpTarget(c.before))
    val w547 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_546 }) }
    w547
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_548 = levelUpNumber(c.before)
    val w549 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_548 }) }
    w549
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w550 = if (not(timerDef("resolution").pausable)) {
      val w551 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w552 = { ...w551, inc: w551.inc.set(iid, { ...w551.inc.get(iid), timers: w551.inc.get(iid).timers.set("resolution", { ...w551.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w552
    } else {
      val w553 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w554 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w555 = { ...w554, inc: w554.inc.set(iid, { ...w554.inc.get(iid), timers: w554.inc.get(iid).timers.set("resolution", { ...w554.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w556 = { ...w555, inc: w555.inc.set(iid, { ...w555.inc.get(iid), timers: w555.inc.get(iid).timers.set("resolution", { ...w555.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w556
    } else w0
      w553
    }
    w550
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w557 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w558 = if (timerDef("reaction").startsOnce) {
      val w559 = ec_resumeTimer(w0, c, iid, "reaction")
      w559
    } else {
      val w560 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w561 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w562 = { ...w561, inc: w561.inc.set(iid, { ...w561.inc.get(iid), timers: w561.inc.get(iid).timers.set("reaction", { ...w561.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w563 = { ...w562, inc: w562.inc.set(iid, { ...w562.inc.get(iid), timers: w562.inc.get(iid).timers.set("reaction", { ...w562.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w563
    } else {
      val sec_564 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w565 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_564 < 0)) 0 else (c.now + (sec_564 * 1000))) }) }) }
      val w566 = { ...w565, inc: w565.inc.set(iid, { ...w565.inc.get(iid), timers: w565.inc.get(iid).timers.set("reaction", { ...w565.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w567 = { ...w566, inc: w566.inc.set(iid, { ...w566.inc.get(iid), timers: w566.inc.get(iid).timers.set("reaction", { ...w566.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w568 = { ...w567, inc: w567.inc.set(iid, { ...w567.inc.get(iid), timers: w567.inc.get(iid).timers.set("reaction", { ...w567.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w568
    }
      w560
    }
      w558
    }
    w557
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_569 = c.before.owner
    val w570 = if (((whom_569 != "") and (whom_569 != c.actor))) w0 else w0
    w570
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_571 = addressee(w0.inc.get(iid))
    val w572 = if (((whom_571 != "") and (whom_571 != c.actor))) w0 else w0
    w572
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
    { val t_573 = world.inc.get(iid).timers.get("resolution")  (((t_573.due != 0) and (t_573.due <= c.now)) and (t_573.fired != t_573.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_574 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w575 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_574) }) }
    val w576 = { ...w575, inc: w575.inc.set(iid, { ...w575.inc.get(iid), slaBreached: true }) }
    val w577 = groupMembersAt(incs(w0), w576.inc.get(iid), c.deadline).foldl([], (acc, x580) => acc.append(x580.id)).foldl(w576, (wf578, eId579) => {
      val w581 = { ...wf578, inc: wf578.inc.set(eId579, { ...wf578.inc.get(eId579), breaches: wf578.inc.get(eId579).breaches.append(breach_574) }) }
      val w582 = { ...w581, inc: w581.inc.set(eId579, { ...w581.inc.get(eId579), slaBreached: true }) }
      w582
    })
    w577
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_583 = settings.alerts.target
    val w584 = if (((whom_583 != "") and (whom_583 != c.actor))) w0 else w0
    w584
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
    { val t_585 = world.inc.get(iid).timers.get("hold")  (((t_585.due != 0) and (t_585.due <= c.now)) and (t_585.fired != t_585.due)) },
    not(["break", "no_link"].foldl(false, (acc, y586) => acc or y586 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_587 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w588 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_587) }) }
    val w589 = { ...w588, inc: w588.inc.set(iid, { ...w588.inc.get(iid), slaBreached: true }) }
    val w590 = groupMembersAt(incs(w0), w589.inc.get(iid), c.deadline).foldl([], (acc, x593) => acc.append(x593.id)).foldl(w589, (wf591, eId592) => {
      val w594 = { ...wf591, inc: wf591.inc.set(eId592, { ...wf591.inc.get(eId592), breaches: wf591.inc.get(eId592).breaches.append(breach_587) }) }
      val w595 = { ...w594, inc: w594.inc.set(eId592, { ...w594.inc.get(eId592), slaBreached: true }) }
      w595
    })
    w590
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_596 = settings.alerts.target
    val w597 = if (((whom_596 != "") and (whom_596 != c.actor))) w0 else w0
    w597
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
    { val t_598 = world.inc.get(iid).timers.get("hold")  (((t_598.due != 0) and (t_598.due <= c.now)) and (t_598.fired != t_598.due)) },
    ["break"].foldl(false, (acc, y599) => acc or y599 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_600 = ""
    val w601 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_600 }) }
    w601
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w602 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w602
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w603 = if (timerDef("hold").startsOnce) {
      val w604 = ec_pauseTimer(w0, c, iid, "hold")
      w604
    } else {
      val w605 = if (false) {
      val w606 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w607 = { ...w606, inc: w606.inc.set(iid, { ...w606.inc.get(iid), timers: w606.inc.get(iid).timers.set("hold", { ...w606.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w608 = { ...w607, inc: w607.inc.set(iid, { ...w607.inc.get(iid), timers: w607.inc.get(iid).timers.set("hold", { ...w607.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w609 = { ...w608, inc: w608.inc.set(iid, { ...w608.inc.get(iid), timers: w608.inc.get(iid).timers.set("hold", { ...w608.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w609
    } else {
      val w610 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_611 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w612 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_611) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w613 = { ...w612, inc: w612.inc.set(iid, { ...w612.inc.get(iid), timers: w612.inc.get(iid).timers.set("hold", { ...w612.inc.get(iid).timers.get("hold"), paused: keep_611 }) }) }
      val w614 = { ...w613, inc: w613.inc.set(iid, { ...w613.inc.get(iid), timers: w613.inc.get(iid).timers.set("hold", { ...w613.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w615 = { ...w614, inc: w614.inc.set(iid, { ...w614.inc.get(iid), timers: w614.inc.get(iid).timers.set("hold", { ...w614.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w615
    }
      w610
    }
      w605
    }
    w603
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w616 = if (not(timerDef("resolution").pausable)) {
      val w617 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w618 = { ...w617, inc: w617.inc.set(iid, { ...w617.inc.get(iid), timers: w617.inc.get(iid).timers.set("resolution", { ...w617.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w618
    } else {
      val w619 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w620 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w621 = { ...w620, inc: w620.inc.set(iid, { ...w620.inc.get(iid), timers: w620.inc.get(iid).timers.set("resolution", { ...w620.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w622 = { ...w621, inc: w621.inc.set(iid, { ...w621.inc.get(iid), timers: w621.inc.get(iid).timers.set("resolution", { ...w621.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w622
    } else w0
      w619
    }
    w616
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w623 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w624 = if (timerDef("reaction").startsOnce) {
      val w625 = ec_resumeTimer(w0, c, iid, "reaction")
      w625
    } else {
      val w626 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w627 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w628 = { ...w627, inc: w627.inc.set(iid, { ...w627.inc.get(iid), timers: w627.inc.get(iid).timers.set("reaction", { ...w627.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w629 = { ...w628, inc: w628.inc.set(iid, { ...w628.inc.get(iid), timers: w628.inc.get(iid).timers.set("reaction", { ...w628.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w629
    } else {
      val sec_630 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w631 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_630 < 0)) 0 else (c.now + (sec_630 * 1000))) }) }) }
      val w632 = { ...w631, inc: w631.inc.set(iid, { ...w631.inc.get(iid), timers: w631.inc.get(iid).timers.set("reaction", { ...w631.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w633 = { ...w632, inc: w632.inc.set(iid, { ...w632.inc.get(iid), timers: w632.inc.get(iid).timers.set("reaction", { ...w632.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w634 = { ...w633, inc: w633.inc.set(iid, { ...w633.inc.get(iid), timers: w633.inc.get(iid).timers.set("reaction", { ...w633.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w634
    }
      w626
    }
      w624
    }
    w623
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
    val reason_635 = "break"
    val w636 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_635 }) }
    w636
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w637 = if (not(timerDef("resolution").pausable)) {
      val w638 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w639 = { ...w638, inc: w638.inc.set(iid, { ...w638.inc.get(iid), timers: w638.inc.get(iid).timers.set("resolution", { ...w638.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w639
    } else {
      val w640 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w641 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w642 = { ...w641, inc: w641.inc.set(iid, { ...w641.inc.get(iid), timers: w641.inc.get(iid).timers.set("resolution", { ...w641.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w643 = { ...w642, inc: w642.inc.set(iid, { ...w642.inc.get(iid), timers: w642.inc.get(iid).timers.set("resolution", { ...w642.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w643
    } else w0
      w640
    }
    w637
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w644 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w645 = if (timerDef("hold").startsOnce) {
      val w646 = ec_resumeTimer(w0, c, iid, "hold")
      w646
    } else {
      val w647 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w648 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w649 = { ...w648, inc: w648.inc.set(iid, { ...w648.inc.get(iid), timers: w648.inc.get(iid).timers.set("hold", { ...w648.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w650 = { ...w649, inc: w649.inc.set(iid, { ...w649.inc.get(iid), timers: w649.inc.get(iid).timers.set("hold", { ...w649.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w650
    } else {
      val sec_651 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w652 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_651 < 0)) 0 else (c.now + (sec_651 * 1000))) }) }) }
      val w653 = { ...w652, inc: w652.inc.set(iid, { ...w652.inc.get(iid), timers: w652.inc.get(iid).timers.set("hold", { ...w652.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w654 = { ...w653, inc: w653.inc.set(iid, { ...w653.inc.get(iid), timers: w653.inc.get(iid).timers.set("hold", { ...w653.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w655 = { ...w654, inc: w654.inc.set(iid, { ...w654.inc.get(iid), timers: w654.inc.get(iid).timers.set("hold", { ...w654.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w655
    }
      w647
    }
      w645
    }
    w644
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
    val reason_656 = "no_link"
    val w657 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_656 }) }
    w657
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w658 = if (not(timerDef("resolution").pausable)) {
      val w659 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w660 = { ...w659, inc: w659.inc.set(iid, { ...w659.inc.get(iid), timers: w659.inc.get(iid).timers.set("resolution", { ...w659.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w660
    } else {
      val w661 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w662 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w663 = { ...w662, inc: w662.inc.set(iid, { ...w662.inc.get(iid), timers: w662.inc.get(iid).timers.set("resolution", { ...w662.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w664 = { ...w663, inc: w663.inc.set(iid, { ...w663.inc.get(iid), timers: w663.inc.get(iid).timers.set("resolution", { ...w663.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w664
    } else w0
      w661
    }
    w658
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w665 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w666 = if (timerDef("hold").startsOnce) {
      val w667 = ec_resumeTimer(w0, c, iid, "hold")
      w667
    } else {
      val w668 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w669 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w670 = { ...w669, inc: w669.inc.set(iid, { ...w669.inc.get(iid), timers: w669.inc.get(iid).timers.set("hold", { ...w669.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w671 = { ...w670, inc: w670.inc.set(iid, { ...w670.inc.get(iid), timers: w670.inc.get(iid).timers.set("hold", { ...w670.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w671
    } else {
      val sec_672 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w673 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_672 < 0)) 0 else (c.now + (sec_672 * 1000))) }) }) }
      val w674 = { ...w673, inc: w673.inc.set(iid, { ...w673.inc.get(iid), timers: w673.inc.get(iid).timers.set("hold", { ...w673.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w675 = { ...w674, inc: w674.inc.set(iid, { ...w674.inc.get(iid), timers: w674.inc.get(iid).timers.set("hold", { ...w674.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w676 = { ...w675, inc: w675.inc.set(iid, { ...w675.inc.get(iid), timers: w675.inc.get(iid).timers.set("hold", { ...w675.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w676
    }
      w668
    }
      w666
    }
    w665
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_677 = settings.alerts.target
    val w678 = if (((whom_677 != "") and (whom_677 != c.actor))) w0 else w0
    w678
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
    ["break", "no_link"].foldl(false, (acc, y679) => acc or y679 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_680 = ""
    val w681 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_680 }) }
    w681
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w682 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w682
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w683 = if (timerDef("hold").startsOnce) {
      val w684 = ec_pauseTimer(w0, c, iid, "hold")
      w684
    } else {
      val w685 = if (false) {
      val w686 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w687 = { ...w686, inc: w686.inc.set(iid, { ...w686.inc.get(iid), timers: w686.inc.get(iid).timers.set("hold", { ...w686.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w688 = { ...w687, inc: w687.inc.set(iid, { ...w687.inc.get(iid), timers: w687.inc.get(iid).timers.set("hold", { ...w687.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w689 = { ...w688, inc: w688.inc.set(iid, { ...w688.inc.get(iid), timers: w688.inc.get(iid).timers.set("hold", { ...w688.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w689
    } else {
      val w690 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_691 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w692 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_691) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w693 = { ...w692, inc: w692.inc.set(iid, { ...w692.inc.get(iid), timers: w692.inc.get(iid).timers.set("hold", { ...w692.inc.get(iid).timers.get("hold"), paused: keep_691 }) }) }
      val w694 = { ...w693, inc: w693.inc.set(iid, { ...w693.inc.get(iid), timers: w693.inc.get(iid).timers.set("hold", { ...w693.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w695 = { ...w694, inc: w694.inc.set(iid, { ...w694.inc.get(iid), timers: w694.inc.get(iid).timers.set("hold", { ...w694.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w695
    }
      w690
    }
      w685
    }
    w683
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w696 = if (not(timerDef("resolution").pausable)) {
      val w697 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w698 = { ...w697, inc: w697.inc.set(iid, { ...w697.inc.get(iid), timers: w697.inc.get(iid).timers.set("resolution", { ...w697.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w698
    } else {
      val w699 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w700 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w701 = { ...w700, inc: w700.inc.set(iid, { ...w700.inc.get(iid), timers: w700.inc.get(iid).timers.set("resolution", { ...w700.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w702 = { ...w701, inc: w701.inc.set(iid, { ...w701.inc.get(iid), timers: w701.inc.get(iid).timers.set("resolution", { ...w701.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w702
    } else w0
      w699
    }
    w696
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w703 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w704 = if (timerDef("reaction").startsOnce) {
      val w705 = ec_resumeTimer(w0, c, iid, "reaction")
      w705
    } else {
      val w706 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w707 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w708 = { ...w707, inc: w707.inc.set(iid, { ...w707.inc.get(iid), timers: w707.inc.get(iid).timers.set("reaction", { ...w707.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w709 = { ...w708, inc: w708.inc.set(iid, { ...w708.inc.get(iid), timers: w708.inc.get(iid).timers.set("reaction", { ...w708.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w709
    } else {
      val sec_710 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w711 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_710 < 0)) 0 else (c.now + (sec_710 * 1000))) }) }) }
      val w712 = { ...w711, inc: w711.inc.set(iid, { ...w711.inc.get(iid), timers: w711.inc.get(iid).timers.set("reaction", { ...w711.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w713 = { ...w712, inc: w712.inc.set(iid, { ...w712.inc.get(iid), timers: w712.inc.get(iid).timers.set("reaction", { ...w712.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w714 = { ...w713, inc: w713.inc.set(iid, { ...w713.inc.get(iid), timers: w713.inc.get(iid).timers.set("reaction", { ...w713.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w714
    }
      w706
    }
      w704
    }
    w703
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
    { val t_715 = world.inc.get(iid).timers.get("hold")  (((t_715.due != 0) and (t_715.due <= c.now)) and (t_715.fired != t_715.due)) },
    ["no_link"].foldl(false, (acc, y716) => acc or y716 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_717 = ""
    val w718 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_717 }) }
    w718
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w719 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w719
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w720 = if (timerDef("hold").startsOnce) {
      val w721 = ec_pauseTimer(w0, c, iid, "hold")
      w721
    } else {
      val w722 = if (false) {
      val w723 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w724 = { ...w723, inc: w723.inc.set(iid, { ...w723.inc.get(iid), timers: w723.inc.get(iid).timers.set("hold", { ...w723.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w725 = { ...w724, inc: w724.inc.set(iid, { ...w724.inc.get(iid), timers: w724.inc.get(iid).timers.set("hold", { ...w724.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w726 = { ...w725, inc: w725.inc.set(iid, { ...w725.inc.get(iid), timers: w725.inc.get(iid).timers.set("hold", { ...w725.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w726
    } else {
      val w727 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_728 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w729 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_728) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w730 = { ...w729, inc: w729.inc.set(iid, { ...w729.inc.get(iid), timers: w729.inc.get(iid).timers.set("hold", { ...w729.inc.get(iid).timers.get("hold"), paused: keep_728 }) }) }
      val w731 = { ...w730, inc: w730.inc.set(iid, { ...w730.inc.get(iid), timers: w730.inc.get(iid).timers.set("hold", { ...w730.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w732 = { ...w731, inc: w731.inc.set(iid, { ...w731.inc.get(iid), timers: w731.inc.get(iid).timers.set("hold", { ...w731.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w732
    }
      w727
    }
      w722
    }
    w720
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w733 = if (not(timerDef("resolution").pausable)) {
      val w734 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w735 = { ...w734, inc: w734.inc.set(iid, { ...w734.inc.get(iid), timers: w734.inc.get(iid).timers.set("resolution", { ...w734.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w735
    } else {
      val w736 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w737 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w738 = { ...w737, inc: w737.inc.set(iid, { ...w737.inc.get(iid), timers: w737.inc.get(iid).timers.set("resolution", { ...w737.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w739 = { ...w738, inc: w738.inc.set(iid, { ...w738.inc.get(iid), timers: w738.inc.get(iid).timers.set("resolution", { ...w738.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w739
    } else w0
      w736
    }
    w733
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w740 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w741 = if (timerDef("reaction").startsOnce) {
      val w742 = ec_resumeTimer(w0, c, iid, "reaction")
      w742
    } else {
      val w743 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w744 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w745 = { ...w744, inc: w744.inc.set(iid, { ...w744.inc.get(iid), timers: w744.inc.get(iid).timers.set("reaction", { ...w744.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w746 = { ...w745, inc: w745.inc.set(iid, { ...w745.inc.get(iid), timers: w745.inc.get(iid).timers.set("reaction", { ...w745.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w746
    } else {
      val sec_747 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w748 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_747 < 0)) 0 else (c.now + (sec_747 * 1000))) }) }) }
      val w749 = { ...w748, inc: w748.inc.set(iid, { ...w748.inc.get(iid), timers: w748.inc.get(iid).timers.set("reaction", { ...w748.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w750 = { ...w749, inc: w749.inc.set(iid, { ...w749.inc.get(iid), timers: w749.inc.get(iid).timers.set("reaction", { ...w749.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w751 = { ...w750, inc: w750.inc.set(iid, { ...w750.inc.get(iid), timers: w750.inc.get(iid).timers.set("reaction", { ...w750.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w751
    }
      w743
    }
      w741
    }
    w740
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
    val group_752 = dutyGroupOf(w0.inc.get(iid).owner)
    val w753 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_752 }) }
    w753
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_754 = ""
    val w755 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_754 }) }
    w755
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_756 = addressee(w0.inc.get(iid))
    val w757 = if (((whom_756 != "") and (whom_756 != c.actor))) w0 else w0
    w757
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
    val who_758 = ""
    val w759 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_758 }) }
    w759
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
    val who_760 = ""
    val w761 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_760 }) }
    w761
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w762 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w762
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w763 = if (timerDef("hold").startsOnce) {
      val w764 = ec_pauseTimer(w0, c, iid, "hold")
      w764
    } else {
      val w765 = if (false) {
      val w766 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w767 = { ...w766, inc: w766.inc.set(iid, { ...w766.inc.get(iid), timers: w766.inc.get(iid).timers.set("hold", { ...w766.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w768 = { ...w767, inc: w767.inc.set(iid, { ...w767.inc.get(iid), timers: w767.inc.get(iid).timers.set("hold", { ...w767.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w769 = { ...w768, inc: w768.inc.set(iid, { ...w768.inc.get(iid), timers: w768.inc.get(iid).timers.set("hold", { ...w768.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w769
    } else {
      val w770 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_771 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w772 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_771) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w773 = { ...w772, inc: w772.inc.set(iid, { ...w772.inc.get(iid), timers: w772.inc.get(iid).timers.set("hold", { ...w772.inc.get(iid).timers.get("hold"), paused: keep_771 }) }) }
      val w774 = { ...w773, inc: w773.inc.set(iid, { ...w773.inc.get(iid), timers: w773.inc.get(iid).timers.set("hold", { ...w773.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w775 = { ...w774, inc: w774.inc.set(iid, { ...w774.inc.get(iid), timers: w774.inc.get(iid).timers.set("hold", { ...w774.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w775
    }
      w770
    }
      w765
    }
    w763
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w776 = if (not(timerDef("resolution").pausable)) {
      val w777 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w778 = { ...w777, inc: w777.inc.set(iid, { ...w777.inc.get(iid), timers: w777.inc.get(iid).timers.set("resolution", { ...w777.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w778
    } else {
      val w779 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w780 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w781 = { ...w780, inc: w780.inc.set(iid, { ...w780.inc.get(iid), timers: w780.inc.get(iid).timers.set("resolution", { ...w780.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w782 = { ...w781, inc: w781.inc.set(iid, { ...w781.inc.get(iid), timers: w781.inc.get(iid).timers.set("resolution", { ...w781.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w782
    } else w0
      w779
    }
    w776
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w783 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w784 = if (timerDef("reaction").startsOnce) {
      val w785 = ec_resumeTimer(w0, c, iid, "reaction")
      w785
    } else {
      val w786 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w787 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w788 = { ...w787, inc: w787.inc.set(iid, { ...w787.inc.get(iid), timers: w787.inc.get(iid).timers.set("reaction", { ...w787.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w789 = { ...w788, inc: w788.inc.set(iid, { ...w788.inc.get(iid), timers: w788.inc.get(iid).timers.set("reaction", { ...w788.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w789
    } else {
      val sec_790 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w791 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_790 < 0)) 0 else (c.now + (sec_790 * 1000))) }) }) }
      val w792 = { ...w791, inc: w791.inc.set(iid, { ...w791.inc.get(iid), timers: w791.inc.get(iid).timers.set("reaction", { ...w791.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w793 = { ...w792, inc: w792.inc.set(iid, { ...w792.inc.get(iid), timers: w792.inc.get(iid).timers.set("reaction", { ...w792.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w794 = { ...w793, inc: w793.inc.set(iid, { ...w793.inc.get(iid), timers: w793.inc.get(iid).timers.set("reaction", { ...w793.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w794
    }
      w786
    }
      w784
    }
    w783
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
    val who_795 = ""
    val w796 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_795 }) }
    w796
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_797 = ""
    val w798 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_797 }) }
    w798
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w799 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w799
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w800 = if (timerDef("hold").startsOnce) {
      val w801 = ec_pauseTimer(w0, c, iid, "hold")
      w801
    } else {
      val w802 = if (false) {
      val w803 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w804 = { ...w803, inc: w803.inc.set(iid, { ...w803.inc.get(iid), timers: w803.inc.get(iid).timers.set("hold", { ...w803.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w805 = { ...w804, inc: w804.inc.set(iid, { ...w804.inc.get(iid), timers: w804.inc.get(iid).timers.set("hold", { ...w804.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w806 = { ...w805, inc: w805.inc.set(iid, { ...w805.inc.get(iid), timers: w805.inc.get(iid).timers.set("hold", { ...w805.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w806
    } else {
      val w807 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_808 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w809 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_808) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w810 = { ...w809, inc: w809.inc.set(iid, { ...w809.inc.get(iid), timers: w809.inc.get(iid).timers.set("hold", { ...w809.inc.get(iid).timers.get("hold"), paused: keep_808 }) }) }
      val w811 = { ...w810, inc: w810.inc.set(iid, { ...w810.inc.get(iid), timers: w810.inc.get(iid).timers.set("hold", { ...w810.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w812 = { ...w811, inc: w811.inc.set(iid, { ...w811.inc.get(iid), timers: w811.inc.get(iid).timers.set("hold", { ...w811.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w812
    }
      w807
    }
      w802
    }
    w800
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w813 = if (not(timerDef("resolution").pausable)) {
      val w814 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w815 = { ...w814, inc: w814.inc.set(iid, { ...w814.inc.get(iid), timers: w814.inc.get(iid).timers.set("resolution", { ...w814.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w815
    } else {
      val w816 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w817 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w818 = { ...w817, inc: w817.inc.set(iid, { ...w817.inc.get(iid), timers: w817.inc.get(iid).timers.set("resolution", { ...w817.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w819 = { ...w818, inc: w818.inc.set(iid, { ...w818.inc.get(iid), timers: w818.inc.get(iid).timers.set("resolution", { ...w818.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w819
    } else w0
      w816
    }
    w813
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w820 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w821 = if (timerDef("reaction").startsOnce) {
      val w822 = ec_resumeTimer(w0, c, iid, "reaction")
      w822
    } else {
      val w823 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w824 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w825 = { ...w824, inc: w824.inc.set(iid, { ...w824.inc.get(iid), timers: w824.inc.get(iid).timers.set("reaction", { ...w824.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w826 = { ...w825, inc: w825.inc.set(iid, { ...w825.inc.get(iid), timers: w825.inc.get(iid).timers.set("reaction", { ...w825.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w826
    } else {
      val sec_827 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w828 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_827 < 0)) 0 else (c.now + (sec_827 * 1000))) }) }) }
      val w829 = { ...w828, inc: w828.inc.set(iid, { ...w828.inc.get(iid), timers: w828.inc.get(iid).timers.set("reaction", { ...w828.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w830 = { ...w829, inc: w829.inc.set(iid, { ...w829.inc.get(iid), timers: w829.inc.get(iid).timers.set("reaction", { ...w829.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w831 = { ...w830, inc: w830.inc.set(iid, { ...w830.inc.get(iid), timers: w830.inc.get(iid).timers.set("reaction", { ...w830.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w831
    }
      w823
    }
      w821
    }
    w820
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_832 = settings.alerts.target
    val w833 = if (((whom_832 != "") and (whom_832 != c.actor))) w0 else w0
    w833
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
    val who_834 = ""
    val w835 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_834 }) }
    w835
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_836 = ""
    val w837 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_836 }) }
    w837
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w838 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w839 = if (timerDef("reaction").startsOnce) {
      val w840 = ec_resumeTimer(w0, c, iid, "reaction")
      w840
    } else {
      val w841 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w842 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w843 = { ...w842, inc: w842.inc.set(iid, { ...w842.inc.get(iid), timers: w842.inc.get(iid).timers.set("reaction", { ...w842.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w844 = { ...w843, inc: w843.inc.set(iid, { ...w843.inc.get(iid), timers: w843.inc.get(iid).timers.set("reaction", { ...w843.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w844
    } else {
      val sec_845 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w846 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_845 < 0)) 0 else (c.now + (sec_845 * 1000))) }) }) }
      val w847 = { ...w846, inc: w846.inc.set(iid, { ...w846.inc.get(iid), timers: w846.inc.get(iid).timers.set("reaction", { ...w846.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w848 = { ...w847, inc: w847.inc.set(iid, { ...w847.inc.get(iid), timers: w847.inc.get(iid).timers.set("reaction", { ...w847.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w849 = { ...w848, inc: w848.inc.set(iid, { ...w848.inc.get(iid), timers: w848.inc.get(iid).timers.set("reaction", { ...w848.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w849
    }
      w841
    }
      w839
    }
    w838
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_850 = settings.alerts.target
    val w851 = if (((whom_850 != "") and (whom_850 != c.actor))) w0 else w0
    w851
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
    not(settings.session.states.foldl(false, (acc, s_852) => acc or ((s_852.id == agentState(c.me)) and s_852.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_853 = incidentById(incs(world), c.form.primaryId)  ((((ps_853.length() > 0) and (ps_853[0].id != world.inc.get(iid).id)) and (ps_853[0].linkedTo == "")) and ((ps_853[0].state == "new") or ((ps_853[0].state == "in_progress") and (ps_853[0].owner == c.me)))) },
    { val ps_854 = incidentById(incs(world), c.form.primaryId)  ((ps_854.length() > 0) and (ps_854[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w855 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w855
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_856 = incidentById(incs(w0), c.form.primaryId)
    val w857 = if ((ps_856.length() > 0)) {
      val w858 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_865 => not(isDone(e_865))).foldl([], (acc, x861) => acc.append(x861.id)).foldl(w0, (wf859, cId860) => {
      val w862 = { ...wf859, inc: wf859.inc.set(cId860, { ...wf859.inc.get(cId860), leftGroup: { primaryId: wf859.inc.get(cId860).linkedTo, linkedAt: wf859.inc.get(cId860).linkedAt, at: c.now } }) }
      val w863 = { ...w862, inc: w862.inc.set(cId860, { ...w862.inc.get(cId860), linkedTo: ps_856[0].id }) }
      val w864 = { ...w863, inc: w863.inc.set(cId860, { ...w863.inc.get(cId860), linkedAt: c.now }) }
      w864
    })
      w858
    } else w0
    w857
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_866 = c.form.primaryId
    val w867 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_866 }) }
    val w868 = { ...w867, inc: w867.inc.set(iid, { ...w867.inc.get(iid), linkedAt: c.now }) }
    w868
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_869 = ""
    val w870 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_869 }) }
    w870
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_871 = ""
    val w872 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_871 }) }
    w872
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w873 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w873
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w874 = if (timerDef("reaction").startsOnce) {
      val w875 = ec_pauseTimer(w0, c, iid, "reaction")
      w875
    } else {
      val w876 = if (false) {
      val w877 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w878 = { ...w877, inc: w877.inc.set(iid, { ...w877.inc.get(iid), timers: w877.inc.get(iid).timers.set("reaction", { ...w877.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w879 = { ...w878, inc: w878.inc.set(iid, { ...w878.inc.get(iid), timers: w878.inc.get(iid).timers.set("reaction", { ...w878.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w880 = { ...w879, inc: w879.inc.set(iid, { ...w879.inc.get(iid), timers: w879.inc.get(iid).timers.set("reaction", { ...w879.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w880
    } else {
      val w881 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_882 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w883 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_882) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w884 = { ...w883, inc: w883.inc.set(iid, { ...w883.inc.get(iid), timers: w883.inc.get(iid).timers.set("reaction", { ...w883.inc.get(iid).timers.get("reaction"), paused: keep_882 }) }) }
      val w885 = { ...w884, inc: w884.inc.set(iid, { ...w884.inc.get(iid), timers: w884.inc.get(iid).timers.set("reaction", { ...w884.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w886 = { ...w885, inc: w885.inc.set(iid, { ...w885.inc.get(iid), timers: w885.inc.get(iid).timers.set("reaction", { ...w885.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w886
    }
      w881
    }
      w876
    }
    w874
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w887 = if (not(timerDef("resolution").pausable)) {
      val w888 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w889 = { ...w888, inc: w888.inc.set(iid, { ...w888.inc.get(iid), timers: w888.inc.get(iid).timers.set("resolution", { ...w888.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w889
    } else {
      val w890 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w891 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w892 = { ...w891, inc: w891.inc.set(iid, { ...w891.inc.get(iid), timers: w891.inc.get(iid).timers.set("resolution", { ...w891.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w893 = { ...w892, inc: w892.inc.set(iid, { ...w892.inc.get(iid), timers: w892.inc.get(iid).timers.set("resolution", { ...w892.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w893
    } else w0
      w890
    }
    w887
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_894 = incidentById(incs(w0), c.form.primaryId)
    val w895 = if (((((ps_894.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_894[0], "resolution", c.now)))) {
      val t_896 = ps_894[0].timers.get("resolution")
      val left_897 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_898 = (if ((t_896.due != 0)) (t_896.due - c.now) else (if (t_896.paused) t_896.left else (timerSec(ps_894[0], "resolution", "") * 1000)))
      val w899 = if ((left_897 < was_898)) {
      val w900 = ps_894.foldl([], (acc, x903) => acc.append(x903.id)).foldl(w0, (wf901, pId902) => {
      val w904 = if ((t_896.due != 0)) {
      val w905 = { ...wf901, inc: wf901.inc.set(pId902, { ...wf901.inc.get(pId902), timers: wf901.inc.get(pId902).timers.set("resolution", { ...wf901.inc.get(pId902).timers.get("resolution"), due: (c.now + left_897) }) }) }
      w905
    } else {
      val w906 = { ...wf901, inc: wf901.inc.set(pId902, { ...wf901.inc.get(pId902), timers: wf901.inc.get(pId902).timers.set("resolution", { ...wf901.inc.get(pId902).timers.get("resolution"), left: left_897 }) }) }
      val w907 = { ...w906, inc: w906.inc.set(pId902, { ...w906.inc.get(pId902), timers: w906.inc.get(pId902).timers.set("resolution", { ...w906.inc.get(pId902).timers.get("resolution"), paused: true }) }) }
      w907
    }
      w904
    })
      w900
    } else w0
      w899
    } else w0
    w895
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w908 = if (timerDef("hold").startsOnce) {
      val w909 = ec_pauseTimer(w0, c, iid, "hold")
      w909
    } else {
      val w910 = if (false) {
      val w911 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w912 = { ...w911, inc: w911.inc.set(iid, { ...w911.inc.get(iid), timers: w911.inc.get(iid).timers.set("hold", { ...w911.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w913 = { ...w912, inc: w912.inc.set(iid, { ...w912.inc.get(iid), timers: w912.inc.get(iid).timers.set("hold", { ...w912.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w914 = { ...w913, inc: w913.inc.set(iid, { ...w913.inc.get(iid), timers: w913.inc.get(iid).timers.set("hold", { ...w913.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w914
    } else {
      val w915 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_916 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w917 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_916) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w918 = { ...w917, inc: w917.inc.set(iid, { ...w917.inc.get(iid), timers: w917.inc.get(iid).timers.set("hold", { ...w917.inc.get(iid).timers.get("hold"), paused: keep_916 }) }) }
      val w919 = { ...w918, inc: w918.inc.set(iid, { ...w918.inc.get(iid), timers: w918.inc.get(iid).timers.set("hold", { ...w918.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w920 = { ...w919, inc: w919.inc.set(iid, { ...w919.inc.get(iid), timers: w919.inc.get(iid).timers.set("hold", { ...w919.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w920
    }
      w915
    }
      w910
    }
    w908
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
    not(settings.session.states.foldl(false, (acc, s_921) => acc or ((s_921.id == agentState(c.me)) and s_921.readOnly))),
    { val ps_922 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_922.length() > 0) and ((ownership(c.me, ps_922[0]) == "owner") or unowned(ps_922[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_923 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w924 = if (((ps_923.length() > 0) and (leftOf(ps_923[0], "resolution", c.now) >= 0))) {
      val w925 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w926 = { ...w925, inc: w925.inc.set(iid, { ...w925.inc.get(iid), timers: w925.inc.get(iid).timers.set("resolution", { ...w925.inc.get(iid).timers.get("resolution"), left: leftOf(ps_923[0], "resolution", c.now) }) }) }
      val w927 = { ...w926, inc: w926.inc.set(iid, { ...w926.inc.get(iid), timers: w926.inc.get(iid).timers.set("resolution", { ...w926.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w928 = if ((leftOf(ps_923[0], "resolution", c.now) == 0)) {
      val w929 = { ...w927, inc: w927.inc.set(iid, { ...w927.inc.get(iid), timers: w927.inc.get(iid).timers.set("resolution", { ...w927.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_923[0], "resolution", c.now)) ps_923[0].timers.get("resolution").fired else ps_923[0].timers.get("resolution").due) }) }) }
      w929
    } else w927
      w928
    } else w0
    w924
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w930 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_931 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w932 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w933 = { ...w932, inc: w932.inc.set(iid, { ...w932.inc.get(iid), linkedTo: "" }) }
      val w934 = { ...w933, inc: w933.inc.set(iid, { ...w933.inc.get(iid), linkedAt: 0 }) }
      val w935 = if (((ps_931.length() > 0) and ("" != ""))) w934 else w934
      val w936 = if (("" != "")) {
      val w937 = ps_931.foldl([], (acc, x940) => acc.append(x940.id)).foldl(w935, (wf938, pId939) => wf938)
      w937
    } else w935
      w936
    } else {
      val w941 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w942 = { ...w941, inc: w941.inc.set(iid, { ...w941.inc.get(iid), linkedAt: 0 }) }
      w942
    }
    w930
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w943 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w944 = if (timerDef("reaction").startsOnce) {
      val w945 = ec_resumeTimer(w0, c, iid, "reaction")
      w945
    } else {
      val w946 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w947 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w948 = { ...w947, inc: w947.inc.set(iid, { ...w947.inc.get(iid), timers: w947.inc.get(iid).timers.set("reaction", { ...w947.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w949 = { ...w948, inc: w948.inc.set(iid, { ...w948.inc.get(iid), timers: w948.inc.get(iid).timers.set("reaction", { ...w948.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w949
    } else {
      val sec_950 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w951 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_950 < 0)) 0 else (c.now + (sec_950 * 1000))) }) }) }
      val w952 = { ...w951, inc: w951.inc.set(iid, { ...w951.inc.get(iid), timers: w951.inc.get(iid).timers.set("reaction", { ...w951.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w953 = { ...w952, inc: w952.inc.set(iid, { ...w952.inc.get(iid), timers: w952.inc.get(iid).timers.set("reaction", { ...w952.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w954 = { ...w953, inc: w953.inc.set(iid, { ...w953.inc.get(iid), timers: w953.inc.get(iid).timers.set("reaction", { ...w953.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w954
    }
      w946
    }
      w944
    }
    w943
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
    { val ps_955 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_955.length() > 0) and isDone(ps_955[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_956 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w957 = if ((ps_956.length() > 0)) {
      val w958 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_956[0].closeResultId }) }
      val w959 = { ...w958, inc: w958.inc.set(iid, { ...w958.inc.get(iid), closeCauseId: ps_956[0].closeCauseId }) }
      val w960 = { ...w959, inc: w959.inc.set(iid, { ...w959.inc.get(iid), result: ps_956[0].result }) }
      val w961 = { ...w960, inc: w960.inc.set(iid, { ...w960.inc.get(iid), closedBy: ps_956[0].closedBy }) }
      val w962 = { ...w961, inc: w961.inc.set(iid, { ...w961.inc.get(iid), owner: ps_956[0].closedBy }) }
      w962
    } else w0
    w957
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w963 = if (not(timerDef("resolution").pausable)) {
      val w964 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w965 = { ...w964, inc: w964.inc.set(iid, { ...w964.inc.get(iid), timers: w964.inc.get(iid).timers.set("resolution", { ...w964.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w965
    } else {
      val w966 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w967 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w968 = { ...w967, inc: w967.inc.set(iid, { ...w967.inc.get(iid), timers: w967.inc.get(iid).timers.set("resolution", { ...w967.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w969 = { ...w968, inc: w968.inc.set(iid, { ...w968.inc.get(iid), timers: w968.inc.get(iid).timers.set("resolution", { ...w968.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w969
    } else w0
      w966
    }
    w963
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_970 = c.now
    val w971 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_970 }) }
    w971
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {
    val w972 = if (["false_alarm"].foldl(false, (acc, y973) => acc or y973 == w0.inc.get(iid).closeResultId)) {
      val w974 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_979 => not(isDone(x_979))).foldl([], (acc, x977) => acc.append(x977.id)).foldl(w0, (wf975, sId976) => {
      val w978 = if (((addressee(wf975.inc.get(sId976)) != "") and (addressee(wf975.inc.get(sId976)) != wf975.inc.get(iid).closedBy))) wf975 else wf975
      w978
    })
      w974
    } else w0
    w972
  }

  def e_close_linked_5(w0: World, c: Ctx, iid: str): World = {

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
    val w6 = e_close_linked_5(w5, c1, iid)
    w6
  }

  // linked_lost_access: system → new

  def ok_linked_lost_access(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    { val ps_980 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_981 = (if (((ps_980.length() > 0) and not(isDone(ps_980[0])))) addressee(ps_980[0]) else "")  ((who_981 != "") and (hasAccess(who_981, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_982 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w983 = if (((ps_982.length() > 0) and (leftOf(ps_982[0], "resolution", c.now) >= 0))) {
      val w984 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w985 = { ...w984, inc: w984.inc.set(iid, { ...w984.inc.get(iid), timers: w984.inc.get(iid).timers.set("resolution", { ...w984.inc.get(iid).timers.get("resolution"), left: leftOf(ps_982[0], "resolution", c.now) }) }) }
      val w986 = { ...w985, inc: w985.inc.set(iid, { ...w985.inc.get(iid), timers: w985.inc.get(iid).timers.set("resolution", { ...w985.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w987 = if ((leftOf(ps_982[0], "resolution", c.now) == 0)) {
      val w988 = { ...w986, inc: w986.inc.set(iid, { ...w986.inc.get(iid), timers: w986.inc.get(iid).timers.set("resolution", { ...w986.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_982[0], "resolution", c.now)) ps_982[0].timers.get("resolution").fired else ps_982[0].timers.get("resolution").due) }) }) }
      w988
    } else w986
      w987
    } else w0
    w983
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w989 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_990 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w991 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w992 = { ...w991, inc: w991.inc.set(iid, { ...w991.inc.get(iid), linkedTo: "" }) }
      val w993 = { ...w992, inc: w992.inc.set(iid, { ...w992.inc.get(iid), linkedAt: 0 }) }
      val w994 = if (((ps_990.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w993 else w993
      val w995 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w996 = ps_990.foldl([], (acc, x999) => acc.append(x999.id)).foldl(w994, (wf997, pId998) => wf997)
      w996
    } else w994
      w995
    } else {
      val w1000 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1001 = { ...w1000, inc: w1000.inc.set(iid, { ...w1000.inc.get(iid), linkedAt: 0 }) }
      w1001
    }
    w989
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w1002 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1003 = if (timerDef("reaction").startsOnce) {
      val w1004 = ec_resumeTimer(w0, c, iid, "reaction")
      w1004
    } else {
      val w1005 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1006 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1007 = { ...w1006, inc: w1006.inc.set(iid, { ...w1006.inc.get(iid), timers: w1006.inc.get(iid).timers.set("reaction", { ...w1006.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1008 = { ...w1007, inc: w1007.inc.set(iid, { ...w1007.inc.get(iid), timers: w1007.inc.get(iid).timers.set("reaction", { ...w1007.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1008
    } else {
      val sec_1009 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w1010 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1009 < 0)) 0 else (c.now + (sec_1009 * 1000))) }) }) }
      val w1011 = { ...w1010, inc: w1010.inc.set(iid, { ...w1010.inc.get(iid), timers: w1010.inc.get(iid).timers.set("reaction", { ...w1010.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1012 = { ...w1011, inc: w1011.inc.set(iid, { ...w1011.inc.get(iid), timers: w1011.inc.get(iid).timers.set("reaction", { ...w1011.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1013 = { ...w1012, inc: w1012.inc.set(iid, { ...w1012.inc.get(iid), timers: w1012.inc.get(iid).timers.set("reaction", { ...w1012.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1013
    }
      w1005
    }
      w1003
    }
    w1002
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_1014 = settings.alerts.target
    val w1015 = if (((whom_1014 != "") and (whom_1014 != c.actor))) w0 else w0
    w1015
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
      settings.holdReasons.foldl(false, (acc, r_1016) => acc or ((r_1016.id == c.form.reasonId) and (r_1016.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_1017) => acc and (isDone(e_1017) or hasAccess(c.form.targetId, e_1017))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_1018) => acc or (i_1018.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_1019) => acc or ((i_1019.id == c.form.resultId) and stepsOk(i_1019, world.inc.get(iid)))),
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
    ["in_progress"].foldl(false, (acc, y1020) => acc or y1020 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_1021) => acc or ((s_1021.id == agentState(c.me)) and s_1021.readOnly))),
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
