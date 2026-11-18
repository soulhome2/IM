// -*- mode: Bluespec; -*-
// Собрано скриптом tools/gen_quint.mjs из Specification/Workflow_machine/workflow_schema.v1.json (с настройками поста post-defaults.json) и частей quint/src/.
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
  // (tools/check_quint_replay.mjs). others — набор объединения, prio, scenario, event и ruleGroup (дежурная группа правила, §8.1) — у появления
  type Action = { name: str, actor: str, incident: str, kind: str, form: Form, surface: str, others: List[str], prio: int, scenario: str, event: str, ruleGroup: str }

  /* ===== Типы машины (cel.types) ===== */


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, closeCauseLabel: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], priorityManual: bool, maintenanceWindowId: str, closeMaintenanceWindowId: str, timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str, eventGuid: str, ruleDutyGroup: str, acceptedAt: int, acceptedBy: str, noReaction: bool, lastAssignedGroup: str, acceptedGroup: str }

  type Timer = { due: int, paused: bool, left: int, fired: int, since: int }

  type Breach = { kind: str, at: int, owner: str }

  type LeftGroup = { primaryId: str, linkedAt: int, at: int }

  type Form = { targetId: str, primaryId: str, resultId: str, reasonId: str, causeId: str, comment: str, files: List[FormFile], priority: str, maintenanceWindowId: str }

  type FormFile = { id: str, fileName: str, mime: str, size: int }

  type Limits = { maxActive: int, maxOnHold: int, maxBulk: int, reopenWindowMin: int, reopenResolutionSec: int, commentMaxLength: int, commentMaxFiles: int, attachmentMaxBytes: int, attachmentTypes: List[str] }

  type SessionState = { id: str, readOnly: bool, readOnlyReasonKey: str }

  type BreakReason = { id: str, labelKey: str, maxMinutes: List[int] }

  type Session = { states: List[SessionState], breakReasons: List[BreakReason], heartbeatSec: int, idleHoldSec: int, idleReleaseSec: int }

  type Shift = { starts: List[str], timeZone: str, refreshSec: int }

  type Escalation = { enabled: bool, levels: List[Level], maxLevel: int, onResolutionOverdue: str }

  type Level = { level: int, targetKind: str, target: str, reactionSec: int }

  type Alerts = { targetKind: str, target: str, noRecipientLog: str }

  type State = { id: str, category: str }

  type CloseResultItem = { id: str, labelKey: str, permission: str, fromStates: List[str], ownerOnlyInStates: List[str], surfaces: List[str], requiredStepSet: str, commentRequired: bool, finish: bool, causeCatalog: str }

  type CauseItem = { id: str, labelKey: str, commentRequired: bool }

  type CauseCatalog = { items: List[CauseItem] }

  type ScopeRule = { own: ScopeOwn }

  type ScopeOwn = { anyOf: List[ScopeCond] }

  type ScopeCond = { state: str, ownership: str }

  type TimerDef = { id: str, labelKey: str, defaultSec: int, byPriority: int -> int, overridesBy: List[str], overrides: List[Override], keepsLeft: bool, startsOnce: bool, pausable: bool, secFrom: str }

  type Override = { eventType: List[str], priority: List[int], sourceGroup: List[str], scenario: List[str], sec: int }

  type HoldReason = { id: str, maxMinutes: List[int], setBy: str, deadlineFromIdle: bool }

  type Event = { guid: str, eventType: str, device: str, deviceType: str, at: int }

  type Maintenance = { mode: str, modes: List[str], markPriority: str, startSkewSec: int }

  type MaintenanceWindow = { id: str, device: List[str], group: List[str], from: int, to: int }

  type Condition = { eventType: List[str], device: List[str], deviceType: List[str], group: List[str] }

  type Rule = { guid: str, active: bool, priority: int, createdAt: int, scenarios: List[str], conditions: List[Condition] }

  type Settings = { limits: Limits, session: Session, escalation: Escalation, alerts: Alerts, states: List[State], closeResults: List[CloseResultItem], timerDefs: List[TimerDef], holdReasons: List[HoldReason], causeCatalogs: str -> CauseCatalog, maintenance: Maintenance, shift: Shift }


  /* ===== Настройки — значения машины (cel.settings) ===== */


  pure val MACHINE_SETTINGS: Settings = {
    limits: { maxActive: 0, maxOnHold: 5, maxBulk: 0, reopenWindowMin: 1440, reopenResolutionSec: 0, commentMaxLength: 2000, commentMaxFiles: 5, attachmentMaxBytes: 10485760, attachmentTypes: ["image/jpeg", "image/png", "application/pdf"] },
    session: { states: [{ id: "ready", readOnly: false, readOnlyReasonKey: "" }, { id: "busy", readOnly: false, readOnlyReasonKey: "" }, { id: "not_ready", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.not_ready" }, { id: "offline", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.offline" }], breakReasons: [{ id: "lunch", labelKey: "workflow.session.break.lunch", maxMinutes: [60] }, { id: "briefing", labelKey: "workflow.session.break.briefing", maxMinutes: [30] }, { id: "patrol", labelKey: "workflow.session.break.patrol", maxMinutes: [20] }], heartbeatSec: 30, idleHoldSec: 300, idleReleaseSec: 1200 },
    escalation: { enabled: true, levels: [{ level: 1, targetKind: "user", target: "petrova", reactionSec: 120 }, { level: 2, targetKind: "user", target: "noc", reactionSec: 90 }], maxLevel: 2, onResolutionOverdue: "alert" },
    alerts: { targetKind: "group", target: "grp-leads", noRecipientLog: "workflow.journal.alert_no_recipient" },
    states: [{ id: "new", category: "pending" }, { id: "pending_acceptance", category: "pending" }, { id: "in_progress", category: "active" }, { id: "on_hold", category: "active" }, { id: "closed", category: "done" }, { id: "linked", category: "linked" }],
    closeResults: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "closing", commentRequired: false, finish: true, causeCatalog: "" }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: false, finish: false, causeCatalog: "false_alarm_cause" }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false, causeCatalog: "" }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false, causeCatalog: "" }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false, causeCatalog: "" }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", permission: "incident:close:unprocessed", fromStates: ["new", "pending_acceptance", "in_progress", "on_hold"], ownerOnlyInStates: ["in_progress", "on_hold"], surfaces: ["queue", "card"], requiredStepSet: "none", commentRequired: true, finish: false, causeCatalog: "mass_fault" }],
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overridesBy: ["eventType", "priority", "sourceGroup", "scenario"], overrides: [{ eventType: [], priority: [100], sourceGroup: [], scenario: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], scenario: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], scenario: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], scenario: [], sec: 1800 }], keepsLeft: true, startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overridesBy: ["eventType", "priority", "sourceGroup", "scenario"], overrides: [], keepsLeft: false, startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overridesBy: [], overrides: [], keepsLeft: false, startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
    holdReasons: [{ id: "break", maxMinutes: [30], setBy: "system", deadlineFromIdle: false }, { id: "no_link", maxMinutes: [], setBy: "system", deadlineFromIdle: true }, { id: "third_party", maxMinutes: [30], setBy: "operator", deadlineFromIdle: false }, { id: "patrol", maxMinutes: [45], setBy: "operator", deadlineFromIdle: false }, { id: "no_data", maxMinutes: [60], setBy: "operator", deadlineFromIdle: false }],
    causeCatalogs: Map("hold" -> { items: [{ id: "break", labelKey: "workflow.catalog.hold.break", commentRequired: false }, { id: "no_link", labelKey: "workflow.catalog.hold.no_link", commentRequired: false }, { id: "third_party", labelKey: "workflow.catalog.hold.third_party", commentRequired: false }, { id: "patrol", labelKey: "workflow.catalog.hold.patrol", commentRequired: false }, { id: "no_data", labelKey: "workflow.catalog.hold.no_data", commentRequired: false }] }, "close_result" -> { items: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", commentRequired: false }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", commentRequired: false }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", commentRequired: true }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", commentRequired: true }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", commentRequired: true }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", commentRequired: true }] }, "mass_fault" -> { items: [{ id: "power", labelKey: "workflow.catalog.mass_fault.power", commentRequired: false }, { id: "link", labelKey: "workflow.catalog.mass_fault.link", commentRequired: false }, { id: "mass_fault", labelKey: "workflow.catalog.mass_fault.mass_fault", commentRequired: false }, { id: "known", labelKey: "workflow.catalog.mass_fault.known", commentRequired: false }] }, "false_alarm_cause" -> { items: [{ id: "animal", labelKey: "workflow.catalog.false_alarm_cause.animal", commentRequired: false }, { id: "weather", labelKey: "workflow.catalog.false_alarm_cause.weather", commentRequired: false }, { id: "equipment", labelKey: "workflow.catalog.false_alarm_cause.equipment", commentRequired: false }, { id: "staff", labelKey: "workflow.catalog.false_alarm_cause.staff", commentRequired: false }, { id: "setup", labelKey: "workflow.catalog.false_alarm_cause.setup", commentRequired: false }, { id: "other", labelKey: "workflow.catalog.false_alarm_cause.other", commentRequired: true }] }),
    maintenance: { mode: "suppress", modes: ["suppress", "mark"], markPriority: "lowest", startSkewSec: 300 },
    shift: { starts: ["08:00", "20:00"], timeZone: "Europe/Moscow", refreshSec: 30 },
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

  pure def intakeKeySame(x: Incident, y: Incident): bool = and {
    x.eventGuid == y.eventGuid,
    x.scenario == y.scenario,
  }

  pure val TYPICAL_PERMISSION_SETS: Set[Set[str]] = Set(Set("incident:claim", "incident:accept", "incident:hold", "incident:release", "incident:close", "incident:transfer:own", "incident:bulk", "incident:run_action", "incident:comment", "agent:set_not_ready"), Set("incident:claim", "incident:accept", "incident:hold", "incident:release", "incident:close", "incident:close:unprocessed", "incident:reopen", "incident:transfer:own", "incident:transfer:any", "incident:reassign", "incident:bulk", "incident:run_action", "incident:comment", "incident:priority", "agent:set_not_ready", "maintenance:edit"))

  pure val STEP_RESULT_IDS: Set[str] = Set("processed")

  pure val STEP_RESULT_CLOSE_IDS: Set[str] = Set("close")

  pure val EXIT_RULE: { appliesTo: Set[str], requiresAnyOf: Set[str], requiresAnyOfWithHoldLimit: Set[str], disables: Set[str] } = { appliesTo: Set("incident:claim", "incident:accept"), requiresAnyOf: Set("incident:hold", "incident:release", "incident:close"), requiresAnyOfWithHoldLimit: Set("incident:release", "incident:close"), disables: Set("incident:claim", "incident:accept") }

  pure val USED_PERMISSIONS: Set[str] = Set("agent:set_not_ready", "incident:accept", "incident:bulk", "incident:claim", "incident:close", "incident:close:unprocessed", "incident:comment", "incident:hold", "incident:priority", "incident:reassign", "incident:release", "incident:reopen", "incident:run_action", "incident:transfer:any", "incident:transfer:own")

  pure val TIMER_IDS: Set[str] = Set("reaction", "resolution", "hold")

  pure val NO_TIMER: Timer = { due: 0, paused: false, left: 0, fired: 0, since: 0 }

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", closeCauseLabel: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], priorityManual: false, maintenanceWindowId: "", closeMaintenanceWindowId: "", timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "", eventGuid: "", ruleDutyGroup: "", acceptedAt: 0, acceptedBy: "", noReaction: false, lastAssignedGroup: "", acceptedGroup: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

  pure val NO_FORM: Form = { targetId: "", primaryId: "", resultId: "", reasonId: "", causeId: "", comment: "", files: [], priority: "", maintenanceWindowId: "" }

  pure val CAUSE_FOR: str -> str = Map("false_alarm" -> "animal", "mass" -> "power")

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

  // §11.1, ARCH-15 (В8), RULE-140. Основной выборки для действия со scope: primaryScenario («Закрыть без обработки») — чей сценарий закрывается. Только среди отмеченных, которые этот оператор может закрыть из очереди (closeOptions и stepsOk — как у closeResultAllowed без выбранного результата; решения 2026-10-29): основной по §11.3 (mergePrimary) среди них, а если такого нет (только отложенные, ожидающие принятия, чужие) — самый срочный из них, у равных — появившийся раньше, у совсем равных — первый по порядку выборки (по возрастанию номера, как у mergePrimary). Одно правило для обеих веток: основной по §11.3, которого закрыть нельзя, основным выборки не становится. Списком из одного или пустым (выборка пуста или закрыть нечего — действие недоступно)

  def bulkPrimary(xs: List[Incident], who: str): List[Incident] =
    { val ok_16 = xs.select(e_17 => closeOptions(who, e_17, "queue").foldl(false, (acc, o_18) => acc or stepsOk(o_18, e_17)))  { val p_19 = mergePrimary(ok_16, who)  (if ((p_19.length() > 0)) p_19 else { val top_20 = ok_16.select(e_21 => ok_16.foldl(true, (acc, k_22) => acc and (k_22.priority <= e_21.priority)))  { val first_23 = top_20.select(e_24 => top_20.foldl(true, (acc, k_25) => acc and (e_24.occurredAt <= k_25.occurredAt)))  (if ((first_23.length() > 0)) [first_23[0]] else []) } }) } }

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

  // §8.1, М1. Адресация инцидента при появлении по дежурной группе правила-победителя (ruleDutyGroup): none — у правила нет группы (create), group — в группе кто-то вошёл в МИ, видит устройство-источник и может принять (canAcceptNow; create_to_group), queue — принять некому или группы уже нет (isGroup ложно: без этой проверки canAcceptNow принял бы id за человека; rule_group_cannot_accept). При пустой группе фактов мира не спрашивает (план 84)

  def ruleAddressing(x: Incident): str =
    (if ((x.ruleDutyGroup == "")) "none" else (if ((isGroup(x.ruleDutyGroup) and canAcceptNow(x.ruleDutyGroup, x, ""))) "group" else "queue"))

  // §8.3. Уровни автоэскалации выше текущего и не выше потолка, адресат которых может принять сейчас (canAcceptNow, RULE-100); уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)

  def nextLevels(x: Incident): List[Level] =
    settings.escalation.levels.select(l_40 => ((((l_40.level > x.escalationLevel) and (l_40.level <= settings.escalation.maxLevel)) and (l_40.target != addressee(x))) and canAcceptNow(l_40.target, x, x.owner)))

  // §2.2. Результаты закрытия, которые этот оператор может выбрать для инцидента

  def closeOptions(who: str, x: Incident, surface: str): List[CloseResultItem] =
    settings.closeResults.select(i_41 => (((can(who, i_41.permission) and i_41.fromStates.foldl(false, (acc, y42) => acc or y42 == x.state)) and not((i_41.ownerOnlyInStates.foldl(false, (acc, y43) => acc or y43 == x.state) and (x.owner != who)))) and (((surface == "") or (i_41.surfaces.length() == 0)) or i_41.surfaces.foldl(false, (acc, y44) => acc or y44 == surface))))

  // §2.2, ТЗ-4. Причина c есть в справочнике причин (causeCatalog) результата r; у результата без справочника — нет

  def causeOk(r: str, c: str): bool =
    settings.closeResults.foldl(false, (acc, i_45) => acc or ((((i_45.id == r) and (i_45.causeCatalog != "")) and settings.causeCatalogs.keys().contains(i_45.causeCatalog)) and settings.causeCatalogs.get(i_45.causeCatalog).items.foldl(false, (acc, x_46) => acc or (x_46.id == c))))

  // §2.2, ТЗ-4. Выбранная причина требует комментария («Другое» у ложной тревоги)

  def causeCommentRequired(r: str, c: str): bool =
    settings.closeResults.foldl(false, (acc, i_47) => acc or ((((i_47.id == r) and (i_47.causeCatalog != "")) and settings.causeCatalogs.keys().contains(i_47.causeCatalog)) and settings.causeCatalogs.get(i_47.causeCatalog).items.foldl(false, (acc, x_48) => acc or ((x_48.id == c) and x_48.commentRequired))))

  // §2.2, ТЗ-4. Снимок названия причины на момент закрытия — ключ подписи причины (closeCauseLabel). Сервер хранит текст названия; причину потом удалят из справочника — инцидент и журнал показывают снимок

  def causeLabel(r: str, c: str): str =
    { val rs_49 = settings.closeResults.select(i_50 => ((i_50.id == r) and settings.causeCatalogs.keys().contains(i_50.causeCatalog)))  (if ((rs_49.length() > 0)) { val xs_51 = settings.causeCatalogs.get(rs_49[0].causeCatalog).items.select(x_52 => (x_52.id == c))  (if ((xs_51.length() > 0)) xs_51[0].labelKey else "") } else "") }

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
    { val ls_53 = nextLevels(x)  ls_53.select(l_54 => ls_53.foldl(true, (acc, k_55) => acc and (l_54.level <= k_55.level))) }

  def levelUpTarget(x: Incident): str =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].target else "")

  def levelUpNumber(x: Incident): int =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].level else 0)

  def timerDef(id: str): TimerDef =
    settings.timerDefs.select(t_56 => (t_56.id == id))[0]

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
    (((((o.eventType.length() == 0) or t.overridesBy.foldl(false, (acc, y57) => acc or y57 == "eventType")) and ((o.priority.length() == 0) or t.overridesBy.foldl(false, (acc, y58) => acc or y58 == "priority"))) and ((o.sourceGroup.length() == 0) or t.overridesBy.foldl(false, (acc, y59) => acc or y59 == "sourceGroup"))) and ((o.scenario.length() == 0) or t.overridesBy.foldl(false, (acc, y60) => acc or y60 == "scenario")))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (больше условий; при равном числе — со сценарием; при равных и этом — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_61 = t.overrides.select(o_62 => (overrideAllowed(t, o_62) and overrideMatches(x, o_62)))  (if ((ms_61.length() > 0)) ms_61.select(o_63 => ms_61.foldl(true, (acc, k_64) => acc and (overrideRank(k_64) <= overrideRank(o_63))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold). У причины с deadlineFromIdle («Нет связи») — порог возврата в очередь минус порог удержания, не меньше 0: срок причины и возврат по молчанию совпадают при любых порогах (RULE-118, RULE-129, RULE-132). Причины нет — -1, срок не ставится. Срок у причины обязателен, кроме deadlineFromIdle (§4, правило 7; RULE-135, check_machine.py): ветка «maxMinutes пуст» — подстраховка

  def holdSec(x: Incident): int =
    { val rs_65 = settings.holdReasons.select(r_66 => (r_66.id == x.holdReasonId))  (if ((rs_65.length() == 0)) (0 - 1) else (if (rs_65[0].deadlineFromIdle) (if ((settings.session.idleReleaseSec > settings.session.idleHoldSec)) (settings.session.idleReleaseSec - settings.session.idleHoldSec) else 0) else (if ((rs_65[0].maxMinutes.length() > 0)) (rs_65[0].maxMinutes[0] * 60) else (0 - 1)))) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_67 = settings.escalation.levels.select(l_68 => (l_68.level == x.escalationLevel))  (if ((ls_67.length() > 0)) ls_67[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_69 = x.timers.get(id)  (if ((t_69.due != 0)) (if (((t_69.due - now) > 0)) (t_69.due - now) else 0) else (if (t_69.paused) t_69.left else (0 - 1))) }

  // RULE-50. Норматив нарушен и отработан: остатка нет, дедлайн сработал

  def spent(x: Incident, id: str, now: int): bool =
    ((leftOf(x, id, now) == 0) and (x.timers.get(id).fired != 0))

  // §11.4, BUG-73, BUG-75. Был в группе основного p в момент at: открытый привязанный, присоединённый не позже, или вышедший не раньше

  def inGroupAt(e: Incident, p: Incident, at: int): bool =
    ((((e.linkedTo == p.id) and not(isDone(e))) and (e.linkedAt <= at)) or (((e.leftGroup.primaryId == p.id) and (e.leftGroup.linkedAt <= at)) and (e.leftGroup.at >= at)))

  // §14.5. Поле «тип события» условия подошло событию: не задано или совпало. Одно из четырёх полей conditionMatches; по ним же объяснение отбора называет поле, на котором условие отпало (§12.5)

  def conditionEventTypeFits(c: Condition, e: Event): bool =
    ((c.eventType.length() == 0) or (c.eventType[0] == e.eventType))

  // §14.5. Поле «устройство» условия подошло событию: не задано или совпало

  def conditionDeviceFits(c: Condition, e: Event): bool =
    ((c.device.length() == 0) or (c.device[0] == e.device))

  // §14.5. Поле «тип устройства» условия подошло событию: не задано или совпало

  def conditionDeviceTypeFits(c: Condition, e: Event): bool =
    ((c.deviceType.length() == 0) or (c.deviceType[0] == e.deviceType))

  // §14.5. Поле «группа» условия подошло событию: не задано или устройство-источник в группе или во вложенной

  def conditionGroupFits(c: Condition, e: Event): bool =
    ((c.group.length() == 0) or deviceInGroup(e.device, c.group[0]))

  // §14.5, ARCH-15. Условие правила подошло событию: каждое заданное поле совпало (поля условия соединены «и»); группа — устройство-источник в ней или во вложенной. Поля — определения conditionEventTypeFits, conditionDeviceFits, conditionDeviceTypeFits, conditionGroupFits

  def conditionMatches(c: Condition, e: Event): bool =
    (((conditionEventTypeFits(c, e) and conditionDeviceFits(c, e)) and conditionDeviceTypeFits(c, e)) and conditionGroupFits(c, e))

  // §14.5, ARCH-15. Точность условия — по самому точному его полю: устройство 3000, тип устройства 2000, группа 1000 плюс глубина группы в дереве; только тип события — 0 (тип ранга не добавляет); такое условие — только у правил до решения 2026-11-12, новые требуют устройство или тип устройства вместе с типом события

  def conditionRank(c: Condition): int =
    (if ((c.device.length() > 0)) 3000 else (if ((c.deviceType.length() > 0)) 2000 else (if ((c.group.length() > 0)) (1000 + groupDepth(c.group[0])) else 0)))

  // §14.5, ARCH-15. Точность правила для события — наибольшая из подошедших условий (условия соединены «или»); не подошло ни одно — -1

  def ruleRank(r: Rule, e: Event): int =
    { val ks_70 = r.conditions.select(c_71 => conditionMatches(c_71, e)).foldl([], (acc, c_72) => acc.append(conditionRank(c_72)))  (if ((ks_70.length() == 0)) (0 - 1) else ks_70.select(k_73 => ks_70.foldl(true, (acc, j_74) => acc and (j_74 <= k_73)))[0]) }

  // §14.5, ARCH-15, ТЗ-2а. Правило подошло событию: оно включено (active), у него есть сценарий и подошло хоть одно условие. Выключенное правило и правило без сценария в выборе не участвуют: в ранжировании их нет, перекрыть включённое они не могут; в объяснении отбора выключенное — вердикт disabled (§12.5): disabled ⇔ !r.active. Rule.active — поле правила; у правила без поля (сохранено до ТЗ-2а) адаптер подставляет true

  def ruleMatches(r: Rule, e: Event): bool =
    ((r.active and (r.scenarios.length() > 0)) and r.conditions.foldl(false, (acc, c_75) => acc or conditionMatches(c_75, e)))

  // §14.5, ARCH-15 (решение пользователя 2026-10-28). Правило a старше b для события — строго: точнее условие; при равной точности — выше приоритет; при равном приоритете — раньше создано. Полное равенство — ни одно не старше: решает порядок списка правил, а он задан intake.ruleOrder (по guid), не порядком строк в базе

  def ruleBeats(a: Rule, b: Rule, e: Event): bool =
    { val ra_76 = ruleRank(a, e)  { val rb_77 = ruleRank(b, e)  ((ra_76 > rb_77) or ((ra_76 == rb_77) and ((a.priority > b.priority) or ((a.priority == b.priority) and (a.createdAt < b.createdAt))))) } }

  // §14.12, ТЗ-21. Интервал окна работ накрывает событие: время события в полуинтервале [from, to) — ровно в конец уже вне окна — и устройство-источник — устройство окна или в группе окна, в том числе во вложенной. w — один интервал: повтор окна сервер разворачивает в интервалы сам (правило — §14.12), машина получает уже развёрнутые

  def windowCovers(w: MaintenanceWindow, e: Event): bool =
    (((w.from <= e.at) and (e.at < w.to)) and (if ((w.device.length() > 0)) (w.device[0] == e.device) else ((w.group.length() > 0) and deviceInGroup(e.device, w.group[0]))))

  // §14.5 п. 6, §14.12, ТЗ-21. Окна проверяются только после выбора правил: winners — сколько инцидентов дали бы правила-победители (после ключа уникальности). Нет победителя — окна нет: событие остаётся «не сработало»

  def windowsAfterWinners(winners: int, ws: List[MaintenanceWindow], e: Event): List[MaintenanceWindow] =
    (if ((winners > 0)) windowsFor(ws, e) else [])

  // §14.12, ТЗ-21. Итог окна для события: режим maintenance.mode (suppress — инцидентов нет, mark — с окном и низшим приоритетом) или '' — окно не действует. Окно итога — первое из windowsAfterWinners. Итог и окно сервер сохраняет с событием при приёме: объяснение отбора отдаёт их, а не пересчитывает по текущим окнам

  def maintenanceOutcome(winners: int, ws: List[MaintenanceWindow], e: Event): str =
    (if ((windowsAfterWinners(winners, ws, e).length() > 0)) settings.maintenance.mode else "")

  // §14.12, §19.1, ТЗ-21 (решение 2026-11-15). Интервалы окон работ, идущие в момент at: тот же полуинтервал [from, to), что у windowCovers, без устройства. По нему сервер отбирает окна для полосы «Идут плановые работы» и значка в дереве групп (GET /operator/maintenance-windows/current) — из интервалов, видимых оператору по его доступу (§5)

  def windowsRunning(ws: List[MaintenanceWindow], at: int): List[MaintenanceWindow] =
    ws.select(w_78 => ((w_78.from <= at) and (at < w_78.to)))

  // §14.12, ТЗ-21. Интервалы окон работ, накрывающие событие; первое по порядку списка (по началу, при равенстве — по id окна) — окно, на которое ссылается итог. Пусто — окна нет

  def windowsFor(ws: List[MaintenanceWindow], e: Event): List[MaintenanceWindow] =
    ws.select(w_79 => windowCovers(w_79, e))

  // §14.5, ARCH-15. Правило-победитель сценария s для события: из подошедших правил с этим сценарием — те, кого не старше ни одно; сервер берёт первое по порядку списка — rules упорядочены по intake.ruleOrder. От него приоритет и ruleGuid инцидента

  def ruleFor(rules: List[Rule], e: Event, s: str): List[Rule] =
    { val ms_80 = rules.select(r_81 => (ruleMatches(r_81, e) and r_81.scenarios.foldl(false, (acc, y82) => acc or y82 == s)))  ms_80.select(r_83 => not(ms_80.foldl(false, (acc, o_84) => acc or ruleBeats(o_84, r_83, e)))) }

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_85 => (e_85.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_86 => ((e_86.id != p.id) and inGroupAt(e_86, p, at)))

  // §14.5, ARCH-15. Соседи — инциденты того же события, кроме самого x: другие службы той же тревоги. Не привязка §11: у каждого свой владелец, сроки и закрытие

  def siblingsOf(incidents: List[Incident], x: Incident): List[Incident] =
    incidents.select(s_87 => (((x.eventGuid != "") and (s_87.eventGuid == x.eventGuid)) and (s_87.id != x.id)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w88 = if (not(timerDef(timerId).pausable)) {
      val sec_89 = timerSec(w0.inc.get(iid), timerId, "")
      val w90 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_89 < 0)) 0 else (c.now + (sec_89 * 1000))) }) }) }
      val w91 = { ...w90, inc: w90.inc.set(iid, { ...w90.inc.get(iid), timers: w90.inc.get(iid).timers.set(timerId, { ...w90.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w91
    } else {
      val w92 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_93 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w94 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_93 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_93)) }) }) }
      val w95 = { ...w94, inc: w94.inc.set(iid, { ...w94.inc.get(iid), timers: w94.inc.get(iid).timers.set(timerId, { ...w94.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w96 = { ...w95, inc: w95.inc.set(iid, { ...w95.inc.get(iid), timers: w95.inc.get(iid).timers.set(timerId, { ...w95.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w96
    } else w0
      w92
    }
    w88
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w97 = if (not(timerDef(timerId).pausable)) {
      val w98 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w99 = { ...w98, inc: w98.inc.set(iid, { ...w98.inc.get(iid), timers: w98.inc.get(iid).timers.set(timerId, { ...w98.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w99
    } else {
      val w100 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w101 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w102 = { ...w101, inc: w101.inc.set(iid, { ...w101.inc.get(iid), timers: w101.inc.get(iid).timers.set(timerId, { ...w101.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w103 = { ...w102, inc: w102.inc.set(iid, { ...w102.inc.get(iid), timers: w102.inc.get(iid).timers.set(timerId, { ...w102.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w103
    } else w0
      w100
    }
    w97
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
    (ruleAddressing(world.inc.get(iid)) == "none"),
  }

  def okAt_create(c: Ctx, iid: str, w: World): bool = all {
    w.inc.get(iid).state == "",
    (ruleAddressing(w.inc.get(iid)) == "none"),
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_104 = ""
    val w105 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_104 }) }
    w105
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_106 = ""
    val w107 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_106 }) }
    val w108 = if ((group_106 != "")) {
      val w109 = { ...w107, inc: w107.inc.set(iid, { ...w107.inc.get(iid), lastAssignedGroup: group_106 }) }
      w109
    } else w107
    w108
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_110 = 0
    val w111 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_110 }) }
    w111
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w112 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w113 = if (timerDef("reaction").startsOnce) {
      val w114 = ec_resumeTimer(w0, c, iid, "reaction")
      w114
    } else {
      val w115 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w116 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w117 = { ...w116, inc: w116.inc.set(iid, { ...w116.inc.get(iid), timers: w116.inc.get(iid).timers.set("reaction", { ...w116.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w118 = { ...w117, inc: w117.inc.set(iid, { ...w117.inc.get(iid), timers: w117.inc.get(iid).timers.set("reaction", { ...w117.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w118
    } else {
      val sec_119 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w120 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_119 < 0)) 0 else (c.now + (sec_119 * 1000))) }) }) }
      val w121 = { ...w120, inc: w120.inc.set(iid, { ...w120.inc.get(iid), timers: w120.inc.get(iid).timers.set("reaction", { ...w120.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w122 = { ...w121, inc: w121.inc.set(iid, { ...w121.inc.get(iid), timers: w121.inc.get(iid).timers.set("reaction", { ...w121.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w123 = { ...w122, inc: w122.inc.set(iid, { ...w122.inc.get(iid), timers: w122.inc.get(iid).timers.set("reaction", { ...w122.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w123
    }
      w115
    }
      w113
    }
    w112
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

  // create_to_group: event → pending_acceptance

  def ok_create_to_group(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
    (ruleAddressing(world.inc.get(iid)) == "group"),
  }

  def okAt_create_to_group(c: Ctx, iid: str, w: World): bool = all {
    w.inc.get(iid).state == "",
    (ruleAddressing(w.inc.get(iid)) == "group"),
  }

  def e_create_to_group_0(w0: World, c: Ctx, iid: str): World = {
    val who_124 = ""
    val w125 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_124 }) }
    w125
  }

  def e_create_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val group_126 = w0.inc.get(iid).ruleDutyGroup
    val w127 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_126 }) }
    val w128 = if ((group_126 != "")) {
      val w129 = { ...w127, inc: w127.inc.set(iid, { ...w127.inc.get(iid), lastAssignedGroup: group_126 }) }
      w129
    } else w127
    w128
  }

  def e_create_to_group_2(w0: World, c: Ctx, iid: str): World = {
    val value_130 = 0
    val w131 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_130 }) }
    w131
  }

  def e_create_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val w132 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w133 = if (timerDef("reaction").startsOnce) {
      val w134 = ec_resumeTimer(w0, c, iid, "reaction")
      w134
    } else {
      val w135 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w136 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w137 = { ...w136, inc: w136.inc.set(iid, { ...w136.inc.get(iid), timers: w136.inc.get(iid).timers.set("reaction", { ...w136.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w138 = { ...w137, inc: w137.inc.set(iid, { ...w137.inc.get(iid), timers: w137.inc.get(iid).timers.set("reaction", { ...w137.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w138
    } else {
      val sec_139 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w140 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_139 < 0)) 0 else (c.now + (sec_139 * 1000))) }) }) }
      val w141 = { ...w140, inc: w140.inc.set(iid, { ...w140.inc.get(iid), timers: w140.inc.get(iid).timers.set("reaction", { ...w140.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w142 = { ...w141, inc: w141.inc.set(iid, { ...w141.inc.get(iid), timers: w141.inc.get(iid).timers.set("reaction", { ...w141.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w143 = { ...w142, inc: w142.inc.set(iid, { ...w142.inc.get(iid), timers: w142.inc.get(iid).timers.set("reaction", { ...w142.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w143
    }
      w135
    }
      w133
    }
    w132
  }

  def e_create_to_group_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_create_to_group_5(w0: World, c: Ctx, iid: str): World = {
    val whom_144 = addressee(w0.inc.get(iid))
    val w145 = if (((whom_144 != "") and (whom_144 != c.actor))) w0 else w0
    w145
  }

  def apply_create_to_group(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_create_to_group_0(ws, c1, iid)
    val w2 = e_create_to_group_1(w1, c1, iid)
    val w3 = e_create_to_group_2(w2, c1, iid)
    val w4 = e_create_to_group_3(w3, c1, iid)
    val w5 = e_create_to_group_4(w4, c1, iid)
    val w6 = e_create_to_group_5(w5, c1, iid)
    w6
  }

  // rule_group_cannot_accept: event → new

  def ok_rule_group_cannot_accept(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
    (ruleAddressing(world.inc.get(iid)) == "queue"),
  }

  def okAt_rule_group_cannot_accept(c: Ctx, iid: str, w: World): bool = all {
    w.inc.get(iid).state == "",
    (ruleAddressing(w.inc.get(iid)) == "queue"),
  }

  def e_rule_group_cannot_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_146 = ""
    val w147 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_146 }) }
    w147
  }

  def e_rule_group_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_148 = ""
    val w149 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_148 }) }
    val w150 = if ((group_148 != "")) {
      val w151 = { ...w149, inc: w149.inc.set(iid, { ...w149.inc.get(iid), lastAssignedGroup: group_148 }) }
      w151
    } else w149
    w150
  }

  def e_rule_group_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val value_152 = 0
    val w153 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_152 }) }
    w153
  }

  def e_rule_group_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w154 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w155 = if (timerDef("reaction").startsOnce) {
      val w156 = ec_resumeTimer(w0, c, iid, "reaction")
      w156
    } else {
      val w157 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w158 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w159 = { ...w158, inc: w158.inc.set(iid, { ...w158.inc.get(iid), timers: w158.inc.get(iid).timers.set("reaction", { ...w158.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w160 = { ...w159, inc: w159.inc.set(iid, { ...w159.inc.get(iid), timers: w159.inc.get(iid).timers.set("reaction", { ...w159.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w160
    } else {
      val sec_161 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w162 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_161 < 0)) 0 else (c.now + (sec_161 * 1000))) }) }) }
      val w163 = { ...w162, inc: w162.inc.set(iid, { ...w162.inc.get(iid), timers: w162.inc.get(iid).timers.set("reaction", { ...w162.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w164 = { ...w163, inc: w163.inc.set(iid, { ...w163.inc.get(iid), timers: w163.inc.get(iid).timers.set("reaction", { ...w163.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w165 = { ...w164, inc: w164.inc.set(iid, { ...w164.inc.get(iid), timers: w164.inc.get(iid).timers.set("reaction", { ...w164.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w165
    }
      w157
    }
      w155
    }
    w154
  }

  def e_rule_group_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_rule_group_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_166 = settings.alerts.target
    val w167 = if (((whom_166 != "") and (whom_166 != c.actor))) w0 else w0
    w167
  }

  def apply_rule_group_cannot_accept(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_rule_group_cannot_accept_0(ws, c1, iid)
    val w2 = e_rule_group_cannot_accept_1(w1, c1, iid)
    val w3 = e_rule_group_cannot_accept_2(w2, c1, iid)
    val w4 = e_rule_group_cannot_accept_3(w3, c1, iid)
    val w5 = e_rule_group_cannot_accept_4(w4, c1, iid)
    val w6 = e_rule_group_cannot_accept_5(w5, c1, iid)
    w6
  }

  // claim: manual → in_progress

  def ok_claim(c: Ctx, iid: str): bool = all {
    Set("new").contains(world.inc.get(iid).state),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_168) => acc or ((s_168.id == agentState(c.me)) and s_168.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_169 = c.actor
    val w170 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_169 }) }
    w170
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w171 = if (timerDef("reaction").startsOnce) {
      val w172 = ec_pauseTimer(w0, c, iid, "reaction")
      w172
    } else {
      val w173 = if (false) {
      val w174 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w175 = { ...w174, inc: w174.inc.set(iid, { ...w174.inc.get(iid), timers: w174.inc.get(iid).timers.set("reaction", { ...w174.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w176 = { ...w175, inc: w175.inc.set(iid, { ...w175.inc.get(iid), timers: w175.inc.get(iid).timers.set("reaction", { ...w175.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w177 = { ...w176, inc: w176.inc.set(iid, { ...w176.inc.get(iid), timers: w176.inc.get(iid).timers.set("reaction", { ...w176.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w177
    } else {
      val w178 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_179 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w180 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_179) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w181 = { ...w180, inc: w180.inc.set(iid, { ...w180.inc.get(iid), timers: w180.inc.get(iid).timers.set("reaction", { ...w180.inc.get(iid).timers.get("reaction"), paused: keep_179 }) }) }
      val w182 = { ...w181, inc: w181.inc.set(iid, { ...w181.inc.get(iid), timers: w181.inc.get(iid).timers.set("reaction", { ...w181.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w183 = { ...w182, inc: w182.inc.set(iid, { ...w182.inc.get(iid), timers: w182.inc.get(iid).timers.set("reaction", { ...w182.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w183
    }
      w178
    }
      w173
    }
    w171
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w184 = if (not(timerDef("resolution").pausable)) {
      val sec_185 = timerSec(w0.inc.get(iid), "resolution", "")
      val w186 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_185 < 0)) 0 else (c.now + (sec_185 * 1000))) }) }) }
      val w187 = { ...w186, inc: w186.inc.set(iid, { ...w186.inc.get(iid), timers: w186.inc.get(iid).timers.set("resolution", { ...w186.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w187
    } else {
      val w188 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_189 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w190 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_189 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_189)) }) }) }
      val w191 = { ...w190, inc: w190.inc.set(iid, { ...w190.inc.get(iid), timers: w190.inc.get(iid).timers.set("resolution", { ...w190.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w192 = { ...w191, inc: w191.inc.set(iid, { ...w191.inc.get(iid), timers: w191.inc.get(iid).timers.set("resolution", { ...w191.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w192
    } else w0
      w188
    }
    w184
  }

  def e_claim_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_claim_4(w0: World, c: Ctx, iid: str): World = {
    val w193 = if (((w0.inc.get(iid).acceptedAt == 0) and not(w0.inc.get(iid).noReaction))) {
      val w194 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedAt: c.now }) }
      val w195 = { ...w194, inc: w194.inc.set(iid, { ...w194.inc.get(iid), acceptedBy: c.actor }) }
      val w196 = { ...w195, inc: w195.inc.set(iid, { ...w195.inc.get(iid), acceptedGroup: (if ((c.before.lastAssignedGroup != "")) c.before.lastAssignedGroup else dutyGroupOf(c.actor)) }) }
      w196
    } else w0
    w193
  }

  def e_claim_5(w0: World, c: Ctx, iid: str): World = {

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
    val w6 = e_claim_5(w5, c1, iid)
    w6
  }

  // accept: manual → in_progress

  def ok_accept(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    can(c.me, "incident:accept"),
    isTarget(c.me, world.inc.get(iid)),
    not(settings.session.states.foldl(false, (acc, s_197) => acc or ((s_197.id == agentState(c.me)) and s_197.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_198 = c.actor
    val w199 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_198 }) }
    w199
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_200 = ""
    val w201 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_200 }) }
    val w202 = if ((group_200 != "")) {
      val w203 = { ...w201, inc: w201.inc.set(iid, { ...w201.inc.get(iid), lastAssignedGroup: group_200 }) }
      w203
    } else w201
    w202
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w204 = if (timerDef("reaction").startsOnce) {
      val w205 = ec_pauseTimer(w0, c, iid, "reaction")
      w205
    } else {
      val w206 = if (false) {
      val w207 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w208 = { ...w207, inc: w207.inc.set(iid, { ...w207.inc.get(iid), timers: w207.inc.get(iid).timers.set("reaction", { ...w207.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w209 = { ...w208, inc: w208.inc.set(iid, { ...w208.inc.get(iid), timers: w208.inc.get(iid).timers.set("reaction", { ...w208.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w210 = { ...w209, inc: w209.inc.set(iid, { ...w209.inc.get(iid), timers: w209.inc.get(iid).timers.set("reaction", { ...w209.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w210
    } else {
      val w211 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_212 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w213 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_212) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w214 = { ...w213, inc: w213.inc.set(iid, { ...w213.inc.get(iid), timers: w213.inc.get(iid).timers.set("reaction", { ...w213.inc.get(iid).timers.get("reaction"), paused: keep_212 }) }) }
      val w215 = { ...w214, inc: w214.inc.set(iid, { ...w214.inc.get(iid), timers: w214.inc.get(iid).timers.set("reaction", { ...w214.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w216 = { ...w215, inc: w215.inc.set(iid, { ...w215.inc.get(iid), timers: w215.inc.get(iid).timers.set("reaction", { ...w215.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w216
    }
      w211
    }
      w206
    }
    w204
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
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

  def e_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_accept_5(w0: World, c: Ctx, iid: str): World = {
    val w226 = if (((w0.inc.get(iid).acceptedAt == 0) and not(w0.inc.get(iid).noReaction))) {
      val w227 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedAt: c.now }) }
      val w228 = { ...w227, inc: w227.inc.set(iid, { ...w227.inc.get(iid), acceptedBy: c.actor }) }
      val w229 = { ...w228, inc: w228.inc.set(iid, { ...w228.inc.get(iid), acceptedGroup: (if ((c.before.lastAssignedGroup != "")) c.before.lastAssignedGroup else dutyGroupOf(c.actor)) }) }
      w229
    } else w0
    w226
  }

  def e_accept_6(w0: World, c: Ctx, iid: str): World = {

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
    val w7 = e_accept_6(w6, c1, iid)
    w7
  }

  // reject: manual → new

  def ok_reject(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    can(c.me, "incident:release"),
    isTarget(c.me, world.inc.get(iid)),
    not(settings.session.states.foldl(false, (acc, s_230) => acc or ((s_230.id == agentState(c.me)) and s_230.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_231 = ""
    val w232 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_231 }) }
    w232
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_233 = ""
    val w234 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_233 }) }
    val w235 = if ((group_233 != "")) {
      val w236 = { ...w234, inc: w234.inc.set(iid, { ...w234.inc.get(iid), lastAssignedGroup: group_233 }) }
      w236
    } else w234
    w235
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
    not(settings.session.states.foldl(false, (acc, s_237) => acc or ((s_237.id == agentState(c.me)) and s_237.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
    settings.holdReasons.foldl(false, (acc, r_238) => acc or (r_238.setBy != "system")),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_239 = c.form.reasonId
    val w240 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_239 }) }
    w240
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
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

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w248 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w249 = if (timerDef("hold").startsOnce) {
      val w250 = ec_resumeTimer(w0, c, iid, "hold")
      w250
    } else {
      val w251 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w252 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w253 = { ...w252, inc: w252.inc.set(iid, { ...w252.inc.get(iid), timers: w252.inc.get(iid).timers.set("hold", { ...w252.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("hold", { ...w253.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w254
    } else {
      val sec_255 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w256 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_255 < 0)) 0 else (c.now + (sec_255 * 1000))) }) }) }
      val w257 = { ...w256, inc: w256.inc.set(iid, { ...w256.inc.get(iid), timers: w256.inc.get(iid).timers.set("hold", { ...w256.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w258 = { ...w257, inc: w257.inc.set(iid, { ...w257.inc.get(iid), timers: w257.inc.get(iid).timers.set("hold", { ...w257.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w259 = { ...w258, inc: w258.inc.set(iid, { ...w258.inc.get(iid), timers: w258.inc.get(iid).timers.set("hold", { ...w258.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w259
    }
      w251
    }
      w249
    }
    w248
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
    not(settings.session.states.foldl(false, (acc, s_260) => acc or ((s_260.id == agentState(c.me)) and s_260.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w261 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w261
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w262 = if (timerDef("hold").startsOnce) {
      val w263 = ec_pauseTimer(w0, c, iid, "hold")
      w263
    } else {
      val w264 = if (false) {
      val w265 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w266 = { ...w265, inc: w265.inc.set(iid, { ...w265.inc.get(iid), timers: w265.inc.get(iid).timers.set("hold", { ...w265.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w267 = { ...w266, inc: w266.inc.set(iid, { ...w266.inc.get(iid), timers: w266.inc.get(iid).timers.set("hold", { ...w266.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w268 = { ...w267, inc: w267.inc.set(iid, { ...w267.inc.get(iid), timers: w267.inc.get(iid).timers.set("hold", { ...w267.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w268
    } else {
      val w269 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_270 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w271 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_270) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w272 = { ...w271, inc: w271.inc.set(iid, { ...w271.inc.get(iid), timers: w271.inc.get(iid).timers.set("hold", { ...w271.inc.get(iid).timers.get("hold"), paused: keep_270 }) }) }
      val w273 = { ...w272, inc: w272.inc.set(iid, { ...w272.inc.get(iid), timers: w272.inc.get(iid).timers.set("hold", { ...w272.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w274 = { ...w273, inc: w273.inc.set(iid, { ...w273.inc.get(iid), timers: w273.inc.get(iid).timers.set("hold", { ...w273.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w274
    }
      w269
    }
      w264
    }
    w262
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w275 = if (not(timerDef("resolution").pausable)) {
      val sec_276 = timerSec(w0.inc.get(iid), "resolution", "")
      val w277 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_276 < 0)) 0 else (c.now + (sec_276 * 1000))) }) }) }
      val w278 = { ...w277, inc: w277.inc.set(iid, { ...w277.inc.get(iid), timers: w277.inc.get(iid).timers.set("resolution", { ...w277.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w278
    } else {
      val w279 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_280 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w281 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_280 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_280)) }) }) }
      val w282 = { ...w281, inc: w281.inc.set(iid, { ...w281.inc.get(iid), timers: w281.inc.get(iid).timers.set("resolution", { ...w281.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w283 = { ...w282, inc: w282.inc.set(iid, { ...w282.inc.get(iid), timers: w282.inc.get(iid).timers.set("resolution", { ...w282.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w283
    } else w0
      w279
    }
    w275
  }

  def e_resume_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resume_4(w0: World, c: Ctx, iid: str): World = {
    val w284 = if (((w0.inc.get(iid).acceptedAt == 0) and not(w0.inc.get(iid).noReaction))) {
      val w285 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedAt: c.now }) }
      val w286 = { ...w285, inc: w285.inc.set(iid, { ...w285.inc.get(iid), acceptedBy: c.actor }) }
      val w287 = { ...w286, inc: w286.inc.set(iid, { ...w286.inc.get(iid), acceptedGroup: (if ((c.before.lastAssignedGroup != "")) c.before.lastAssignedGroup else dutyGroupOf(c.actor)) }) }
      w287
    } else w0
    w284
  }

  def e_resume_5(w0: World, c: Ctx, iid: str): World = {

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
    val w6 = e_resume_5(w5, c1, iid)
    w6
  }

  // release: manual → new

  def ok_release(c: Ctx, iid: str): bool = all {
    Set("in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:release"),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_288) => acc or ((s_288.id == agentState(c.me)) and s_288.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_289 = ""
    val w290 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_289 }) }
    w290
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w291 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w291
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w292 = if (not(timerDef("resolution").pausable)) {
      val w293 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w294 = { ...w293, inc: w293.inc.set(iid, { ...w293.inc.get(iid), timers: w293.inc.get(iid).timers.set("resolution", { ...w293.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w294
    } else {
      val w295 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w296 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w297 = { ...w296, inc: w296.inc.set(iid, { ...w296.inc.get(iid), timers: w296.inc.get(iid).timers.set("resolution", { ...w296.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w298 = { ...w297, inc: w297.inc.set(iid, { ...w297.inc.get(iid), timers: w297.inc.get(iid).timers.set("resolution", { ...w297.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w298
    } else w0
      w295
    }
    w292
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w299 = if (timerDef("hold").startsOnce) {
      val w300 = ec_pauseTimer(w0, c, iid, "hold")
      w300
    } else {
      val w301 = if (false) {
      val w302 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w303 = { ...w302, inc: w302.inc.set(iid, { ...w302.inc.get(iid), timers: w302.inc.get(iid).timers.set("hold", { ...w302.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w304 = { ...w303, inc: w303.inc.set(iid, { ...w303.inc.get(iid), timers: w303.inc.get(iid).timers.set("hold", { ...w303.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w305 = { ...w304, inc: w304.inc.set(iid, { ...w304.inc.get(iid), timers: w304.inc.get(iid).timers.set("hold", { ...w304.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w305
    } else {
      val w306 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_307 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w308 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_307) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w309 = { ...w308, inc: w308.inc.set(iid, { ...w308.inc.get(iid), timers: w308.inc.get(iid).timers.set("hold", { ...w308.inc.get(iid).timers.get("hold"), paused: keep_307 }) }) }
      val w310 = { ...w309, inc: w309.inc.set(iid, { ...w309.inc.get(iid), timers: w309.inc.get(iid).timers.set("hold", { ...w309.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w311 = { ...w310, inc: w310.inc.set(iid, { ...w310.inc.get(iid), timers: w310.inc.get(iid).timers.set("hold", { ...w310.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w311
    }
      w306
    }
      w301
    }
    w299
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w312 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w313 = if (timerDef("reaction").startsOnce) {
      val w314 = ec_resumeTimer(w0, c, iid, "reaction")
      w314
    } else {
      val w315 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w316 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w317 = { ...w316, inc: w316.inc.set(iid, { ...w316.inc.get(iid), timers: w316.inc.get(iid).timers.set("reaction", { ...w316.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w318 = { ...w317, inc: w317.inc.set(iid, { ...w317.inc.get(iid), timers: w317.inc.get(iid).timers.set("reaction", { ...w317.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w318
    } else {
      val sec_319 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w320 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_319 < 0)) 0 else (c.now + (sec_319 * 1000))) }) }) }
      val w321 = { ...w320, inc: w320.inc.set(iid, { ...w320.inc.get(iid), timers: w320.inc.get(iid).timers.set("reaction", { ...w320.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w322 = { ...w321, inc: w321.inc.set(iid, { ...w321.inc.get(iid), timers: w321.inc.get(iid).timers.set("reaction", { ...w321.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w323 = { ...w322, inc: w322.inc.set(iid, { ...w322.inc.get(iid), timers: w322.inc.get(iid).timers.set("reaction", { ...w322.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w323
    }
      w315
    }
      w313
    }
    w312
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
    not(settings.session.states.foldl(false, (acc, s_324) => acc or ((s_324.id == agentState(c.me)) and s_324.readOnly))),
    transferTargets.foldl(false, (acc, t_325) => acc or (offersTransferTo(c.me, t_325, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_326) => acc and (isDone(e_326) or hasAccess(t_325, e_326))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_327) => acc and (isDone(e_327) or hasAccess(c.form.targetId, e_327)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_328 = personOf(c.form.targetId)
    val w329 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_328 }) }
    w329
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_330 = groupOf(c.form.targetId)
    val w331 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_330 }) }
    val w332 = if ((group_330 != "")) {
      val w333 = { ...w331, inc: w331.inc.set(iid, { ...w331.inc.get(iid), lastAssignedGroup: group_330 }) }
      w333
    } else w331
    w332
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w334 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w334
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w335 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w335
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w336 = if (not(timerDef("resolution").pausable)) {
      val w337 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w338 = { ...w337, inc: w337.inc.set(iid, { ...w337.inc.get(iid), timers: w337.inc.get(iid).timers.set("resolution", { ...w337.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w338
    } else {
      val w339 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w340 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w341 = { ...w340, inc: w340.inc.set(iid, { ...w340.inc.get(iid), timers: w340.inc.get(iid).timers.set("resolution", { ...w340.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w342 = { ...w341, inc: w341.inc.set(iid, { ...w341.inc.get(iid), timers: w341.inc.get(iid).timers.set("resolution", { ...w341.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w342
    } else w0
      w339
    }
    w336
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w343 = if (timerDef("hold").startsOnce) {
      val w344 = ec_pauseTimer(w0, c, iid, "hold")
      w344
    } else {
      val w345 = if (false) {
      val w346 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w347 = { ...w346, inc: w346.inc.set(iid, { ...w346.inc.get(iid), timers: w346.inc.get(iid).timers.set("hold", { ...w346.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w348 = { ...w347, inc: w347.inc.set(iid, { ...w347.inc.get(iid), timers: w347.inc.get(iid).timers.set("hold", { ...w347.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w349 = { ...w348, inc: w348.inc.set(iid, { ...w348.inc.get(iid), timers: w348.inc.get(iid).timers.set("hold", { ...w348.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w349
    } else {
      val w350 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_351 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w352 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_351) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w353 = { ...w352, inc: w352.inc.set(iid, { ...w352.inc.get(iid), timers: w352.inc.get(iid).timers.set("hold", { ...w352.inc.get(iid).timers.get("hold"), paused: keep_351 }) }) }
      val w354 = { ...w353, inc: w353.inc.set(iid, { ...w353.inc.get(iid), timers: w353.inc.get(iid).timers.set("hold", { ...w353.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w355 = { ...w354, inc: w354.inc.set(iid, { ...w354.inc.get(iid), timers: w354.inc.get(iid).timers.set("hold", { ...w354.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w355
    }
      w350
    }
      w345
    }
    w343
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w356 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w357 = if (timerDef("reaction").startsOnce) {
      val w358 = ec_resumeTimer(w0, c, iid, "reaction")
      w358
    } else {
      val w359 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w360 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w361 = { ...w360, inc: w360.inc.set(iid, { ...w360.inc.get(iid), timers: w360.inc.get(iid).timers.set("reaction", { ...w360.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w362 = { ...w361, inc: w361.inc.set(iid, { ...w361.inc.get(iid), timers: w361.inc.get(iid).timers.set("reaction", { ...w361.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w362
    } else {
      val sec_363 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w364 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_363 < 0)) 0 else (c.now + (sec_363 * 1000))) }) }) }
      val w365 = { ...w364, inc: w364.inc.set(iid, { ...w364.inc.get(iid), timers: w364.inc.get(iid).timers.set("reaction", { ...w364.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w366 = { ...w365, inc: w365.inc.set(iid, { ...w365.inc.get(iid), timers: w365.inc.get(iid).timers.set("reaction", { ...w365.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w367 = { ...w366, inc: w366.inc.set(iid, { ...w366.inc.get(iid), timers: w366.inc.get(iid).timers.set("reaction", { ...w366.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w367
    }
      w359
    }
      w357
    }
    w356
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_368 = c.before.owner
    val w369 = if (((whom_368 != "") and (whom_368 != c.actor))) w0 else w0
    w369
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_370 = addressee(w0.inc.get(iid))
    val w371 = if (((whom_370 != "") and (whom_370 != c.actor))) w0 else w0
    w371
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
    not(settings.session.states.foldl(false, (acc, s_372) => acc or ((s_372.id == agentState(c.me)) and s_372.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_373 = c.actor
    val w374 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_373 }) }
    w374
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_375 = ""
    val w376 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_375 }) }
    val w377 = if ((group_375 != "")) {
      val w378 = { ...w376, inc: w376.inc.set(iid, { ...w376.inc.get(iid), lastAssignedGroup: group_375 }) }
      w378
    } else w376
    w377
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w379 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w379
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w380 = if (timerDef("reaction").startsOnce) {
      val w381 = ec_pauseTimer(w0, c, iid, "reaction")
      w381
    } else {
      val w382 = if (false) {
      val w383 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w384 = { ...w383, inc: w383.inc.set(iid, { ...w383.inc.get(iid), timers: w383.inc.get(iid).timers.set("reaction", { ...w383.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w385 = { ...w384, inc: w384.inc.set(iid, { ...w384.inc.get(iid), timers: w384.inc.get(iid).timers.set("reaction", { ...w384.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w386 = { ...w385, inc: w385.inc.set(iid, { ...w385.inc.get(iid), timers: w385.inc.get(iid).timers.set("reaction", { ...w385.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w386
    } else {
      val w387 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_388 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w389 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_388) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w390 = { ...w389, inc: w389.inc.set(iid, { ...w389.inc.get(iid), timers: w389.inc.get(iid).timers.set("reaction", { ...w389.inc.get(iid).timers.get("reaction"), paused: keep_388 }) }) }
      val w391 = { ...w390, inc: w390.inc.set(iid, { ...w390.inc.get(iid), timers: w390.inc.get(iid).timers.set("reaction", { ...w390.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w392 = { ...w391, inc: w391.inc.set(iid, { ...w391.inc.get(iid), timers: w391.inc.get(iid).timers.set("reaction", { ...w391.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w392
    }
      w387
    }
      w382
    }
    w380
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w393 = if (timerDef("hold").startsOnce) {
      val w394 = ec_pauseTimer(w0, c, iid, "hold")
      w394
    } else {
      val w395 = if (false) {
      val w396 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w397 = { ...w396, inc: w396.inc.set(iid, { ...w396.inc.get(iid), timers: w396.inc.get(iid).timers.set("hold", { ...w396.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w398 = { ...w397, inc: w397.inc.set(iid, { ...w397.inc.get(iid), timers: w397.inc.get(iid).timers.set("hold", { ...w397.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w399 = { ...w398, inc: w398.inc.set(iid, { ...w398.inc.get(iid), timers: w398.inc.get(iid).timers.set("hold", { ...w398.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w399
    } else {
      val w400 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_401 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w402 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_401) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w403 = { ...w402, inc: w402.inc.set(iid, { ...w402.inc.get(iid), timers: w402.inc.get(iid).timers.set("hold", { ...w402.inc.get(iid).timers.get("hold"), paused: keep_401 }) }) }
      val w404 = { ...w403, inc: w403.inc.set(iid, { ...w403.inc.get(iid), timers: w403.inc.get(iid).timers.set("hold", { ...w403.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w405 = { ...w404, inc: w404.inc.set(iid, { ...w404.inc.get(iid), timers: w404.inc.get(iid).timers.set("hold", { ...w404.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w405
    }
      w400
    }
      w395
    }
    w393
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w406 = if (not(timerDef("resolution").pausable)) {
      val sec_407 = timerSec(w0.inc.get(iid), "resolution", "")
      val w408 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_407 < 0)) 0 else (c.now + (sec_407 * 1000))) }) }) }
      val w409 = { ...w408, inc: w408.inc.set(iid, { ...w408.inc.get(iid), timers: w408.inc.get(iid).timers.set("resolution", { ...w408.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w409
    } else {
      val w410 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_411 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w412 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_411 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_411)) }) }) }
      val w413 = { ...w412, inc: w412.inc.set(iid, { ...w412.inc.get(iid), timers: w412.inc.get(iid).timers.set("resolution", { ...w412.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w414 = { ...w413, inc: w413.inc.set(iid, { ...w413.inc.get(iid), timers: w413.inc.get(iid).timers.set("resolution", { ...w413.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w414
    } else w0
      w410
    }
    w406
  }

  def e_takeover_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_7(w0: World, c: Ctx, iid: str): World = {
    val w415 = if (((w0.inc.get(iid).acceptedAt == 0) and not(w0.inc.get(iid).noReaction))) {
      val w416 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedAt: c.now }) }
      val w417 = { ...w416, inc: w416.inc.set(iid, { ...w416.inc.get(iid), acceptedBy: c.actor }) }
      val w418 = { ...w417, inc: w417.inc.set(iid, { ...w417.inc.get(iid), acceptedGroup: (if ((c.before.lastAssignedGroup != "")) c.before.lastAssignedGroup else dutyGroupOf(c.actor)) }) }
      w418
    } else w0
    w415
  }

  def e_takeover_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_9(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_10(w0: World, c: Ctx, iid: str): World = {
    val whom_419 = c.before.owner
    val w420 = if (((whom_419 != "") and (whom_419 != c.actor))) w0 else w0
    w420
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
    val w11 = e_takeover_10(w10, c1, iid)
    w11
  }

  // close: manual → closed

  def ok_close(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    not(settings.session.states.foldl(false, (acc, s_421) => acc or ((s_421.id == agentState(c.me)) and s_421.readOnly))),
    { val os_422 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_422.foldl(false, (acc, o_423) => acc or ((o_423.id == c.form.resultId) and stepsOk(o_423, world.inc.get(iid)))) else os_422.foldl(false, (acc, o_424) => acc or stepsOk(o_424, world.inc.get(iid)))) },
    ((((c.form.resultId == "") or (c.form.causeId == "")) or not(settings.closeResults.foldl(false, (acc, i_425) => acc or ((i_425.id == c.form.resultId) and (i_425.causeCatalog != ""))))) or (causeOk(c.form.resultId, c.form.causeId) and (not(causeCommentRequired(c.form.resultId, c.form.causeId)) or (c.form.comment != "")))),
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_426 = c.actor
    val w427 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_426 }) }
    w427
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_428 = ""
    val w429 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_428 }) }
    val w430 = if ((group_428 != "")) {
      val w431 = { ...w429, inc: w429.inc.set(iid, { ...w429.inc.get(iid), lastAssignedGroup: group_428 }) }
      w431
    } else w429
    w430
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_432 = c.actor
    val w433 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_432 }) }
    w433
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_434 = c.now
    val w435 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_434 }) }
    w435
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_436 = c.form.resultId
    val w437 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_436 }) }
    w437
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_438 = (if (causeOk(c.form.resultId, c.form.causeId)) c.form.causeId else "")
    val w439 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_438 }) }
    w439
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_440 = causeLabel(c.form.resultId, c.form.causeId)
    val w441 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_440 }) }
    w441
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val value_442 = (if ((c.form.resultId == "drill")) c.form.maintenanceWindowId else "")
    val w443 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_442 }) }
    w443
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val value_444 = c.form.comment
    val w445 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_444 }) }
    w445
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w446 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w446
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w447 = if (timerDef("reaction").startsOnce) {
      val w448 = ec_pauseTimer(w0, c, iid, "reaction")
      w448
    } else {
      val w449 = if (true) {
      val w450 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w451 = { ...w450, inc: w450.inc.set(iid, { ...w450.inc.get(iid), timers: w450.inc.get(iid).timers.set("reaction", { ...w450.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w452 = { ...w451, inc: w451.inc.set(iid, { ...w451.inc.get(iid), timers: w451.inc.get(iid).timers.set("reaction", { ...w451.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w453 = { ...w452, inc: w452.inc.set(iid, { ...w452.inc.get(iid), timers: w452.inc.get(iid).timers.set("reaction", { ...w452.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w453
    } else {
      val w454 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_455 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w456 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_455) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w457 = { ...w456, inc: w456.inc.set(iid, { ...w456.inc.get(iid), timers: w456.inc.get(iid).timers.set("reaction", { ...w456.inc.get(iid).timers.get("reaction"), paused: keep_455 }) }) }
      val w458 = { ...w457, inc: w457.inc.set(iid, { ...w457.inc.get(iid), timers: w457.inc.get(iid).timers.set("reaction", { ...w457.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w459 = { ...w458, inc: w458.inc.set(iid, { ...w458.inc.get(iid), timers: w458.inc.get(iid).timers.set("reaction", { ...w458.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w459
    }
      w454
    }
      w449
    }
    w447
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {
    val w460 = if (not(timerDef("resolution").pausable)) {
      val w461 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w462 = { ...w461, inc: w461.inc.set(iid, { ...w461.inc.get(iid), timers: w461.inc.get(iid).timers.set("resolution", { ...w461.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w462
    } else {
      val w463 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w464 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w465 = { ...w464, inc: w464.inc.set(iid, { ...w464.inc.get(iid), timers: w464.inc.get(iid).timers.set("resolution", { ...w464.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w466 = { ...w465, inc: w465.inc.set(iid, { ...w465.inc.get(iid), timers: w465.inc.get(iid).timers.set("resolution", { ...w465.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w466
    } else w0
      w463
    }
    w460
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {
    val w467 = if (timerDef("hold").startsOnce) {
      val w468 = ec_pauseTimer(w0, c, iid, "hold")
      w468
    } else {
      val w469 = if (false) {
      val w470 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w471 = { ...w470, inc: w470.inc.set(iid, { ...w470.inc.get(iid), timers: w470.inc.get(iid).timers.set("hold", { ...w470.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w472 = { ...w471, inc: w471.inc.set(iid, { ...w471.inc.get(iid), timers: w471.inc.get(iid).timers.set("hold", { ...w471.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w473 = { ...w472, inc: w472.inc.set(iid, { ...w472.inc.get(iid), timers: w472.inc.get(iid).timers.set("hold", { ...w472.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w473
    } else {
      val w474 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_475 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w476 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_475) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w477 = { ...w476, inc: w476.inc.set(iid, { ...w476.inc.get(iid), timers: w476.inc.get(iid).timers.set("hold", { ...w476.inc.get(iid).timers.get("hold"), paused: keep_475 }) }) }
      val w478 = { ...w477, inc: w477.inc.set(iid, { ...w477.inc.get(iid), timers: w477.inc.get(iid).timers.set("hold", { ...w477.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w479 = { ...w478, inc: w478.inc.set(iid, { ...w478.inc.get(iid), timers: w478.inc.get(iid).timers.set("hold", { ...w478.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w479
    }
      w474
    }
      w469
    }
    w467
  }

  def e_close_13(w0: World, c: Ctx, iid: str): World = {
    val w480 = if ((w0.inc.get(iid).acceptedAt == 0)) {
      val w481 = if (not(w0.inc.get(iid).noReaction)) {
      val w482 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedGroup: (if ((c.before.lastAssignedGroup != "")) c.before.lastAssignedGroup else dutyGroupOf(w0.inc.get(iid).closedBy)) }) }
      w482
    } else w0
      val w483 = { ...w481, inc: w481.inc.set(iid, { ...w481.inc.get(iid), noReaction: true }) }
      w483
    } else w0
    w480
  }

  def e_close_14(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_15(w0: World, c: Ctx, iid: str): World = {
    val w484 = if (["false_alarm"].foldl(false, (acc, y485) => acc or y485 == w0.inc.get(iid).closeResultId)) {
      val w486 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_490 => not(isDone(x_490))).foldl([], (acc, x489) => acc.append(x489.id)).foldl(w0, (wf487, sId488) => wf487)
      w486
    } else w0
    w484
  }

  def e_close_16(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_17(w0: World, c: Ctx, iid: str): World = {
    val w491 = if (["false_alarm"].foldl(false, (acc, y492) => acc or y492 == w0.inc.get(iid).closeResultId)) {
      val w493 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_500 => not(isDone(x_500))).foldl([], (acc, x496) => acc.append(x496.id)).foldl(w0, (wf494, sId495) => {
      val lead_497 = (if ((wf494.inc.get(sId495).linkedTo != "")) { val ps_498 = incidentById(incs(w0), wf494.inc.get(sId495).linkedTo)  (if (((ps_498.length() > 0) and not(isDone(ps_498[0])))) addressee(ps_498[0]) else "") } else addressee(wf494.inc.get(sId495)))
      val w499 = if (((lead_497 != "") and (lead_497 != wf494.inc.get(iid).closedBy))) wf494 else wf494
      w499
    })
      w493
    } else w0
    w491
  }

  def e_close_18(w0: World, c: Ctx, iid: str): World = {

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
    val w16 = e_close_15(w15, c1, iid)
    val w17 = e_close_16(w16, c1, iid)
    val w18 = e_close_17(w17, c1, iid)
    val w19 = e_close_18(w18, c1, iid)
    w19
  }

  // reopen: manual → in_progress

  def ok_reopen(c: Ctx, iid: str): bool = all {
    Set("closed").contains(world.inc.get(iid).state),
    can(c.me, "incident:reopen"),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_501) => acc or ((s_501.id == agentState(c.me)) and s_501.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_502 = c.actor
    val w503 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_502 }) }
    w503
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w504 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_505 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w506 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w507 = { ...w506, inc: w506.inc.set(iid, { ...w506.inc.get(iid), linkedTo: "" }) }
      val w508 = { ...w507, inc: w507.inc.set(iid, { ...w507.inc.get(iid), linkedAt: 0 }) }
      val w509 = if (((ps_505.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w508 else w508
      val w510 = if (("workflow.journal.linked_reopened" != "")) {
      val w511 = ps_505.foldl([], (acc, x514) => acc.append(x514.id)).foldl(w509, (wf512, pId513) => wf512)
      w511
    } else w509
      w510
    } else {
      val w515 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w516 = { ...w515, inc: w515.inc.set(iid, { ...w515.inc.get(iid), linkedAt: 0 }) }
      w516
    }
    w504
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_517 = ""
    val w518 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_517 }) }
    w518
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_519 = ""
    val w520 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_519 }) }
    w520
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_521 = ""
    val w522 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_521 }) }
    w522
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_523 = ""
    val w524 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_523 }) }
    w524
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_525 = ""
    val w526 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_525 }) }
    w526
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val value_527 = 0
    val w528 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_527 }) }
    w528
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val value_529 = ""
    val w530 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_529 }) }
    w530
  }

  def e_reopen_10(w0: World, c: Ctx, iid: str): World = {
    val sec_531 = settings.limits.reopenResolutionSec
    val w532 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_531 > 0)) sec_531 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w533 = { ...w532, inc: w532.inc.set(iid, { ...w532.inc.get(iid), timers: w532.inc.get(iid).timers.set("resolution", { ...w532.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w534 = { ...w533, inc: w533.inc.set(iid, { ...w533.inc.get(iid), timers: w533.inc.get(iid).timers.set("resolution", { ...w533.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w534
  }

  def e_reopen_11(w0: World, c: Ctx, iid: str): World = {
    val w535 = if (timerDef("reaction").startsOnce) {
      val w536 = ec_pauseTimer(w0, c, iid, "reaction")
      w536
    } else {
      val w537 = if (true) {
      val w538 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w539 = { ...w538, inc: w538.inc.set(iid, { ...w538.inc.get(iid), timers: w538.inc.get(iid).timers.set("reaction", { ...w538.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w540 = { ...w539, inc: w539.inc.set(iid, { ...w539.inc.get(iid), timers: w539.inc.get(iid).timers.set("reaction", { ...w539.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w541 = { ...w540, inc: w540.inc.set(iid, { ...w540.inc.get(iid), timers: w540.inc.get(iid).timers.set("reaction", { ...w540.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w541
    } else {
      val w542 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_543 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w544 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_543) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w545 = { ...w544, inc: w544.inc.set(iid, { ...w544.inc.get(iid), timers: w544.inc.get(iid).timers.set("reaction", { ...w544.inc.get(iid).timers.get("reaction"), paused: keep_543 }) }) }
      val w546 = { ...w545, inc: w545.inc.set(iid, { ...w545.inc.get(iid), timers: w545.inc.get(iid).timers.set("reaction", { ...w545.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w547 = { ...w546, inc: w546.inc.set(iid, { ...w546.inc.get(iid), timers: w546.inc.get(iid).timers.set("reaction", { ...w546.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w547
    }
      w542
    }
      w537
    }
    w535
  }

  def e_reopen_12(w0: World, c: Ctx, iid: str): World = {

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
    val w12 = e_reopen_11(w11, c1, iid)
    val w13 = e_reopen_12(w12, c1, iid)
    w13
  }

  // comment: manual

  def ok_comment(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance", "in_progress", "on_hold", "closed", "linked").contains(world.inc.get(iid).state),
    can(c.me, "incident:comment"),
    not(settings.session.states.foldl(false, (acc, s_548) => acc or ((s_548.id == agentState(c.me)) and s_548.readOnly))),
    ((if (c.form.comment == "") 0 else 1) <= settings.limits.commentMaxLength),
    (c.form.files.length() <= settings.limits.commentMaxFiles),
    c.form.files.foldl(true, (acc, f_549) => acc and (f_549.size <= settings.limits.attachmentMaxBytes)),
    c.form.files.foldl(true, (acc, f_550) => acc and settings.limits.attachmentTypes.foldl(false, (acc, y551) => acc or y551 == f_550.mime)),
  }

  def e_comment_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_comment(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_comment_0(w0, c1, iid)
    w1
  }

  // change_priority: manual

  def ok_change_priority(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:priority"),
    not(settings.session.states.foldl(false, (acc, s_552) => acc or ((s_552.id == agentState(c.me)) and s_552.readOnly))),
    ((c.form.priority == "") or (priorityOf(c.form.priority) != world.inc.get(iid).priority)),
  }

  def e_change_priority_0(w0: World, c: Ctx, iid: str): World = {
    val value_553 = priorityOf(c.form.priority)
    val w554 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priority: value_553 }) }
    w554
  }

  def e_change_priority_1(w0: World, c: Ctx, iid: str): World = {
    val value_555 = true
    val w556 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priorityManual: value_555 }) }
    w556
  }

  def e_change_priority_2(w0: World, c: Ctx, iid: str): World = {
    val t_557 = w0.inc.get(iid).timers.get("reaction")
    val raw_558 = ((timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel") - timerSec(c.before, "reaction", "byEscalationLevel")) * 1000)
    val delta_559 = (if (((raw_558 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_560) => acc or (m_560.state == "linked")))) 0 else raw_558)
    val w561 = if ((((t_557.due != 0) and (t_557.due > c.now)) and (t_557.fired != t_557.due))) {
      val w562 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if (((t_557.due + delta_559) > c.now)) (t_557.due + delta_559) else c.now) }) }) }
      w562
    } else {
      val w563 = if ((((timerDef("reaction").pausable and (t_557.due == 0)) and t_557.paused) and (t_557.left > 0))) {
      val w564 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (((t_557.left + delta_559) > 0)) (t_557.left + delta_559) else 1) }) }) }
      w564
    } else w0
      w563
    }
    w561
  }

  def e_change_priority_3(w0: World, c: Ctx, iid: str): World = {
    val t_565 = w0.inc.get(iid).timers.get("resolution")
    val raw_566 = ((timerSec(w0.inc.get(iid), "resolution", "") - timerSec(c.before, "resolution", "")) * 1000)
    val delta_567 = (if (((raw_566 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_568) => acc or (m_568.state == "linked")))) 0 else raw_566)
    val w569 = if ((((t_565.due != 0) and (t_565.due > c.now)) and (t_565.fired != t_565.due))) {
      val w570 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((t_565.due + delta_567) > c.now)) (t_565.due + delta_567) else c.now) }) }) }
      w570
    } else {
      val w571 = if ((((timerDef("resolution").pausable and (t_565.due == 0)) and t_565.paused) and (t_565.left > 0))) {
      val w572 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((t_565.left + delta_567) > 0)) (t_565.left + delta_567) else 1) }) }) }
      w572
    } else w0
      w571
    }
    w569
  }

  def e_change_priority_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_change_priority(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_change_priority_0(w0, c1, iid)
    val w2 = e_change_priority_1(w1, c1, iid)
    val w3 = e_change_priority_2(w2, c1, iid)
    val w4 = e_change_priority_3(w3, c1, iid)
    val w5 = e_change_priority_4(w4, c1, iid)
    w5
  }

  // auto_escalate: timer → pending_acceptance

  def ok_auto_escalate(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == true),
    { val t_573 = world.inc.get(iid).timers.get("reaction")  (((t_573.due != 0) and (t_573.due <= c.now)) and (t_573.fired != t_573.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_574 = personOf(levelUpTarget(c.before))
    val w575 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_574 }) }
    w575
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_576 = groupOf(levelUpTarget(c.before))
    val w577 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_576 }) }
    val w578 = if ((group_576 != "")) {
      val w579 = { ...w577, inc: w577.inc.set(iid, { ...w577.inc.get(iid), lastAssignedGroup: group_576 }) }
      w579
    } else w577
    w578
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_580 = levelUpNumber(c.before)
    val w581 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_580 }) }
    w581
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w582 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w582
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w583 = if (not(timerDef("resolution").pausable)) {
      val w584 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w585 = { ...w584, inc: w584.inc.set(iid, { ...w584.inc.get(iid), timers: w584.inc.get(iid).timers.set("resolution", { ...w584.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w585
    } else {
      val w586 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w587 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w588 = { ...w587, inc: w587.inc.set(iid, { ...w587.inc.get(iid), timers: w587.inc.get(iid).timers.set("resolution", { ...w587.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w589 = { ...w588, inc: w588.inc.set(iid, { ...w588.inc.get(iid), timers: w588.inc.get(iid).timers.set("resolution", { ...w588.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w589
    } else w0
      w586
    }
    w583
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w590 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w591 = if (timerDef("reaction").startsOnce) {
      val w592 = ec_resumeTimer(w0, c, iid, "reaction")
      w592
    } else {
      val w593 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w594 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w595 = { ...w594, inc: w594.inc.set(iid, { ...w594.inc.get(iid), timers: w594.inc.get(iid).timers.set("reaction", { ...w594.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w596 = { ...w595, inc: w595.inc.set(iid, { ...w595.inc.get(iid), timers: w595.inc.get(iid).timers.set("reaction", { ...w595.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w596
    } else {
      val sec_597 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w598 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_597 < 0)) 0 else (c.now + (sec_597 * 1000))) }) }) }
      val w599 = { ...w598, inc: w598.inc.set(iid, { ...w598.inc.get(iid), timers: w598.inc.get(iid).timers.set("reaction", { ...w598.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w600 = { ...w599, inc: w599.inc.set(iid, { ...w599.inc.get(iid), timers: w599.inc.get(iid).timers.set("reaction", { ...w599.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w601 = { ...w600, inc: w600.inc.set(iid, { ...w600.inc.get(iid), timers: w600.inc.get(iid).timers.set("reaction", { ...w600.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w601
    }
      w593
    }
      w591
    }
    w590
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_602 = addressee(w0.inc.get(iid))
    val w603 = if (((whom_602 != "") and (whom_602 != c.actor))) w0 else w0
    w603
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
    { val t_604 = world.inc.get(iid).timers.get("reaction")  (((t_604.due != 0) and (t_604.due <= c.now)) and (t_604.fired != t_604.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_605 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w606 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_605) }) }
    val w607 = { ...w606, inc: w606.inc.set(iid, { ...w606.inc.get(iid), slaBreached: true }) }
    val w608 = groupMembersAt(incs(w0), w607.inc.get(iid), c.deadline).foldl([], (acc, x611) => acc.append(x611.id)).foldl(w607, (wf609, eId610) => {
      val w612 = { ...wf609, inc: wf609.inc.set(eId610, { ...wf609.inc.get(eId610), breaches: wf609.inc.get(eId610).breaches.append(breach_605) }) }
      val w613 = { ...w612, inc: w612.inc.set(eId610, { ...w612.inc.get(eId610), slaBreached: true }) }
      w613
    })
    w608
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w614 = if (timerDef("reaction").startsOnce) {
      val w615 = ec_pauseTimer(w0, c, iid, "reaction")
      w615
    } else {
      val w616 = if (false) {
      val w617 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w618 = { ...w617, inc: w617.inc.set(iid, { ...w617.inc.get(iid), timers: w617.inc.get(iid).timers.set("reaction", { ...w617.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w619 = { ...w618, inc: w618.inc.set(iid, { ...w618.inc.get(iid), timers: w618.inc.get(iid).timers.set("reaction", { ...w618.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w620 = { ...w619, inc: w619.inc.set(iid, { ...w619.inc.get(iid), timers: w619.inc.get(iid).timers.set("reaction", { ...w619.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w620
    } else {
      val w621 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_622 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w623 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_622) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w624 = { ...w623, inc: w623.inc.set(iid, { ...w623.inc.get(iid), timers: w623.inc.get(iid).timers.set("reaction", { ...w623.inc.get(iid).timers.get("reaction"), paused: keep_622 }) }) }
      val w625 = { ...w624, inc: w624.inc.set(iid, { ...w624.inc.get(iid), timers: w624.inc.get(iid).timers.set("reaction", { ...w624.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w626 = { ...w625, inc: w625.inc.set(iid, { ...w625.inc.get(iid), timers: w625.inc.get(iid).timers.set("reaction", { ...w625.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w626
    }
      w621
    }
      w616
    }
    w614
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_627 = settings.alerts.target
    val w628 = if (((whom_627 != "") and (whom_627 != c.actor))) w0 else w0
    w628
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
    { val t_629 = world.inc.get(iid).timers.get("reaction")  (((t_629.due != 0) and (t_629.due <= c.now)) and (t_629.fired != t_629.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_630 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w631 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_630) }) }
    val w632 = { ...w631, inc: w631.inc.set(iid, { ...w631.inc.get(iid), slaBreached: true }) }
    val w633 = groupMembersAt(incs(w0), w632.inc.get(iid), c.deadline).foldl([], (acc, x636) => acc.append(x636.id)).foldl(w632, (wf634, eId635) => {
      val w637 = { ...wf634, inc: wf634.inc.set(eId635, { ...wf634.inc.get(eId635), breaches: wf634.inc.get(eId635).breaches.append(breach_630) }) }
      val w638 = { ...w637, inc: w637.inc.set(eId635, { ...w637.inc.get(eId635), slaBreached: true }) }
      w638
    })
    w633
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w639 = if (timerDef("reaction").startsOnce) {
      val w640 = ec_pauseTimer(w0, c, iid, "reaction")
      w640
    } else {
      val w641 = if (false) {
      val w642 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w643 = { ...w642, inc: w642.inc.set(iid, { ...w642.inc.get(iid), timers: w642.inc.get(iid).timers.set("reaction", { ...w642.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w644 = { ...w643, inc: w643.inc.set(iid, { ...w643.inc.get(iid), timers: w643.inc.get(iid).timers.set("reaction", { ...w643.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w645 = { ...w644, inc: w644.inc.set(iid, { ...w644.inc.get(iid), timers: w644.inc.get(iid).timers.set("reaction", { ...w644.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w645
    } else {
      val w646 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_647 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w648 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_647) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w649 = { ...w648, inc: w648.inc.set(iid, { ...w648.inc.get(iid), timers: w648.inc.get(iid).timers.set("reaction", { ...w648.inc.get(iid).timers.get("reaction"), paused: keep_647 }) }) }
      val w650 = { ...w649, inc: w649.inc.set(iid, { ...w649.inc.get(iid), timers: w649.inc.get(iid).timers.set("reaction", { ...w649.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w651 = { ...w650, inc: w650.inc.set(iid, { ...w650.inc.get(iid), timers: w650.inc.get(iid).timers.set("reaction", { ...w650.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w651
    }
      w646
    }
      w641
    }
    w639
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_652 = settings.alerts.target
    val w653 = if (((whom_652 != "") and (whom_652 != c.actor))) w0 else w0
    w653
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
    { val t_654 = world.inc.get(iid).timers.get("resolution")  (((t_654.due != 0) and (t_654.due <= c.now)) and (t_654.fired != t_654.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_655 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w656 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_655) }) }
    val w657 = { ...w656, inc: w656.inc.set(iid, { ...w656.inc.get(iid), slaBreached: true }) }
    val w658 = groupMembersAt(incs(w0), w657.inc.get(iid), c.deadline).foldl([], (acc, x661) => acc.append(x661.id)).foldl(w657, (wf659, eId660) => {
      val w662 = { ...wf659, inc: wf659.inc.set(eId660, { ...wf659.inc.get(eId660), breaches: wf659.inc.get(eId660).breaches.append(breach_655) }) }
      val w663 = { ...w662, inc: w662.inc.set(eId660, { ...w662.inc.get(eId660), slaBreached: true }) }
      w663
    })
    w658
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_664 = settings.alerts.target
    val w665 = if (((whom_664 != "") and (whom_664 != c.actor))) w0 else w0
    w665
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
    { val t_666 = world.inc.get(iid).timers.get("resolution")  (((t_666.due != 0) and (t_666.due <= c.now)) and (t_666.fired != t_666.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_667 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w668 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_667) }) }
    val w669 = { ...w668, inc: w668.inc.set(iid, { ...w668.inc.get(iid), slaBreached: true }) }
    val w670 = groupMembersAt(incs(w0), w669.inc.get(iid), c.deadline).foldl([], (acc, x673) => acc.append(x673.id)).foldl(w669, (wf671, eId672) => {
      val w674 = { ...wf671, inc: wf671.inc.set(eId672, { ...wf671.inc.get(eId672), breaches: wf671.inc.get(eId672).breaches.append(breach_667) }) }
      val w675 = { ...w674, inc: w674.inc.set(eId672, { ...w674.inc.get(eId672), slaBreached: true }) }
      w675
    })
    w670
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_676 = personOf(levelUpTarget(c.before))
    val w677 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_676 }) }
    w677
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_678 = groupOf(levelUpTarget(c.before))
    val w679 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_678 }) }
    val w680 = if ((group_678 != "")) {
      val w681 = { ...w679, inc: w679.inc.set(iid, { ...w679.inc.get(iid), lastAssignedGroup: group_678 }) }
      w681
    } else w679
    w680
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_682 = levelUpNumber(c.before)
    val w683 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_682 }) }
    w683
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w684 = if (not(timerDef("resolution").pausable)) {
      val w685 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w686 = { ...w685, inc: w685.inc.set(iid, { ...w685.inc.get(iid), timers: w685.inc.get(iid).timers.set("resolution", { ...w685.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w686
    } else {
      val w687 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w688 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w689 = { ...w688, inc: w688.inc.set(iid, { ...w688.inc.get(iid), timers: w688.inc.get(iid).timers.set("resolution", { ...w688.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w690 = { ...w689, inc: w689.inc.set(iid, { ...w689.inc.get(iid), timers: w689.inc.get(iid).timers.set("resolution", { ...w689.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w690
    } else w0
      w687
    }
    w684
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w691 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w692 = if (timerDef("reaction").startsOnce) {
      val w693 = ec_resumeTimer(w0, c, iid, "reaction")
      w693
    } else {
      val w694 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w695 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w696 = { ...w695, inc: w695.inc.set(iid, { ...w695.inc.get(iid), timers: w695.inc.get(iid).timers.set("reaction", { ...w695.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w697 = { ...w696, inc: w696.inc.set(iid, { ...w696.inc.get(iid), timers: w696.inc.get(iid).timers.set("reaction", { ...w696.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w697
    } else {
      val sec_698 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w699 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_698 < 0)) 0 else (c.now + (sec_698 * 1000))) }) }) }
      val w700 = { ...w699, inc: w699.inc.set(iid, { ...w699.inc.get(iid), timers: w699.inc.get(iid).timers.set("reaction", { ...w699.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w701 = { ...w700, inc: w700.inc.set(iid, { ...w700.inc.get(iid), timers: w700.inc.get(iid).timers.set("reaction", { ...w700.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w702 = { ...w701, inc: w701.inc.set(iid, { ...w701.inc.get(iid), timers: w701.inc.get(iid).timers.set("reaction", { ...w701.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w702
    }
      w694
    }
      w692
    }
    w691
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_703 = c.before.owner
    val w704 = if (((whom_703 != "") and (whom_703 != c.actor))) w0 else w0
    w704
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_705 = addressee(w0.inc.get(iid))
    val w706 = if (((whom_705 != "") and (whom_705 != c.actor))) w0 else w0
    w706
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
    { val t_707 = world.inc.get(iid).timers.get("resolution")  (((t_707.due != 0) and (t_707.due <= c.now)) and (t_707.fired != t_707.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_708 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w709 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_708) }) }
    val w710 = { ...w709, inc: w709.inc.set(iid, { ...w709.inc.get(iid), slaBreached: true }) }
    val w711 = groupMembersAt(incs(w0), w710.inc.get(iid), c.deadline).foldl([], (acc, x714) => acc.append(x714.id)).foldl(w710, (wf712, eId713) => {
      val w715 = { ...wf712, inc: wf712.inc.set(eId713, { ...wf712.inc.get(eId713), breaches: wf712.inc.get(eId713).breaches.append(breach_708) }) }
      val w716 = { ...w715, inc: w715.inc.set(eId713, { ...w715.inc.get(eId713), slaBreached: true }) }
      w716
    })
    w711
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_717 = settings.alerts.target
    val w718 = if (((whom_717 != "") and (whom_717 != c.actor))) w0 else w0
    w718
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
    { val t_719 = world.inc.get(iid).timers.get("hold")  (((t_719.due != 0) and (t_719.due <= c.now)) and (t_719.fired != t_719.due)) },
    not(["break", "no_link"].foldl(false, (acc, y720) => acc or y720 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_721 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w722 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_721) }) }
    val w723 = { ...w722, inc: w722.inc.set(iid, { ...w722.inc.get(iid), slaBreached: true }) }
    val w724 = groupMembersAt(incs(w0), w723.inc.get(iid), c.deadline).foldl([], (acc, x727) => acc.append(x727.id)).foldl(w723, (wf725, eId726) => {
      val w728 = { ...wf725, inc: wf725.inc.set(eId726, { ...wf725.inc.get(eId726), breaches: wf725.inc.get(eId726).breaches.append(breach_721) }) }
      val w729 = { ...w728, inc: w728.inc.set(eId726, { ...w728.inc.get(eId726), slaBreached: true }) }
      w729
    })
    w724
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_730 = settings.alerts.target
    val w731 = if (((whom_730 != "") and (whom_730 != c.actor))) w0 else w0
    w731
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
    { val t_732 = world.inc.get(iid).timers.get("hold")  (((t_732.due != 0) and (t_732.due <= c.now)) and (t_732.fired != t_732.due)) },
    ["break"].foldl(false, (acc, y733) => acc or y733 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_734 = ""
    val w735 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_734 }) }
    w735
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w736 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w736
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w737 = if (timerDef("hold").startsOnce) {
      val w738 = ec_pauseTimer(w0, c, iid, "hold")
      w738
    } else {
      val w739 = if (false) {
      val w740 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w741 = { ...w740, inc: w740.inc.set(iid, { ...w740.inc.get(iid), timers: w740.inc.get(iid).timers.set("hold", { ...w740.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w742 = { ...w741, inc: w741.inc.set(iid, { ...w741.inc.get(iid), timers: w741.inc.get(iid).timers.set("hold", { ...w741.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w743 = { ...w742, inc: w742.inc.set(iid, { ...w742.inc.get(iid), timers: w742.inc.get(iid).timers.set("hold", { ...w742.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w743
    } else {
      val w744 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_745 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w746 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_745) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w747 = { ...w746, inc: w746.inc.set(iid, { ...w746.inc.get(iid), timers: w746.inc.get(iid).timers.set("hold", { ...w746.inc.get(iid).timers.get("hold"), paused: keep_745 }) }) }
      val w748 = { ...w747, inc: w747.inc.set(iid, { ...w747.inc.get(iid), timers: w747.inc.get(iid).timers.set("hold", { ...w747.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w749 = { ...w748, inc: w748.inc.set(iid, { ...w748.inc.get(iid), timers: w748.inc.get(iid).timers.set("hold", { ...w748.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w749
    }
      w744
    }
      w739
    }
    w737
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w750 = if (not(timerDef("resolution").pausable)) {
      val w751 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w752 = { ...w751, inc: w751.inc.set(iid, { ...w751.inc.get(iid), timers: w751.inc.get(iid).timers.set("resolution", { ...w751.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w752
    } else {
      val w753 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w754 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w755 = { ...w754, inc: w754.inc.set(iid, { ...w754.inc.get(iid), timers: w754.inc.get(iid).timers.set("resolution", { ...w754.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w756 = { ...w755, inc: w755.inc.set(iid, { ...w755.inc.get(iid), timers: w755.inc.get(iid).timers.set("resolution", { ...w755.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w756
    } else w0
      w753
    }
    w750
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w757 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w758 = if (timerDef("reaction").startsOnce) {
      val w759 = ec_resumeTimer(w0, c, iid, "reaction")
      w759
    } else {
      val w760 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w761 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w762 = { ...w761, inc: w761.inc.set(iid, { ...w761.inc.get(iid), timers: w761.inc.get(iid).timers.set("reaction", { ...w761.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w763 = { ...w762, inc: w762.inc.set(iid, { ...w762.inc.get(iid), timers: w762.inc.get(iid).timers.set("reaction", { ...w762.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w763
    } else {
      val sec_764 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w765 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_764 < 0)) 0 else (c.now + (sec_764 * 1000))) }) }) }
      val w766 = { ...w765, inc: w765.inc.set(iid, { ...w765.inc.get(iid), timers: w765.inc.get(iid).timers.set("reaction", { ...w765.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w767 = { ...w766, inc: w766.inc.set(iid, { ...w766.inc.get(iid), timers: w766.inc.get(iid).timers.set("reaction", { ...w766.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w768 = { ...w767, inc: w767.inc.set(iid, { ...w767.inc.get(iid), timers: w767.inc.get(iid).timers.set("reaction", { ...w767.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w768
    }
      w760
    }
      w758
    }
    w757
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
    val reason_769 = "break"
    val w770 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_769 }) }
    w770
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w771 = if (not(timerDef("resolution").pausable)) {
      val w772 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w773 = { ...w772, inc: w772.inc.set(iid, { ...w772.inc.get(iid), timers: w772.inc.get(iid).timers.set("resolution", { ...w772.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w773
    } else {
      val w774 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w775 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w776 = { ...w775, inc: w775.inc.set(iid, { ...w775.inc.get(iid), timers: w775.inc.get(iid).timers.set("resolution", { ...w775.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w777 = { ...w776, inc: w776.inc.set(iid, { ...w776.inc.get(iid), timers: w776.inc.get(iid).timers.set("resolution", { ...w776.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w777
    } else w0
      w774
    }
    w771
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w778 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w779 = if (timerDef("hold").startsOnce) {
      val w780 = ec_resumeTimer(w0, c, iid, "hold")
      w780
    } else {
      val w781 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w782 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w783 = { ...w782, inc: w782.inc.set(iid, { ...w782.inc.get(iid), timers: w782.inc.get(iid).timers.set("hold", { ...w782.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w784 = { ...w783, inc: w783.inc.set(iid, { ...w783.inc.get(iid), timers: w783.inc.get(iid).timers.set("hold", { ...w783.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w784
    } else {
      val sec_785 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w786 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_785 < 0)) 0 else (c.now + (sec_785 * 1000))) }) }) }
      val w787 = { ...w786, inc: w786.inc.set(iid, { ...w786.inc.get(iid), timers: w786.inc.get(iid).timers.set("hold", { ...w786.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w788 = { ...w787, inc: w787.inc.set(iid, { ...w787.inc.get(iid), timers: w787.inc.get(iid).timers.set("hold", { ...w787.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w789 = { ...w788, inc: w788.inc.set(iid, { ...w788.inc.get(iid), timers: w788.inc.get(iid).timers.set("hold", { ...w788.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w789
    }
      w781
    }
      w779
    }
    w778
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
    val reason_790 = "no_link"
    val w791 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_790 }) }
    w791
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w792 = if (not(timerDef("resolution").pausable)) {
      val w793 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w794 = { ...w793, inc: w793.inc.set(iid, { ...w793.inc.get(iid), timers: w793.inc.get(iid).timers.set("resolution", { ...w793.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w794
    } else {
      val w795 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w796 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w797 = { ...w796, inc: w796.inc.set(iid, { ...w796.inc.get(iid), timers: w796.inc.get(iid).timers.set("resolution", { ...w796.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w798 = { ...w797, inc: w797.inc.set(iid, { ...w797.inc.get(iid), timers: w797.inc.get(iid).timers.set("resolution", { ...w797.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w798
    } else w0
      w795
    }
    w792
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w799 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w800 = if (timerDef("hold").startsOnce) {
      val w801 = ec_resumeTimer(w0, c, iid, "hold")
      w801
    } else {
      val w802 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w803 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w804 = { ...w803, inc: w803.inc.set(iid, { ...w803.inc.get(iid), timers: w803.inc.get(iid).timers.set("hold", { ...w803.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w805 = { ...w804, inc: w804.inc.set(iid, { ...w804.inc.get(iid), timers: w804.inc.get(iid).timers.set("hold", { ...w804.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w805
    } else {
      val sec_806 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w807 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_806 < 0)) 0 else (c.now + (sec_806 * 1000))) }) }) }
      val w808 = { ...w807, inc: w807.inc.set(iid, { ...w807.inc.get(iid), timers: w807.inc.get(iid).timers.set("hold", { ...w807.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w809 = { ...w808, inc: w808.inc.set(iid, { ...w808.inc.get(iid), timers: w808.inc.get(iid).timers.set("hold", { ...w808.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w810 = { ...w809, inc: w809.inc.set(iid, { ...w809.inc.get(iid), timers: w809.inc.get(iid).timers.set("hold", { ...w809.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w810
    }
      w802
    }
      w800
    }
    w799
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_811 = settings.alerts.target
    val w812 = if (((whom_811 != "") and (whom_811 != c.actor))) w0 else w0
    w812
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
    ["break", "no_link"].foldl(false, (acc, y813) => acc or y813 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_814 = ""
    val w815 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_814 }) }
    w815
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w816 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w816
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w817 = if (timerDef("hold").startsOnce) {
      val w818 = ec_pauseTimer(w0, c, iid, "hold")
      w818
    } else {
      val w819 = if (false) {
      val w820 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w821 = { ...w820, inc: w820.inc.set(iid, { ...w820.inc.get(iid), timers: w820.inc.get(iid).timers.set("hold", { ...w820.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w822 = { ...w821, inc: w821.inc.set(iid, { ...w821.inc.get(iid), timers: w821.inc.get(iid).timers.set("hold", { ...w821.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w823 = { ...w822, inc: w822.inc.set(iid, { ...w822.inc.get(iid), timers: w822.inc.get(iid).timers.set("hold", { ...w822.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w823
    } else {
      val w824 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_825 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w826 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_825) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w827 = { ...w826, inc: w826.inc.set(iid, { ...w826.inc.get(iid), timers: w826.inc.get(iid).timers.set("hold", { ...w826.inc.get(iid).timers.get("hold"), paused: keep_825 }) }) }
      val w828 = { ...w827, inc: w827.inc.set(iid, { ...w827.inc.get(iid), timers: w827.inc.get(iid).timers.set("hold", { ...w827.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w829 = { ...w828, inc: w828.inc.set(iid, { ...w828.inc.get(iid), timers: w828.inc.get(iid).timers.set("hold", { ...w828.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w829
    }
      w824
    }
      w819
    }
    w817
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w830 = if (not(timerDef("resolution").pausable)) {
      val w831 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w832 = { ...w831, inc: w831.inc.set(iid, { ...w831.inc.get(iid), timers: w831.inc.get(iid).timers.set("resolution", { ...w831.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w832
    } else {
      val w833 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w834 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w835 = { ...w834, inc: w834.inc.set(iid, { ...w834.inc.get(iid), timers: w834.inc.get(iid).timers.set("resolution", { ...w834.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w836 = { ...w835, inc: w835.inc.set(iid, { ...w835.inc.get(iid), timers: w835.inc.get(iid).timers.set("resolution", { ...w835.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w836
    } else w0
      w833
    }
    w830
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w837 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w838 = if (timerDef("reaction").startsOnce) {
      val w839 = ec_resumeTimer(w0, c, iid, "reaction")
      w839
    } else {
      val w840 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w841 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w842 = { ...w841, inc: w841.inc.set(iid, { ...w841.inc.get(iid), timers: w841.inc.get(iid).timers.set("reaction", { ...w841.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w843 = { ...w842, inc: w842.inc.set(iid, { ...w842.inc.get(iid), timers: w842.inc.get(iid).timers.set("reaction", { ...w842.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w843
    } else {
      val sec_844 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w845 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_844 < 0)) 0 else (c.now + (sec_844 * 1000))) }) }) }
      val w846 = { ...w845, inc: w845.inc.set(iid, { ...w845.inc.get(iid), timers: w845.inc.get(iid).timers.set("reaction", { ...w845.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w847 = { ...w846, inc: w846.inc.set(iid, { ...w846.inc.get(iid), timers: w846.inc.get(iid).timers.set("reaction", { ...w846.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w848 = { ...w847, inc: w847.inc.set(iid, { ...w847.inc.get(iid), timers: w847.inc.get(iid).timers.set("reaction", { ...w847.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w848
    }
      w840
    }
      w838
    }
    w837
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
    { val t_849 = world.inc.get(iid).timers.get("hold")  (((t_849.due != 0) and (t_849.due <= c.now)) and (t_849.fired != t_849.due)) },
    ["no_link"].foldl(false, (acc, y850) => acc or y850 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_851 = ""
    val w852 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_851 }) }
    w852
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w853 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w853
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w854 = if (timerDef("hold").startsOnce) {
      val w855 = ec_pauseTimer(w0, c, iid, "hold")
      w855
    } else {
      val w856 = if (false) {
      val w857 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w858 = { ...w857, inc: w857.inc.set(iid, { ...w857.inc.get(iid), timers: w857.inc.get(iid).timers.set("hold", { ...w857.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w859 = { ...w858, inc: w858.inc.set(iid, { ...w858.inc.get(iid), timers: w858.inc.get(iid).timers.set("hold", { ...w858.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w860 = { ...w859, inc: w859.inc.set(iid, { ...w859.inc.get(iid), timers: w859.inc.get(iid).timers.set("hold", { ...w859.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w860
    } else {
      val w861 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_862 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w863 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_862) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w864 = { ...w863, inc: w863.inc.set(iid, { ...w863.inc.get(iid), timers: w863.inc.get(iid).timers.set("hold", { ...w863.inc.get(iid).timers.get("hold"), paused: keep_862 }) }) }
      val w865 = { ...w864, inc: w864.inc.set(iid, { ...w864.inc.get(iid), timers: w864.inc.get(iid).timers.set("hold", { ...w864.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w866 = { ...w865, inc: w865.inc.set(iid, { ...w865.inc.get(iid), timers: w865.inc.get(iid).timers.set("hold", { ...w865.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w866
    }
      w861
    }
      w856
    }
    w854
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w867 = if (not(timerDef("resolution").pausable)) {
      val w868 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w869 = { ...w868, inc: w868.inc.set(iid, { ...w868.inc.get(iid), timers: w868.inc.get(iid).timers.set("resolution", { ...w868.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w869
    } else {
      val w870 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w871 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w872 = { ...w871, inc: w871.inc.set(iid, { ...w871.inc.get(iid), timers: w871.inc.get(iid).timers.set("resolution", { ...w871.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w873 = { ...w872, inc: w872.inc.set(iid, { ...w872.inc.get(iid), timers: w872.inc.get(iid).timers.set("resolution", { ...w872.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w873
    } else w0
      w870
    }
    w867
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w874 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w875 = if (timerDef("reaction").startsOnce) {
      val w876 = ec_resumeTimer(w0, c, iid, "reaction")
      w876
    } else {
      val w877 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w878 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w879 = { ...w878, inc: w878.inc.set(iid, { ...w878.inc.get(iid), timers: w878.inc.get(iid).timers.set("reaction", { ...w878.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w880 = { ...w879, inc: w879.inc.set(iid, { ...w879.inc.get(iid), timers: w879.inc.get(iid).timers.set("reaction", { ...w879.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w880
    } else {
      val sec_881 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w882 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_881 < 0)) 0 else (c.now + (sec_881 * 1000))) }) }) }
      val w883 = { ...w882, inc: w882.inc.set(iid, { ...w882.inc.get(iid), timers: w882.inc.get(iid).timers.set("reaction", { ...w882.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w884 = { ...w883, inc: w883.inc.set(iid, { ...w883.inc.get(iid), timers: w883.inc.get(iid).timers.set("reaction", { ...w883.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w885 = { ...w884, inc: w884.inc.set(iid, { ...w884.inc.get(iid), timers: w884.inc.get(iid).timers.set("reaction", { ...w884.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w885
    }
      w877
    }
      w875
    }
    w874
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
    val group_886 = dutyGroupOf(w0.inc.get(iid).owner)
    val w887 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_886 }) }
    val w888 = if ((group_886 != "")) {
      val w889 = { ...w887, inc: w887.inc.set(iid, { ...w887.inc.get(iid), lastAssignedGroup: group_886 }) }
      w889
    } else w887
    w888
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_890 = ""
    val w891 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_890 }) }
    w891
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_892 = addressee(w0.inc.get(iid))
    val w893 = if (((whom_892 != "") and (whom_892 != c.actor))) w0 else w0
    w893
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
    val who_894 = ""
    val w895 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_894 }) }
    w895
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
    val who_896 = ""
    val w897 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_896 }) }
    w897
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w898 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w898
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w899 = if (timerDef("hold").startsOnce) {
      val w900 = ec_pauseTimer(w0, c, iid, "hold")
      w900
    } else {
      val w901 = if (false) {
      val w902 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w903 = { ...w902, inc: w902.inc.set(iid, { ...w902.inc.get(iid), timers: w902.inc.get(iid).timers.set("hold", { ...w902.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w904 = { ...w903, inc: w903.inc.set(iid, { ...w903.inc.get(iid), timers: w903.inc.get(iid).timers.set("hold", { ...w903.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w905 = { ...w904, inc: w904.inc.set(iid, { ...w904.inc.get(iid), timers: w904.inc.get(iid).timers.set("hold", { ...w904.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w905
    } else {
      val w906 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_907 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w908 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_907) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w909 = { ...w908, inc: w908.inc.set(iid, { ...w908.inc.get(iid), timers: w908.inc.get(iid).timers.set("hold", { ...w908.inc.get(iid).timers.get("hold"), paused: keep_907 }) }) }
      val w910 = { ...w909, inc: w909.inc.set(iid, { ...w909.inc.get(iid), timers: w909.inc.get(iid).timers.set("hold", { ...w909.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w911 = { ...w910, inc: w910.inc.set(iid, { ...w910.inc.get(iid), timers: w910.inc.get(iid).timers.set("hold", { ...w910.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w911
    }
      w906
    }
      w901
    }
    w899
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w912 = if (not(timerDef("resolution").pausable)) {
      val w913 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w914 = { ...w913, inc: w913.inc.set(iid, { ...w913.inc.get(iid), timers: w913.inc.get(iid).timers.set("resolution", { ...w913.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w914
    } else {
      val w915 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w916 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w917 = { ...w916, inc: w916.inc.set(iid, { ...w916.inc.get(iid), timers: w916.inc.get(iid).timers.set("resolution", { ...w916.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w918 = { ...w917, inc: w917.inc.set(iid, { ...w917.inc.get(iid), timers: w917.inc.get(iid).timers.set("resolution", { ...w917.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w918
    } else w0
      w915
    }
    w912
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w919 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w920 = if (timerDef("reaction").startsOnce) {
      val w921 = ec_resumeTimer(w0, c, iid, "reaction")
      w921
    } else {
      val w922 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w923 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w924 = { ...w923, inc: w923.inc.set(iid, { ...w923.inc.get(iid), timers: w923.inc.get(iid).timers.set("reaction", { ...w923.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w925 = { ...w924, inc: w924.inc.set(iid, { ...w924.inc.get(iid), timers: w924.inc.get(iid).timers.set("reaction", { ...w924.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w925
    } else {
      val sec_926 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w927 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_926 < 0)) 0 else (c.now + (sec_926 * 1000))) }) }) }
      val w928 = { ...w927, inc: w927.inc.set(iid, { ...w927.inc.get(iid), timers: w927.inc.get(iid).timers.set("reaction", { ...w927.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w929 = { ...w928, inc: w928.inc.set(iid, { ...w928.inc.get(iid), timers: w928.inc.get(iid).timers.set("reaction", { ...w928.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w930 = { ...w929, inc: w929.inc.set(iid, { ...w929.inc.get(iid), timers: w929.inc.get(iid).timers.set("reaction", { ...w929.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w930
    }
      w922
    }
      w920
    }
    w919
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
    val who_931 = ""
    val w932 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_931 }) }
    w932
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_933 = ""
    val w934 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_933 }) }
    val w935 = if ((group_933 != "")) {
      val w936 = { ...w934, inc: w934.inc.set(iid, { ...w934.inc.get(iid), lastAssignedGroup: group_933 }) }
      w936
    } else w934
    w935
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w937 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w937
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w938 = if (timerDef("hold").startsOnce) {
      val w939 = ec_pauseTimer(w0, c, iid, "hold")
      w939
    } else {
      val w940 = if (false) {
      val w941 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w942 = { ...w941, inc: w941.inc.set(iid, { ...w941.inc.get(iid), timers: w941.inc.get(iid).timers.set("hold", { ...w941.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w943 = { ...w942, inc: w942.inc.set(iid, { ...w942.inc.get(iid), timers: w942.inc.get(iid).timers.set("hold", { ...w942.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w944 = { ...w943, inc: w943.inc.set(iid, { ...w943.inc.get(iid), timers: w943.inc.get(iid).timers.set("hold", { ...w943.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w944
    } else {
      val w945 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_946 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w947 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_946) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w948 = { ...w947, inc: w947.inc.set(iid, { ...w947.inc.get(iid), timers: w947.inc.get(iid).timers.set("hold", { ...w947.inc.get(iid).timers.get("hold"), paused: keep_946 }) }) }
      val w949 = { ...w948, inc: w948.inc.set(iid, { ...w948.inc.get(iid), timers: w948.inc.get(iid).timers.set("hold", { ...w948.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w950 = { ...w949, inc: w949.inc.set(iid, { ...w949.inc.get(iid), timers: w949.inc.get(iid).timers.set("hold", { ...w949.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w950
    }
      w945
    }
      w940
    }
    w938
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w951 = if (not(timerDef("resolution").pausable)) {
      val w952 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w953 = { ...w952, inc: w952.inc.set(iid, { ...w952.inc.get(iid), timers: w952.inc.get(iid).timers.set("resolution", { ...w952.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w953
    } else {
      val w954 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w955 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w956 = { ...w955, inc: w955.inc.set(iid, { ...w955.inc.get(iid), timers: w955.inc.get(iid).timers.set("resolution", { ...w955.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w957 = { ...w956, inc: w956.inc.set(iid, { ...w956.inc.get(iid), timers: w956.inc.get(iid).timers.set("resolution", { ...w956.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w957
    } else w0
      w954
    }
    w951
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w958 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w959 = if (timerDef("reaction").startsOnce) {
      val w960 = ec_resumeTimer(w0, c, iid, "reaction")
      w960
    } else {
      val w961 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w962 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w963 = { ...w962, inc: w962.inc.set(iid, { ...w962.inc.get(iid), timers: w962.inc.get(iid).timers.set("reaction", { ...w962.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w964 = { ...w963, inc: w963.inc.set(iid, { ...w963.inc.get(iid), timers: w963.inc.get(iid).timers.set("reaction", { ...w963.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w964
    } else {
      val sec_965 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w966 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_965 < 0)) 0 else (c.now + (sec_965 * 1000))) }) }) }
      val w967 = { ...w966, inc: w966.inc.set(iid, { ...w966.inc.get(iid), timers: w966.inc.get(iid).timers.set("reaction", { ...w966.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w968 = { ...w967, inc: w967.inc.set(iid, { ...w967.inc.get(iid), timers: w967.inc.get(iid).timers.set("reaction", { ...w967.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w969 = { ...w968, inc: w968.inc.set(iid, { ...w968.inc.get(iid), timers: w968.inc.get(iid).timers.set("reaction", { ...w968.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w969
    }
      w961
    }
      w959
    }
    w958
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_970 = settings.alerts.target
    val w971 = if (((whom_970 != "") and (whom_970 != c.actor))) w0 else w0
    w971
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
    val who_972 = ""
    val w973 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_972 }) }
    w973
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_974 = ""
    val w975 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_974 }) }
    val w976 = if ((group_974 != "")) {
      val w977 = { ...w975, inc: w975.inc.set(iid, { ...w975.inc.get(iid), lastAssignedGroup: group_974 }) }
      w977
    } else w975
    w976
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w978 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w979 = if (timerDef("reaction").startsOnce) {
      val w980 = ec_resumeTimer(w0, c, iid, "reaction")
      w980
    } else {
      val w981 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w982 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w983 = { ...w982, inc: w982.inc.set(iid, { ...w982.inc.get(iid), timers: w982.inc.get(iid).timers.set("reaction", { ...w982.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w984 = { ...w983, inc: w983.inc.set(iid, { ...w983.inc.get(iid), timers: w983.inc.get(iid).timers.set("reaction", { ...w983.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w984
    } else {
      val sec_985 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w986 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_985 < 0)) 0 else (c.now + (sec_985 * 1000))) }) }) }
      val w987 = { ...w986, inc: w986.inc.set(iid, { ...w986.inc.get(iid), timers: w986.inc.get(iid).timers.set("reaction", { ...w986.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w988 = { ...w987, inc: w987.inc.set(iid, { ...w987.inc.get(iid), timers: w987.inc.get(iid).timers.set("reaction", { ...w987.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w989 = { ...w988, inc: w988.inc.set(iid, { ...w988.inc.get(iid), timers: w988.inc.get(iid).timers.set("reaction", { ...w988.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w989
    }
      w981
    }
      w979
    }
    w978
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_990 = settings.alerts.target
    val w991 = if (((whom_990 != "") and (whom_990 != c.actor))) w0 else w0
    w991
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
    not(settings.session.states.foldl(false, (acc, s_992) => acc or ((s_992.id == agentState(c.me)) and s_992.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_993 = incidentById(incs(world), c.form.primaryId)  ((((ps_993.length() > 0) and (ps_993[0].id != world.inc.get(iid).id)) and (ps_993[0].linkedTo == "")) and ((ps_993[0].state == "new") or ((ps_993[0].state == "in_progress") and (ps_993[0].owner == c.me)))) },
    { val ps_994 = incidentById(incs(world), c.form.primaryId)  ((ps_994.length() > 0) and (ps_994[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w995 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w995
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_996 = incidentById(incs(w0), c.form.primaryId)
    val w997 = if ((ps_996.length() > 0)) {
      val w998 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_1005 => not(isDone(e_1005))).foldl([], (acc, x1001) => acc.append(x1001.id)).foldl(w0, (wf999, cId1000) => {
      val w1002 = { ...wf999, inc: wf999.inc.set(cId1000, { ...wf999.inc.get(cId1000), leftGroup: { primaryId: wf999.inc.get(cId1000).linkedTo, linkedAt: wf999.inc.get(cId1000).linkedAt, at: c.now } }) }
      val w1003 = { ...w1002, inc: w1002.inc.set(cId1000, { ...w1002.inc.get(cId1000), linkedTo: ps_996[0].id }) }
      val w1004 = { ...w1003, inc: w1003.inc.set(cId1000, { ...w1003.inc.get(cId1000), linkedAt: c.now }) }
      w1004
    })
      w998
    } else w0
    w997
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_1006 = c.form.primaryId
    val w1007 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_1006 }) }
    val w1008 = { ...w1007, inc: w1007.inc.set(iid, { ...w1007.inc.get(iid), linkedAt: c.now }) }
    w1008
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_1009 = ""
    val w1010 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_1009 }) }
    w1010
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_1011 = ""
    val w1012 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_1011 }) }
    val w1013 = if ((group_1011 != "")) {
      val w1014 = { ...w1012, inc: w1012.inc.set(iid, { ...w1012.inc.get(iid), lastAssignedGroup: group_1011 }) }
      w1014
    } else w1012
    w1013
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w1015 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w1015
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w1016 = if (timerDef("reaction").startsOnce) {
      val w1017 = ec_pauseTimer(w0, c, iid, "reaction")
      w1017
    } else {
      val w1018 = if (false) {
      val w1019 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w1020 = { ...w1019, inc: w1019.inc.set(iid, { ...w1019.inc.get(iid), timers: w1019.inc.get(iid).timers.set("reaction", { ...w1019.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1021 = { ...w1020, inc: w1020.inc.set(iid, { ...w1020.inc.get(iid), timers: w1020.inc.get(iid).timers.set("reaction", { ...w1020.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w1022 = { ...w1021, inc: w1021.inc.set(iid, { ...w1021.inc.get(iid), timers: w1021.inc.get(iid).timers.set("reaction", { ...w1021.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w1022
    } else {
      val w1023 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_1024 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w1025 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_1024) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w1026 = { ...w1025, inc: w1025.inc.set(iid, { ...w1025.inc.get(iid), timers: w1025.inc.get(iid).timers.set("reaction", { ...w1025.inc.get(iid).timers.get("reaction"), paused: keep_1024 }) }) }
      val w1027 = { ...w1026, inc: w1026.inc.set(iid, { ...w1026.inc.get(iid), timers: w1026.inc.get(iid).timers.set("reaction", { ...w1026.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w1028 = { ...w1027, inc: w1027.inc.set(iid, { ...w1027.inc.get(iid), timers: w1027.inc.get(iid).timers.set("reaction", { ...w1027.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w1028
    }
      w1023
    }
      w1018
    }
    w1016
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w1029 = if (not(timerDef("resolution").pausable)) {
      val w1030 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1031 = { ...w1030, inc: w1030.inc.set(iid, { ...w1030.inc.get(iid), timers: w1030.inc.get(iid).timers.set("resolution", { ...w1030.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w1031
    } else {
      val w1032 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w1033 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w1034 = { ...w1033, inc: w1033.inc.set(iid, { ...w1033.inc.get(iid), timers: w1033.inc.get(iid).timers.set("resolution", { ...w1033.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1035 = { ...w1034, inc: w1034.inc.set(iid, { ...w1034.inc.get(iid), timers: w1034.inc.get(iid).timers.set("resolution", { ...w1034.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w1035
    } else w0
      w1032
    }
    w1029
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_1036 = incidentById(incs(w0), c.form.primaryId)
    val w1037 = if (((((ps_1036.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_1036[0], "resolution", c.now)))) {
      val t_1038 = ps_1036[0].timers.get("resolution")
      val left_1039 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_1040 = (if ((t_1038.due != 0)) (t_1038.due - c.now) else (if (t_1038.paused) t_1038.left else (timerSec(ps_1036[0], "resolution", "") * 1000)))
      val w1041 = if ((left_1039 < was_1040)) {
      val w1042 = ps_1036.foldl([], (acc, x1045) => acc.append(x1045.id)).foldl(w0, (wf1043, pId1044) => {
      val w1046 = if ((t_1038.due != 0)) {
      val w1047 = { ...wf1043, inc: wf1043.inc.set(pId1044, { ...wf1043.inc.get(pId1044), timers: wf1043.inc.get(pId1044).timers.set("resolution", { ...wf1043.inc.get(pId1044).timers.get("resolution"), due: (c.now + left_1039) }) }) }
      w1047
    } else {
      val w1048 = { ...wf1043, inc: wf1043.inc.set(pId1044, { ...wf1043.inc.get(pId1044), timers: wf1043.inc.get(pId1044).timers.set("resolution", { ...wf1043.inc.get(pId1044).timers.get("resolution"), left: left_1039 }) }) }
      val w1049 = { ...w1048, inc: w1048.inc.set(pId1044, { ...w1048.inc.get(pId1044), timers: w1048.inc.get(pId1044).timers.set("resolution", { ...w1048.inc.get(pId1044).timers.get("resolution"), paused: true }) }) }
      w1049
    }
      w1046
    })
      w1042
    } else w0
      w1041
    } else w0
    w1037
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w1050 = if (timerDef("hold").startsOnce) {
      val w1051 = ec_pauseTimer(w0, c, iid, "hold")
      w1051
    } else {
      val w1052 = if (false) {
      val w1053 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w1054 = { ...w1053, inc: w1053.inc.set(iid, { ...w1053.inc.get(iid), timers: w1053.inc.get(iid).timers.set("hold", { ...w1053.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w1055 = { ...w1054, inc: w1054.inc.set(iid, { ...w1054.inc.get(iid), timers: w1054.inc.get(iid).timers.set("hold", { ...w1054.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w1056 = { ...w1055, inc: w1055.inc.set(iid, { ...w1055.inc.get(iid), timers: w1055.inc.get(iid).timers.set("hold", { ...w1055.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w1056
    } else {
      val w1057 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_1058 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w1059 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_1058) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w1060 = { ...w1059, inc: w1059.inc.set(iid, { ...w1059.inc.get(iid), timers: w1059.inc.get(iid).timers.set("hold", { ...w1059.inc.get(iid).timers.get("hold"), paused: keep_1058 }) }) }
      val w1061 = { ...w1060, inc: w1060.inc.set(iid, { ...w1060.inc.get(iid), timers: w1060.inc.get(iid).timers.set("hold", { ...w1060.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w1062 = { ...w1061, inc: w1061.inc.set(iid, { ...w1061.inc.get(iid), timers: w1061.inc.get(iid).timers.set("hold", { ...w1061.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w1062
    }
      w1057
    }
      w1052
    }
    w1050
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
    not(settings.session.states.foldl(false, (acc, s_1063) => acc or ((s_1063.id == agentState(c.me)) and s_1063.readOnly))),
    { val ps_1064 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1064.length() > 0) and ((ownership(c.me, ps_1064[0]) == "owner") or unowned(ps_1064[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_1065 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1066 = if (((ps_1065.length() > 0) and (leftOf(ps_1065[0], "resolution", c.now) >= 0))) {
      val w1067 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1068 = { ...w1067, inc: w1067.inc.set(iid, { ...w1067.inc.get(iid), timers: w1067.inc.get(iid).timers.set("resolution", { ...w1067.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1065[0], "resolution", c.now) }) }) }
      val w1069 = { ...w1068, inc: w1068.inc.set(iid, { ...w1068.inc.get(iid), timers: w1068.inc.get(iid).timers.set("resolution", { ...w1068.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1070 = if ((leftOf(ps_1065[0], "resolution", c.now) == 0)) {
      val w1071 = { ...w1069, inc: w1069.inc.set(iid, { ...w1069.inc.get(iid), timers: w1069.inc.get(iid).timers.set("resolution", { ...w1069.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1065[0], "resolution", c.now)) ps_1065[0].timers.get("resolution").fired else ps_1065[0].timers.get("resolution").due) }) }) }
      w1071
    } else w1069
      w1070
    } else w0
    w1066
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w1072 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1073 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1074 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1075 = { ...w1074, inc: w1074.inc.set(iid, { ...w1074.inc.get(iid), linkedTo: "" }) }
      val w1076 = { ...w1075, inc: w1075.inc.set(iid, { ...w1075.inc.get(iid), linkedAt: 0 }) }
      val w1077 = if (((ps_1073.length() > 0) and ("" != ""))) w1076 else w1076
      val w1078 = if (("" != "")) {
      val w1079 = ps_1073.foldl([], (acc, x1082) => acc.append(x1082.id)).foldl(w1077, (wf1080, pId1081) => wf1080)
      w1079
    } else w1077
      w1078
    } else {
      val w1083 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1084 = { ...w1083, inc: w1083.inc.set(iid, { ...w1083.inc.get(iid), linkedAt: 0 }) }
      w1084
    }
    w1072
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w1085 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1086 = if (timerDef("reaction").startsOnce) {
      val w1087 = ec_resumeTimer(w0, c, iid, "reaction")
      w1087
    } else {
      val w1088 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1089 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1090 = { ...w1089, inc: w1089.inc.set(iid, { ...w1089.inc.get(iid), timers: w1089.inc.get(iid).timers.set("reaction", { ...w1089.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1091 = { ...w1090, inc: w1090.inc.set(iid, { ...w1090.inc.get(iid), timers: w1090.inc.get(iid).timers.set("reaction", { ...w1090.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1091
    } else {
      val sec_1092 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w1093 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1092 < 0)) 0 else (c.now + (sec_1092 * 1000))) }) }) }
      val w1094 = { ...w1093, inc: w1093.inc.set(iid, { ...w1093.inc.get(iid), timers: w1093.inc.get(iid).timers.set("reaction", { ...w1093.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1095 = { ...w1094, inc: w1094.inc.set(iid, { ...w1094.inc.get(iid), timers: w1094.inc.get(iid).timers.set("reaction", { ...w1094.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1096 = { ...w1095, inc: w1095.inc.set(iid, { ...w1095.inc.get(iid), timers: w1095.inc.get(iid).timers.set("reaction", { ...w1095.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1096
    }
      w1088
    }
      w1086
    }
    w1085
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
    { val ps_1097 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1097.length() > 0) and isDone(ps_1097[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1098 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1099 = if ((ps_1098.length() > 0)) {
      val w1100 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_1098[0].closeResultId }) }
      val w1101 = { ...w1100, inc: w1100.inc.set(iid, { ...w1100.inc.get(iid), closeCauseId: ps_1098[0].closeCauseId }) }
      val w1102 = { ...w1101, inc: w1101.inc.set(iid, { ...w1101.inc.get(iid), closeCauseLabel: ps_1098[0].closeCauseLabel }) }
      val w1103 = { ...w1102, inc: w1102.inc.set(iid, { ...w1102.inc.get(iid), result: ps_1098[0].result }) }
      val w1104 = { ...w1103, inc: w1103.inc.set(iid, { ...w1103.inc.get(iid), closedBy: ps_1098[0].closedBy }) }
      val w1105 = { ...w1104, inc: w1104.inc.set(iid, { ...w1104.inc.get(iid), owner: ps_1098[0].closedBy }) }
      w1105
    } else w0
    w1099
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w1106 = if (not(timerDef("resolution").pausable)) {
      val w1107 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1108 = { ...w1107, inc: w1107.inc.set(iid, { ...w1107.inc.get(iid), timers: w1107.inc.get(iid).timers.set("resolution", { ...w1107.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w1108
    } else {
      val w1109 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w1110 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w1111 = { ...w1110, inc: w1110.inc.set(iid, { ...w1110.inc.get(iid), timers: w1110.inc.get(iid).timers.set("resolution", { ...w1110.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1112 = { ...w1111, inc: w1111.inc.set(iid, { ...w1111.inc.get(iid), timers: w1111.inc.get(iid).timers.set("resolution", { ...w1111.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w1112
    } else w0
      w1109
    }
    w1106
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_1113 = c.now
    val w1114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_1113 }) }
    w1114
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {
    val w1115 = if ((w0.inc.get(iid).acceptedAt == 0)) {
      val w1116 = if (not(w0.inc.get(iid).noReaction)) {
      val w1117 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedGroup: (if ((c.before.lastAssignedGroup != "")) c.before.lastAssignedGroup else dutyGroupOf(w0.inc.get(iid).closedBy)) }) }
      w1117
    } else w0
      val w1118 = { ...w1116, inc: w1116.inc.set(iid, { ...w1116.inc.get(iid), noReaction: true }) }
      w1118
    } else w0
    w1115
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_5(w0: World, c: Ctx, iid: str): World = {
    val w1119 = if (["false_alarm"].foldl(false, (acc, y1120) => acc or y1120 == w0.inc.get(iid).closeResultId)) {
      val w1121 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1125 => not(isDone(x_1125))).foldl([], (acc, x1124) => acc.append(x1124.id)).foldl(w0, (wf1122, sId1123) => wf1122)
      w1121
    } else w0
    w1119
  }

  def e_close_linked_6(w0: World, c: Ctx, iid: str): World = {
    val w1126 = if (["false_alarm"].foldl(false, (acc, y1127) => acc or y1127 == w0.inc.get(iid).closeResultId)) {
      val w1128 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1135 => not(isDone(x_1135))).foldl([], (acc, x1131) => acc.append(x1131.id)).foldl(w0, (wf1129, sId1130) => {
      val lead_1132 = (if ((wf1129.inc.get(sId1130).linkedTo != "")) { val ps_1133 = incidentById(incs(w0), wf1129.inc.get(sId1130).linkedTo)  (if (((ps_1133.length() > 0) and not(isDone(ps_1133[0])))) addressee(ps_1133[0]) else "") } else addressee(wf1129.inc.get(sId1130)))
      val w1134 = if (((lead_1132 != "") and (lead_1132 != wf1129.inc.get(iid).closedBy))) wf1129 else wf1129
      w1134
    })
      w1128
    } else w0
    w1126
  }

  def e_close_linked_7(w0: World, c: Ctx, iid: str): World = {

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
    val w7 = e_close_linked_6(w6, c1, iid)
    val w8 = e_close_linked_7(w7, c1, iid)
    w8
  }

  // linked_lost_access: system → new

  def ok_linked_lost_access(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    { val ps_1136 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_1137 = (if (((ps_1136.length() > 0) and not(isDone(ps_1136[0])))) addressee(ps_1136[0]) else "")  ((who_1137 != "") and (hasAccess(who_1137, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1138 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1139 = if (((ps_1138.length() > 0) and (leftOf(ps_1138[0], "resolution", c.now) >= 0))) {
      val w1140 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1141 = { ...w1140, inc: w1140.inc.set(iid, { ...w1140.inc.get(iid), timers: w1140.inc.get(iid).timers.set("resolution", { ...w1140.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1138[0], "resolution", c.now) }) }) }
      val w1142 = { ...w1141, inc: w1141.inc.set(iid, { ...w1141.inc.get(iid), timers: w1141.inc.get(iid).timers.set("resolution", { ...w1141.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1143 = if ((leftOf(ps_1138[0], "resolution", c.now) == 0)) {
      val w1144 = { ...w1142, inc: w1142.inc.set(iid, { ...w1142.inc.get(iid), timers: w1142.inc.get(iid).timers.set("resolution", { ...w1142.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1138[0], "resolution", c.now)) ps_1138[0].timers.get("resolution").fired else ps_1138[0].timers.get("resolution").due) }) }) }
      w1144
    } else w1142
      w1143
    } else w0
    w1139
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w1145 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1146 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1147 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1148 = { ...w1147, inc: w1147.inc.set(iid, { ...w1147.inc.get(iid), linkedTo: "" }) }
      val w1149 = { ...w1148, inc: w1148.inc.set(iid, { ...w1148.inc.get(iid), linkedAt: 0 }) }
      val w1150 = if (((ps_1146.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w1149 else w1149
      val w1151 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w1152 = ps_1146.foldl([], (acc, x1155) => acc.append(x1155.id)).foldl(w1150, (wf1153, pId1154) => wf1153)
      w1152
    } else w1150
      w1151
    } else {
      val w1156 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1157 = { ...w1156, inc: w1156.inc.set(iid, { ...w1156.inc.get(iid), linkedAt: 0 }) }
      w1157
    }
    w1145
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w1158 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1159 = if (timerDef("reaction").startsOnce) {
      val w1160 = ec_resumeTimer(w0, c, iid, "reaction")
      w1160
    } else {
      val w1161 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1162 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1163 = { ...w1162, inc: w1162.inc.set(iid, { ...w1162.inc.get(iid), timers: w1162.inc.get(iid).timers.set("reaction", { ...w1162.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1164 = { ...w1163, inc: w1163.inc.set(iid, { ...w1163.inc.get(iid), timers: w1163.inc.get(iid).timers.set("reaction", { ...w1163.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1164
    } else {
      val sec_1165 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w1166 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1165 < 0)) 0 else (c.now + (sec_1165 * 1000))) }) }) }
      val w1167 = { ...w1166, inc: w1166.inc.set(iid, { ...w1166.inc.get(iid), timers: w1166.inc.get(iid).timers.set("reaction", { ...w1166.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1168 = { ...w1167, inc: w1167.inc.set(iid, { ...w1167.inc.get(iid), timers: w1167.inc.get(iid).timers.set("reaction", { ...w1167.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1169 = { ...w1168, inc: w1168.inc.set(iid, { ...w1168.inc.get(iid), timers: w1168.inc.get(iid).timers.set("reaction", { ...w1168.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1169
    }
      w1161
    }
      w1159
    }
    w1158
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_1170 = settings.alerts.target
    val w1171 = if (((whom_1170 != "") and (whom_1170 != c.actor))) w0 else w0
    w1171
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
      Set("break", "no_link", "third_party", "patrol", "no_data").contains(c.form.reasonId),
      settings.holdReasons.foldl(false, (acc, r_1172) => acc or ((r_1172.id == c.form.reasonId) and (r_1172.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_1173) => acc and (isDone(e_1173) or hasAccess(c.form.targetId, e_1173))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_1174) => acc or (i_1174.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_1175) => acc or ((i_1175.id == c.form.resultId) and stepsOk(i_1175, world.inc.get(iid)))),
    },
    c.form.causeId == "" or all {
      settings.closeResults.foldl(false, (acc, i_1176) => acc or ((((i_1176.id == c.form.resultId) and (i_1176.causeCatalog != "")) and settings.causeCatalogs.keys().contains(i_1176.causeCatalog)) and (settings.causeCatalogs.get(i_1176.causeCatalog).items.length() > 0))),
      Set("animal", "weather", "equipment", "staff", "setup", "other", "power", "link", "mass_fault", "known").contains(c.form.causeId),
    },
  }

  def formOk(tid: str, c: Ctx, iid: str): bool =
    if (tid == "hold") form_hold(c, iid)
    else if (tid == "transfer") form_transfer(c, iid)
    else if (tid == "close") form_close(c, iid)
    else true

  def trOk(tid: str, c: Ctx, iid: str): bool =
    if (tid == "create") ok_create(c, iid)
    else if (tid == "create_to_group") ok_create_to_group(c, iid)
    else if (tid == "rule_group_cannot_accept") ok_rule_group_cannot_accept(c, iid)
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
    else if (tid == "comment") ok_comment(c, iid)
    else if (tid == "change_priority") ok_change_priority(c, iid)
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

  pure val INTAKE_CREATE: List[str] = ["create", "create_to_group", "rule_group_cannot_accept"]

  def trOkAt(tid: str, c: Ctx, iid: str, w: World): bool =
    if (tid == "create") okAt_create(c, iid, w)
    else if (tid == "create_to_group") okAt_create_to_group(c, iid, w)
    else if (tid == "rule_group_cannot_accept") okAt_rule_group_cannot_accept(c, iid, w)
    else false

  def trApply(tid: str, c: Ctx, iid: str, w: World): World =
    if (tid == "create") apply_create(c, iid, w)
    else if (tid == "create_to_group") apply_create_to_group(c, iid, w)
    else if (tid == "rule_group_cannot_accept") apply_rule_group_cannot_accept(c, iid, w)
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
    else if (tid == "comment") apply_comment(c, iid, w)
    else if (tid == "change_priority") apply_change_priority(c, iid, w)
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
    { id: "create_to_group", trigger: "event", actor: "dispatcher", from: Set(), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "rule_group_cannot_accept", trigger: "event", actor: "dispatcher", from: Set(), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
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
    { id: "comment", trigger: "manual", actor: "dispatcher", from: Set("new", "pending_acceptance", "in_progress", "on_hold", "closed", "linked"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "change_priority", trigger: "manual", actor: "dispatcher", from: Set("new", "pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
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

  pure val CONTINUES_ON: str -> Set[str] = Map("reaction" -> Set("addressee_signed_out_to_group", "addressee_signed_out_to_queue", "transfer", "reject", "comment", "change_priority"), "resolution" -> Set("comment", "change_priority"), "hold" -> Set("comment", "change_priority"))

  pure val GRACE_MS: int = 3000

  pure val TAKE_WITH: str = "claim"

  pure val MERGE: str = "merge"

  val reached_create = lastAction.name == "create"
  val reached_create_to_group = lastAction.name == "create_to_group"
  val reached_rule_group_cannot_accept = lastAction.name == "rule_group_cannot_accept"
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
  val reached_comment = lastAction.name == "comment"
  val reached_change_priority = lastAction.name == "change_priority"
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
    ["in_progress"].foldl(false, (acc, y1177) => acc or y1177 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_1178) => acc or ((s_1178.id == agentState(c.me)) and s_1178.readOnly))),
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
  // Дежурная группа правила-победителя у появляющегося инцидента (ruleDutyGroup, §8.1, М1): нет (""), одна из групп
  // модели или id группы, которой уже нет (её удалили после правки правила, isGroup ложно)
  pure val GONE_GROUP = "gone"
  pure val RULE_GROUPS: Set[str] = Set("", GONE_GROUP).union(GROUPS)
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
  // Уровни приоритета модели: значение варианта формы (число строкой) → число уровня; одно место для обоих (ТЗ-13)
  pure val PRIORITY_IDS: str -> int = Map("100" -> 100, "50" -> 50)
  pure val PRIORITIES: Set[int] = PRIORITY_IDS.keys().map(k => PRIORITY_IDS.get(k))
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
  // Число уровня приоритета по значению варианта формы (ТЗ-13): уровни модели — PRIORITY_IDS; нет такого — -1
  def priorityOf(id: str): int = if (PRIORITY_IDS.keys().contains(id)) PRIORITY_IDS.get(id) else -1
  // Групп устройств в модели нет: строк overrides по sourceGroup в машине тоже нет
  def inSourceGroup(x: Incident, g: str): bool = false
  // Условия правил по группе (§14.5, ARCH-15): групп устройств в модели нет — устройство ни в одной, глубина 0
  def deviceInGroup(d: str, g: str): bool = false
  // Окон работ в модели нет (ТЗ-21): поле «окно работ» формы закрытия скрыто
  def inMaintenance(x: Incident): bool = false
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
    { name: name, actor: actor, incident: i, kind: kind, form: NO_FORM, surface: "", others: [], prio: 0, scenario: "", event: "", ruleGroup: "" }

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

  // Инцидент события ev со сценарием sc (§14.5, ARCH-15). Правило уже выбрано — от него сценарий, приоритет и дежурная
  // группа правила rg (ruleDutyGroup, §8.1, М1; "" — у правила группы нет); сам выбор правила по событию — вне модели
  // (его держат тесты API и порчи кода intake-*). Ключ — intake.uniqueKey машины (intakeKeySame, генерируется; сейчас
  // событие + сценарий, PROC-93): второго инцидента с тем же ключом нет, повтор события и пересекающиеся правила его не дают
  def born(i: str, ev: str, sc: str, prio: int, rg: str): Incident =
    { ...NO_INCIDENT, id: i, number: i, eventType: "fire", priority: prio, occurredAt: clock, scenario: sc, eventGuid: ev, ruleDutyGroup: rg }
  def createOk(i: str, ev: str, sc: str): bool = all {
    incOf(i).state == "",
    not(INCIDENTS.exists(j => incOf(j).state != "" and intakeKeySame(incOf(j), born(i, ev, sc, 0, "")))),
  }
  // Мир с рождённым инцидентом — до перехода появления: его условия смотрят в ruleDutyGroup инцидента
  def bornWorld(i: str, ev: str, sc: str, prio: int, rg: str): World =
    { ...world, inc: world.inc.set(i, born(i, ev, sc, prio, rg)), answers: world.answers.set(i, Set()) }
  // Переходы появления (intake.create), условия которых выполнены, — по ruleAddressing машины ровно один (инвариант
  // intakeExactlyOne); ядро берёт его, а не первый по порядку списка
  def intakeReady(i: str, w: World): List[str] =
    INTAKE_CREATE.select(tid => trOkAt(tid, ctx(DISPATCHER, DISPATCHER, NO_FORM, ""), i, w))
  action createIn(i: str, ev: str, sc: str, prio: int, rg: str): bool = {
    val w0 = bornWorld(i, ev, sc, prio, rg)
    val ts = intakeReady(i, w0)
    all {
      createOk(i, ev, sc),
      ts.length() > 0,
      commit({ ...act0("create", ts[0], DISPATCHER, i), prio: prio, scenario: sc, event: ev, ruleGroup: rg }, trApply(ts[0], ctx(DISPATCHER, DISPATCHER, NO_FORM, ""), i, w0)),
    }
  }
  // Правило без дежурной группы — прежнее появление (create)
  action create(i: str, ev: str, sc: str, prio: int): bool = createIn(i, ev, sc, prio, "")

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
    // Дежурная группа правила (§8.1, М1): нет, одна из групп модели или группы уже нет (id не группы — ruleAddressing
    // даёт queue)
    nondet rg = RULE_GROUPS.oneOf()
    createIn(i, ev, sc, prio, rg)
  }
  action manualAny(a: str, i: str, tids: Set[str], results: Set[str]): bool = {
    nondet tid = tids.oneOf()
    nondet target = TARGETS.oneOf()
    nondet reason = HOLD_REASONS_BY_OPERATOR.oneOf()
    nondet result = results.oneOf()
    nondet surface = tr(tid).surfaces.oneOf()
    // Уровень для «Сменить приоритет» (ТЗ-13) — из уровней модели (PRIORITY_IDS)
    nondet prio = PRIORITY_IDS.keys().oneOf()
    val form = { ...NO_FORM, targetId: target, reasonId: reason, resultId: result,
      causeId: if (CAUSE_FOR.keys().contains(result)) CAUSE_FOR.get(result) else "", comment: "c", priority: prio }
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

  // 26. Появление по дежурной группе правила (§8.1, М1) — своими словами, не определением ruleAddressing машины: в группе
  //     правила есть участник, который вошёл в МИ (не offline; перерыв не мешает), с правом «Принимать» и доступом к
  //     объекту инцидента. Группы нет (id не группы модели) — принять некому
  def ruleGroupCanTake(x: Incident): bool =
    GROUPS.contains(x.ruleDutyGroup) and cfg.members.get(x.ruleDutyGroup).exists(m => agents.get(m) != "offline" and can(m, "incident:accept") and access(m, x))
  // 26а. Из переходов появления (intake.create) при любой группе правила — нет, группа модели, группы нет — условия
  //      выполнены ровно у одного: появление не теряется и не раздваивается
  val intakeExactlyOne = INCIDENTS.forall(i => RULE_GROUPS.forall(rg => intakeReady(i, bornWorld(i, OWN_EVENT.get(i), "fire", 100, rg)).length() == 1))
  // 26б. Как появился инцидент: без группы правила — create в «Новый» без адресата; группа может принять —
  //      create_to_group «Ожидает принятия» у группы правила, без владельца, уровень 0, передач 0; не может — в «Новый»
  //      без адресата переходом rule_group_cannot_accept (его оповещение модель не видит: уведомления мир не меняют)
  val intakeByRuleGroup = lastAction.kind == "create" implies {
    val x = incOf(lastAction.incident)
    val rg = lastAction.ruleGroup
    all {
      x.ruleDutyGroup == rg,
      if (rg == "") lastAction.name == "create" and x.state == "new" and x.assignmentGroup == NOBODY
      else if (ruleGroupCanTake(x)) all {
        lastAction.name == "create_to_group",
        x.state == "pending_acceptance",
        x.owner == NOBODY,
        x.assignmentGroup == rg,
        x.escalationLevel == 0,
        x.transferCount == 0,
      }
      else lastAction.name == "rule_group_cannot_accept" and x.state == "new" and x.owner == NOBODY and x.assignmentGroup == NOBODY,
    }
  }
  // 26в. «Ожидает принятия» у группы без эскалаций и передач — только появление у группы правила: адресат — группа
  //      правила (§8.1, М1)
  val ruleGroupPendingAddressee = INCIDENTS.forall(i => {
    val x = incOf(i)
    (x.state == "pending_acceptance" and x.owner == NOBODY and x.escalationLevel == 0 and x.transferCount == 0) implies x.assignmentGroup == x.ruleDutyGroup
  })
  // 26г. Группа правила — снимок при появлении: ни один переход её не меняет
  val ruleDutyGroupKept = INCIDENTS.forall(i => prev.world.inc.get(i).state != "" implies incOf(i).ruleDutyGroup == prev.world.inc.get(i).ruleDutyGroup)

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
    intakeExactlyOne,
    intakeByRuleGroup,
    ruleGroupPendingAddressee,
    ruleDutyGroupKept,
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
