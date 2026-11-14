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

  type Maintenance = { mode: str, modes: List[str], markPriority: str, defaultTimeZone: str, startSkewSec: int }

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
    holdReasons: [{ id: "third_party", maxMinutes: [30], setBy: "operator", deadlineFromIdle: false }, { id: "patrol", maxMinutes: [45], setBy: "operator", deadlineFromIdle: false }, { id: "no_data", maxMinutes: [60], setBy: "operator", deadlineFromIdle: false }, { id: "break", maxMinutes: [30], setBy: "system", deadlineFromIdle: false }, { id: "no_link", maxMinutes: [], setBy: "system", deadlineFromIdle: true }],
    causeCatalogs: Map("hold" -> { items: [{ id: "third_party", labelKey: "workflow.catalog.hold.third_party", commentRequired: false }, { id: "patrol", labelKey: "workflow.catalog.hold.patrol", commentRequired: false }, { id: "no_data", labelKey: "workflow.catalog.hold.no_data", commentRequired: false }, { id: "break", labelKey: "workflow.catalog.hold.break", commentRequired: false }, { id: "no_link", labelKey: "workflow.catalog.hold.no_link", commentRequired: false }] }, "close_result" -> { items: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", commentRequired: false }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", commentRequired: false }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", commentRequired: true }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", commentRequired: true }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", commentRequired: true }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", commentRequired: true }] }, "mass_fault" -> { items: [{ id: "power", labelKey: "workflow.catalog.mass_fault.power", commentRequired: false }, { id: "link", labelKey: "workflow.catalog.mass_fault.link", commentRequired: false }, { id: "mass_fault", labelKey: "workflow.catalog.mass_fault.mass_fault", commentRequired: false }, { id: "known", labelKey: "workflow.catalog.mass_fault.known", commentRequired: false }] }, "false_alarm_cause" -> { items: [{ id: "animal", labelKey: "workflow.catalog.false_alarm_cause.animal", commentRequired: false }, { id: "weather", labelKey: "workflow.catalog.false_alarm_cause.weather", commentRequired: false }, { id: "equipment", labelKey: "workflow.catalog.false_alarm_cause.equipment", commentRequired: false }, { id: "staff", labelKey: "workflow.catalog.false_alarm_cause.staff", commentRequired: false }, { id: "setup", labelKey: "workflow.catalog.false_alarm_cause.setup", commentRequired: false }, { id: "other", labelKey: "workflow.catalog.false_alarm_cause.other", commentRequired: true }] }),
    maintenance: { mode: "suppress", modes: ["suppress", "mark"], markPriority: "lowest", defaultTimeZone: "UTC", startSkewSec: 300 },
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
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_179 = c.form.reasonId
    val w180 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_179 }) }
    w180
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w181 = if (not(timerDef("resolution").pausable)) {
      val w182 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w183 = { ...w182, inc: w182.inc.set(iid, { ...w182.inc.get(iid), timers: w182.inc.get(iid).timers.set("resolution", { ...w182.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w183
    } else {
      val w184 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w185 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w186 = { ...w185, inc: w185.inc.set(iid, { ...w185.inc.get(iid), timers: w185.inc.get(iid).timers.set("resolution", { ...w185.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w187 = { ...w186, inc: w186.inc.set(iid, { ...w186.inc.get(iid), timers: w186.inc.get(iid).timers.set("resolution", { ...w186.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w187
    } else w0
      w184
    }
    w181
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w188 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w189 = if (timerDef("hold").startsOnce) {
      val w190 = ec_resumeTimer(w0, c, iid, "hold")
      w190
    } else {
      val w191 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w192 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w193 = { ...w192, inc: w192.inc.set(iid, { ...w192.inc.get(iid), timers: w192.inc.get(iid).timers.set("hold", { ...w192.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w194 = { ...w193, inc: w193.inc.set(iid, { ...w193.inc.get(iid), timers: w193.inc.get(iid).timers.set("hold", { ...w193.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w194
    } else {
      val sec_195 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w196 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_195 < 0)) 0 else (c.now + (sec_195 * 1000))) }) }) }
      val w197 = { ...w196, inc: w196.inc.set(iid, { ...w196.inc.get(iid), timers: w196.inc.get(iid).timers.set("hold", { ...w196.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w198 = { ...w197, inc: w197.inc.set(iid, { ...w197.inc.get(iid), timers: w197.inc.get(iid).timers.set("hold", { ...w197.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w199 = { ...w198, inc: w198.inc.set(iid, { ...w198.inc.get(iid), timers: w198.inc.get(iid).timers.set("hold", { ...w198.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w199
    }
      w191
    }
      w189
    }
    w188
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
    not(settings.session.states.foldl(false, (acc, s_200) => acc or ((s_200.id == agentState(c.me)) and s_200.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w201 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w201
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w202 = if (timerDef("hold").startsOnce) {
      val w203 = ec_pauseTimer(w0, c, iid, "hold")
      w203
    } else {
      val w204 = if (false) {
      val w205 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w206 = { ...w205, inc: w205.inc.set(iid, { ...w205.inc.get(iid), timers: w205.inc.get(iid).timers.set("hold", { ...w205.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w207 = { ...w206, inc: w206.inc.set(iid, { ...w206.inc.get(iid), timers: w206.inc.get(iid).timers.set("hold", { ...w206.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w208 = { ...w207, inc: w207.inc.set(iid, { ...w207.inc.get(iid), timers: w207.inc.get(iid).timers.set("hold", { ...w207.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w208
    } else {
      val w209 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_210 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w211 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_210) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w212 = { ...w211, inc: w211.inc.set(iid, { ...w211.inc.get(iid), timers: w211.inc.get(iid).timers.set("hold", { ...w211.inc.get(iid).timers.get("hold"), paused: keep_210 }) }) }
      val w213 = { ...w212, inc: w212.inc.set(iid, { ...w212.inc.get(iid), timers: w212.inc.get(iid).timers.set("hold", { ...w212.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w214 = { ...w213, inc: w213.inc.set(iid, { ...w213.inc.get(iid), timers: w213.inc.get(iid).timers.set("hold", { ...w213.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w214
    }
      w209
    }
      w204
    }
    w202
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w215 = if (not(timerDef("resolution").pausable)) {
      val sec_216 = timerSec(w0.inc.get(iid), "resolution", "")
      val w217 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_216 < 0)) 0 else (c.now + (sec_216 * 1000))) }) }) }
      val w218 = { ...w217, inc: w217.inc.set(iid, { ...w217.inc.get(iid), timers: w217.inc.get(iid).timers.set("resolution", { ...w217.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w218
    } else {
      val w219 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_220 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w221 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_220 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_220)) }) }) }
      val w222 = { ...w221, inc: w221.inc.set(iid, { ...w221.inc.get(iid), timers: w221.inc.get(iid).timers.set("resolution", { ...w221.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w223 = { ...w222, inc: w222.inc.set(iid, { ...w222.inc.get(iid), timers: w222.inc.get(iid).timers.set("resolution", { ...w222.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w223
    } else w0
      w219
    }
    w215
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
    not(settings.session.states.foldl(false, (acc, s_224) => acc or ((s_224.id == agentState(c.me)) and s_224.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_225 = ""
    val w226 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_225 }) }
    w226
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w227 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w227
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w228 = if (not(timerDef("resolution").pausable)) {
      val w229 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w230 = { ...w229, inc: w229.inc.set(iid, { ...w229.inc.get(iid), timers: w229.inc.get(iid).timers.set("resolution", { ...w229.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w230
    } else {
      val w231 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w232 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w233 = { ...w232, inc: w232.inc.set(iid, { ...w232.inc.get(iid), timers: w232.inc.get(iid).timers.set("resolution", { ...w232.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w234 = { ...w233, inc: w233.inc.set(iid, { ...w233.inc.get(iid), timers: w233.inc.get(iid).timers.set("resolution", { ...w233.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w234
    } else w0
      w231
    }
    w228
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w235 = if (timerDef("hold").startsOnce) {
      val w236 = ec_pauseTimer(w0, c, iid, "hold")
      w236
    } else {
      val w237 = if (false) {
      val w238 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w239 = { ...w238, inc: w238.inc.set(iid, { ...w238.inc.get(iid), timers: w238.inc.get(iid).timers.set("hold", { ...w238.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w240 = { ...w239, inc: w239.inc.set(iid, { ...w239.inc.get(iid), timers: w239.inc.get(iid).timers.set("hold", { ...w239.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w241 = { ...w240, inc: w240.inc.set(iid, { ...w240.inc.get(iid), timers: w240.inc.get(iid).timers.set("hold", { ...w240.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w241
    } else {
      val w242 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_243 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w244 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_243) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w245 = { ...w244, inc: w244.inc.set(iid, { ...w244.inc.get(iid), timers: w244.inc.get(iid).timers.set("hold", { ...w244.inc.get(iid).timers.get("hold"), paused: keep_243 }) }) }
      val w246 = { ...w245, inc: w245.inc.set(iid, { ...w245.inc.get(iid), timers: w245.inc.get(iid).timers.set("hold", { ...w245.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w247 = { ...w246, inc: w246.inc.set(iid, { ...w246.inc.get(iid), timers: w246.inc.get(iid).timers.set("hold", { ...w246.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w247
    }
      w242
    }
      w237
    }
    w235
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w248 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w249 = if (timerDef("reaction").startsOnce) {
      val w250 = ec_resumeTimer(w0, c, iid, "reaction")
      w250
    } else {
      val w251 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w252 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w253 = { ...w252, inc: w252.inc.set(iid, { ...w252.inc.get(iid), timers: w252.inc.get(iid).timers.set("reaction", { ...w252.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("reaction", { ...w253.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w254
    } else {
      val sec_255 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w256 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_255 < 0)) 0 else (c.now + (sec_255 * 1000))) }) }) }
      val w257 = { ...w256, inc: w256.inc.set(iid, { ...w256.inc.get(iid), timers: w256.inc.get(iid).timers.set("reaction", { ...w256.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w258 = { ...w257, inc: w257.inc.set(iid, { ...w257.inc.get(iid), timers: w257.inc.get(iid).timers.set("reaction", { ...w257.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w259 = { ...w258, inc: w258.inc.set(iid, { ...w258.inc.get(iid), timers: w258.inc.get(iid).timers.set("reaction", { ...w258.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w259
    }
      w251
    }
      w249
    }
    w248
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
    not(settings.session.states.foldl(false, (acc, s_260) => acc or ((s_260.id == agentState(c.me)) and s_260.readOnly))),
    transferTargets.foldl(false, (acc, t_261) => acc or (offersTransferTo(c.me, t_261, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_262) => acc and (isDone(e_262) or hasAccess(t_261, e_262))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_263) => acc and (isDone(e_263) or hasAccess(c.form.targetId, e_263)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_264 = personOf(c.form.targetId)
    val w265 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_264 }) }
    w265
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_266 = groupOf(c.form.targetId)
    val w267 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_266 }) }
    w267
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w268 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w268
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w269 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w269
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
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

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
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

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w290 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w291 = if (timerDef("reaction").startsOnce) {
      val w292 = ec_resumeTimer(w0, c, iid, "reaction")
      w292
    } else {
      val w293 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w294 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w295 = { ...w294, inc: w294.inc.set(iid, { ...w294.inc.get(iid), timers: w294.inc.get(iid).timers.set("reaction", { ...w294.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("reaction", { ...w295.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w296
    } else {
      val sec_297 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
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

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_302 = c.before.owner
    val w303 = if (((whom_302 != "") and (whom_302 != c.actor))) w0 else w0
    w303
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_304 = addressee(w0.inc.get(iid))
    val w305 = if (((whom_304 != "") and (whom_304 != c.actor))) w0 else w0
    w305
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
    not(settings.session.states.foldl(false, (acc, s_306) => acc or ((s_306.id == agentState(c.me)) and s_306.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_307 = c.actor
    val w308 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_307 }) }
    w308
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_309 = ""
    val w310 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_309 }) }
    w310
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w311 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w311
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w312 = if (timerDef("reaction").startsOnce) {
      val w313 = ec_pauseTimer(w0, c, iid, "reaction")
      w313
    } else {
      val w314 = if (false) {
      val w315 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w316 = { ...w315, inc: w315.inc.set(iid, { ...w315.inc.get(iid), timers: w315.inc.get(iid).timers.set("reaction", { ...w315.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w317 = { ...w316, inc: w316.inc.set(iid, { ...w316.inc.get(iid), timers: w316.inc.get(iid).timers.set("reaction", { ...w316.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w318 = { ...w317, inc: w317.inc.set(iid, { ...w317.inc.get(iid), timers: w317.inc.get(iid).timers.set("reaction", { ...w317.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w318
    } else {
      val w319 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_320 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w321 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_320) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w322 = { ...w321, inc: w321.inc.set(iid, { ...w321.inc.get(iid), timers: w321.inc.get(iid).timers.set("reaction", { ...w321.inc.get(iid).timers.get("reaction"), paused: keep_320 }) }) }
      val w323 = { ...w322, inc: w322.inc.set(iid, { ...w322.inc.get(iid), timers: w322.inc.get(iid).timers.set("reaction", { ...w322.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w324 = { ...w323, inc: w323.inc.set(iid, { ...w323.inc.get(iid), timers: w323.inc.get(iid).timers.set("reaction", { ...w323.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w324
    }
      w319
    }
      w314
    }
    w312
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w325 = if (timerDef("hold").startsOnce) {
      val w326 = ec_pauseTimer(w0, c, iid, "hold")
      w326
    } else {
      val w327 = if (false) {
      val w328 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w329 = { ...w328, inc: w328.inc.set(iid, { ...w328.inc.get(iid), timers: w328.inc.get(iid).timers.set("hold", { ...w328.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w330 = { ...w329, inc: w329.inc.set(iid, { ...w329.inc.get(iid), timers: w329.inc.get(iid).timers.set("hold", { ...w329.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w331 = { ...w330, inc: w330.inc.set(iid, { ...w330.inc.get(iid), timers: w330.inc.get(iid).timers.set("hold", { ...w330.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w331
    } else {
      val w332 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_333 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w334 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_333) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w335 = { ...w334, inc: w334.inc.set(iid, { ...w334.inc.get(iid), timers: w334.inc.get(iid).timers.set("hold", { ...w334.inc.get(iid).timers.get("hold"), paused: keep_333 }) }) }
      val w336 = { ...w335, inc: w335.inc.set(iid, { ...w335.inc.get(iid), timers: w335.inc.get(iid).timers.set("hold", { ...w335.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w337 = { ...w336, inc: w336.inc.set(iid, { ...w336.inc.get(iid), timers: w336.inc.get(iid).timers.set("hold", { ...w336.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w337
    }
      w332
    }
      w327
    }
    w325
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w338 = if (not(timerDef("resolution").pausable)) {
      val sec_339 = timerSec(w0.inc.get(iid), "resolution", "")
      val w340 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_339 < 0)) 0 else (c.now + (sec_339 * 1000))) }) }) }
      val w341 = { ...w340, inc: w340.inc.set(iid, { ...w340.inc.get(iid), timers: w340.inc.get(iid).timers.set("resolution", { ...w340.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w341
    } else {
      val w342 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_343 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w344 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_343 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_343)) }) }) }
      val w345 = { ...w344, inc: w344.inc.set(iid, { ...w344.inc.get(iid), timers: w344.inc.get(iid).timers.set("resolution", { ...w344.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w346 = { ...w345, inc: w345.inc.set(iid, { ...w345.inc.get(iid), timers: w345.inc.get(iid).timers.set("resolution", { ...w345.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w346
    } else w0
      w342
    }
    w338
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
    val whom_347 = c.before.owner
    val w348 = if (((whom_347 != "") and (whom_347 != c.actor))) w0 else w0
    w348
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
    not(settings.session.states.foldl(false, (acc, s_349) => acc or ((s_349.id == agentState(c.me)) and s_349.readOnly))),
    { val os_350 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_350.foldl(false, (acc, o_351) => acc or ((o_351.id == c.form.resultId) and stepsOk(o_351, world.inc.get(iid)))) else os_350.foldl(false, (acc, o_352) => acc or stepsOk(o_352, world.inc.get(iid)))) },
    ((((c.form.resultId == "") or (c.form.causeId == "")) or not(settings.closeResults.foldl(false, (acc, i_353) => acc or ((i_353.id == c.form.resultId) and (i_353.causeCatalog != ""))))) or (causeOk(c.form.resultId, c.form.causeId) and (not(causeCommentRequired(c.form.resultId, c.form.causeId)) or (c.form.comment != "")))),
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_354 = c.actor
    val w355 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_354 }) }
    w355
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_356 = ""
    val w357 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_356 }) }
    w357
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_358 = c.actor
    val w359 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_358 }) }
    w359
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_360 = c.now
    val w361 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_360 }) }
    w361
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_362 = c.form.resultId
    val w363 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_362 }) }
    w363
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_364 = (if (causeOk(c.form.resultId, c.form.causeId)) c.form.causeId else "")
    val w365 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_364 }) }
    w365
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_366 = causeLabel(c.form.resultId, c.form.causeId)
    val w367 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_366 }) }
    w367
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val value_368 = (if ((c.form.resultId == "drill")) c.form.maintenanceWindowId else "")
    val w369 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_368 }) }
    w369
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val value_370 = c.form.comment
    val w371 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_370 }) }
    w371
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w372 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w372
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w373 = if (timerDef("reaction").startsOnce) {
      val w374 = ec_pauseTimer(w0, c, iid, "reaction")
      w374
    } else {
      val w375 = if (true) {
      val w376 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w377 = { ...w376, inc: w376.inc.set(iid, { ...w376.inc.get(iid), timers: w376.inc.get(iid).timers.set("reaction", { ...w376.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w378 = { ...w377, inc: w377.inc.set(iid, { ...w377.inc.get(iid), timers: w377.inc.get(iid).timers.set("reaction", { ...w377.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w379 = { ...w378, inc: w378.inc.set(iid, { ...w378.inc.get(iid), timers: w378.inc.get(iid).timers.set("reaction", { ...w378.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w379
    } else {
      val w380 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_381 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w382 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_381) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w383 = { ...w382, inc: w382.inc.set(iid, { ...w382.inc.get(iid), timers: w382.inc.get(iid).timers.set("reaction", { ...w382.inc.get(iid).timers.get("reaction"), paused: keep_381 }) }) }
      val w384 = { ...w383, inc: w383.inc.set(iid, { ...w383.inc.get(iid), timers: w383.inc.get(iid).timers.set("reaction", { ...w383.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w385 = { ...w384, inc: w384.inc.set(iid, { ...w384.inc.get(iid), timers: w384.inc.get(iid).timers.set("reaction", { ...w384.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w385
    }
      w380
    }
      w375
    }
    w373
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {
    val w386 = if (not(timerDef("resolution").pausable)) {
      val w387 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w388 = { ...w387, inc: w387.inc.set(iid, { ...w387.inc.get(iid), timers: w387.inc.get(iid).timers.set("resolution", { ...w387.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w388
    } else {
      val w389 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w390 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w391 = { ...w390, inc: w390.inc.set(iid, { ...w390.inc.get(iid), timers: w390.inc.get(iid).timers.set("resolution", { ...w390.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w392 = { ...w391, inc: w391.inc.set(iid, { ...w391.inc.get(iid), timers: w391.inc.get(iid).timers.set("resolution", { ...w391.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w392
    } else w0
      w389
    }
    w386
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {
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

  def e_close_13(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_14(w0: World, c: Ctx, iid: str): World = {
    val w406 = if (["false_alarm"].foldl(false, (acc, y407) => acc or y407 == w0.inc.get(iid).closeResultId)) {
      val w408 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_412 => not(isDone(x_412))).foldl([], (acc, x411) => acc.append(x411.id)).foldl(w0, (wf409, sId410) => wf409)
      w408
    } else w0
    w406
  }

  def e_close_15(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_16(w0: World, c: Ctx, iid: str): World = {
    val w413 = if (["false_alarm"].foldl(false, (acc, y414) => acc or y414 == w0.inc.get(iid).closeResultId)) {
      val w415 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_422 => not(isDone(x_422))).foldl([], (acc, x418) => acc.append(x418.id)).foldl(w0, (wf416, sId417) => {
      val lead_419 = (if ((wf416.inc.get(sId417).linkedTo != "")) { val ps_420 = incidentById(incs(w0), wf416.inc.get(sId417).linkedTo)  (if (((ps_420.length() > 0) and not(isDone(ps_420[0])))) addressee(ps_420[0]) else "") } else addressee(wf416.inc.get(sId417)))
      val w421 = if (((lead_419 != "") and (lead_419 != wf416.inc.get(iid).closedBy))) wf416 else wf416
      w421
    })
      w415
    } else w0
    w413
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
    not(settings.session.states.foldl(false, (acc, s_423) => acc or ((s_423.id == agentState(c.me)) and s_423.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_424 = c.actor
    val w425 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_424 }) }
    w425
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w426 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_427 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w428 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w429 = { ...w428, inc: w428.inc.set(iid, { ...w428.inc.get(iid), linkedTo: "" }) }
      val w430 = { ...w429, inc: w429.inc.set(iid, { ...w429.inc.get(iid), linkedAt: 0 }) }
      val w431 = if (((ps_427.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w430 else w430
      val w432 = if (("workflow.journal.linked_reopened" != "")) {
      val w433 = ps_427.foldl([], (acc, x436) => acc.append(x436.id)).foldl(w431, (wf434, pId435) => wf434)
      w433
    } else w431
      w432
    } else {
      val w437 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w438 = { ...w437, inc: w437.inc.set(iid, { ...w437.inc.get(iid), linkedAt: 0 }) }
      w438
    }
    w426
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_439 = ""
    val w440 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_439 }) }
    w440
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_441 = ""
    val w442 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_441 }) }
    w442
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_443 = ""
    val w444 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeMaintenanceWindowId: value_443 }) }
    w444
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_445 = ""
    val w446 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_445 }) }
    w446
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_447 = ""
    val w448 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_447 }) }
    w448
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val value_449 = 0
    val w450 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_449 }) }
    w450
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val value_451 = ""
    val w452 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_451 }) }
    w452
  }

  def e_reopen_10(w0: World, c: Ctx, iid: str): World = {
    val sec_453 = settings.limits.reopenResolutionSec
    val w454 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_453 > 0)) sec_453 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w455 = { ...w454, inc: w454.inc.set(iid, { ...w454.inc.get(iid), timers: w454.inc.get(iid).timers.set("resolution", { ...w454.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w456 = { ...w455, inc: w455.inc.set(iid, { ...w455.inc.get(iid), timers: w455.inc.get(iid).timers.set("resolution", { ...w455.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w456
  }

  def e_reopen_11(w0: World, c: Ctx, iid: str): World = {
    val w457 = if (timerDef("reaction").startsOnce) {
      val w458 = ec_pauseTimer(w0, c, iid, "reaction")
      w458
    } else {
      val w459 = if (true) {
      val w460 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w461 = { ...w460, inc: w460.inc.set(iid, { ...w460.inc.get(iid), timers: w460.inc.get(iid).timers.set("reaction", { ...w460.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w462 = { ...w461, inc: w461.inc.set(iid, { ...w461.inc.get(iid), timers: w461.inc.get(iid).timers.set("reaction", { ...w461.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w463 = { ...w462, inc: w462.inc.set(iid, { ...w462.inc.get(iid), timers: w462.inc.get(iid).timers.set("reaction", { ...w462.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w463
    } else {
      val w464 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_465 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w466 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_465) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w467 = { ...w466, inc: w466.inc.set(iid, { ...w466.inc.get(iid), timers: w466.inc.get(iid).timers.set("reaction", { ...w466.inc.get(iid).timers.get("reaction"), paused: keep_465 }) }) }
      val w468 = { ...w467, inc: w467.inc.set(iid, { ...w467.inc.get(iid), timers: w467.inc.get(iid).timers.set("reaction", { ...w467.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w469 = { ...w468, inc: w468.inc.set(iid, { ...w468.inc.get(iid), timers: w468.inc.get(iid).timers.set("reaction", { ...w468.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w469
    }
      w464
    }
      w459
    }
    w457
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
    not(settings.session.states.foldl(false, (acc, s_470) => acc or ((s_470.id == agentState(c.me)) and s_470.readOnly))),
    ((if (c.form.comment == "") 0 else 1) <= settings.limits.commentMaxLength),
    (c.form.files.length() <= settings.limits.commentMaxFiles),
    c.form.files.foldl(true, (acc, f_471) => acc and (f_471.size <= settings.limits.attachmentMaxBytes)),
    c.form.files.foldl(true, (acc, f_472) => acc and settings.limits.attachmentTypes.foldl(false, (acc, y473) => acc or y473 == f_472.mime)),
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
    not(settings.session.states.foldl(false, (acc, s_474) => acc or ((s_474.id == agentState(c.me)) and s_474.readOnly))),
    ((c.form.priority == "") or (priorityOf(c.form.priority) != world.inc.get(iid).priority)),
  }

  def e_change_priority_0(w0: World, c: Ctx, iid: str): World = {
    val value_475 = priorityOf(c.form.priority)
    val w476 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priority: value_475 }) }
    w476
  }

  def e_change_priority_1(w0: World, c: Ctx, iid: str): World = {
    val value_477 = true
    val w478 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priorityManual: value_477 }) }
    w478
  }

  def e_change_priority_2(w0: World, c: Ctx, iid: str): World = {
    val t_479 = w0.inc.get(iid).timers.get("reaction")
    val raw_480 = ((timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel") - timerSec(c.before, "reaction", "byEscalationLevel")) * 1000)
    val delta_481 = (if (((raw_480 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_482) => acc or (m_482.state == "linked")))) 0 else raw_480)
    val w483 = if ((((t_479.due != 0) and (t_479.due > c.now)) and (t_479.fired != t_479.due))) {
      val w484 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if (((t_479.due + delta_481) > c.now)) (t_479.due + delta_481) else c.now) }) }) }
      w484
    } else {
      val w485 = if ((((timerDef("reaction").pausable and (t_479.due == 0)) and t_479.paused) and (t_479.left > 0))) {
      val w486 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (((t_479.left + delta_481) > 0)) (t_479.left + delta_481) else 1) }) }) }
      w486
    } else w0
      w485
    }
    w483
  }

  def e_change_priority_3(w0: World, c: Ctx, iid: str): World = {
    val t_487 = w0.inc.get(iid).timers.get("resolution")
    val raw_488 = ((timerSec(w0.inc.get(iid), "resolution", "") - timerSec(c.before, "resolution", "")) * 1000)
    val delta_489 = (if (((raw_488 > 0) and linkedOf(incs(w0), w0.inc.get(iid).id).foldl(false, (acc, m_490) => acc or (m_490.state == "linked")))) 0 else raw_488)
    val w491 = if ((((t_487.due != 0) and (t_487.due > c.now)) and (t_487.fired != t_487.due))) {
      val w492 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((t_487.due + delta_489) > c.now)) (t_487.due + delta_489) else c.now) }) }) }
      w492
    } else {
      val w493 = if ((((timerDef("resolution").pausable and (t_487.due == 0)) and t_487.paused) and (t_487.left > 0))) {
      val w494 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((t_487.left + delta_489) > 0)) (t_487.left + delta_489) else 1) }) }) }
      w494
    } else w0
      w493
    }
    w491
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
    { val t_495 = world.inc.get(iid).timers.get("reaction")  (((t_495.due != 0) and (t_495.due <= c.now)) and (t_495.fired != t_495.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_496 = personOf(levelUpTarget(c.before))
    val w497 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_496 }) }
    w497
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_498 = groupOf(levelUpTarget(c.before))
    val w499 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_498 }) }
    w499
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_500 = levelUpNumber(c.before)
    val w501 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_500 }) }
    w501
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w502 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w502
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w503 = if (not(timerDef("resolution").pausable)) {
      val w504 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w505 = { ...w504, inc: w504.inc.set(iid, { ...w504.inc.get(iid), timers: w504.inc.get(iid).timers.set("resolution", { ...w504.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w505
    } else {
      val w506 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w507 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w508 = { ...w507, inc: w507.inc.set(iid, { ...w507.inc.get(iid), timers: w507.inc.get(iid).timers.set("resolution", { ...w507.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w509 = { ...w508, inc: w508.inc.set(iid, { ...w508.inc.get(iid), timers: w508.inc.get(iid).timers.set("resolution", { ...w508.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w509
    } else w0
      w506
    }
    w503
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w510 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w511 = if (timerDef("reaction").startsOnce) {
      val w512 = ec_resumeTimer(w0, c, iid, "reaction")
      w512
    } else {
      val w513 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w514 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w515 = { ...w514, inc: w514.inc.set(iid, { ...w514.inc.get(iid), timers: w514.inc.get(iid).timers.set("reaction", { ...w514.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w516 = { ...w515, inc: w515.inc.set(iid, { ...w515.inc.get(iid), timers: w515.inc.get(iid).timers.set("reaction", { ...w515.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w516
    } else {
      val sec_517 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w518 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_517 < 0)) 0 else (c.now + (sec_517 * 1000))) }) }) }
      val w519 = { ...w518, inc: w518.inc.set(iid, { ...w518.inc.get(iid), timers: w518.inc.get(iid).timers.set("reaction", { ...w518.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w520 = { ...w519, inc: w519.inc.set(iid, { ...w519.inc.get(iid), timers: w519.inc.get(iid).timers.set("reaction", { ...w519.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w521 = { ...w520, inc: w520.inc.set(iid, { ...w520.inc.get(iid), timers: w520.inc.get(iid).timers.set("reaction", { ...w520.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w521
    }
      w513
    }
      w511
    }
    w510
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_522 = addressee(w0.inc.get(iid))
    val w523 = if (((whom_522 != "") and (whom_522 != c.actor))) w0 else w0
    w523
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
    { val t_524 = world.inc.get(iid).timers.get("reaction")  (((t_524.due != 0) and (t_524.due <= c.now)) and (t_524.fired != t_524.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_525 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w526 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_525) }) }
    val w527 = { ...w526, inc: w526.inc.set(iid, { ...w526.inc.get(iid), slaBreached: true }) }
    val w528 = groupMembersAt(incs(w0), w527.inc.get(iid), c.deadline).foldl([], (acc, x531) => acc.append(x531.id)).foldl(w527, (wf529, eId530) => {
      val w532 = { ...wf529, inc: wf529.inc.set(eId530, { ...wf529.inc.get(eId530), breaches: wf529.inc.get(eId530).breaches.append(breach_525) }) }
      val w533 = { ...w532, inc: w532.inc.set(eId530, { ...w532.inc.get(eId530), slaBreached: true }) }
      w533
    })
    w528
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w534 = if (timerDef("reaction").startsOnce) {
      val w535 = ec_pauseTimer(w0, c, iid, "reaction")
      w535
    } else {
      val w536 = if (false) {
      val w537 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w538 = { ...w537, inc: w537.inc.set(iid, { ...w537.inc.get(iid), timers: w537.inc.get(iid).timers.set("reaction", { ...w537.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w539 = { ...w538, inc: w538.inc.set(iid, { ...w538.inc.get(iid), timers: w538.inc.get(iid).timers.set("reaction", { ...w538.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w540 = { ...w539, inc: w539.inc.set(iid, { ...w539.inc.get(iid), timers: w539.inc.get(iid).timers.set("reaction", { ...w539.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w540
    } else {
      val w541 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_542 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w543 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_542) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w544 = { ...w543, inc: w543.inc.set(iid, { ...w543.inc.get(iid), timers: w543.inc.get(iid).timers.set("reaction", { ...w543.inc.get(iid).timers.get("reaction"), paused: keep_542 }) }) }
      val w545 = { ...w544, inc: w544.inc.set(iid, { ...w544.inc.get(iid), timers: w544.inc.get(iid).timers.set("reaction", { ...w544.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w546 = { ...w545, inc: w545.inc.set(iid, { ...w545.inc.get(iid), timers: w545.inc.get(iid).timers.set("reaction", { ...w545.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w546
    }
      w541
    }
      w536
    }
    w534
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_547 = settings.alerts.target
    val w548 = if (((whom_547 != "") and (whom_547 != c.actor))) w0 else w0
    w548
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
    { val t_549 = world.inc.get(iid).timers.get("reaction")  (((t_549.due != 0) and (t_549.due <= c.now)) and (t_549.fired != t_549.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_550 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w551 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_550) }) }
    val w552 = { ...w551, inc: w551.inc.set(iid, { ...w551.inc.get(iid), slaBreached: true }) }
    val w553 = groupMembersAt(incs(w0), w552.inc.get(iid), c.deadline).foldl([], (acc, x556) => acc.append(x556.id)).foldl(w552, (wf554, eId555) => {
      val w557 = { ...wf554, inc: wf554.inc.set(eId555, { ...wf554.inc.get(eId555), breaches: wf554.inc.get(eId555).breaches.append(breach_550) }) }
      val w558 = { ...w557, inc: w557.inc.set(eId555, { ...w557.inc.get(eId555), slaBreached: true }) }
      w558
    })
    w553
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w559 = if (timerDef("reaction").startsOnce) {
      val w560 = ec_pauseTimer(w0, c, iid, "reaction")
      w560
    } else {
      val w561 = if (false) {
      val w562 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w563 = { ...w562, inc: w562.inc.set(iid, { ...w562.inc.get(iid), timers: w562.inc.get(iid).timers.set("reaction", { ...w562.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w564 = { ...w563, inc: w563.inc.set(iid, { ...w563.inc.get(iid), timers: w563.inc.get(iid).timers.set("reaction", { ...w563.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w565 = { ...w564, inc: w564.inc.set(iid, { ...w564.inc.get(iid), timers: w564.inc.get(iid).timers.set("reaction", { ...w564.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w565
    } else {
      val w566 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_567 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w568 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_567) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w569 = { ...w568, inc: w568.inc.set(iid, { ...w568.inc.get(iid), timers: w568.inc.get(iid).timers.set("reaction", { ...w568.inc.get(iid).timers.get("reaction"), paused: keep_567 }) }) }
      val w570 = { ...w569, inc: w569.inc.set(iid, { ...w569.inc.get(iid), timers: w569.inc.get(iid).timers.set("reaction", { ...w569.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w571 = { ...w570, inc: w570.inc.set(iid, { ...w570.inc.get(iid), timers: w570.inc.get(iid).timers.set("reaction", { ...w570.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w571
    }
      w566
    }
      w561
    }
    w559
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_572 = settings.alerts.target
    val w573 = if (((whom_572 != "") and (whom_572 != c.actor))) w0 else w0
    w573
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
    { val t_574 = world.inc.get(iid).timers.get("resolution")  (((t_574.due != 0) and (t_574.due <= c.now)) and (t_574.fired != t_574.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_575 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w576 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_575) }) }
    val w577 = { ...w576, inc: w576.inc.set(iid, { ...w576.inc.get(iid), slaBreached: true }) }
    val w578 = groupMembersAt(incs(w0), w577.inc.get(iid), c.deadline).foldl([], (acc, x581) => acc.append(x581.id)).foldl(w577, (wf579, eId580) => {
      val w582 = { ...wf579, inc: wf579.inc.set(eId580, { ...wf579.inc.get(eId580), breaches: wf579.inc.get(eId580).breaches.append(breach_575) }) }
      val w583 = { ...w582, inc: w582.inc.set(eId580, { ...w582.inc.get(eId580), slaBreached: true }) }
      w583
    })
    w578
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_584 = settings.alerts.target
    val w585 = if (((whom_584 != "") and (whom_584 != c.actor))) w0 else w0
    w585
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
    { val t_586 = world.inc.get(iid).timers.get("resolution")  (((t_586.due != 0) and (t_586.due <= c.now)) and (t_586.fired != t_586.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_587 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w588 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_587) }) }
    val w589 = { ...w588, inc: w588.inc.set(iid, { ...w588.inc.get(iid), slaBreached: true }) }
    val w590 = groupMembersAt(incs(w0), w589.inc.get(iid), c.deadline).foldl([], (acc, x593) => acc.append(x593.id)).foldl(w589, (wf591, eId592) => {
      val w594 = { ...wf591, inc: wf591.inc.set(eId592, { ...wf591.inc.get(eId592), breaches: wf591.inc.get(eId592).breaches.append(breach_587) }) }
      val w595 = { ...w594, inc: w594.inc.set(eId592, { ...w594.inc.get(eId592), slaBreached: true }) }
      w595
    })
    w590
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_596 = personOf(levelUpTarget(c.before))
    val w597 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_596 }) }
    w597
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_598 = groupOf(levelUpTarget(c.before))
    val w599 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_598 }) }
    w599
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_600 = levelUpNumber(c.before)
    val w601 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_600 }) }
    w601
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w602 = if (not(timerDef("resolution").pausable)) {
      val w603 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w604 = { ...w603, inc: w603.inc.set(iid, { ...w603.inc.get(iid), timers: w603.inc.get(iid).timers.set("resolution", { ...w603.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w604
    } else {
      val w605 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w606 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w607 = { ...w606, inc: w606.inc.set(iid, { ...w606.inc.get(iid), timers: w606.inc.get(iid).timers.set("resolution", { ...w606.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w608 = { ...w607, inc: w607.inc.set(iid, { ...w607.inc.get(iid), timers: w607.inc.get(iid).timers.set("resolution", { ...w607.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w608
    } else w0
      w605
    }
    w602
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w609 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w610 = if (timerDef("reaction").startsOnce) {
      val w611 = ec_resumeTimer(w0, c, iid, "reaction")
      w611
    } else {
      val w612 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w613 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w614 = { ...w613, inc: w613.inc.set(iid, { ...w613.inc.get(iid), timers: w613.inc.get(iid).timers.set("reaction", { ...w613.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w615 = { ...w614, inc: w614.inc.set(iid, { ...w614.inc.get(iid), timers: w614.inc.get(iid).timers.set("reaction", { ...w614.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w615
    } else {
      val sec_616 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w617 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_616 < 0)) 0 else (c.now + (sec_616 * 1000))) }) }) }
      val w618 = { ...w617, inc: w617.inc.set(iid, { ...w617.inc.get(iid), timers: w617.inc.get(iid).timers.set("reaction", { ...w617.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w619 = { ...w618, inc: w618.inc.set(iid, { ...w618.inc.get(iid), timers: w618.inc.get(iid).timers.set("reaction", { ...w618.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w620 = { ...w619, inc: w619.inc.set(iid, { ...w619.inc.get(iid), timers: w619.inc.get(iid).timers.set("reaction", { ...w619.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w620
    }
      w612
    }
      w610
    }
    w609
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_621 = c.before.owner
    val w622 = if (((whom_621 != "") and (whom_621 != c.actor))) w0 else w0
    w622
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_623 = addressee(w0.inc.get(iid))
    val w624 = if (((whom_623 != "") and (whom_623 != c.actor))) w0 else w0
    w624
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
    { val t_625 = world.inc.get(iid).timers.get("resolution")  (((t_625.due != 0) and (t_625.due <= c.now)) and (t_625.fired != t_625.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_626 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w627 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_626) }) }
    val w628 = { ...w627, inc: w627.inc.set(iid, { ...w627.inc.get(iid), slaBreached: true }) }
    val w629 = groupMembersAt(incs(w0), w628.inc.get(iid), c.deadline).foldl([], (acc, x632) => acc.append(x632.id)).foldl(w628, (wf630, eId631) => {
      val w633 = { ...wf630, inc: wf630.inc.set(eId631, { ...wf630.inc.get(eId631), breaches: wf630.inc.get(eId631).breaches.append(breach_626) }) }
      val w634 = { ...w633, inc: w633.inc.set(eId631, { ...w633.inc.get(eId631), slaBreached: true }) }
      w634
    })
    w629
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_635 = settings.alerts.target
    val w636 = if (((whom_635 != "") and (whom_635 != c.actor))) w0 else w0
    w636
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
    { val t_637 = world.inc.get(iid).timers.get("hold")  (((t_637.due != 0) and (t_637.due <= c.now)) and (t_637.fired != t_637.due)) },
    not(["break", "no_link"].foldl(false, (acc, y638) => acc or y638 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_639 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w640 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_639) }) }
    val w641 = { ...w640, inc: w640.inc.set(iid, { ...w640.inc.get(iid), slaBreached: true }) }
    val w642 = groupMembersAt(incs(w0), w641.inc.get(iid), c.deadline).foldl([], (acc, x645) => acc.append(x645.id)).foldl(w641, (wf643, eId644) => {
      val w646 = { ...wf643, inc: wf643.inc.set(eId644, { ...wf643.inc.get(eId644), breaches: wf643.inc.get(eId644).breaches.append(breach_639) }) }
      val w647 = { ...w646, inc: w646.inc.set(eId644, { ...w646.inc.get(eId644), slaBreached: true }) }
      w647
    })
    w642
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_648 = settings.alerts.target
    val w649 = if (((whom_648 != "") and (whom_648 != c.actor))) w0 else w0
    w649
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
    { val t_650 = world.inc.get(iid).timers.get("hold")  (((t_650.due != 0) and (t_650.due <= c.now)) and (t_650.fired != t_650.due)) },
    ["break"].foldl(false, (acc, y651) => acc or y651 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_652 = ""
    val w653 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_652 }) }
    w653
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w654 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w654
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w655 = if (timerDef("hold").startsOnce) {
      val w656 = ec_pauseTimer(w0, c, iid, "hold")
      w656
    } else {
      val w657 = if (false) {
      val w658 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w659 = { ...w658, inc: w658.inc.set(iid, { ...w658.inc.get(iid), timers: w658.inc.get(iid).timers.set("hold", { ...w658.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w660 = { ...w659, inc: w659.inc.set(iid, { ...w659.inc.get(iid), timers: w659.inc.get(iid).timers.set("hold", { ...w659.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w661 = { ...w660, inc: w660.inc.set(iid, { ...w660.inc.get(iid), timers: w660.inc.get(iid).timers.set("hold", { ...w660.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w661
    } else {
      val w662 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_663 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w664 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_663) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w665 = { ...w664, inc: w664.inc.set(iid, { ...w664.inc.get(iid), timers: w664.inc.get(iid).timers.set("hold", { ...w664.inc.get(iid).timers.get("hold"), paused: keep_663 }) }) }
      val w666 = { ...w665, inc: w665.inc.set(iid, { ...w665.inc.get(iid), timers: w665.inc.get(iid).timers.set("hold", { ...w665.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w667 = { ...w666, inc: w666.inc.set(iid, { ...w666.inc.get(iid), timers: w666.inc.get(iid).timers.set("hold", { ...w666.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w667
    }
      w662
    }
      w657
    }
    w655
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w668 = if (not(timerDef("resolution").pausable)) {
      val w669 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w670 = { ...w669, inc: w669.inc.set(iid, { ...w669.inc.get(iid), timers: w669.inc.get(iid).timers.set("resolution", { ...w669.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w670
    } else {
      val w671 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w672 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w673 = { ...w672, inc: w672.inc.set(iid, { ...w672.inc.get(iid), timers: w672.inc.get(iid).timers.set("resolution", { ...w672.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w674 = { ...w673, inc: w673.inc.set(iid, { ...w673.inc.get(iid), timers: w673.inc.get(iid).timers.set("resolution", { ...w673.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w674
    } else w0
      w671
    }
    w668
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w675 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w676 = if (timerDef("reaction").startsOnce) {
      val w677 = ec_resumeTimer(w0, c, iid, "reaction")
      w677
    } else {
      val w678 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w679 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w680 = { ...w679, inc: w679.inc.set(iid, { ...w679.inc.get(iid), timers: w679.inc.get(iid).timers.set("reaction", { ...w679.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w681 = { ...w680, inc: w680.inc.set(iid, { ...w680.inc.get(iid), timers: w680.inc.get(iid).timers.set("reaction", { ...w680.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w681
    } else {
      val sec_682 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w683 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_682 < 0)) 0 else (c.now + (sec_682 * 1000))) }) }) }
      val w684 = { ...w683, inc: w683.inc.set(iid, { ...w683.inc.get(iid), timers: w683.inc.get(iid).timers.set("reaction", { ...w683.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w685 = { ...w684, inc: w684.inc.set(iid, { ...w684.inc.get(iid), timers: w684.inc.get(iid).timers.set("reaction", { ...w684.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w686 = { ...w685, inc: w685.inc.set(iid, { ...w685.inc.get(iid), timers: w685.inc.get(iid).timers.set("reaction", { ...w685.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w686
    }
      w678
    }
      w676
    }
    w675
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
    val reason_687 = "break"
    val w688 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_687 }) }
    w688
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w689 = if (not(timerDef("resolution").pausable)) {
      val w690 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w691 = { ...w690, inc: w690.inc.set(iid, { ...w690.inc.get(iid), timers: w690.inc.get(iid).timers.set("resolution", { ...w690.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w691
    } else {
      val w692 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w693 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w694 = { ...w693, inc: w693.inc.set(iid, { ...w693.inc.get(iid), timers: w693.inc.get(iid).timers.set("resolution", { ...w693.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w695 = { ...w694, inc: w694.inc.set(iid, { ...w694.inc.get(iid), timers: w694.inc.get(iid).timers.set("resolution", { ...w694.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w695
    } else w0
      w692
    }
    w689
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w696 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w697 = if (timerDef("hold").startsOnce) {
      val w698 = ec_resumeTimer(w0, c, iid, "hold")
      w698
    } else {
      val w699 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w700 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w701 = { ...w700, inc: w700.inc.set(iid, { ...w700.inc.get(iid), timers: w700.inc.get(iid).timers.set("hold", { ...w700.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w702 = { ...w701, inc: w701.inc.set(iid, { ...w701.inc.get(iid), timers: w701.inc.get(iid).timers.set("hold", { ...w701.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w702
    } else {
      val sec_703 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w704 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_703 < 0)) 0 else (c.now + (sec_703 * 1000))) }) }) }
      val w705 = { ...w704, inc: w704.inc.set(iid, { ...w704.inc.get(iid), timers: w704.inc.get(iid).timers.set("hold", { ...w704.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w706 = { ...w705, inc: w705.inc.set(iid, { ...w705.inc.get(iid), timers: w705.inc.get(iid).timers.set("hold", { ...w705.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w707 = { ...w706, inc: w706.inc.set(iid, { ...w706.inc.get(iid), timers: w706.inc.get(iid).timers.set("hold", { ...w706.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w707
    }
      w699
    }
      w697
    }
    w696
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
    val reason_708 = "no_link"
    val w709 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_708 }) }
    w709
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
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

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w717 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w718 = if (timerDef("hold").startsOnce) {
      val w719 = ec_resumeTimer(w0, c, iid, "hold")
      w719
    } else {
      val w720 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w721 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w722 = { ...w721, inc: w721.inc.set(iid, { ...w721.inc.get(iid), timers: w721.inc.get(iid).timers.set("hold", { ...w721.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w723 = { ...w722, inc: w722.inc.set(iid, { ...w722.inc.get(iid), timers: w722.inc.get(iid).timers.set("hold", { ...w722.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w723
    } else {
      val sec_724 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w725 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_724 < 0)) 0 else (c.now + (sec_724 * 1000))) }) }) }
      val w726 = { ...w725, inc: w725.inc.set(iid, { ...w725.inc.get(iid), timers: w725.inc.get(iid).timers.set("hold", { ...w725.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w727 = { ...w726, inc: w726.inc.set(iid, { ...w726.inc.get(iid), timers: w726.inc.get(iid).timers.set("hold", { ...w726.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w728 = { ...w727, inc: w727.inc.set(iid, { ...w727.inc.get(iid), timers: w727.inc.get(iid).timers.set("hold", { ...w727.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w728
    }
      w720
    }
      w718
    }
    w717
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_729 = settings.alerts.target
    val w730 = if (((whom_729 != "") and (whom_729 != c.actor))) w0 else w0
    w730
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
    ["break", "no_link"].foldl(false, (acc, y731) => acc or y731 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_732 = ""
    val w733 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_732 }) }
    w733
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w734 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w734
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w735 = if (timerDef("hold").startsOnce) {
      val w736 = ec_pauseTimer(w0, c, iid, "hold")
      w736
    } else {
      val w737 = if (false) {
      val w738 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w739 = { ...w738, inc: w738.inc.set(iid, { ...w738.inc.get(iid), timers: w738.inc.get(iid).timers.set("hold", { ...w738.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w740 = { ...w739, inc: w739.inc.set(iid, { ...w739.inc.get(iid), timers: w739.inc.get(iid).timers.set("hold", { ...w739.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w741 = { ...w740, inc: w740.inc.set(iid, { ...w740.inc.get(iid), timers: w740.inc.get(iid).timers.set("hold", { ...w740.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w741
    } else {
      val w742 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_743 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w744 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_743) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w745 = { ...w744, inc: w744.inc.set(iid, { ...w744.inc.get(iid), timers: w744.inc.get(iid).timers.set("hold", { ...w744.inc.get(iid).timers.get("hold"), paused: keep_743 }) }) }
      val w746 = { ...w745, inc: w745.inc.set(iid, { ...w745.inc.get(iid), timers: w745.inc.get(iid).timers.set("hold", { ...w745.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w747 = { ...w746, inc: w746.inc.set(iid, { ...w746.inc.get(iid), timers: w746.inc.get(iid).timers.set("hold", { ...w746.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w747
    }
      w742
    }
      w737
    }
    w735
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w748 = if (not(timerDef("resolution").pausable)) {
      val w749 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w750 = { ...w749, inc: w749.inc.set(iid, { ...w749.inc.get(iid), timers: w749.inc.get(iid).timers.set("resolution", { ...w749.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w750
    } else {
      val w751 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w752 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w753 = { ...w752, inc: w752.inc.set(iid, { ...w752.inc.get(iid), timers: w752.inc.get(iid).timers.set("resolution", { ...w752.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w754 = { ...w753, inc: w753.inc.set(iid, { ...w753.inc.get(iid), timers: w753.inc.get(iid).timers.set("resolution", { ...w753.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w754
    } else w0
      w751
    }
    w748
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w755 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w756 = if (timerDef("reaction").startsOnce) {
      val w757 = ec_resumeTimer(w0, c, iid, "reaction")
      w757
    } else {
      val w758 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w759 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w760 = { ...w759, inc: w759.inc.set(iid, { ...w759.inc.get(iid), timers: w759.inc.get(iid).timers.set("reaction", { ...w759.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w761 = { ...w760, inc: w760.inc.set(iid, { ...w760.inc.get(iid), timers: w760.inc.get(iid).timers.set("reaction", { ...w760.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w761
    } else {
      val sec_762 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w763 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_762 < 0)) 0 else (c.now + (sec_762 * 1000))) }) }) }
      val w764 = { ...w763, inc: w763.inc.set(iid, { ...w763.inc.get(iid), timers: w763.inc.get(iid).timers.set("reaction", { ...w763.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w765 = { ...w764, inc: w764.inc.set(iid, { ...w764.inc.get(iid), timers: w764.inc.get(iid).timers.set("reaction", { ...w764.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w766 = { ...w765, inc: w765.inc.set(iid, { ...w765.inc.get(iid), timers: w765.inc.get(iid).timers.set("reaction", { ...w765.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w766
    }
      w758
    }
      w756
    }
    w755
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
    { val t_767 = world.inc.get(iid).timers.get("hold")  (((t_767.due != 0) and (t_767.due <= c.now)) and (t_767.fired != t_767.due)) },
    ["no_link"].foldl(false, (acc, y768) => acc or y768 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_769 = ""
    val w770 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_769 }) }
    w770
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w771 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w771
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w772 = if (timerDef("hold").startsOnce) {
      val w773 = ec_pauseTimer(w0, c, iid, "hold")
      w773
    } else {
      val w774 = if (false) {
      val w775 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w776 = { ...w775, inc: w775.inc.set(iid, { ...w775.inc.get(iid), timers: w775.inc.get(iid).timers.set("hold", { ...w775.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w777 = { ...w776, inc: w776.inc.set(iid, { ...w776.inc.get(iid), timers: w776.inc.get(iid).timers.set("hold", { ...w776.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w778 = { ...w777, inc: w777.inc.set(iid, { ...w777.inc.get(iid), timers: w777.inc.get(iid).timers.set("hold", { ...w777.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w778
    } else {
      val w779 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_780 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w781 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_780) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w782 = { ...w781, inc: w781.inc.set(iid, { ...w781.inc.get(iid), timers: w781.inc.get(iid).timers.set("hold", { ...w781.inc.get(iid).timers.get("hold"), paused: keep_780 }) }) }
      val w783 = { ...w782, inc: w782.inc.set(iid, { ...w782.inc.get(iid), timers: w782.inc.get(iid).timers.set("hold", { ...w782.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w784 = { ...w783, inc: w783.inc.set(iid, { ...w783.inc.get(iid), timers: w783.inc.get(iid).timers.set("hold", { ...w783.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w784
    }
      w779
    }
      w774
    }
    w772
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w785 = if (not(timerDef("resolution").pausable)) {
      val w786 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w787 = { ...w786, inc: w786.inc.set(iid, { ...w786.inc.get(iid), timers: w786.inc.get(iid).timers.set("resolution", { ...w786.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w787
    } else {
      val w788 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w789 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w790 = { ...w789, inc: w789.inc.set(iid, { ...w789.inc.get(iid), timers: w789.inc.get(iid).timers.set("resolution", { ...w789.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w791 = { ...w790, inc: w790.inc.set(iid, { ...w790.inc.get(iid), timers: w790.inc.get(iid).timers.set("resolution", { ...w790.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w791
    } else w0
      w788
    }
    w785
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w792 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w793 = if (timerDef("reaction").startsOnce) {
      val w794 = ec_resumeTimer(w0, c, iid, "reaction")
      w794
    } else {
      val w795 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w796 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w797 = { ...w796, inc: w796.inc.set(iid, { ...w796.inc.get(iid), timers: w796.inc.get(iid).timers.set("reaction", { ...w796.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w798 = { ...w797, inc: w797.inc.set(iid, { ...w797.inc.get(iid), timers: w797.inc.get(iid).timers.set("reaction", { ...w797.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w798
    } else {
      val sec_799 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w800 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_799 < 0)) 0 else (c.now + (sec_799 * 1000))) }) }) }
      val w801 = { ...w800, inc: w800.inc.set(iid, { ...w800.inc.get(iid), timers: w800.inc.get(iid).timers.set("reaction", { ...w800.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w802 = { ...w801, inc: w801.inc.set(iid, { ...w801.inc.get(iid), timers: w801.inc.get(iid).timers.set("reaction", { ...w801.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w803 = { ...w802, inc: w802.inc.set(iid, { ...w802.inc.get(iid), timers: w802.inc.get(iid).timers.set("reaction", { ...w802.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w803
    }
      w795
    }
      w793
    }
    w792
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
    val group_804 = dutyGroupOf(w0.inc.get(iid).owner)
    val w805 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_804 }) }
    w805
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_806 = ""
    val w807 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_806 }) }
    w807
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_808 = addressee(w0.inc.get(iid))
    val w809 = if (((whom_808 != "") and (whom_808 != c.actor))) w0 else w0
    w809
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
    val who_810 = ""
    val w811 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_810 }) }
    w811
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
    val who_812 = ""
    val w813 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_812 }) }
    w813
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w814 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w814
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w815 = if (timerDef("hold").startsOnce) {
      val w816 = ec_pauseTimer(w0, c, iid, "hold")
      w816
    } else {
      val w817 = if (false) {
      val w818 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w819 = { ...w818, inc: w818.inc.set(iid, { ...w818.inc.get(iid), timers: w818.inc.get(iid).timers.set("hold", { ...w818.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w820 = { ...w819, inc: w819.inc.set(iid, { ...w819.inc.get(iid), timers: w819.inc.get(iid).timers.set("hold", { ...w819.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w821 = { ...w820, inc: w820.inc.set(iid, { ...w820.inc.get(iid), timers: w820.inc.get(iid).timers.set("hold", { ...w820.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w821
    } else {
      val w822 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_823 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w824 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_823) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w825 = { ...w824, inc: w824.inc.set(iid, { ...w824.inc.get(iid), timers: w824.inc.get(iid).timers.set("hold", { ...w824.inc.get(iid).timers.get("hold"), paused: keep_823 }) }) }
      val w826 = { ...w825, inc: w825.inc.set(iid, { ...w825.inc.get(iid), timers: w825.inc.get(iid).timers.set("hold", { ...w825.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w827 = { ...w826, inc: w826.inc.set(iid, { ...w826.inc.get(iid), timers: w826.inc.get(iid).timers.set("hold", { ...w826.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w827
    }
      w822
    }
      w817
    }
    w815
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w828 = if (not(timerDef("resolution").pausable)) {
      val w829 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w830 = { ...w829, inc: w829.inc.set(iid, { ...w829.inc.get(iid), timers: w829.inc.get(iid).timers.set("resolution", { ...w829.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w830
    } else {
      val w831 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w832 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w833 = { ...w832, inc: w832.inc.set(iid, { ...w832.inc.get(iid), timers: w832.inc.get(iid).timers.set("resolution", { ...w832.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w834 = { ...w833, inc: w833.inc.set(iid, { ...w833.inc.get(iid), timers: w833.inc.get(iid).timers.set("resolution", { ...w833.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w834
    } else w0
      w831
    }
    w828
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w835 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w836 = if (timerDef("reaction").startsOnce) {
      val w837 = ec_resumeTimer(w0, c, iid, "reaction")
      w837
    } else {
      val w838 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w839 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w840 = { ...w839, inc: w839.inc.set(iid, { ...w839.inc.get(iid), timers: w839.inc.get(iid).timers.set("reaction", { ...w839.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w841 = { ...w840, inc: w840.inc.set(iid, { ...w840.inc.get(iid), timers: w840.inc.get(iid).timers.set("reaction", { ...w840.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w841
    } else {
      val sec_842 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
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
    val who_847 = ""
    val w848 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_847 }) }
    w848
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_849 = ""
    val w850 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_849 }) }
    w850
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w851 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w851
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w852 = if (timerDef("hold").startsOnce) {
      val w853 = ec_pauseTimer(w0, c, iid, "hold")
      w853
    } else {
      val w854 = if (false) {
      val w855 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w856 = { ...w855, inc: w855.inc.set(iid, { ...w855.inc.get(iid), timers: w855.inc.get(iid).timers.set("hold", { ...w855.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w857 = { ...w856, inc: w856.inc.set(iid, { ...w856.inc.get(iid), timers: w856.inc.get(iid).timers.set("hold", { ...w856.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w858 = { ...w857, inc: w857.inc.set(iid, { ...w857.inc.get(iid), timers: w857.inc.get(iid).timers.set("hold", { ...w857.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w858
    } else {
      val w859 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_860 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w861 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_860) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w862 = { ...w861, inc: w861.inc.set(iid, { ...w861.inc.get(iid), timers: w861.inc.get(iid).timers.set("hold", { ...w861.inc.get(iid).timers.get("hold"), paused: keep_860 }) }) }
      val w863 = { ...w862, inc: w862.inc.set(iid, { ...w862.inc.get(iid), timers: w862.inc.get(iid).timers.set("hold", { ...w862.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w864 = { ...w863, inc: w863.inc.set(iid, { ...w863.inc.get(iid), timers: w863.inc.get(iid).timers.set("hold", { ...w863.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w864
    }
      w859
    }
      w854
    }
    w852
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w865 = if (not(timerDef("resolution").pausable)) {
      val w866 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w867 = { ...w866, inc: w866.inc.set(iid, { ...w866.inc.get(iid), timers: w866.inc.get(iid).timers.set("resolution", { ...w866.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w867
    } else {
      val w868 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w869 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w870 = { ...w869, inc: w869.inc.set(iid, { ...w869.inc.get(iid), timers: w869.inc.get(iid).timers.set("resolution", { ...w869.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w871 = { ...w870, inc: w870.inc.set(iid, { ...w870.inc.get(iid), timers: w870.inc.get(iid).timers.set("resolution", { ...w870.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w871
    } else w0
      w868
    }
    w865
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w872 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w873 = if (timerDef("reaction").startsOnce) {
      val w874 = ec_resumeTimer(w0, c, iid, "reaction")
      w874
    } else {
      val w875 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w876 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w877 = { ...w876, inc: w876.inc.set(iid, { ...w876.inc.get(iid), timers: w876.inc.get(iid).timers.set("reaction", { ...w876.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w878 = { ...w877, inc: w877.inc.set(iid, { ...w877.inc.get(iid), timers: w877.inc.get(iid).timers.set("reaction", { ...w877.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w878
    } else {
      val sec_879 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w880 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_879 < 0)) 0 else (c.now + (sec_879 * 1000))) }) }) }
      val w881 = { ...w880, inc: w880.inc.set(iid, { ...w880.inc.get(iid), timers: w880.inc.get(iid).timers.set("reaction", { ...w880.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w882 = { ...w881, inc: w881.inc.set(iid, { ...w881.inc.get(iid), timers: w881.inc.get(iid).timers.set("reaction", { ...w881.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w883 = { ...w882, inc: w882.inc.set(iid, { ...w882.inc.get(iid), timers: w882.inc.get(iid).timers.set("reaction", { ...w882.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w883
    }
      w875
    }
      w873
    }
    w872
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_884 = settings.alerts.target
    val w885 = if (((whom_884 != "") and (whom_884 != c.actor))) w0 else w0
    w885
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
    val who_886 = ""
    val w887 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_886 }) }
    w887
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_888 = ""
    val w889 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_888 }) }
    w889
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w890 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w891 = if (timerDef("reaction").startsOnce) {
      val w892 = ec_resumeTimer(w0, c, iid, "reaction")
      w892
    } else {
      val w893 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w894 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w895 = { ...w894, inc: w894.inc.set(iid, { ...w894.inc.get(iid), timers: w894.inc.get(iid).timers.set("reaction", { ...w894.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w896 = { ...w895, inc: w895.inc.set(iid, { ...w895.inc.get(iid), timers: w895.inc.get(iid).timers.set("reaction", { ...w895.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w896
    } else {
      val sec_897 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w898 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_897 < 0)) 0 else (c.now + (sec_897 * 1000))) }) }) }
      val w899 = { ...w898, inc: w898.inc.set(iid, { ...w898.inc.get(iid), timers: w898.inc.get(iid).timers.set("reaction", { ...w898.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w900 = { ...w899, inc: w899.inc.set(iid, { ...w899.inc.get(iid), timers: w899.inc.get(iid).timers.set("reaction", { ...w899.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w901 = { ...w900, inc: w900.inc.set(iid, { ...w900.inc.get(iid), timers: w900.inc.get(iid).timers.set("reaction", { ...w900.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w901
    }
      w893
    }
      w891
    }
    w890
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_902 = settings.alerts.target
    val w903 = if (((whom_902 != "") and (whom_902 != c.actor))) w0 else w0
    w903
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
    not(settings.session.states.foldl(false, (acc, s_904) => acc or ((s_904.id == agentState(c.me)) and s_904.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_905 = incidentById(incs(world), c.form.primaryId)  ((((ps_905.length() > 0) and (ps_905[0].id != world.inc.get(iid).id)) and (ps_905[0].linkedTo == "")) and ((ps_905[0].state == "new") or ((ps_905[0].state == "in_progress") and (ps_905[0].owner == c.me)))) },
    { val ps_906 = incidentById(incs(world), c.form.primaryId)  ((ps_906.length() > 0) and (ps_906[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w907 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w907
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_908 = incidentById(incs(w0), c.form.primaryId)
    val w909 = if ((ps_908.length() > 0)) {
      val w910 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_917 => not(isDone(e_917))).foldl([], (acc, x913) => acc.append(x913.id)).foldl(w0, (wf911, cId912) => {
      val w914 = { ...wf911, inc: wf911.inc.set(cId912, { ...wf911.inc.get(cId912), leftGroup: { primaryId: wf911.inc.get(cId912).linkedTo, linkedAt: wf911.inc.get(cId912).linkedAt, at: c.now } }) }
      val w915 = { ...w914, inc: w914.inc.set(cId912, { ...w914.inc.get(cId912), linkedTo: ps_908[0].id }) }
      val w916 = { ...w915, inc: w915.inc.set(cId912, { ...w915.inc.get(cId912), linkedAt: c.now }) }
      w916
    })
      w910
    } else w0
    w909
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_918 = c.form.primaryId
    val w919 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_918 }) }
    val w920 = { ...w919, inc: w919.inc.set(iid, { ...w919.inc.get(iid), linkedAt: c.now }) }
    w920
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_921 = ""
    val w922 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_921 }) }
    w922
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_923 = ""
    val w924 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_923 }) }
    w924
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w925 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w925
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w926 = if (timerDef("reaction").startsOnce) {
      val w927 = ec_pauseTimer(w0, c, iid, "reaction")
      w927
    } else {
      val w928 = if (false) {
      val w929 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w930 = { ...w929, inc: w929.inc.set(iid, { ...w929.inc.get(iid), timers: w929.inc.get(iid).timers.set("reaction", { ...w929.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w931 = { ...w930, inc: w930.inc.set(iid, { ...w930.inc.get(iid), timers: w930.inc.get(iid).timers.set("reaction", { ...w930.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w932 = { ...w931, inc: w931.inc.set(iid, { ...w931.inc.get(iid), timers: w931.inc.get(iid).timers.set("reaction", { ...w931.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w932
    } else {
      val w933 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_934 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w935 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_934) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w936 = { ...w935, inc: w935.inc.set(iid, { ...w935.inc.get(iid), timers: w935.inc.get(iid).timers.set("reaction", { ...w935.inc.get(iid).timers.get("reaction"), paused: keep_934 }) }) }
      val w937 = { ...w936, inc: w936.inc.set(iid, { ...w936.inc.get(iid), timers: w936.inc.get(iid).timers.set("reaction", { ...w936.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w938 = { ...w937, inc: w937.inc.set(iid, { ...w937.inc.get(iid), timers: w937.inc.get(iid).timers.set("reaction", { ...w937.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w938
    }
      w933
    }
      w928
    }
    w926
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w939 = if (not(timerDef("resolution").pausable)) {
      val w940 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w941 = { ...w940, inc: w940.inc.set(iid, { ...w940.inc.get(iid), timers: w940.inc.get(iid).timers.set("resolution", { ...w940.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w941
    } else {
      val w942 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w943 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w944 = { ...w943, inc: w943.inc.set(iid, { ...w943.inc.get(iid), timers: w943.inc.get(iid).timers.set("resolution", { ...w943.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w945 = { ...w944, inc: w944.inc.set(iid, { ...w944.inc.get(iid), timers: w944.inc.get(iid).timers.set("resolution", { ...w944.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w945
    } else w0
      w942
    }
    w939
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_946 = incidentById(incs(w0), c.form.primaryId)
    val w947 = if (((((ps_946.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_946[0], "resolution", c.now)))) {
      val t_948 = ps_946[0].timers.get("resolution")
      val left_949 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_950 = (if ((t_948.due != 0)) (t_948.due - c.now) else (if (t_948.paused) t_948.left else (timerSec(ps_946[0], "resolution", "") * 1000)))
      val w951 = if ((left_949 < was_950)) {
      val w952 = ps_946.foldl([], (acc, x955) => acc.append(x955.id)).foldl(w0, (wf953, pId954) => {
      val w956 = if ((t_948.due != 0)) {
      val w957 = { ...wf953, inc: wf953.inc.set(pId954, { ...wf953.inc.get(pId954), timers: wf953.inc.get(pId954).timers.set("resolution", { ...wf953.inc.get(pId954).timers.get("resolution"), due: (c.now + left_949) }) }) }
      w957
    } else {
      val w958 = { ...wf953, inc: wf953.inc.set(pId954, { ...wf953.inc.get(pId954), timers: wf953.inc.get(pId954).timers.set("resolution", { ...wf953.inc.get(pId954).timers.get("resolution"), left: left_949 }) }) }
      val w959 = { ...w958, inc: w958.inc.set(pId954, { ...w958.inc.get(pId954), timers: w958.inc.get(pId954).timers.set("resolution", { ...w958.inc.get(pId954).timers.get("resolution"), paused: true }) }) }
      w959
    }
      w956
    })
      w952
    } else w0
      w951
    } else w0
    w947
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w960 = if (timerDef("hold").startsOnce) {
      val w961 = ec_pauseTimer(w0, c, iid, "hold")
      w961
    } else {
      val w962 = if (false) {
      val w963 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w964 = { ...w963, inc: w963.inc.set(iid, { ...w963.inc.get(iid), timers: w963.inc.get(iid).timers.set("hold", { ...w963.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w965 = { ...w964, inc: w964.inc.set(iid, { ...w964.inc.get(iid), timers: w964.inc.get(iid).timers.set("hold", { ...w964.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w966 = { ...w965, inc: w965.inc.set(iid, { ...w965.inc.get(iid), timers: w965.inc.get(iid).timers.set("hold", { ...w965.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w966
    } else {
      val w967 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_968 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w969 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_968) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w970 = { ...w969, inc: w969.inc.set(iid, { ...w969.inc.get(iid), timers: w969.inc.get(iid).timers.set("hold", { ...w969.inc.get(iid).timers.get("hold"), paused: keep_968 }) }) }
      val w971 = { ...w970, inc: w970.inc.set(iid, { ...w970.inc.get(iid), timers: w970.inc.get(iid).timers.set("hold", { ...w970.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w972 = { ...w971, inc: w971.inc.set(iid, { ...w971.inc.get(iid), timers: w971.inc.get(iid).timers.set("hold", { ...w971.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w972
    }
      w967
    }
      w962
    }
    w960
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
    not(settings.session.states.foldl(false, (acc, s_973) => acc or ((s_973.id == agentState(c.me)) and s_973.readOnly))),
    { val ps_974 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_974.length() > 0) and ((ownership(c.me, ps_974[0]) == "owner") or unowned(ps_974[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_975 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w976 = if (((ps_975.length() > 0) and (leftOf(ps_975[0], "resolution", c.now) >= 0))) {
      val w977 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w978 = { ...w977, inc: w977.inc.set(iid, { ...w977.inc.get(iid), timers: w977.inc.get(iid).timers.set("resolution", { ...w977.inc.get(iid).timers.get("resolution"), left: leftOf(ps_975[0], "resolution", c.now) }) }) }
      val w979 = { ...w978, inc: w978.inc.set(iid, { ...w978.inc.get(iid), timers: w978.inc.get(iid).timers.set("resolution", { ...w978.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w980 = if ((leftOf(ps_975[0], "resolution", c.now) == 0)) {
      val w981 = { ...w979, inc: w979.inc.set(iid, { ...w979.inc.get(iid), timers: w979.inc.get(iid).timers.set("resolution", { ...w979.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_975[0], "resolution", c.now)) ps_975[0].timers.get("resolution").fired else ps_975[0].timers.get("resolution").due) }) }) }
      w981
    } else w979
      w980
    } else w0
    w976
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w982 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_983 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w984 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w985 = { ...w984, inc: w984.inc.set(iid, { ...w984.inc.get(iid), linkedTo: "" }) }
      val w986 = { ...w985, inc: w985.inc.set(iid, { ...w985.inc.get(iid), linkedAt: 0 }) }
      val w987 = if (((ps_983.length() > 0) and ("" != ""))) w986 else w986
      val w988 = if (("" != "")) {
      val w989 = ps_983.foldl([], (acc, x992) => acc.append(x992.id)).foldl(w987, (wf990, pId991) => wf990)
      w989
    } else w987
      w988
    } else {
      val w993 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w994 = { ...w993, inc: w993.inc.set(iid, { ...w993.inc.get(iid), linkedAt: 0 }) }
      w994
    }
    w982
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w995 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w996 = if (timerDef("reaction").startsOnce) {
      val w997 = ec_resumeTimer(w0, c, iid, "reaction")
      w997
    } else {
      val w998 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w999 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1000 = { ...w999, inc: w999.inc.set(iid, { ...w999.inc.get(iid), timers: w999.inc.get(iid).timers.set("reaction", { ...w999.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1001 = { ...w1000, inc: w1000.inc.set(iid, { ...w1000.inc.get(iid), timers: w1000.inc.get(iid).timers.set("reaction", { ...w1000.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1001
    } else {
      val sec_1002 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w1003 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1002 < 0)) 0 else (c.now + (sec_1002 * 1000))) }) }) }
      val w1004 = { ...w1003, inc: w1003.inc.set(iid, { ...w1003.inc.get(iid), timers: w1003.inc.get(iid).timers.set("reaction", { ...w1003.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1005 = { ...w1004, inc: w1004.inc.set(iid, { ...w1004.inc.get(iid), timers: w1004.inc.get(iid).timers.set("reaction", { ...w1004.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1006 = { ...w1005, inc: w1005.inc.set(iid, { ...w1005.inc.get(iid), timers: w1005.inc.get(iid).timers.set("reaction", { ...w1005.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1006
    }
      w998
    }
      w996
    }
    w995
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
    { val ps_1007 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1007.length() > 0) and isDone(ps_1007[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1008 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1009 = if ((ps_1008.length() > 0)) {
      val w1010 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_1008[0].closeResultId }) }
      val w1011 = { ...w1010, inc: w1010.inc.set(iid, { ...w1010.inc.get(iid), closeCauseId: ps_1008[0].closeCauseId }) }
      val w1012 = { ...w1011, inc: w1011.inc.set(iid, { ...w1011.inc.get(iid), closeCauseLabel: ps_1008[0].closeCauseLabel }) }
      val w1013 = { ...w1012, inc: w1012.inc.set(iid, { ...w1012.inc.get(iid), result: ps_1008[0].result }) }
      val w1014 = { ...w1013, inc: w1013.inc.set(iid, { ...w1013.inc.get(iid), closedBy: ps_1008[0].closedBy }) }
      val w1015 = { ...w1014, inc: w1014.inc.set(iid, { ...w1014.inc.get(iid), owner: ps_1008[0].closedBy }) }
      w1015
    } else w0
    w1009
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w1016 = if (not(timerDef("resolution").pausable)) {
      val w1017 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1018 = { ...w1017, inc: w1017.inc.set(iid, { ...w1017.inc.get(iid), timers: w1017.inc.get(iid).timers.set("resolution", { ...w1017.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w1018
    } else {
      val w1019 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w1020 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w1021 = { ...w1020, inc: w1020.inc.set(iid, { ...w1020.inc.get(iid), timers: w1020.inc.get(iid).timers.set("resolution", { ...w1020.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1022 = { ...w1021, inc: w1021.inc.set(iid, { ...w1021.inc.get(iid), timers: w1021.inc.get(iid).timers.set("resolution", { ...w1021.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w1022
    } else w0
      w1019
    }
    w1016
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_1023 = c.now
    val w1024 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_1023 }) }
    w1024
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {
    val w1025 = if (["false_alarm"].foldl(false, (acc, y1026) => acc or y1026 == w0.inc.get(iid).closeResultId)) {
      val w1027 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1031 => not(isDone(x_1031))).foldl([], (acc, x1030) => acc.append(x1030.id)).foldl(w0, (wf1028, sId1029) => wf1028)
      w1027
    } else w0
    w1025
  }

  def e_close_linked_5(w0: World, c: Ctx, iid: str): World = {
    val w1032 = if (["false_alarm"].foldl(false, (acc, y1033) => acc or y1033 == w0.inc.get(iid).closeResultId)) {
      val w1034 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1041 => not(isDone(x_1041))).foldl([], (acc, x1037) => acc.append(x1037.id)).foldl(w0, (wf1035, sId1036) => {
      val lead_1038 = (if ((wf1035.inc.get(sId1036).linkedTo != "")) { val ps_1039 = incidentById(incs(w0), wf1035.inc.get(sId1036).linkedTo)  (if (((ps_1039.length() > 0) and not(isDone(ps_1039[0])))) addressee(ps_1039[0]) else "") } else addressee(wf1035.inc.get(sId1036)))
      val w1040 = if (((lead_1038 != "") and (lead_1038 != wf1035.inc.get(iid).closedBy))) wf1035 else wf1035
      w1040
    })
      w1034
    } else w0
    w1032
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
    { val ps_1042 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_1043 = (if (((ps_1042.length() > 0) and not(isDone(ps_1042[0])))) addressee(ps_1042[0]) else "")  ((who_1043 != "") and (hasAccess(who_1043, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1044 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1045 = if (((ps_1044.length() > 0) and (leftOf(ps_1044[0], "resolution", c.now) >= 0))) {
      val w1046 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1047 = { ...w1046, inc: w1046.inc.set(iid, { ...w1046.inc.get(iid), timers: w1046.inc.get(iid).timers.set("resolution", { ...w1046.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1044[0], "resolution", c.now) }) }) }
      val w1048 = { ...w1047, inc: w1047.inc.set(iid, { ...w1047.inc.get(iid), timers: w1047.inc.get(iid).timers.set("resolution", { ...w1047.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1049 = if ((leftOf(ps_1044[0], "resolution", c.now) == 0)) {
      val w1050 = { ...w1048, inc: w1048.inc.set(iid, { ...w1048.inc.get(iid), timers: w1048.inc.get(iid).timers.set("resolution", { ...w1048.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1044[0], "resolution", c.now)) ps_1044[0].timers.get("resolution").fired else ps_1044[0].timers.get("resolution").due) }) }) }
      w1050
    } else w1048
      w1049
    } else w0
    w1045
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w1051 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1052 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1053 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1054 = { ...w1053, inc: w1053.inc.set(iid, { ...w1053.inc.get(iid), linkedTo: "" }) }
      val w1055 = { ...w1054, inc: w1054.inc.set(iid, { ...w1054.inc.get(iid), linkedAt: 0 }) }
      val w1056 = if (((ps_1052.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w1055 else w1055
      val w1057 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w1058 = ps_1052.foldl([], (acc, x1061) => acc.append(x1061.id)).foldl(w1056, (wf1059, pId1060) => wf1059)
      w1058
    } else w1056
      w1057
    } else {
      val w1062 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1063 = { ...w1062, inc: w1062.inc.set(iid, { ...w1062.inc.get(iid), linkedAt: 0 }) }
      w1063
    }
    w1051
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w1064 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1065 = if (timerDef("reaction").startsOnce) {
      val w1066 = ec_resumeTimer(w0, c, iid, "reaction")
      w1066
    } else {
      val w1067 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1068 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1069 = { ...w1068, inc: w1068.inc.set(iid, { ...w1068.inc.get(iid), timers: w1068.inc.get(iid).timers.set("reaction", { ...w1068.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1070 = { ...w1069, inc: w1069.inc.set(iid, { ...w1069.inc.get(iid), timers: w1069.inc.get(iid).timers.set("reaction", { ...w1069.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1070
    } else {
      val sec_1071 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w1072 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1071 < 0)) 0 else (c.now + (sec_1071 * 1000))) }) }) }
      val w1073 = { ...w1072, inc: w1072.inc.set(iid, { ...w1072.inc.get(iid), timers: w1072.inc.get(iid).timers.set("reaction", { ...w1072.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1074 = { ...w1073, inc: w1073.inc.set(iid, { ...w1073.inc.get(iid), timers: w1073.inc.get(iid).timers.set("reaction", { ...w1073.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1075 = { ...w1074, inc: w1074.inc.set(iid, { ...w1074.inc.get(iid), timers: w1074.inc.get(iid).timers.set("reaction", { ...w1074.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1075
    }
      w1067
    }
      w1065
    }
    w1064
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_1076 = settings.alerts.target
    val w1077 = if (((whom_1076 != "") and (whom_1076 != c.actor))) w0 else w0
    w1077
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
      settings.holdReasons.foldl(false, (acc, r_1078) => acc or ((r_1078.id == c.form.reasonId) and (r_1078.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_1079) => acc and (isDone(e_1079) or hasAccess(c.form.targetId, e_1079))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_1080) => acc or (i_1080.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_1081) => acc or ((i_1081.id == c.form.resultId) and stepsOk(i_1081, world.inc.get(iid)))),
    },
    c.form.causeId == "" or all {
      settings.closeResults.foldl(false, (acc, i_1082) => acc or ((i_1082.id == c.form.resultId) and (i_1082.causeCatalog != ""))),
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
    ["in_progress"].foldl(false, (acc, y1083) => acc or y1083 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_1084) => acc or ((s_1084.id == agentState(c.me)) and s_1084.readOnly))),
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
