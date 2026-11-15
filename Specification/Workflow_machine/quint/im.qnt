// -*- mode: Bluespec; -*-
// Собрано скриптом tools/gen_quint.mjs из Specification/Workflow_machine/workflow_schema.v1.json (с настройками поста fixtures/demo.json) и частей quint/src/.
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


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, closeCauseLabel: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], priorityManual: bool, maintenanceWindowId: str, closeMaintenanceWindowId: str, timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str, eventGuid: str }

  type Timer = { due: int, paused: bool, left: int, fired: int, since: int }

  type Breach = { kind: str, at: int, owner: str }

  type LeftGroup = { primaryId: str, linkedAt: int, at: int }

  type Form = { targetId: str, primaryId: str, resultId: str, reasonId: str, causeId: str, comment: str, files: List[FormFile], priority: str, maintenanceWindowId: str }

  type FormFile = { id: str, fileName: str, mime: str, size: int }

  type Limits = { maxActive: int, maxOnHold: int, maxBulk: int, reopenWindowMin: int, reopenResolutionSec: int, commentMaxLength: int, commentMaxFiles: int, attachmentMaxBytes: int, attachmentTypes: List[str] }

  type SessionState = { id: str, readOnly: bool, readOnlyReasonKey: str }

  type Session = { states: List[SessionState], heartbeatSec: int, idleHoldSec: int, idleReleaseSec: int }

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
    session: { states: [{ id: "ready", readOnly: false, readOnlyReasonKey: "" }, { id: "busy", readOnly: false, readOnlyReasonKey: "" }, { id: "not_ready", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.not_ready" }, { id: "offline", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.offline" }], heartbeatSec: 30, idleHoldSec: 300, idleReleaseSec: 1200 },
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

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", closeCauseLabel: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], priorityManual: false, maintenanceWindowId: "", closeMaintenanceWindowId: "", timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "", eventGuid: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

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

  // §14.12, ТЗ-21. Интервалы окон работ, накрывающие событие; первое по порядку списка (по началу, при равенстве — по id окна) — окно, на которое ссылается итог. Пусто — окна нет

  def windowsFor(ws: List[MaintenanceWindow], e: Event): List[MaintenanceWindow] =
    ws.select(w_78 => windowCovers(w_78, e))

  // §14.5, ARCH-15. Правило-победитель сценария s для события: из подошедших правил с этим сценарием — те, кого не старше ни одно; сервер берёт первое по порядку списка — rules упорядочены по intake.ruleOrder. От него приоритет и ruleGuid инцидента

  def ruleFor(rules: List[Rule], e: Event, s: str): List[Rule] =
    { val ms_79 = rules.select(r_80 => (ruleMatches(r_80, e) and r_80.scenarios.foldl(false, (acc, y81) => acc or y81 == s)))  ms_79.select(r_82 => not(ms_79.foldl(false, (acc, o_83) => acc or ruleBeats(o_83, r_82, e)))) }

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_84 => (e_84.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_85 => ((e_85.id != p.id) and inGroupAt(e_85, p, at)))

  // §14.5, ARCH-15. Соседи — инциденты того же события, кроме самого x: другие службы той же тревоги. Не привязка §11: у каждого свой владелец, сроки и закрытие

  def siblingsOf(incidents: List[Incident], x: Incident): List[Incident] =
    incidents.select(s_86 => (((x.eventGuid != "") and (s_86.eventGuid == x.eventGuid)) and (s_86.id != x.id)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w87 = if (not(timerDef(timerId).pausable)) {
      val sec_88 = timerSec(w0.inc.get(iid), timerId, "")
      val w89 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_88 < 0)) 0 else (c.now + (sec_88 * 1000))) }) }) }
      val w90 = { ...w89, inc: w89.inc.set(iid, { ...w89.inc.get(iid), timers: w89.inc.get(iid).timers.set(timerId, { ...w89.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w90
    } else {
      val w91 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_92 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w93 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_92 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_92)) }) }) }
      val w94 = { ...w93, inc: w93.inc.set(iid, { ...w93.inc.get(iid), timers: w93.inc.get(iid).timers.set(timerId, { ...w93.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w95 = { ...w94, inc: w94.inc.set(iid, { ...w94.inc.get(iid), timers: w94.inc.get(iid).timers.set(timerId, { ...w94.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w95
    } else w0
      w91
    }
    w87
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w96 = if (not(timerDef(timerId).pausable)) {
      val w97 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w98 = { ...w97, inc: w97.inc.set(iid, { ...w97.inc.get(iid), timers: w97.inc.get(iid).timers.set(timerId, { ...w97.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w98
    } else {
      val w99 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w100 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w101 = { ...w100, inc: w100.inc.set(iid, { ...w100.inc.get(iid), timers: w100.inc.get(iid).timers.set(timerId, { ...w100.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w102 = { ...w101, inc: w101.inc.set(iid, { ...w101.inc.get(iid), timers: w101.inc.get(iid).timers.set(timerId, { ...w101.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w102
    } else w0
      w99
    }
    w96
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_103 = ""
    val w104 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_103 }) }
    w104
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_105 = ""
    val w106 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_105 }) }
    w106
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_107 = 0
    val w108 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_107 }) }
    w108
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w109 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w110 = if (timerDef("reaction").startsOnce) {
      val w111 = ec_resumeTimer(w0, c, iid, "reaction")
      w111
    } else {
      val w112 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w113 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w114 = { ...w113, inc: w113.inc.set(iid, { ...w113.inc.get(iid), timers: w113.inc.get(iid).timers.set("reaction", { ...w113.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w115 = { ...w114, inc: w114.inc.set(iid, { ...w114.inc.get(iid), timers: w114.inc.get(iid).timers.set("reaction", { ...w114.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w115
    } else {
      val sec_116 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w117 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_116 < 0)) 0 else (c.now + (sec_116 * 1000))) }) }) }
      val w118 = { ...w117, inc: w117.inc.set(iid, { ...w117.inc.get(iid), timers: w117.inc.get(iid).timers.set("reaction", { ...w117.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w119 = { ...w118, inc: w118.inc.set(iid, { ...w118.inc.get(iid), timers: w118.inc.get(iid).timers.set("reaction", { ...w118.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w120 = { ...w119, inc: w119.inc.set(iid, { ...w119.inc.get(iid), timers: w119.inc.get(iid).timers.set("reaction", { ...w119.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w120
    }
      w112
    }
      w110
    }
    w109
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
    not(settings.session.states.foldl(false, (acc, s_121) => acc or ((s_121.id == agentState(c.me)) and s_121.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_122 = c.actor
    val w123 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_122 }) }
    w123
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w124 = if (timerDef("reaction").startsOnce) {
      val w125 = ec_pauseTimer(w0, c, iid, "reaction")
      w125
    } else {
      val w126 = if (false) {
      val w127 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w128 = { ...w127, inc: w127.inc.set(iid, { ...w127.inc.get(iid), timers: w127.inc.get(iid).timers.set("reaction", { ...w127.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w129 = { ...w128, inc: w128.inc.set(iid, { ...w128.inc.get(iid), timers: w128.inc.get(iid).timers.set("reaction", { ...w128.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w130 = { ...w129, inc: w129.inc.set(iid, { ...w129.inc.get(iid), timers: w129.inc.get(iid).timers.set("reaction", { ...w129.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w130
    } else {
      val w131 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_132 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w133 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_132) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w134 = { ...w133, inc: w133.inc.set(iid, { ...w133.inc.get(iid), timers: w133.inc.get(iid).timers.set("reaction", { ...w133.inc.get(iid).timers.get("reaction"), paused: keep_132 }) }) }
      val w135 = { ...w134, inc: w134.inc.set(iid, { ...w134.inc.get(iid), timers: w134.inc.get(iid).timers.set("reaction", { ...w134.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w136 = { ...w135, inc: w135.inc.set(iid, { ...w135.inc.get(iid), timers: w135.inc.get(iid).timers.set("reaction", { ...w135.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w136
    }
      w131
    }
      w126
    }
    w124
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
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
    not(settings.session.states.foldl(false, (acc, s_146) => acc or ((s_146.id == agentState(c.me)) and s_146.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_147 = c.actor
    val w148 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_147 }) }
    w148
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_149 = ""
    val w150 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_149 }) }
    w150
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w151 = if (timerDef("reaction").startsOnce) {
      val w152 = ec_pauseTimer(w0, c, iid, "reaction")
      w152
    } else {
      val w153 = if (false) {
      val w154 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w155 = { ...w154, inc: w154.inc.set(iid, { ...w154.inc.get(iid), timers: w154.inc.get(iid).timers.set("reaction", { ...w154.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w156 = { ...w155, inc: w155.inc.set(iid, { ...w155.inc.get(iid), timers: w155.inc.get(iid).timers.set("reaction", { ...w155.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w157 = { ...w156, inc: w156.inc.set(iid, { ...w156.inc.get(iid), timers: w156.inc.get(iid).timers.set("reaction", { ...w156.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w157
    } else {
      val w158 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_159 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w160 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_159) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w161 = { ...w160, inc: w160.inc.set(iid, { ...w160.inc.get(iid), timers: w160.inc.get(iid).timers.set("reaction", { ...w160.inc.get(iid).timers.get("reaction"), paused: keep_159 }) }) }
      val w162 = { ...w161, inc: w161.inc.set(iid, { ...w161.inc.get(iid), timers: w161.inc.get(iid).timers.set("reaction", { ...w161.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w163 = { ...w162, inc: w162.inc.set(iid, { ...w162.inc.get(iid), timers: w162.inc.get(iid).timers.set("reaction", { ...w162.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w163
    }
      w158
    }
      w153
    }
    w151
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w164 = if (not(timerDef("resolution").pausable)) {
      val sec_165 = timerSec(w0.inc.get(iid), "resolution", "")
      val w166 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_165 < 0)) 0 else (c.now + (sec_165 * 1000))) }) }) }
      val w167 = { ...w166, inc: w166.inc.set(iid, { ...w166.inc.get(iid), timers: w166.inc.get(iid).timers.set("resolution", { ...w166.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w167
    } else {
      val w168 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_169 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w170 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_169 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_169)) }) }) }
      val w171 = { ...w170, inc: w170.inc.set(iid, { ...w170.inc.get(iid), timers: w170.inc.get(iid).timers.set("resolution", { ...w170.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w172 = { ...w171, inc: w171.inc.set(iid, { ...w171.inc.get(iid), timers: w171.inc.get(iid).timers.set("resolution", { ...w171.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w172
    } else w0
      w168
    }
    w164
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
    not(settings.session.states.foldl(false, (acc, s_173) => acc or ((s_173.id == agentState(c.me)) and s_173.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_174 = ""
    val w175 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_174 }) }
    w175
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_176 = ""
    val w177 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_176 }) }
    w177
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
    not(settings.session.states.foldl(false, (acc, s_178) => acc or ((s_178.id == agentState(c.me)) and s_178.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
    settings.holdReasons.foldl(false, (acc, r_179) => acc or (r_179.setBy != "system")),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_180 = c.form.reasonId
    val w181 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_180 }) }
    w181
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
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

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w189 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w190 = if (timerDef("hold").startsOnce) {
      val w191 = ec_resumeTimer(w0, c, iid, "hold")
      w191
    } else {
      val w192 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w193 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w194 = { ...w193, inc: w193.inc.set(iid, { ...w193.inc.get(iid), timers: w193.inc.get(iid).timers.set("hold", { ...w193.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w195 = { ...w194, inc: w194.inc.set(iid, { ...w194.inc.get(iid), timers: w194.inc.get(iid).timers.set("hold", { ...w194.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w195
    } else {
      val sec_196 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w197 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_196 < 0)) 0 else (c.now + (sec_196 * 1000))) }) }) }
      val w198 = { ...w197, inc: w197.inc.set(iid, { ...w197.inc.get(iid), timers: w197.inc.get(iid).timers.set("hold", { ...w197.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w199 = { ...w198, inc: w198.inc.set(iid, { ...w198.inc.get(iid), timers: w198.inc.get(iid).timers.set("hold", { ...w198.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w200 = { ...w199, inc: w199.inc.set(iid, { ...w199.inc.get(iid), timers: w199.inc.get(iid).timers.set("hold", { ...w199.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w200
    }
      w192
    }
      w190
    }
    w189
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
    not(settings.session.states.foldl(false, (acc, s_201) => acc or ((s_201.id == agentState(c.me)) and s_201.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w202 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w202
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w203 = if (timerDef("hold").startsOnce) {
      val w204 = ec_pauseTimer(w0, c, iid, "hold")
      w204
    } else {
      val w205 = if (false) {
      val w206 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w207 = { ...w206, inc: w206.inc.set(iid, { ...w206.inc.get(iid), timers: w206.inc.get(iid).timers.set("hold", { ...w206.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w208 = { ...w207, inc: w207.inc.set(iid, { ...w207.inc.get(iid), timers: w207.inc.get(iid).timers.set("hold", { ...w207.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w209 = { ...w208, inc: w208.inc.set(iid, { ...w208.inc.get(iid), timers: w208.inc.get(iid).timers.set("hold", { ...w208.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w209
    } else {
      val w210 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_211 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w212 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_211) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w213 = { ...w212, inc: w212.inc.set(iid, { ...w212.inc.get(iid), timers: w212.inc.get(iid).timers.set("hold", { ...w212.inc.get(iid).timers.get("hold"), paused: keep_211 }) }) }
      val w214 = { ...w213, inc: w213.inc.set(iid, { ...w213.inc.get(iid), timers: w213.inc.get(iid).timers.set("hold", { ...w213.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w215 = { ...w214, inc: w214.inc.set(iid, { ...w214.inc.get(iid), timers: w214.inc.get(iid).timers.set("hold", { ...w214.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w215
    }
      w210
    }
      w205
    }
    w203
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w216 = if (not(timerDef("resolution").pausable)) {
      val sec_217 = timerSec(w0.inc.get(iid), "resolution", "")
      val w218 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_217 < 0)) 0 else (c.now + (sec_217 * 1000))) }) }) }
      val w219 = { ...w218, inc: w218.inc.set(iid, { ...w218.inc.get(iid), timers: w218.inc.get(iid).timers.set("resolution", { ...w218.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w219
    } else {
      val w220 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_221 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w222 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_221 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_221)) }) }) }
      val w223 = { ...w222, inc: w222.inc.set(iid, { ...w222.inc.get(iid), timers: w222.inc.get(iid).timers.set("resolution", { ...w222.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w224 = { ...w223, inc: w223.inc.set(iid, { ...w223.inc.get(iid), timers: w223.inc.get(iid).timers.set("resolution", { ...w223.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w224
    } else w0
      w220
    }
    w216
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
    not(settings.session.states.foldl(false, (acc, s_225) => acc or ((s_225.id == agentState(c.me)) and s_225.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_226 = ""
    val w227 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_226 }) }
    w227
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w228 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w228
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
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

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w236 = if (timerDef("hold").startsOnce) {
      val w237 = ec_pauseTimer(w0, c, iid, "hold")
      w237
    } else {
      val w238 = if (false) {
      val w239 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w240 = { ...w239, inc: w239.inc.set(iid, { ...w239.inc.get(iid), timers: w239.inc.get(iid).timers.set("hold", { ...w239.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w241 = { ...w240, inc: w240.inc.set(iid, { ...w240.inc.get(iid), timers: w240.inc.get(iid).timers.set("hold", { ...w240.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w242 = { ...w241, inc: w241.inc.set(iid, { ...w241.inc.get(iid), timers: w241.inc.get(iid).timers.set("hold", { ...w241.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w242
    } else {
      val w243 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_244 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w245 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_244) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w246 = { ...w245, inc: w245.inc.set(iid, { ...w245.inc.get(iid), timers: w245.inc.get(iid).timers.set("hold", { ...w245.inc.get(iid).timers.get("hold"), paused: keep_244 }) }) }
      val w247 = { ...w246, inc: w246.inc.set(iid, { ...w246.inc.get(iid), timers: w246.inc.get(iid).timers.set("hold", { ...w246.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w248 = { ...w247, inc: w247.inc.set(iid, { ...w247.inc.get(iid), timers: w247.inc.get(iid).timers.set("hold", { ...w247.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w248
    }
      w243
    }
      w238
    }
    w236
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w249 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w250 = if (timerDef("reaction").startsOnce) {
      val w251 = ec_resumeTimer(w0, c, iid, "reaction")
      w251
    } else {
      val w252 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w253 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("reaction", { ...w253.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w255 = { ...w254, inc: w254.inc.set(iid, { ...w254.inc.get(iid), timers: w254.inc.get(iid).timers.set("reaction", { ...w254.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w255
    } else {
      val sec_256 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w257 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_256 < 0)) 0 else (c.now + (sec_256 * 1000))) }) }) }
      val w258 = { ...w257, inc: w257.inc.set(iid, { ...w257.inc.get(iid), timers: w257.inc.get(iid).timers.set("reaction", { ...w257.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w259 = { ...w258, inc: w258.inc.set(iid, { ...w258.inc.get(iid), timers: w258.inc.get(iid).timers.set("reaction", { ...w258.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w260 = { ...w259, inc: w259.inc.set(iid, { ...w259.inc.get(iid), timers: w259.inc.get(iid).timers.set("reaction", { ...w259.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w260
    }
      w252
    }
      w250
    }
    w249
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
    not(settings.session.states.foldl(false, (acc, s_261) => acc or ((s_261.id == agentState(c.me)) and s_261.readOnly))),
    transferTargets.foldl(false, (acc, t_262) => acc or (offersTransferTo(c.me, t_262, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_263) => acc and (isDone(e_263) or hasAccess(t_262, e_263))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_264) => acc and (isDone(e_264) or hasAccess(c.form.targetId, e_264)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_265 = personOf(c.form.targetId)
    val w266 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_265 }) }
    w266
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_267 = groupOf(c.form.targetId)
    val w268 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_267 }) }
    w268
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w269 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w269
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w270 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w270
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w271 = if (not(timerDef("resolution").pausable)) {
      val w272 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w273 = { ...w272, inc: w272.inc.set(iid, { ...w272.inc.get(iid), timers: w272.inc.get(iid).timers.set("resolution", { ...w272.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w273
    } else {
      val w274 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w275 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w276 = { ...w275, inc: w275.inc.set(iid, { ...w275.inc.get(iid), timers: w275.inc.get(iid).timers.set("resolution", { ...w275.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w277 = { ...w276, inc: w276.inc.set(iid, { ...w276.inc.get(iid), timers: w276.inc.get(iid).timers.set("resolution", { ...w276.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w277
    } else w0
      w274
    }
    w271
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w278 = if (timerDef("hold").startsOnce) {
      val w279 = ec_pauseTimer(w0, c, iid, "hold")
      w279
    } else {
      val w280 = if (false) {
      val w281 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w282 = { ...w281, inc: w281.inc.set(iid, { ...w281.inc.get(iid), timers: w281.inc.get(iid).timers.set("hold", { ...w281.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w283 = { ...w282, inc: w282.inc.set(iid, { ...w282.inc.get(iid), timers: w282.inc.get(iid).timers.set("hold", { ...w282.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w284 = { ...w283, inc: w283.inc.set(iid, { ...w283.inc.get(iid), timers: w283.inc.get(iid).timers.set("hold", { ...w283.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w284
    } else {
      val w285 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_286 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w287 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_286) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w288 = { ...w287, inc: w287.inc.set(iid, { ...w287.inc.get(iid), timers: w287.inc.get(iid).timers.set("hold", { ...w287.inc.get(iid).timers.get("hold"), paused: keep_286 }) }) }
      val w289 = { ...w288, inc: w288.inc.set(iid, { ...w288.inc.get(iid), timers: w288.inc.get(iid).timers.set("hold", { ...w288.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w290 = { ...w289, inc: w289.inc.set(iid, { ...w289.inc.get(iid), timers: w289.inc.get(iid).timers.set("hold", { ...w289.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w290
    }
      w285
    }
      w280
    }
    w278
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w291 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w292 = if (timerDef("reaction").startsOnce) {
      val w293 = ec_resumeTimer(w0, c, iid, "reaction")
      w293
    } else {
      val w294 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w295 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("reaction", { ...w295.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w297 = { ...w296, inc: w296.inc.set(iid, { ...w296.inc.get(iid), timers: w296.inc.get(iid).timers.set("reaction", { ...w296.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w297
    } else {
      val sec_298 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w299 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_298 < 0)) 0 else (c.now + (sec_298 * 1000))) }) }) }
      val w300 = { ...w299, inc: w299.inc.set(iid, { ...w299.inc.get(iid), timers: w299.inc.get(iid).timers.set("reaction", { ...w299.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w301 = { ...w300, inc: w300.inc.set(iid, { ...w300.inc.get(iid), timers: w300.inc.get(iid).timers.set("reaction", { ...w300.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w302 = { ...w301, inc: w301.inc.set(iid, { ...w301.inc.get(iid), timers: w301.inc.get(iid).timers.set("reaction", { ...w301.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w302
    }
      w294
    }
      w292
    }
    w291
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_303 = c.before.owner
    val w304 = if (((whom_303 != "") and (whom_303 != c.actor))) w0 else w0
    w304
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_305 = addressee(w0.inc.get(iid))
    val w306 = if (((whom_305 != "") and (whom_305 != c.actor))) w0 else w0
    w306
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
    not(settings.session.states.foldl(false, (acc, s_307) => acc or ((s_307.id == agentState(c.me)) and s_307.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_308 = c.actor
    val w309 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_308 }) }
    w309
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_310 = ""
    val w311 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_310 }) }
    w311
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w312 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w312
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w313 = if (timerDef("reaction").startsOnce) {
      val w314 = ec_pauseTimer(w0, c, iid, "reaction")
      w314
    } else {
      val w315 = if (false) {
      val w316 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w317 = { ...w316, inc: w316.inc.set(iid, { ...w316.inc.get(iid), timers: w316.inc.get(iid).timers.set("reaction", { ...w316.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w318 = { ...w317, inc: w317.inc.set(iid, { ...w317.inc.get(iid), timers: w317.inc.get(iid).timers.set("reaction", { ...w317.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w319 = { ...w318, inc: w318.inc.set(iid, { ...w318.inc.get(iid), timers: w318.inc.get(iid).timers.set("reaction", { ...w318.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w319
    } else {
      val w320 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_321 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w322 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_321) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w323 = { ...w322, inc: w322.inc.set(iid, { ...w322.inc.get(iid), timers: w322.inc.get(iid).timers.set("reaction", { ...w322.inc.get(iid).timers.get("reaction"), paused: keep_321 }) }) }
      val w324 = { ...w323, inc: w323.inc.set(iid, { ...w323.inc.get(iid), timers: w323.inc.get(iid).timers.set("reaction", { ...w323.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w325 = { ...w324, inc: w324.inc.set(iid, { ...w324.inc.get(iid), timers: w324.inc.get(iid).timers.set("reaction", { ...w324.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w325
    }
      w320
    }
      w315
    }
    w313
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w326 = if (timerDef("hold").startsOnce) {
      val w327 = ec_pauseTimer(w0, c, iid, "hold")
      w327
    } else {
      val w328 = if (false) {
      val w329 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w330 = { ...w329, inc: w329.inc.set(iid, { ...w329.inc.get(iid), timers: w329.inc.get(iid).timers.set("hold", { ...w329.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w331 = { ...w330, inc: w330.inc.set(iid, { ...w330.inc.get(iid), timers: w330.inc.get(iid).timers.set("hold", { ...w330.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w332 = { ...w331, inc: w331.inc.set(iid, { ...w331.inc.get(iid), timers: w331.inc.get(iid).timers.set("hold", { ...w331.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w332
    } else {
      val w333 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_334 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w335 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_334) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w336 = { ...w335, inc: w335.inc.set(iid, { ...w335.inc.get(iid), timers: w335.inc.get(iid).timers.set("hold", { ...w335.inc.get(iid).timers.get("hold"), paused: keep_334 }) }) }
      val w337 = { ...w336, inc: w336.inc.set(iid, { ...w336.inc.get(iid), timers: w336.inc.get(iid).timers.set("hold", { ...w336.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w338 = { ...w337, inc: w337.inc.set(iid, { ...w337.inc.get(iid), timers: w337.inc.get(iid).timers.set("hold", { ...w337.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w338
    }
      w333
    }
      w328
    }
    w326
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w339 = if (not(timerDef("resolution").pausable)) {
      val sec_340 = timerSec(w0.inc.get(iid), "resolution", "")
      val w341 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_340 < 0)) 0 else (c.now + (sec_340 * 1000))) }) }) }
      val w342 = { ...w341, inc: w341.inc.set(iid, { ...w341.inc.get(iid), timers: w341.inc.get(iid).timers.set("resolution", { ...w341.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w342
    } else {
      val w343 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_344 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w345 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_344 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_344)) }) }) }
      val w346 = { ...w345, inc: w345.inc.set(iid, { ...w345.inc.get(iid), timers: w345.inc.get(iid).timers.set("resolution", { ...w345.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w347 = { ...w346, inc: w346.inc.set(iid, { ...w346.inc.get(iid), timers: w346.inc.get(iid).timers.set("resolution", { ...w346.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w347
    } else w0
      w343
    }
    w339
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
    val whom_348 = c.before.owner
    val w349 = if (((whom_348 != "") and (whom_348 != c.actor))) w0 else w0
    w349
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
    not(settings.session.states.foldl(false, (acc, s_350) => acc or ((s_350.id == agentState(c.me)) and s_350.readOnly))),
    { val os_351 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_351.foldl(false, (acc, o_352) => acc or ((o_352.id == c.form.resultId) and stepsOk(o_352, world.inc.get(iid)))) else os_351.foldl(false, (acc, o_353) => acc or stepsOk(o_353, world.inc.get(iid)))) },
    ((((c.form.resultId == "") or (c.form.causeId == "")) or not(settings.closeResults.foldl(false, (acc, i_354) => acc or ((i_354.id == c.form.resultId) and (i_354.causeCatalog != ""))))) or (causeOk(c.form.resultId, c.form.causeId) and (not(causeCommentRequired(c.form.resultId, c.form.causeId)) or (c.form.comment != "")))),
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_355 = c.actor
    val w356 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_355 }) }
    w356
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_357 = ""
    val w358 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_357 }) }
    w358
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_359 = c.actor
    val w360 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_359 }) }
    w360
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_361 = c.now
    val w362 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_361 }) }
    w362
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_363 = c.form.resultId
    val w364 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_363 }) }
    w364
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_365 = (if (causeOk(c.form.resultId, c.form.causeId)) c.form.causeId else "")
    val w366 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_365 }) }
    w366
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_367 = causeLabel(c.form.resultId, c.form.causeId)
    val w368 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_367 }) }
    w368
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val value_369 = (if ((c.form.resultId == "drill")) c.form.maintenanceWindowId else "")
    val w370 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_369 }) }
    w370
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val value_371 = c.form.comment
    val w372 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_371 }) }
    w372
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w373 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w373
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w374 = if (timerDef("reaction").startsOnce) {
      val w375 = ec_pauseTimer(w0, c, iid, "reaction")
      w375
    } else {
      val w376 = if (true) {
      val w377 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w378 = { ...w377, inc: w377.inc.set(iid, { ...w377.inc.get(iid), timers: w377.inc.get(iid).timers.set("reaction", { ...w377.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w379 = { ...w378, inc: w378.inc.set(iid, { ...w378.inc.get(iid), timers: w378.inc.get(iid).timers.set("reaction", { ...w378.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w380 = { ...w379, inc: w379.inc.set(iid, { ...w379.inc.get(iid), timers: w379.inc.get(iid).timers.set("reaction", { ...w379.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w380
    } else {
      val w381 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_382 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w383 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_382) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w384 = { ...w383, inc: w383.inc.set(iid, { ...w383.inc.get(iid), timers: w383.inc.get(iid).timers.set("reaction", { ...w383.inc.get(iid).timers.get("reaction"), paused: keep_382 }) }) }
      val w385 = { ...w384, inc: w384.inc.set(iid, { ...w384.inc.get(iid), timers: w384.inc.get(iid).timers.set("reaction", { ...w384.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w386 = { ...w385, inc: w385.inc.set(iid, { ...w385.inc.get(iid), timers: w385.inc.get(iid).timers.set("reaction", { ...w385.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w386
    }
      w381
    }
      w376
    }
    w374
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {
    val w387 = if (not(timerDef("resolution").pausable)) {
      val w388 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w389 = { ...w388, inc: w388.inc.set(iid, { ...w388.inc.get(iid), timers: w388.inc.get(iid).timers.set("resolution", { ...w388.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w389
    } else {
      val w390 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w391 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w392 = { ...w391, inc: w391.inc.set(iid, { ...w391.inc.get(iid), timers: w391.inc.get(iid).timers.set("resolution", { ...w391.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w393 = { ...w392, inc: w392.inc.set(iid, { ...w392.inc.get(iid), timers: w392.inc.get(iid).timers.set("resolution", { ...w392.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w393
    } else w0
      w390
    }
    w387
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {
    val w394 = if (timerDef("hold").startsOnce) {
      val w395 = ec_pauseTimer(w0, c, iid, "hold")
      w395
    } else {
      val w396 = if (false) {
      val w397 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w398 = { ...w397, inc: w397.inc.set(iid, { ...w397.inc.get(iid), timers: w397.inc.get(iid).timers.set("hold", { ...w397.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w399 = { ...w398, inc: w398.inc.set(iid, { ...w398.inc.get(iid), timers: w398.inc.get(iid).timers.set("hold", { ...w398.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w400 = { ...w399, inc: w399.inc.set(iid, { ...w399.inc.get(iid), timers: w399.inc.get(iid).timers.set("hold", { ...w399.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w400
    } else {
      val w401 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_402 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w403 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_402) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w404 = { ...w403, inc: w403.inc.set(iid, { ...w403.inc.get(iid), timers: w403.inc.get(iid).timers.set("hold", { ...w403.inc.get(iid).timers.get("hold"), paused: keep_402 }) }) }
      val w405 = { ...w404, inc: w404.inc.set(iid, { ...w404.inc.get(iid), timers: w404.inc.get(iid).timers.set("hold", { ...w404.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w406 = { ...w405, inc: w405.inc.set(iid, { ...w405.inc.get(iid), timers: w405.inc.get(iid).timers.set("hold", { ...w405.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w406
    }
      w401
    }
      w396
    }
    w394
  }

  def e_close_13(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_14(w0: World, c: Ctx, iid: str): World = {
    val w407 = if (["false_alarm"].foldl(false, (acc, y408) => acc or y408 == w0.inc.get(iid).closeResultId)) {
      val w409 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_413 => not(isDone(x_413))).foldl([], (acc, x412) => acc.append(x412.id)).foldl(w0, (wf410, sId411) => wf410)
      w409
    } else w0
    w407
  }

  def e_close_15(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_16(w0: World, c: Ctx, iid: str): World = {
    val w414 = if (["false_alarm"].foldl(false, (acc, y415) => acc or y415 == w0.inc.get(iid).closeResultId)) {
      val w416 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_423 => not(isDone(x_423))).foldl([], (acc, x419) => acc.append(x419.id)).foldl(w0, (wf417, sId418) => {
      val lead_420 = (if ((wf417.inc.get(sId418).linkedTo != "")) { val ps_421 = incidentById(incs(w0), wf417.inc.get(sId418).linkedTo)  (if (((ps_421.length() > 0) and not(isDone(ps_421[0])))) addressee(ps_421[0]) else "") } else addressee(wf417.inc.get(sId418)))
      val w422 = if (((lead_420 != "") and (lead_420 != wf417.inc.get(iid).closedBy))) wf417 else wf417
      w422
    })
      w416
    } else w0
    w414
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
    not(settings.session.states.foldl(false, (acc, s_424) => acc or ((s_424.id == agentState(c.me)) and s_424.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_425 = c.actor
    val w426 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_425 }) }
    w426
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w427 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_428 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w429 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w430 = { ...w429, inc: w429.inc.set(iid, { ...w429.inc.get(iid), linkedTo: "" }) }
      val w431 = { ...w430, inc: w430.inc.set(iid, { ...w430.inc.get(iid), linkedAt: 0 }) }
      val w432 = if (((ps_428.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w431 else w431
      val w433 = if (("workflow.journal.linked_reopened" != "")) {
      val w434 = ps_428.foldl([], (acc, x437) => acc.append(x437.id)).foldl(w432, (wf435, pId436) => wf435)
      w434
    } else w432
      w433
    } else {
      val w438 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w439 = { ...w438, inc: w438.inc.set(iid, { ...w438.inc.get(iid), linkedAt: 0 }) }
      w439
    }
    w427
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_440 = ""
    val w441 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_440 }) }
    w441
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_442 = ""
    val w443 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_442 }) }
    w443
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_444 = ""
    val w445 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_444 }) }
    w445
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_446 = ""
    val w447 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_446 }) }
    w447
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_448 = ""
    val w449 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_448 }) }
    w449
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val value_450 = 0
    val w451 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_450 }) }
    w451
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val value_452 = ""
    val w453 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_452 }) }
    w453
  }

  def e_reopen_10(w0: World, c: Ctx, iid: str): World = {
    val sec_454 = settings.limits.reopenResolutionSec
    val w455 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_454 > 0)) sec_454 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w456 = { ...w455, inc: w455.inc.set(iid, { ...w455.inc.get(iid), timers: w455.inc.get(iid).timers.set("resolution", { ...w455.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w457 = { ...w456, inc: w456.inc.set(iid, { ...w456.inc.get(iid), timers: w456.inc.get(iid).timers.set("resolution", { ...w456.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w457
  }

  def e_reopen_11(w0: World, c: Ctx, iid: str): World = {
    val w458 = if (timerDef("reaction").startsOnce) {
      val w459 = ec_pauseTimer(w0, c, iid, "reaction")
      w459
    } else {
      val w460 = if (true) {
      val w461 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w462 = { ...w461, inc: w461.inc.set(iid, { ...w461.inc.get(iid), timers: w461.inc.get(iid).timers.set("reaction", { ...w461.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w463 = { ...w462, inc: w462.inc.set(iid, { ...w462.inc.get(iid), timers: w462.inc.get(iid).timers.set("reaction", { ...w462.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w464 = { ...w463, inc: w463.inc.set(iid, { ...w463.inc.get(iid), timers: w463.inc.get(iid).timers.set("reaction", { ...w463.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w464
    } else {
      val w465 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_466 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w467 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_466) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w468 = { ...w467, inc: w467.inc.set(iid, { ...w467.inc.get(iid), timers: w467.inc.get(iid).timers.set("reaction", { ...w467.inc.get(iid).timers.get("reaction"), paused: keep_466 }) }) }
      val w469 = { ...w468, inc: w468.inc.set(iid, { ...w468.inc.get(iid), timers: w468.inc.get(iid).timers.set("reaction", { ...w468.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w470 = { ...w469, inc: w469.inc.set(iid, { ...w469.inc.get(iid), timers: w469.inc.get(iid).timers.set("reaction", { ...w469.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w470
    }
      w465
    }
      w460
    }
    w458
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
    not(settings.session.states.foldl(false, (acc, s_471) => acc or ((s_471.id == agentState(c.me)) and s_471.readOnly))),
    ((if (c.form.comment == "") 0 else 1) <= settings.limits.commentMaxLength),
    (c.form.files.length() <= settings.limits.commentMaxFiles),
    c.form.files.foldl(true, (acc, f_472) => acc and (f_472.size <= settings.limits.attachmentMaxBytes)),
    c.form.files.foldl(true, (acc, f_473) => acc and settings.limits.attachmentTypes.foldl(false, (acc, y474) => acc or y474 == f_473.mime)),
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
    not(settings.session.states.foldl(false, (acc, s_475) => acc or ((s_475.id == agentState(c.me)) and s_475.readOnly))),
    ((c.form.priority == "") or (priorityOf(c.form.priority) != world.inc.get(iid).priority)),
  }

  def e_change_priority_0(w0: World, c: Ctx, iid: str): World = {
    val value_476 = priorityOf(c.form.priority)
    val w477 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priority: value_476 }) }
    w477
  }

  def e_change_priority_1(w0: World, c: Ctx, iid: str): World = {
    val value_478 = true
    val w479 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priorityManual: value_478 }) }
    w479
  }

  def e_change_priority_2(w0: World, c: Ctx, iid: str): World = {
    val t_480 = w0.inc.get(iid).timers.get("reaction")
    val raw_481 = ((timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel") - timerSec(c.before, "reaction", "byEscalationLevel")) * 1000)
    val delta_482 = (if (((raw_481 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_483) => acc or (m_483.state == "linked")))) 0 else raw_481)
    val w484 = if ((((t_480.due != 0) and (t_480.due > c.now)) and (t_480.fired != t_480.due))) {
      val w485 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if (((t_480.due + delta_482) > c.now)) (t_480.due + delta_482) else c.now) }) }) }
      w485
    } else {
      val w486 = if ((((timerDef("reaction").pausable and (t_480.due == 0)) and t_480.paused) and (t_480.left > 0))) {
      val w487 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (((t_480.left + delta_482) > 0)) (t_480.left + delta_482) else 1) }) }) }
      w487
    } else w0
      w486
    }
    w484
  }

  def e_change_priority_3(w0: World, c: Ctx, iid: str): World = {
    val t_488 = w0.inc.get(iid).timers.get("resolution")
    val raw_489 = ((timerSec(w0.inc.get(iid), "resolution", "") - timerSec(c.before, "resolution", "")) * 1000)
    val delta_490 = (if (((raw_489 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_491) => acc or (m_491.state == "linked")))) 0 else raw_489)
    val w492 = if ((((t_488.due != 0) and (t_488.due > c.now)) and (t_488.fired != t_488.due))) {
      val w493 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((t_488.due + delta_490) > c.now)) (t_488.due + delta_490) else c.now) }) }) }
      w493
    } else {
      val w494 = if ((((timerDef("resolution").pausable and (t_488.due == 0)) and t_488.paused) and (t_488.left > 0))) {
      val w495 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((t_488.left + delta_490) > 0)) (t_488.left + delta_490) else 1) }) }) }
      w495
    } else w0
      w494
    }
    w492
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
    { val t_496 = world.inc.get(iid).timers.get("reaction")  (((t_496.due != 0) and (t_496.due <= c.now)) and (t_496.fired != t_496.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_497 = personOf(levelUpTarget(c.before))
    val w498 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_497 }) }
    w498
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_499 = groupOf(levelUpTarget(c.before))
    val w500 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_499 }) }
    w500
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_501 = levelUpNumber(c.before)
    val w502 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_501 }) }
    w502
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w503 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w503
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w504 = if (not(timerDef("resolution").pausable)) {
      val w505 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w506 = { ...w505, inc: w505.inc.set(iid, { ...w505.inc.get(iid), timers: w505.inc.get(iid).timers.set("resolution", { ...w505.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w506
    } else {
      val w507 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w508 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w509 = { ...w508, inc: w508.inc.set(iid, { ...w508.inc.get(iid), timers: w508.inc.get(iid).timers.set("resolution", { ...w508.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w510 = { ...w509, inc: w509.inc.set(iid, { ...w509.inc.get(iid), timers: w509.inc.get(iid).timers.set("resolution", { ...w509.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w510
    } else w0
      w507
    }
    w504
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w511 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w512 = if (timerDef("reaction").startsOnce) {
      val w513 = ec_resumeTimer(w0, c, iid, "reaction")
      w513
    } else {
      val w514 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w515 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w516 = { ...w515, inc: w515.inc.set(iid, { ...w515.inc.get(iid), timers: w515.inc.get(iid).timers.set("reaction", { ...w515.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w517 = { ...w516, inc: w516.inc.set(iid, { ...w516.inc.get(iid), timers: w516.inc.get(iid).timers.set("reaction", { ...w516.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w517
    } else {
      val sec_518 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w519 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_518 < 0)) 0 else (c.now + (sec_518 * 1000))) }) }) }
      val w520 = { ...w519, inc: w519.inc.set(iid, { ...w519.inc.get(iid), timers: w519.inc.get(iid).timers.set("reaction", { ...w519.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w521 = { ...w520, inc: w520.inc.set(iid, { ...w520.inc.get(iid), timers: w520.inc.get(iid).timers.set("reaction", { ...w520.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w522 = { ...w521, inc: w521.inc.set(iid, { ...w521.inc.get(iid), timers: w521.inc.get(iid).timers.set("reaction", { ...w521.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w522
    }
      w514
    }
      w512
    }
    w511
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_523 = addressee(w0.inc.get(iid))
    val w524 = if (((whom_523 != "") and (whom_523 != c.actor))) w0 else w0
    w524
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
    { val t_525 = world.inc.get(iid).timers.get("reaction")  (((t_525.due != 0) and (t_525.due <= c.now)) and (t_525.fired != t_525.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_526 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w527 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_526) }) }
    val w528 = { ...w527, inc: w527.inc.set(iid, { ...w527.inc.get(iid), slaBreached: true }) }
    val w529 = groupMembersAt(incs(w0), w528.inc.get(iid), c.deadline).foldl([], (acc, x532) => acc.append(x532.id)).foldl(w528, (wf530, eId531) => {
      val w533 = { ...wf530, inc: wf530.inc.set(eId531, { ...wf530.inc.get(eId531), breaches: wf530.inc.get(eId531).breaches.append(breach_526) }) }
      val w534 = { ...w533, inc: w533.inc.set(eId531, { ...w533.inc.get(eId531), slaBreached: true }) }
      w534
    })
    w529
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w535 = if (timerDef("reaction").startsOnce) {
      val w536 = ec_pauseTimer(w0, c, iid, "reaction")
      w536
    } else {
      val w537 = if (false) {
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

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_548 = settings.alerts.target
    val w549 = if (((whom_548 != "") and (whom_548 != c.actor))) w0 else w0
    w549
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
    { val t_550 = world.inc.get(iid).timers.get("reaction")  (((t_550.due != 0) and (t_550.due <= c.now)) and (t_550.fired != t_550.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_551 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w552 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_551) }) }
    val w553 = { ...w552, inc: w552.inc.set(iid, { ...w552.inc.get(iid), slaBreached: true }) }
    val w554 = groupMembersAt(incs(w0), w553.inc.get(iid), c.deadline).foldl([], (acc, x557) => acc.append(x557.id)).foldl(w553, (wf555, eId556) => {
      val w558 = { ...wf555, inc: wf555.inc.set(eId556, { ...wf555.inc.get(eId556), breaches: wf555.inc.get(eId556).breaches.append(breach_551) }) }
      val w559 = { ...w558, inc: w558.inc.set(eId556, { ...w558.inc.get(eId556), slaBreached: true }) }
      w559
    })
    w554
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w560 = if (timerDef("reaction").startsOnce) {
      val w561 = ec_pauseTimer(w0, c, iid, "reaction")
      w561
    } else {
      val w562 = if (false) {
      val w563 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w564 = { ...w563, inc: w563.inc.set(iid, { ...w563.inc.get(iid), timers: w563.inc.get(iid).timers.set("reaction", { ...w563.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w565 = { ...w564, inc: w564.inc.set(iid, { ...w564.inc.get(iid), timers: w564.inc.get(iid).timers.set("reaction", { ...w564.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w566 = { ...w565, inc: w565.inc.set(iid, { ...w565.inc.get(iid), timers: w565.inc.get(iid).timers.set("reaction", { ...w565.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w566
    } else {
      val w567 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_568 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w569 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_568) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w570 = { ...w569, inc: w569.inc.set(iid, { ...w569.inc.get(iid), timers: w569.inc.get(iid).timers.set("reaction", { ...w569.inc.get(iid).timers.get("reaction"), paused: keep_568 }) }) }
      val w571 = { ...w570, inc: w570.inc.set(iid, { ...w570.inc.get(iid), timers: w570.inc.get(iid).timers.set("reaction", { ...w570.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w572 = { ...w571, inc: w571.inc.set(iid, { ...w571.inc.get(iid), timers: w571.inc.get(iid).timers.set("reaction", { ...w571.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w572
    }
      w567
    }
      w562
    }
    w560
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_573 = settings.alerts.target
    val w574 = if (((whom_573 != "") and (whom_573 != c.actor))) w0 else w0
    w574
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
    { val t_575 = world.inc.get(iid).timers.get("resolution")  (((t_575.due != 0) and (t_575.due <= c.now)) and (t_575.fired != t_575.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_576 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w577 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_576) }) }
    val w578 = { ...w577, inc: w577.inc.set(iid, { ...w577.inc.get(iid), slaBreached: true }) }
    val w579 = groupMembersAt(incs(w0), w578.inc.get(iid), c.deadline).foldl([], (acc, x582) => acc.append(x582.id)).foldl(w578, (wf580, eId581) => {
      val w583 = { ...wf580, inc: wf580.inc.set(eId581, { ...wf580.inc.get(eId581), breaches: wf580.inc.get(eId581).breaches.append(breach_576) }) }
      val w584 = { ...w583, inc: w583.inc.set(eId581, { ...w583.inc.get(eId581), slaBreached: true }) }
      w584
    })
    w579
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_585 = settings.alerts.target
    val w586 = if (((whom_585 != "") and (whom_585 != c.actor))) w0 else w0
    w586
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
    { val t_587 = world.inc.get(iid).timers.get("resolution")  (((t_587.due != 0) and (t_587.due <= c.now)) and (t_587.fired != t_587.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_588 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w589 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_588) }) }
    val w590 = { ...w589, inc: w589.inc.set(iid, { ...w589.inc.get(iid), slaBreached: true }) }
    val w591 = groupMembersAt(incs(w0), w590.inc.get(iid), c.deadline).foldl([], (acc, x594) => acc.append(x594.id)).foldl(w590, (wf592, eId593) => {
      val w595 = { ...wf592, inc: wf592.inc.set(eId593, { ...wf592.inc.get(eId593), breaches: wf592.inc.get(eId593).breaches.append(breach_588) }) }
      val w596 = { ...w595, inc: w595.inc.set(eId593, { ...w595.inc.get(eId593), slaBreached: true }) }
      w596
    })
    w591
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_597 = personOf(levelUpTarget(c.before))
    val w598 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_597 }) }
    w598
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_599 = groupOf(levelUpTarget(c.before))
    val w600 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_599 }) }
    w600
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_601 = levelUpNumber(c.before)
    val w602 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_601 }) }
    w602
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w603 = if (not(timerDef("resolution").pausable)) {
      val w604 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w605 = { ...w604, inc: w604.inc.set(iid, { ...w604.inc.get(iid), timers: w604.inc.get(iid).timers.set("resolution", { ...w604.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w605
    } else {
      val w606 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w607 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w608 = { ...w607, inc: w607.inc.set(iid, { ...w607.inc.get(iid), timers: w607.inc.get(iid).timers.set("resolution", { ...w607.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w609 = { ...w608, inc: w608.inc.set(iid, { ...w608.inc.get(iid), timers: w608.inc.get(iid).timers.set("resolution", { ...w608.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w609
    } else w0
      w606
    }
    w603
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w610 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w611 = if (timerDef("reaction").startsOnce) {
      val w612 = ec_resumeTimer(w0, c, iid, "reaction")
      w612
    } else {
      val w613 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w614 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w615 = { ...w614, inc: w614.inc.set(iid, { ...w614.inc.get(iid), timers: w614.inc.get(iid).timers.set("reaction", { ...w614.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w616 = { ...w615, inc: w615.inc.set(iid, { ...w615.inc.get(iid), timers: w615.inc.get(iid).timers.set("reaction", { ...w615.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w616
    } else {
      val sec_617 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w618 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_617 < 0)) 0 else (c.now + (sec_617 * 1000))) }) }) }
      val w619 = { ...w618, inc: w618.inc.set(iid, { ...w618.inc.get(iid), timers: w618.inc.get(iid).timers.set("reaction", { ...w618.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w620 = { ...w619, inc: w619.inc.set(iid, { ...w619.inc.get(iid), timers: w619.inc.get(iid).timers.set("reaction", { ...w619.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w621 = { ...w620, inc: w620.inc.set(iid, { ...w620.inc.get(iid), timers: w620.inc.get(iid).timers.set("reaction", { ...w620.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w621
    }
      w613
    }
      w611
    }
    w610
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_622 = c.before.owner
    val w623 = if (((whom_622 != "") and (whom_622 != c.actor))) w0 else w0
    w623
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_624 = addressee(w0.inc.get(iid))
    val w625 = if (((whom_624 != "") and (whom_624 != c.actor))) w0 else w0
    w625
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
    { val t_626 = world.inc.get(iid).timers.get("resolution")  (((t_626.due != 0) and (t_626.due <= c.now)) and (t_626.fired != t_626.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_627 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w628 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_627) }) }
    val w629 = { ...w628, inc: w628.inc.set(iid, { ...w628.inc.get(iid), slaBreached: true }) }
    val w630 = groupMembersAt(incs(w0), w629.inc.get(iid), c.deadline).foldl([], (acc, x633) => acc.append(x633.id)).foldl(w629, (wf631, eId632) => {
      val w634 = { ...wf631, inc: wf631.inc.set(eId632, { ...wf631.inc.get(eId632), breaches: wf631.inc.get(eId632).breaches.append(breach_627) }) }
      val w635 = { ...w634, inc: w634.inc.set(eId632, { ...w634.inc.get(eId632), slaBreached: true }) }
      w635
    })
    w630
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_636 = settings.alerts.target
    val w637 = if (((whom_636 != "") and (whom_636 != c.actor))) w0 else w0
    w637
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
    { val t_638 = world.inc.get(iid).timers.get("hold")  (((t_638.due != 0) and (t_638.due <= c.now)) and (t_638.fired != t_638.due)) },
    not(["break", "no_link"].foldl(false, (acc, y639) => acc or y639 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_640 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w641 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_640) }) }
    val w642 = { ...w641, inc: w641.inc.set(iid, { ...w641.inc.get(iid), slaBreached: true }) }
    val w643 = groupMembersAt(incs(w0), w642.inc.get(iid), c.deadline).foldl([], (acc, x646) => acc.append(x646.id)).foldl(w642, (wf644, eId645) => {
      val w647 = { ...wf644, inc: wf644.inc.set(eId645, { ...wf644.inc.get(eId645), breaches: wf644.inc.get(eId645).breaches.append(breach_640) }) }
      val w648 = { ...w647, inc: w647.inc.set(eId645, { ...w647.inc.get(eId645), slaBreached: true }) }
      w648
    })
    w643
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_649 = settings.alerts.target
    val w650 = if (((whom_649 != "") and (whom_649 != c.actor))) w0 else w0
    w650
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
    { val t_651 = world.inc.get(iid).timers.get("hold")  (((t_651.due != 0) and (t_651.due <= c.now)) and (t_651.fired != t_651.due)) },
    ["break"].foldl(false, (acc, y652) => acc or y652 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_653 = ""
    val w654 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_653 }) }
    w654
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w655 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w655
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w656 = if (timerDef("hold").startsOnce) {
      val w657 = ec_pauseTimer(w0, c, iid, "hold")
      w657
    } else {
      val w658 = if (false) {
      val w659 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w660 = { ...w659, inc: w659.inc.set(iid, { ...w659.inc.get(iid), timers: w659.inc.get(iid).timers.set("hold", { ...w659.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w661 = { ...w660, inc: w660.inc.set(iid, { ...w660.inc.get(iid), timers: w660.inc.get(iid).timers.set("hold", { ...w660.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w662 = { ...w661, inc: w661.inc.set(iid, { ...w661.inc.get(iid), timers: w661.inc.get(iid).timers.set("hold", { ...w661.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w662
    } else {
      val w663 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_664 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w665 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_664) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w666 = { ...w665, inc: w665.inc.set(iid, { ...w665.inc.get(iid), timers: w665.inc.get(iid).timers.set("hold", { ...w665.inc.get(iid).timers.get("hold"), paused: keep_664 }) }) }
      val w667 = { ...w666, inc: w666.inc.set(iid, { ...w666.inc.get(iid), timers: w666.inc.get(iid).timers.set("hold", { ...w666.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w668 = { ...w667, inc: w667.inc.set(iid, { ...w667.inc.get(iid), timers: w667.inc.get(iid).timers.set("hold", { ...w667.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w668
    }
      w663
    }
      w658
    }
    w656
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w669 = if (not(timerDef("resolution").pausable)) {
      val w670 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w671 = { ...w670, inc: w670.inc.set(iid, { ...w670.inc.get(iid), timers: w670.inc.get(iid).timers.set("resolution", { ...w670.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w671
    } else {
      val w672 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w673 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w674 = { ...w673, inc: w673.inc.set(iid, { ...w673.inc.get(iid), timers: w673.inc.get(iid).timers.set("resolution", { ...w673.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w675 = { ...w674, inc: w674.inc.set(iid, { ...w674.inc.get(iid), timers: w674.inc.get(iid).timers.set("resolution", { ...w674.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w675
    } else w0
      w672
    }
    w669
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w676 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w677 = if (timerDef("reaction").startsOnce) {
      val w678 = ec_resumeTimer(w0, c, iid, "reaction")
      w678
    } else {
      val w679 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w680 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w681 = { ...w680, inc: w680.inc.set(iid, { ...w680.inc.get(iid), timers: w680.inc.get(iid).timers.set("reaction", { ...w680.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w682 = { ...w681, inc: w681.inc.set(iid, { ...w681.inc.get(iid), timers: w681.inc.get(iid).timers.set("reaction", { ...w681.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w682
    } else {
      val sec_683 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w684 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_683 < 0)) 0 else (c.now + (sec_683 * 1000))) }) }) }
      val w685 = { ...w684, inc: w684.inc.set(iid, { ...w684.inc.get(iid), timers: w684.inc.get(iid).timers.set("reaction", { ...w684.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w686 = { ...w685, inc: w685.inc.set(iid, { ...w685.inc.get(iid), timers: w685.inc.get(iid).timers.set("reaction", { ...w685.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w687 = { ...w686, inc: w686.inc.set(iid, { ...w686.inc.get(iid), timers: w686.inc.get(iid).timers.set("reaction", { ...w686.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w687
    }
      w679
    }
      w677
    }
    w676
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
    val reason_688 = "break"
    val w689 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_688 }) }
    w689
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w690 = if (not(timerDef("resolution").pausable)) {
      val w691 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w692 = { ...w691, inc: w691.inc.set(iid, { ...w691.inc.get(iid), timers: w691.inc.get(iid).timers.set("resolution", { ...w691.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w692
    } else {
      val w693 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w694 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w695 = { ...w694, inc: w694.inc.set(iid, { ...w694.inc.get(iid), timers: w694.inc.get(iid).timers.set("resolution", { ...w694.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w696 = { ...w695, inc: w695.inc.set(iid, { ...w695.inc.get(iid), timers: w695.inc.get(iid).timers.set("resolution", { ...w695.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w696
    } else w0
      w693
    }
    w690
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w697 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w698 = if (timerDef("hold").startsOnce) {
      val w699 = ec_resumeTimer(w0, c, iid, "hold")
      w699
    } else {
      val w700 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w701 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w702 = { ...w701, inc: w701.inc.set(iid, { ...w701.inc.get(iid), timers: w701.inc.get(iid).timers.set("hold", { ...w701.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w703 = { ...w702, inc: w702.inc.set(iid, { ...w702.inc.get(iid), timers: w702.inc.get(iid).timers.set("hold", { ...w702.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w703
    } else {
      val sec_704 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w705 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_704 < 0)) 0 else (c.now + (sec_704 * 1000))) }) }) }
      val w706 = { ...w705, inc: w705.inc.set(iid, { ...w705.inc.get(iid), timers: w705.inc.get(iid).timers.set("hold", { ...w705.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w707 = { ...w706, inc: w706.inc.set(iid, { ...w706.inc.get(iid), timers: w706.inc.get(iid).timers.set("hold", { ...w706.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w708 = { ...w707, inc: w707.inc.set(iid, { ...w707.inc.get(iid), timers: w707.inc.get(iid).timers.set("hold", { ...w707.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w708
    }
      w700
    }
      w698
    }
    w697
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
    val reason_709 = "no_link"
    val w710 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_709 }) }
    w710
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w711 = if (not(timerDef("resolution").pausable)) {
      val w712 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w713 = { ...w712, inc: w712.inc.set(iid, { ...w712.inc.get(iid), timers: w712.inc.get(iid).timers.set("resolution", { ...w712.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w713
    } else {
      val w714 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w715 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w716 = { ...w715, inc: w715.inc.set(iid, { ...w715.inc.get(iid), timers: w715.inc.get(iid).timers.set("resolution", { ...w715.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w717 = { ...w716, inc: w716.inc.set(iid, { ...w716.inc.get(iid), timers: w716.inc.get(iid).timers.set("resolution", { ...w716.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w717
    } else w0
      w714
    }
    w711
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w718 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w719 = if (timerDef("hold").startsOnce) {
      val w720 = ec_resumeTimer(w0, c, iid, "hold")
      w720
    } else {
      val w721 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w722 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w723 = { ...w722, inc: w722.inc.set(iid, { ...w722.inc.get(iid), timers: w722.inc.get(iid).timers.set("hold", { ...w722.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w724 = { ...w723, inc: w723.inc.set(iid, { ...w723.inc.get(iid), timers: w723.inc.get(iid).timers.set("hold", { ...w723.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w724
    } else {
      val sec_725 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w726 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_725 < 0)) 0 else (c.now + (sec_725 * 1000))) }) }) }
      val w727 = { ...w726, inc: w726.inc.set(iid, { ...w726.inc.get(iid), timers: w726.inc.get(iid).timers.set("hold", { ...w726.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w728 = { ...w727, inc: w727.inc.set(iid, { ...w727.inc.get(iid), timers: w727.inc.get(iid).timers.set("hold", { ...w727.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w729 = { ...w728, inc: w728.inc.set(iid, { ...w728.inc.get(iid), timers: w728.inc.get(iid).timers.set("hold", { ...w728.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w729
    }
      w721
    }
      w719
    }
    w718
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_730 = settings.alerts.target
    val w731 = if (((whom_730 != "") and (whom_730 != c.actor))) w0 else w0
    w731
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
    ["break", "no_link"].foldl(false, (acc, y732) => acc or y732 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_733 = ""
    val w734 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_733 }) }
    w734
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w735 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w735
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w736 = if (timerDef("hold").startsOnce) {
      val w737 = ec_pauseTimer(w0, c, iid, "hold")
      w737
    } else {
      val w738 = if (false) {
      val w739 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w740 = { ...w739, inc: w739.inc.set(iid, { ...w739.inc.get(iid), timers: w739.inc.get(iid).timers.set("hold", { ...w739.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w741 = { ...w740, inc: w740.inc.set(iid, { ...w740.inc.get(iid), timers: w740.inc.get(iid).timers.set("hold", { ...w740.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w742 = { ...w741, inc: w741.inc.set(iid, { ...w741.inc.get(iid), timers: w741.inc.get(iid).timers.set("hold", { ...w741.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w742
    } else {
      val w743 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_744 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w745 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_744) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w746 = { ...w745, inc: w745.inc.set(iid, { ...w745.inc.get(iid), timers: w745.inc.get(iid).timers.set("hold", { ...w745.inc.get(iid).timers.get("hold"), paused: keep_744 }) }) }
      val w747 = { ...w746, inc: w746.inc.set(iid, { ...w746.inc.get(iid), timers: w746.inc.get(iid).timers.set("hold", { ...w746.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w748 = { ...w747, inc: w747.inc.set(iid, { ...w747.inc.get(iid), timers: w747.inc.get(iid).timers.set("hold", { ...w747.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w748
    }
      w743
    }
      w738
    }
    w736
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w749 = if (not(timerDef("resolution").pausable)) {
      val w750 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w751 = { ...w750, inc: w750.inc.set(iid, { ...w750.inc.get(iid), timers: w750.inc.get(iid).timers.set("resolution", { ...w750.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w751
    } else {
      val w752 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w753 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w754 = { ...w753, inc: w753.inc.set(iid, { ...w753.inc.get(iid), timers: w753.inc.get(iid).timers.set("resolution", { ...w753.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w755 = { ...w754, inc: w754.inc.set(iid, { ...w754.inc.get(iid), timers: w754.inc.get(iid).timers.set("resolution", { ...w754.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w755
    } else w0
      w752
    }
    w749
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w756 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w757 = if (timerDef("reaction").startsOnce) {
      val w758 = ec_resumeTimer(w0, c, iid, "reaction")
      w758
    } else {
      val w759 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w760 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w761 = { ...w760, inc: w760.inc.set(iid, { ...w760.inc.get(iid), timers: w760.inc.get(iid).timers.set("reaction", { ...w760.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w762 = { ...w761, inc: w761.inc.set(iid, { ...w761.inc.get(iid), timers: w761.inc.get(iid).timers.set("reaction", { ...w761.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w762
    } else {
      val sec_763 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w764 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_763 < 0)) 0 else (c.now + (sec_763 * 1000))) }) }) }
      val w765 = { ...w764, inc: w764.inc.set(iid, { ...w764.inc.get(iid), timers: w764.inc.get(iid).timers.set("reaction", { ...w764.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w766 = { ...w765, inc: w765.inc.set(iid, { ...w765.inc.get(iid), timers: w765.inc.get(iid).timers.set("reaction", { ...w765.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w767 = { ...w766, inc: w766.inc.set(iid, { ...w766.inc.get(iid), timers: w766.inc.get(iid).timers.set("reaction", { ...w766.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w767
    }
      w759
    }
      w757
    }
    w756
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
    { val t_768 = world.inc.get(iid).timers.get("hold")  (((t_768.due != 0) and (t_768.due <= c.now)) and (t_768.fired != t_768.due)) },
    ["no_link"].foldl(false, (acc, y769) => acc or y769 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_770 = ""
    val w771 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_770 }) }
    w771
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w772 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w772
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w773 = if (timerDef("hold").startsOnce) {
      val w774 = ec_pauseTimer(w0, c, iid, "hold")
      w774
    } else {
      val w775 = if (false) {
      val w776 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w777 = { ...w776, inc: w776.inc.set(iid, { ...w776.inc.get(iid), timers: w776.inc.get(iid).timers.set("hold", { ...w776.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w778 = { ...w777, inc: w777.inc.set(iid, { ...w777.inc.get(iid), timers: w777.inc.get(iid).timers.set("hold", { ...w777.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w779 = { ...w778, inc: w778.inc.set(iid, { ...w778.inc.get(iid), timers: w778.inc.get(iid).timers.set("hold", { ...w778.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w779
    } else {
      val w780 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_781 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w782 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_781) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w783 = { ...w782, inc: w782.inc.set(iid, { ...w782.inc.get(iid), timers: w782.inc.get(iid).timers.set("hold", { ...w782.inc.get(iid).timers.get("hold"), paused: keep_781 }) }) }
      val w784 = { ...w783, inc: w783.inc.set(iid, { ...w783.inc.get(iid), timers: w783.inc.get(iid).timers.set("hold", { ...w783.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w785 = { ...w784, inc: w784.inc.set(iid, { ...w784.inc.get(iid), timers: w784.inc.get(iid).timers.set("hold", { ...w784.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w785
    }
      w780
    }
      w775
    }
    w773
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w786 = if (not(timerDef("resolution").pausable)) {
      val w787 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w788 = { ...w787, inc: w787.inc.set(iid, { ...w787.inc.get(iid), timers: w787.inc.get(iid).timers.set("resolution", { ...w787.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w788
    } else {
      val w789 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w790 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w791 = { ...w790, inc: w790.inc.set(iid, { ...w790.inc.get(iid), timers: w790.inc.get(iid).timers.set("resolution", { ...w790.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w792 = { ...w791, inc: w791.inc.set(iid, { ...w791.inc.get(iid), timers: w791.inc.get(iid).timers.set("resolution", { ...w791.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w792
    } else w0
      w789
    }
    w786
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w793 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w794 = if (timerDef("reaction").startsOnce) {
      val w795 = ec_resumeTimer(w0, c, iid, "reaction")
      w795
    } else {
      val w796 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w797 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w798 = { ...w797, inc: w797.inc.set(iid, { ...w797.inc.get(iid), timers: w797.inc.get(iid).timers.set("reaction", { ...w797.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w799 = { ...w798, inc: w798.inc.set(iid, { ...w798.inc.get(iid), timers: w798.inc.get(iid).timers.set("reaction", { ...w798.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w799
    } else {
      val sec_800 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w801 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_800 < 0)) 0 else (c.now + (sec_800 * 1000))) }) }) }
      val w802 = { ...w801, inc: w801.inc.set(iid, { ...w801.inc.get(iid), timers: w801.inc.get(iid).timers.set("reaction", { ...w801.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w803 = { ...w802, inc: w802.inc.set(iid, { ...w802.inc.get(iid), timers: w802.inc.get(iid).timers.set("reaction", { ...w802.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w804 = { ...w803, inc: w803.inc.set(iid, { ...w803.inc.get(iid), timers: w803.inc.get(iid).timers.set("reaction", { ...w803.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w804
    }
      w796
    }
      w794
    }
    w793
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
    val group_805 = dutyGroupOf(w0.inc.get(iid).owner)
    val w806 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_805 }) }
    w806
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_807 = ""
    val w808 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_807 }) }
    w808
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_809 = addressee(w0.inc.get(iid))
    val w810 = if (((whom_809 != "") and (whom_809 != c.actor))) w0 else w0
    w810
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
    val who_811 = ""
    val w812 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_811 }) }
    w812
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
    val who_813 = ""
    val w814 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_813 }) }
    w814
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w815 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w815
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w816 = if (timerDef("hold").startsOnce) {
      val w817 = ec_pauseTimer(w0, c, iid, "hold")
      w817
    } else {
      val w818 = if (false) {
      val w819 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w820 = { ...w819, inc: w819.inc.set(iid, { ...w819.inc.get(iid), timers: w819.inc.get(iid).timers.set("hold", { ...w819.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w821 = { ...w820, inc: w820.inc.set(iid, { ...w820.inc.get(iid), timers: w820.inc.get(iid).timers.set("hold", { ...w820.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w822 = { ...w821, inc: w821.inc.set(iid, { ...w821.inc.get(iid), timers: w821.inc.get(iid).timers.set("hold", { ...w821.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w822
    } else {
      val w823 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_824 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w825 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_824) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w826 = { ...w825, inc: w825.inc.set(iid, { ...w825.inc.get(iid), timers: w825.inc.get(iid).timers.set("hold", { ...w825.inc.get(iid).timers.get("hold"), paused: keep_824 }) }) }
      val w827 = { ...w826, inc: w826.inc.set(iid, { ...w826.inc.get(iid), timers: w826.inc.get(iid).timers.set("hold", { ...w826.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w828 = { ...w827, inc: w827.inc.set(iid, { ...w827.inc.get(iid), timers: w827.inc.get(iid).timers.set("hold", { ...w827.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w828
    }
      w823
    }
      w818
    }
    w816
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w829 = if (not(timerDef("resolution").pausable)) {
      val w830 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w831 = { ...w830, inc: w830.inc.set(iid, { ...w830.inc.get(iid), timers: w830.inc.get(iid).timers.set("resolution", { ...w830.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w831
    } else {
      val w832 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w833 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w834 = { ...w833, inc: w833.inc.set(iid, { ...w833.inc.get(iid), timers: w833.inc.get(iid).timers.set("resolution", { ...w833.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w835 = { ...w834, inc: w834.inc.set(iid, { ...w834.inc.get(iid), timers: w834.inc.get(iid).timers.set("resolution", { ...w834.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w835
    } else w0
      w832
    }
    w829
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w836 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w837 = if (timerDef("reaction").startsOnce) {
      val w838 = ec_resumeTimer(w0, c, iid, "reaction")
      w838
    } else {
      val w839 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w840 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w841 = { ...w840, inc: w840.inc.set(iid, { ...w840.inc.get(iid), timers: w840.inc.get(iid).timers.set("reaction", { ...w840.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w842 = { ...w841, inc: w841.inc.set(iid, { ...w841.inc.get(iid), timers: w841.inc.get(iid).timers.set("reaction", { ...w841.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w842
    } else {
      val sec_843 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w844 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_843 < 0)) 0 else (c.now + (sec_843 * 1000))) }) }) }
      val w845 = { ...w844, inc: w844.inc.set(iid, { ...w844.inc.get(iid), timers: w844.inc.get(iid).timers.set("reaction", { ...w844.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w846 = { ...w845, inc: w845.inc.set(iid, { ...w845.inc.get(iid), timers: w845.inc.get(iid).timers.set("reaction", { ...w845.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w847 = { ...w846, inc: w846.inc.set(iid, { ...w846.inc.get(iid), timers: w846.inc.get(iid).timers.set("reaction", { ...w846.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w847
    }
      w839
    }
      w837
    }
    w836
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
    val who_848 = ""
    val w849 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_848 }) }
    w849
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_850 = ""
    val w851 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_850 }) }
    w851
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w852 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w852
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w853 = if (timerDef("hold").startsOnce) {
      val w854 = ec_pauseTimer(w0, c, iid, "hold")
      w854
    } else {
      val w855 = if (false) {
      val w856 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w857 = { ...w856, inc: w856.inc.set(iid, { ...w856.inc.get(iid), timers: w856.inc.get(iid).timers.set("hold", { ...w856.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w858 = { ...w857, inc: w857.inc.set(iid, { ...w857.inc.get(iid), timers: w857.inc.get(iid).timers.set("hold", { ...w857.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w859 = { ...w858, inc: w858.inc.set(iid, { ...w858.inc.get(iid), timers: w858.inc.get(iid).timers.set("hold", { ...w858.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w859
    } else {
      val w860 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_861 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w862 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_861) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w863 = { ...w862, inc: w862.inc.set(iid, { ...w862.inc.get(iid), timers: w862.inc.get(iid).timers.set("hold", { ...w862.inc.get(iid).timers.get("hold"), paused: keep_861 }) }) }
      val w864 = { ...w863, inc: w863.inc.set(iid, { ...w863.inc.get(iid), timers: w863.inc.get(iid).timers.set("hold", { ...w863.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w865 = { ...w864, inc: w864.inc.set(iid, { ...w864.inc.get(iid), timers: w864.inc.get(iid).timers.set("hold", { ...w864.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w865
    }
      w860
    }
      w855
    }
    w853
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w866 = if (not(timerDef("resolution").pausable)) {
      val w867 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w868 = { ...w867, inc: w867.inc.set(iid, { ...w867.inc.get(iid), timers: w867.inc.get(iid).timers.set("resolution", { ...w867.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w868
    } else {
      val w869 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w870 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w871 = { ...w870, inc: w870.inc.set(iid, { ...w870.inc.get(iid), timers: w870.inc.get(iid).timers.set("resolution", { ...w870.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w872 = { ...w871, inc: w871.inc.set(iid, { ...w871.inc.get(iid), timers: w871.inc.get(iid).timers.set("resolution", { ...w871.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w872
    } else w0
      w869
    }
    w866
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w873 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w874 = if (timerDef("reaction").startsOnce) {
      val w875 = ec_resumeTimer(w0, c, iid, "reaction")
      w875
    } else {
      val w876 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w877 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w878 = { ...w877, inc: w877.inc.set(iid, { ...w877.inc.get(iid), timers: w877.inc.get(iid).timers.set("reaction", { ...w877.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w879 = { ...w878, inc: w878.inc.set(iid, { ...w878.inc.get(iid), timers: w878.inc.get(iid).timers.set("reaction", { ...w878.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w879
    } else {
      val sec_880 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w881 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_880 < 0)) 0 else (c.now + (sec_880 * 1000))) }) }) }
      val w882 = { ...w881, inc: w881.inc.set(iid, { ...w881.inc.get(iid), timers: w881.inc.get(iid).timers.set("reaction", { ...w881.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w883 = { ...w882, inc: w882.inc.set(iid, { ...w882.inc.get(iid), timers: w882.inc.get(iid).timers.set("reaction", { ...w882.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w884 = { ...w883, inc: w883.inc.set(iid, { ...w883.inc.get(iid), timers: w883.inc.get(iid).timers.set("reaction", { ...w883.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w884
    }
      w876
    }
      w874
    }
    w873
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_885 = settings.alerts.target
    val w886 = if (((whom_885 != "") and (whom_885 != c.actor))) w0 else w0
    w886
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
    val who_887 = ""
    val w888 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_887 }) }
    w888
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_889 = ""
    val w890 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_889 }) }
    w890
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w891 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w892 = if (timerDef("reaction").startsOnce) {
      val w893 = ec_resumeTimer(w0, c, iid, "reaction")
      w893
    } else {
      val w894 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w895 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w896 = { ...w895, inc: w895.inc.set(iid, { ...w895.inc.get(iid), timers: w895.inc.get(iid).timers.set("reaction", { ...w895.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w897 = { ...w896, inc: w896.inc.set(iid, { ...w896.inc.get(iid), timers: w896.inc.get(iid).timers.set("reaction", { ...w896.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w897
    } else {
      val sec_898 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
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

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_903 = settings.alerts.target
    val w904 = if (((whom_903 != "") and (whom_903 != c.actor))) w0 else w0
    w904
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
    not(settings.session.states.foldl(false, (acc, s_905) => acc or ((s_905.id == agentState(c.me)) and s_905.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_906 = incidentById(incs(world), c.form.primaryId)  ((((ps_906.length() > 0) and (ps_906[0].id != world.inc.get(iid).id)) and (ps_906[0].linkedTo == "")) and ((ps_906[0].state == "new") or ((ps_906[0].state == "in_progress") and (ps_906[0].owner == c.me)))) },
    { val ps_907 = incidentById(incs(world), c.form.primaryId)  ((ps_907.length() > 0) and (ps_907[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w908 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w908
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_909 = incidentById(incs(w0), c.form.primaryId)
    val w910 = if ((ps_909.length() > 0)) {
      val w911 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_918 => not(isDone(e_918))).foldl([], (acc, x914) => acc.append(x914.id)).foldl(w0, (wf912, cId913) => {
      val w915 = { ...wf912, inc: wf912.inc.set(cId913, { ...wf912.inc.get(cId913), leftGroup: { primaryId: wf912.inc.get(cId913).linkedTo, linkedAt: wf912.inc.get(cId913).linkedAt, at: c.now } }) }
      val w916 = { ...w915, inc: w915.inc.set(cId913, { ...w915.inc.get(cId913), linkedTo: ps_909[0].id }) }
      val w917 = { ...w916, inc: w916.inc.set(cId913, { ...w916.inc.get(cId913), linkedAt: c.now }) }
      w917
    })
      w911
    } else w0
    w910
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_919 = c.form.primaryId
    val w920 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_919 }) }
    val w921 = { ...w920, inc: w920.inc.set(iid, { ...w920.inc.get(iid), linkedAt: c.now }) }
    w921
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_922 = ""
    val w923 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_922 }) }
    w923
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_924 = ""
    val w925 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_924 }) }
    w925
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w926 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w926
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w927 = if (timerDef("reaction").startsOnce) {
      val w928 = ec_pauseTimer(w0, c, iid, "reaction")
      w928
    } else {
      val w929 = if (false) {
      val w930 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w931 = { ...w930, inc: w930.inc.set(iid, { ...w930.inc.get(iid), timers: w930.inc.get(iid).timers.set("reaction", { ...w930.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w932 = { ...w931, inc: w931.inc.set(iid, { ...w931.inc.get(iid), timers: w931.inc.get(iid).timers.set("reaction", { ...w931.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w933 = { ...w932, inc: w932.inc.set(iid, { ...w932.inc.get(iid), timers: w932.inc.get(iid).timers.set("reaction", { ...w932.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w933
    } else {
      val w934 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_935 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w936 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_935) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w937 = { ...w936, inc: w936.inc.set(iid, { ...w936.inc.get(iid), timers: w936.inc.get(iid).timers.set("reaction", { ...w936.inc.get(iid).timers.get("reaction"), paused: keep_935 }) }) }
      val w938 = { ...w937, inc: w937.inc.set(iid, { ...w937.inc.get(iid), timers: w937.inc.get(iid).timers.set("reaction", { ...w937.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w939 = { ...w938, inc: w938.inc.set(iid, { ...w938.inc.get(iid), timers: w938.inc.get(iid).timers.set("reaction", { ...w938.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w939
    }
      w934
    }
      w929
    }
    w927
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w940 = if (not(timerDef("resolution").pausable)) {
      val w941 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w942 = { ...w941, inc: w941.inc.set(iid, { ...w941.inc.get(iid), timers: w941.inc.get(iid).timers.set("resolution", { ...w941.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w942
    } else {
      val w943 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w944 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w945 = { ...w944, inc: w944.inc.set(iid, { ...w944.inc.get(iid), timers: w944.inc.get(iid).timers.set("resolution", { ...w944.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w946 = { ...w945, inc: w945.inc.set(iid, { ...w945.inc.get(iid), timers: w945.inc.get(iid).timers.set("resolution", { ...w945.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w946
    } else w0
      w943
    }
    w940
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_947 = incidentById(incs(w0), c.form.primaryId)
    val w948 = if (((((ps_947.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_947[0], "resolution", c.now)))) {
      val t_949 = ps_947[0].timers.get("resolution")
      val left_950 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_951 = (if ((t_949.due != 0)) (t_949.due - c.now) else (if (t_949.paused) t_949.left else (timerSec(ps_947[0], "resolution", "") * 1000)))
      val w952 = if ((left_950 < was_951)) {
      val w953 = ps_947.foldl([], (acc, x956) => acc.append(x956.id)).foldl(w0, (wf954, pId955) => {
      val w957 = if ((t_949.due != 0)) {
      val w958 = { ...wf954, inc: wf954.inc.set(pId955, { ...wf954.inc.get(pId955), timers: wf954.inc.get(pId955).timers.set("resolution", { ...wf954.inc.get(pId955).timers.get("resolution"), due: (c.now + left_950) }) }) }
      w958
    } else {
      val w959 = { ...wf954, inc: wf954.inc.set(pId955, { ...wf954.inc.get(pId955), timers: wf954.inc.get(pId955).timers.set("resolution", { ...wf954.inc.get(pId955).timers.get("resolution"), left: left_950 }) }) }
      val w960 = { ...w959, inc: w959.inc.set(pId955, { ...w959.inc.get(pId955), timers: w959.inc.get(pId955).timers.set("resolution", { ...w959.inc.get(pId955).timers.get("resolution"), paused: true }) }) }
      w960
    }
      w957
    })
      w953
    } else w0
      w952
    } else w0
    w948
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w961 = if (timerDef("hold").startsOnce) {
      val w962 = ec_pauseTimer(w0, c, iid, "hold")
      w962
    } else {
      val w963 = if (false) {
      val w964 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w965 = { ...w964, inc: w964.inc.set(iid, { ...w964.inc.get(iid), timers: w964.inc.get(iid).timers.set("hold", { ...w964.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w966 = { ...w965, inc: w965.inc.set(iid, { ...w965.inc.get(iid), timers: w965.inc.get(iid).timers.set("hold", { ...w965.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w967 = { ...w966, inc: w966.inc.set(iid, { ...w966.inc.get(iid), timers: w966.inc.get(iid).timers.set("hold", { ...w966.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w967
    } else {
      val w968 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_969 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w970 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_969) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w971 = { ...w970, inc: w970.inc.set(iid, { ...w970.inc.get(iid), timers: w970.inc.get(iid).timers.set("hold", { ...w970.inc.get(iid).timers.get("hold"), paused: keep_969 }) }) }
      val w972 = { ...w971, inc: w971.inc.set(iid, { ...w971.inc.get(iid), timers: w971.inc.get(iid).timers.set("hold", { ...w971.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w973 = { ...w972, inc: w972.inc.set(iid, { ...w972.inc.get(iid), timers: w972.inc.get(iid).timers.set("hold", { ...w972.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w973
    }
      w968
    }
      w963
    }
    w961
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
    not(settings.session.states.foldl(false, (acc, s_974) => acc or ((s_974.id == agentState(c.me)) and s_974.readOnly))),
    { val ps_975 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_975.length() > 0) and ((ownership(c.me, ps_975[0]) == "owner") or unowned(ps_975[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_976 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w977 = if (((ps_976.length() > 0) and (leftOf(ps_976[0], "resolution", c.now) >= 0))) {
      val w978 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w979 = { ...w978, inc: w978.inc.set(iid, { ...w978.inc.get(iid), timers: w978.inc.get(iid).timers.set("resolution", { ...w978.inc.get(iid).timers.get("resolution"), left: leftOf(ps_976[0], "resolution", c.now) }) }) }
      val w980 = { ...w979, inc: w979.inc.set(iid, { ...w979.inc.get(iid), timers: w979.inc.get(iid).timers.set("resolution", { ...w979.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w981 = if ((leftOf(ps_976[0], "resolution", c.now) == 0)) {
      val w982 = { ...w980, inc: w980.inc.set(iid, { ...w980.inc.get(iid), timers: w980.inc.get(iid).timers.set("resolution", { ...w980.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_976[0], "resolution", c.now)) ps_976[0].timers.get("resolution").fired else ps_976[0].timers.get("resolution").due) }) }) }
      w982
    } else w980
      w981
    } else w0
    w977
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w983 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_984 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w985 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w986 = { ...w985, inc: w985.inc.set(iid, { ...w985.inc.get(iid), linkedTo: "" }) }
      val w987 = { ...w986, inc: w986.inc.set(iid, { ...w986.inc.get(iid), linkedAt: 0 }) }
      val w988 = if (((ps_984.length() > 0) and ("" != ""))) w987 else w987
      val w989 = if (("" != "")) {
      val w990 = ps_984.foldl([], (acc, x993) => acc.append(x993.id)).foldl(w988, (wf991, pId992) => wf991)
      w990
    } else w988
      w989
    } else {
      val w994 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w995 = { ...w994, inc: w994.inc.set(iid, { ...w994.inc.get(iid), linkedAt: 0 }) }
      w995
    }
    w983
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w996 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w997 = if (timerDef("reaction").startsOnce) {
      val w998 = ec_resumeTimer(w0, c, iid, "reaction")
      w998
    } else {
      val w999 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1000 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1001 = { ...w1000, inc: w1000.inc.set(iid, { ...w1000.inc.get(iid), timers: w1000.inc.get(iid).timers.set("reaction", { ...w1000.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1002 = { ...w1001, inc: w1001.inc.set(iid, { ...w1001.inc.get(iid), timers: w1001.inc.get(iid).timers.set("reaction", { ...w1001.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1002
    } else {
      val sec_1003 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w1004 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1003 < 0)) 0 else (c.now + (sec_1003 * 1000))) }) }) }
      val w1005 = { ...w1004, inc: w1004.inc.set(iid, { ...w1004.inc.get(iid), timers: w1004.inc.get(iid).timers.set("reaction", { ...w1004.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1006 = { ...w1005, inc: w1005.inc.set(iid, { ...w1005.inc.get(iid), timers: w1005.inc.get(iid).timers.set("reaction", { ...w1005.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1007 = { ...w1006, inc: w1006.inc.set(iid, { ...w1006.inc.get(iid), timers: w1006.inc.get(iid).timers.set("reaction", { ...w1006.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1007
    }
      w999
    }
      w997
    }
    w996
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
    { val ps_1008 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1008.length() > 0) and isDone(ps_1008[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1009 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1010 = if ((ps_1009.length() > 0)) {
      val w1011 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_1009[0].closeResultId }) }
      val w1012 = { ...w1011, inc: w1011.inc.set(iid, { ...w1011.inc.get(iid), closeCauseId: ps_1009[0].closeCauseId }) }
      val w1013 = { ...w1012, inc: w1012.inc.set(iid, { ...w1012.inc.get(iid), closeCauseLabel: ps_1009[0].closeCauseLabel }) }
      val w1014 = { ...w1013, inc: w1013.inc.set(iid, { ...w1013.inc.get(iid), result: ps_1009[0].result }) }
      val w1015 = { ...w1014, inc: w1014.inc.set(iid, { ...w1014.inc.get(iid), closedBy: ps_1009[0].closedBy }) }
      val w1016 = { ...w1015, inc: w1015.inc.set(iid, { ...w1015.inc.get(iid), owner: ps_1009[0].closedBy }) }
      w1016
    } else w0
    w1010
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w1017 = if (not(timerDef("resolution").pausable)) {
      val w1018 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1019 = { ...w1018, inc: w1018.inc.set(iid, { ...w1018.inc.get(iid), timers: w1018.inc.get(iid).timers.set("resolution", { ...w1018.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w1019
    } else {
      val w1020 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w1021 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w1022 = { ...w1021, inc: w1021.inc.set(iid, { ...w1021.inc.get(iid), timers: w1021.inc.get(iid).timers.set("resolution", { ...w1021.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1023 = { ...w1022, inc: w1022.inc.set(iid, { ...w1022.inc.get(iid), timers: w1022.inc.get(iid).timers.set("resolution", { ...w1022.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w1023
    } else w0
      w1020
    }
    w1017
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_1024 = c.now
    val w1025 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_1024 }) }
    w1025
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {
    val w1026 = if (["false_alarm"].foldl(false, (acc, y1027) => acc or y1027 == w0.inc.get(iid).closeResultId)) {
      val w1028 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1032 => not(isDone(x_1032))).foldl([], (acc, x1031) => acc.append(x1031.id)).foldl(w0, (wf1029, sId1030) => wf1029)
      w1028
    } else w0
    w1026
  }

  def e_close_linked_5(w0: World, c: Ctx, iid: str): World = {
    val w1033 = if (["false_alarm"].foldl(false, (acc, y1034) => acc or y1034 == w0.inc.get(iid).closeResultId)) {
      val w1035 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1042 => not(isDone(x_1042))).foldl([], (acc, x1038) => acc.append(x1038.id)).foldl(w0, (wf1036, sId1037) => {
      val lead_1039 = (if ((wf1036.inc.get(sId1037).linkedTo != "")) { val ps_1040 = incidentById(incs(w0), wf1036.inc.get(sId1037).linkedTo)  (if (((ps_1040.length() > 0) and not(isDone(ps_1040[0])))) addressee(ps_1040[0]) else "") } else addressee(wf1036.inc.get(sId1037)))
      val w1041 = if (((lead_1039 != "") and (lead_1039 != wf1036.inc.get(iid).closedBy))) wf1036 else wf1036
      w1041
    })
      w1035
    } else w0
    w1033
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
    { val ps_1043 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_1044 = (if (((ps_1043.length() > 0) and not(isDone(ps_1043[0])))) addressee(ps_1043[0]) else "")  ((who_1044 != "") and (hasAccess(who_1044, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1045 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1046 = if (((ps_1045.length() > 0) and (leftOf(ps_1045[0], "resolution", c.now) >= 0))) {
      val w1047 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1048 = { ...w1047, inc: w1047.inc.set(iid, { ...w1047.inc.get(iid), timers: w1047.inc.get(iid).timers.set("resolution", { ...w1047.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1045[0], "resolution", c.now) }) }) }
      val w1049 = { ...w1048, inc: w1048.inc.set(iid, { ...w1048.inc.get(iid), timers: w1048.inc.get(iid).timers.set("resolution", { ...w1048.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1050 = if ((leftOf(ps_1045[0], "resolution", c.now) == 0)) {
      val w1051 = { ...w1049, inc: w1049.inc.set(iid, { ...w1049.inc.get(iid), timers: w1049.inc.get(iid).timers.set("resolution", { ...w1049.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1045[0], "resolution", c.now)) ps_1045[0].timers.get("resolution").fired else ps_1045[0].timers.get("resolution").due) }) }) }
      w1051
    } else w1049
      w1050
    } else w0
    w1046
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w1052 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1053 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1054 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1055 = { ...w1054, inc: w1054.inc.set(iid, { ...w1054.inc.get(iid), linkedTo: "" }) }
      val w1056 = { ...w1055, inc: w1055.inc.set(iid, { ...w1055.inc.get(iid), linkedAt: 0 }) }
      val w1057 = if (((ps_1053.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w1056 else w1056
      val w1058 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w1059 = ps_1053.foldl([], (acc, x1062) => acc.append(x1062.id)).foldl(w1057, (wf1060, pId1061) => wf1060)
      w1059
    } else w1057
      w1058
    } else {
      val w1063 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1064 = { ...w1063, inc: w1063.inc.set(iid, { ...w1063.inc.get(iid), linkedAt: 0 }) }
      w1064
    }
    w1052
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w1065 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1066 = if (timerDef("reaction").startsOnce) {
      val w1067 = ec_resumeTimer(w0, c, iid, "reaction")
      w1067
    } else {
      val w1068 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1069 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1070 = { ...w1069, inc: w1069.inc.set(iid, { ...w1069.inc.get(iid), timers: w1069.inc.get(iid).timers.set("reaction", { ...w1069.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1071 = { ...w1070, inc: w1070.inc.set(iid, { ...w1070.inc.get(iid), timers: w1070.inc.get(iid).timers.set("reaction", { ...w1070.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1071
    } else {
      val sec_1072 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w1073 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1072 < 0)) 0 else (c.now + (sec_1072 * 1000))) }) }) }
      val w1074 = { ...w1073, inc: w1073.inc.set(iid, { ...w1073.inc.get(iid), timers: w1073.inc.get(iid).timers.set("reaction", { ...w1073.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1075 = { ...w1074, inc: w1074.inc.set(iid, { ...w1074.inc.get(iid), timers: w1074.inc.get(iid).timers.set("reaction", { ...w1074.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1076 = { ...w1075, inc: w1075.inc.set(iid, { ...w1075.inc.get(iid), timers: w1075.inc.get(iid).timers.set("reaction", { ...w1075.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1076
    }
      w1068
    }
      w1066
    }
    w1065
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_1077 = settings.alerts.target
    val w1078 = if (((whom_1077 != "") and (whom_1077 != c.actor))) w0 else w0
    w1078
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
      settings.holdReasons.foldl(false, (acc, r_1079) => acc or ((r_1079.id == c.form.reasonId) and (r_1079.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_1080) => acc and (isDone(e_1080) or hasAccess(c.form.targetId, e_1080))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_1081) => acc or (i_1081.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_1082) => acc or ((i_1082.id == c.form.resultId) and stepsOk(i_1082, world.inc.get(iid)))),
    },
    c.form.causeId == "" or all {
      settings.closeResults.foldl(false, (acc, i_1083) => acc or ((((i_1083.id == c.form.resultId) and (i_1083.causeCatalog != "")) and settings.causeCatalogs.keys().contains(i_1083.causeCatalog)) and (settings.causeCatalogs.get(i_1083.causeCatalog).items.length() > 0))),
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
    ["in_progress"].foldl(false, (acc, y1084) => acc or y1084 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_1085) => acc or ((s_1085.id == agentState(c.me)) and s_1085.readOnly))),
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
  // выбор правила по событию — вне модели (его держат тесты API и порчи кода intake-*). Ключ — intake.uniqueKey машины
  // (intakeKeySame, генерируется; сейчас событие + сценарий, PROC-93): второго инцидента с тем же ключом нет, повтор события
  // и пересекающиеся правила его не дают
  def born(i: str, ev: str, sc: str, prio: int): Incident =
    { ...NO_INCIDENT, id: i, number: i, eventType: "fire", priority: prio, occurredAt: clock, scenario: sc, eventGuid: ev }
  def createOk(i: str, ev: str, sc: str): bool = all {
    incOf(i).state == "",
    not(INCIDENTS.exists(j => incOf(j).state != "" and intakeKeySame(incOf(j), born(i, ev, sc, 0)))),
  }
  action create(i: str, ev: str, sc: str, prio: int): bool = {
    val t = ofTrigger("event")[0]
    val w0 = { ...world,
      inc: world.inc.set(i, born(i, ev, sc, prio)),
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
