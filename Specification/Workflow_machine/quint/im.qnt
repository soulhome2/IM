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


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, closeCauseLabel: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], priorityManual: bool, timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str, eventGuid: str }

  type Timer = { due: int, paused: bool, left: int, fired: int, since: int }

  type Breach = { kind: str, at: int, owner: str }

  type LeftGroup = { primaryId: str, linkedAt: int, at: int }

  type Form = { targetId: str, primaryId: str, resultId: str, reasonId: str, causeId: str, comment: str, files: List[FormFile], priority: str }

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

  type Event = { guid: str, eventType: str, device: str, deviceType: str }

  type Condition = { eventType: List[str], device: List[str], deviceType: List[str], group: List[str] }

  type Rule = { guid: str, active: bool, priority: int, createdAt: int, scenarios: List[str], conditions: List[Condition] }

  type Settings = { limits: Limits, session: Session, escalation: Escalation, alerts: Alerts, states: List[State], closeResults: List[CloseResultItem], timerDefs: List[TimerDef], holdReasons: List[HoldReason], causeCatalogs: str -> CauseCatalog }


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

  pure val TYPICAL_PERMISSION_SETS: Set[Set[str]] = Set(Set("incident:claim", "incident:accept", "incident:hold", "incident:release", "incident:close", "incident:transfer:own", "incident:bulk", "incident:run_action", "incident:comment", "agent:set_not_ready"), Set("incident:claim", "incident:accept", "incident:hold", "incident:release", "incident:close", "incident:close:unprocessed", "incident:reopen", "incident:transfer:own", "incident:transfer:any", "incident:reassign", "incident:bulk", "incident:run_action", "incident:comment", "incident:priority", "agent:set_not_ready"))

  pure val STEP_RESULT_IDS: Set[str] = Set("processed")

  pure val STEP_RESULT_CLOSE_IDS: Set[str] = Set("close")

  pure val EXIT_RULE: { appliesTo: Set[str], requiresAnyOf: Set[str], requiresAnyOfWithHoldLimit: Set[str], disables: Set[str] } = { appliesTo: Set("incident:claim", "incident:accept"), requiresAnyOf: Set("incident:hold", "incident:release", "incident:close"), requiresAnyOfWithHoldLimit: Set("incident:release", "incident:close"), disables: Set("incident:claim", "incident:accept") }

  pure val USED_PERMISSIONS: Set[str] = Set("agent:set_not_ready", "incident:accept", "incident:bulk", "incident:claim", "incident:close", "incident:close:unprocessed", "incident:comment", "incident:hold", "incident:priority", "incident:reassign", "incident:release", "incident:reopen", "incident:run_action", "incident:transfer:any", "incident:transfer:own")

  pure val TIMER_IDS: Set[str] = Set("reaction", "resolution", "hold")

  pure val NO_TIMER: Timer = { due: 0, paused: false, left: 0, fired: 0, since: 0 }

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", closeCauseLabel: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], priorityManual: false, timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "", eventGuid: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

  pure val NO_FORM: Form = { targetId: "", primaryId: "", resultId: "", reasonId: "", causeId: "", comment: "", files: [], priority: "" }

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

  // §14.5, ARCH-15. Правило-победитель сценария s для события: из подошедших правил с этим сценарием — те, кого не старше ни одно; сервер берёт первое по порядку списка — rules упорядочены по intake.ruleOrder. От него приоритет и ruleGuid инцидента

  def ruleFor(rules: List[Rule], e: Event, s: str): List[Rule] =
    { val ms_78 = rules.select(r_79 => (ruleMatches(r_79, e) and r_79.scenarios.foldl(false, (acc, y80) => acc or y80 == s)))  ms_78.select(r_81 => not(ms_78.foldl(false, (acc, o_82) => acc or ruleBeats(o_82, r_81, e)))) }

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_83 => (e_83.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_84 => ((e_84.id != p.id) and inGroupAt(e_84, p, at)))

  // §14.5, ARCH-15. Соседи — инциденты того же события, кроме самого x: другие службы той же тревоги. Не привязка §11: у каждого свой владелец, сроки и закрытие

  def siblingsOf(incidents: List[Incident], x: Incident): List[Incident] =
    incidents.select(s_85 => (((x.eventGuid != "") and (s_85.eventGuid == x.eventGuid)) and (s_85.id != x.id)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w86 = if (not(timerDef(timerId).pausable)) {
      val sec_87 = timerSec(w0.inc.get(iid), timerId, "")
      val w88 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_87 < 0)) 0 else (c.now + (sec_87 * 1000))) }) }) }
      val w89 = { ...w88, inc: w88.inc.set(iid, { ...w88.inc.get(iid), timers: w88.inc.get(iid).timers.set(timerId, { ...w88.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w89
    } else {
      val w90 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_91 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w92 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_91 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_91)) }) }) }
      val w93 = { ...w92, inc: w92.inc.set(iid, { ...w92.inc.get(iid), timers: w92.inc.get(iid).timers.set(timerId, { ...w92.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w94 = { ...w93, inc: w93.inc.set(iid, { ...w93.inc.get(iid), timers: w93.inc.get(iid).timers.set(timerId, { ...w93.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w94
    } else w0
      w90
    }
    w86
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w95 = if (not(timerDef(timerId).pausable)) {
      val w96 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w97 = { ...w96, inc: w96.inc.set(iid, { ...w96.inc.get(iid), timers: w96.inc.get(iid).timers.set(timerId, { ...w96.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w97
    } else {
      val w98 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w99 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w100 = { ...w99, inc: w99.inc.set(iid, { ...w99.inc.get(iid), timers: w99.inc.get(iid).timers.set(timerId, { ...w99.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w101 = { ...w100, inc: w100.inc.set(iid, { ...w100.inc.get(iid), timers: w100.inc.get(iid).timers.set(timerId, { ...w100.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w101
    } else w0
      w98
    }
    w95
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_102 = ""
    val w103 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_102 }) }
    w103
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_104 = ""
    val w105 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_104 }) }
    w105
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_106 = 0
    val w107 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_106 }) }
    w107
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w108 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w109 = if (timerDef("reaction").startsOnce) {
      val w110 = ec_resumeTimer(w0, c, iid, "reaction")
      w110
    } else {
      val w111 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w112 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w113 = { ...w112, inc: w112.inc.set(iid, { ...w112.inc.get(iid), timers: w112.inc.get(iid).timers.set("reaction", { ...w112.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w114 = { ...w113, inc: w113.inc.set(iid, { ...w113.inc.get(iid), timers: w113.inc.get(iid).timers.set("reaction", { ...w113.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w114
    } else {
      val sec_115 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w116 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_115 < 0)) 0 else (c.now + (sec_115 * 1000))) }) }) }
      val w117 = { ...w116, inc: w116.inc.set(iid, { ...w116.inc.get(iid), timers: w116.inc.get(iid).timers.set("reaction", { ...w116.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w118 = { ...w117, inc: w117.inc.set(iid, { ...w117.inc.get(iid), timers: w117.inc.get(iid).timers.set("reaction", { ...w117.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w119 = { ...w118, inc: w118.inc.set(iid, { ...w118.inc.get(iid), timers: w118.inc.get(iid).timers.set("reaction", { ...w118.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w119
    }
      w111
    }
      w109
    }
    w108
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
    not(settings.session.states.foldl(false, (acc, s_120) => acc or ((s_120.id == agentState(c.me)) and s_120.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_121 = c.actor
    val w122 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_121 }) }
    w122
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w123 = if (timerDef("reaction").startsOnce) {
      val w124 = ec_pauseTimer(w0, c, iid, "reaction")
      w124
    } else {
      val w125 = if (false) {
      val w126 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w127 = { ...w126, inc: w126.inc.set(iid, { ...w126.inc.get(iid), timers: w126.inc.get(iid).timers.set("reaction", { ...w126.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w128 = { ...w127, inc: w127.inc.set(iid, { ...w127.inc.get(iid), timers: w127.inc.get(iid).timers.set("reaction", { ...w127.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w129 = { ...w128, inc: w128.inc.set(iid, { ...w128.inc.get(iid), timers: w128.inc.get(iid).timers.set("reaction", { ...w128.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w129
    } else {
      val w130 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_131 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w132 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_131) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w133 = { ...w132, inc: w132.inc.set(iid, { ...w132.inc.get(iid), timers: w132.inc.get(iid).timers.set("reaction", { ...w132.inc.get(iid).timers.get("reaction"), paused: keep_131 }) }) }
      val w134 = { ...w133, inc: w133.inc.set(iid, { ...w133.inc.get(iid), timers: w133.inc.get(iid).timers.set("reaction", { ...w133.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w135 = { ...w134, inc: w134.inc.set(iid, { ...w134.inc.get(iid), timers: w134.inc.get(iid).timers.set("reaction", { ...w134.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w135
    }
      w130
    }
      w125
    }
    w123
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w136 = if (not(timerDef("resolution").pausable)) {
      val sec_137 = timerSec(w0.inc.get(iid), "resolution", "")
      val w138 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_137 < 0)) 0 else (c.now + (sec_137 * 1000))) }) }) }
      val w139 = { ...w138, inc: w138.inc.set(iid, { ...w138.inc.get(iid), timers: w138.inc.get(iid).timers.set("resolution", { ...w138.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w139
    } else {
      val w140 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_141 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w142 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_141 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_141)) }) }) }
      val w143 = { ...w142, inc: w142.inc.set(iid, { ...w142.inc.get(iid), timers: w142.inc.get(iid).timers.set("resolution", { ...w142.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w144 = { ...w143, inc: w143.inc.set(iid, { ...w143.inc.get(iid), timers: w143.inc.get(iid).timers.set("resolution", { ...w143.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w144
    } else w0
      w140
    }
    w136
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
    not(settings.session.states.foldl(false, (acc, s_145) => acc or ((s_145.id == agentState(c.me)) and s_145.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_146 = c.actor
    val w147 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_146 }) }
    w147
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_148 = ""
    val w149 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_148 }) }
    w149
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w150 = if (timerDef("reaction").startsOnce) {
      val w151 = ec_pauseTimer(w0, c, iid, "reaction")
      w151
    } else {
      val w152 = if (false) {
      val w153 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w154 = { ...w153, inc: w153.inc.set(iid, { ...w153.inc.get(iid), timers: w153.inc.get(iid).timers.set("reaction", { ...w153.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w155 = { ...w154, inc: w154.inc.set(iid, { ...w154.inc.get(iid), timers: w154.inc.get(iid).timers.set("reaction", { ...w154.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w156 = { ...w155, inc: w155.inc.set(iid, { ...w155.inc.get(iid), timers: w155.inc.get(iid).timers.set("reaction", { ...w155.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w156
    } else {
      val w157 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_158 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w159 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_158) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w160 = { ...w159, inc: w159.inc.set(iid, { ...w159.inc.get(iid), timers: w159.inc.get(iid).timers.set("reaction", { ...w159.inc.get(iid).timers.get("reaction"), paused: keep_158 }) }) }
      val w161 = { ...w160, inc: w160.inc.set(iid, { ...w160.inc.get(iid), timers: w160.inc.get(iid).timers.set("reaction", { ...w160.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w162 = { ...w161, inc: w161.inc.set(iid, { ...w161.inc.get(iid), timers: w161.inc.get(iid).timers.set("reaction", { ...w161.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w162
    }
      w157
    }
      w152
    }
    w150
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w163 = if (not(timerDef("resolution").pausable)) {
      val sec_164 = timerSec(w0.inc.get(iid), "resolution", "")
      val w165 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_164 < 0)) 0 else (c.now + (sec_164 * 1000))) }) }) }
      val w166 = { ...w165, inc: w165.inc.set(iid, { ...w165.inc.get(iid), timers: w165.inc.get(iid).timers.set("resolution", { ...w165.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w166
    } else {
      val w167 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_168 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w169 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_168 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_168)) }) }) }
      val w170 = { ...w169, inc: w169.inc.set(iid, { ...w169.inc.get(iid), timers: w169.inc.get(iid).timers.set("resolution", { ...w169.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w171 = { ...w170, inc: w170.inc.set(iid, { ...w170.inc.get(iid), timers: w170.inc.get(iid).timers.set("resolution", { ...w170.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w171
    } else w0
      w167
    }
    w163
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
    not(settings.session.states.foldl(false, (acc, s_172) => acc or ((s_172.id == agentState(c.me)) and s_172.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_173 = ""
    val w174 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_173 }) }
    w174
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_175 = ""
    val w176 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_175 }) }
    w176
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
    not(settings.session.states.foldl(false, (acc, s_177) => acc or ((s_177.id == agentState(c.me)) and s_177.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_178 = c.form.reasonId
    val w179 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_178 }) }
    w179
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w180 = if (not(timerDef("resolution").pausable)) {
      val w181 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w182 = { ...w181, inc: w181.inc.set(iid, { ...w181.inc.get(iid), timers: w181.inc.get(iid).timers.set("resolution", { ...w181.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w182
    } else {
      val w183 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w184 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w185 = { ...w184, inc: w184.inc.set(iid, { ...w184.inc.get(iid), timers: w184.inc.get(iid).timers.set("resolution", { ...w184.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w186 = { ...w185, inc: w185.inc.set(iid, { ...w185.inc.get(iid), timers: w185.inc.get(iid).timers.set("resolution", { ...w185.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w186
    } else w0
      w183
    }
    w180
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w187 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w188 = if (timerDef("hold").startsOnce) {
      val w189 = ec_resumeTimer(w0, c, iid, "hold")
      w189
    } else {
      val w190 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w191 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w192 = { ...w191, inc: w191.inc.set(iid, { ...w191.inc.get(iid), timers: w191.inc.get(iid).timers.set("hold", { ...w191.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w193 = { ...w192, inc: w192.inc.set(iid, { ...w192.inc.get(iid), timers: w192.inc.get(iid).timers.set("hold", { ...w192.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w193
    } else {
      val sec_194 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w195 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_194 < 0)) 0 else (c.now + (sec_194 * 1000))) }) }) }
      val w196 = { ...w195, inc: w195.inc.set(iid, { ...w195.inc.get(iid), timers: w195.inc.get(iid).timers.set("hold", { ...w195.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w197 = { ...w196, inc: w196.inc.set(iid, { ...w196.inc.get(iid), timers: w196.inc.get(iid).timers.set("hold", { ...w196.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w198 = { ...w197, inc: w197.inc.set(iid, { ...w197.inc.get(iid), timers: w197.inc.get(iid).timers.set("hold", { ...w197.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w198
    }
      w190
    }
      w188
    }
    w187
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
    not(settings.session.states.foldl(false, (acc, s_199) => acc or ((s_199.id == agentState(c.me)) and s_199.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w200 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w200
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w201 = if (timerDef("hold").startsOnce) {
      val w202 = ec_pauseTimer(w0, c, iid, "hold")
      w202
    } else {
      val w203 = if (false) {
      val w204 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w205 = { ...w204, inc: w204.inc.set(iid, { ...w204.inc.get(iid), timers: w204.inc.get(iid).timers.set("hold", { ...w204.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w206 = { ...w205, inc: w205.inc.set(iid, { ...w205.inc.get(iid), timers: w205.inc.get(iid).timers.set("hold", { ...w205.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w207 = { ...w206, inc: w206.inc.set(iid, { ...w206.inc.get(iid), timers: w206.inc.get(iid).timers.set("hold", { ...w206.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w207
    } else {
      val w208 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_209 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w210 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_209) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w211 = { ...w210, inc: w210.inc.set(iid, { ...w210.inc.get(iid), timers: w210.inc.get(iid).timers.set("hold", { ...w210.inc.get(iid).timers.get("hold"), paused: keep_209 }) }) }
      val w212 = { ...w211, inc: w211.inc.set(iid, { ...w211.inc.get(iid), timers: w211.inc.get(iid).timers.set("hold", { ...w211.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w213 = { ...w212, inc: w212.inc.set(iid, { ...w212.inc.get(iid), timers: w212.inc.get(iid).timers.set("hold", { ...w212.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w213
    }
      w208
    }
      w203
    }
    w201
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w214 = if (not(timerDef("resolution").pausable)) {
      val sec_215 = timerSec(w0.inc.get(iid), "resolution", "")
      val w216 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_215 < 0)) 0 else (c.now + (sec_215 * 1000))) }) }) }
      val w217 = { ...w216, inc: w216.inc.set(iid, { ...w216.inc.get(iid), timers: w216.inc.get(iid).timers.set("resolution", { ...w216.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w217
    } else {
      val w218 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_219 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w220 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_219 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_219)) }) }) }
      val w221 = { ...w220, inc: w220.inc.set(iid, { ...w220.inc.get(iid), timers: w220.inc.get(iid).timers.set("resolution", { ...w220.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w222 = { ...w221, inc: w221.inc.set(iid, { ...w221.inc.get(iid), timers: w221.inc.get(iid).timers.set("resolution", { ...w221.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w222
    } else w0
      w218
    }
    w214
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
    not(settings.session.states.foldl(false, (acc, s_223) => acc or ((s_223.id == agentState(c.me)) and s_223.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_224 = ""
    val w225 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_224 }) }
    w225
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w226 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w226
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w227 = if (not(timerDef("resolution").pausable)) {
      val w228 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w229 = { ...w228, inc: w228.inc.set(iid, { ...w228.inc.get(iid), timers: w228.inc.get(iid).timers.set("resolution", { ...w228.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w229
    } else {
      val w230 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w231 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w232 = { ...w231, inc: w231.inc.set(iid, { ...w231.inc.get(iid), timers: w231.inc.get(iid).timers.set("resolution", { ...w231.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w233 = { ...w232, inc: w232.inc.set(iid, { ...w232.inc.get(iid), timers: w232.inc.get(iid).timers.set("resolution", { ...w232.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w233
    } else w0
      w230
    }
    w227
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w234 = if (timerDef("hold").startsOnce) {
      val w235 = ec_pauseTimer(w0, c, iid, "hold")
      w235
    } else {
      val w236 = if (false) {
      val w237 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w238 = { ...w237, inc: w237.inc.set(iid, { ...w237.inc.get(iid), timers: w237.inc.get(iid).timers.set("hold", { ...w237.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w239 = { ...w238, inc: w238.inc.set(iid, { ...w238.inc.get(iid), timers: w238.inc.get(iid).timers.set("hold", { ...w238.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w240 = { ...w239, inc: w239.inc.set(iid, { ...w239.inc.get(iid), timers: w239.inc.get(iid).timers.set("hold", { ...w239.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w240
    } else {
      val w241 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_242 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w243 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_242) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w244 = { ...w243, inc: w243.inc.set(iid, { ...w243.inc.get(iid), timers: w243.inc.get(iid).timers.set("hold", { ...w243.inc.get(iid).timers.get("hold"), paused: keep_242 }) }) }
      val w245 = { ...w244, inc: w244.inc.set(iid, { ...w244.inc.get(iid), timers: w244.inc.get(iid).timers.set("hold", { ...w244.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w246 = { ...w245, inc: w245.inc.set(iid, { ...w245.inc.get(iid), timers: w245.inc.get(iid).timers.set("hold", { ...w245.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w246
    }
      w241
    }
      w236
    }
    w234
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w247 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w248 = if (timerDef("reaction").startsOnce) {
      val w249 = ec_resumeTimer(w0, c, iid, "reaction")
      w249
    } else {
      val w250 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w251 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w252 = { ...w251, inc: w251.inc.set(iid, { ...w251.inc.get(iid), timers: w251.inc.get(iid).timers.set("reaction", { ...w251.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w253 = { ...w252, inc: w252.inc.set(iid, { ...w252.inc.get(iid), timers: w252.inc.get(iid).timers.set("reaction", { ...w252.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w253
    } else {
      val sec_254 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w255 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_254 < 0)) 0 else (c.now + (sec_254 * 1000))) }) }) }
      val w256 = { ...w255, inc: w255.inc.set(iid, { ...w255.inc.get(iid), timers: w255.inc.get(iid).timers.set("reaction", { ...w255.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w257 = { ...w256, inc: w256.inc.set(iid, { ...w256.inc.get(iid), timers: w256.inc.get(iid).timers.set("reaction", { ...w256.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w258 = { ...w257, inc: w257.inc.set(iid, { ...w257.inc.get(iid), timers: w257.inc.get(iid).timers.set("reaction", { ...w257.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w258
    }
      w250
    }
      w248
    }
    w247
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
    not(settings.session.states.foldl(false, (acc, s_259) => acc or ((s_259.id == agentState(c.me)) and s_259.readOnly))),
    transferTargets.foldl(false, (acc, t_260) => acc or (offersTransferTo(c.me, t_260, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_261) => acc and (isDone(e_261) or hasAccess(t_260, e_261))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_262) => acc and (isDone(e_262) or hasAccess(c.form.targetId, e_262)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_263 = personOf(c.form.targetId)
    val w264 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_263 }) }
    w264
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_265 = groupOf(c.form.targetId)
    val w266 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_265 }) }
    w266
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w267 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w267
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w268 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w268
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w269 = if (not(timerDef("resolution").pausable)) {
      val w270 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w271 = { ...w270, inc: w270.inc.set(iid, { ...w270.inc.get(iid), timers: w270.inc.get(iid).timers.set("resolution", { ...w270.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w271
    } else {
      val w272 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w273 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w274 = { ...w273, inc: w273.inc.set(iid, { ...w273.inc.get(iid), timers: w273.inc.get(iid).timers.set("resolution", { ...w273.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w275 = { ...w274, inc: w274.inc.set(iid, { ...w274.inc.get(iid), timers: w274.inc.get(iid).timers.set("resolution", { ...w274.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w275
    } else w0
      w272
    }
    w269
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w276 = if (timerDef("hold").startsOnce) {
      val w277 = ec_pauseTimer(w0, c, iid, "hold")
      w277
    } else {
      val w278 = if (false) {
      val w279 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w280 = { ...w279, inc: w279.inc.set(iid, { ...w279.inc.get(iid), timers: w279.inc.get(iid).timers.set("hold", { ...w279.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w281 = { ...w280, inc: w280.inc.set(iid, { ...w280.inc.get(iid), timers: w280.inc.get(iid).timers.set("hold", { ...w280.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w282 = { ...w281, inc: w281.inc.set(iid, { ...w281.inc.get(iid), timers: w281.inc.get(iid).timers.set("hold", { ...w281.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w282
    } else {
      val w283 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_284 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w285 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_284) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w286 = { ...w285, inc: w285.inc.set(iid, { ...w285.inc.get(iid), timers: w285.inc.get(iid).timers.set("hold", { ...w285.inc.get(iid).timers.get("hold"), paused: keep_284 }) }) }
      val w287 = { ...w286, inc: w286.inc.set(iid, { ...w286.inc.get(iid), timers: w286.inc.get(iid).timers.set("hold", { ...w286.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w288 = { ...w287, inc: w287.inc.set(iid, { ...w287.inc.get(iid), timers: w287.inc.get(iid).timers.set("hold", { ...w287.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w288
    }
      w283
    }
      w278
    }
    w276
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w289 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w290 = if (timerDef("reaction").startsOnce) {
      val w291 = ec_resumeTimer(w0, c, iid, "reaction")
      w291
    } else {
      val w292 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w293 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w294 = { ...w293, inc: w293.inc.set(iid, { ...w293.inc.get(iid), timers: w293.inc.get(iid).timers.set("reaction", { ...w293.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w295 = { ...w294, inc: w294.inc.set(iid, { ...w294.inc.get(iid), timers: w294.inc.get(iid).timers.set("reaction", { ...w294.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w295
    } else {
      val sec_296 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w297 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_296 < 0)) 0 else (c.now + (sec_296 * 1000))) }) }) }
      val w298 = { ...w297, inc: w297.inc.set(iid, { ...w297.inc.get(iid), timers: w297.inc.get(iid).timers.set("reaction", { ...w297.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w299 = { ...w298, inc: w298.inc.set(iid, { ...w298.inc.get(iid), timers: w298.inc.get(iid).timers.set("reaction", { ...w298.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w300 = { ...w299, inc: w299.inc.set(iid, { ...w299.inc.get(iid), timers: w299.inc.get(iid).timers.set("reaction", { ...w299.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w300
    }
      w292
    }
      w290
    }
    w289
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_301 = c.before.owner
    val w302 = if (((whom_301 != "") and (whom_301 != c.actor))) w0 else w0
    w302
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_303 = addressee(w0.inc.get(iid))
    val w304 = if (((whom_303 != "") and (whom_303 != c.actor))) w0 else w0
    w304
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
    not(settings.session.states.foldl(false, (acc, s_305) => acc or ((s_305.id == agentState(c.me)) and s_305.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_306 = c.actor
    val w307 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_306 }) }
    w307
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_308 = ""
    val w309 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_308 }) }
    w309
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w310 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w310
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w311 = if (timerDef("reaction").startsOnce) {
      val w312 = ec_pauseTimer(w0, c, iid, "reaction")
      w312
    } else {
      val w313 = if (false) {
      val w314 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w315 = { ...w314, inc: w314.inc.set(iid, { ...w314.inc.get(iid), timers: w314.inc.get(iid).timers.set("reaction", { ...w314.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w316 = { ...w315, inc: w315.inc.set(iid, { ...w315.inc.get(iid), timers: w315.inc.get(iid).timers.set("reaction", { ...w315.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w317 = { ...w316, inc: w316.inc.set(iid, { ...w316.inc.get(iid), timers: w316.inc.get(iid).timers.set("reaction", { ...w316.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w317
    } else {
      val w318 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_319 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w320 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_319) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w321 = { ...w320, inc: w320.inc.set(iid, { ...w320.inc.get(iid), timers: w320.inc.get(iid).timers.set("reaction", { ...w320.inc.get(iid).timers.get("reaction"), paused: keep_319 }) }) }
      val w322 = { ...w321, inc: w321.inc.set(iid, { ...w321.inc.get(iid), timers: w321.inc.get(iid).timers.set("reaction", { ...w321.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w323 = { ...w322, inc: w322.inc.set(iid, { ...w322.inc.get(iid), timers: w322.inc.get(iid).timers.set("reaction", { ...w322.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w323
    }
      w318
    }
      w313
    }
    w311
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w324 = if (timerDef("hold").startsOnce) {
      val w325 = ec_pauseTimer(w0, c, iid, "hold")
      w325
    } else {
      val w326 = if (false) {
      val w327 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w328 = { ...w327, inc: w327.inc.set(iid, { ...w327.inc.get(iid), timers: w327.inc.get(iid).timers.set("hold", { ...w327.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w329 = { ...w328, inc: w328.inc.set(iid, { ...w328.inc.get(iid), timers: w328.inc.get(iid).timers.set("hold", { ...w328.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w330 = { ...w329, inc: w329.inc.set(iid, { ...w329.inc.get(iid), timers: w329.inc.get(iid).timers.set("hold", { ...w329.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w330
    } else {
      val w331 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_332 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w333 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_332) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w334 = { ...w333, inc: w333.inc.set(iid, { ...w333.inc.get(iid), timers: w333.inc.get(iid).timers.set("hold", { ...w333.inc.get(iid).timers.get("hold"), paused: keep_332 }) }) }
      val w335 = { ...w334, inc: w334.inc.set(iid, { ...w334.inc.get(iid), timers: w334.inc.get(iid).timers.set("hold", { ...w334.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w336 = { ...w335, inc: w335.inc.set(iid, { ...w335.inc.get(iid), timers: w335.inc.get(iid).timers.set("hold", { ...w335.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w336
    }
      w331
    }
      w326
    }
    w324
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w337 = if (not(timerDef("resolution").pausable)) {
      val sec_338 = timerSec(w0.inc.get(iid), "resolution", "")
      val w339 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_338 < 0)) 0 else (c.now + (sec_338 * 1000))) }) }) }
      val w340 = { ...w339, inc: w339.inc.set(iid, { ...w339.inc.get(iid), timers: w339.inc.get(iid).timers.set("resolution", { ...w339.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w340
    } else {
      val w341 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_342 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w343 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_342 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_342)) }) }) }
      val w344 = { ...w343, inc: w343.inc.set(iid, { ...w343.inc.get(iid), timers: w343.inc.get(iid).timers.set("resolution", { ...w343.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w345 = { ...w344, inc: w344.inc.set(iid, { ...w344.inc.get(iid), timers: w344.inc.get(iid).timers.set("resolution", { ...w344.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w345
    } else w0
      w341
    }
    w337
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
    val whom_346 = c.before.owner
    val w347 = if (((whom_346 != "") and (whom_346 != c.actor))) w0 else w0
    w347
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
    not(settings.session.states.foldl(false, (acc, s_348) => acc or ((s_348.id == agentState(c.me)) and s_348.readOnly))),
    { val os_349 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_349.foldl(false, (acc, o_350) => acc or ((o_350.id == c.form.resultId) and stepsOk(o_350, world.inc.get(iid)))) else os_349.foldl(false, (acc, o_351) => acc or stepsOk(o_351, world.inc.get(iid)))) },
    ((((c.form.resultId == "") or (c.form.causeId == "")) or not(settings.closeResults.foldl(false, (acc, i_352) => acc or ((i_352.id == c.form.resultId) and (i_352.causeCatalog != ""))))) or (causeOk(c.form.resultId, c.form.causeId) and (not(causeCommentRequired(c.form.resultId, c.form.causeId)) or (c.form.comment != "")))),
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_353 = c.actor
    val w354 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_353 }) }
    w354
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_355 = ""
    val w356 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_355 }) }
    w356
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_357 = c.actor
    val w358 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_357 }) }
    w358
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_359 = c.now
    val w360 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_359 }) }
    w360
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_361 = c.form.resultId
    val w362 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_361 }) }
    w362
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_363 = (if (causeOk(c.form.resultId, c.form.causeId)) c.form.causeId else "")
    val w364 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_363 }) }
    w364
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_365 = causeLabel(c.form.resultId, c.form.causeId)
    val w366 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_365 }) }
    w366
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val value_367 = c.form.comment
    val w368 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_367 }) }
    w368
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w369 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w369
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w370 = if (timerDef("reaction").startsOnce) {
      val w371 = ec_pauseTimer(w0, c, iid, "reaction")
      w371
    } else {
      val w372 = if (true) {
      val w373 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w374 = { ...w373, inc: w373.inc.set(iid, { ...w373.inc.get(iid), timers: w373.inc.get(iid).timers.set("reaction", { ...w373.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w375 = { ...w374, inc: w374.inc.set(iid, { ...w374.inc.get(iid), timers: w374.inc.get(iid).timers.set("reaction", { ...w374.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w376 = { ...w375, inc: w375.inc.set(iid, { ...w375.inc.get(iid), timers: w375.inc.get(iid).timers.set("reaction", { ...w375.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w376
    } else {
      val w377 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_378 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w379 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_378) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w380 = { ...w379, inc: w379.inc.set(iid, { ...w379.inc.get(iid), timers: w379.inc.get(iid).timers.set("reaction", { ...w379.inc.get(iid).timers.get("reaction"), paused: keep_378 }) }) }
      val w381 = { ...w380, inc: w380.inc.set(iid, { ...w380.inc.get(iid), timers: w380.inc.get(iid).timers.set("reaction", { ...w380.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w382 = { ...w381, inc: w381.inc.set(iid, { ...w381.inc.get(iid), timers: w381.inc.get(iid).timers.set("reaction", { ...w381.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w382
    }
      w377
    }
      w372
    }
    w370
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w383 = if (not(timerDef("resolution").pausable)) {
      val w384 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w385 = { ...w384, inc: w384.inc.set(iid, { ...w384.inc.get(iid), timers: w384.inc.get(iid).timers.set("resolution", { ...w384.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w385
    } else {
      val w386 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w387 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w388 = { ...w387, inc: w387.inc.set(iid, { ...w387.inc.get(iid), timers: w387.inc.get(iid).timers.set("resolution", { ...w387.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w389 = { ...w388, inc: w388.inc.set(iid, { ...w388.inc.get(iid), timers: w388.inc.get(iid).timers.set("resolution", { ...w388.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w389
    } else w0
      w386
    }
    w383
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {
    val w390 = if (timerDef("hold").startsOnce) {
      val w391 = ec_pauseTimer(w0, c, iid, "hold")
      w391
    } else {
      val w392 = if (false) {
      val w393 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w394 = { ...w393, inc: w393.inc.set(iid, { ...w393.inc.get(iid), timers: w393.inc.get(iid).timers.set("hold", { ...w393.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w395 = { ...w394, inc: w394.inc.set(iid, { ...w394.inc.get(iid), timers: w394.inc.get(iid).timers.set("hold", { ...w394.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w396 = { ...w395, inc: w395.inc.set(iid, { ...w395.inc.get(iid), timers: w395.inc.get(iid).timers.set("hold", { ...w395.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w396
    } else {
      val w397 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_398 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w399 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_398) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w400 = { ...w399, inc: w399.inc.set(iid, { ...w399.inc.get(iid), timers: w399.inc.get(iid).timers.set("hold", { ...w399.inc.get(iid).timers.get("hold"), paused: keep_398 }) }) }
      val w401 = { ...w400, inc: w400.inc.set(iid, { ...w400.inc.get(iid), timers: w400.inc.get(iid).timers.set("hold", { ...w400.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w402 = { ...w401, inc: w401.inc.set(iid, { ...w401.inc.get(iid), timers: w401.inc.get(iid).timers.set("hold", { ...w401.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w402
    }
      w397
    }
      w392
    }
    w390
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_13(w0: World, c: Ctx, iid: str): World = {
    val w403 = if (["false_alarm"].foldl(false, (acc, y404) => acc or y404 == w0.inc.get(iid).closeResultId)) {
      val w405 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_409 => not(isDone(x_409))).foldl([], (acc, x408) => acc.append(x408.id)).foldl(w0, (wf406, sId407) => wf406)
      w405
    } else w0
    w403
  }

  def e_close_14(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_15(w0: World, c: Ctx, iid: str): World = {
    val w410 = if (["false_alarm"].foldl(false, (acc, y411) => acc or y411 == w0.inc.get(iid).closeResultId)) {
      val w412 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_419 => not(isDone(x_419))).foldl([], (acc, x415) => acc.append(x415.id)).foldl(w0, (wf413, sId414) => {
      val lead_416 = (if ((wf413.inc.get(sId414).linkedTo != "")) { val ps_417 = incidentById(incs(w0), wf413.inc.get(sId414).linkedTo)  (if (((ps_417.length() > 0) and not(isDone(ps_417[0])))) addressee(ps_417[0]) else "") } else addressee(wf413.inc.get(sId414)))
      val w418 = if (((lead_416 != "") and (lead_416 != wf413.inc.get(iid).closedBy))) wf413 else wf413
      w418
    })
      w412
    } else w0
    w410
  }

  def e_close_16(w0: World, c: Ctx, iid: str): World = {

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
    w17
  }

  // reopen: manual → in_progress

  def ok_reopen(c: Ctx, iid: str): bool = all {
    Set("closed").contains(world.inc.get(iid).state),
    can(c.me, "incident:reopen"),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_420) => acc or ((s_420.id == agentState(c.me)) and s_420.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_421 = c.actor
    val w422 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_421 }) }
    w422
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w423 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_424 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w425 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w426 = { ...w425, inc: w425.inc.set(iid, { ...w425.inc.get(iid), linkedTo: "" }) }
      val w427 = { ...w426, inc: w426.inc.set(iid, { ...w426.inc.get(iid), linkedAt: 0 }) }
      val w428 = if (((ps_424.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w427 else w427
      val w429 = if (("workflow.journal.linked_reopened" != "")) {
      val w430 = ps_424.foldl([], (acc, x433) => acc.append(x433.id)).foldl(w428, (wf431, pId432) => wf431)
      w430
    } else w428
      w429
    } else {
      val w434 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w435 = { ...w434, inc: w434.inc.set(iid, { ...w434.inc.get(iid), linkedAt: 0 }) }
      w435
    }
    w423
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_436 = ""
    val w437 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_436 }) }
    w437
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_438 = ""
    val w439 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_438 }) }
    w439
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_440 = ""
    val w441 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseLabel: value_440 }) }
    w441
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_442 = ""
    val w443 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_442 }) }
    w443
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_444 = 0
    val w445 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_444 }) }
    w445
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val value_446 = ""
    val w447 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_446 }) }
    w447
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val sec_448 = settings.limits.reopenResolutionSec
    val w449 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_448 > 0)) sec_448 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w450 = { ...w449, inc: w449.inc.set(iid, { ...w449.inc.get(iid), timers: w449.inc.get(iid).timers.set("resolution", { ...w449.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w451 = { ...w450, inc: w450.inc.set(iid, { ...w450.inc.get(iid), timers: w450.inc.get(iid).timers.set("resolution", { ...w450.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w451
  }

  def e_reopen_10(w0: World, c: Ctx, iid: str): World = {
    val w452 = if (timerDef("reaction").startsOnce) {
      val w453 = ec_pauseTimer(w0, c, iid, "reaction")
      w453
    } else {
      val w454 = if (true) {
      val w455 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w456 = { ...w455, inc: w455.inc.set(iid, { ...w455.inc.get(iid), timers: w455.inc.get(iid).timers.set("reaction", { ...w455.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w457 = { ...w456, inc: w456.inc.set(iid, { ...w456.inc.get(iid), timers: w456.inc.get(iid).timers.set("reaction", { ...w456.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w458 = { ...w457, inc: w457.inc.set(iid, { ...w457.inc.get(iid), timers: w457.inc.get(iid).timers.set("reaction", { ...w457.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w458
    } else {
      val w459 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_460 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w461 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_460) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w462 = { ...w461, inc: w461.inc.set(iid, { ...w461.inc.get(iid), timers: w461.inc.get(iid).timers.set("reaction", { ...w461.inc.get(iid).timers.get("reaction"), paused: keep_460 }) }) }
      val w463 = { ...w462, inc: w462.inc.set(iid, { ...w462.inc.get(iid), timers: w462.inc.get(iid).timers.set("reaction", { ...w462.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w464 = { ...w463, inc: w463.inc.set(iid, { ...w463.inc.get(iid), timers: w463.inc.get(iid).timers.set("reaction", { ...w463.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w464
    }
      w459
    }
      w454
    }
    w452
  }

  def e_reopen_11(w0: World, c: Ctx, iid: str): World = {

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
    w12
  }

  // comment: manual

  def ok_comment(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance", "in_progress", "on_hold", "closed", "linked").contains(world.inc.get(iid).state),
    can(c.me, "incident:comment"),
    not(settings.session.states.foldl(false, (acc, s_465) => acc or ((s_465.id == agentState(c.me)) and s_465.readOnly))),
    ((if (c.form.comment == "") 0 else 1) <= settings.limits.commentMaxLength),
    (c.form.files.length() <= settings.limits.commentMaxFiles),
    c.form.files.foldl(true, (acc, f_466) => acc and (f_466.size <= settings.limits.attachmentMaxBytes)),
    c.form.files.foldl(true, (acc, f_467) => acc and settings.limits.attachmentTypes.foldl(false, (acc, y468) => acc or y468 == f_467.mime)),
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
    not(settings.session.states.foldl(false, (acc, s_469) => acc or ((s_469.id == agentState(c.me)) and s_469.readOnly))),
    ((c.form.priority == "") or (priorityOf(c.form.priority) != world.inc.get(iid).priority)),
  }

  def e_change_priority_0(w0: World, c: Ctx, iid: str): World = {
    val value_470 = priorityOf(c.form.priority)
    val w471 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priority: value_470 }) }
    w471
  }

  def e_change_priority_1(w0: World, c: Ctx, iid: str): World = {
    val value_472 = true
    val w473 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), priorityManual: value_472 }) }
    w473
  }

  def e_change_priority_2(w0: World, c: Ctx, iid: str): World = {
    val t_474 = w0.inc.get(iid).timers.get("reaction")
    val delta_475 = ((timerSec(w0.inc.get(iid), "reaction", "byEscalationLevel") - timerSec(c.before, "reaction", "byEscalationLevel")) * 1000)
    val w476 = if ((((t_474.due != 0) and (t_474.due > c.now)) and (t_474.fired != t_474.due))) {
      val w477 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if (((t_474.due + delta_475) > c.now)) (t_474.due + delta_475) else c.now) }) }) }
      w477
    } else {
      val w478 = if ((((timerDef("reaction").pausable and (t_474.due == 0)) and t_474.paused) and (t_474.left > 0))) {
      val w479 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (((t_474.left + delta_475) > 0)) (t_474.left + delta_475) else 1) }) }) }
      w479
    } else w0
      w478
    }
    w476
  }

  def e_change_priority_3(w0: World, c: Ctx, iid: str): World = {
    val t_480 = w0.inc.get(iid).timers.get("resolution")
    val delta_481 = ((timerSec(w0.inc.get(iid), "resolution", "") - timerSec(c.before, "resolution", "")) * 1000)
    val w482 = if ((((t_480.due != 0) and (t_480.due > c.now)) and (t_480.fired != t_480.due))) {
      val w483 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((t_480.due + delta_481) > c.now)) (t_480.due + delta_481) else c.now) }) }) }
      w483
    } else {
      val w484 = if ((((timerDef("resolution").pausable and (t_480.due == 0)) and t_480.paused) and (t_480.left > 0))) {
      val w485 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((t_480.left + delta_481) > 0)) (t_480.left + delta_481) else 1) }) }) }
      w485
    } else w0
      w484
    }
    w482
  }

  def e_change_priority_4(w0: World, c: Ctx, iid: str): World = {
    val ms_486 = linkedOf(incs(w0), w0.inc.get(iid).id).select(m_487 => ((m_487.state == "linked") and not(spent(m_487, "resolution", m_487.linkedAt))))
    val w488 = if ((ms_486.length() > 0)) {
      val cs_489 = ms_486.foldl([], (acc, m_490) => acc.append((m_490.linkedAt + (if ((leftOf(m_490, "resolution", m_490.linkedAt) >= 0)) leftOf(m_490, "resolution", m_490.linkedAt) else (timerSec(m_490, "resolution", "") * 1000)))))
      val cap_491 = cs_489.select(c_492 => cs_489.foldl(true, (acc, k_493) => acc and (c_492 <= k_493)))[0]
      val t_494 = w0.inc.get(iid).timers.get("resolution")
      val w495 = if (((t_494.due != 0) and (t_494.due > cap_491))) {
      val w496 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((cap_491 > c.now)) cap_491 else c.now) }) }) }
      w496
    } else {
      val w497 = if ((((t_494.due == 0) and t_494.paused) and (t_494.left > c.before.timers.get("resolution").left))) {
      val w498 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: c.before.timers.get("resolution").left }) }) }
      w498
    } else w0
      w497
    }
      w495
    } else w0
    w488
  }

  def e_change_priority_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_change_priority(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_change_priority_0(w0, c1, iid)
    val w2 = e_change_priority_1(w1, c1, iid)
    val w3 = e_change_priority_2(w2, c1, iid)
    val w4 = e_change_priority_3(w3, c1, iid)
    val w5 = e_change_priority_4(w4, c1, iid)
    val w6 = e_change_priority_5(w5, c1, iid)
    w6
  }

  // auto_escalate: timer → pending_acceptance

  def ok_auto_escalate(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == true),
    { val t_499 = world.inc.get(iid).timers.get("reaction")  (((t_499.due != 0) and (t_499.due <= c.now)) and (t_499.fired != t_499.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_500 = personOf(levelUpTarget(c.before))
    val w501 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_500 }) }
    w501
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_502 = groupOf(levelUpTarget(c.before))
    val w503 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_502 }) }
    w503
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_504 = levelUpNumber(c.before)
    val w505 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_504 }) }
    w505
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w506 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w506
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w507 = if (not(timerDef("resolution").pausable)) {
      val w508 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w509 = { ...w508, inc: w508.inc.set(iid, { ...w508.inc.get(iid), timers: w508.inc.get(iid).timers.set("resolution", { ...w508.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w509
    } else {
      val w510 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w511 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w512 = { ...w511, inc: w511.inc.set(iid, { ...w511.inc.get(iid), timers: w511.inc.get(iid).timers.set("resolution", { ...w511.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w513 = { ...w512, inc: w512.inc.set(iid, { ...w512.inc.get(iid), timers: w512.inc.get(iid).timers.set("resolution", { ...w512.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w513
    } else w0
      w510
    }
    w507
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w514 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w515 = if (timerDef("reaction").startsOnce) {
      val w516 = ec_resumeTimer(w0, c, iid, "reaction")
      w516
    } else {
      val w517 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w518 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w519 = { ...w518, inc: w518.inc.set(iid, { ...w518.inc.get(iid), timers: w518.inc.get(iid).timers.set("reaction", { ...w518.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w520 = { ...w519, inc: w519.inc.set(iid, { ...w519.inc.get(iid), timers: w519.inc.get(iid).timers.set("reaction", { ...w519.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w520
    } else {
      val sec_521 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w522 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_521 < 0)) 0 else (c.now + (sec_521 * 1000))) }) }) }
      val w523 = { ...w522, inc: w522.inc.set(iid, { ...w522.inc.get(iid), timers: w522.inc.get(iid).timers.set("reaction", { ...w522.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w524 = { ...w523, inc: w523.inc.set(iid, { ...w523.inc.get(iid), timers: w523.inc.get(iid).timers.set("reaction", { ...w523.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w525 = { ...w524, inc: w524.inc.set(iid, { ...w524.inc.get(iid), timers: w524.inc.get(iid).timers.set("reaction", { ...w524.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w525
    }
      w517
    }
      w515
    }
    w514
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_526 = addressee(w0.inc.get(iid))
    val w527 = if (((whom_526 != "") and (whom_526 != c.actor))) w0 else w0
    w527
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
    { val t_528 = world.inc.get(iid).timers.get("reaction")  (((t_528.due != 0) and (t_528.due <= c.now)) and (t_528.fired != t_528.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_529 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w530 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_529) }) }
    val w531 = { ...w530, inc: w530.inc.set(iid, { ...w530.inc.get(iid), slaBreached: true }) }
    val w532 = groupMembersAt(incs(w0), w531.inc.get(iid), c.deadline).foldl([], (acc, x535) => acc.append(x535.id)).foldl(w531, (wf533, eId534) => {
      val w536 = { ...wf533, inc: wf533.inc.set(eId534, { ...wf533.inc.get(eId534), breaches: wf533.inc.get(eId534).breaches.append(breach_529) }) }
      val w537 = { ...w536, inc: w536.inc.set(eId534, { ...w536.inc.get(eId534), slaBreached: true }) }
      w537
    })
    w532
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w538 = if (timerDef("reaction").startsOnce) {
      val w539 = ec_pauseTimer(w0, c, iid, "reaction")
      w539
    } else {
      val w540 = if (false) {
      val w541 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w542 = { ...w541, inc: w541.inc.set(iid, { ...w541.inc.get(iid), timers: w541.inc.get(iid).timers.set("reaction", { ...w541.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w543 = { ...w542, inc: w542.inc.set(iid, { ...w542.inc.get(iid), timers: w542.inc.get(iid).timers.set("reaction", { ...w542.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w544 = { ...w543, inc: w543.inc.set(iid, { ...w543.inc.get(iid), timers: w543.inc.get(iid).timers.set("reaction", { ...w543.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w544
    } else {
      val w545 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_546 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w547 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_546) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w548 = { ...w547, inc: w547.inc.set(iid, { ...w547.inc.get(iid), timers: w547.inc.get(iid).timers.set("reaction", { ...w547.inc.get(iid).timers.get("reaction"), paused: keep_546 }) }) }
      val w549 = { ...w548, inc: w548.inc.set(iid, { ...w548.inc.get(iid), timers: w548.inc.get(iid).timers.set("reaction", { ...w548.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w550 = { ...w549, inc: w549.inc.set(iid, { ...w549.inc.get(iid), timers: w549.inc.get(iid).timers.set("reaction", { ...w549.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w550
    }
      w545
    }
      w540
    }
    w538
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_551 = settings.alerts.target
    val w552 = if (((whom_551 != "") and (whom_551 != c.actor))) w0 else w0
    w552
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
    { val t_553 = world.inc.get(iid).timers.get("reaction")  (((t_553.due != 0) and (t_553.due <= c.now)) and (t_553.fired != t_553.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_554 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w555 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_554) }) }
    val w556 = { ...w555, inc: w555.inc.set(iid, { ...w555.inc.get(iid), slaBreached: true }) }
    val w557 = groupMembersAt(incs(w0), w556.inc.get(iid), c.deadline).foldl([], (acc, x560) => acc.append(x560.id)).foldl(w556, (wf558, eId559) => {
      val w561 = { ...wf558, inc: wf558.inc.set(eId559, { ...wf558.inc.get(eId559), breaches: wf558.inc.get(eId559).breaches.append(breach_554) }) }
      val w562 = { ...w561, inc: w561.inc.set(eId559, { ...w561.inc.get(eId559), slaBreached: true }) }
      w562
    })
    w557
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w563 = if (timerDef("reaction").startsOnce) {
      val w564 = ec_pauseTimer(w0, c, iid, "reaction")
      w564
    } else {
      val w565 = if (false) {
      val w566 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w567 = { ...w566, inc: w566.inc.set(iid, { ...w566.inc.get(iid), timers: w566.inc.get(iid).timers.set("reaction", { ...w566.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w568 = { ...w567, inc: w567.inc.set(iid, { ...w567.inc.get(iid), timers: w567.inc.get(iid).timers.set("reaction", { ...w567.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w569 = { ...w568, inc: w568.inc.set(iid, { ...w568.inc.get(iid), timers: w568.inc.get(iid).timers.set("reaction", { ...w568.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w569
    } else {
      val w570 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_571 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w572 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_571) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w573 = { ...w572, inc: w572.inc.set(iid, { ...w572.inc.get(iid), timers: w572.inc.get(iid).timers.set("reaction", { ...w572.inc.get(iid).timers.get("reaction"), paused: keep_571 }) }) }
      val w574 = { ...w573, inc: w573.inc.set(iid, { ...w573.inc.get(iid), timers: w573.inc.get(iid).timers.set("reaction", { ...w573.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w575 = { ...w574, inc: w574.inc.set(iid, { ...w574.inc.get(iid), timers: w574.inc.get(iid).timers.set("reaction", { ...w574.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w575
    }
      w570
    }
      w565
    }
    w563
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_576 = settings.alerts.target
    val w577 = if (((whom_576 != "") and (whom_576 != c.actor))) w0 else w0
    w577
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
    { val t_578 = world.inc.get(iid).timers.get("resolution")  (((t_578.due != 0) and (t_578.due <= c.now)) and (t_578.fired != t_578.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_579 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w580 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_579) }) }
    val w581 = { ...w580, inc: w580.inc.set(iid, { ...w580.inc.get(iid), slaBreached: true }) }
    val w582 = groupMembersAt(incs(w0), w581.inc.get(iid), c.deadline).foldl([], (acc, x585) => acc.append(x585.id)).foldl(w581, (wf583, eId584) => {
      val w586 = { ...wf583, inc: wf583.inc.set(eId584, { ...wf583.inc.get(eId584), breaches: wf583.inc.get(eId584).breaches.append(breach_579) }) }
      val w587 = { ...w586, inc: w586.inc.set(eId584, { ...w586.inc.get(eId584), slaBreached: true }) }
      w587
    })
    w582
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_588 = settings.alerts.target
    val w589 = if (((whom_588 != "") and (whom_588 != c.actor))) w0 else w0
    w589
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
    { val t_590 = world.inc.get(iid).timers.get("resolution")  (((t_590.due != 0) and (t_590.due <= c.now)) and (t_590.fired != t_590.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_591 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w592 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_591) }) }
    val w593 = { ...w592, inc: w592.inc.set(iid, { ...w592.inc.get(iid), slaBreached: true }) }
    val w594 = groupMembersAt(incs(w0), w593.inc.get(iid), c.deadline).foldl([], (acc, x597) => acc.append(x597.id)).foldl(w593, (wf595, eId596) => {
      val w598 = { ...wf595, inc: wf595.inc.set(eId596, { ...wf595.inc.get(eId596), breaches: wf595.inc.get(eId596).breaches.append(breach_591) }) }
      val w599 = { ...w598, inc: w598.inc.set(eId596, { ...w598.inc.get(eId596), slaBreached: true }) }
      w599
    })
    w594
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_600 = personOf(levelUpTarget(c.before))
    val w601 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_600 }) }
    w601
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_602 = groupOf(levelUpTarget(c.before))
    val w603 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_602 }) }
    w603
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_604 = levelUpNumber(c.before)
    val w605 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_604 }) }
    w605
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w606 = if (not(timerDef("resolution").pausable)) {
      val w607 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w608 = { ...w607, inc: w607.inc.set(iid, { ...w607.inc.get(iid), timers: w607.inc.get(iid).timers.set("resolution", { ...w607.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w608
    } else {
      val w609 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w610 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w611 = { ...w610, inc: w610.inc.set(iid, { ...w610.inc.get(iid), timers: w610.inc.get(iid).timers.set("resolution", { ...w610.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w612 = { ...w611, inc: w611.inc.set(iid, { ...w611.inc.get(iid), timers: w611.inc.get(iid).timers.set("resolution", { ...w611.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w612
    } else w0
      w609
    }
    w606
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w613 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w614 = if (timerDef("reaction").startsOnce) {
      val w615 = ec_resumeTimer(w0, c, iid, "reaction")
      w615
    } else {
      val w616 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w617 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w618 = { ...w617, inc: w617.inc.set(iid, { ...w617.inc.get(iid), timers: w617.inc.get(iid).timers.set("reaction", { ...w617.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w619 = { ...w618, inc: w618.inc.set(iid, { ...w618.inc.get(iid), timers: w618.inc.get(iid).timers.set("reaction", { ...w618.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w619
    } else {
      val sec_620 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w621 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_620 < 0)) 0 else (c.now + (sec_620 * 1000))) }) }) }
      val w622 = { ...w621, inc: w621.inc.set(iid, { ...w621.inc.get(iid), timers: w621.inc.get(iid).timers.set("reaction", { ...w621.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w623 = { ...w622, inc: w622.inc.set(iid, { ...w622.inc.get(iid), timers: w622.inc.get(iid).timers.set("reaction", { ...w622.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w624 = { ...w623, inc: w623.inc.set(iid, { ...w623.inc.get(iid), timers: w623.inc.get(iid).timers.set("reaction", { ...w623.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w624
    }
      w616
    }
      w614
    }
    w613
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_625 = c.before.owner
    val w626 = if (((whom_625 != "") and (whom_625 != c.actor))) w0 else w0
    w626
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_627 = addressee(w0.inc.get(iid))
    val w628 = if (((whom_627 != "") and (whom_627 != c.actor))) w0 else w0
    w628
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
    { val t_629 = world.inc.get(iid).timers.get("resolution")  (((t_629.due != 0) and (t_629.due <= c.now)) and (t_629.fired != t_629.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_630 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w631 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_630) }) }
    val w632 = { ...w631, inc: w631.inc.set(iid, { ...w631.inc.get(iid), slaBreached: true }) }
    val w633 = groupMembersAt(incs(w0), w632.inc.get(iid), c.deadline).foldl([], (acc, x636) => acc.append(x636.id)).foldl(w632, (wf634, eId635) => {
      val w637 = { ...wf634, inc: wf634.inc.set(eId635, { ...wf634.inc.get(eId635), breaches: wf634.inc.get(eId635).breaches.append(breach_630) }) }
      val w638 = { ...w637, inc: w637.inc.set(eId635, { ...w637.inc.get(eId635), slaBreached: true }) }
      w638
    })
    w633
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_639 = settings.alerts.target
    val w640 = if (((whom_639 != "") and (whom_639 != c.actor))) w0 else w0
    w640
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
    { val t_641 = world.inc.get(iid).timers.get("hold")  (((t_641.due != 0) and (t_641.due <= c.now)) and (t_641.fired != t_641.due)) },
    not(["break", "no_link"].foldl(false, (acc, y642) => acc or y642 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_643 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w644 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_643) }) }
    val w645 = { ...w644, inc: w644.inc.set(iid, { ...w644.inc.get(iid), slaBreached: true }) }
    val w646 = groupMembersAt(incs(w0), w645.inc.get(iid), c.deadline).foldl([], (acc, x649) => acc.append(x649.id)).foldl(w645, (wf647, eId648) => {
      val w650 = { ...wf647, inc: wf647.inc.set(eId648, { ...wf647.inc.get(eId648), breaches: wf647.inc.get(eId648).breaches.append(breach_643) }) }
      val w651 = { ...w650, inc: w650.inc.set(eId648, { ...w650.inc.get(eId648), slaBreached: true }) }
      w651
    })
    w646
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_652 = settings.alerts.target
    val w653 = if (((whom_652 != "") and (whom_652 != c.actor))) w0 else w0
    w653
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
    { val t_654 = world.inc.get(iid).timers.get("hold")  (((t_654.due != 0) and (t_654.due <= c.now)) and (t_654.fired != t_654.due)) },
    ["break"].foldl(false, (acc, y655) => acc or y655 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_656 = ""
    val w657 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_656 }) }
    w657
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w658 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w658
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w659 = if (timerDef("hold").startsOnce) {
      val w660 = ec_pauseTimer(w0, c, iid, "hold")
      w660
    } else {
      val w661 = if (false) {
      val w662 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w663 = { ...w662, inc: w662.inc.set(iid, { ...w662.inc.get(iid), timers: w662.inc.get(iid).timers.set("hold", { ...w662.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w664 = { ...w663, inc: w663.inc.set(iid, { ...w663.inc.get(iid), timers: w663.inc.get(iid).timers.set("hold", { ...w663.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w665 = { ...w664, inc: w664.inc.set(iid, { ...w664.inc.get(iid), timers: w664.inc.get(iid).timers.set("hold", { ...w664.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w665
    } else {
      val w666 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_667 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w668 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_667) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w669 = { ...w668, inc: w668.inc.set(iid, { ...w668.inc.get(iid), timers: w668.inc.get(iid).timers.set("hold", { ...w668.inc.get(iid).timers.get("hold"), paused: keep_667 }) }) }
      val w670 = { ...w669, inc: w669.inc.set(iid, { ...w669.inc.get(iid), timers: w669.inc.get(iid).timers.set("hold", { ...w669.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w671 = { ...w670, inc: w670.inc.set(iid, { ...w670.inc.get(iid), timers: w670.inc.get(iid).timers.set("hold", { ...w670.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w671
    }
      w666
    }
      w661
    }
    w659
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w672 = if (not(timerDef("resolution").pausable)) {
      val w673 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w674 = { ...w673, inc: w673.inc.set(iid, { ...w673.inc.get(iid), timers: w673.inc.get(iid).timers.set("resolution", { ...w673.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w674
    } else {
      val w675 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w676 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w677 = { ...w676, inc: w676.inc.set(iid, { ...w676.inc.get(iid), timers: w676.inc.get(iid).timers.set("resolution", { ...w676.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w678 = { ...w677, inc: w677.inc.set(iid, { ...w677.inc.get(iid), timers: w677.inc.get(iid).timers.set("resolution", { ...w677.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w678
    } else w0
      w675
    }
    w672
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w679 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w680 = if (timerDef("reaction").startsOnce) {
      val w681 = ec_resumeTimer(w0, c, iid, "reaction")
      w681
    } else {
      val w682 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w683 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w684 = { ...w683, inc: w683.inc.set(iid, { ...w683.inc.get(iid), timers: w683.inc.get(iid).timers.set("reaction", { ...w683.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w685 = { ...w684, inc: w684.inc.set(iid, { ...w684.inc.get(iid), timers: w684.inc.get(iid).timers.set("reaction", { ...w684.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w685
    } else {
      val sec_686 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w687 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_686 < 0)) 0 else (c.now + (sec_686 * 1000))) }) }) }
      val w688 = { ...w687, inc: w687.inc.set(iid, { ...w687.inc.get(iid), timers: w687.inc.get(iid).timers.set("reaction", { ...w687.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w689 = { ...w688, inc: w688.inc.set(iid, { ...w688.inc.get(iid), timers: w688.inc.get(iid).timers.set("reaction", { ...w688.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w690 = { ...w689, inc: w689.inc.set(iid, { ...w689.inc.get(iid), timers: w689.inc.get(iid).timers.set("reaction", { ...w689.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w690
    }
      w682
    }
      w680
    }
    w679
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
    val reason_691 = "break"
    val w692 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_691 }) }
    w692
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
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

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w700 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w701 = if (timerDef("hold").startsOnce) {
      val w702 = ec_resumeTimer(w0, c, iid, "hold")
      w702
    } else {
      val w703 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w704 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w705 = { ...w704, inc: w704.inc.set(iid, { ...w704.inc.get(iid), timers: w704.inc.get(iid).timers.set("hold", { ...w704.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w706 = { ...w705, inc: w705.inc.set(iid, { ...w705.inc.get(iid), timers: w705.inc.get(iid).timers.set("hold", { ...w705.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w706
    } else {
      val sec_707 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w708 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_707 < 0)) 0 else (c.now + (sec_707 * 1000))) }) }) }
      val w709 = { ...w708, inc: w708.inc.set(iid, { ...w708.inc.get(iid), timers: w708.inc.get(iid).timers.set("hold", { ...w708.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w710 = { ...w709, inc: w709.inc.set(iid, { ...w709.inc.get(iid), timers: w709.inc.get(iid).timers.set("hold", { ...w709.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w711 = { ...w710, inc: w710.inc.set(iid, { ...w710.inc.get(iid), timers: w710.inc.get(iid).timers.set("hold", { ...w710.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w711
    }
      w703
    }
      w701
    }
    w700
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
    val reason_712 = "no_link"
    val w713 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_712 }) }
    w713
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
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

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w721 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w722 = if (timerDef("hold").startsOnce) {
      val w723 = ec_resumeTimer(w0, c, iid, "hold")
      w723
    } else {
      val w724 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w725 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w726 = { ...w725, inc: w725.inc.set(iid, { ...w725.inc.get(iid), timers: w725.inc.get(iid).timers.set("hold", { ...w725.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w727 = { ...w726, inc: w726.inc.set(iid, { ...w726.inc.get(iid), timers: w726.inc.get(iid).timers.set("hold", { ...w726.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w727
    } else {
      val sec_728 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w729 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_728 < 0)) 0 else (c.now + (sec_728 * 1000))) }) }) }
      val w730 = { ...w729, inc: w729.inc.set(iid, { ...w729.inc.get(iid), timers: w729.inc.get(iid).timers.set("hold", { ...w729.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w731 = { ...w730, inc: w730.inc.set(iid, { ...w730.inc.get(iid), timers: w730.inc.get(iid).timers.set("hold", { ...w730.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w732 = { ...w731, inc: w731.inc.set(iid, { ...w731.inc.get(iid), timers: w731.inc.get(iid).timers.set("hold", { ...w731.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w732
    }
      w724
    }
      w722
    }
    w721
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_733 = settings.alerts.target
    val w734 = if (((whom_733 != "") and (whom_733 != c.actor))) w0 else w0
    w734
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
    ["break", "no_link"].foldl(false, (acc, y735) => acc or y735 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_736 = ""
    val w737 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_736 }) }
    w737
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w738 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w738
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w739 = if (timerDef("hold").startsOnce) {
      val w740 = ec_pauseTimer(w0, c, iid, "hold")
      w740
    } else {
      val w741 = if (false) {
      val w742 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w743 = { ...w742, inc: w742.inc.set(iid, { ...w742.inc.get(iid), timers: w742.inc.get(iid).timers.set("hold", { ...w742.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w744 = { ...w743, inc: w743.inc.set(iid, { ...w743.inc.get(iid), timers: w743.inc.get(iid).timers.set("hold", { ...w743.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w745 = { ...w744, inc: w744.inc.set(iid, { ...w744.inc.get(iid), timers: w744.inc.get(iid).timers.set("hold", { ...w744.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w745
    } else {
      val w746 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_747 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w748 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_747) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w749 = { ...w748, inc: w748.inc.set(iid, { ...w748.inc.get(iid), timers: w748.inc.get(iid).timers.set("hold", { ...w748.inc.get(iid).timers.get("hold"), paused: keep_747 }) }) }
      val w750 = { ...w749, inc: w749.inc.set(iid, { ...w749.inc.get(iid), timers: w749.inc.get(iid).timers.set("hold", { ...w749.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w751 = { ...w750, inc: w750.inc.set(iid, { ...w750.inc.get(iid), timers: w750.inc.get(iid).timers.set("hold", { ...w750.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w751
    }
      w746
    }
      w741
    }
    w739
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
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

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w759 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w760 = if (timerDef("reaction").startsOnce) {
      val w761 = ec_resumeTimer(w0, c, iid, "reaction")
      w761
    } else {
      val w762 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w763 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w764 = { ...w763, inc: w763.inc.set(iid, { ...w763.inc.get(iid), timers: w763.inc.get(iid).timers.set("reaction", { ...w763.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w765 = { ...w764, inc: w764.inc.set(iid, { ...w764.inc.get(iid), timers: w764.inc.get(iid).timers.set("reaction", { ...w764.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w765
    } else {
      val sec_766 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w767 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_766 < 0)) 0 else (c.now + (sec_766 * 1000))) }) }) }
      val w768 = { ...w767, inc: w767.inc.set(iid, { ...w767.inc.get(iid), timers: w767.inc.get(iid).timers.set("reaction", { ...w767.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w769 = { ...w768, inc: w768.inc.set(iid, { ...w768.inc.get(iid), timers: w768.inc.get(iid).timers.set("reaction", { ...w768.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w770 = { ...w769, inc: w769.inc.set(iid, { ...w769.inc.get(iid), timers: w769.inc.get(iid).timers.set("reaction", { ...w769.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w770
    }
      w762
    }
      w760
    }
    w759
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
    { val t_771 = world.inc.get(iid).timers.get("hold")  (((t_771.due != 0) and (t_771.due <= c.now)) and (t_771.fired != t_771.due)) },
    ["no_link"].foldl(false, (acc, y772) => acc or y772 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_773 = ""
    val w774 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_773 }) }
    w774
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w775 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w775
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w776 = if (timerDef("hold").startsOnce) {
      val w777 = ec_pauseTimer(w0, c, iid, "hold")
      w777
    } else {
      val w778 = if (false) {
      val w779 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w780 = { ...w779, inc: w779.inc.set(iid, { ...w779.inc.get(iid), timers: w779.inc.get(iid).timers.set("hold", { ...w779.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w781 = { ...w780, inc: w780.inc.set(iid, { ...w780.inc.get(iid), timers: w780.inc.get(iid).timers.set("hold", { ...w780.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w782 = { ...w781, inc: w781.inc.set(iid, { ...w781.inc.get(iid), timers: w781.inc.get(iid).timers.set("hold", { ...w781.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w782
    } else {
      val w783 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_784 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w785 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_784) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w786 = { ...w785, inc: w785.inc.set(iid, { ...w785.inc.get(iid), timers: w785.inc.get(iid).timers.set("hold", { ...w785.inc.get(iid).timers.get("hold"), paused: keep_784 }) }) }
      val w787 = { ...w786, inc: w786.inc.set(iid, { ...w786.inc.get(iid), timers: w786.inc.get(iid).timers.set("hold", { ...w786.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w788 = { ...w787, inc: w787.inc.set(iid, { ...w787.inc.get(iid), timers: w787.inc.get(iid).timers.set("hold", { ...w787.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w788
    }
      w783
    }
      w778
    }
    w776
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w789 = if (not(timerDef("resolution").pausable)) {
      val w790 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w791 = { ...w790, inc: w790.inc.set(iid, { ...w790.inc.get(iid), timers: w790.inc.get(iid).timers.set("resolution", { ...w790.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w791
    } else {
      val w792 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w793 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w794 = { ...w793, inc: w793.inc.set(iid, { ...w793.inc.get(iid), timers: w793.inc.get(iid).timers.set("resolution", { ...w793.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w795 = { ...w794, inc: w794.inc.set(iid, { ...w794.inc.get(iid), timers: w794.inc.get(iid).timers.set("resolution", { ...w794.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w795
    } else w0
      w792
    }
    w789
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w796 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w797 = if (timerDef("reaction").startsOnce) {
      val w798 = ec_resumeTimer(w0, c, iid, "reaction")
      w798
    } else {
      val w799 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w800 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w801 = { ...w800, inc: w800.inc.set(iid, { ...w800.inc.get(iid), timers: w800.inc.get(iid).timers.set("reaction", { ...w800.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w802 = { ...w801, inc: w801.inc.set(iid, { ...w801.inc.get(iid), timers: w801.inc.get(iid).timers.set("reaction", { ...w801.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w802
    } else {
      val sec_803 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w804 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_803 < 0)) 0 else (c.now + (sec_803 * 1000))) }) }) }
      val w805 = { ...w804, inc: w804.inc.set(iid, { ...w804.inc.get(iid), timers: w804.inc.get(iid).timers.set("reaction", { ...w804.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w806 = { ...w805, inc: w805.inc.set(iid, { ...w805.inc.get(iid), timers: w805.inc.get(iid).timers.set("reaction", { ...w805.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w807 = { ...w806, inc: w806.inc.set(iid, { ...w806.inc.get(iid), timers: w806.inc.get(iid).timers.set("reaction", { ...w806.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w807
    }
      w799
    }
      w797
    }
    w796
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
    val group_808 = dutyGroupOf(w0.inc.get(iid).owner)
    val w809 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_808 }) }
    w809
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_810 = ""
    val w811 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_810 }) }
    w811
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_812 = addressee(w0.inc.get(iid))
    val w813 = if (((whom_812 != "") and (whom_812 != c.actor))) w0 else w0
    w813
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
    val who_814 = ""
    val w815 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_814 }) }
    w815
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
    val who_816 = ""
    val w817 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_816 }) }
    w817
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w818 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w818
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w819 = if (timerDef("hold").startsOnce) {
      val w820 = ec_pauseTimer(w0, c, iid, "hold")
      w820
    } else {
      val w821 = if (false) {
      val w822 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w823 = { ...w822, inc: w822.inc.set(iid, { ...w822.inc.get(iid), timers: w822.inc.get(iid).timers.set("hold", { ...w822.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w824 = { ...w823, inc: w823.inc.set(iid, { ...w823.inc.get(iid), timers: w823.inc.get(iid).timers.set("hold", { ...w823.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w825 = { ...w824, inc: w824.inc.set(iid, { ...w824.inc.get(iid), timers: w824.inc.get(iid).timers.set("hold", { ...w824.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w825
    } else {
      val w826 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_827 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w828 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_827) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w829 = { ...w828, inc: w828.inc.set(iid, { ...w828.inc.get(iid), timers: w828.inc.get(iid).timers.set("hold", { ...w828.inc.get(iid).timers.get("hold"), paused: keep_827 }) }) }
      val w830 = { ...w829, inc: w829.inc.set(iid, { ...w829.inc.get(iid), timers: w829.inc.get(iid).timers.set("hold", { ...w829.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w831 = { ...w830, inc: w830.inc.set(iid, { ...w830.inc.get(iid), timers: w830.inc.get(iid).timers.set("hold", { ...w830.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w831
    }
      w826
    }
      w821
    }
    w819
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w832 = if (not(timerDef("resolution").pausable)) {
      val w833 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w834 = { ...w833, inc: w833.inc.set(iid, { ...w833.inc.get(iid), timers: w833.inc.get(iid).timers.set("resolution", { ...w833.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w834
    } else {
      val w835 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w836 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w837 = { ...w836, inc: w836.inc.set(iid, { ...w836.inc.get(iid), timers: w836.inc.get(iid).timers.set("resolution", { ...w836.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w838 = { ...w837, inc: w837.inc.set(iid, { ...w837.inc.get(iid), timers: w837.inc.get(iid).timers.set("resolution", { ...w837.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w838
    } else w0
      w835
    }
    w832
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w839 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w840 = if (timerDef("reaction").startsOnce) {
      val w841 = ec_resumeTimer(w0, c, iid, "reaction")
      w841
    } else {
      val w842 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w843 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w844 = { ...w843, inc: w843.inc.set(iid, { ...w843.inc.get(iid), timers: w843.inc.get(iid).timers.set("reaction", { ...w843.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w845 = { ...w844, inc: w844.inc.set(iid, { ...w844.inc.get(iid), timers: w844.inc.get(iid).timers.set("reaction", { ...w844.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w845
    } else {
      val sec_846 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w847 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_846 < 0)) 0 else (c.now + (sec_846 * 1000))) }) }) }
      val w848 = { ...w847, inc: w847.inc.set(iid, { ...w847.inc.get(iid), timers: w847.inc.get(iid).timers.set("reaction", { ...w847.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w849 = { ...w848, inc: w848.inc.set(iid, { ...w848.inc.get(iid), timers: w848.inc.get(iid).timers.set("reaction", { ...w848.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w850 = { ...w849, inc: w849.inc.set(iid, { ...w849.inc.get(iid), timers: w849.inc.get(iid).timers.set("reaction", { ...w849.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w850
    }
      w842
    }
      w840
    }
    w839
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
    val who_851 = ""
    val w852 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_851 }) }
    w852
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_853 = ""
    val w854 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_853 }) }
    w854
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w855 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w855
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w856 = if (timerDef("hold").startsOnce) {
      val w857 = ec_pauseTimer(w0, c, iid, "hold")
      w857
    } else {
      val w858 = if (false) {
      val w859 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w860 = { ...w859, inc: w859.inc.set(iid, { ...w859.inc.get(iid), timers: w859.inc.get(iid).timers.set("hold", { ...w859.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w861 = { ...w860, inc: w860.inc.set(iid, { ...w860.inc.get(iid), timers: w860.inc.get(iid).timers.set("hold", { ...w860.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w862 = { ...w861, inc: w861.inc.set(iid, { ...w861.inc.get(iid), timers: w861.inc.get(iid).timers.set("hold", { ...w861.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w862
    } else {
      val w863 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_864 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w865 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_864) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w866 = { ...w865, inc: w865.inc.set(iid, { ...w865.inc.get(iid), timers: w865.inc.get(iid).timers.set("hold", { ...w865.inc.get(iid).timers.get("hold"), paused: keep_864 }) }) }
      val w867 = { ...w866, inc: w866.inc.set(iid, { ...w866.inc.get(iid), timers: w866.inc.get(iid).timers.set("hold", { ...w866.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w868 = { ...w867, inc: w867.inc.set(iid, { ...w867.inc.get(iid), timers: w867.inc.get(iid).timers.set("hold", { ...w867.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w868
    }
      w863
    }
      w858
    }
    w856
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w869 = if (not(timerDef("resolution").pausable)) {
      val w870 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w871 = { ...w870, inc: w870.inc.set(iid, { ...w870.inc.get(iid), timers: w870.inc.get(iid).timers.set("resolution", { ...w870.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w871
    } else {
      val w872 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w873 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w874 = { ...w873, inc: w873.inc.set(iid, { ...w873.inc.get(iid), timers: w873.inc.get(iid).timers.set("resolution", { ...w873.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w875 = { ...w874, inc: w874.inc.set(iid, { ...w874.inc.get(iid), timers: w874.inc.get(iid).timers.set("resolution", { ...w874.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w875
    } else w0
      w872
    }
    w869
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w876 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w877 = if (timerDef("reaction").startsOnce) {
      val w878 = ec_resumeTimer(w0, c, iid, "reaction")
      w878
    } else {
      val w879 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w880 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w881 = { ...w880, inc: w880.inc.set(iid, { ...w880.inc.get(iid), timers: w880.inc.get(iid).timers.set("reaction", { ...w880.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w882 = { ...w881, inc: w881.inc.set(iid, { ...w881.inc.get(iid), timers: w881.inc.get(iid).timers.set("reaction", { ...w881.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w882
    } else {
      val sec_883 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w884 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_883 < 0)) 0 else (c.now + (sec_883 * 1000))) }) }) }
      val w885 = { ...w884, inc: w884.inc.set(iid, { ...w884.inc.get(iid), timers: w884.inc.get(iid).timers.set("reaction", { ...w884.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w886 = { ...w885, inc: w885.inc.set(iid, { ...w885.inc.get(iid), timers: w885.inc.get(iid).timers.set("reaction", { ...w885.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w887 = { ...w886, inc: w886.inc.set(iid, { ...w886.inc.get(iid), timers: w886.inc.get(iid).timers.set("reaction", { ...w886.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w887
    }
      w879
    }
      w877
    }
    w876
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_888 = settings.alerts.target
    val w889 = if (((whom_888 != "") and (whom_888 != c.actor))) w0 else w0
    w889
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
    val who_890 = ""
    val w891 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_890 }) }
    w891
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_892 = ""
    val w893 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_892 }) }
    w893
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w894 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w895 = if (timerDef("reaction").startsOnce) {
      val w896 = ec_resumeTimer(w0, c, iid, "reaction")
      w896
    } else {
      val w897 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w898 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w899 = { ...w898, inc: w898.inc.set(iid, { ...w898.inc.get(iid), timers: w898.inc.get(iid).timers.set("reaction", { ...w898.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w900 = { ...w899, inc: w899.inc.set(iid, { ...w899.inc.get(iid), timers: w899.inc.get(iid).timers.set("reaction", { ...w899.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w900
    } else {
      val sec_901 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w902 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_901 < 0)) 0 else (c.now + (sec_901 * 1000))) }) }) }
      val w903 = { ...w902, inc: w902.inc.set(iid, { ...w902.inc.get(iid), timers: w902.inc.get(iid).timers.set("reaction", { ...w902.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w904 = { ...w903, inc: w903.inc.set(iid, { ...w903.inc.get(iid), timers: w903.inc.get(iid).timers.set("reaction", { ...w903.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w905 = { ...w904, inc: w904.inc.set(iid, { ...w904.inc.get(iid), timers: w904.inc.get(iid).timers.set("reaction", { ...w904.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w905
    }
      w897
    }
      w895
    }
    w894
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_906 = settings.alerts.target
    val w907 = if (((whom_906 != "") and (whom_906 != c.actor))) w0 else w0
    w907
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
    not(settings.session.states.foldl(false, (acc, s_908) => acc or ((s_908.id == agentState(c.me)) and s_908.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_909 = incidentById(incs(world), c.form.primaryId)  ((((ps_909.length() > 0) and (ps_909[0].id != world.inc.get(iid).id)) and (ps_909[0].linkedTo == "")) and ((ps_909[0].state == "new") or ((ps_909[0].state == "in_progress") and (ps_909[0].owner == c.me)))) },
    { val ps_910 = incidentById(incs(world), c.form.primaryId)  ((ps_910.length() > 0) and (ps_910[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w911 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w911
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_912 = incidentById(incs(w0), c.form.primaryId)
    val w913 = if ((ps_912.length() > 0)) {
      val w914 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_921 => not(isDone(e_921))).foldl([], (acc, x917) => acc.append(x917.id)).foldl(w0, (wf915, cId916) => {
      val w918 = { ...wf915, inc: wf915.inc.set(cId916, { ...wf915.inc.get(cId916), leftGroup: { primaryId: wf915.inc.get(cId916).linkedTo, linkedAt: wf915.inc.get(cId916).linkedAt, at: c.now } }) }
      val w919 = { ...w918, inc: w918.inc.set(cId916, { ...w918.inc.get(cId916), linkedTo: ps_912[0].id }) }
      val w920 = { ...w919, inc: w919.inc.set(cId916, { ...w919.inc.get(cId916), linkedAt: c.now }) }
      w920
    })
      w914
    } else w0
    w913
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_922 = c.form.primaryId
    val w923 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_922 }) }
    val w924 = { ...w923, inc: w923.inc.set(iid, { ...w923.inc.get(iid), linkedAt: c.now }) }
    w924
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_925 = ""
    val w926 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_925 }) }
    w926
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_927 = ""
    val w928 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_927 }) }
    w928
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w929 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w929
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w930 = if (timerDef("reaction").startsOnce) {
      val w931 = ec_pauseTimer(w0, c, iid, "reaction")
      w931
    } else {
      val w932 = if (false) {
      val w933 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w934 = { ...w933, inc: w933.inc.set(iid, { ...w933.inc.get(iid), timers: w933.inc.get(iid).timers.set("reaction", { ...w933.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w935 = { ...w934, inc: w934.inc.set(iid, { ...w934.inc.get(iid), timers: w934.inc.get(iid).timers.set("reaction", { ...w934.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w936 = { ...w935, inc: w935.inc.set(iid, { ...w935.inc.get(iid), timers: w935.inc.get(iid).timers.set("reaction", { ...w935.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w936
    } else {
      val w937 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_938 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w939 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_938) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w940 = { ...w939, inc: w939.inc.set(iid, { ...w939.inc.get(iid), timers: w939.inc.get(iid).timers.set("reaction", { ...w939.inc.get(iid).timers.get("reaction"), paused: keep_938 }) }) }
      val w941 = { ...w940, inc: w940.inc.set(iid, { ...w940.inc.get(iid), timers: w940.inc.get(iid).timers.set("reaction", { ...w940.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w942 = { ...w941, inc: w941.inc.set(iid, { ...w941.inc.get(iid), timers: w941.inc.get(iid).timers.set("reaction", { ...w941.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w942
    }
      w937
    }
      w932
    }
    w930
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w943 = if (not(timerDef("resolution").pausable)) {
      val w944 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w945 = { ...w944, inc: w944.inc.set(iid, { ...w944.inc.get(iid), timers: w944.inc.get(iid).timers.set("resolution", { ...w944.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w945
    } else {
      val w946 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w947 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w948 = { ...w947, inc: w947.inc.set(iid, { ...w947.inc.get(iid), timers: w947.inc.get(iid).timers.set("resolution", { ...w947.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w949 = { ...w948, inc: w948.inc.set(iid, { ...w948.inc.get(iid), timers: w948.inc.get(iid).timers.set("resolution", { ...w948.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w949
    } else w0
      w946
    }
    w943
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_950 = incidentById(incs(w0), c.form.primaryId)
    val w951 = if (((((ps_950.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_950[0], "resolution", c.now)))) {
      val t_952 = ps_950[0].timers.get("resolution")
      val left_953 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_954 = (if ((t_952.due != 0)) (t_952.due - c.now) else (if (t_952.paused) t_952.left else (timerSec(ps_950[0], "resolution", "") * 1000)))
      val w955 = if ((left_953 < was_954)) {
      val w956 = ps_950.foldl([], (acc, x959) => acc.append(x959.id)).foldl(w0, (wf957, pId958) => {
      val w960 = if ((t_952.due != 0)) {
      val w961 = { ...wf957, inc: wf957.inc.set(pId958, { ...wf957.inc.get(pId958), timers: wf957.inc.get(pId958).timers.set("resolution", { ...wf957.inc.get(pId958).timers.get("resolution"), due: (c.now + left_953) }) }) }
      w961
    } else {
      val w962 = { ...wf957, inc: wf957.inc.set(pId958, { ...wf957.inc.get(pId958), timers: wf957.inc.get(pId958).timers.set("resolution", { ...wf957.inc.get(pId958).timers.get("resolution"), left: left_953 }) }) }
      val w963 = { ...w962, inc: w962.inc.set(pId958, { ...w962.inc.get(pId958), timers: w962.inc.get(pId958).timers.set("resolution", { ...w962.inc.get(pId958).timers.get("resolution"), paused: true }) }) }
      w963
    }
      w960
    })
      w956
    } else w0
      w955
    } else w0
    w951
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w964 = if (timerDef("hold").startsOnce) {
      val w965 = ec_pauseTimer(w0, c, iid, "hold")
      w965
    } else {
      val w966 = if (false) {
      val w967 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w968 = { ...w967, inc: w967.inc.set(iid, { ...w967.inc.get(iid), timers: w967.inc.get(iid).timers.set("hold", { ...w967.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w969 = { ...w968, inc: w968.inc.set(iid, { ...w968.inc.get(iid), timers: w968.inc.get(iid).timers.set("hold", { ...w968.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w970 = { ...w969, inc: w969.inc.set(iid, { ...w969.inc.get(iid), timers: w969.inc.get(iid).timers.set("hold", { ...w969.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w970
    } else {
      val w971 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_972 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w973 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_972) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w974 = { ...w973, inc: w973.inc.set(iid, { ...w973.inc.get(iid), timers: w973.inc.get(iid).timers.set("hold", { ...w973.inc.get(iid).timers.get("hold"), paused: keep_972 }) }) }
      val w975 = { ...w974, inc: w974.inc.set(iid, { ...w974.inc.get(iid), timers: w974.inc.get(iid).timers.set("hold", { ...w974.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w976 = { ...w975, inc: w975.inc.set(iid, { ...w975.inc.get(iid), timers: w975.inc.get(iid).timers.set("hold", { ...w975.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w976
    }
      w971
    }
      w966
    }
    w964
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
    not(settings.session.states.foldl(false, (acc, s_977) => acc or ((s_977.id == agentState(c.me)) and s_977.readOnly))),
    { val ps_978 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_978.length() > 0) and ((ownership(c.me, ps_978[0]) == "owner") or unowned(ps_978[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_979 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w980 = if (((ps_979.length() > 0) and (leftOf(ps_979[0], "resolution", c.now) >= 0))) {
      val w981 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w982 = { ...w981, inc: w981.inc.set(iid, { ...w981.inc.get(iid), timers: w981.inc.get(iid).timers.set("resolution", { ...w981.inc.get(iid).timers.get("resolution"), left: leftOf(ps_979[0], "resolution", c.now) }) }) }
      val w983 = { ...w982, inc: w982.inc.set(iid, { ...w982.inc.get(iid), timers: w982.inc.get(iid).timers.set("resolution", { ...w982.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w984 = if ((leftOf(ps_979[0], "resolution", c.now) == 0)) {
      val w985 = { ...w983, inc: w983.inc.set(iid, { ...w983.inc.get(iid), timers: w983.inc.get(iid).timers.set("resolution", { ...w983.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_979[0], "resolution", c.now)) ps_979[0].timers.get("resolution").fired else ps_979[0].timers.get("resolution").due) }) }) }
      w985
    } else w983
      w984
    } else w0
    w980
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w986 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_987 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w988 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w989 = { ...w988, inc: w988.inc.set(iid, { ...w988.inc.get(iid), linkedTo: "" }) }
      val w990 = { ...w989, inc: w989.inc.set(iid, { ...w989.inc.get(iid), linkedAt: 0 }) }
      val w991 = if (((ps_987.length() > 0) and ("" != ""))) w990 else w990
      val w992 = if (("" != "")) {
      val w993 = ps_987.foldl([], (acc, x996) => acc.append(x996.id)).foldl(w991, (wf994, pId995) => wf994)
      w993
    } else w991
      w992
    } else {
      val w997 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w998 = { ...w997, inc: w997.inc.set(iid, { ...w997.inc.get(iid), linkedAt: 0 }) }
      w998
    }
    w986
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w999 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1000 = if (timerDef("reaction").startsOnce) {
      val w1001 = ec_resumeTimer(w0, c, iid, "reaction")
      w1001
    } else {
      val w1002 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1003 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1004 = { ...w1003, inc: w1003.inc.set(iid, { ...w1003.inc.get(iid), timers: w1003.inc.get(iid).timers.set("reaction", { ...w1003.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1005 = { ...w1004, inc: w1004.inc.set(iid, { ...w1004.inc.get(iid), timers: w1004.inc.get(iid).timers.set("reaction", { ...w1004.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1005
    } else {
      val sec_1006 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w1007 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1006 < 0)) 0 else (c.now + (sec_1006 * 1000))) }) }) }
      val w1008 = { ...w1007, inc: w1007.inc.set(iid, { ...w1007.inc.get(iid), timers: w1007.inc.get(iid).timers.set("reaction", { ...w1007.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1009 = { ...w1008, inc: w1008.inc.set(iid, { ...w1008.inc.get(iid), timers: w1008.inc.get(iid).timers.set("reaction", { ...w1008.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1010 = { ...w1009, inc: w1009.inc.set(iid, { ...w1009.inc.get(iid), timers: w1009.inc.get(iid).timers.set("reaction", { ...w1009.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1010
    }
      w1002
    }
      w1000
    }
    w999
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
    { val ps_1011 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_1011.length() > 0) and isDone(ps_1011[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1012 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1013 = if ((ps_1012.length() > 0)) {
      val w1014 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_1012[0].closeResultId }) }
      val w1015 = { ...w1014, inc: w1014.inc.set(iid, { ...w1014.inc.get(iid), closeCauseId: ps_1012[0].closeCauseId }) }
      val w1016 = { ...w1015, inc: w1015.inc.set(iid, { ...w1015.inc.get(iid), closeCauseLabel: ps_1012[0].closeCauseLabel }) }
      val w1017 = { ...w1016, inc: w1016.inc.set(iid, { ...w1016.inc.get(iid), result: ps_1012[0].result }) }
      val w1018 = { ...w1017, inc: w1017.inc.set(iid, { ...w1017.inc.get(iid), closedBy: ps_1012[0].closedBy }) }
      val w1019 = { ...w1018, inc: w1018.inc.set(iid, { ...w1018.inc.get(iid), owner: ps_1012[0].closedBy }) }
      w1019
    } else w0
    w1013
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w1020 = if (not(timerDef("resolution").pausable)) {
      val w1021 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1022 = { ...w1021, inc: w1021.inc.set(iid, { ...w1021.inc.get(iid), timers: w1021.inc.get(iid).timers.set("resolution", { ...w1021.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w1022
    } else {
      val w1023 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w1024 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w1025 = { ...w1024, inc: w1024.inc.set(iid, { ...w1024.inc.get(iid), timers: w1024.inc.get(iid).timers.set("resolution", { ...w1024.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1026 = { ...w1025, inc: w1025.inc.set(iid, { ...w1025.inc.get(iid), timers: w1025.inc.get(iid).timers.set("resolution", { ...w1025.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w1026
    } else w0
      w1023
    }
    w1020
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_1027 = c.now
    val w1028 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_1027 }) }
    w1028
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {
    val w1029 = if (["false_alarm"].foldl(false, (acc, y1030) => acc or y1030 == w0.inc.get(iid).closeResultId)) {
      val w1031 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1035 => not(isDone(x_1035))).foldl([], (acc, x1034) => acc.append(x1034.id)).foldl(w0, (wf1032, sId1033) => wf1032)
      w1031
    } else w0
    w1029
  }

  def e_close_linked_5(w0: World, c: Ctx, iid: str): World = {
    val w1036 = if (["false_alarm"].foldl(false, (acc, y1037) => acc or y1037 == w0.inc.get(iid).closeResultId)) {
      val w1038 = siblingsOf(incs(w0), w0.inc.get(iid)).select(x_1045 => not(isDone(x_1045))).foldl([], (acc, x1041) => acc.append(x1041.id)).foldl(w0, (wf1039, sId1040) => {
      val lead_1042 = (if ((wf1039.inc.get(sId1040).linkedTo != "")) { val ps_1043 = incidentById(incs(w0), wf1039.inc.get(sId1040).linkedTo)  (if (((ps_1043.length() > 0) and not(isDone(ps_1043[0])))) addressee(ps_1043[0]) else "") } else addressee(wf1039.inc.get(sId1040)))
      val w1044 = if (((lead_1042 != "") and (lead_1042 != wf1039.inc.get(iid).closedBy))) wf1039 else wf1039
      w1044
    })
      w1038
    } else w0
    w1036
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
    { val ps_1046 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_1047 = (if (((ps_1046.length() > 0) and not(isDone(ps_1046[0])))) addressee(ps_1046[0]) else "")  ((who_1047 != "") and (hasAccess(who_1047, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_1048 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w1049 = if (((ps_1048.length() > 0) and (leftOf(ps_1048[0], "resolution", c.now) >= 0))) {
      val w1050 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w1051 = { ...w1050, inc: w1050.inc.set(iid, { ...w1050.inc.get(iid), timers: w1050.inc.get(iid).timers.set("resolution", { ...w1050.inc.get(iid).timers.get("resolution"), left: leftOf(ps_1048[0], "resolution", c.now) }) }) }
      val w1052 = { ...w1051, inc: w1051.inc.set(iid, { ...w1051.inc.get(iid), timers: w1051.inc.get(iid).timers.set("resolution", { ...w1051.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w1053 = if ((leftOf(ps_1048[0], "resolution", c.now) == 0)) {
      val w1054 = { ...w1052, inc: w1052.inc.set(iid, { ...w1052.inc.get(iid), timers: w1052.inc.get(iid).timers.set("resolution", { ...w1052.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_1048[0], "resolution", c.now)) ps_1048[0].timers.get("resolution").fired else ps_1048[0].timers.get("resolution").due) }) }) }
      w1054
    } else w1052
      w1053
    } else w0
    w1049
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w1055 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_1056 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w1057 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w1058 = { ...w1057, inc: w1057.inc.set(iid, { ...w1057.inc.get(iid), linkedTo: "" }) }
      val w1059 = { ...w1058, inc: w1058.inc.set(iid, { ...w1058.inc.get(iid), linkedAt: 0 }) }
      val w1060 = if (((ps_1056.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w1059 else w1059
      val w1061 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w1062 = ps_1056.foldl([], (acc, x1065) => acc.append(x1065.id)).foldl(w1060, (wf1063, pId1064) => wf1063)
      w1062
    } else w1060
      w1061
    } else {
      val w1066 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w1067 = { ...w1066, inc: w1066.inc.set(iid, { ...w1066.inc.get(iid), linkedAt: 0 }) }
      w1067
    }
    w1055
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w1068 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w1069 = if (timerDef("reaction").startsOnce) {
      val w1070 = ec_resumeTimer(w0, c, iid, "reaction")
      w1070
    } else {
      val w1071 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w1072 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w1073 = { ...w1072, inc: w1072.inc.set(iid, { ...w1072.inc.get(iid), timers: w1072.inc.get(iid).timers.set("reaction", { ...w1072.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1074 = { ...w1073, inc: w1073.inc.set(iid, { ...w1073.inc.get(iid), timers: w1073.inc.get(iid).timers.set("reaction", { ...w1073.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1074
    } else {
      val sec_1075 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w1076 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_1075 < 0)) 0 else (c.now + (sec_1075 * 1000))) }) }) }
      val w1077 = { ...w1076, inc: w1076.inc.set(iid, { ...w1076.inc.get(iid), timers: w1076.inc.get(iid).timers.set("reaction", { ...w1076.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w1078 = { ...w1077, inc: w1077.inc.set(iid, { ...w1077.inc.get(iid), timers: w1077.inc.get(iid).timers.set("reaction", { ...w1077.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w1079 = { ...w1078, inc: w1078.inc.set(iid, { ...w1078.inc.get(iid), timers: w1078.inc.get(iid).timers.set("reaction", { ...w1078.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w1079
    }
      w1071
    }
      w1069
    }
    w1068
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_1080 = settings.alerts.target
    val w1081 = if (((whom_1080 != "") and (whom_1080 != c.actor))) w0 else w0
    w1081
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
      settings.holdReasons.foldl(false, (acc, r_1082) => acc or ((r_1082.id == c.form.reasonId) and (r_1082.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_1083) => acc and (isDone(e_1083) or hasAccess(c.form.targetId, e_1083))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_1084) => acc or (i_1084.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_1085) => acc or ((i_1085.id == c.form.resultId) and stepsOk(i_1085, world.inc.get(iid)))),
    },
    c.form.causeId == "" or all {
      settings.closeResults.foldl(false, (acc, i_1086) => acc or ((i_1086.id == c.form.resultId) and (i_1086.causeCatalog != ""))),
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
    ["in_progress"].foldl(false, (acc, y1087) => acc or y1087 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_1088) => acc or ((s_1088.id == agentState(c.me)) and s_1088.readOnly))),
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
