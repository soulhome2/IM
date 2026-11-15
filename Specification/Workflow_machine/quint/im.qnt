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


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, closeCauseLabel: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], priorityManual: bool, maintenanceWindowId: str, closeMaintenanceWindowId: str, timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str, eventGuid: str, ruleDutyGroup: str }

  type Timer = { due: int, paused: bool, left: int, fired: int, since: int }

  type Breach = { kind: str, at: int, owner: str }

  type LeftGroup = { primaryId: str, linkedAt: int, at: int }

  type Form = { targetId: str, primaryId: str, resultId: str, reasonId: str, causeId: str, comment: str, files: List[FormFile], priority: str, maintenanceWindowId: str }

  type FormFile = { id: str, fileName: str, mime: str, size: int }

  type Limits = { maxActive: int, maxOnHold: int, maxBulk: int, reopenWindowMin: int, reopenResolutionSec: int, commentMaxLength: int, commentMaxFiles: int, attachmentMaxBytes: int, attachmentTypes: List[str] }

  type SessionState = { id: str, readOnly: bool, readOnlyReasonKey: str }

  type BreakReason = { id: str, labelKey: str }

  type Session = { states: List[SessionState], breakReasons: List[BreakReason], heartbeatSec: int, idleHoldSec: int, idleReleaseSec: int }

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

  type Settings = { limits: Limits, session: Session, escalation: Escalation, alerts: Alerts, states: List[State], closeResults: List[CloseResultItem], timerDefs: List[TimerDef], holdReasons: List[HoldReason], causeCatalogs: str -> CauseCatalog, maintenance: Maintenance }


  /* ===== Настройки — значения машины (cel.settings) ===== */


  pure val MACHINE_SETTINGS: Settings = {
    limits: { maxActive: 0, maxOnHold: 5, maxBulk: 0, reopenWindowMin: 1440, reopenResolutionSec: 0, commentMaxLength: 2000, commentMaxFiles: 5, attachmentMaxBytes: 10485760, attachmentTypes: ["image/jpeg", "image/png", "application/pdf"] },
    session: { states: [{ id: "ready", readOnly: false, readOnlyReasonKey: "" }, { id: "busy", readOnly: false, readOnlyReasonKey: "" }, { id: "not_ready", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.not_ready" }, { id: "offline", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.offline" }], breakReasons: [{ id: "lunch", labelKey: "workflow.session.break.lunch" }, { id: "briefing", labelKey: "workflow.session.break.briefing" }, { id: "patrol", labelKey: "workflow.session.break.patrol" }], heartbeatSec: 30, idleHoldSec: 300, idleReleaseSec: 1200 },
    escalation: { enabled: true, levels: [{ level: 1, targetKind: "user", target: "petrova", reactionSec: 120 }, { level: 2, targetKind: "user", target: "noc", reactionSec: 90 }], maxLevel: 2, onResolutionOverdue: "alert" },
    alerts: { targetKind: "group", target: "grp-leads", noRecipientLog: "workflow.journal.alert_no_recipient" },
    states: [{ id: "new", category: "pending" }, { id: "pending_acceptance", category: "pending" }, { id: "in_progress", category: "active" }, { id: "on_hold", category: "active" }, { id: "closed", category: "done" }, { id: "linked", category: "linked" }],
    closeResults: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "closing", commentRequired: false, finish: true, causeCatalog: "" }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: false, finish: false, causeCatalog: "false_alarm_cause" }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false, causeCatalog: "" }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false, causeCatalog: "" }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false, causeCatalog: "" }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", permission: "incident:close:unprocessed", fromStates: ["new", "pending_acceptance", "in_progress", "on_hold"], ownerOnlyInStates: ["in_progress", "on_hold"], surfaces: ["queue", "card"], requiredStepSet: "none", commentRequired: true, finish: false, causeCatalog: "mass_fault" }],
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overridesBy: ["eventType", "priority", "sourceGroup", "scenario"], overrides: [{ eventType: [], priority: [100], sourceGroup: [], scenario: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], scenario: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], scenario: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], scenario: [], sec: 1800 }], keepsLeft: true, startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overridesBy: ["eventType", "priority", "sourceGroup", "scenario"], overrides: [], keepsLeft: false, startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overridesBy: [], overrides: [], keepsLeft: false, startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
    holdReasons: [{ id: "break", maxMinutes: [30], setBy: "system", deadlineFromIdle: false }, { id: "no_link", maxMinutes: [], setBy: "system", deadlineFromIdle: true }, { id: "third_party", maxMinutes: [30], setBy: "operator", deadlineFromIdle: false }, { id: "patrol", maxMinutes: [45], setBy: "operator", deadlineFromIdle: false }, { id: "no_data", maxMinutes: [60], setBy: "operator", deadlineFromIdle: false }],
    causeCatalogs: Map("hold" -> { items: [{ id: "break", labelKey: "workflow.catalog.hold.break", commentRequired: false }, { id: "no_link", labelKey: "workflow.catalog.hold.no_link", commentRequired: false }, { id: "third_party", labelKey: "workflow.catalog.hold.third_party", commentRequired: false }, { id: "patrol", labelKey: "workflow.catalog.hold.patrol", commentRequired: false }, { id: "no_data", labelKey: "workflow.catalog.hold.no_data", commentRequired: false }] }, "close_result" -> { items: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", commentRequired: false }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", commentRequired: false }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", commentRequired: true }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", commentRequired: true }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", commentRequired: true }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", commentRequired: true }] }, "mass_fault" -> { items: [{ id: "power", labelKey: "workflow.catalog.mass_fault.power", commentRequired: false }, { id: "link", labelKey: "workflow.catalog.mass_fault.link", commentRequired: false }, { id: "mass_fault", labelKey: "workflow.catalog.mass_fault.mass_fault", commentRequired: false }, { id: "known", labelKey: "workflow.catalog.mass_fault.known", commentRequired: false }] }, "false_alarm_cause" -> { items: [{ id: "animal", labelKey: "workflow.catalog.false_alarm_cause.animal", commentRequired: false }, { id: "weather", labelKey: "workflow.catalog.false_alarm_cause.weather", commentRequired: false }, { id: "equipment", labelKey: "workflow.catalog.false_alarm_cause.equipment", commentRequired: false }, { id: "staff", labelKey: "workflow.catalog.false_alarm_cause.staff", commentRequired: false }, { id: "setup", labelKey: "workflow.catalog.false_alarm_cause.setup", commentRequired: false }, { id: "other", labelKey: "workflow.catalog.false_alarm_cause.other", commentRequired: true }] }),
    maintenance: { mode: "suppress", modes: ["suppress", "mark"], markPriority: "lowest", startSkewSec: 300 },
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

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", closeCauseLabel: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], priorityManual: false, maintenanceWindowId: "", closeMaintenanceWindowId: "", timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "", eventGuid: "", ruleDutyGroup: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

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
    not(settings.session.states.foldl(false, (acc, s_187) => acc or ((s_187.id == agentState(c.me)) and s_187.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_188 = c.actor
    val w189 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_188 }) }
    w189
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_190 = ""
    val w191 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_190 }) }
    w191
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w192 = if (timerDef("reaction").startsOnce) {
      val w193 = ec_pauseTimer(w0, c, iid, "reaction")
      w193
    } else {
      val w194 = if (false) {
      val w195 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w196 = { ...w195, inc: w195.inc.set(iid, { ...w195.inc.get(iid), timers: w195.inc.get(iid).timers.set("reaction", { ...w195.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w197 = { ...w196, inc: w196.inc.set(iid, { ...w196.inc.get(iid), timers: w196.inc.get(iid).timers.set("reaction", { ...w196.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w198 = { ...w197, inc: w197.inc.set(iid, { ...w197.inc.get(iid), timers: w197.inc.get(iid).timers.set("reaction", { ...w197.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w198
    } else {
      val w199 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_200 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w201 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_200) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w202 = { ...w201, inc: w201.inc.set(iid, { ...w201.inc.get(iid), timers: w201.inc.get(iid).timers.set("reaction", { ...w201.inc.get(iid).timers.get("reaction"), paused: keep_200 }) }) }
      val w203 = { ...w202, inc: w202.inc.set(iid, { ...w202.inc.get(iid), timers: w202.inc.get(iid).timers.set("reaction", { ...w202.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w204 = { ...w203, inc: w203.inc.set(iid, { ...w203.inc.get(iid), timers: w203.inc.get(iid).timers.set("reaction", { ...w203.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w204
    }
      w199
    }
      w194
    }
    w192
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w205 = if (not(timerDef("resolution").pausable)) {
      val sec_206 = timerSec(w0.inc.get(iid), "resolution", "")
      val w207 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_206 < 0)) 0 else (c.now + (sec_206 * 1000))) }) }) }
      val w208 = { ...w207, inc: w207.inc.set(iid, { ...w207.inc.get(iid), timers: w207.inc.get(iid).timers.set("resolution", { ...w207.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w208
    } else {
      val w209 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_210 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w211 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_210 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_210)) }) }) }
      val w212 = { ...w211, inc: w211.inc.set(iid, { ...w211.inc.get(iid), timers: w211.inc.get(iid).timers.set("resolution", { ...w211.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w213 = { ...w212, inc: w212.inc.set(iid, { ...w212.inc.get(iid), timers: w212.inc.get(iid).timers.set("resolution", { ...w212.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w213
    } else w0
      w209
    }
    w205
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
    not(settings.session.states.foldl(false, (acc, s_214) => acc or ((s_214.id == agentState(c.me)) and s_214.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_215 = ""
    val w216 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_215 }) }
    w216
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_217 = ""
    val w218 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_217 }) }
    w218
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
    not(settings.session.states.foldl(false, (acc, s_219) => acc or ((s_219.id == agentState(c.me)) and s_219.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
    settings.holdReasons.foldl(false, (acc, r_220) => acc or (r_220.setBy != "system")),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_221 = c.form.reasonId
    val w222 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_221 }) }
    w222
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w223 = if (not(timerDef("resolution").pausable)) {
      val w224 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w225 = { ...w224, inc: w224.inc.set(iid, { ...w224.inc.get(iid), timers: w224.inc.get(iid).timers.set("resolution", { ...w224.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w225
    } else {
      val w226 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w227 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w228 = { ...w227, inc: w227.inc.set(iid, { ...w227.inc.get(iid), timers: w227.inc.get(iid).timers.set("resolution", { ...w227.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w229 = { ...w228, inc: w228.inc.set(iid, { ...w228.inc.get(iid), timers: w228.inc.get(iid).timers.set("resolution", { ...w228.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w229
    } else w0
      w226
    }
    w223
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w230 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w231 = if (timerDef("hold").startsOnce) {
      val w232 = ec_resumeTimer(w0, c, iid, "hold")
      w232
    } else {
      val w233 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w234 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w235 = { ...w234, inc: w234.inc.set(iid, { ...w234.inc.get(iid), timers: w234.inc.get(iid).timers.set("hold", { ...w234.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w236 = { ...w235, inc: w235.inc.set(iid, { ...w235.inc.get(iid), timers: w235.inc.get(iid).timers.set("hold", { ...w235.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w236
    } else {
      val sec_237 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w238 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_237 < 0)) 0 else (c.now + (sec_237 * 1000))) }) }) }
      val w239 = { ...w238, inc: w238.inc.set(iid, { ...w238.inc.get(iid), timers: w238.inc.get(iid).timers.set("hold", { ...w238.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w240 = { ...w239, inc: w239.inc.set(iid, { ...w239.inc.get(iid), timers: w239.inc.get(iid).timers.set("hold", { ...w239.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w241 = { ...w240, inc: w240.inc.set(iid, { ...w240.inc.get(iid), timers: w240.inc.get(iid).timers.set("hold", { ...w240.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w241
    }
      w233
    }
      w231
    }
    w230
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
    not(settings.session.states.foldl(false, (acc, s_242) => acc or ((s_242.id == agentState(c.me)) and s_242.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w243 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w243
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w244 = if (timerDef("hold").startsOnce) {
      val w245 = ec_pauseTimer(w0, c, iid, "hold")
      w245
    } else {
      val w246 = if (false) {
      val w247 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w248 = { ...w247, inc: w247.inc.set(iid, { ...w247.inc.get(iid), timers: w247.inc.get(iid).timers.set("hold", { ...w247.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w249 = { ...w248, inc: w248.inc.set(iid, { ...w248.inc.get(iid), timers: w248.inc.get(iid).timers.set("hold", { ...w248.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w250 = { ...w249, inc: w249.inc.set(iid, { ...w249.inc.get(iid), timers: w249.inc.get(iid).timers.set("hold", { ...w249.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w250
    } else {
      val w251 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_252 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w253 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_252) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("hold", { ...w253.inc.get(iid).timers.get("hold"), paused: keep_252 }) }) }
      val w255 = { ...w254, inc: w254.inc.set(iid, { ...w254.inc.get(iid), timers: w254.inc.get(iid).timers.set("hold", { ...w254.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w256 = { ...w255, inc: w255.inc.set(iid, { ...w255.inc.get(iid), timers: w255.inc.get(iid).timers.set("hold", { ...w255.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w256
    }
      w251
    }
      w246
    }
    w244
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w257 = if (not(timerDef("resolution").pausable)) {
      val sec_258 = timerSec(w0.inc.get(iid), "resolution", "")
      val w259 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_258 < 0)) 0 else (c.now + (sec_258 * 1000))) }) }) }
      val w260 = { ...w259, inc: w259.inc.set(iid, { ...w259.inc.get(iid), timers: w259.inc.get(iid).timers.set("resolution", { ...w259.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w260
    } else {
      val w261 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_262 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w263 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_262 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_262)) }) }) }
      val w264 = { ...w263, inc: w263.inc.set(iid, { ...w263.inc.get(iid), timers: w263.inc.get(iid).timers.set("resolution", { ...w263.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w265 = { ...w264, inc: w264.inc.set(iid, { ...w264.inc.get(iid), timers: w264.inc.get(iid).timers.set("resolution", { ...w264.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w265
    } else w0
      w261
    }
    w257
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
    not(settings.session.states.foldl(false, (acc, s_266) => acc or ((s_266.id == agentState(c.me)) and s_266.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_267 = ""
    val w268 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_267 }) }
    w268
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w269 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w269
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w270 = if (not(timerDef("resolution").pausable)) {
      val w271 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w272 = { ...w271, inc: w271.inc.set(iid, { ...w271.inc.get(iid), timers: w271.inc.get(iid).timers.set("resolution", { ...w271.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w272
    } else {
      val w273 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w274 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w275 = { ...w274, inc: w274.inc.set(iid, { ...w274.inc.get(iid), timers: w274.inc.get(iid).timers.set("resolution", { ...w274.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w276 = { ...w275, inc: w275.inc.set(iid, { ...w275.inc.get(iid), timers: w275.inc.get(iid).timers.set("resolution", { ...w275.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w276
    } else w0
      w273
    }
    w270
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w277 = if (timerDef("hold").startsOnce) {
      val w278 = ec_pauseTimer(w0, c, iid, "hold")
      w278
    } else {
      val w279 = if (false) {
      val w280 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w281 = { ...w280, inc: w280.inc.set(iid, { ...w280.inc.get(iid), timers: w280.inc.get(iid).timers.set("hold", { ...w280.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w282 = { ...w281, inc: w281.inc.set(iid, { ...w281.inc.get(iid), timers: w281.inc.get(iid).timers.set("hold", { ...w281.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w283 = { ...w282, inc: w282.inc.set(iid, { ...w282.inc.get(iid), timers: w282.inc.get(iid).timers.set("hold", { ...w282.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w283
    } else {
      val w284 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_285 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w286 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_285) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w287 = { ...w286, inc: w286.inc.set(iid, { ...w286.inc.get(iid), timers: w286.inc.get(iid).timers.set("hold", { ...w286.inc.get(iid).timers.get("hold"), paused: keep_285 }) }) }
      val w288 = { ...w287, inc: w287.inc.set(iid, { ...w287.inc.get(iid), timers: w287.inc.get(iid).timers.set("hold", { ...w287.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w289 = { ...w288, inc: w288.inc.set(iid, { ...w288.inc.get(iid), timers: w288.inc.get(iid).timers.set("hold", { ...w288.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w289
    }
      w284
    }
      w279
    }
    w277
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w290 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w291 = if (timerDef("reaction").startsOnce) {
      val w292 = ec_resumeTimer(w0, c, iid, "reaction")
      w292
    } else {
      val w293 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w294 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w295 = { ...w294, inc: w294.inc.set(iid, { ...w294.inc.get(iid), timers: w294.inc.get(iid).timers.set("reaction", { ...w294.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("reaction", { ...w295.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w296
    } else {
      val sec_297 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w298 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_297 < 0)) 0 else (c.now + (sec_297 * 1000))) }) }) }
      val w299 = { ...w298, inc: w298.inc.set(iid, { ...w298.inc.get(iid), timers: w298.inc.get(iid).timers.set("reaction", { ...w298.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w300 = { ...w299, inc: w299.inc.set(iid, { ...w299.inc.get(iid), timers: w299.inc.get(iid).timers.set("reaction", { ...w299.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w301 = { ...w300, inc: w300.inc.set(iid, { ...w300.inc.get(iid), timers: w300.inc.get(iid).timers.set("reaction", { ...w300.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w301
    }
      w293
    }
      w291
    }
    w290
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
    not(settings.session.states.foldl(false, (acc, s_302) => acc or ((s_302.id == agentState(c.me)) and s_302.readOnly))),
    transferTargets.foldl(false, (acc, t_303) => acc or (offersTransferTo(c.me, t_303, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_304) => acc and (isDone(e_304) or hasAccess(t_303, e_304))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_305) => acc and (isDone(e_305) or hasAccess(c.form.targetId, e_305)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_306 = personOf(c.form.targetId)
    val w307 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_306 }) }
    w307
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_308 = groupOf(c.form.targetId)
    val w309 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_308 }) }
    w309
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w310 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w310
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w311 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w311
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w312 = if (not(timerDef("resolution").pausable)) {
      val w313 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w314 = { ...w313, inc: w313.inc.set(iid, { ...w313.inc.get(iid), timers: w313.inc.get(iid).timers.set("resolution", { ...w313.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w314
    } else {
      val w315 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w316 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w317 = { ...w316, inc: w316.inc.set(iid, { ...w316.inc.get(iid), timers: w316.inc.get(iid).timers.set("resolution", { ...w316.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w318 = { ...w317, inc: w317.inc.set(iid, { ...w317.inc.get(iid), timers: w317.inc.get(iid).timers.set("resolution", { ...w317.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w318
    } else w0
      w315
    }
    w312
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w319 = if (timerDef("hold").startsOnce) {
      val w320 = ec_pauseTimer(w0, c, iid, "hold")
      w320
    } else {
      val w321 = if (false) {
      val w322 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w323 = { ...w322, inc: w322.inc.set(iid, { ...w322.inc.get(iid), timers: w322.inc.get(iid).timers.set("hold", { ...w322.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w324 = { ...w323, inc: w323.inc.set(iid, { ...w323.inc.get(iid), timers: w323.inc.get(iid).timers.set("hold", { ...w323.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w325 = { ...w324, inc: w324.inc.set(iid, { ...w324.inc.get(iid), timers: w324.inc.get(iid).timers.set("hold", { ...w324.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w325
    } else {
      val w326 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_327 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w328 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_327) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w329 = { ...w328, inc: w328.inc.set(iid, { ...w328.inc.get(iid), timers: w328.inc.get(iid).timers.set("hold", { ...w328.inc.get(iid).timers.get("hold"), paused: keep_327 }) }) }
      val w330 = { ...w329, inc: w329.inc.set(iid, { ...w329.inc.get(iid), timers: w329.inc.get(iid).timers.set("hold", { ...w329.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w331 = { ...w330, inc: w330.inc.set(iid, { ...w330.inc.get(iid), timers: w330.inc.get(iid).timers.set("hold", { ...w330.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w331
    }
      w326
    }
      w321
    }
    w319
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w332 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w333 = if (timerDef("reaction").startsOnce) {
      val w334 = ec_resumeTimer(w0, c, iid, "reaction")
      w334
    } else {
      val w335 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w336 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w337 = { ...w336, inc: w336.inc.set(iid, { ...w336.inc.get(iid), timers: w336.inc.get(iid).timers.set("reaction", { ...w336.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w338 = { ...w337, inc: w337.inc.set(iid, { ...w337.inc.get(iid), timers: w337.inc.get(iid).timers.set("reaction", { ...w337.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w338
    } else {
      val sec_339 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w340 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_339 < 0)) 0 else (c.now + (sec_339 * 1000))) }) }) }
      val w341 = { ...w340, inc: w340.inc.set(iid, { ...w340.inc.get(iid), timers: w340.inc.get(iid).timers.set("reaction", { ...w340.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w342 = { ...w341, inc: w341.inc.set(iid, { ...w341.inc.get(iid), timers: w341.inc.get(iid).timers.set("reaction", { ...w341.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w343 = { ...w342, inc: w342.inc.set(iid, { ...w342.inc.get(iid), timers: w342.inc.get(iid).timers.set("reaction", { ...w342.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w343
    }
      w335
    }
      w333
    }
    w332
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_344 = c.before.owner
    val w345 = if (((whom_344 != "") and (whom_344 != c.actor))) w0 else w0
    w345
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_346 = addressee(w0.inc.get(iid))
    val w347 = if (((whom_346 != "") and (whom_346 != c.actor))) w0 else w0
    w347
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
    not(settings.session.states.foldl(false, (acc, s_348) => acc or ((s_348.id == agentState(c.me)) and s_348.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_349 = c.actor
    val w350 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_349 }) }
    w350
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_351 = ""
    val w352 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_351 }) }
    w352
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w353 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w353
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w354 = if (timerDef("reaction").startsOnce) {
      val w355 = ec_pauseTimer(w0, c, iid, "reaction")
      w355
    } else {
      val w356 = if (false) {
      val w357 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w358 = { ...w357, inc: w357.inc.set(iid, { ...w357.inc.get(iid), timers: w357.inc.get(iid).timers.set("reaction", { ...w357.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w359 = { ...w358, inc: w358.inc.set(iid, { ...w358.inc.get(iid), timers: w358.inc.get(iid).timers.set("reaction", { ...w358.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w360 = { ...w359, inc: w359.inc.set(iid, { ...w359.inc.get(iid), timers: w359.inc.get(iid).timers.set("reaction", { ...w359.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w360
    } else {
      val w361 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_362 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w363 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_362) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w364 = { ...w363, inc: w363.inc.set(iid, { ...w363.inc.get(iid), timers: w363.inc.get(iid).timers.set("reaction", { ...w363.inc.get(iid).timers.get("reaction"), paused: keep_362 }) }) }
      val w365 = { ...w364, inc: w364.inc.set(iid, { ...w364.inc.get(iid), timers: w364.inc.get(iid).timers.set("reaction", { ...w364.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w366 = { ...w365, inc: w365.inc.set(iid, { ...w365.inc.get(iid), timers: w365.inc.get(iid).timers.set("reaction", { ...w365.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w366
    }
      w361
    }
      w356
    }
    w354
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w367 = if (timerDef("hold").startsOnce) {
      val w368 = ec_pauseTimer(w0, c, iid, "hold")
      w368
    } else {
      val w369 = if (false) {
      val w370 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w371 = { ...w370, inc: w370.inc.set(iid, { ...w370.inc.get(iid), timers: w370.inc.get(iid).timers.set("hold", { ...w370.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w372 = { ...w371, inc: w371.inc.set(iid, { ...w371.inc.get(iid), timers: w371.inc.get(iid).timers.set("hold", { ...w371.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w373 = { ...w372, inc: w372.inc.set(iid, { ...w372.inc.get(iid), timers: w372.inc.get(iid).timers.set("hold", { ...w372.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w373
    } else {
      val w374 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_375 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w376 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_375) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w377 = { ...w376, inc: w376.inc.set(iid, { ...w376.inc.get(iid), timers: w376.inc.get(iid).timers.set("hold", { ...w376.inc.get(iid).timers.get("hold"), paused: keep_375 }) }) }
      val w378 = { ...w377, inc: w377.inc.set(iid, { ...w377.inc.get(iid), timers: w377.inc.get(iid).timers.set("hold", { ...w377.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w379 = { ...w378, inc: w378.inc.set(iid, { ...w378.inc.get(iid), timers: w378.inc.get(iid).timers.set("hold", { ...w378.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w379
    }
      w374
    }
      w369
    }
    w367
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w380 = if (not(timerDef("resolution").pausable)) {
      val sec_381 = timerSec(w0.inc.get(iid), "resolution", "")
      val w382 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_381 < 0)) 0 else (c.now + (sec_381 * 1000))) }) }) }
      val w383 = { ...w382, inc: w382.inc.set(iid, { ...w382.inc.get(iid), timers: w382.inc.get(iid).timers.set("resolution", { ...w382.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w383
    } else {
      val w384 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_385 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w386 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_385 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_385)) }) }) }
      val w387 = { ...w386, inc: w386.inc.set(iid, { ...w386.inc.get(iid), timers: w386.inc.get(iid).timers.set("resolution", { ...w386.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w388 = { ...w387, inc: w387.inc.set(iid, { ...w387.inc.get(iid), timers: w387.inc.get(iid).timers.set("resolution", { ...w387.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w388
    } else w0
      w384
    }
    w380
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
    val whom_389 = c.before.owner
    val w390 = if (((whom_389 != "") and (whom_389 != c.actor))) w0 else w0
    w390
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
    not(settings.session.states.foldl(false, (acc, s_391) => acc or ((s_391.id == agentState(c.me)) and s_391.readOnly))),
    { val os_392 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_392.foldl(false, (acc, o_393) => acc or ((o_393.id == c.form.resultId) and stepsOk(o_393, world.inc.get(iid)))) else os_392.foldl(false, (acc, o_394) => acc or stepsOk(o_394, world.inc.get(iid)))) },
    ((((c.form.resultId == "") or (c.form.causeId == "")) or not(settings.closeResults.foldl(false, (acc, i_395) => acc or ((i_395.id == c.form.resultId) and (i_395.causeCatalog != ""))))) or (causeOk(c.form.resultId, c.form.causeId) and (not(causeCommentRequired(c.form.resultId, c.form.causeId)) or (c.form.comment != "")))),
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_396 = c.actor
    val w397 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_396 }) }
    w397
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_398 = ""
    val w399 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_398 }) }
    w399
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_400 = c.actor
    val w401 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_400 }) }
    w401
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_402 = c.now
    val w403 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_402 }) }
    w403
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_404 = c.form.resultId
    val w405 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_404 }) }
    w405
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_406 = (if (causeOk(c.form.resultId, c.form.causeId)) c.form.causeId else "")
    val w407 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_406 }) }
    w407
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_408 = causeLabel(c.form.resultId, c.form.causeId)
    val w409 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_408 }) }
    w409
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val value_410 = (if ((c.form.resultId == "drill")) c.form.maintenanceWindowId else "")
    val w411 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_410 }) }
    w411
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val value_412 = c.form.comment
    val w413 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_412 }) }
    w413
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w414 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w414
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w415 = if (timerDef("reaction").startsOnce) {
      val w416 = ec_pauseTimer(w0, c, iid, "reaction")
      w416
    } else {
      val w417 = if (true) {
      val w418 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w419 = { ...w418, inc: w418.inc.set(iid, { ...w418.inc.get(iid), timers: w418.inc.get(iid).timers.set("reaction", { ...w418.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w420 = { ...w419, inc: w419.inc.set(iid, { ...w419.inc.get(iid), timers: w419.inc.get(iid).timers.set("reaction", { ...w419.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w421 = { ...w420, inc: w420.inc.set(iid, { ...w420.inc.get(iid), timers: w420.inc.get(iid).timers.set("reaction", { ...w420.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w421
    } else {
      val w422 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_423 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w424 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_423) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w425 = { ...w424, inc: w424.inc.set(iid, { ...w424.inc.get(iid), timers: w424.inc.get(iid).timers.set("reaction", { ...w424.inc.get(iid).timers.get("reaction"), paused: keep_423 }) }) }
      val w426 = { ...w425, inc: w425.inc.set(iid, { ...w425.inc.get(iid), timers: w425.inc.get(iid).timers.set("reaction", { ...w425.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w427 = { ...w426, inc: w426.inc.set(iid, { ...w426.inc.get(iid), timers: w426.inc.get(iid).timers.set("reaction", { ...w426.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w427
    }
      w422
    }
      w417
    }
    w415
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {
    val w428 = if (not(timerDef("resolution").pausable)) {
      val w429 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w430 = { ...w429, inc: w429.inc.set(iid, { ...w429.inc.get(iid), timers: w429.inc.get(iid).timers.set("resolution", { ...w429.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w430
    } else {
      val w431 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w432 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w433 = { ...w432, inc: w432.inc.set(iid, { ...w432.inc.get(iid), timers: w432.inc.get(iid).timers.set("resolution", { ...w432.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w434 = { ...w433, inc: w433.inc.set(iid, { ...w433.inc.get(iid), timers: w433.inc.get(iid).timers.set("resolution", { ...w433.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w434
    } else w0
      w431
    }
    w428
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {
    val w435 = if (timerDef("hold").startsOnce) {
      val w436 = ec_pauseTimer(w0, c, iid, "hold")
      w436
    } else {
      val w437 = if (false) {
      val w438 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w439 = { ...w438, inc: w438.inc.set(iid, { ...w438.inc.get(iid), timers: w438.inc.get(iid).timers.set("hold", { ...w438.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w440 = { ...w439, inc: w439.inc.set(iid, { ...w439.inc.get(iid), timers: w439.inc.get(iid).timers.set("hold", { ...w439.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w441 = { ...w440, inc: w440.inc.set(iid, { ...w440.inc.get(iid), timers: w440.inc.get(iid).timers.set("hold", { ...w440.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w441
    } else {
      val w442 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_443 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w444 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_443) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w445 = { ...w444, inc: w444.inc.set(iid, { ...w444.inc.get(iid), timers: w444.inc.get(iid).timers.set("hold", { ...w444.inc.get(iid).timers.get("hold"), paused: keep_443 }) }) }
      val w446 = { ...w445, inc: w445.inc.set(iid, { ...w445.inc.get(iid), timers: w445.inc.get(iid).timers.set("hold", { ...w445.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w447 = { ...w446, inc: w446.inc.set(iid, { ...w446.inc.get(iid), timers: w446.inc.get(iid).timers.set("hold", { ...w446.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w447
    }
      w442
    }
      w437
    }
    w435
  }

  def e_close_13(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_14(w0: World, c: Ctx, iid: str): World = {
    val w448 = if (["false_alarm"].foldl(false, (acc, y449) => acc or y449 == w0.inc.get(iid).closeResultId)) {
      val w450 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_454 => not(isDone(x_454))).foldl([], (acc, x453) => acc.append(x453.id)).foldl(w0, (wf451, sId452) => wf451)
      w450
    } else w0
    w448
  }

  def e_close_15(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_16(w0: World, c: Ctx, iid: str): World = {
    val w455 = if (["false_alarm"].foldl(false, (acc, y456) => acc or y456 == w0.inc.get(iid).closeResultId)) {
      val w457 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_464 => not(isDone(x_464))).foldl([], (acc, x460) => acc.append(x460.id)).foldl(w0, (wf458, sId459) => {
      val lead_461 = (if ((wf458.inc.get(sId459).linkedTo != "")) { val ps_462 = incidentById(incs(w0), wf458.inc.get(sId459).linkedTo)  (if (((ps_462.length() > 0) and not(isDone(ps_462[0])))) addressee(ps_462[0]) else "") } else addressee(wf458.inc.get(sId459)))
      val w463 = if (((lead_461 != "") and (lead_461 != wf458.inc.get(iid).closedBy))) wf458 else wf458
      w463
    })
      w457
    } else w0
    w455
  }

  def e_close_17(w0: World, c: Ctx, iid: str): World = {

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
    w18
  }

  // reopen: manual → in_progress

  def ok_reopen(c: Ctx, iid: str): bool = all {
    Set("closed").contains(world.inc.get(iid).state),
    can(c.me, "incident:reopen"),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_465) => acc or ((s_465.id == agentState(c.me)) and s_465.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_466 = c.actor
    val w467 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_466 }) }
    w467
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w468 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_469 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w470 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w471 = { ...w470, inc: w470.inc.set(iid, { ...w470.inc.get(iid), linkedTo: "" }) }
      val w472 = { ...w471, inc: w471.inc.set(iid, { ...w471.inc.get(iid), linkedAt: 0 }) }
      val w473 = if (((ps_469.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w472 else w472
      val w474 = if (("workflow.journal.linked_reopened" != "")) {
      val w475 = ps_469.foldl([], (acc, x478) => acc.append(x478.id)).foldl(w473, (wf476, pId477) => wf476)
      w475
    } else w473
      w474
    } else {
      val w479 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w480 = { ...w479, inc: w479.inc.set(iid, { ...w479.inc.get(iid), linkedAt: 0 }) }
      w480
    }
    w468
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_481 = ""
    val w482 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_481 }) }
    w482
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_483 = ""
    val w484 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_483 }) }
    w484
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_485 = ""
    val w486 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_485 }) }
    w486
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_487 = ""
    val w488 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_487 }) }
    w488
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_489 = ""
    val w490 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_489 }) }
    w490
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val value_491 = 0
    val w492 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_491 }) }
    w492
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val value_493 = ""
    val w494 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_493 }) }
    w494
  }

  def e_reopen_10(w0: World, c: Ctx, iid: str): World = {
    val sec_495 = settings.limits.reopenResolutionSec
    val w496 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_495 > 0)) sec_495 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w497 = { ...w496, inc: w496.inc.set(iid, { ...w496.inc.get(iid), timers: w496.inc.get(iid).timers.set("resolution", { ...w496.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w498 = { ...w497, inc: w497.inc.set(iid, { ...w497.inc.get(iid), timers: w497.inc.get(iid).timers.set("resolution", { ...w497.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w498
  }

  def e_reopen_11(w0: World, c: Ctx, iid: str): World = {
    val w499 = if (timerDef("reaction").startsOnce) {
      val w500 = ec_pauseTimer(w0, c, iid, "reaction")
      w500
    } else {
      val w501 = if (true) {
      val w502 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w503 = { ...w502, inc: w502.inc.set(iid, { ...w502.inc.get(iid), timers: w502.inc.get(iid).timers.set("reaction", { ...w502.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w504 = { ...w503, inc: w503.inc.set(iid, { ...w503.inc.get(iid), timers: w503.inc.get(iid).timers.set("reaction", { ...w503.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w505 = { ...w504, inc: w504.inc.set(iid, { ...w504.inc.get(iid), timers: w504.inc.get(iid).timers.set("reaction", { ...w504.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w505
    } else {
      val w506 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_507 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w508 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_507) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w509 = { ...w508, inc: w508.inc.set(iid, { ...w508.inc.get(iid), timers: w508.inc.get(iid).timers.set("reaction", { ...w508.inc.get(iid).timers.get("reaction"), paused: keep_507 }) }) }
      val w510 = { ...w509, inc: w509.inc.set(iid, { ...w509.inc.get(iid), timers: w509.inc.get(iid).timers.set("reaction", { ...w509.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w511 = { ...w510, inc: w510.inc.set(iid, { ...w510.inc.get(iid), timers: w510.inc.get(iid).timers.set("reaction", { ...w510.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w511
    }
      w506
    }
      w501
    }
    w499
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
    not(settings.session.states.foldl(false, (acc, s_512) => acc or ((s_512.id == agentState(c.me)) and s_512.readOnly))),
    ((if (c.form.comment == "") 0 else 1) <= settings.limits.commentMaxLength),
    (c.form.files.length() <= settings.limits.commentMaxFiles),
    c.form.files.foldl(true, (acc, f_513) => acc and (f_513.size <= settings.limits.attachmentMaxBytes)),
    c.form.files.foldl(true, (acc, f_514) => acc and settings.limits.attachmentTypes.foldl(false, (acc, y515) => acc or y515 == f_514.mime)),
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
    not(settings.session.states.foldl(false, (acc, s_516) => acc or ((s_516.id == agentState(c.me)) and s_516.readOnly))),
    ((c.form.priority == "") or (priorityOf(c.form.priority) != world.inc.get(iid).priority)),
  }

  def e_change_priority_0(w0: World, c: Ctx, iid: str): World = {
    val value_517 = priorityOf(c.form.priority)
    val w518 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priority: value_517 }) }
    w518
  }

  def e_change_priority_1(w0: World, c: Ctx, iid: str): World = {
    val value_519 = true
    val w520 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priorityManual: value_519 }) }
    w520
  }

  def e_change_priority_2(w0: World, c: Ctx, iid: str): World = {
    val t_521 = w0.inc.get(iid).timers.get("reaction")
    val raw_522 = ((timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel") - timerSec(c.before, "reaction", "byEscalationLevel")) * 1000)
    val delta_523 = (if (((raw_522 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_524) => acc or (m_524.state == "linked")))) 0 else raw_522)
    val w525 = if ((((t_521.due != 0) and (t_521.due > c.now)) and (t_521.fired != t_521.due))) {
      val w526 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if (((t_521.due + delta_523) > c.now)) (t_521.due + delta_523) else c.now) }) }) }
      w526
    } else {
      val w527 = if ((((timerDef("reaction").pausable and (t_521.due == 0)) and t_521.paused) and (t_521.left > 0))) {
      val w528 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (((t_521.left + delta_523) > 0)) (t_521.left + delta_523) else 1) }) }) }
      w528
    } else w0
      w527
    }
    w525
  }

  def e_change_priority_3(w0: World, c: Ctx, iid: str): World = {
    val t_529 = w0.inc.get(iid).timers.get("resolution")
    val raw_530 = ((timerSec(w0.inc.get(iid), "resolution", "") - timerSec(c.before, "resolution", "")) * 1000)
    val delta_531 = (if (((raw_530 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_532) => acc or (m_532.state == "linked")))) 0 else raw_530)
    val w533 = if ((((t_529.due != 0) and (t_529.due > c.now)) and (t_529.fired != t_529.due))) {
      val w534 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((t_529.due + delta_531) > c.now)) (t_529.due + delta_531) else c.now) }) }) }
      w534
    } else {
      val w535 = if ((((timerDef("resolution").pausable and (t_529.due == 0)) and t_529.paused) and (t_529.left > 0))) {
      val w536 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((t_529.left + delta_531) > 0)) (t_529.left + delta_531) else 1) }) }) }
      w536
    } else w0
      w535
    }
    w533
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
    { val t_537 = world.inc.get(iid).timers.get("reaction")  (((t_537.due != 0) and (t_537.due <= c.now)) and (t_537.fired != t_537.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_538 = personOf(levelUpTarget(c.before))
    val w539 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_538 }) }
    w539
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_540 = groupOf(levelUpTarget(c.before))
    val w541 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_540 }) }
    w541
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_542 = levelUpNumber(c.before)
    val w543 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_542 }) }
    w543
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w544 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w544
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w545 = if (not(timerDef("resolution").pausable)) {
      val w546 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w547 = { ...w546, inc: w546.inc.set(iid, { ...w546.inc.get(iid), timers: w546.inc.get(iid).timers.set("resolution", { ...w546.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w547
    } else {
      val w548 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w549 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w550 = { ...w549, inc: w549.inc.set(iid, { ...w549.inc.get(iid), timers: w549.inc.get(iid).timers.set("resolution", { ...w549.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w551 = { ...w550, inc: w550.inc.set(iid, { ...w550.inc.get(iid), timers: w550.inc.get(iid).timers.set("resolution", { ...w550.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w551
    } else w0
      w548
    }
    w545
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w552 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w553 = if (timerDef("reaction").startsOnce) {
      val w554 = ec_resumeTimer(w0, c, iid, "reaction")
      w554
    } else {
      val w555 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w556 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w557 = { ...w556, inc: w556.inc.set(iid, { ...w556.inc.get(iid), timers: w556.inc.get(iid).timers.set("reaction", { ...w556.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w558 = { ...w557, inc: w557.inc.set(iid, { ...w557.inc.get(iid), timers: w557.inc.get(iid).timers.set("reaction", { ...w557.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w558
    } else {
      val sec_559 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w560 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_559 < 0)) 0 else (c.now + (sec_559 * 1000))) }) }) }
      val w561 = { ...w560, inc: w560.inc.set(iid, { ...w560.inc.get(iid), timers: w560.inc.get(iid).timers.set("reaction", { ...w560.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w562 = { ...w561, inc: w561.inc.set(iid, { ...w561.inc.get(iid), timers: w561.inc.get(iid).timers.set("reaction", { ...w561.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w563 = { ...w562, inc: w562.inc.set(iid, { ...w562.inc.get(iid), timers: w562.inc.get(iid).timers.set("reaction", { ...w562.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w563
    }
      w555
    }
      w553
    }
    w552
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_564 = addressee(w0.inc.get(iid))
    val w565 = if (((whom_564 != "") and (whom_564 != c.actor))) w0 else w0
    w565
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
    { val t_566 = world.inc.get(iid).timers.get("reaction")  (((t_566.due != 0) and (t_566.due <= c.now)) and (t_566.fired != t_566.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_567 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w568 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_567) }) }
    val w569 = { ...w568, inc: w568.inc.set(iid, { ...w568.inc.get(iid), slaBreached: true }) }
    val w570 = groupMembersAt(incs(w0), w569.inc.get(iid), c.deadline).foldl([], (acc, x573) => acc.append(x573.id)).foldl(w569, (wf571, eId572) => {
      val w574 = { ...wf571, inc: wf571.inc.set(eId572, { ...wf571.inc.get(eId572), breaches: wf571.inc.get(eId572).breaches.append(breach_567) }) }
      val w575 = { ...w574, inc: w574.inc.set(eId572, { ...w574.inc.get(eId572), slaBreached: true }) }
      w575
    })
    w570
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w576 = if (timerDef("reaction").startsOnce) {
      val w577 = ec_pauseTimer(w0, c, iid, "reaction")
      w577
    } else {
      val w578 = if (false) {
      val w579 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w580 = { ...w579, inc: w579.inc.set(iid, { ...w579.inc.get(iid), timers: w579.inc.get(iid).timers.set("reaction", { ...w579.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w581 = { ...w580, inc: w580.inc.set(iid, { ...w580.inc.get(iid), timers: w580.inc.get(iid).timers.set("reaction", { ...w580.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w582 = { ...w581, inc: w581.inc.set(iid, { ...w581.inc.get(iid), timers: w581.inc.get(iid).timers.set("reaction", { ...w581.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w582
    } else {
      val w583 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_584 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w585 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_584) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w586 = { ...w585, inc: w585.inc.set(iid, { ...w585.inc.get(iid), timers: w585.inc.get(iid).timers.set("reaction", { ...w585.inc.get(iid).timers.get("reaction"), paused: keep_584 }) }) }
      val w587 = { ...w586, inc: w586.inc.set(iid, { ...w586.inc.get(iid), timers: w586.inc.get(iid).timers.set("reaction", { ...w586.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w588 = { ...w587, inc: w587.inc.set(iid, { ...w587.inc.get(iid), timers: w587.inc.get(iid).timers.set("reaction", { ...w587.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w588
    }
      w583
    }
      w578
    }
    w576
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_589 = settings.alerts.target
    val w590 = if (((whom_589 != "") and (whom_589 != c.actor))) w0 else w0
    w590
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
    { val t_591 = world.inc.get(iid).timers.get("reaction")  (((t_591.due != 0) and (t_591.due <= c.now)) and (t_591.fired != t_591.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_592 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w593 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_592) }) }
    val w594 = { ...w593, inc: w593.inc.set(iid, { ...w593.inc.get(iid), slaBreached: true }) }
    val w595 = groupMembersAt(incs(w0), w594.inc.get(iid), c.deadline).foldl([], (acc, x598) => acc.append(x598.id)).foldl(w594, (wf596, eId597) => {
      val w599 = { ...wf596, inc: wf596.inc.set(eId597, { ...wf596.inc.get(eId597), breaches: wf596.inc.get(eId597).breaches.append(breach_592) }) }
      val w600 = { ...w599, inc: w599.inc.set(eId597, { ...w599.inc.get(eId597), slaBreached: true }) }
      w600
    })
    w595
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w601 = if (timerDef("reaction").startsOnce) {
      val w602 = ec_pauseTimer(w0, c, iid, "reaction")
      w602
    } else {
      val w603 = if (false) {
      val w604 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w605 = { ...w604, inc: w604.inc.set(iid, { ...w604.inc.get(iid), timers: w604.inc.get(iid).timers.set("reaction", { ...w604.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w606 = { ...w605, inc: w605.inc.set(iid, { ...w605.inc.get(iid), timers: w605.inc.get(iid).timers.set("reaction", { ...w605.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w607 = { ...w606, inc: w606.inc.set(iid, { ...w606.inc.get(iid), timers: w606.inc.get(iid).timers.set("reaction", { ...w606.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w607
    } else {
      val w608 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_609 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w610 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_609) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w611 = { ...w610, inc: w610.inc.set(iid, { ...w610.inc.get(iid), timers: w610.inc.get(iid).timers.set("reaction", { ...w610.inc.get(iid).timers.get("reaction"), paused: keep_609 }) }) }
      val w612 = { ...w611, inc: w611.inc.set(iid, { ...w611.inc.get(iid), timers: w611.inc.get(iid).timers.set("reaction", { ...w611.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w613 = { ...w612, inc: w612.inc.set(iid, { ...w612.inc.get(iid), timers: w612.inc.get(iid).timers.set("reaction", { ...w612.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w613
    }
      w608
    }
      w603
    }
    w601
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_614 = settings.alerts.target
    val w615 = if (((whom_614 != "") and (whom_614 != c.actor))) w0 else w0
    w615
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
    { val t_616 = world.inc.get(iid).timers.get("resolution")  (((t_616.due != 0) and (t_616.due <= c.now)) and (t_616.fired != t_616.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_617 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w618 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_617) }) }
    val w619 = { ...w618, inc: w618.inc.set(iid, { ...w618.inc.get(iid), slaBreached: true }) }
    val w620 = groupMembersAt(incs(w0), w619.inc.get(iid), c.deadline).foldl([], (acc, x623) => acc.append(x623.id)).foldl(w619, (wf621, eId622) => {
      val w624 = { ...wf621, inc: wf621.inc.set(eId622, { ...wf621.inc.get(eId622), breaches: wf621.inc.get(eId622).breaches.append(breach_617) }) }
      val w625 = { ...w624, inc: w624.inc.set(eId622, { ...w624.inc.get(eId622), slaBreached: true }) }
      w625
    })
    w620
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_626 = settings.alerts.target
    val w627 = if (((whom_626 != "") and (whom_626 != c.actor))) w0 else w0
    w627
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
    { val t_628 = world.inc.get(iid).timers.get("resolution")  (((t_628.due != 0) and (t_628.due <= c.now)) and (t_628.fired != t_628.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_629 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w630 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_629) }) }
    val w631 = { ...w630, inc: w630.inc.set(iid, { ...w630.inc.get(iid), slaBreached: true }) }
    val w632 = groupMembersAt(incs(w0), w631.inc.get(iid), c.deadline).foldl([], (acc, x635) => acc.append(x635.id)).foldl(w631, (wf633, eId634) => {
      val w636 = { ...wf633, inc: wf633.inc.set(eId634, { ...wf633.inc.get(eId634), breaches: wf633.inc.get(eId634).breaches.append(breach_629) }) }
      val w637 = { ...w636, inc: w636.inc.set(eId634, { ...w636.inc.get(eId634), slaBreached: true }) }
      w637
    })
    w632
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_638 = personOf(levelUpTarget(c.before))
    val w639 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_638 }) }
    w639
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_640 = groupOf(levelUpTarget(c.before))
    val w641 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_640 }) }
    w641
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_642 = levelUpNumber(c.before)
    val w643 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_642 }) }
    w643
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w644 = if (not(timerDef("resolution").pausable)) {
      val w645 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w646 = { ...w645, inc: w645.inc.set(iid, { ...w645.inc.get(iid), timers: w645.inc.get(iid).timers.set("resolution", { ...w645.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w646
    } else {
      val w647 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w648 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w649 = { ...w648, inc: w648.inc.set(iid, { ...w648.inc.get(iid), timers: w648.inc.get(iid).timers.set("resolution", { ...w648.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w650 = { ...w649, inc: w649.inc.set(iid, { ...w649.inc.get(iid), timers: w649.inc.get(iid).timers.set("resolution", { ...w649.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w650
    } else w0
      w647
    }
    w644
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w651 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w652 = if (timerDef("reaction").startsOnce) {
      val w653 = ec_resumeTimer(w0, c, iid, "reaction")
      w653
    } else {
      val w654 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w655 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w656 = { ...w655, inc: w655.inc.set(iid, { ...w655.inc.get(iid), timers: w655.inc.get(iid).timers.set("reaction", { ...w655.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w657 = { ...w656, inc: w656.inc.set(iid, { ...w656.inc.get(iid), timers: w656.inc.get(iid).timers.set("reaction", { ...w656.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w657
    } else {
      val sec_658 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w659 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_658 < 0)) 0 else (c.now + (sec_658 * 1000))) }) }) }
      val w660 = { ...w659, inc: w659.inc.set(iid, { ...w659.inc.get(iid), timers: w659.inc.get(iid).timers.set("reaction", { ...w659.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w661 = { ...w660, inc: w660.inc.set(iid, { ...w660.inc.get(iid), timers: w660.inc.get(iid).timers.set("reaction", { ...w660.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w662 = { ...w661, inc: w661.inc.set(iid, { ...w661.inc.get(iid), timers: w661.inc.get(iid).timers.set("reaction", { ...w661.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w662
    }
      w654
    }
      w652
    }
    w651
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_663 = c.before.owner
    val w664 = if (((whom_663 != "") and (whom_663 != c.actor))) w0 else w0
    w664
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_665 = addressee(w0.inc.get(iid))
    val w666 = if (((whom_665 != "") and (whom_665 != c.actor))) w0 else w0
    w666
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
    { val t_667 = world.inc.get(iid).timers.get("resolution")  (((t_667.due != 0) and (t_667.due <= c.now)) and (t_667.fired != t_667.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_668 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w669 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_668) }) }
    val w670 = { ...w669, inc: w669.inc.set(iid, { ...w669.inc.get(iid), slaBreached: true }) }
    val w671 = groupMembersAt(incs(w0), w670.inc.get(iid), c.deadline).foldl([], (acc, x674) => acc.append(x674.id)).foldl(w670, (wf672, eId673) => {
      val w675 = { ...wf672, inc: wf672.inc.set(eId673, { ...wf672.inc.get(eId673), breaches: wf672.inc.get(eId673).breaches.append(breach_668) }) }
      val w676 = { ...w675, inc: w675.inc.set(eId673, { ...w675.inc.get(eId673), slaBreached: true }) }
      w676
    })
    w671
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_677 = settings.alerts.target
    val w678 = if (((whom_677 != "") and (whom_677 != c.actor))) w0 else w0
    w678
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
    { val t_679 = world.inc.get(iid).timers.get("hold")  (((t_679.due != 0) and (t_679.due <= c.now)) and (t_679.fired != t_679.due)) },
    not(["break", "no_link"].foldl(false, (acc, y680) => acc or y680 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_681 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w682 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_681) }) }
    val w683 = { ...w682, inc: w682.inc.set(iid, { ...w682.inc.get(iid), slaBreached: true }) }
    val w684 = groupMembersAt(incs(w0), w683.inc.get(iid), c.deadline).foldl([], (acc, x687) => acc.append(x687.id)).foldl(w683, (wf685, eId686) => {
      val w688 = { ...wf685, inc: wf685.inc.set(eId686, { ...wf685.inc.get(eId686), breaches: wf685.inc.get(eId686).breaches.append(breach_681) }) }
      val w689 = { ...w688, inc: w688.inc.set(eId686, { ...w688.inc.get(eId686), slaBreached: true }) }
      w689
    })
    w684
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_690 = settings.alerts.target
    val w691 = if (((whom_690 != "") and (whom_690 != c.actor))) w0 else w0
    w691
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
    { val t_692 = world.inc.get(iid).timers.get("hold")  (((t_692.due != 0) and (t_692.due <= c.now)) and (t_692.fired != t_692.due)) },
    ["break"].foldl(false, (acc, y693) => acc or y693 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_694 = ""
    val w695 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_694 }) }
    w695
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w696 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w696
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w697 = if (timerDef("hold").startsOnce) {
      val w698 = ec_pauseTimer(w0, c, iid, "hold")
      w698
    } else {
      val w699 = if (false) {
      val w700 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w701 = { ...w700, inc: w700.inc.set(iid, { ...w700.inc.get(iid), timers: w700.inc.get(iid).timers.set("hold", { ...w700.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w702 = { ...w701, inc: w701.inc.set(iid, { ...w701.inc.get(iid), timers: w701.inc.get(iid).timers.set("hold", { ...w701.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w703 = { ...w702, inc: w702.inc.set(iid, { ...w702.inc.get(iid), timers: w702.inc.get(iid).timers.set("hold", { ...w702.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w703
    } else {
      val w704 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_705 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w706 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_705) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w707 = { ...w706, inc: w706.inc.set(iid, { ...w706.inc.get(iid), timers: w706.inc.get(iid).timers.set("hold", { ...w706.inc.get(iid).timers.get("hold"), paused: keep_705 }) }) }
      val w708 = { ...w707, inc: w707.inc.set(iid, { ...w707.inc.get(iid), timers: w707.inc.get(iid).timers.set("hold", { ...w707.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w709 = { ...w708, inc: w708.inc.set(iid, { ...w708.inc.get(iid), timers: w708.inc.get(iid).timers.set("hold", { ...w708.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w709
    }
      w704
    }
      w699
    }
    w697
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w710 = if (not(timerDef("resolution").pausable)) {
      val w711 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w712 = { ...w711, inc: w711.inc.set(iid, { ...w711.inc.get(iid), timers: w711.inc.get(iid).timers.set("resolution", { ...w711.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w712
    } else {
      val w713 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w714 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w715 = { ...w714, inc: w714.inc.set(iid, { ...w714.inc.get(iid), timers: w714.inc.get(iid).timers.set("resolution", { ...w714.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w716 = { ...w715, inc: w715.inc.set(iid, { ...w715.inc.get(iid), timers: w715.inc.get(iid).timers.set("resolution", { ...w715.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w716
    } else w0
      w713
    }
    w710
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w717 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w718 = if (timerDef("reaction").startsOnce) {
      val w719 = ec_resumeTimer(w0, c, iid, "reaction")
      w719
    } else {
      val w720 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w721 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w722 = { ...w721, inc: w721.inc.set(iid, { ...w721.inc.get(iid), timers: w721.inc.get(iid).timers.set("reaction", { ...w721.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w723 = { ...w722, inc: w722.inc.set(iid, { ...w722.inc.get(iid), timers: w722.inc.get(iid).timers.set("reaction", { ...w722.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w723
    } else {
      val sec_724 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w725 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_724 < 0)) 0 else (c.now + (sec_724 * 1000))) }) }) }
      val w726 = { ...w725, inc: w725.inc.set(iid, { ...w725.inc.get(iid), timers: w725.inc.get(iid).timers.set("reaction", { ...w725.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w727 = { ...w726, inc: w726.inc.set(iid, { ...w726.inc.get(iid), timers: w726.inc.get(iid).timers.set("reaction", { ...w726.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w728 = { ...w727, inc: w727.inc.set(iid, { ...w727.inc.get(iid), timers: w727.inc.get(iid).timers.set("reaction", { ...w727.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w728
    }
      w720
    }
      w718
    }
    w717
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
    val reason_729 = "break"
    val w730 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_729 }) }
    w730
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w731 = if (not(timerDef("resolution").pausable)) {
      val w732 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w733 = { ...w732, inc: w732.inc.set(iid, { ...w732.inc.get(iid), timers: w732.inc.get(iid).timers.set("resolution", { ...w732.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w733
    } else {
      val w734 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w735 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w736 = { ...w735, inc: w735.inc.set(iid, { ...w735.inc.get(iid), timers: w735.inc.get(iid).timers.set("resolution", { ...w735.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w737 = { ...w736, inc: w736.inc.set(iid, { ...w736.inc.get(iid), timers: w736.inc.get(iid).timers.set("resolution", { ...w736.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w737
    } else w0
      w734
    }
    w731
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w738 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w739 = if (timerDef("hold").startsOnce) {
      val w740 = ec_resumeTimer(w0, c, iid, "hold")
      w740
    } else {
      val w741 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w742 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w743 = { ...w742, inc: w742.inc.set(iid, { ...w742.inc.get(iid), timers: w742.inc.get(iid).timers.set("hold", { ...w742.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w744 = { ...w743, inc: w743.inc.set(iid, { ...w743.inc.get(iid), timers: w743.inc.get(iid).timers.set("hold", { ...w743.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w744
    } else {
      val sec_745 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w746 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_745 < 0)) 0 else (c.now + (sec_745 * 1000))) }) }) }
      val w747 = { ...w746, inc: w746.inc.set(iid, { ...w746.inc.get(iid), timers: w746.inc.get(iid).timers.set("hold", { ...w746.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w748 = { ...w747, inc: w747.inc.set(iid, { ...w747.inc.get(iid), timers: w747.inc.get(iid).timers.set("hold", { ...w747.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w749 = { ...w748, inc: w748.inc.set(iid, { ...w748.inc.get(iid), timers: w748.inc.get(iid).timers.set("hold", { ...w748.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w749
    }
      w741
    }
      w739
    }
    w738
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
    val reason_750 = "no_link"
    val w751 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_750 }) }
    w751
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w752 = if (not(timerDef("resolution").pausable)) {
      val w753 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w754 = { ...w753, inc: w753.inc.set(iid, { ...w753.inc.get(iid), timers: w753.inc.get(iid).timers.set("resolution", { ...w753.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w754
    } else {
      val w755 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w756 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w757 = { ...w756, inc: w756.inc.set(iid, { ...w756.inc.get(iid), timers: w756.inc.get(iid).timers.set("resolution", { ...w756.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w758 = { ...w757, inc: w757.inc.set(iid, { ...w757.inc.get(iid), timers: w757.inc.get(iid).timers.set("resolution", { ...w757.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w758
    } else w0
      w755
    }
    w752
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w759 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w760 = if (timerDef("hold").startsOnce) {
      val w761 = ec_resumeTimer(w0, c, iid, "hold")
      w761
    } else {
      val w762 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w763 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w764 = { ...w763, inc: w763.inc.set(iid, { ...w763.inc.get(iid), timers: w763.inc.get(iid).timers.set("hold", { ...w763.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w765 = { ...w764, inc: w764.inc.set(iid, { ...w764.inc.get(iid), timers: w764.inc.get(iid).timers.set("hold", { ...w764.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w765
    } else {
      val sec_766 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w767 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_766 < 0)) 0 else (c.now + (sec_766 * 1000))) }) }) }
      val w768 = { ...w767, inc: w767.inc.set(iid, { ...w767.inc.get(iid), timers: w767.inc.get(iid).timers.set("hold", { ...w767.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w769 = { ...w768, inc: w768.inc.set(iid, { ...w768.inc.get(iid), timers: w768.inc.get(iid).timers.set("hold", { ...w768.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w770 = { ...w769, inc: w769.inc.set(iid, { ...w769.inc.get(iid), timers: w769.inc.get(iid).timers.set("hold", { ...w769.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w770
    }
      w762
    }
      w760
    }
    w759
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_771 = settings.alerts.target
    val w772 = if (((whom_771 != "") and (whom_771 != c.actor))) w0 else w0
    w772
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
    ["break", "no_link"].foldl(false, (acc, y773) => acc or y773 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_774 = ""
    val w775 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_774 }) }
    w775
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w776 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w776
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w777 = if (timerDef("hold").startsOnce) {
      val w778 = ec_pauseTimer(w0, c, iid, "hold")
      w778
    } else {
      val w779 = if (false) {
      val w780 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w781 = { ...w780, inc: w780.inc.set(iid, { ...w780.inc.get(iid), timers: w780.inc.get(iid).timers.set("hold", { ...w780.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w782 = { ...w781, inc: w781.inc.set(iid, { ...w781.inc.get(iid), timers: w781.inc.get(iid).timers.set("hold", { ...w781.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w783 = { ...w782, inc: w782.inc.set(iid, { ...w782.inc.get(iid), timers: w782.inc.get(iid).timers.set("hold", { ...w782.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w783
    } else {
      val w784 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_785 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w786 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_785) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w787 = { ...w786, inc: w786.inc.set(iid, { ...w786.inc.get(iid), timers: w786.inc.get(iid).timers.set("hold", { ...w786.inc.get(iid).timers.get("hold"), paused: keep_785 }) }) }
      val w788 = { ...w787, inc: w787.inc.set(iid, { ...w787.inc.get(iid), timers: w787.inc.get(iid).timers.set("hold", { ...w787.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w789 = { ...w788, inc: w788.inc.set(iid, { ...w788.inc.get(iid), timers: w788.inc.get(iid).timers.set("hold", { ...w788.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w789
    }
      w784
    }
      w779
    }
    w777
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w790 = if (not(timerDef("resolution").pausable)) {
      val w791 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w792 = { ...w791, inc: w791.inc.set(iid, { ...w791.inc.get(iid), timers: w791.inc.get(iid).timers.set("resolution", { ...w791.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w792
    } else {
      val w793 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w794 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w795 = { ...w794, inc: w794.inc.set(iid, { ...w794.inc.get(iid), timers: w794.inc.get(iid).timers.set("resolution", { ...w794.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w796 = { ...w795, inc: w795.inc.set(iid, { ...w795.inc.get(iid), timers: w795.inc.get(iid).timers.set("resolution", { ...w795.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w796
    } else w0
      w793
    }
    w790
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w797 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w798 = if (timerDef("reaction").startsOnce) {
      val w799 = ec_resumeTimer(w0, c, iid, "reaction")
      w799
    } else {
      val w800 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w801 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w802 = { ...w801, inc: w801.inc.set(iid, { ...w801.inc.get(iid), timers: w801.inc.get(iid).timers.set("reaction", { ...w801.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w803 = { ...w802, inc: w802.inc.set(iid, { ...w802.inc.get(iid), timers: w802.inc.get(iid).timers.set("reaction", { ...w802.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w803
    } else {
      val sec_804 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w805 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_804 < 0)) 0 else (c.now + (sec_804 * 1000))) }) }) }
      val w806 = { ...w805, inc: w805.inc.set(iid, { ...w805.inc.get(iid), timers: w805.inc.get(iid).timers.set("reaction", { ...w805.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w807 = { ...w806, inc: w806.inc.set(iid, { ...w806.inc.get(iid), timers: w806.inc.get(iid).timers.set("reaction", { ...w806.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w808 = { ...w807, inc: w807.inc.set(iid, { ...w807.inc.get(iid), timers: w807.inc.get(iid).timers.set("reaction", { ...w807.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w808
    }
      w800
    }
      w798
    }
    w797
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
    { val t_809 = world.inc.get(iid).timers.get("hold")  (((t_809.due != 0) and (t_809.due <= c.now)) and (t_809.fired != t_809.due)) },
    ["no_link"].foldl(false, (acc, y810) => acc or y810 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_811 = ""
    val w812 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_811 }) }
    w812
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w813 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w813
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w814 = if (timerDef("hold").startsOnce) {
      val w815 = ec_pauseTimer(w0, c, iid, "hold")
      w815
    } else {
      val w816 = if (false) {
      val w817 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w818 = { ...w817, inc: w817.inc.set(iid, { ...w817.inc.get(iid), timers: w817.inc.get(iid).timers.set("hold", { ...w817.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w819 = { ...w818, inc: w818.inc.set(iid, { ...w818.inc.get(iid), timers: w818.inc.get(iid).timers.set("hold", { ...w818.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w820 = { ...w819, inc: w819.inc.set(iid, { ...w819.inc.get(iid), timers: w819.inc.get(iid).timers.set("hold", { ...w819.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w820
    } else {
      val w821 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_822 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w823 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_822) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w824 = { ...w823, inc: w823.inc.set(iid, { ...w823.inc.get(iid), timers: w823.inc.get(iid).timers.set("hold", { ...w823.inc.get(iid).timers.get("hold"), paused: keep_822 }) }) }
      val w825 = { ...w824, inc: w824.inc.set(iid, { ...w824.inc.get(iid), timers: w824.inc.get(iid).timers.set("hold", { ...w824.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w826 = { ...w825, inc: w825.inc.set(iid, { ...w825.inc.get(iid), timers: w825.inc.get(iid).timers.set("hold", { ...w825.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w826
    }
      w821
    }
      w816
    }
    w814
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w827 = if (not(timerDef("resolution").pausable)) {
      val w828 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w829 = { ...w828, inc: w828.inc.set(iid, { ...w828.inc.get(iid), timers: w828.inc.get(iid).timers.set("resolution", { ...w828.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w829
    } else {
      val w830 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w831 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w832 = { ...w831, inc: w831.inc.set(iid, { ...w831.inc.get(iid), timers: w831.inc.get(iid).timers.set("resolution", { ...w831.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w833 = { ...w832, inc: w832.inc.set(iid, { ...w832.inc.get(iid), timers: w832.inc.get(iid).timers.set("resolution", { ...w832.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w833
    } else w0
      w830
    }
    w827
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w834 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w835 = if (timerDef("reaction").startsOnce) {
      val w836 = ec_resumeTimer(w0, c, iid, "reaction")
      w836
    } else {
      val w837 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w838 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w839 = { ...w838, inc: w838.inc.set(iid, { ...w838.inc.get(iid), timers: w838.inc.get(iid).timers.set("reaction", { ...w838.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w840 = { ...w839, inc: w839.inc.set(iid, { ...w839.inc.get(iid), timers: w839.inc.get(iid).timers.set("reaction", { ...w839.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w840
    } else {
      val sec_841 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w842 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_841 < 0)) 0 else (c.now + (sec_841 * 1000))) }) }) }
      val w843 = { ...w842, inc: w842.inc.set(iid, { ...w842.inc.get(iid), timers: w842.inc.get(iid).timers.set("reaction", { ...w842.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w844 = { ...w843, inc: w843.inc.set(iid, { ...w843.inc.get(iid), timers: w843.inc.get(iid).timers.set("reaction", { ...w843.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w845 = { ...w844, inc: w844.inc.set(iid, { ...w844.inc.get(iid), timers: w844.inc.get(iid).timers.set("reaction", { ...w844.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w845
    }
      w837
    }
      w835
    }
    w834
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
    val group_846 = dutyGroupOf(w0.inc.get(iid).owner)
    val w847 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_846 }) }
    w847
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_848 = ""
    val w849 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_848 }) }
    w849
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_850 = addressee(w0.inc.get(iid))
    val w851 = if (((whom_850 != "") and (whom_850 != c.actor))) w0 else w0
    w851
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
    val who_852 = ""
    val w853 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_852 }) }
    w853
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
    val who_854 = ""
    val w855 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_854 }) }
    w855
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w856 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w856
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w857 = if (timerDef("hold").startsOnce) {
      val w858 = ec_pauseTimer(w0, c, iid, "hold")
      w858
    } else {
      val w859 = if (false) {
      val w860 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w861 = { ...w860, inc: w860.inc.set(iid, { ...w860.inc.get(iid), timers: w860.inc.get(iid).timers.set("hold", { ...w860.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w862 = { ...w861, inc: w861.inc.set(iid, { ...w861.inc.get(iid), timers: w861.inc.get(iid).timers.set("hold", { ...w861.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w863 = { ...w862, inc: w862.inc.set(iid, { ...w862.inc.get(iid), timers: w862.inc.get(iid).timers.set("hold", { ...w862.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w863
    } else {
      val w864 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_865 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w866 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_865) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w867 = { ...w866, inc: w866.inc.set(iid, { ...w866.inc.get(iid), timers: w866.inc.get(iid).timers.set("hold", { ...w866.inc.get(iid).timers.get("hold"), paused: keep_865 }) }) }
      val w868 = { ...w867, inc: w867.inc.set(iid, { ...w867.inc.get(iid), timers: w867.inc.get(iid).timers.set("hold", { ...w867.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w869 = { ...w868, inc: w868.inc.set(iid, { ...w868.inc.get(iid), timers: w868.inc.get(iid).timers.set("hold", { ...w868.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w869
    }
      w864
    }
      w859
    }
    w857
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w870 = if (not(timerDef("resolution").pausable)) {
      val w871 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w872 = { ...w871, inc: w871.inc.set(iid, { ...w871.inc.get(iid), timers: w871.inc.get(iid).timers.set("resolution", { ...w871.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w872
    } else {
      val w873 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w874 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w875 = { ...w874, inc: w874.inc.set(iid, { ...w874.inc.get(iid), timers: w874.inc.get(iid).timers.set("resolution", { ...w874.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w876 = { ...w875, inc: w875.inc.set(iid, { ...w875.inc.get(iid), timers: w875.inc.get(iid).timers.set("resolution", { ...w875.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w876
    } else w0
      w873
    }
    w870
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w877 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w878 = if (timerDef("reaction").startsOnce) {
      val w879 = ec_resumeTimer(w0, c, iid, "reaction")
      w879
    } else {
      val w880 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w881 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w882 = { ...w881, inc: w881.inc.set(iid, { ...w881.inc.get(iid), timers: w881.inc.get(iid).timers.set("reaction", { ...w881.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w883 = { ...w882, inc: w882.inc.set(iid, { ...w882.inc.get(iid), timers: w882.inc.get(iid).timers.set("reaction", { ...w882.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w883
    } else {
      val sec_884 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w885 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_884 < 0)) 0 else (c.now + (sec_884 * 1000))) }) }) }
      val w886 = { ...w885, inc: w885.inc.set(iid, { ...w885.inc.get(iid), timers: w885.inc.get(iid).timers.set("reaction", { ...w885.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w887 = { ...w886, inc: w886.inc.set(iid, { ...w886.inc.get(iid), timers: w886.inc.get(iid).timers.set("reaction", { ...w886.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w888 = { ...w887, inc: w887.inc.set(iid, { ...w887.inc.get(iid), timers: w887.inc.get(iid).timers.set("reaction", { ...w887.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w888
    }
      w880
    }
      w878
    }
    w877
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
    val who_889 = ""
    val w890 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_889 }) }
    w890
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_891 = ""
    val w892 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_891 }) }
    w892
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w893 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w893
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w894 = if (timerDef("hold").startsOnce) {
      val w895 = ec_pauseTimer(w0, c, iid, "hold")
      w895
    } else {
      val w896 = if (false) {
      val w897 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w898 = { ...w897, inc: w897.inc.set(iid, { ...w897.inc.get(iid), timers: w897.inc.get(iid).timers.set("hold", { ...w897.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w899 = { ...w898, inc: w898.inc.set(iid, { ...w898.inc.get(iid), timers: w898.inc.get(iid).timers.set("hold", { ...w898.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w900 = { ...w899, inc: w899.inc.set(iid, { ...w899.inc.get(iid), timers: w899.inc.get(iid).timers.set("hold", { ...w899.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w900
    } else {
      val w901 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_902 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w903 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_902) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w904 = { ...w903, inc: w903.inc.set(iid, { ...w903.inc.get(iid), timers: w903.inc.get(iid).timers.set("hold", { ...w903.inc.get(iid).timers.get("hold"), paused: keep_902 }) }) }
      val w905 = { ...w904, inc: w904.inc.set(iid, { ...w904.inc.get(iid), timers: w904.inc.get(iid).timers.set("hold", { ...w904.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w906 = { ...w905, inc: w905.inc.set(iid, { ...w905.inc.get(iid), timers: w905.inc.get(iid).timers.set("hold", { ...w905.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w906
    }
      w901
    }
      w896
    }
    w894
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w907 = if (not(timerDef("resolution").pausable)) {
      val w908 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w909 = { ...w908, inc: w908.inc.set(iid, { ...w908.inc.get(iid), timers: w908.inc.get(iid).timers.set("resolution", { ...w908.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w909
    } else {
      val w910 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w911 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w912 = { ...w911, inc: w911.inc.set(iid, { ...w911.inc.get(iid), timers: w911.inc.get(iid).timers.set("resolution", { ...w911.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w913 = { ...w912, inc: w912.inc.set(iid, { ...w912.inc.get(iid), timers: w912.inc.get(iid).timers.set("resolution", { ...w912.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w913
    } else w0
      w910
    }
    w907
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w914 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w915 = if (timerDef("reaction").startsOnce) {
      val w916 = ec_resumeTimer(w0, c, iid, "reaction")
      w916
    } else {
      val w917 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w918 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w919 = { ...w918, inc: w918.inc.set(iid, { ...w918.inc.get(iid), timers: w918.inc.get(iid).timers.set("reaction", { ...w918.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w920 = { ...w919, inc: w919.inc.set(iid, { ...w919.inc.get(iid), timers: w919.inc.get(iid).timers.set("reaction", { ...w919.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w920
    } else {
      val sec_921 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w922 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_921 < 0)) 0 else (c.now + (sec_921 * 1000))) }) }) }
      val w923 = { ...w922, inc: w922.inc.set(iid, { ...w922.inc.get(iid), timers: w922.inc.get(iid).timers.set("reaction", { ...w922.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w924 = { ...w923, inc: w923.inc.set(iid, { ...w923.inc.get(iid), timers: w923.inc.get(iid).timers.set("reaction", { ...w923.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w925 = { ...w924, inc: w924.inc.set(iid, { ...w924.inc.get(iid), timers: w924.inc.get(iid).timers.set("reaction", { ...w924.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w925
    }
      w917
    }
      w915
    }
    w914
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_926 = settings.alerts.target
    val w927 = if (((whom_926 != "") and (whom_926 != c.actor))) w0 else w0
    w927
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
    val who_928 = ""
    val w929 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_928 }) }
    w929
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_930 = ""
    val w931 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_930 }) }
    w931
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w932 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w933 = if (timerDef("reaction").startsOnce) {
      val w934 = ec_resumeTimer(w0, c, iid, "reaction")
      w934
    } else {
      val w935 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w936 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w937 = { ...w936, inc: w936.inc.set(iid, { ...w936.inc.get(iid), timers: w936.inc.get(iid).timers.set("reaction", { ...w936.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w938 = { ...w937, inc: w937.inc.set(iid, { ...w937.inc.get(iid), timers: w937.inc.get(iid).timers.set("reaction", { ...w937.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w938
    } else {
      val sec_939 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w940 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_939 < 0)) 0 else (c.now + (sec_939 * 1000))) }) }) }
      val w941 = { ...w940, inc: w940.inc.set(iid, { ...w940.inc.get(iid), timers: w940.inc.get(iid).timers.set("reaction", { ...w940.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w942 = { ...w941, inc: w941.inc.set(iid, { ...w941.inc.get(iid), timers: w941.inc.get(iid).timers.set("reaction", { ...w941.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w943 = { ...w942, inc: w942.inc.set(iid, { ...w942.inc.get(iid), timers: w942.inc.get(iid).timers.set("reaction", { ...w942.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w943
    }
      w935
    }
      w933
    }
    w932
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_944 = settings.alerts.target
    val w945 = if (((whom_944 != "") and (whom_944 != c.actor))) w0 else w0
    w945
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
    not(settings.session.states.foldl(false, (acc, s_946) => acc or ((s_946.id == agentState(c.me)) and s_946.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_947 = incidentById(incs(world), c.form.primaryId)  ((((ps_947.length() > 0) and (ps_947[0].id != world.inc.get(iid).id)) and (ps_947[0].linkedTo == "")) and ((ps_947[0].state == "new") or ((ps_947[0].state == "in_progress") and (ps_947[0].owner == c.me)))) },
    { val ps_948 = incidentById(incs(world), c.form.primaryId)  ((ps_948.length() > 0) and (ps_948[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w949 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w949
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_950 = incidentById(incs(w0), c.form.primaryId)
    val w951 = if ((ps_950.length() > 0)) {
      val w952 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_959 => not(isDone(e_959))).foldl([], (acc, x955) => acc.append(x955.id)).foldl(w0, (wf953, cId954) => {
      val w956 = { ...wf953, inc: wf953.inc.set(cId954, { ...wf953.inc.get(cId954), leftGroup: { primaryId: wf953.inc.get(cId954).linkedTo, linkedAt: wf953.inc.get(cId954).linkedAt, at: c.now } }) }
      val w957 = { ...w956, inc: w956.inc.set(cId954, { ...w956.inc.get(cId954), linkedTo: ps_950[0].id }) }
      val w958 = { ...w957, inc: w957.inc.set(cId954, { ...w957.inc.get(cId954), linkedAt: c.now }) }
      w958
    })
      w952
    } else w0
    w951
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_960 = c.form.primaryId
    val w961 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_960 }) }
    val w962 = { ...w961, inc: w961.inc.set(iid, { ...w961.inc.get(iid), linkedAt: c.now }) }
    w962
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_963 = ""
    val w964 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_963 }) }
    w964
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_965 = ""
    val w966 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_965 }) }
    w966
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w967 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w967
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w968 = if (timerDef("reaction").startsOnce) {
      val w969 = ec_pauseTimer(w0, c, iid, "reaction")
      w969
    } else {
      val w970 = if (false) {
      val w971 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w972 = { ...w971, inc: w971.inc.set(iid, { ...w971.inc.get(iid), timers: w971.inc.get(iid).timers.set("reaction", { ...w971.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w973 = { ...w972, inc: w972.inc.set(iid, { ...w972.inc.get(iid), timers: w972.inc.get(iid).timers.set("reaction", { ...w972.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w974 = { ...w973, inc: w973.inc.set(iid, { ...w973.inc.get(iid), timers: w973.inc.get(iid).timers.set("reaction", { ...w973.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w974
    } else {
      val w975 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_976 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w977 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_976) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w978 = { ...w977, inc: w977.inc.set(iid, { ...w977.inc.get(iid), timers: w977.inc.get(iid).timers.set("reaction", { ...w977.inc.get(iid).timers.get("reaction"), paused: keep_976 }) }) }
      val w979 = { ...w978, inc: w978.inc.set(iid, { ...w978.inc.get(iid), timers: w978.inc.get(iid).timers.set("reaction", { ...w978.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w980 = { ...w979, inc: w979.inc.set(iid, { ...w979.inc.get(iid), timers: w979.inc.get(iid).timers.set("reaction", { ...w979.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w980
    }
      w975
    }
      w970
    }
    w968
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w981 = if (not(timerDef("resolution").pausable)) {
      val w982 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w983 = { ...w982, inc: w982.inc.set(iid, { ...w982.inc.get(iid), timers: w982.inc.get(iid).timers.set("resolution", { ...w982.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w983
    } else {
      val w984 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w985 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w986 = { ...w985, inc: w985.inc.set(iid, { ...w985.inc.get(iid), timers: w985.inc.get(iid).timers.set("resolution", { ...w985.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w987 = { ...w986, inc: w986.inc.set(iid, { ...w986.inc.get(iid), timers: w986.inc.get(iid).timers.set("resolution", { ...w986.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w987
    } else w0
      w984
    }
    w981
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_988 = incidentById(incs(w0), c.form.primaryId)
    val w989 = if (((((ps_988.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_988[0], "resolution", c.now)))) {
      val t_990 = ps_988[0].timers.get("resolution")
      val left_991 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_992 = (if ((t_990.due != 0)) (t_990.due - c.now) else (if (t_990.paused) t_990.left else (timerSec(ps_988[0], "resolution", "") * 1000)))
      val w993 = if ((left_991 < was_992)) {
      val w994 = ps_988.foldl([], (acc, x997) => acc.append(x997.id)).foldl(w0, (wf995, pId996) => {
      val w998 = if ((t_990.due != 0)) {
      val w999 = { ...wf995, inc: wf995.inc.set(pId996, { ...wf995.inc.get(pId996), timers: wf995.inc.get(pId996).timers.set("resolution", { ...wf995.inc.get(pId996).timers.get("resolution"), due: (c.now + left_991) }) }) }
      w999
    } else {
      val w1000 = { ...wf995, inc: wf995.inc.set(pId996, { ...wf995.inc.get(pId996), timers: wf995.inc.get(pId996).timers.set("resolution", { ...wf995.inc.get(pId996).timers.get("resolution"), left: left_991 }) }) }
      val w1001 = { ...w1000, inc: w1000.inc.set(pId996, { ...w1000.inc.get(pId996), timers: w1000.inc.get(pId996).timers.set("resolution", { ...w1000.inc.get(pId996).timers.get("resolution"), paused: true }) }) }
      w1001
    }
      w998
    })
      w994
    } else w0
      w993
    } else w0
    w989
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w1002 = if (timerDef("hold").startsOnce) {
      val w1003 = ec_pauseTimer(w0, c, iid, "hold")
      w1003
    } else {
      val w1004 = if (false) {
      val w1005 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w1006 = { ...w1005, inc: w1005.inc.set(iid, { ...w1005.inc.get(iid), timers: w1005.inc.get(iid).timers.set("hold", { ...w1005.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w1007 = { ...w1006, inc: w1006.inc.set(iid, { ...w1006.inc.get(iid), timers: w1006.inc.get(iid).timers.set("hold", { ...w1006.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w1008 = { ...w1007, inc: w1007.inc.set(iid, { ...w1007.inc.get(iid), timers: w1007.inc.get(iid).timers.set("hold", { ...w1007.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w1008
    } else {
      val w1009 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_1010 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w1011 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_1010) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w1012 = { ...w1011, inc: w1011.inc.set(iid, { ...w1011.inc.get(iid), timers: w1011.inc.get(iid).timers.set("hold", { ...w1011.inc.get(iid).timers.get("hold"), paused: keep_1010 }) }) }
      val w1013 = { ...w1012, inc: w1012.inc.set(iid, { ...w1012.inc.get(iid), timers: w1012.inc.get(iid).timers.set("hold", { ...w1012.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w1014 = { ...w1013, inc: w1013.inc.set(iid, { ...w1013.inc.get(iid), timers: w1013.inc.get(iid).timers.set("hold", { ...w1013.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w1014
    }
      w1009
    }
      w1004
    }
    w1002
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
    not(settings.session.states.foldl(false, (acc, s_1015) => acc or ((s_1015.id == agentState(c.me)) and s_1015.readOnly))),
    { val ps_1016 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1016.length() > 0) and ((ownership(c.me, ps_1016[0]) == "owner") or unowned(ps_1016[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_1017 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1018 = if (((ps_1017.length() > 0) and (leftOf(ps_1017[0], "resolution", c.now) >= 0))) {
      val w1019 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1020 = { ...w1019, inc: w1019.inc.set(iid, { ...w1019.inc.get(iid), timers: w1019.inc.get(iid).timers.set("resolution", { ...w1019.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1017[0], "resolution", c.now) }) }) }
      val w1021 = { ...w1020, inc: w1020.inc.set(iid, { ...w1020.inc.get(iid), timers: w1020.inc.get(iid).timers.set("resolution", { ...w1020.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1022 = if ((leftOf(ps_1017[0], "resolution", c.now) == 0)) {
      val w1023 = { ...w1021, inc: w1021.inc.set(iid, { ...w1021.inc.get(iid), timers: w1021.inc.get(iid).timers.set("resolution", { ...w1021.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1017[0], "resolution", c.now)) ps_1017[0].timers.get("resolution").fired else ps_1017[0].timers.get("resolution").due) }) }) }
      w1023
    } else w1021
      w1022
    } else w0
    w1018
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w1024 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1025 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1026 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1027 = { ...w1026, inc: w1026.inc.set(iid, { ...w1026.inc.get(iid), linkedTo: "" }) }
      val w1028 = { ...w1027, inc: w1027.inc.set(iid, { ...w1027.inc.get(iid), linkedAt: 0 }) }
      val w1029 = if (((ps_1025.length() > 0) and ("" != ""))) w1028 else w1028
      val w1030 = if (("" != "")) {
      val w1031 = ps_1025.foldl([], (acc, x1034) => acc.append(x1034.id)).foldl(w1029, (wf1032, pId1033) => wf1032)
      w1031
    } else w1029
      w1030
    } else {
      val w1035 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1036 = { ...w1035, inc: w1035.inc.set(iid, { ...w1035.inc.get(iid), linkedAt: 0 }) }
      w1036
    }
    w1024
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w1037 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1038 = if (timerDef("reaction").startsOnce) {
      val w1039 = ec_resumeTimer(w0, c, iid, "reaction")
      w1039
    } else {
      val w1040 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1041 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1042 = { ...w1041, inc: w1041.inc.set(iid, { ...w1041.inc.get(iid), timers: w1041.inc.get(iid).timers.set("reaction", { ...w1041.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1043 = { ...w1042, inc: w1042.inc.set(iid, { ...w1042.inc.get(iid), timers: w1042.inc.get(iid).timers.set("reaction", { ...w1042.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1043
    } else {
      val sec_1044 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w1045 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1044 < 0)) 0 else (c.now + (sec_1044 * 1000))) }) }) }
      val w1046 = { ...w1045, inc: w1045.inc.set(iid, { ...w1045.inc.get(iid), timers: w1045.inc.get(iid).timers.set("reaction", { ...w1045.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1047 = { ...w1046, inc: w1046.inc.set(iid, { ...w1046.inc.get(iid), timers: w1046.inc.get(iid).timers.set("reaction", { ...w1046.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1048 = { ...w1047, inc: w1047.inc.set(iid, { ...w1047.inc.get(iid), timers: w1047.inc.get(iid).timers.set("reaction", { ...w1047.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1048
    }
      w1040
    }
      w1038
    }
    w1037
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
    { val ps_1049 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1049.length() > 0) and isDone(ps_1049[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1050 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1051 = if ((ps_1050.length() > 0)) {
      val w1052 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_1050[0].closeResultId }) }
      val w1053 = { ...w1052, inc: w1052.inc.set(iid, { ...w1052.inc.get(iid), closeCauseId: ps_1050[0].closeCauseId }) }
      val w1054 = { ...w1053, inc: w1053.inc.set(iid, { ...w1053.inc.get(iid), closeCauseLabel: ps_1050[0].closeCauseLabel }) }
      val w1055 = { ...w1054, inc: w1054.inc.set(iid, { ...w1054.inc.get(iid), result: ps_1050[0].result }) }
      val w1056 = { ...w1055, inc: w1055.inc.set(iid, { ...w1055.inc.get(iid), closedBy: ps_1050[0].closedBy }) }
      val w1057 = { ...w1056, inc: w1056.inc.set(iid, { ...w1056.inc.get(iid), owner: ps_1050[0].closedBy }) }
      w1057
    } else w0
    w1051
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w1058 = if (not(timerDef("resolution").pausable)) {
      val w1059 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1060 = { ...w1059, inc: w1059.inc.set(iid, { ...w1059.inc.get(iid), timers: w1059.inc.get(iid).timers.set("resolution", { ...w1059.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w1060
    } else {
      val w1061 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w1062 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w1063 = { ...w1062, inc: w1062.inc.set(iid, { ...w1062.inc.get(iid), timers: w1062.inc.get(iid).timers.set("resolution", { ...w1062.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1064 = { ...w1063, inc: w1063.inc.set(iid, { ...w1063.inc.get(iid), timers: w1063.inc.get(iid).timers.set("resolution", { ...w1063.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w1064
    } else w0
      w1061
    }
    w1058
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_1065 = c.now
    val w1066 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_1065 }) }
    w1066
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {
    val w1067 = if (["false_alarm"].foldl(false, (acc, y1068) => acc or y1068 == w0.inc.get(iid).closeResultId)) {
      val w1069 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1073 => not(isDone(x_1073))).foldl([], (acc, x1072) => acc.append(x1072.id)).foldl(w0, (wf1070, sId1071) => wf1070)
      w1069
    } else w0
    w1067
  }

  def e_close_linked_5(w0: World, c: Ctx, iid: str): World = {
    val w1074 = if (["false_alarm"].foldl(false, (acc, y1075) => acc or y1075 == w0.inc.get(iid).closeResultId)) {
      val w1076 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1083 => not(isDone(x_1083))).foldl([], (acc, x1079) => acc.append(x1079.id)).foldl(w0, (wf1077, sId1078) => {
      val lead_1080 = (if ((wf1077.inc.get(sId1078).linkedTo != "")) { val ps_1081 = incidentById(incs(w0), wf1077.inc.get(sId1078).linkedTo)  (if (((ps_1081.length() > 0) and not(isDone(ps_1081[0])))) addressee(ps_1081[0]) else "") } else addressee(wf1077.inc.get(sId1078)))
      val w1082 = if (((lead_1080 != "") and (lead_1080 != wf1077.inc.get(iid).closedBy))) wf1077 else wf1077
      w1082
    })
      w1076
    } else w0
    w1074
  }

  def e_close_linked_6(w0: World, c: Ctx, iid: str): World = {

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
    w7
  }

  // linked_lost_access: system → new

  def ok_linked_lost_access(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    { val ps_1084 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_1085 = (if (((ps_1084.length() > 0) and not(isDone(ps_1084[0])))) addressee(ps_1084[0]) else "")  ((who_1085 != "") and (hasAccess(who_1085, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1086 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1087 = if (((ps_1086.length() > 0) and (leftOf(ps_1086[0], "resolution", c.now) >= 0))) {
      val w1088 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1089 = { ...w1088, inc: w1088.inc.set(iid, { ...w1088.inc.get(iid), timers: w1088.inc.get(iid).timers.set("resolution", { ...w1088.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1086[0], "resolution", c.now) }) }) }
      val w1090 = { ...w1089, inc: w1089.inc.set(iid, { ...w1089.inc.get(iid), timers: w1089.inc.get(iid).timers.set("resolution", { ...w1089.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1091 = if ((leftOf(ps_1086[0], "resolution", c.now) == 0)) {
      val w1092 = { ...w1090, inc: w1090.inc.set(iid, { ...w1090.inc.get(iid), timers: w1090.inc.get(iid).timers.set("resolution", { ...w1090.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1086[0], "resolution", c.now)) ps_1086[0].timers.get("resolution").fired else ps_1086[0].timers.get("resolution").due) }) }) }
      w1092
    } else w1090
      w1091
    } else w0
    w1087
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w1093 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1094 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1095 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1096 = { ...w1095, inc: w1095.inc.set(iid, { ...w1095.inc.get(iid), linkedTo: "" }) }
      val w1097 = { ...w1096, inc: w1096.inc.set(iid, { ...w1096.inc.get(iid), linkedAt: 0 }) }
      val w1098 = if (((ps_1094.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w1097 else w1097
      val w1099 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w1100 = ps_1094.foldl([], (acc, x1103) => acc.append(x1103.id)).foldl(w1098, (wf1101, pId1102) => wf1101)
      w1100
    } else w1098
      w1099
    } else {
      val w1104 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1105 = { ...w1104, inc: w1104.inc.set(iid, { ...w1104.inc.get(iid), linkedAt: 0 }) }
      w1105
    }
    w1093
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w1106 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1107 = if (timerDef("reaction").startsOnce) {
      val w1108 = ec_resumeTimer(w0, c, iid, "reaction")
      w1108
    } else {
      val w1109 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1110 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1111 = { ...w1110, inc: w1110.inc.set(iid, { ...w1110.inc.get(iid), timers: w1110.inc.get(iid).timers.set("reaction", { ...w1110.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1112 = { ...w1111, inc: w1111.inc.set(iid, { ...w1111.inc.get(iid), timers: w1111.inc.get(iid).timers.set("reaction", { ...w1111.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1112
    } else {
      val sec_1113 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w1114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1113 < 0)) 0 else (c.now + (sec_1113 * 1000))) }) }) }
      val w1115 = { ...w1114, inc: w1114.inc.set(iid, { ...w1114.inc.get(iid), timers: w1114.inc.get(iid).timers.set("reaction", { ...w1114.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1116 = { ...w1115, inc: w1115.inc.set(iid, { ...w1115.inc.get(iid), timers: w1115.inc.get(iid).timers.set("reaction", { ...w1115.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1117 = { ...w1116, inc: w1116.inc.set(iid, { ...w1116.inc.get(iid), timers: w1116.inc.get(iid).timers.set("reaction", { ...w1116.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1117
    }
      w1109
    }
      w1107
    }
    w1106
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_1118 = settings.alerts.target
    val w1119 = if (((whom_1118 != "") and (whom_1118 != c.actor))) w0 else w0
    w1119
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
      settings.holdReasons.foldl(false, (acc, r_1120) => acc or ((r_1120.id == c.form.reasonId) and (r_1120.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_1121) => acc and (isDone(e_1121) or hasAccess(c.form.targetId, e_1121))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_1122) => acc or (i_1122.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_1123) => acc or ((i_1123.id == c.form.resultId) and stepsOk(i_1123, world.inc.get(iid)))),
    },
    c.form.causeId == "" or all {
      settings.closeResults.foldl(false, (acc, i_1124) => acc or ((((i_1124.id == c.form.resultId) and (i_1124.causeCatalog != "")) and settings.causeCatalogs.keys().contains(i_1124.causeCatalog)) and (settings.causeCatalogs.get(i_1124.causeCatalog).items.length() > 0))),
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
    ["in_progress"].foldl(false, (acc, y1125) => acc or y1125 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_1126) => acc or ((s_1126.id == agentState(c.me)) and s_1126.readOnly))),
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
