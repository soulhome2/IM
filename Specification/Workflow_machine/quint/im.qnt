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


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, closeCauseLabel: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], priorityManual: bool, maintenanceWindowId: str, closeMaintenanceWindowId: str, timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str, eventGuid: str, ruleDutyGroup: str, acceptedAt: int, acceptedBy: str, noReaction: bool }

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

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", closeCauseLabel: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], priorityManual: false, maintenanceWindowId: "", closeMaintenanceWindowId: "", timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "", eventGuid: "", ruleDutyGroup: "", acceptedAt: 0, acceptedBy: "", noReaction: false }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

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
    w107
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_108 = 0
    val w109 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_108 }) }
    w109
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w110 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w111 = if (timerDef("reaction").startsOnce) {
      val w112 = ec_resumeTimer(w0, c, iid, "reaction")
      w112
    } else {
      val w113 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w115 = { ...w114, inc: w114.inc.set(iid, { ...w114.inc.get(iid), timers: w114.inc.get(iid).timers.set("reaction", { ...w114.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w116 = { ...w115, inc: w115.inc.set(iid, { ...w115.inc.get(iid), timers: w115.inc.get(iid).timers.set("reaction", { ...w115.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w116
    } else {
      val sec_117 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w118 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_117 < 0)) 0 else (c.now + (sec_117 * 1000))) }) }) }
      val w119 = { ...w118, inc: w118.inc.set(iid, { ...w118.inc.get(iid), timers: w118.inc.get(iid).timers.set("reaction", { ...w118.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w120 = { ...w119, inc: w119.inc.set(iid, { ...w119.inc.get(iid), timers: w119.inc.get(iid).timers.set("reaction", { ...w119.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w121 = { ...w120, inc: w120.inc.set(iid, { ...w120.inc.get(iid), timers: w120.inc.get(iid).timers.set("reaction", { ...w120.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w121
    }
      w113
    }
      w111
    }
    w110
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
    val who_122 = ""
    val w123 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_122 }) }
    w123
  }

  def e_create_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val group_124 = w0.inc.get(iid).ruleDutyGroup
    val w125 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_124 }) }
    w125
  }

  def e_create_to_group_2(w0: World, c: Ctx, iid: str): World = {
    val value_126 = 0
    val w127 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_126 }) }
    w127
  }

  def e_create_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val w128 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w129 = if (timerDef("reaction").startsOnce) {
      val w130 = ec_resumeTimer(w0, c, iid, "reaction")
      w130
    } else {
      val w131 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w132 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w133 = { ...w132, inc: w132.inc.set(iid, { ...w132.inc.get(iid), timers: w132.inc.get(iid).timers.set("reaction", { ...w132.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w134 = { ...w133, inc: w133.inc.set(iid, { ...w133.inc.get(iid), timers: w133.inc.get(iid).timers.set("reaction", { ...w133.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w134
    } else {
      val sec_135 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w136 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_135 < 0)) 0 else (c.now + (sec_135 * 1000))) }) }) }
      val w137 = { ...w136, inc: w136.inc.set(iid, { ...w136.inc.get(iid), timers: w136.inc.get(iid).timers.set("reaction", { ...w136.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w138 = { ...w137, inc: w137.inc.set(iid, { ...w137.inc.get(iid), timers: w137.inc.get(iid).timers.set("reaction", { ...w137.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w139 = { ...w138, inc: w138.inc.set(iid, { ...w138.inc.get(iid), timers: w138.inc.get(iid).timers.set("reaction", { ...w138.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w139
    }
      w131
    }
      w129
    }
    w128
  }

  def e_create_to_group_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_create_to_group_5(w0: World, c: Ctx, iid: str): World = {
    val whom_140 = addressee(w0.inc.get(iid))
    val w141 = if (((whom_140 != "") and (whom_140 != c.actor))) w0 else w0
    w141
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
    val who_142 = ""
    val w143 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_142 }) }
    w143
  }

  def e_rule_group_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_144 = ""
    val w145 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_144 }) }
    w145
  }

  def e_rule_group_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val value_146 = 0
    val w147 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_146 }) }
    w147
  }

  def e_rule_group_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w148 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w149 = if (timerDef("reaction").startsOnce) {
      val w150 = ec_resumeTimer(w0, c, iid, "reaction")
      w150
    } else {
      val w151 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w152 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w153 = { ...w152, inc: w152.inc.set(iid, { ...w152.inc.get(iid), timers: w152.inc.get(iid).timers.set("reaction", { ...w152.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w154 = { ...w153, inc: w153.inc.set(iid, { ...w153.inc.get(iid), timers: w153.inc.get(iid).timers.set("reaction", { ...w153.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w154
    } else {
      val sec_155 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w156 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_155 < 0)) 0 else (c.now + (sec_155 * 1000))) }) }) }
      val w157 = { ...w156, inc: w156.inc.set(iid, { ...w156.inc.get(iid), timers: w156.inc.get(iid).timers.set("reaction", { ...w156.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w158 = { ...w157, inc: w157.inc.set(iid, { ...w157.inc.get(iid), timers: w157.inc.get(iid).timers.set("reaction", { ...w157.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w159 = { ...w158, inc: w158.inc.set(iid, { ...w158.inc.get(iid), timers: w158.inc.get(iid).timers.set("reaction", { ...w158.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w159
    }
      w151
    }
      w149
    }
    w148
  }

  def e_rule_group_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_rule_group_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_160 = settings.alerts.target
    val w161 = if (((whom_160 != "") and (whom_160 != c.actor))) w0 else w0
    w161
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
    not(settings.session.states.foldl(false, (acc, s_162) => acc or ((s_162.id == agentState(c.me)) and s_162.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_163 = c.actor
    val w164 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_163 }) }
    w164
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w165 = if (timerDef("reaction").startsOnce) {
      val w166 = ec_pauseTimer(w0, c, iid, "reaction")
      w166
    } else {
      val w167 = if (false) {
      val w168 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w169 = { ...w168, inc: w168.inc.set(iid, { ...w168.inc.get(iid), timers: w168.inc.get(iid).timers.set("reaction", { ...w168.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w170 = { ...w169, inc: w169.inc.set(iid, { ...w169.inc.get(iid), timers: w169.inc.get(iid).timers.set("reaction", { ...w169.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w171 = { ...w170, inc: w170.inc.set(iid, { ...w170.inc.get(iid), timers: w170.inc.get(iid).timers.set("reaction", { ...w170.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w171
    } else {
      val w172 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_173 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w174 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_173) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w175 = { ...w174, inc: w174.inc.set(iid, { ...w174.inc.get(iid), timers: w174.inc.get(iid).timers.set("reaction", { ...w174.inc.get(iid).timers.get("reaction"), paused: keep_173 }) }) }
      val w176 = { ...w175, inc: w175.inc.set(iid, { ...w175.inc.get(iid), timers: w175.inc.get(iid).timers.set("reaction", { ...w175.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w177 = { ...w176, inc: w176.inc.set(iid, { ...w176.inc.get(iid), timers: w176.inc.get(iid).timers.set("reaction", { ...w176.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w177
    }
      w172
    }
      w167
    }
    w165
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w178 = if (not(timerDef("resolution").pausable)) {
      val sec_179 = timerSec(w0.inc.get(iid), "resolution", "")
      val w180 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_179 < 0)) 0 else (c.now + (sec_179 * 1000))) }) }) }
      val w181 = { ...w180, inc: w180.inc.set(iid, { ...w180.inc.get(iid), timers: w180.inc.get(iid).timers.set("resolution", { ...w180.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w181
    } else {
      val w182 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_183 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w184 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_183 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_183)) }) }) }
      val w185 = { ...w184, inc: w184.inc.set(iid, { ...w184.inc.get(iid), timers: w184.inc.get(iid).timers.set("resolution", { ...w184.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w186 = { ...w185, inc: w185.inc.set(iid, { ...w185.inc.get(iid), timers: w185.inc.get(iid).timers.set("resolution", { ...w185.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w186
    } else w0
      w182
    }
    w178
  }

  def e_claim_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_claim_4(w0: World, c: Ctx, iid: str): World = {
    val w187 = if (((w0.inc.get(iid).acceptedAt == 0) and not(w0.inc.get(iid).noReaction))) {
      val w188 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedAt: c.now }) }
      val w189 = { ...w188, inc: w188.inc.set(iid, { ...w188.inc.get(iid), acceptedBy: c.actor }) }
      w189
    } else w0
    w187
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
    not(settings.session.states.foldl(false, (acc, s_190) => acc or ((s_190.id == agentState(c.me)) and s_190.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_191 = c.actor
    val w192 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_191 }) }
    w192
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_193 = ""
    val w194 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_193 }) }
    w194
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w195 = if (timerDef("reaction").startsOnce) {
      val w196 = ec_pauseTimer(w0, c, iid, "reaction")
      w196
    } else {
      val w197 = if (false) {
      val w198 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w199 = { ...w198, inc: w198.inc.set(iid, { ...w198.inc.get(iid), timers: w198.inc.get(iid).timers.set("reaction", { ...w198.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w200 = { ...w199, inc: w199.inc.set(iid, { ...w199.inc.get(iid), timers: w199.inc.get(iid).timers.set("reaction", { ...w199.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w201 = { ...w200, inc: w200.inc.set(iid, { ...w200.inc.get(iid), timers: w200.inc.get(iid).timers.set("reaction", { ...w200.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w201
    } else {
      val w202 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_203 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w204 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_203) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w205 = { ...w204, inc: w204.inc.set(iid, { ...w204.inc.get(iid), timers: w204.inc.get(iid).timers.set("reaction", { ...w204.inc.get(iid).timers.get("reaction"), paused: keep_203 }) }) }
      val w206 = { ...w205, inc: w205.inc.set(iid, { ...w205.inc.get(iid), timers: w205.inc.get(iid).timers.set("reaction", { ...w205.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w207 = { ...w206, inc: w206.inc.set(iid, { ...w206.inc.get(iid), timers: w206.inc.get(iid).timers.set("reaction", { ...w206.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w207
    }
      w202
    }
      w197
    }
    w195
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w208 = if (not(timerDef("resolution").pausable)) {
      val sec_209 = timerSec(w0.inc.get(iid), "resolution", "")
      val w210 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_209 < 0)) 0 else (c.now + (sec_209 * 1000))) }) }) }
      val w211 = { ...w210, inc: w210.inc.set(iid, { ...w210.inc.get(iid), timers: w210.inc.get(iid).timers.set("resolution", { ...w210.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w211
    } else {
      val w212 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_213 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w214 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_213 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_213)) }) }) }
      val w215 = { ...w214, inc: w214.inc.set(iid, { ...w214.inc.get(iid), timers: w214.inc.get(iid).timers.set("resolution", { ...w214.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w216 = { ...w215, inc: w215.inc.set(iid, { ...w215.inc.get(iid), timers: w215.inc.get(iid).timers.set("resolution", { ...w215.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w216
    } else w0
      w212
    }
    w208
  }

  def e_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_accept_5(w0: World, c: Ctx, iid: str): World = {
    val w217 = if (((w0.inc.get(iid).acceptedAt == 0) and not(w0.inc.get(iid).noReaction))) {
      val w218 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedAt: c.now }) }
      val w219 = { ...w218, inc: w218.inc.set(iid, { ...w218.inc.get(iid), acceptedBy: c.actor }) }
      w219
    } else w0
    w217
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
    not(settings.session.states.foldl(false, (acc, s_220) => acc or ((s_220.id == agentState(c.me)) and s_220.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_221 = ""
    val w222 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_221 }) }
    w222
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_223 = ""
    val w224 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_223 }) }
    w224
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
    not(settings.session.states.foldl(false, (acc, s_225) => acc or ((s_225.id == agentState(c.me)) and s_225.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
    settings.holdReasons.foldl(false, (acc, r_226) => acc or (r_226.setBy != "system")),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_227 = c.form.reasonId
    val w228 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_227 }) }
    w228
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w229 = if (not(timerDef("resolution").pausable)) {
      val w230 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w231 = { ...w230, inc: w230.inc.set(iid, { ...w230.inc.get(iid), timers: w230.inc.get(iid).timers.set("resolution", { ...w230.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w231
    } else {
      val w232 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w233 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w234 = { ...w233, inc: w233.inc.set(iid, { ...w233.inc.get(iid), timers: w233.inc.get(iid).timers.set("resolution", { ...w233.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w235 = { ...w234, inc: w234.inc.set(iid, { ...w234.inc.get(iid), timers: w234.inc.get(iid).timers.set("resolution", { ...w234.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w235
    } else w0
      w232
    }
    w229
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w236 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w237 = if (timerDef("hold").startsOnce) {
      val w238 = ec_resumeTimer(w0, c, iid, "hold")
      w238
    } else {
      val w239 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w240 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w241 = { ...w240, inc: w240.inc.set(iid, { ...w240.inc.get(iid), timers: w240.inc.get(iid).timers.set("hold", { ...w240.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w242 = { ...w241, inc: w241.inc.set(iid, { ...w241.inc.get(iid), timers: w241.inc.get(iid).timers.set("hold", { ...w241.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w242
    } else {
      val sec_243 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w244 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_243 < 0)) 0 else (c.now + (sec_243 * 1000))) }) }) }
      val w245 = { ...w244, inc: w244.inc.set(iid, { ...w244.inc.get(iid), timers: w244.inc.get(iid).timers.set("hold", { ...w244.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w246 = { ...w245, inc: w245.inc.set(iid, { ...w245.inc.get(iid), timers: w245.inc.get(iid).timers.set("hold", { ...w245.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w247 = { ...w246, inc: w246.inc.set(iid, { ...w246.inc.get(iid), timers: w246.inc.get(iid).timers.set("hold", { ...w246.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w247
    }
      w239
    }
      w237
    }
    w236
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
    not(settings.session.states.foldl(false, (acc, s_248) => acc or ((s_248.id == agentState(c.me)) and s_248.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w249 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w249
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w250 = if (timerDef("hold").startsOnce) {
      val w251 = ec_pauseTimer(w0, c, iid, "hold")
      w251
    } else {
      val w252 = if (false) {
      val w253 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("hold", { ...w253.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w255 = { ...w254, inc: w254.inc.set(iid, { ...w254.inc.get(iid), timers: w254.inc.get(iid).timers.set("hold", { ...w254.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w256 = { ...w255, inc: w255.inc.set(iid, { ...w255.inc.get(iid), timers: w255.inc.get(iid).timers.set("hold", { ...w255.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w256
    } else {
      val w257 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_258 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w259 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_258) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w260 = { ...w259, inc: w259.inc.set(iid, { ...w259.inc.get(iid), timers: w259.inc.get(iid).timers.set("hold", { ...w259.inc.get(iid).timers.get("hold"), paused: keep_258 }) }) }
      val w261 = { ...w260, inc: w260.inc.set(iid, { ...w260.inc.get(iid), timers: w260.inc.get(iid).timers.set("hold", { ...w260.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w262 = { ...w261, inc: w261.inc.set(iid, { ...w261.inc.get(iid), timers: w261.inc.get(iid).timers.set("hold", { ...w261.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w262
    }
      w257
    }
      w252
    }
    w250
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w263 = if (not(timerDef("resolution").pausable)) {
      val sec_264 = timerSec(w0.inc.get(iid), "resolution", "")
      val w265 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_264 < 0)) 0 else (c.now + (sec_264 * 1000))) }) }) }
      val w266 = { ...w265, inc: w265.inc.set(iid, { ...w265.inc.get(iid), timers: w265.inc.get(iid).timers.set("resolution", { ...w265.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w266
    } else {
      val w267 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_268 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w269 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_268 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_268)) }) }) }
      val w270 = { ...w269, inc: w269.inc.set(iid, { ...w269.inc.get(iid), timers: w269.inc.get(iid).timers.set("resolution", { ...w269.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w271 = { ...w270, inc: w270.inc.set(iid, { ...w270.inc.get(iid), timers: w270.inc.get(iid).timers.set("resolution", { ...w270.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w271
    } else w0
      w267
    }
    w263
  }

  def e_resume_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resume_4(w0: World, c: Ctx, iid: str): World = {
    val w272 = if (((w0.inc.get(iid).acceptedAt == 0) and not(w0.inc.get(iid).noReaction))) {
      val w273 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedAt: c.now }) }
      val w274 = { ...w273, inc: w273.inc.set(iid, { ...w273.inc.get(iid), acceptedBy: c.actor }) }
      w274
    } else w0
    w272
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
    not(settings.session.states.foldl(false, (acc, s_275) => acc or ((s_275.id == agentState(c.me)) and s_275.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_276 = ""
    val w277 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_276 }) }
    w277
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w278 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w278
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w279 = if (not(timerDef("resolution").pausable)) {
      val w280 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w281 = { ...w280, inc: w280.inc.set(iid, { ...w280.inc.get(iid), timers: w280.inc.get(iid).timers.set("resolution", { ...w280.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w281
    } else {
      val w282 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w283 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w284 = { ...w283, inc: w283.inc.set(iid, { ...w283.inc.get(iid), timers: w283.inc.get(iid).timers.set("resolution", { ...w283.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w285 = { ...w284, inc: w284.inc.set(iid, { ...w284.inc.get(iid), timers: w284.inc.get(iid).timers.set("resolution", { ...w284.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w285
    } else w0
      w282
    }
    w279
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w286 = if (timerDef("hold").startsOnce) {
      val w287 = ec_pauseTimer(w0, c, iid, "hold")
      w287
    } else {
      val w288 = if (false) {
      val w289 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w290 = { ...w289, inc: w289.inc.set(iid, { ...w289.inc.get(iid), timers: w289.inc.get(iid).timers.set("hold", { ...w289.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w291 = { ...w290, inc: w290.inc.set(iid, { ...w290.inc.get(iid), timers: w290.inc.get(iid).timers.set("hold", { ...w290.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w292 = { ...w291, inc: w291.inc.set(iid, { ...w291.inc.get(iid), timers: w291.inc.get(iid).timers.set("hold", { ...w291.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w292
    } else {
      val w293 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_294 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w295 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_294) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("hold", { ...w295.inc.get(iid).timers.get("hold"), paused: keep_294 }) }) }
      val w297 = { ...w296, inc: w296.inc.set(iid, { ...w296.inc.get(iid), timers: w296.inc.get(iid).timers.set("hold", { ...w296.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w298 = { ...w297, inc: w297.inc.set(iid, { ...w297.inc.get(iid), timers: w297.inc.get(iid).timers.set("hold", { ...w297.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w298
    }
      w293
    }
      w288
    }
    w286
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w299 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w300 = if (timerDef("reaction").startsOnce) {
      val w301 = ec_resumeTimer(w0, c, iid, "reaction")
      w301
    } else {
      val w302 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w303 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w304 = { ...w303, inc: w303.inc.set(iid, { ...w303.inc.get(iid), timers: w303.inc.get(iid).timers.set("reaction", { ...w303.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w305 = { ...w304, inc: w304.inc.set(iid, { ...w304.inc.get(iid), timers: w304.inc.get(iid).timers.set("reaction", { ...w304.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w305
    } else {
      val sec_306 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w307 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_306 < 0)) 0 else (c.now + (sec_306 * 1000))) }) }) }
      val w308 = { ...w307, inc: w307.inc.set(iid, { ...w307.inc.get(iid), timers: w307.inc.get(iid).timers.set("reaction", { ...w307.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w309 = { ...w308, inc: w308.inc.set(iid, { ...w308.inc.get(iid), timers: w308.inc.get(iid).timers.set("reaction", { ...w308.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w310 = { ...w309, inc: w309.inc.set(iid, { ...w309.inc.get(iid), timers: w309.inc.get(iid).timers.set("reaction", { ...w309.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w310
    }
      w302
    }
      w300
    }
    w299
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
    not(settings.session.states.foldl(false, (acc, s_311) => acc or ((s_311.id == agentState(c.me)) and s_311.readOnly))),
    transferTargets.foldl(false, (acc, t_312) => acc or (offersTransferTo(c.me, t_312, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_313) => acc and (isDone(e_313) or hasAccess(t_312, e_313))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_314) => acc and (isDone(e_314) or hasAccess(c.form.targetId, e_314)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_315 = personOf(c.form.targetId)
    val w316 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_315 }) }
    w316
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_317 = groupOf(c.form.targetId)
    val w318 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_317 }) }
    w318
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w319 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w319
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w320 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w320
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w321 = if (not(timerDef("resolution").pausable)) {
      val w322 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w323 = { ...w322, inc: w322.inc.set(iid, { ...w322.inc.get(iid), timers: w322.inc.get(iid).timers.set("resolution", { ...w322.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w323
    } else {
      val w324 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w325 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w326 = { ...w325, inc: w325.inc.set(iid, { ...w325.inc.get(iid), timers: w325.inc.get(iid).timers.set("resolution", { ...w325.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w327 = { ...w326, inc: w326.inc.set(iid, { ...w326.inc.get(iid), timers: w326.inc.get(iid).timers.set("resolution", { ...w326.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w327
    } else w0
      w324
    }
    w321
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w328 = if (timerDef("hold").startsOnce) {
      val w329 = ec_pauseTimer(w0, c, iid, "hold")
      w329
    } else {
      val w330 = if (false) {
      val w331 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w332 = { ...w331, inc: w331.inc.set(iid, { ...w331.inc.get(iid), timers: w331.inc.get(iid).timers.set("hold", { ...w331.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w333 = { ...w332, inc: w332.inc.set(iid, { ...w332.inc.get(iid), timers: w332.inc.get(iid).timers.set("hold", { ...w332.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w334 = { ...w333, inc: w333.inc.set(iid, { ...w333.inc.get(iid), timers: w333.inc.get(iid).timers.set("hold", { ...w333.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w334
    } else {
      val w335 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_336 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w337 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_336) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w338 = { ...w337, inc: w337.inc.set(iid, { ...w337.inc.get(iid), timers: w337.inc.get(iid).timers.set("hold", { ...w337.inc.get(iid).timers.get("hold"), paused: keep_336 }) }) }
      val w339 = { ...w338, inc: w338.inc.set(iid, { ...w338.inc.get(iid), timers: w338.inc.get(iid).timers.set("hold", { ...w338.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w340 = { ...w339, inc: w339.inc.set(iid, { ...w339.inc.get(iid), timers: w339.inc.get(iid).timers.set("hold", { ...w339.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w340
    }
      w335
    }
      w330
    }
    w328
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w341 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w342 = if (timerDef("reaction").startsOnce) {
      val w343 = ec_resumeTimer(w0, c, iid, "reaction")
      w343
    } else {
      val w344 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w345 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w346 = { ...w345, inc: w345.inc.set(iid, { ...w345.inc.get(iid), timers: w345.inc.get(iid).timers.set("reaction", { ...w345.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w347 = { ...w346, inc: w346.inc.set(iid, { ...w346.inc.get(iid), timers: w346.inc.get(iid).timers.set("reaction", { ...w346.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w347
    } else {
      val sec_348 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w349 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_348 < 0)) 0 else (c.now + (sec_348 * 1000))) }) }) }
      val w350 = { ...w349, inc: w349.inc.set(iid, { ...w349.inc.get(iid), timers: w349.inc.get(iid).timers.set("reaction", { ...w349.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w351 = { ...w350, inc: w350.inc.set(iid, { ...w350.inc.get(iid), timers: w350.inc.get(iid).timers.set("reaction", { ...w350.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w352 = { ...w351, inc: w351.inc.set(iid, { ...w351.inc.get(iid), timers: w351.inc.get(iid).timers.set("reaction", { ...w351.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w352
    }
      w344
    }
      w342
    }
    w341
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_353 = c.before.owner
    val w354 = if (((whom_353 != "") and (whom_353 != c.actor))) w0 else w0
    w354
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_355 = addressee(w0.inc.get(iid))
    val w356 = if (((whom_355 != "") and (whom_355 != c.actor))) w0 else w0
    w356
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
    not(settings.session.states.foldl(false, (acc, s_357) => acc or ((s_357.id == agentState(c.me)) and s_357.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_358 = c.actor
    val w359 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_358 }) }
    w359
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_360 = ""
    val w361 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_360 }) }
    w361
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w362 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w362
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w363 = if (timerDef("reaction").startsOnce) {
      val w364 = ec_pauseTimer(w0, c, iid, "reaction")
      w364
    } else {
      val w365 = if (false) {
      val w366 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w367 = { ...w366, inc: w366.inc.set(iid, { ...w366.inc.get(iid), timers: w366.inc.get(iid).timers.set("reaction", { ...w366.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w368 = { ...w367, inc: w367.inc.set(iid, { ...w367.inc.get(iid), timers: w367.inc.get(iid).timers.set("reaction", { ...w367.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w369 = { ...w368, inc: w368.inc.set(iid, { ...w368.inc.get(iid), timers: w368.inc.get(iid).timers.set("reaction", { ...w368.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w369
    } else {
      val w370 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_371 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w372 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_371) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w373 = { ...w372, inc: w372.inc.set(iid, { ...w372.inc.get(iid), timers: w372.inc.get(iid).timers.set("reaction", { ...w372.inc.get(iid).timers.get("reaction"), paused: keep_371 }) }) }
      val w374 = { ...w373, inc: w373.inc.set(iid, { ...w373.inc.get(iid), timers: w373.inc.get(iid).timers.set("reaction", { ...w373.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w375 = { ...w374, inc: w374.inc.set(iid, { ...w374.inc.get(iid), timers: w374.inc.get(iid).timers.set("reaction", { ...w374.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w375
    }
      w370
    }
      w365
    }
    w363
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
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

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w389 = if (not(timerDef("resolution").pausable)) {
      val sec_390 = timerSec(w0.inc.get(iid), "resolution", "")
      val w391 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_390 < 0)) 0 else (c.now + (sec_390 * 1000))) }) }) }
      val w392 = { ...w391, inc: w391.inc.set(iid, { ...w391.inc.get(iid), timers: w391.inc.get(iid).timers.set("resolution", { ...w391.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w392
    } else {
      val w393 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_394 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w395 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_394 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_394)) }) }) }
      val w396 = { ...w395, inc: w395.inc.set(iid, { ...w395.inc.get(iid), timers: w395.inc.get(iid).timers.set("resolution", { ...w395.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w397 = { ...w396, inc: w396.inc.set(iid, { ...w396.inc.get(iid), timers: w396.inc.get(iid).timers.set("resolution", { ...w396.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w397
    } else w0
      w393
    }
    w389
  }

  def e_takeover_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_7(w0: World, c: Ctx, iid: str): World = {
    val w398 = if (((w0.inc.get(iid).acceptedAt == 0) and not(w0.inc.get(iid).noReaction))) {
      val w399 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), acceptedAt: c.now }) }
      val w400 = { ...w399, inc: w399.inc.set(iid, { ...w399.inc.get(iid), acceptedBy: c.actor }) }
      w400
    } else w0
    w398
  }

  def e_takeover_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_9(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_10(w0: World, c: Ctx, iid: str): World = {
    val whom_401 = c.before.owner
    val w402 = if (((whom_401 != "") and (whom_401 != c.actor))) w0 else w0
    w402
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
    not(settings.session.states.foldl(false, (acc, s_403) => acc or ((s_403.id == agentState(c.me)) and s_403.readOnly))),
    { val os_404 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_404.foldl(false, (acc, o_405) => acc or ((o_405.id == c.form.resultId) and stepsOk(o_405, world.inc.get(iid)))) else os_404.foldl(false, (acc, o_406) => acc or stepsOk(o_406, world.inc.get(iid)))) },
    ((((c.form.resultId == "") or (c.form.causeId == "")) or not(settings.closeResults.foldl(false, (acc, i_407) => acc or ((i_407.id == c.form.resultId) and (i_407.causeCatalog != ""))))) or (causeOk(c.form.resultId, c.form.causeId) and (not(causeCommentRequired(c.form.resultId, c.form.causeId)) or (c.form.comment != "")))),
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_408 = c.actor
    val w409 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_408 }) }
    w409
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_410 = ""
    val w411 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_410 }) }
    w411
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_412 = c.actor
    val w413 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_412 }) }
    w413
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_414 = c.now
    val w415 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_414 }) }
    w415
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_416 = c.form.resultId
    val w417 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_416 }) }
    w417
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_418 = (if (causeOk(c.form.resultId, c.form.causeId)) c.form.causeId else "")
    val w419 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_418 }) }
    w419
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_420 = causeLabel(c.form.resultId, c.form.causeId)
    val w421 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_420 }) }
    w421
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val value_422 = (if ((c.form.resultId == "drill")) c.form.maintenanceWindowId else "")
    val w423 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_422 }) }
    w423
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val value_424 = c.form.comment
    val w425 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_424 }) }
    w425
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w426 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w426
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
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

  def e_close_11(w0: World, c: Ctx, iid: str): World = {
    val w440 = if (not(timerDef("resolution").pausable)) {
      val w441 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w442 = { ...w441, inc: w441.inc.set(iid, { ...w441.inc.get(iid), timers: w441.inc.get(iid).timers.set("resolution", { ...w441.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w442
    } else {
      val w443 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w444 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w445 = { ...w444, inc: w444.inc.set(iid, { ...w444.inc.get(iid), timers: w444.inc.get(iid).timers.set("resolution", { ...w444.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w446 = { ...w445, inc: w445.inc.set(iid, { ...w445.inc.get(iid), timers: w445.inc.get(iid).timers.set("resolution", { ...w445.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w446
    } else w0
      w443
    }
    w440
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {
    val w447 = if (timerDef("hold").startsOnce) {
      val w448 = ec_pauseTimer(w0, c, iid, "hold")
      w448
    } else {
      val w449 = if (false) {
      val w450 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w451 = { ...w450, inc: w450.inc.set(iid, { ...w450.inc.get(iid), timers: w450.inc.get(iid).timers.set("hold", { ...w450.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w452 = { ...w451, inc: w451.inc.set(iid, { ...w451.inc.get(iid), timers: w451.inc.get(iid).timers.set("hold", { ...w451.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w453 = { ...w452, inc: w452.inc.set(iid, { ...w452.inc.get(iid), timers: w452.inc.get(iid).timers.set("hold", { ...w452.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w453
    } else {
      val w454 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_455 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w456 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_455) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w457 = { ...w456, inc: w456.inc.set(iid, { ...w456.inc.get(iid), timers: w456.inc.get(iid).timers.set("hold", { ...w456.inc.get(iid).timers.get("hold"), paused: keep_455 }) }) }
      val w458 = { ...w457, inc: w457.inc.set(iid, { ...w457.inc.get(iid), timers: w457.inc.get(iid).timers.set("hold", { ...w457.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w459 = { ...w458, inc: w458.inc.set(iid, { ...w458.inc.get(iid), timers: w458.inc.get(iid).timers.set("hold", { ...w458.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w459
    }
      w454
    }
      w449
    }
    w447
  }

  def e_close_13(w0: World, c: Ctx, iid: str): World = {
    val w460 = if ((w0.inc.get(iid).acceptedAt == 0)) {
      val w461 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), noReaction: true }) }
      w461
    } else w0
    w460
  }

  def e_close_14(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_15(w0: World, c: Ctx, iid: str): World = {
    val w462 = if (["false_alarm"].foldl(false, (acc, y463) => acc or y463 == w0.inc.get(iid).closeResultId)) {
      val w464 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_468 => not(isDone(x_468))).foldl([], (acc, x467) => acc.append(x467.id)).foldl(w0, (wf465, sId466) => wf465)
      w464
    } else w0
    w462
  }

  def e_close_16(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_17(w0: World, c: Ctx, iid: str): World = {
    val w469 = if (["false_alarm"].foldl(false, (acc, y470) => acc or y470 == w0.inc.get(iid).closeResultId)) {
      val w471 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_478 => not(isDone(x_478))).foldl([], (acc, x474) => acc.append(x474.id)).foldl(w0, (wf472, sId473) => {
      val lead_475 = (if ((wf472.inc.get(sId473).linkedTo != "")) { val ps_476 = incidentById(incs(w0), wf472.inc.get(sId473).linkedTo)  (if (((ps_476.length() > 0) and not(isDone(ps_476[0])))) addressee(ps_476[0]) else "") } else addressee(wf472.inc.get(sId473)))
      val w477 = if (((lead_475 != "") and (lead_475 != wf472.inc.get(iid).closedBy))) wf472 else wf472
      w477
    })
      w471
    } else w0
    w469
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
    not(settings.session.states.foldl(false, (acc, s_479) => acc or ((s_479.id == agentState(c.me)) and s_479.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_480 = c.actor
    val w481 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_480 }) }
    w481
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w482 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_483 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w484 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w485 = { ...w484, inc: w484.inc.set(iid, { ...w484.inc.get(iid), linkedTo: "" }) }
      val w486 = { ...w485, inc: w485.inc.set(iid, { ...w485.inc.get(iid), linkedAt: 0 }) }
      val w487 = if (((ps_483.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w486 else w486
      val w488 = if (("workflow.journal.linked_reopened" != "")) {
      val w489 = ps_483.foldl([], (acc, x492) => acc.append(x492.id)).foldl(w487, (wf490, pId491) => wf490)
      w489
    } else w487
      w488
    } else {
      val w493 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w494 = { ...w493, inc: w493.inc.set(iid, { ...w493.inc.get(iid), linkedAt: 0 }) }
      w494
    }
    w482
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_495 = ""
    val w496 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_495 }) }
    w496
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_497 = ""
    val w498 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_497 }) }
    w498
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_499 = ""
    val w500 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_499 }) }
    w500
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_501 = ""
    val w502 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_501 }) }
    w502
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_503 = ""
    val w504 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_503 }) }
    w504
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val value_505 = 0
    val w506 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_505 }) }
    w506
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val value_507 = ""
    val w508 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_507 }) }
    w508
  }

  def e_reopen_10(w0: World, c: Ctx, iid: str): World = {
    val sec_509 = settings.limits.reopenResolutionSec
    val w510 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_509 > 0)) sec_509 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w511 = { ...w510, inc: w510.inc.set(iid, { ...w510.inc.get(iid), timers: w510.inc.get(iid).timers.set("resolution", { ...w510.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w512 = { ...w511, inc: w511.inc.set(iid, { ...w511.inc.get(iid), timers: w511.inc.get(iid).timers.set("resolution", { ...w511.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w512
  }

  def e_reopen_11(w0: World, c: Ctx, iid: str): World = {
    val w513 = if (timerDef("reaction").startsOnce) {
      val w514 = ec_pauseTimer(w0, c, iid, "reaction")
      w514
    } else {
      val w515 = if (true) {
      val w516 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w517 = { ...w516, inc: w516.inc.set(iid, { ...w516.inc.get(iid), timers: w516.inc.get(iid).timers.set("reaction", { ...w516.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w518 = { ...w517, inc: w517.inc.set(iid, { ...w517.inc.get(iid), timers: w517.inc.get(iid).timers.set("reaction", { ...w517.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w519 = { ...w518, inc: w518.inc.set(iid, { ...w518.inc.get(iid), timers: w518.inc.get(iid).timers.set("reaction", { ...w518.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w519
    } else {
      val w520 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_521 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w522 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_521) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w523 = { ...w522, inc: w522.inc.set(iid, { ...w522.inc.get(iid), timers: w522.inc.get(iid).timers.set("reaction", { ...w522.inc.get(iid).timers.get("reaction"), paused: keep_521 }) }) }
      val w524 = { ...w523, inc: w523.inc.set(iid, { ...w523.inc.get(iid), timers: w523.inc.get(iid).timers.set("reaction", { ...w523.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w525 = { ...w524, inc: w524.inc.set(iid, { ...w524.inc.get(iid), timers: w524.inc.get(iid).timers.set("reaction", { ...w524.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w525
    }
      w520
    }
      w515
    }
    w513
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
    not(settings.session.states.foldl(false, (acc, s_526) => acc or ((s_526.id == agentState(c.me)) and s_526.readOnly))),
    ((if (c.form.comment == "") 0 else 1) <= settings.limits.commentMaxLength),
    (c.form.files.length() <= settings.limits.commentMaxFiles),
    c.form.files.foldl(true, (acc, f_527) => acc and (f_527.size <= settings.limits.attachmentMaxBytes)),
    c.form.files.foldl(true, (acc, f_528) => acc and settings.limits.attachmentTypes.foldl(false, (acc, y529) => acc or y529 == f_528.mime)),
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
    not(settings.session.states.foldl(false, (acc, s_530) => acc or ((s_530.id == agentState(c.me)) and s_530.readOnly))),
    ((c.form.priority == "") or (priorityOf(c.form.priority) != world.inc.get(iid).priority)),
  }

  def e_change_priority_0(w0: World, c: Ctx, iid: str): World = {
    val value_531 = priorityOf(c.form.priority)
    val w532 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priority: value_531 }) }
    w532
  }

  def e_change_priority_1(w0: World, c: Ctx, iid: str): World = {
    val value_533 = true
    val w534 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priorityManual: value_533 }) }
    w534
  }

  def e_change_priority_2(w0: World, c: Ctx, iid: str): World = {
    val t_535 = w0.inc.get(iid).timers.get("reaction")
    val raw_536 = ((timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel") - timerSec(c.before, "reaction", "byEscalationLevel")) * 1000)
    val delta_537 = (if (((raw_536 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_538) => acc or (m_538.state == "linked")))) 0 else raw_536)
    val w539 = if ((((t_535.due != 0) and (t_535.due > c.now)) and (t_535.fired != t_535.due))) {
      val w540 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if (((t_535.due + delta_537) > c.now)) (t_535.due + delta_537) else c.now) }) }) }
      w540
    } else {
      val w541 = if ((((timerDef("reaction").pausable and (t_535.due == 0)) and t_535.paused) and (t_535.left > 0))) {
      val w542 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (((t_535.left + delta_537) > 0)) (t_535.left + delta_537) else 1) }) }) }
      w542
    } else w0
      w541
    }
    w539
  }

  def e_change_priority_3(w0: World, c: Ctx, iid: str): World = {
    val t_543 = w0.inc.get(iid).timers.get("resolution")
    val raw_544 = ((timerSec(w0.inc.get(iid), "resolution", "") - timerSec(c.before, "resolution", "")) * 1000)
    val delta_545 = (if (((raw_544 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_546) => acc or (m_546.state == "linked")))) 0 else raw_544)
    val w547 = if ((((t_543.due != 0) and (t_543.due > c.now)) and (t_543.fired != t_543.due))) {
      val w548 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((t_543.due + delta_545) > c.now)) (t_543.due + delta_545) else c.now) }) }) }
      w548
    } else {
      val w549 = if ((((timerDef("resolution").pausable and (t_543.due == 0)) and t_543.paused) and (t_543.left > 0))) {
      val w550 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((t_543.left + delta_545) > 0)) (t_543.left + delta_545) else 1) }) }) }
      w550
    } else w0
      w549
    }
    w547
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
    { val t_551 = world.inc.get(iid).timers.get("reaction")  (((t_551.due != 0) and (t_551.due <= c.now)) and (t_551.fired != t_551.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_552 = personOf(levelUpTarget(c.before))
    val w553 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_552 }) }
    w553
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_554 = groupOf(levelUpTarget(c.before))
    val w555 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_554 }) }
    w555
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_556 = levelUpNumber(c.before)
    val w557 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_556 }) }
    w557
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w558 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w558
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w559 = if (not(timerDef("resolution").pausable)) {
      val w560 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w561 = { ...w560, inc: w560.inc.set(iid, { ...w560.inc.get(iid), timers: w560.inc.get(iid).timers.set("resolution", { ...w560.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w561
    } else {
      val w562 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w563 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w564 = { ...w563, inc: w563.inc.set(iid, { ...w563.inc.get(iid), timers: w563.inc.get(iid).timers.set("resolution", { ...w563.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w565 = { ...w564, inc: w564.inc.set(iid, { ...w564.inc.get(iid), timers: w564.inc.get(iid).timers.set("resolution", { ...w564.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w565
    } else w0
      w562
    }
    w559
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w566 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w567 = if (timerDef("reaction").startsOnce) {
      val w568 = ec_resumeTimer(w0, c, iid, "reaction")
      w568
    } else {
      val w569 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w570 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w571 = { ...w570, inc: w570.inc.set(iid, { ...w570.inc.get(iid), timers: w570.inc.get(iid).timers.set("reaction", { ...w570.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w572 = { ...w571, inc: w571.inc.set(iid, { ...w571.inc.get(iid), timers: w571.inc.get(iid).timers.set("reaction", { ...w571.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w572
    } else {
      val sec_573 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w574 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_573 < 0)) 0 else (c.now + (sec_573 * 1000))) }) }) }
      val w575 = { ...w574, inc: w574.inc.set(iid, { ...w574.inc.get(iid), timers: w574.inc.get(iid).timers.set("reaction", { ...w574.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w576 = { ...w575, inc: w575.inc.set(iid, { ...w575.inc.get(iid), timers: w575.inc.get(iid).timers.set("reaction", { ...w575.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w577 = { ...w576, inc: w576.inc.set(iid, { ...w576.inc.get(iid), timers: w576.inc.get(iid).timers.set("reaction", { ...w576.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w577
    }
      w569
    }
      w567
    }
    w566
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_578 = addressee(w0.inc.get(iid))
    val w579 = if (((whom_578 != "") and (whom_578 != c.actor))) w0 else w0
    w579
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
    { val t_580 = world.inc.get(iid).timers.get("reaction")  (((t_580.due != 0) and (t_580.due <= c.now)) and (t_580.fired != t_580.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_581 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w582 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_581) }) }
    val w583 = { ...w582, inc: w582.inc.set(iid, { ...w582.inc.get(iid), slaBreached: true }) }
    val w584 = groupMembersAt(incs(w0), w583.inc.get(iid), c.deadline).foldl([], (acc, x587) => acc.append(x587.id)).foldl(w583, (wf585, eId586) => {
      val w588 = { ...wf585, inc: wf585.inc.set(eId586, { ...wf585.inc.get(eId586), breaches: wf585.inc.get(eId586).breaches.append(breach_581) }) }
      val w589 = { ...w588, inc: w588.inc.set(eId586, { ...w588.inc.get(eId586), slaBreached: true }) }
      w589
    })
    w584
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w590 = if (timerDef("reaction").startsOnce) {
      val w591 = ec_pauseTimer(w0, c, iid, "reaction")
      w591
    } else {
      val w592 = if (false) {
      val w593 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w594 = { ...w593, inc: w593.inc.set(iid, { ...w593.inc.get(iid), timers: w593.inc.get(iid).timers.set("reaction", { ...w593.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w595 = { ...w594, inc: w594.inc.set(iid, { ...w594.inc.get(iid), timers: w594.inc.get(iid).timers.set("reaction", { ...w594.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w596 = { ...w595, inc: w595.inc.set(iid, { ...w595.inc.get(iid), timers: w595.inc.get(iid).timers.set("reaction", { ...w595.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w596
    } else {
      val w597 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_598 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w599 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_598) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w600 = { ...w599, inc: w599.inc.set(iid, { ...w599.inc.get(iid), timers: w599.inc.get(iid).timers.set("reaction", { ...w599.inc.get(iid).timers.get("reaction"), paused: keep_598 }) }) }
      val w601 = { ...w600, inc: w600.inc.set(iid, { ...w600.inc.get(iid), timers: w600.inc.get(iid).timers.set("reaction", { ...w600.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w602 = { ...w601, inc: w601.inc.set(iid, { ...w601.inc.get(iid), timers: w601.inc.get(iid).timers.set("reaction", { ...w601.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w602
    }
      w597
    }
      w592
    }
    w590
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_603 = settings.alerts.target
    val w604 = if (((whom_603 != "") and (whom_603 != c.actor))) w0 else w0
    w604
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
    { val t_605 = world.inc.get(iid).timers.get("reaction")  (((t_605.due != 0) and (t_605.due <= c.now)) and (t_605.fired != t_605.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_606 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w607 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_606) }) }
    val w608 = { ...w607, inc: w607.inc.set(iid, { ...w607.inc.get(iid), slaBreached: true }) }
    val w609 = groupMembersAt(incs(w0), w608.inc.get(iid), c.deadline).foldl([], (acc, x612) => acc.append(x612.id)).foldl(w608, (wf610, eId611) => {
      val w613 = { ...wf610, inc: wf610.inc.set(eId611, { ...wf610.inc.get(eId611), breaches: wf610.inc.get(eId611).breaches.append(breach_606) }) }
      val w614 = { ...w613, inc: w613.inc.set(eId611, { ...w613.inc.get(eId611), slaBreached: true }) }
      w614
    })
    w609
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w615 = if (timerDef("reaction").startsOnce) {
      val w616 = ec_pauseTimer(w0, c, iid, "reaction")
      w616
    } else {
      val w617 = if (false) {
      val w618 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w619 = { ...w618, inc: w618.inc.set(iid, { ...w618.inc.get(iid), timers: w618.inc.get(iid).timers.set("reaction", { ...w618.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w620 = { ...w619, inc: w619.inc.set(iid, { ...w619.inc.get(iid), timers: w619.inc.get(iid).timers.set("reaction", { ...w619.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w621 = { ...w620, inc: w620.inc.set(iid, { ...w620.inc.get(iid), timers: w620.inc.get(iid).timers.set("reaction", { ...w620.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w621
    } else {
      val w622 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_623 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w624 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_623) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w625 = { ...w624, inc: w624.inc.set(iid, { ...w624.inc.get(iid), timers: w624.inc.get(iid).timers.set("reaction", { ...w624.inc.get(iid).timers.get("reaction"), paused: keep_623 }) }) }
      val w626 = { ...w625, inc: w625.inc.set(iid, { ...w625.inc.get(iid), timers: w625.inc.get(iid).timers.set("reaction", { ...w625.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w627 = { ...w626, inc: w626.inc.set(iid, { ...w626.inc.get(iid), timers: w626.inc.get(iid).timers.set("reaction", { ...w626.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w627
    }
      w622
    }
      w617
    }
    w615
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_628 = settings.alerts.target
    val w629 = if (((whom_628 != "") and (whom_628 != c.actor))) w0 else w0
    w629
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
    { val t_630 = world.inc.get(iid).timers.get("resolution")  (((t_630.due != 0) and (t_630.due <= c.now)) and (t_630.fired != t_630.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_631 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w632 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_631) }) }
    val w633 = { ...w632, inc: w632.inc.set(iid, { ...w632.inc.get(iid), slaBreached: true }) }
    val w634 = groupMembersAt(incs(w0), w633.inc.get(iid), c.deadline).foldl([], (acc, x637) => acc.append(x637.id)).foldl(w633, (wf635, eId636) => {
      val w638 = { ...wf635, inc: wf635.inc.set(eId636, { ...wf635.inc.get(eId636), breaches: wf635.inc.get(eId636).breaches.append(breach_631) }) }
      val w639 = { ...w638, inc: w638.inc.set(eId636, { ...w638.inc.get(eId636), slaBreached: true }) }
      w639
    })
    w634
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_640 = settings.alerts.target
    val w641 = if (((whom_640 != "") and (whom_640 != c.actor))) w0 else w0
    w641
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
    { val t_642 = world.inc.get(iid).timers.get("resolution")  (((t_642.due != 0) and (t_642.due <= c.now)) and (t_642.fired != t_642.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_643 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w644 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_643) }) }
    val w645 = { ...w644, inc: w644.inc.set(iid, { ...w644.inc.get(iid), slaBreached: true }) }
    val w646 = groupMembersAt(incs(w0), w645.inc.get(iid), c.deadline).foldl([], (acc, x649) => acc.append(x649.id)).foldl(w645, (wf647, eId648) => {
      val w650 = { ...wf647, inc: wf647.inc.set(eId648, { ...wf647.inc.get(eId648), breaches: wf647.inc.get(eId648).breaches.append(breach_643) }) }
      val w651 = { ...w650, inc: w650.inc.set(eId648, { ...w650.inc.get(eId648), slaBreached: true }) }
      w651
    })
    w646
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_652 = personOf(levelUpTarget(c.before))
    val w653 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_652 }) }
    w653
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_654 = groupOf(levelUpTarget(c.before))
    val w655 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_654 }) }
    w655
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_656 = levelUpNumber(c.before)
    val w657 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_656 }) }
    w657
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
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

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w665 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w666 = if (timerDef("reaction").startsOnce) {
      val w667 = ec_resumeTimer(w0, c, iid, "reaction")
      w667
    } else {
      val w668 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w669 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w670 = { ...w669, inc: w669.inc.set(iid, { ...w669.inc.get(iid), timers: w669.inc.get(iid).timers.set("reaction", { ...w669.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w671 = { ...w670, inc: w670.inc.set(iid, { ...w670.inc.get(iid), timers: w670.inc.get(iid).timers.set("reaction", { ...w670.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w671
    } else {
      val sec_672 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w673 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_672 < 0)) 0 else (c.now + (sec_672 * 1000))) }) }) }
      val w674 = { ...w673, inc: w673.inc.set(iid, { ...w673.inc.get(iid), timers: w673.inc.get(iid).timers.set("reaction", { ...w673.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w675 = { ...w674, inc: w674.inc.set(iid, { ...w674.inc.get(iid), timers: w674.inc.get(iid).timers.set("reaction", { ...w674.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w676 = { ...w675, inc: w675.inc.set(iid, { ...w675.inc.get(iid), timers: w675.inc.get(iid).timers.set("reaction", { ...w675.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w676
    }
      w668
    }
      w666
    }
    w665
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_677 = c.before.owner
    val w678 = if (((whom_677 != "") and (whom_677 != c.actor))) w0 else w0
    w678
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_679 = addressee(w0.inc.get(iid))
    val w680 = if (((whom_679 != "") and (whom_679 != c.actor))) w0 else w0
    w680
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
    { val t_681 = world.inc.get(iid).timers.get("resolution")  (((t_681.due != 0) and (t_681.due <= c.now)) and (t_681.fired != t_681.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_682 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w683 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_682) }) }
    val w684 = { ...w683, inc: w683.inc.set(iid, { ...w683.inc.get(iid), slaBreached: true }) }
    val w685 = groupMembersAt(incs(w0), w684.inc.get(iid), c.deadline).foldl([], (acc, x688) => acc.append(x688.id)).foldl(w684, (wf686, eId687) => {
      val w689 = { ...wf686, inc: wf686.inc.set(eId687, { ...wf686.inc.get(eId687), breaches: wf686.inc.get(eId687).breaches.append(breach_682) }) }
      val w690 = { ...w689, inc: w689.inc.set(eId687, { ...w689.inc.get(eId687), slaBreached: true }) }
      w690
    })
    w685
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_691 = settings.alerts.target
    val w692 = if (((whom_691 != "") and (whom_691 != c.actor))) w0 else w0
    w692
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
    { val t_693 = world.inc.get(iid).timers.get("hold")  (((t_693.due != 0) and (t_693.due <= c.now)) and (t_693.fired != t_693.due)) },
    not(["break", "no_link"].foldl(false, (acc, y694) => acc or y694 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_695 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w696 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_695) }) }
    val w697 = { ...w696, inc: w696.inc.set(iid, { ...w696.inc.get(iid), slaBreached: true }) }
    val w698 = groupMembersAt(incs(w0), w697.inc.get(iid), c.deadline).foldl([], (acc, x701) => acc.append(x701.id)).foldl(w697, (wf699, eId700) => {
      val w702 = { ...wf699, inc: wf699.inc.set(eId700, { ...wf699.inc.get(eId700), breaches: wf699.inc.get(eId700).breaches.append(breach_695) }) }
      val w703 = { ...w702, inc: w702.inc.set(eId700, { ...w702.inc.get(eId700), slaBreached: true }) }
      w703
    })
    w698
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_704 = settings.alerts.target
    val w705 = if (((whom_704 != "") and (whom_704 != c.actor))) w0 else w0
    w705
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
    { val t_706 = world.inc.get(iid).timers.get("hold")  (((t_706.due != 0) and (t_706.due <= c.now)) and (t_706.fired != t_706.due)) },
    ["break"].foldl(false, (acc, y707) => acc or y707 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_708 = ""
    val w709 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_708 }) }
    w709
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w710 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w710
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w711 = if (timerDef("hold").startsOnce) {
      val w712 = ec_pauseTimer(w0, c, iid, "hold")
      w712
    } else {
      val w713 = if (false) {
      val w714 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w715 = { ...w714, inc: w714.inc.set(iid, { ...w714.inc.get(iid), timers: w714.inc.get(iid).timers.set("hold", { ...w714.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w716 = { ...w715, inc: w715.inc.set(iid, { ...w715.inc.get(iid), timers: w715.inc.get(iid).timers.set("hold", { ...w715.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w717 = { ...w716, inc: w716.inc.set(iid, { ...w716.inc.get(iid), timers: w716.inc.get(iid).timers.set("hold", { ...w716.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w717
    } else {
      val w718 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_719 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w720 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_719) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w721 = { ...w720, inc: w720.inc.set(iid, { ...w720.inc.get(iid), timers: w720.inc.get(iid).timers.set("hold", { ...w720.inc.get(iid).timers.get("hold"), paused: keep_719 }) }) }
      val w722 = { ...w721, inc: w721.inc.set(iid, { ...w721.inc.get(iid), timers: w721.inc.get(iid).timers.set("hold", { ...w721.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w723 = { ...w722, inc: w722.inc.set(iid, { ...w722.inc.get(iid), timers: w722.inc.get(iid).timers.set("hold", { ...w722.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w723
    }
      w718
    }
      w713
    }
    w711
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w724 = if (not(timerDef("resolution").pausable)) {
      val w725 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w726 = { ...w725, inc: w725.inc.set(iid, { ...w725.inc.get(iid), timers: w725.inc.get(iid).timers.set("resolution", { ...w725.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w726
    } else {
      val w727 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w728 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w729 = { ...w728, inc: w728.inc.set(iid, { ...w728.inc.get(iid), timers: w728.inc.get(iid).timers.set("resolution", { ...w728.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w730 = { ...w729, inc: w729.inc.set(iid, { ...w729.inc.get(iid), timers: w729.inc.get(iid).timers.set("resolution", { ...w729.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w730
    } else w0
      w727
    }
    w724
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w731 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w732 = if (timerDef("reaction").startsOnce) {
      val w733 = ec_resumeTimer(w0, c, iid, "reaction")
      w733
    } else {
      val w734 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w735 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w736 = { ...w735, inc: w735.inc.set(iid, { ...w735.inc.get(iid), timers: w735.inc.get(iid).timers.set("reaction", { ...w735.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w737 = { ...w736, inc: w736.inc.set(iid, { ...w736.inc.get(iid), timers: w736.inc.get(iid).timers.set("reaction", { ...w736.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w737
    } else {
      val sec_738 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w739 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_738 < 0)) 0 else (c.now + (sec_738 * 1000))) }) }) }
      val w740 = { ...w739, inc: w739.inc.set(iid, { ...w739.inc.get(iid), timers: w739.inc.get(iid).timers.set("reaction", { ...w739.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w741 = { ...w740, inc: w740.inc.set(iid, { ...w740.inc.get(iid), timers: w740.inc.get(iid).timers.set("reaction", { ...w740.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w742 = { ...w741, inc: w741.inc.set(iid, { ...w741.inc.get(iid), timers: w741.inc.get(iid).timers.set("reaction", { ...w741.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w742
    }
      w734
    }
      w732
    }
    w731
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
    val reason_743 = "break"
    val w744 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_743 }) }
    w744
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w745 = if (not(timerDef("resolution").pausable)) {
      val w746 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w747 = { ...w746, inc: w746.inc.set(iid, { ...w746.inc.get(iid), timers: w746.inc.get(iid).timers.set("resolution", { ...w746.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w747
    } else {
      val w748 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w749 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w750 = { ...w749, inc: w749.inc.set(iid, { ...w749.inc.get(iid), timers: w749.inc.get(iid).timers.set("resolution", { ...w749.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w751 = { ...w750, inc: w750.inc.set(iid, { ...w750.inc.get(iid), timers: w750.inc.get(iid).timers.set("resolution", { ...w750.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w751
    } else w0
      w748
    }
    w745
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w752 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w753 = if (timerDef("hold").startsOnce) {
      val w754 = ec_resumeTimer(w0, c, iid, "hold")
      w754
    } else {
      val w755 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w756 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w757 = { ...w756, inc: w756.inc.set(iid, { ...w756.inc.get(iid), timers: w756.inc.get(iid).timers.set("hold", { ...w756.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w758 = { ...w757, inc: w757.inc.set(iid, { ...w757.inc.get(iid), timers: w757.inc.get(iid).timers.set("hold", { ...w757.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w758
    } else {
      val sec_759 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w760 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_759 < 0)) 0 else (c.now + (sec_759 * 1000))) }) }) }
      val w761 = { ...w760, inc: w760.inc.set(iid, { ...w760.inc.get(iid), timers: w760.inc.get(iid).timers.set("hold", { ...w760.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w762 = { ...w761, inc: w761.inc.set(iid, { ...w761.inc.get(iid), timers: w761.inc.get(iid).timers.set("hold", { ...w761.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w763 = { ...w762, inc: w762.inc.set(iid, { ...w762.inc.get(iid), timers: w762.inc.get(iid).timers.set("hold", { ...w762.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w763
    }
      w755
    }
      w753
    }
    w752
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
    val reason_764 = "no_link"
    val w765 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_764 }) }
    w765
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w766 = if (not(timerDef("resolution").pausable)) {
      val w767 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w768 = { ...w767, inc: w767.inc.set(iid, { ...w767.inc.get(iid), timers: w767.inc.get(iid).timers.set("resolution", { ...w767.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w768
    } else {
      val w769 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w770 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w771 = { ...w770, inc: w770.inc.set(iid, { ...w770.inc.get(iid), timers: w770.inc.get(iid).timers.set("resolution", { ...w770.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w772 = { ...w771, inc: w771.inc.set(iid, { ...w771.inc.get(iid), timers: w771.inc.get(iid).timers.set("resolution", { ...w771.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w772
    } else w0
      w769
    }
    w766
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w773 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w774 = if (timerDef("hold").startsOnce) {
      val w775 = ec_resumeTimer(w0, c, iid, "hold")
      w775
    } else {
      val w776 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w777 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w778 = { ...w777, inc: w777.inc.set(iid, { ...w777.inc.get(iid), timers: w777.inc.get(iid).timers.set("hold", { ...w777.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w779 = { ...w778, inc: w778.inc.set(iid, { ...w778.inc.get(iid), timers: w778.inc.get(iid).timers.set("hold", { ...w778.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w779
    } else {
      val sec_780 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w781 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_780 < 0)) 0 else (c.now + (sec_780 * 1000))) }) }) }
      val w782 = { ...w781, inc: w781.inc.set(iid, { ...w781.inc.get(iid), timers: w781.inc.get(iid).timers.set("hold", { ...w781.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w783 = { ...w782, inc: w782.inc.set(iid, { ...w782.inc.get(iid), timers: w782.inc.get(iid).timers.set("hold", { ...w782.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w784 = { ...w783, inc: w783.inc.set(iid, { ...w783.inc.get(iid), timers: w783.inc.get(iid).timers.set("hold", { ...w783.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w784
    }
      w776
    }
      w774
    }
    w773
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_785 = settings.alerts.target
    val w786 = if (((whom_785 != "") and (whom_785 != c.actor))) w0 else w0
    w786
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
    ["break", "no_link"].foldl(false, (acc, y787) => acc or y787 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_788 = ""
    val w789 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_788 }) }
    w789
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w790 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w790
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w791 = if (timerDef("hold").startsOnce) {
      val w792 = ec_pauseTimer(w0, c, iid, "hold")
      w792
    } else {
      val w793 = if (false) {
      val w794 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w795 = { ...w794, inc: w794.inc.set(iid, { ...w794.inc.get(iid), timers: w794.inc.get(iid).timers.set("hold", { ...w794.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w796 = { ...w795, inc: w795.inc.set(iid, { ...w795.inc.get(iid), timers: w795.inc.get(iid).timers.set("hold", { ...w795.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w797 = { ...w796, inc: w796.inc.set(iid, { ...w796.inc.get(iid), timers: w796.inc.get(iid).timers.set("hold", { ...w796.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w797
    } else {
      val w798 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_799 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w800 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_799) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w801 = { ...w800, inc: w800.inc.set(iid, { ...w800.inc.get(iid), timers: w800.inc.get(iid).timers.set("hold", { ...w800.inc.get(iid).timers.get("hold"), paused: keep_799 }) }) }
      val w802 = { ...w801, inc: w801.inc.set(iid, { ...w801.inc.get(iid), timers: w801.inc.get(iid).timers.set("hold", { ...w801.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w803 = { ...w802, inc: w802.inc.set(iid, { ...w802.inc.get(iid), timers: w802.inc.get(iid).timers.set("hold", { ...w802.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w803
    }
      w798
    }
      w793
    }
    w791
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w804 = if (not(timerDef("resolution").pausable)) {
      val w805 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w806 = { ...w805, inc: w805.inc.set(iid, { ...w805.inc.get(iid), timers: w805.inc.get(iid).timers.set("resolution", { ...w805.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w806
    } else {
      val w807 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w808 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w809 = { ...w808, inc: w808.inc.set(iid, { ...w808.inc.get(iid), timers: w808.inc.get(iid).timers.set("resolution", { ...w808.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w810 = { ...w809, inc: w809.inc.set(iid, { ...w809.inc.get(iid), timers: w809.inc.get(iid).timers.set("resolution", { ...w809.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w810
    } else w0
      w807
    }
    w804
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w811 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w812 = if (timerDef("reaction").startsOnce) {
      val w813 = ec_resumeTimer(w0, c, iid, "reaction")
      w813
    } else {
      val w814 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w815 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w816 = { ...w815, inc: w815.inc.set(iid, { ...w815.inc.get(iid), timers: w815.inc.get(iid).timers.set("reaction", { ...w815.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w817 = { ...w816, inc: w816.inc.set(iid, { ...w816.inc.get(iid), timers: w816.inc.get(iid).timers.set("reaction", { ...w816.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w817
    } else {
      val sec_818 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w819 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_818 < 0)) 0 else (c.now + (sec_818 * 1000))) }) }) }
      val w820 = { ...w819, inc: w819.inc.set(iid, { ...w819.inc.get(iid), timers: w819.inc.get(iid).timers.set("reaction", { ...w819.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w821 = { ...w820, inc: w820.inc.set(iid, { ...w820.inc.get(iid), timers: w820.inc.get(iid).timers.set("reaction", { ...w820.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w822 = { ...w821, inc: w821.inc.set(iid, { ...w821.inc.get(iid), timers: w821.inc.get(iid).timers.set("reaction", { ...w821.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w822
    }
      w814
    }
      w812
    }
    w811
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
    { val t_823 = world.inc.get(iid).timers.get("hold")  (((t_823.due != 0) and (t_823.due <= c.now)) and (t_823.fired != t_823.due)) },
    ["no_link"].foldl(false, (acc, y824) => acc or y824 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_825 = ""
    val w826 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_825 }) }
    w826
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w827 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w827
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w828 = if (timerDef("hold").startsOnce) {
      val w829 = ec_pauseTimer(w0, c, iid, "hold")
      w829
    } else {
      val w830 = if (false) {
      val w831 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w832 = { ...w831, inc: w831.inc.set(iid, { ...w831.inc.get(iid), timers: w831.inc.get(iid).timers.set("hold", { ...w831.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w833 = { ...w832, inc: w832.inc.set(iid, { ...w832.inc.get(iid), timers: w832.inc.get(iid).timers.set("hold", { ...w832.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w834 = { ...w833, inc: w833.inc.set(iid, { ...w833.inc.get(iid), timers: w833.inc.get(iid).timers.set("hold", { ...w833.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w834
    } else {
      val w835 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_836 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w837 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_836) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w838 = { ...w837, inc: w837.inc.set(iid, { ...w837.inc.get(iid), timers: w837.inc.get(iid).timers.set("hold", { ...w837.inc.get(iid).timers.get("hold"), paused: keep_836 }) }) }
      val w839 = { ...w838, inc: w838.inc.set(iid, { ...w838.inc.get(iid), timers: w838.inc.get(iid).timers.set("hold", { ...w838.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w840 = { ...w839, inc: w839.inc.set(iid, { ...w839.inc.get(iid), timers: w839.inc.get(iid).timers.set("hold", { ...w839.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w840
    }
      w835
    }
      w830
    }
    w828
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w841 = if (not(timerDef("resolution").pausable)) {
      val w842 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w843 = { ...w842, inc: w842.inc.set(iid, { ...w842.inc.get(iid), timers: w842.inc.get(iid).timers.set("resolution", { ...w842.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w843
    } else {
      val w844 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w845 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w846 = { ...w845, inc: w845.inc.set(iid, { ...w845.inc.get(iid), timers: w845.inc.get(iid).timers.set("resolution", { ...w845.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w847 = { ...w846, inc: w846.inc.set(iid, { ...w846.inc.get(iid), timers: w846.inc.get(iid).timers.set("resolution", { ...w846.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w847
    } else w0
      w844
    }
    w841
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w848 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w849 = if (timerDef("reaction").startsOnce) {
      val w850 = ec_resumeTimer(w0, c, iid, "reaction")
      w850
    } else {
      val w851 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w852 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w853 = { ...w852, inc: w852.inc.set(iid, { ...w852.inc.get(iid), timers: w852.inc.get(iid).timers.set("reaction", { ...w852.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w854 = { ...w853, inc: w853.inc.set(iid, { ...w853.inc.get(iid), timers: w853.inc.get(iid).timers.set("reaction", { ...w853.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w854
    } else {
      val sec_855 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w856 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_855 < 0)) 0 else (c.now + (sec_855 * 1000))) }) }) }
      val w857 = { ...w856, inc: w856.inc.set(iid, { ...w856.inc.get(iid), timers: w856.inc.get(iid).timers.set("reaction", { ...w856.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w858 = { ...w857, inc: w857.inc.set(iid, { ...w857.inc.get(iid), timers: w857.inc.get(iid).timers.set("reaction", { ...w857.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w859 = { ...w858, inc: w858.inc.set(iid, { ...w858.inc.get(iid), timers: w858.inc.get(iid).timers.set("reaction", { ...w858.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w859
    }
      w851
    }
      w849
    }
    w848
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
    val group_860 = dutyGroupOf(w0.inc.get(iid).owner)
    val w861 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_860 }) }
    w861
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_862 = ""
    val w863 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_862 }) }
    w863
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_864 = addressee(w0.inc.get(iid))
    val w865 = if (((whom_864 != "") and (whom_864 != c.actor))) w0 else w0
    w865
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
    val who_866 = ""
    val w867 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_866 }) }
    w867
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
    val who_868 = ""
    val w869 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_868 }) }
    w869
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w870 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w870
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w871 = if (timerDef("hold").startsOnce) {
      val w872 = ec_pauseTimer(w0, c, iid, "hold")
      w872
    } else {
      val w873 = if (false) {
      val w874 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w875 = { ...w874, inc: w874.inc.set(iid, { ...w874.inc.get(iid), timers: w874.inc.get(iid).timers.set("hold", { ...w874.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w876 = { ...w875, inc: w875.inc.set(iid, { ...w875.inc.get(iid), timers: w875.inc.get(iid).timers.set("hold", { ...w875.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w877 = { ...w876, inc: w876.inc.set(iid, { ...w876.inc.get(iid), timers: w876.inc.get(iid).timers.set("hold", { ...w876.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w877
    } else {
      val w878 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_879 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w880 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_879) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w881 = { ...w880, inc: w880.inc.set(iid, { ...w880.inc.get(iid), timers: w880.inc.get(iid).timers.set("hold", { ...w880.inc.get(iid).timers.get("hold"), paused: keep_879 }) }) }
      val w882 = { ...w881, inc: w881.inc.set(iid, { ...w881.inc.get(iid), timers: w881.inc.get(iid).timers.set("hold", { ...w881.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w883 = { ...w882, inc: w882.inc.set(iid, { ...w882.inc.get(iid), timers: w882.inc.get(iid).timers.set("hold", { ...w882.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w883
    }
      w878
    }
      w873
    }
    w871
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
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

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w891 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w892 = if (timerDef("reaction").startsOnce) {
      val w893 = ec_resumeTimer(w0, c, iid, "reaction")
      w893
    } else {
      val w894 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w895 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w896 = { ...w895, inc: w895.inc.set(iid, { ...w895.inc.get(iid), timers: w895.inc.get(iid).timers.set("reaction", { ...w895.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w897 = { ...w896, inc: w896.inc.set(iid, { ...w896.inc.get(iid), timers: w896.inc.get(iid).timers.set("reaction", { ...w896.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w897
    } else {
      val sec_898 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w899 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_898 < 0)) 0 else (c.now + (sec_898 * 1000))) }) }) }
      val w900 = { ...w899, inc: w899.inc.set(iid, { ...w899.inc.get(iid), timers: w899.inc.get(iid).timers.set("reaction", { ...w899.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w901 = { ...w900, inc: w900.inc.set(iid, { ...w900.inc.get(iid), timers: w900.inc.get(iid).timers.set("reaction", { ...w900.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w902 = { ...w901, inc: w901.inc.set(iid, { ...w901.inc.get(iid), timers: w901.inc.get(iid).timers.set("reaction", { ...w901.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w902
    }
      w894
    }
      w892
    }
    w891
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
    val who_903 = ""
    val w904 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_903 }) }
    w904
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_905 = ""
    val w906 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_905 }) }
    w906
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w907 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w907
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
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

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w921 = if (not(timerDef("resolution").pausable)) {
      val w922 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w923 = { ...w922, inc: w922.inc.set(iid, { ...w922.inc.get(iid), timers: w922.inc.get(iid).timers.set("resolution", { ...w922.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w923
    } else {
      val w924 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w925 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w926 = { ...w925, inc: w925.inc.set(iid, { ...w925.inc.get(iid), timers: w925.inc.get(iid).timers.set("resolution", { ...w925.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w927 = { ...w926, inc: w926.inc.set(iid, { ...w926.inc.get(iid), timers: w926.inc.get(iid).timers.set("resolution", { ...w926.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w927
    } else w0
      w924
    }
    w921
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w928 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w929 = if (timerDef("reaction").startsOnce) {
      val w930 = ec_resumeTimer(w0, c, iid, "reaction")
      w930
    } else {
      val w931 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w932 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w933 = { ...w932, inc: w932.inc.set(iid, { ...w932.inc.get(iid), timers: w932.inc.get(iid).timers.set("reaction", { ...w932.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w934 = { ...w933, inc: w933.inc.set(iid, { ...w933.inc.get(iid), timers: w933.inc.get(iid).timers.set("reaction", { ...w933.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w934
    } else {
      val sec_935 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w936 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_935 < 0)) 0 else (c.now + (sec_935 * 1000))) }) }) }
      val w937 = { ...w936, inc: w936.inc.set(iid, { ...w936.inc.get(iid), timers: w936.inc.get(iid).timers.set("reaction", { ...w936.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w938 = { ...w937, inc: w937.inc.set(iid, { ...w937.inc.get(iid), timers: w937.inc.get(iid).timers.set("reaction", { ...w937.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w939 = { ...w938, inc: w938.inc.set(iid, { ...w938.inc.get(iid), timers: w938.inc.get(iid).timers.set("reaction", { ...w938.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w939
    }
      w931
    }
      w929
    }
    w928
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_940 = settings.alerts.target
    val w941 = if (((whom_940 != "") and (whom_940 != c.actor))) w0 else w0
    w941
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
    val who_942 = ""
    val w943 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_942 }) }
    w943
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_944 = ""
    val w945 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_944 }) }
    w945
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w946 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w947 = if (timerDef("reaction").startsOnce) {
      val w948 = ec_resumeTimer(w0, c, iid, "reaction")
      w948
    } else {
      val w949 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w950 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w951 = { ...w950, inc: w950.inc.set(iid, { ...w950.inc.get(iid), timers: w950.inc.get(iid).timers.set("reaction", { ...w950.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w952 = { ...w951, inc: w951.inc.set(iid, { ...w951.inc.get(iid), timers: w951.inc.get(iid).timers.set("reaction", { ...w951.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w952
    } else {
      val sec_953 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w954 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_953 < 0)) 0 else (c.now + (sec_953 * 1000))) }) }) }
      val w955 = { ...w954, inc: w954.inc.set(iid, { ...w954.inc.get(iid), timers: w954.inc.get(iid).timers.set("reaction", { ...w954.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w956 = { ...w955, inc: w955.inc.set(iid, { ...w955.inc.get(iid), timers: w955.inc.get(iid).timers.set("reaction", { ...w955.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w957 = { ...w956, inc: w956.inc.set(iid, { ...w956.inc.get(iid), timers: w956.inc.get(iid).timers.set("reaction", { ...w956.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w957
    }
      w949
    }
      w947
    }
    w946
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_958 = settings.alerts.target
    val w959 = if (((whom_958 != "") and (whom_958 != c.actor))) w0 else w0
    w959
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
    not(settings.session.states.foldl(false, (acc, s_960) => acc or ((s_960.id == agentState(c.me)) and s_960.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_961 = incidentById(incs(world), c.form.primaryId)  ((((ps_961.length() > 0) and (ps_961[0].id != world.inc.get(iid).id)) and (ps_961[0].linkedTo == "")) and ((ps_961[0].state == "new") or ((ps_961[0].state == "in_progress") and (ps_961[0].owner == c.me)))) },
    { val ps_962 = incidentById(incs(world), c.form.primaryId)  ((ps_962.length() > 0) and (ps_962[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w963 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w963
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_964 = incidentById(incs(w0), c.form.primaryId)
    val w965 = if ((ps_964.length() > 0)) {
      val w966 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_973 => not(isDone(e_973))).foldl([], (acc, x969) => acc.append(x969.id)).foldl(w0, (wf967, cId968) => {
      val w970 = { ...wf967, inc: wf967.inc.set(cId968, { ...wf967.inc.get(cId968), leftGroup: { primaryId: wf967.inc.get(cId968).linkedTo, linkedAt: wf967.inc.get(cId968).linkedAt, at: c.now } }) }
      val w971 = { ...w970, inc: w970.inc.set(cId968, { ...w970.inc.get(cId968), linkedTo: ps_964[0].id }) }
      val w972 = { ...w971, inc: w971.inc.set(cId968, { ...w971.inc.get(cId968), linkedAt: c.now }) }
      w972
    })
      w966
    } else w0
    w965
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_974 = c.form.primaryId
    val w975 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_974 }) }
    val w976 = { ...w975, inc: w975.inc.set(iid, { ...w975.inc.get(iid), linkedAt: c.now }) }
    w976
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_977 = ""
    val w978 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_977 }) }
    w978
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_979 = ""
    val w980 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_979 }) }
    w980
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w981 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w981
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w982 = if (timerDef("reaction").startsOnce) {
      val w983 = ec_pauseTimer(w0, c, iid, "reaction")
      w983
    } else {
      val w984 = if (false) {
      val w985 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w986 = { ...w985, inc: w985.inc.set(iid, { ...w985.inc.get(iid), timers: w985.inc.get(iid).timers.set("reaction", { ...w985.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w987 = { ...w986, inc: w986.inc.set(iid, { ...w986.inc.get(iid), timers: w986.inc.get(iid).timers.set("reaction", { ...w986.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w988 = { ...w987, inc: w987.inc.set(iid, { ...w987.inc.get(iid), timers: w987.inc.get(iid).timers.set("reaction", { ...w987.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w988
    } else {
      val w989 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_990 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w991 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_990) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w992 = { ...w991, inc: w991.inc.set(iid, { ...w991.inc.get(iid), timers: w991.inc.get(iid).timers.set("reaction", { ...w991.inc.get(iid).timers.get("reaction"), paused: keep_990 }) }) }
      val w993 = { ...w992, inc: w992.inc.set(iid, { ...w992.inc.get(iid), timers: w992.inc.get(iid).timers.set("reaction", { ...w992.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w994 = { ...w993, inc: w993.inc.set(iid, { ...w993.inc.get(iid), timers: w993.inc.get(iid).timers.set("reaction", { ...w993.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w994
    }
      w989
    }
      w984
    }
    w982
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w995 = if (not(timerDef("resolution").pausable)) {
      val w996 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w997 = { ...w996, inc: w996.inc.set(iid, { ...w996.inc.get(iid), timers: w996.inc.get(iid).timers.set("resolution", { ...w996.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w997
    } else {
      val w998 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w999 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w1000 = { ...w999, inc: w999.inc.set(iid, { ...w999.inc.get(iid), timers: w999.inc.get(iid).timers.set("resolution", { ...w999.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1001 = { ...w1000, inc: w1000.inc.set(iid, { ...w1000.inc.get(iid), timers: w1000.inc.get(iid).timers.set("resolution", { ...w1000.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w1001
    } else w0
      w998
    }
    w995
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_1002 = incidentById(incs(w0), c.form.primaryId)
    val w1003 = if (((((ps_1002.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_1002[0], "resolution", c.now)))) {
      val t_1004 = ps_1002[0].timers.get("resolution")
      val left_1005 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_1006 = (if ((t_1004.due != 0)) (t_1004.due - c.now) else (if (t_1004.paused) t_1004.left else (timerSec(ps_1002[0], "resolution", "") * 1000)))
      val w1007 = if ((left_1005 < was_1006)) {
      val w1008 = ps_1002.foldl([], (acc, x1011) => acc.append(x1011.id)).foldl(w0, (wf1009, pId1010) => {
      val w1012 = if ((t_1004.due != 0)) {
      val w1013 = { ...wf1009, inc: wf1009.inc.set(pId1010, { ...wf1009.inc.get(pId1010), timers: wf1009.inc.get(pId1010).timers.set("resolution", { ...wf1009.inc.get(pId1010).timers.get("resolution"), due: (c.now + left_1005) }) }) }
      w1013
    } else {
      val w1014 = { ...wf1009, inc: wf1009.inc.set(pId1010, { ...wf1009.inc.get(pId1010), timers: wf1009.inc.get(pId1010).timers.set("resolution", { ...wf1009.inc.get(pId1010).timers.get("resolution"), left: left_1005 }) }) }
      val w1015 = { ...w1014, inc: w1014.inc.set(pId1010, { ...w1014.inc.get(pId1010), timers: w1014.inc.get(pId1010).timers.set("resolution", { ...w1014.inc.get(pId1010).timers.get("resolution"), paused: true }) }) }
      w1015
    }
      w1012
    })
      w1008
    } else w0
      w1007
    } else w0
    w1003
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w1016 = if (timerDef("hold").startsOnce) {
      val w1017 = ec_pauseTimer(w0, c, iid, "hold")
      w1017
    } else {
      val w1018 = if (false) {
      val w1019 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w1020 = { ...w1019, inc: w1019.inc.set(iid, { ...w1019.inc.get(iid), timers: w1019.inc.get(iid).timers.set("hold", { ...w1019.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w1021 = { ...w1020, inc: w1020.inc.set(iid, { ...w1020.inc.get(iid), timers: w1020.inc.get(iid).timers.set("hold", { ...w1020.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w1022 = { ...w1021, inc: w1021.inc.set(iid, { ...w1021.inc.get(iid), timers: w1021.inc.get(iid).timers.set("hold", { ...w1021.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w1022
    } else {
      val w1023 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_1024 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w1025 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_1024) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w1026 = { ...w1025, inc: w1025.inc.set(iid, { ...w1025.inc.get(iid), timers: w1025.inc.get(iid).timers.set("hold", { ...w1025.inc.get(iid).timers.get("hold"), paused: keep_1024 }) }) }
      val w1027 = { ...w1026, inc: w1026.inc.set(iid, { ...w1026.inc.get(iid), timers: w1026.inc.get(iid).timers.set("hold", { ...w1026.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w1028 = { ...w1027, inc: w1027.inc.set(iid, { ...w1027.inc.get(iid), timers: w1027.inc.get(iid).timers.set("hold", { ...w1027.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w1028
    }
      w1023
    }
      w1018
    }
    w1016
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
    not(settings.session.states.foldl(false, (acc, s_1029) => acc or ((s_1029.id == agentState(c.me)) and s_1029.readOnly))),
    { val ps_1030 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1030.length() > 0) and ((ownership(c.me, ps_1030[0]) == "owner") or unowned(ps_1030[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_1031 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1032 = if (((ps_1031.length() > 0) and (leftOf(ps_1031[0], "resolution", c.now) >= 0))) {
      val w1033 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1034 = { ...w1033, inc: w1033.inc.set(iid, { ...w1033.inc.get(iid), timers: w1033.inc.get(iid).timers.set("resolution", { ...w1033.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1031[0], "resolution", c.now) }) }) }
      val w1035 = { ...w1034, inc: w1034.inc.set(iid, { ...w1034.inc.get(iid), timers: w1034.inc.get(iid).timers.set("resolution", { ...w1034.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1036 = if ((leftOf(ps_1031[0], "resolution", c.now) == 0)) {
      val w1037 = { ...w1035, inc: w1035.inc.set(iid, { ...w1035.inc.get(iid), timers: w1035.inc.get(iid).timers.set("resolution", { ...w1035.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1031[0], "resolution", c.now)) ps_1031[0].timers.get("resolution").fired else ps_1031[0].timers.get("resolution").due) }) }) }
      w1037
    } else w1035
      w1036
    } else w0
    w1032
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w1038 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1039 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1040 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1041 = { ...w1040, inc: w1040.inc.set(iid, { ...w1040.inc.get(iid), linkedTo: "" }) }
      val w1042 = { ...w1041, inc: w1041.inc.set(iid, { ...w1041.inc.get(iid), linkedAt: 0 }) }
      val w1043 = if (((ps_1039.length() > 0) and ("" != ""))) w1042 else w1042
      val w1044 = if (("" != "")) {
      val w1045 = ps_1039.foldl([], (acc, x1048) => acc.append(x1048.id)).foldl(w1043, (wf1046, pId1047) => wf1046)
      w1045
    } else w1043
      w1044
    } else {
      val w1049 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1050 = { ...w1049, inc: w1049.inc.set(iid, { ...w1049.inc.get(iid), linkedAt: 0 }) }
      w1050
    }
    w1038
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w1051 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1052 = if (timerDef("reaction").startsOnce) {
      val w1053 = ec_resumeTimer(w0, c, iid, "reaction")
      w1053
    } else {
      val w1054 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1055 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1056 = { ...w1055, inc: w1055.inc.set(iid, { ...w1055.inc.get(iid), timers: w1055.inc.get(iid).timers.set("reaction", { ...w1055.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1057 = { ...w1056, inc: w1056.inc.set(iid, { ...w1056.inc.get(iid), timers: w1056.inc.get(iid).timers.set("reaction", { ...w1056.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1057
    } else {
      val sec_1058 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w1059 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1058 < 0)) 0 else (c.now + (sec_1058 * 1000))) }) }) }
      val w1060 = { ...w1059, inc: w1059.inc.set(iid, { ...w1059.inc.get(iid), timers: w1059.inc.get(iid).timers.set("reaction", { ...w1059.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1061 = { ...w1060, inc: w1060.inc.set(iid, { ...w1060.inc.get(iid), timers: w1060.inc.get(iid).timers.set("reaction", { ...w1060.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1062 = { ...w1061, inc: w1061.inc.set(iid, { ...w1061.inc.get(iid), timers: w1061.inc.get(iid).timers.set("reaction", { ...w1061.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1062
    }
      w1054
    }
      w1052
    }
    w1051
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
    { val ps_1063 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1063.length() > 0) and isDone(ps_1063[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1064 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1065 = if ((ps_1064.length() > 0)) {
      val w1066 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_1064[0].closeResultId }) }
      val w1067 = { ...w1066, inc: w1066.inc.set(iid, { ...w1066.inc.get(iid), closeCauseId: ps_1064[0].closeCauseId }) }
      val w1068 = { ...w1067, inc: w1067.inc.set(iid, { ...w1067.inc.get(iid), closeCauseLabel: ps_1064[0].closeCauseLabel }) }
      val w1069 = { ...w1068, inc: w1068.inc.set(iid, { ...w1068.inc.get(iid), result: ps_1064[0].result }) }
      val w1070 = { ...w1069, inc: w1069.inc.set(iid, { ...w1069.inc.get(iid), closedBy: ps_1064[0].closedBy }) }
      val w1071 = { ...w1070, inc: w1070.inc.set(iid, { ...w1070.inc.get(iid), owner: ps_1064[0].closedBy }) }
      w1071
    } else w0
    w1065
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w1072 = if (not(timerDef("resolution").pausable)) {
      val w1073 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1074 = { ...w1073, inc: w1073.inc.set(iid, { ...w1073.inc.get(iid), timers: w1073.inc.get(iid).timers.set("resolution", { ...w1073.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w1074
    } else {
      val w1075 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w1076 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w1077 = { ...w1076, inc: w1076.inc.set(iid, { ...w1076.inc.get(iid), timers: w1076.inc.get(iid).timers.set("resolution", { ...w1076.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1078 = { ...w1077, inc: w1077.inc.set(iid, { ...w1077.inc.get(iid), timers: w1077.inc.get(iid).timers.set("resolution", { ...w1077.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w1078
    } else w0
      w1075
    }
    w1072
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_1079 = c.now
    val w1080 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_1079 }) }
    w1080
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {
    val w1081 = if ((w0.inc.get(iid).acceptedAt == 0)) {
      val w1082 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), noReaction: true }) }
      w1082
    } else w0
    w1081
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_5(w0: World, c: Ctx, iid: str): World = {
    val w1083 = if (["false_alarm"].foldl(false, (acc, y1084) => acc or y1084 == w0.inc.get(iid).closeResultId)) {
      val w1085 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1089 => not(isDone(x_1089))).foldl([], (acc, x1088) => acc.append(x1088.id)).foldl(w0, (wf1086, sId1087) => wf1086)
      w1085
    } else w0
    w1083
  }

  def e_close_linked_6(w0: World, c: Ctx, iid: str): World = {
    val w1090 = if (["false_alarm"].foldl(false, (acc, y1091) => acc or y1091 == w0.inc.get(iid).closeResultId)) {
      val w1092 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1099 => not(isDone(x_1099))).foldl([], (acc, x1095) => acc.append(x1095.id)).foldl(w0, (wf1093, sId1094) => {
      val lead_1096 = (if ((wf1093.inc.get(sId1094).linkedTo != "")) { val ps_1097 = incidentById(incs(w0), wf1093.inc.get(sId1094).linkedTo)  (if (((ps_1097.length() > 0) and not(isDone(ps_1097[0])))) addressee(ps_1097[0]) else "") } else addressee(wf1093.inc.get(sId1094)))
      val w1098 = if (((lead_1096 != "") and (lead_1096 != wf1093.inc.get(iid).closedBy))) wf1093 else wf1093
      w1098
    })
      w1092
    } else w0
    w1090
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
    { val ps_1100 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_1101 = (if (((ps_1100.length() > 0) and not(isDone(ps_1100[0])))) addressee(ps_1100[0]) else "")  ((who_1101 != "") and (hasAccess(who_1101, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1102 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1103 = if (((ps_1102.length() > 0) and (leftOf(ps_1102[0], "resolution", c.now) >= 0))) {
      val w1104 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1105 = { ...w1104, inc: w1104.inc.set(iid, { ...w1104.inc.get(iid), timers: w1104.inc.get(iid).timers.set("resolution", { ...w1104.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1102[0], "resolution", c.now) }) }) }
      val w1106 = { ...w1105, inc: w1105.inc.set(iid, { ...w1105.inc.get(iid), timers: w1105.inc.get(iid).timers.set("resolution", { ...w1105.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1107 = if ((leftOf(ps_1102[0], "resolution", c.now) == 0)) {
      val w1108 = { ...w1106, inc: w1106.inc.set(iid, { ...w1106.inc.get(iid), timers: w1106.inc.get(iid).timers.set("resolution", { ...w1106.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1102[0], "resolution", c.now)) ps_1102[0].timers.get("resolution").fired else ps_1102[0].timers.get("resolution").due) }) }) }
      w1108
    } else w1106
      w1107
    } else w0
    w1103
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w1109 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1110 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1111 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1112 = { ...w1111, inc: w1111.inc.set(iid, { ...w1111.inc.get(iid), linkedTo: "" }) }
      val w1113 = { ...w1112, inc: w1112.inc.set(iid, { ...w1112.inc.get(iid), linkedAt: 0 }) }
      val w1114 = if (((ps_1110.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w1113 else w1113
      val w1115 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w1116 = ps_1110.foldl([], (acc, x1119) => acc.append(x1119.id)).foldl(w1114, (wf1117, pId1118) => wf1117)
      w1116
    } else w1114
      w1115
    } else {
      val w1120 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1121 = { ...w1120, inc: w1120.inc.set(iid, { ...w1120.inc.get(iid), linkedAt: 0 }) }
      w1121
    }
    w1109
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w1122 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1123 = if (timerDef("reaction").startsOnce) {
      val w1124 = ec_resumeTimer(w0, c, iid, "reaction")
      w1124
    } else {
      val w1125 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1126 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1127 = { ...w1126, inc: w1126.inc.set(iid, { ...w1126.inc.get(iid), timers: w1126.inc.get(iid).timers.set("reaction", { ...w1126.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1128 = { ...w1127, inc: w1127.inc.set(iid, { ...w1127.inc.get(iid), timers: w1127.inc.get(iid).timers.set("reaction", { ...w1127.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1128
    } else {
      val sec_1129 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w1130 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1129 < 0)) 0 else (c.now + (sec_1129 * 1000))) }) }) }
      val w1131 = { ...w1130, inc: w1130.inc.set(iid, { ...w1130.inc.get(iid), timers: w1130.inc.get(iid).timers.set("reaction", { ...w1130.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1132 = { ...w1131, inc: w1131.inc.set(iid, { ...w1131.inc.get(iid), timers: w1131.inc.get(iid).timers.set("reaction", { ...w1131.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1133 = { ...w1132, inc: w1132.inc.set(iid, { ...w1132.inc.get(iid), timers: w1132.inc.get(iid).timers.set("reaction", { ...w1132.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1133
    }
      w1125
    }
      w1123
    }
    w1122
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_1134 = settings.alerts.target
    val w1135 = if (((whom_1134 != "") and (whom_1134 != c.actor))) w0 else w0
    w1135
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
      settings.holdReasons.foldl(false, (acc, r_1136) => acc or ((r_1136.id == c.form.reasonId) and (r_1136.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_1137) => acc and (isDone(e_1137) or hasAccess(c.form.targetId, e_1137))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_1138) => acc or (i_1138.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_1139) => acc or ((i_1139.id == c.form.resultId) and stepsOk(i_1139, world.inc.get(iid)))),
    },
    c.form.causeId == "" or all {
      settings.closeResults.foldl(false, (acc, i_1140) => acc or ((((i_1140.id == c.form.resultId) and (i_1140.causeCatalog != "")) and settings.causeCatalogs.keys().contains(i_1140.causeCatalog)) and (settings.causeCatalogs.get(i_1140.causeCatalog).items.length() > 0))),
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
    ["in_progress"].foldl(false, (acc, y1141) => acc or y1141 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_1142) => acc or ((s_1142.id == agentState(c.me)) and s_1142.readOnly))),
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
